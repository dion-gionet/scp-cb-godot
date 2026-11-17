// Models (doors, items, NPCs, props) lit like Blitz3D's fixed-function pipeline (Direct3D 7, per vertex):
//   vertex colour = clamp(brush colour * (AmbientLight + sum over the shown lights of colour * max(N.L, 0) * range / distance))
//   pixel = texture * vertex colour
// All of it is display (gamma) arithmetic, like shaders/lightmap.gdshader: the texture is read raw and the product converted
// to linear for the output. The lights and the fog are in entity_light.gdshaderinc.
#include "res://shaders/entity_light.gdshaderinc"
uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint = vec4(1.0);              // EntityColor / EntityAlpha (albedo_color)
uniform bool fullbright = false;           // EntityFX 1
uniform bool use_vertex_color = false;
uniform float alpha_scissor = 0.5;

varying vec3 lit;

vec3 from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	if (fullbright) {
		lit = tint.rgb;
	} else {
		vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 normal = MODEL_NORMAL_MATRIX * NORMAL;
		float size = length(normal);
		vec3 sum = size > 0.0001 ? entity_light_sum(at, normal / size) : entity_ambient;
		lit = clamp(sum * tint.rgb, vec3(0.0), vec3(1.0));
	}
	if (use_vertex_color) {
		lit *= COLOR.rgb;
	}
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	vec3 col = clamp(alb.rgb * lit, vec3(0.0), vec3(1.0));
	ALBEDO = mix(from_srgb(col), from_srgb(room_fog_color), room_fog_amount(VERTEX, CAMERA_VISIBLE_LAYERS));
#ifdef ENTITY_ALPHA
	ALPHA = alb.a * tint.a;
#endif
#ifdef ENTITY_SCISSOR
	ALPHA = alb.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif
}
