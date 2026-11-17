shader_type spatial;
// The additive pictures of Particles.bb (flash, dust, the sun, sparks): see particle_mix.gdshader. Blitz adds the picture's
// display (sRGB) value times its alpha to the screen's, so the added amount is that product converted to linear, as in
// gamma_add.gdshaderinc (exact over a dark background, which is where these are seen).
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_add;

#include "res://shaders/particle_billboard.gdshaderinc"
#include "res://shaders/srgb.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
varying float v_alpha;
varying vec3 v_tint;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.x;
	v_tint = COLOR.rgb;
	upright_billboard(MODEL_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX, INSTANCE_CUSTOM.y, MODELVIEW_MATRIX);
}

void fragment() {
	vec3 top = to_srgb(texture(tex, UV).rgb) * to_srgb(v_tint) * clamp(v_alpha, 0.0, 1.0);
	ALBEDO = from_srgb(clamp(top, vec3(0.0), vec3(1.0)));
	ALPHA = 1.0;
}
