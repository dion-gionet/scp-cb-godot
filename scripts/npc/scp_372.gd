extends Node3D
# SCP-372 (NPCs.bb NPCtype372, UpdateNPCs): a flickering shape seen at the edge of vision, never in the pocket dimension or SCP-1499.
# Idle it is hidden; while the player's eyes are shut (the blink timer between -5 and -15) there is a 1 in 50 chance a frame that it
# appears 1.5-2 m from the player, up to 90 degrees off where they look, for State = 20-60 frames. Seen on screen it gives the
# achievement, rustles now and then and keeps to the side of the view, moving along at 0.03 a frame; it uses up State twice over and
# goes idle at 0. `0 1 2 3` frames 32-113 are its flicker; it spins on its roll axis as it floats.


const MODEL_SCALE := 0.35 / 20.0
const RUSTLES := ["SFX/SCP/372/Rustle0.ogg", "SFX/SCP/372/Rustle1.ogg", "SFX/SCP/372/Rustle2.ogg"]

var idle := false
var state := 0.0
var frame := 32.0
var facing := 0.0
var hold := false
var _visual: Node3D
var _voice: AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("scp372")
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/372.b3d"))
	var width: float = _visual.mesh_instance.get_aabb().size.x
	_visual.scale = Vector3.ONE * (0.35 / maxf(width, 0.001))
	add_child(_visual)
	_visual.set_frame(frame)

func save_state() -> Dictionary:
	return {"idle": idle, "state": state, "frame": frame, "facing": facing}

func load_state(data: Dictionary) -> void:
	idle = bool(data.idle)
	state = float(data.state)
	frame = float(data.frame)
	facing = float(data.get("facing", 0.0))
	_visual.set_frame(frame)
	visible = not idle

func _animate(start: float, quit: float, speed: float, fps: float) -> void:
	var new_time := maxf(minf(frame + speed * fps, quit), start)
	if new_time >= quit:
		new_time = start
	frame = new_time
	_visual.set_frame(frame)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or not facility.active:
		return
	var here: String = facility.room_name_at(player.global_position)
	if here == "pocketdimension" or here == "dimension1499":
		return
	var fps := delta * 70.0
	if hold:
		_hold_at_view_edge(player, fps)
		return
	if idle:
		visible = false
		if randf() < fps / 50.0 and player.blink_timer < -5.0 and player.blink_timer > -15.0:
			visible = true
			var heading := player.rotation.y + deg_to_rad(randf_range(-90.0, 90.0))
			var distance := randf_range(1.5, 2.0)
			global_position = Vector3(player.global_position.x + sin(heading) * distance, player.global_position.y + 0.2, player.global_position.z - cos(heading) * distance)
			idle = false
			state = randf_range(20.0, 60.0)
			if randi_range(1, 300) == 1:
				Sfx.play_at(self, RUSTLES[randi_range(0, 2)], 8.0, randf_range(0.0, 0.2))
		return
	var lift := _pose(fps, 0.005)
	if EntityInView.mesh(player.camera, _visual.mesh_instance):
		GameState.give_achievement("372")
		if randf() < fps / 30.0 and (_voice == null or not is_instance_valid(_voice) or not _voice.playing) and _in_line_of_sight(player, lift):
			_voice = Sfx.play_at(self, RUSTLES[randi_range(0, 2)], 8.0, 0.3)
		var to_me := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)
		var yaw_to_me := atan2(-to_me.x, -to_me.y)
		var side := fposmod(rad_to_deg(player.rotation.y - yaw_to_me), 360.0)
		var heading_yaw := player.rotation.y - deg_to_rad(80.0) if side < 180.0 else player.rotation.y + deg_to_rad(80.0)
		facing = heading_yaw
		var step := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw)) * 0.03 * fps
		global_position += step
		state -= fps
	state -= fps / 80.0
	if state <= 0.0:
		idle = true

# Console `hold372`: debug only, not in the original. Keeps the shape 1.5 m ahead and 30 degrees to the left at eye height, awake and drifting nowhere.
func _hold_at_view_edge(player: CharacterBody3D, fps: float) -> void:
	var heading := player.rotation.y + deg_to_rad(30.0)
	global_position = Vector3(player.global_position.x - sin(heading) * 1.5, player.camera.global_position.y - 0.5, player.global_position.z - cos(heading) * 1.5)
	idle = false
	visible = true
	state = 60.0
	_pose(fps, 0.0)

# The float (0.3 + 0.1 sin(ms / 2)), the jitter, the yaw of the collider then the spin on the roll axis, and the flicker; returns the lift.
func _pose(fps: float, jitter: float) -> float:
	var lift := 0.3 + 0.1 * sin(GameState.clock_ms() / 2.0 * PI / 180.0)
	_visual.position = Vector3(randf_range(-jitter, jitter), lift, randf_range(-jitter, jitter))
	_visual.rotation = Vector3(0.0, facing, deg_to_rad(fmod(GameState.clock_ms() / 5.0, 360.0)))
	_animate(32.0, 113.0, 0.4, fps)
	return lift

func _in_line_of_sight(player: CharacterBody3D, lift: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, global_position + Vector3(0.0, lift, 0.0))
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
