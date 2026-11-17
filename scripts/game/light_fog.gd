extends Node
# The original's "fog of war": black camera fog that thickens with the darkness around the player.
# Main.bb: CameraFogRange(Camera, CameraFogNear * LightVolume, CameraFogFar * LightVolume) with the options.ini
# near 0.5 / far 6.0, so in a dim corridor nothing is seen beyond 6 units. MapSystem.bb UpdateRooms adds up
# TempLightVolume over the lights of the rooms near the player (within HideDistance 15):
#   intensity^2 * (15 - distance) / 15   (intensity = the light colour's average, 0..1)
# then TempLightVolume = Max(sum / 4.5, 1); LightVolume follows it with CurveValue(.., 50). Gunshots flash it
# to TempLightVolume * 1.2 (`flash`). Night vision sets the far distance to 30 (CameraFogFar).
# The pocket dimension keeps its own fog (pocket_dimension.gd).

const HIDE_DISTANCE := 15.0
const FOG_NEAR := 0.5
const FOG_FAR := 6.0
const FOG_FAR_NVG := 30.0

var temp_light_volume := 1.0
var light_volume := 1.0
var _flash_frames := 0.0
var _saved_background := Color(-1.0, 0.0, 0.0)

func _physics_process(delta: float) -> void:
	var facility := get_parent()
	var player: CharacterBody3D = GameState.player
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	# the intro happens in the 173 room before the facility is active; the original fogs it the same way (its own lights)
	var chamber: Node = null if facility.active else get_tree().get_first_node_in_group("chamber")
	if player == null or holder == null or (not facility.active and chamber == null):
		return
	var env := holder.environment
	if facility.pocket != null and facility.pocket.player_inside:
		return
	if not GameState.fog_of_war:
		env.fog_enabled = false
		_set_room_fog(100000.0, 200000.0, Color.BLACK)
		return
	var fps := delta * 70.0
	if GameState.fog_override.x < 0.0 and _saved_background.r >= 0.0:
		env.background_color = _saved_background      # the gates' pale sky colour goes with their fog
		_saved_background = Color(-1.0, 0.0, 0.0)
	if GameState.fog_override.x >= 0.0:
		if _saved_background.r < 0.0:
			_saved_background = env.background_color
		# the gates: CameraFogRange 5, 45 (30 at gate A) in a pale colour that is also the sky's clear colour
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = GameState.fog_color
		env.background_color = GameState.fog_color
		env.fog_depth_curve = 1.0
		env.fog_depth_begin = GameState.fog_override.x
		env.fog_depth_end = GameState.fog_override.y
		_set_room_fog(GameState.fog_override.x, GameState.fog_override.y, GameState.fog_color)
		return
	temp_light_volume = measure(facility, player.global_position) if chamber == null else measure_points(chamber.light_points, player.global_position)
	var target := temp_light_volume
	if _flash_frames > 0.0:
		_flash_frames -= fps
		target = temp_light_volume * 1.2
		light_volume = target
	else:
		light_volume += (target - light_volume) * minf(fps / 50.0, 1.0)
	if GameState.light_dim > 0.0:
		light_volume = temp_light_volume - temp_light_volume * GameState.light_dim
		GameState.light_dim = 0.0
	var far := FOG_FAR_NVG if GameState.wearing_night_vision != 0 else FOG_FAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color.BLACK
	env.fog_depth_curve = 1.0
	env.fog_depth_begin = FOG_NEAR * light_volume
	env.fog_depth_end = far * light_volume
	_set_room_fog(FOG_NEAR * light_volume, far * light_volume, Color.BLACK)

# The room shaders fog themselves (see shaders/lightmap.gdshader); the environment's fog covers everything else.
func _set_room_fog(near: float, far: float, color: Color) -> void:
	RenderingServer.global_shader_parameter_set(&"room_fog_range", Vector2(near, far))
	RenderingServer.global_shader_parameter_set(&"room_fog_color", Vector3(color.r, color.g, color.b))

# TempLightVolume at a point: UpdateRooms (MapSystem.bb 5646) sums the lights of the rooms it shows, the player's neighbourhood.
static func measure(facility: FacilityMap, at: Vector3) -> float:
	var total := 0.0
	for room: Node in facility.drawing.ring_rooms:
		if not is_instance_valid(room) or not "lights" in room:
			continue
		for light in room.lights:
			var distance := at.distance_to(light.global_position)
			if distance < HIDE_DISTANCE:
				var color: Color = light.light_color
				var intensity: float = (color.r + color.g + color.b) / 3.0 * light.light_energy      # LightIntensity = (r + g + b) / 255 / 3 of the intensity-scaled colour
				total += intensity * intensity * ((HIDE_DISTANCE - distance) / HIDE_DISTANCE)
	return maxf(total / 4.5, 1.0)

# TempLightVolume from a list of [position, LightIntensity] (the intro room's lights).
static func measure_points(points: Array, at: Vector3) -> float:
	var total := 0.0
	for point in points:
		var distance: float = at.distance_to(point[0])
		if distance < HIDE_DISTANCE:
			var intensity: float = point[1]
			total += intensity * intensity * ((HIDE_DISTANCE - distance) / HIDE_DISTANCE)
	return maxf(total / 4.5, 1.0)

# A shot lights the corridor for a moment (LightVolume = TempLightVolume * 1.2, held until the next update).
func flash() -> void:
	_flash_frames = 2.0
