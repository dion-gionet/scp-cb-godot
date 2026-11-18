shader_type spatial;
// Particles.bb sprites drawn through a MultiMesh (one draw per picture): a billboard that keeps the instance's scale,
// its alpha in INSTANCE_CUSTOM.x and its roll in .y. EntityFX 8 (no fog) is why the fog is off; the blend is the picture's own alpha,
// on display values (display_mix.gdshaderinc): smoke.png has pale lines at 1-3 % alpha along two edges, which a linear blend
// drew over the dark rooms as two sides of a square.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;

#include "res://shaders/particle_billboard.gdshaderinc"
#include "res://shaders/output_encode.gdshaderinc"
#include "res://shaders/display_mix.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
varying float v_alpha;
varying vec3 v_tint;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.x;
	v_tint = to_srgb(COLOR.rgb);      // the instance colour is the same raw value on both renderers
	upright_billboard(MODEL_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX, INSTANCE_CUSTOM.y, MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(tex, UV);
	float cover;
	vec3 albedo;
	display_mix(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, as_display(c.rgb) * v_tint, c.a * v_alpha, albedo, cover);
	ALBEDO = albedo;
	ALPHA = cover;
}
