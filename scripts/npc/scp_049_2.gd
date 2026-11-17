extends "res://scripts/npc/scp_008_zombie.gd"
# SCP-049-2, the "cured" (NPCs.bb NPCtypeZombie, UpdateNPCs "Case NPCtypeZombie"): 100 HP, speed 0.8 / 100, model zombie1.b3d at
# 0.27 / 2.5. It shares the walking, seeing, route and animation helpers of the SCP-008-1 script and keeps its own rules:
# State 0 lies on the floor (frames 719-777, now and then it stirs when the player is within 5); 1 stands up (155-682, then
# 926-935); 2 follows: every 3 s it checks whether the player is within 5 and visible and then hunts them for 5 s (turns at
# them and walks at full speed, breathing); out of that it follows a route to the player, re-planned every 5 s, and stands
# swaying (778-926) while it has none; within 0.7 it attacks (State 3: frames 2-65 or 66-132, the blow lands at frame 23 / 90 within
# 1.1 and 60 degrees: injuries + 0.4-1.0); State 4 is the room049 scene's "put away" state (it just stands). Dead: frames 133-157.
# It only acts when the player is within 4 vertically.


const KILL_MESSAGE := "Subject D-9341. Cause of death: multiple lacerations and severe blunt force trauma caused by an instance of SCP-049-2."

var kind := "049-2"

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp0492")
	hp = 100.0
	speed = 0.8 / 100.0
	frame = 107.0
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	_body = CollisionShape3D.new()
	_body.shape = shape
	_body.position.y = shape.radius
	add_child(_body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/zombie1.b3d"))
	_visual.scale = Vector3.ONE * (0.27 / 2.5)
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)      # RotateEntity n.obj, -90, yaw: the skeleton is authored lying down
	add_child(_visual)
	_visual.set_frame(frame)
	_loop = AudioStreamPlayer3D.new()
	_loop.max_distance = 6.0
	_loop.volume_db = linear_to_db(0.6)
	var breath := Sfx.stream("SFX/SCP/049/0492Breath.ogg")
	if breath != null:
		breath.loop = true
		_loop.stream = breath
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 14.0
	add_child(_voice)
	set_state(state)
	if state == 0:
		set_frame(719.0)

func set_state(value: int) -> void:
	state = value
	collision_layer = 0 if is_dead else 4

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active:
		return
	if absf(player.global_position.y - global_position.y) >= 4.0:
		return
	var fps := delta * 70.0
	var before := frame
	var move := 0.0
	if is_dead:
		if _loop.playing:
			_loop.stop()
		collision_layer = 0
		animate(133.0, 157.0, 0.5, fps, false)
		_gravity_step(delta, Vector3.ZERO)
		return
	match state:
		0:
			animate(719.0, 777.0, 0.2, fps, false)
			if frame == 777.0 and randi_range(1, 700) == 1 and global_position.distance_to(player.global_position) < 5.0:
				set_frame(719.0)
		1:
			if frame >= 682.0:
				animate(926.0, 935.0, 0.3, fps, false)
				if frame == 935.0:
					set_state(2)
			else:
				animate(155.0, 682.0, 1.5, fps, false)
		2:
			move = _follow(fps, player, facility, before)
		3:
			_hit(fps, player, before)
	var breathing := state == 2 and state2 > 0.0 and not GameState.no_target_mode()
	if breathing and not _loop.playing:
		_loop.play()
	elif not breathing and _loop.playing:
		_loop.stop()
	_gravity_step(delta, -global_transform.basis.z * move / maxf(delta, 0.0001))

func _follow(fps: float, player: CharacterBody3D, facility: FacilityMap, before: float) -> float:
	var move := 0.0
	var dist := global_position.distance_to(player.global_position)
	if state3 < 0.0:
		if dist < 5.0 and _line_clear(player):
			state2 = 70.0 * 5.0
		state3 = 70.0 * 3.0
	else:
		state3 -= fps
	if state2 > 0.0 and not GameState.no_target_mode():
		path_status = 0
		rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 30.0, fps)
		if dist < 0.7:
			set_state(3)
			set_frame(2.0 if randi_range(1, 2) == 1 else 66.0)
		else:
			curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
			move = curr_speed * fps
			animate(936.0, 1017.0, curr_speed * 60.0, fps)
		state2 -= fps
	else:
		if path_status == 1:
			move = _walk_route(fps, facility)
		else:
			curr_speed = 0.0
			animate(778.0, 926.0, 0.1, fps)
			path_timer -= fps
			if path_timer <= 0.0:
				_find_path(player.global_position + Vector3(0.0, 0.1, 0.0))
				path_timer += 70.0 * 5.0
	if curr_speed > 0.005:
		if (before < 977.0 and frame >= 977.0) or (before > 1010.0 and frame < 940.0):
			Sfx.play_at(self, "SFX/Character/MTF/Step%d.ogg" % randi_range(1, 3), 8.0, randf_range(0.3, 0.5))
			steps_played += 1
	return move

func _line_clear(player: CharacterBody3D) -> bool:
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0.0, 0.3, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# The route walk of the state-2 zombie: PointEntity at the waypoint, CurveValue(Speed), frames 936-1017.
func _walk_route(fps: float, facility: FacilityMap) -> float:
	while path_location < path.size() and path_location <= 19 and path[path_location] == Vector3.INF:
		path_location += 1
	if path_location >= path.size() or path_location > 19:
		path_location = 0
		path_status = 0
		return 0.0
	var point: Vector3 = path[path_location]
	rotation.y = _curve_angle(_yaw_wanted(point), rotation.y, 30.0, fps)
	curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
	animate(936.0, 1017.0, curr_speed * 60.0, fps)
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	if flat < 0.6:
		for node in facility.doors_near(point, 0.6):
			var door := node as Node3D
			if door != null and not door.elevator and not door.locked and door.keycard == 0 and door.code.is_empty() and not door.open and (door.openstate <= 0.0 or door.openstate >= 180.0):
				door.npc_open()
	if flat < 0.2:
		path_location += 1
	return curr_speed * fps

func _hit(fps: float, player: CharacterBody3D, before: float) -> void:
	if GameState.no_target_mode():
		set_state(2)
		return
	var near := global_position.distance_to(player.global_position) < 1.1
	var facing := absf(rad_to_deg(_yaw_to(player.global_position))) <= 60.0
	if frame < 66.0:
		animate(2.0, 65.0, 0.7, fps, false)
		if before < 23.0 and frame >= 23.0:
			_land(near, facing)
		elif frame == 65.0:
			set_state(2)
	else:
		animate(66.0, 132.0, 0.7, fps, false)
		if before < 90.0 and frame >= 90.0:
			_land(near, facing)
		elif frame == 132.0:
			set_state(2)

func _land(near: bool, facing: bool) -> void:
	if not near or not facing:
		return
	Sfx.play_global(self, "SFX/Character/D9341/Damage%d.ogg" % randi_range(5, 8))
	GameState.injuries += randf_range(0.4, 1.0)
	GameState.death_msg = KILL_MESSAGE
	hits += 1

func die() -> void:
	is_dead = true
	set_frame(133.0)
	collision_layer = 0
