// Blitz3D blends in gamma (sRGB) space and Godot in linear space, which makes translucent pictures too
// bright (mix) and additive ones too dim. These unlit quads read the screen and blend by hand in sRGB.
// The conversions use the exact sRGB curves, matching the ones the texture sampler and the display use: a 2.2 power
// lifts the darkest texels (an edge value of 5 / 255 came back as 11 / 255), which drew the squares around the light glows.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec4 color : source_color = vec4(1.0);
uniform bool additive = false;
uniform bool multiply = false;           // EntityBlend 2: the picture's raw value times what is behind it
uniform bool billboard = false;
uniform vec2 uv_offset = vec2(0.0);      // PositionTexture: the picture slides (the tesla gate's arc)
// EntityFX 0 (the decals): the picture is lit like a model, per vertex, by AmbientLight and the shown lights
uniform bool entity_lit = false;
#include "res://shaders/entity_light.gdshaderinc"

varying vec3 lit;

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), c));
}

vec3 from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

#include "res://shaders/display_mix.gdshaderinc"

void vertex() {
	lit = vec3(1.0);
	if (entity_lit) {
		lit = clamp(entity_light_sum((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(MODEL_NORMAL_MATRIX * NORMAL)), vec3(0.0), vec3(1.0));
	}
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec4 src = texture(tex, UV + uv_offset) * color;
	// the screen copy predates the transparent pass, so a see-through texel would erase the decals and sprites already drawn there
	if (src.a <= 0.003 && !additive && !multiply) {
		discard;
	}
	vec3 behind_linear = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 behind = to_srgb(behind_linear);
	// the picture's own raw value: the product of two raw values is what Blitz multiplies
	vec3 top = to_srgb(texture(tex, UV + uv_offset).rgb) * to_srgb(color.rgb) * lit;
#ifdef ROOM_FOG
	// the picture's own colour is fogged like the rooms', never what is behind it: that was fogged when it was drawn, and
	// fogging the blended result again left a darker square round every decal
	top = to_srgb(mix(from_srgb(clamp(top, vec3(0.0), vec3(1.0))), from_srgb(room_fog_color), room_fog_amount(VERTEX, CAMERA_VISIBLE_LAYERS)));
#endif
	if (additive || multiply) {
		ALBEDO = from_srgb(additive ? min(behind + top * src.a, vec3(1.0)) : behind * top);
		ALPHA = 1.0;
	} else {
		float cover;
		vec3 albedo;
		display_mix(behind_linear, top, src.a, albedo, cover);
		ALBEDO = albedo;
		ALPHA = cover;
	}
}
