extends Node3D
# SCP-513-1 (NPCs.bb NPCtype5131, UpdateNPCs): the shape the bell calls. Made when SCP-513 is rung with none about (item_use.gd).
# It is never in the pocket dimension. Idle it is hidden; 1 frame in 200 it appears on a waypoint 3-9 away on both axes in another
# room, for 15-20 s (State2, run down four times as fast within 4 m). Then:
#   0 stands (frames 2-74 or 75-124) turning to the player; once it has been seen (within 6, on screen, in sight: a bell) and the
#     player is within 4 it moves on (1 or 2)
#   1 / 2 walks (125-194 / 195-264 at its speed) or stands (2) along the waypoints, always to a neighbour farther from the player
# A second, half-clear copy of it shakes beside the body. When the time is up, or there is nowhere to go, it vanishes again.


var idle := true
var state := 0
var state2 := 0.0
var prev_state := 0
var last_seen := 0
var frame := 2.0
var curr_speed := 0.0
var path := -1                      # n\Path[0]: a waypoint id, -1 for none
var twitch := Vector2.ZERO          # PrevX / PrevZ
var _body: Node3D
var _ghost: Node3D
var _yaw := 0.0                      # the body's own yaw (n\obj)

func _ready() -> void:
	add_to_group("scp513_1")
	_body = B3DModel.new()
	_body.load_file(ContentPaths.existing_file("GFX/npcs/bll.b3d"))
	var scale_value: float = 1.8 / maxf(_body.mesh_instance.get_aabb().size.x, 0.001)
	_body.scale = Vector3.ONE * scale_value
	add_child(_body)
	_ghost = B3DModel.new()
	_ghost.load_file(ContentPaths.existing_file("GFX/npcs/bll.b3d"))
	_ghost.scale = Vector3.ONE * scale_value
	add_child(_ghost)
	_ghost.set_as_top_level(true)
	for mesh_node in [_ghost.mesh_instance]:
		(mesh_node as GeometryInstance3D).transparency = 0.4
	_hide()

func save_state() -> Dictionary:
	return {"idle": idle, "state": state, "state2": state2, "prev_state": prev_state, "last_seen": last_seen, "frame": frame, "curr_speed": curr_speed, "yaw": _yaw}

func load_state(data: Dictionary) -> void:
	idle = bool(data.idle)
	state = int(data.state)
	state2 = float(data.state2)
	prev_state = int(data.prev_state)
	last_seen = int(data.last_seen)
	frame = float(data.frame)
	curr_speed = float(data.curr_speed)
	_yaw = float(data.yaw)
	path = -1          # waypoint ids are made again with the rooms: it picks its way anew
	_body.set_frame(frame)
	_ghost.set_frame(frame)
	if idle:
		_hide()
	else:
		_show()

func _hide() -> void:
	_body.visible = false
	_ghost.visible = false

func _show() -> void:
	_body.visible = true
	_ghost.visible = true

func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps

func _animate(start: float, quit: float, speed: float, fps: float) -> void:
	var new_time := maxf(minf(frame + speed * fps, quit), start)
	if new_time >= quit:
		new_time = start
	frame = new_time
	_body.set_frame(frame)
	_ghost.set_frame(frame)

func _yaw_to(point: Vector3) -> float:
	return atan2(-(point.x - global_position.x), -(point.z - global_position.z))

func _noticed(player: CharacterBody3D) -> bool:
	if not player.camera.is_position_in_frustum(global_position + Vector3(0.0, 0.8, 0.0)):
		return false
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, global_position + Vector3(0.0, 0.8, 0.0))
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or not facility.active:
		return
	if facility.room_name_at(player.global_position) == "pocketdimension":
		return
	var fps := delta * 70.0
	var graph = facility.graph
	if idle:
		_hide()
		if randf() < fps / 200.0:
			var player_room := str(facility.record_at(player.global_position).get("key", ""))
			for id in graph.point_ids():
				if graph.room_key_of(id) == player_room:
					continue
				var at: Vector3 = graph.position_of(id)
				var x := absf(player.global_position.x - at.x)
				var z := absf(player.global_position.z - at.z)
				if x > 3.0 and x < 9.0 and z > 3.0 and z < 9.0:
					global_position = at
					_show()
					last_seen = 0
					path = id
					idle = false
					state2 = randi_range(15, 20) * 70.0
					state = maxi(randi_range(-1, 2), 0)
					prev_state = randi_range(0, 1)
					break
		return
	var dist := global_position.distance_to(player.global_position)
	twitch.x = _curve(0.0, twitch.x, 10.0, fps)
	twitch.y = _curve(0.0, twitch.y, 10.0, fps)
	if randf() < fps / 100.0:
		if randi_range(1, 5) == 1:
			twitch = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z) * 0.9
		else:
			twitch = Vector2(randf_range(0.1, 0.5), randf_range(0.1, 0.5))
	var jitter := randf_range(-1.0, 1.0)
	_ghost.global_position = Vector3(global_position.x + twitch.x * jitter, global_position.y - 0.2 + sin(deg_to_rad(fmod(GameState.clock_ms() / 8.0 - 45.0, 360.0))) * 0.05, global_position.z + twitch.y * jitter)
	_ghost.global_rotation = Vector3(0.0, _yaw, 0.0)
	if state == 0:
		if prev_state == 0:
			_animate(2.0, 74.0, 0.2, fps)
		else:
			_animate(75.0, 124.0, 0.2, fps)
		if last_seen != 0:
			_yaw += wrapf(_yaw_to(player.global_position) - _yaw, -PI, PI) / 40.0 * fps
			if dist < 4.0:
				state = randi_range(1, 2)
		elif dist < 6.0 and randi_range(1, 5) == 1:
			if _noticed(player):
				last_seen = 1
				Sfx.play_global(self, "SFX/SCP/513/Bell%d.ogg" % randi_range(2, 3))
	else:
		_follow_path(player, facility, graph, dist, fps)
	if is_instance_valid(self) and not idle:
		var bob := sin(deg_to_rad(fmod(GameState.clock_ms() / 8.0, 360.0))) * 0.1
		_body.global_position = Vector3(global_position.x, global_position.y - 0.2 + bob, global_position.z)
		match state:
			1:
				if prev_state == 0:
					_animate(125.0, 194.0, curr_speed * 20.0, fps)
				else:
					_animate(195.0, 264.0, curr_speed * 20.0, fps)
				_yaw = rotation.y
			2:
				if prev_state == 0:
					_animate(2.0, 74.0, 0.2, fps)
				else:
					_animate(75.0, 124.0, 0.2, fps)
				_yaw = rotation.y
		_body.global_rotation = Vector3(0.0, _yaw, 0.0)
		if state2 > 0.0:
			if dist < 4.0:
				state2 -= fps * 4.0
			state2 -= fps
		else:
			path = -1
			idle = true
			state2 = 0.0

func _follow_path(player: CharacterBody3D, facility: FacilityMap, graph, dist: float, fps: float) -> void:
	if path < 0:
		for id in graph.point_ids():
			var at: Vector3 = graph.position_of(id)
			var x := absf(global_position.x - at.x)
			var z := absf(global_position.z - at.z)
			if x < 8.0 and x > 1.0 and z < 8.0 and z > 1.0 and player.global_position.distance_to(at) > dist:
				path = id
				break
		if path < 0:
			idle = true
			state2 = 0.0
		return
	var target: Vector3 = graph.position_of(path)
	if global_position.distance_to(target) > 1.0:
		var yaw := _yaw_to(target)
		rotation.y += wrapf(yaw - rotation.y, -PI, PI) / 15.0 * fps
		curr_speed = _curve(0.05 * maxf((7.0 - dist) / 7.0, 0.0), curr_speed, 15.0, fps)
		var forward := -global_transform.basis.z
		global_position += Vector3(forward.x, 0.0, forward.z) * curr_speed * fps
		if randf() < fps / 200.0:
			global_position += Vector3(forward.x, 0.0, forward.z) * 0.5
	else:
		for id in graph.neighbours_of(path):
			if player.global_position.distance_to(graph.position_of(id)) > dist:
				if last_seen == 0 and _noticed(player):
					last_seen = 1
					Sfx.play_global(self, "SFX/SCP/513/Bell%d.ogg" % randi_range(2, 3))
				path = id
				break
