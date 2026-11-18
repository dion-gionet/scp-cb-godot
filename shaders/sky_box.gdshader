shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear, repeat_disable;

// A sky box face that sits at the far plane, whatever its size: anything drawn in front of it hides it (Godot 4's depth is
// reversed, so the far plane is 0). The box follows the camera.
void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = vec4(clip.xy, 0.0, clip.w);
}

void fragment() {
	ALBEDO = texture(tex, UV).rgb;
}
