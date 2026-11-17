shader_type spatial;
render_mode unshaded, fog_disabled;

// The room surfaces as MapSystem.bb LoadRMesh builds their brush: stage 0 is AmbientLightRoomTex (black, or 15 / 255 with
// night vision), the "_lm" lightmap is added onto it (TextureBlend 3) and the diffuse texture multiplies the result, times two
// when its rmesh type is 1 (TextureBlend 5). Blitz3D does that arithmetic on the display (gamma) values, so the textures are
// read raw (no source_color), multiplied raw and converted to linear for the output. The rmesh vertex colours do not reach
// the result when there is a lightmap (stage 0 throws them away).
uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D lightmap_tex : filter_linear_mipmap, repeat_enable;
uniform float light_energy = 1.0;
uniform bool use_lightmap = false;
uniform bool albedo_x2 = false;     // TextureBlend 5 on the diffuse texture (also on a surface with no lightmap: white stage 0, then the doubled diffuse)
uniform bool entity_brush = false; // a b3d map piece: vertex colours also reach the lightmapped result, and TextureBlend 5 doubles the unlit one
uniform bool fullbright = false;   // debug: albedo only, no lightmap, no light level
uniform vec4 tint = vec4(1.0);
global uniform float room_ambient;   // night vision lifts every lightmap by 15 / 255 (AmbientLightRooms)
#include "res://shaders/room_fog.gdshaderinc"

vec3 from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV) * tint;
	vec3 col = alb.rgb;
	if (fullbright) {
		col *= COLOR.rgb;
	} else if (use_lightmap) {
		vec3 lit = clamp(texture(lightmap_tex, UV2).rgb + vec3(room_ambient), vec3(0.0), vec3(1.0));
		if (entity_brush) {
			lit *= COLOR.rgb;
		}
		col = lit * col;
		if (albedo_x2) {
			col *= 2.0;
		}
		col *= light_energy;
	} else {
		col *= COLOR.rgb * light_energy;
		if (albedo_x2) {
			col *= 2.0;
		}
	}
	col = clamp(col, vec3(0.0), vec3(1.0));
	// The fade to the fog colour is done in linear light: measured on the original (the start room's walkway), the floor fades out over the CameraFogRange distances with this curve rather than with a fade of the display values.
	float fog = room_fog_amount(VERTEX, CAMERA_VISIBLE_LAYERS);
	ALBEDO = mix(from_srgb(col), from_srgb(room_fog_color), fog);
}
