shader_type spatial;
// The multiplied pictures of Particles.bb (EntityBlend 2): see particle_mix.gdshader.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mul;

#include "res://shaders/particle_billboard.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
varying float v_alpha;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.x;
	upright_billboard(MODEL_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX, INSTANCE_CUSTOM.y, MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = texture(tex, UV).rgb;
	ALPHA = v_alpha;
}
