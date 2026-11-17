extends "res://scripts/npc/scp_008_zombie.gd"
# SCP-966, "Sleep Killer" (NPCs.bb NPCtype966, UpdateNPCs "Case NPCtype966"): speed 1.0 / 100, model scp-966.b3d at 0.5 / 40 (full
# bright), seen only through night vision. Within 15 of the player it acts; farther away it hides and now and then (1 in 600
# frames) jumps to a waypoint 1-10 away on both axes and at least 16 from the player.
#  - the player wearing out (stamina below 10) raises State3 (down again by 0.2 a frame while it is under 900); above 350 every
#    966 turns hostile (State 8, State3 1000)
#  - without night vision the body is hidden; within 1 it makes the player feel it (a line every 20 s)
#  - State 0 stands (frames 2-214, 628-652); it picks 1-4 (echo and stare) when the player is near or after a loop, else 5 / 6
#  - 1, 2 echo (214-257, the sound at 228): while State3 < 900 within 16 and without a mask, suit or ring: blur by the echo,
#    BlinkEffect 1.5 and StaminaEffect 2.0 (1000 s)
#  - 3, 4 stare (257-332 / 332-457) turned at the player; 5, 6 walk (580-628) at half speed, turning off walls; 8 chases the
#    player (a route when out of sight, straight at them when seen, State 10 within 1)
#  - 10 attacks (458-557): the blows at frames 470, 500 and 527 within 1 do 0.5-1.0 injuries
# It was meant to replace the old sleeping "SCP-966-1" of 1.3 and lives in room966 (two of them wait there for the player).


var angle := 0.0           # n\Angle: the heading the body turns toward (radians)
var reload := 0.0          # n\Reload: frames until the next "something is here" line
var last_seen := 0.0       # n\LastSeen: the echo of the attack has played
var state_clock := 0.0     # n\State2: the next time (ms) it looks for a wall in front

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp966")
	speed = 1.0 / 100.0
	frame = 15.0
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	_body = CollisionShape3D.new()
	_body.shape = shape
	_body.position.y = shape.radius
	add_child(_body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/scp-966.b3d"))
	_visual.scale = Vector3.ONE * (0.5 / 40.0)
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(_visual)
	_visual.set_frame(frame)
	_loop = AudioStreamPlayer3D.new()
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 14.0
	add_child(_voice)
	angle = rotation.y

func set_state(value: int) -> void:
	state = value

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	if dist >= HIDE_DISTANCE:
		_visual.visible = false
		velocity = Vector3.ZERO
		if randi_range(1, 600) == 1:
			_teleport_closer()
		return
	var before := frame
	var move := 0.0
	var s := GameState
	if s.wearing_night_vision == 0:
		_visual.visible = false
		if dist < 1.0 and reload <= 0.0 and _message_idle():
			var lines := ["You feel something breathing right next to you.", "\"It feels like something's in this room with me.\"", "You feel like something is here with you, but you do not see anything.", "\"Is my mind playing tricks on me or is there someone else here?\"", "You feel like something is following you.", "You can feel something near you, but you are unable to see it. Perhaps its time is now."]
			_message(lines[randi_range(1, 6) - 1], 8.0)
			reload = 20.0 * 70.0
		reload -= fps
	else:
		_visual.visible = true
	if state3 > 5.0 * 70.0:
		if state3 < 1000.0:
			for other in get_tree().get_nodes_in_group("scp966"):
				other.state3 = 1000.0
		state = maxi(state, 8)
		state3 = 1000.0
	if player.stamina < 10.0:
		state3 += fps
	elif state3 < 900.0:
		state3 = maxf(state3 - fps * 0.2, 0.0)
	if state != 10:
		last_seen = 0.0
	match state:
		0:
			if frame > 556.0:
				animate(628.0, 652.0, 0.25, fps, false)
				if frame > 651.0:
					set_frame(2.0)
			else:
				animate(2.0, 214.0, 0.25, fps, false)
				if frame > 213.0:
					state = randi_range(1, 4) if randi_range(1, 3) == 1 and dist < 4.0 else randi_range(5, 6)
				if dist < 2.0:
					state = randi_range(1, 4)
			curr_speed = _curve_value(0.0, curr_speed, 10.0, fps)
			move = curr_speed * fps
		1, 2:
			animate(214.0, 257.0, 0.25, fps, false)
			if frame > 256.0:
				state = 0
			if frame > 228.0 and before <= 228.0:
				Sfx.play_at(self, "SFX/SCP/966/Echo%d.ogg" % randi_range(1, 3), 10.0)
			rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 20.0, fps)
			if state3 < 900.0:
				s.blur_timer = ((sin(deg_to_rad(s.clock_ms() / 50.0)) + 1.0) * 200.0) / maxf(dist, 0.1)
				if s.wearing_night_vision > 0:
					s.give_achievement("966")
				if not s.wearing_714 and s.wearing_gas_mask < 3 and s.wearing_hazmat < 3 and dist < 16.0:
					s.blink_effect = maxf(s.blink_effect, 1.5)
					s.blink_effect_timer = 1000.0
					s.stamina_effect = 2.0
					s.stamina_effect_timer = 1000.0
		3, 4:
			if state == 3:
				animate(257.0, 332.0, 0.25, fps, false)
				if frame > 331.0:
					state = 0
			else:
				animate(332.0, 457.0, 0.25, fps, false)
				if frame > 456.0:
					state = 0
			if idle_cue(before, frame):
				Sfx.play_at(self, "SFX/SCP/966/Idle%d.ogg" % randi_range(1, 3), 10.0)
			rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 20.0, fps)
		5, 6, 8:
			move = _walk(fps, player, facility, dist, before)
		10:
			_attack966(fps, player, dist, before)
	_gravity_step(delta, -global_transform.basis.z * move / maxf(delta, 0.0001))

# Blitz3D And/Or share one precedence level and fold left to right, so the original's
# `f>271 And p<=271 Or f>354 Or f>314 And p<=314 Or f>301 And p<=301` reduces to this
static func idle_cue(before: float, now: float) -> bool:
	return before <= 301.0 and (now > 301.0 or (now > 271.0 and before <= 271.0))

func _message_idle() -> bool:
	var hud := get_tree().get_first_node_in_group("hud")
	return hud == null or hud.message_time_left() <= 0.0

func _message(text: String, seconds: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.message(text, seconds)

func _walk(fps: float, player: CharacterBody3D, facility: FacilityMap, dist: float, before: float) -> float:
	if frame < 580.0 and frame > 214.0:
		animate(556.0, 580.0, 0.25, fps, false)
	else:
		if curr_speed >= 0.005:
			animate(580.0, 628.0, curr_speed * 25.0, fps)
		else:
			animate(2.0, 214.0, 0.25, fps)
		if state == 8 and dist < 32.0:
			if path_timer <= 0.0:
				_find_path(player.global_position)
				path_timer = 40.0 * 10.0
				curr_speed = 0.0
			path_timer = maxf(path_timer - fps, 0.0)
			if not _clear_to(player):
				if path_status == 2:
					curr_speed = 0.0
					set_frame(2.0)
				elif path_status == 1:
					_route_heading(facility)
					curr_speed = _curve_value(speed, curr_speed, 10.0, fps)
				elif path_status == 0:
					curr_speed = _curve_value(0.0, curr_speed, 10.0, fps)
			else:
				angle = _yaw_wanted(player.global_position)
				curr_speed = _curve_value(speed, curr_speed, 10.0, fps)
				if dist < 1.0:
					state = 10
		else:
			var now := GameState.clock_ms()
			if now > state_clock and dist < 16.0:
				var ahead := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.5, 0.0), global_position + Vector3(0.0, 0.5, 0.0) - global_transform.basis.z * 1.5)
				ahead.collision_mask = 1
				if not get_world_3d().direct_space_state.intersect_ray(ahead).is_empty():
					angle = rotation.y + deg_to_rad(randf_range(80.0, 110.0))
				state_clock = now + 1000.0
				if randi_range(1, 5) == 1:
					state = 0
			curr_speed = _curve_value(speed * 0.5, curr_speed, 20.0, fps)
		if (before < 604.0 and frame >= 604.0) or (before < 627.0 and frame >= 627.0):
			Sfx.play_at(self, "SFX/Step/SCP/StepSCP%d.ogg" % randi_range(1, 4), 7.0, randf_range(0.5, 0.7))
			steps_played += 1
		rotation.y = _curve_angle(angle, rotation.y, 10.0, fps)
		return curr_speed * fps
	return 0.0

func _clear_to(player: CharacterBody3D) -> bool:
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0.0, 0.3, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# The heading toward the route's next point; doors on the way open for it (NPC doors only: not the locked ones).
func _route_heading(facility: FacilityMap) -> void:
	while path_location < path.size() and path_location <= 19 and path[path_location] == Vector3.INF:
		path_location += 1
	if path_location >= path.size() or path_location > 19:
		path_location = 0
		path_status = 0
		return
	var point: Vector3 = path[path_location]
	angle = _yaw_wanted(point)
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	if flat < 0.8:
		var blocked := false
		for node in facility.doors_near(point, 0.8):
			var door := node as Node3D
			if door == null or door.elevator:
				continue
			if (door.locked or door.keycard != 0 or not door.code.is_empty()) and not door.open:
				blocked = true
			elif not door.open and (door.openstate <= 0.0 or door.openstate >= 180.0):
				door.npc_open()
		if flat < 0.3:
			path_location += 1
		if blocked:
			path_status = 0
			path_location = 0
			path_timer = 40.0 * 10.0

func _attack966(fps: float, player: CharacterBody3D, dist: float, before: float) -> void:
	if last_seen == 0.0:
		Sfx.play_at(self, "SFX/SCP/966/Echo%d.ogg" % randi_range(1, 3), 10.0)
		last_seen = 1.0
	if frame > 557.0:
		animate(628.0, 652.0, 0.25, fps, false)
		if frame > 651.0:
			set_frame([458.0, 488.0, 518.0][randi_range(1, 3) - 1])
	elif frame <= 487.0:
		animate(458.0, 487.0, 0.3, fps, false)
		if frame > 486.0:
			state = 8
	elif frame <= 517.0:
		animate(488.0, 517.0, 0.3, fps, false)
		if frame > 516.0:
			state = 8
	elif frame <= 557.0:
		animate(518.0, 557.0, 0.3, fps, false)
		if frame > 556.0:
			state = 8
	if dist < 1.0:
		if (frame > 470.0 and before <= 470.0) or (frame > 500.0 and before <= 500.0) or (frame > 527.0 and before <= 527.0):
			Sfx.play_global(self, "SFX/General/Slash%d.ogg" % randi_range(1, 2))
			GameState.injuries += randf_range(0.5, 1.0)
			hits += 1
	angle = _yaw_wanted(player.global_position)
	rotation.y = _curve_angle(angle, rotation.y, 30.0, fps)

func _teleport_closer() -> void:
	if TeleportCloser.run(self):
		velocity = Vector3.ZERO
		path_status = 0
		path_timer = 0.0
		path_location = 0

func die() -> void:
	pass
