shader_type spatial;
// The DevilParticleSystem's smoke (ParticleEffect[1]) through the particle MultiMesh: alpha in INSTANCE_CUSTOM.x. Its quads face
// the camera (ParticlePiv takes the camera's pitch, yaw and roll), are drawn with EntityFX 34 (vertex colour and alpha, lit, fogged)
// and have no normals, so of the lights only AmbientLight reaches them. The blend is on display values like the other smoke.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;

#include "res://shaders/output_encode.gdshaderinc"
#include "res://shaders/display_mix.gdshaderinc"
#include "res://shaders/room_fog.gdshaderinc"

global uniform vec3 entity_ambient;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
varying float v_alpha;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.x;
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
}

void fragment() {
	vec4 c = texture(tex, UV);
	vec3 top = as_display(c.rgb) * entity_ambient;
	top = to_srgb(mix(from_srgb(clamp(top, vec3(0.0), vec3(1.0))), from_srgb(room_fog_color), room_fog_amount(VERTEX, CAMERA_VISIBLE_LAYERS)));
	float cover;
	vec3 albedo;
	display_mix(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, top, c.a * v_alpha, albedo, cover);
	ALBEDO = albedo;
	ALPHA = cover;
}
