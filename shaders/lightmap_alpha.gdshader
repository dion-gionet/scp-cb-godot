shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_draw_never, fog_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D lightmap_tex : filter_linear_mipmap, repeat_enable;
uniform float light_energy = 1.0;
uniform bool use_lightmap = false;
uniform bool albedo_x2 = false;     // TextureBlend 5
uniform bool fullbright = false;   // debug: albedo only, no lightmap, no light level
uniform vec4 tint = vec4(1.0);
global uniform float room_ambient;
#include "res://shaders/room_fog.gdshaderinc"

// Blitz blends in gamma (sRGB) space and Godot in linear space, which makes a white, mostly clear glass pane much
// brighter than the original. The pane does not read the screen (Godot copies it once, before any translucent object, so a
// pane that read it would wipe out the decals and sprites behind it): it uses the hardware blend, premultiplied, with the
// two terms converted so that the result matches the gamma blend: what is behind is dimmed by (1 - a) in display values,
// (1 - a)^2.2 in linear ones, and the pane's own light is added as a linear value (the textures are read raw, see
// lightmap.gdshader).
vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), c));
}

vec3 from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV) * tint * COLOR;
	vec3 col = alb.rgb;
	if (use_lightmap && !fullbright) {
		col *= texture(lightmap_tex, UV2).rgb + vec3(room_ambient);
	}
	if (albedo_x2) {
		col *= 2.0;
	}
	vec3 lit = fullbright ? col : col * light_energy;
	float fog = room_fog_amount(VERTEX, CAMERA_VISIBLE_LAYERS);
	// the fog fade in linear light, as in lightmap.gdshader
	lit = to_srgb(mix(from_srgb(clamp(lit, vec3(0.0), vec3(1.0))), from_srgb(room_fog_color), fog));
	float a = clamp(alb.a, 0.0, 1.0);
	ALBEDO = from_srgb(lit * a);
	ALPHA = 1.0 - pow(1.0 - a, 2.2);
}
