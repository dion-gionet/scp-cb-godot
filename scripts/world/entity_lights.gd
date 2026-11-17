class_name EntityLights
# The point lights the models are lit with (shaders/entity.gdshaderinc). Blitz3D hands its shown lights to Direct3D 7 in
# creation order and the device lights with at most 8 of them. Each light carries the meta "blitz_range" (LightRange)
# and "blitz_colour" (LightColor / 255).

const MAX_LIGHTS := 8

static var shown: Array[Light3D] = []

static func upload(lights: Array[Light3D]) -> void:
	shown = lights.slice(0, MAX_LIGHTS)
	var positions: Array[Vector4] = []
	var colours: Array[Vector4] = []
	for light in shown:
		var at := light.global_position
		var colour: Color = light.get_meta("blitz_colour", light.light_color)
		positions.append(Vector4(at.x, at.y, at.z, float(light.get_meta("blitz_range", 1.0))))
		colours.append(Vector4(colour.r, colour.g, colour.b, 0.0))
	while positions.size() < MAX_LIGHTS:
		positions.append(Vector4.ZERO)
		colours.append(Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"entity_light_pos_a", Projection(positions[0], positions[1], positions[2], positions[3]))
	RenderingServer.global_shader_parameter_set(&"entity_light_pos_b", Projection(positions[4], positions[5], positions[6], positions[7]))
	RenderingServer.global_shader_parameter_set(&"entity_light_col_a", Projection(colours[0], colours[1], colours[2], colours[3]))
	RenderingServer.global_shader_parameter_set(&"entity_light_col_b", Projection(colours[4], colours[5], colours[6], colours[7]))

static func clear() -> void:
	upload([])

# The vertex colour shaders/entity.gdshaderinc gives a point with this world normal, for tests.
static func vertex_light(at: Vector3, normal: Vector3, ambient: float) -> Vector3:
	var sum := Vector3.ONE * ambient
	for light in shown:
		var to_light := light.global_position - at
		var dist := maxf(to_light.length(), 0.0001)
		var colour: Color = light.get_meta("blitz_colour", light.light_color)
		var power := maxf(normal.normalized().dot(to_light / dist), 0.0) * float(light.get_meta("blitz_range", 1.0)) / dist
		sum += Vector3(colour.r, colour.g, colour.b) * power
	return sum.clamp(Vector3.ZERO, Vector3.ONE)
