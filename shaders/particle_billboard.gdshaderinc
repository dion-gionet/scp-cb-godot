// SpriteViewMode 3 (upright) of Particles.bb: the sprite turns around the world's up axis to face the camera and stays vertical;
// its random roll (INSTANCE_CUSTOM.y, radians) turns it in its own plane.
void upright_billboard(mat4 model, mat4 inv_view, mat4 view, float roll, out mat4 modelview) {
	vec3 to_camera = inv_view[3].xyz - model[3].xyz;
	to_camera.y = 0.0;
	to_camera = length(to_camera) < 0.0001 ? inv_view[2].xyz : normalize(to_camera);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera));
	float c = cos(roll);
	float s = sin(roll);
	vec3 x_axis = right * c + vec3(0.0, 1.0, 0.0) * s;
	vec3 y_axis = -right * s + vec3(0.0, 1.0, 0.0) * c;
	modelview = view * mat4(
		vec4(x_axis * length(model[0].xyz), 0.0),
		vec4(y_axis * length(model[1].xyz), 0.0),
		vec4(to_camera * length(model[2].xyz), 0.0),
		vec4(model[3].xyz, 1.0));
}
