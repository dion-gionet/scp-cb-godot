extends CharacterBody3D
# A Nine-Tailed Fox soldier (NPCs.bb UpdateMTFUnit). Three of them arrive from gate A a while after
# the breach (see mtf_director.gd update_squad) and patrol the facility: the leader walks to rooms,
# the others follow. Their state decides what they do:
#   0 wandering        1 searching for / shooting the player   2 looking at / containing SCP-173
#   3 following a path 4 SCP-106 or 049 seen: backing off      5 looking at a spot (enemy)
#   6 shooting the player as an SCP-049-2   7 just shooting    8 SCP-096 seen    9 an 049-2 / 008 seen
# 8 and 9 need SCP-096, 049-2 and 008, none of which exist in this port yet, so they end at once.
# Speeds are per 70 Hz frame like the original.


const RS := MeshLoader.ROOM_SCALE
const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0
const HIDE_DISTANCE := 15.0
const WALK := Vector2(488.0, 522.0)
const MODEL_PITCH := PI * 0.5    # RotateEntity nobj, -90, angle: the skeleton is authored lying down (z is flipped here)

var state := 0
var state2 := 0.0
var state3 := 0.0
var prev_state := 0
var angle := 0.0              # n\Angle: the body turns toward the heading with a lag (radians)
var speed := 0.02 * GameState.npc_speed_factor()   # NPCs.ini [MTF] speed 2.0; the states that set 0.015 or 0.03 override it
var curr_speed := 0.0
var reload := 0.0
var idle := 0.0               # frames the unit stands still (events)
var blink_timer := 70.0 * 10.0
var last_seen := 0.0
var enemy := Vector3.ZERO     # EnemyX/Y/Z
var is_dead := false
var frame := 1.0
var leader: Node = null       # MTFLeader
var target: Node = null       # n\Target (106, 049)
var no_target := false

var path: Array[Vector3] = []
var path_status := 0
var path_location := 0
var path_timer := 0.0
var path_goal := Vector3.INF   # PathX/PathZ: a straight walk (inside 173's chamber)

var shots_fired := 0
var steps_played := 0
var voices: Array[String] = []     # what it has said (tests)

var _visual: Node3D
var _voice: AudioStreamPlayer3D
var _breath: AudioStreamPlayer3D
var _prev_173 := Vector2.INF    # 173's last position (INF: not seen yet, so the first look counts as no movement)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("mtf")
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	body.shape = shape
	body.position.y = shape.radius
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/MTF2.b3d"))
	_visual.scale = Vector3.ONE * (0.29 / 2.5)
	_visual.rotation = Vector3(MODEL_PITCH, 0.0, 0.0)
	_visual.position.y = -0.15 + 0.2    # PositionEntity obj, collider y - 0.15 (the collider is 0.2 above the feet)
	add_child(_visual)
	frame = WALK.x
	_visual.set_frame(frame)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 8.0
	add_child(_voice)
	_breath = AudioStreamPlayer3D.new()
	_breath.max_distance = 10.0
	var breath := Sfx.stream("SFX/Character/MTF/Breath.ogg")
	if breath != null:
		breath.loop = true
		_breath.stream = breath
	add_child(_breath)
	angle = rotation.y
	blink_timer = 70.0 * randf_range(10.0, 15.0)

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null:
		return
	var fps := delta * 70.0
	if is_dead:
		blink_timer = -1.0
		set_frame(532.0)
		_breath.stop()
		_gravity_step(delta, Vector3.ZERO)
		return
	if not _breath.playing and global_position.distance_to(player.global_position) < 8.0:
		_breath.play()
	elif _breath.playing and global_position.distance_to(player.global_position) >= 8.0:
		_breath.stop()
	blink_timer -= fps
	if blink_timer <= -5.0:
		# the "blinking" clip only while containing 173
		var statue := _statue()
		if state == 2 and statue != null and _other_sees_me(statue):
			say("SFX/Character/MTF/173/BLINKING.ogg")
		blink_timer = 70.0 * randf_range(10.0, 15.0)
	reload -= fps
	var before := frame
	if int(state) != 1:
		prev_state = 0
	var move := 0.0
	if idle > 0.0:
		_finish_walking(fps)
		idle = maxf(idle - fps, 0.0)
	else:
		move = _run_state(fps, player, facility)
		_post_state(fps, before, player, facility)
	_apply_angle(fps)
	_gravity_step(delta, -global_transform.basis.z * move / maxf(delta, 0.0001))
	_check_ground()

func _run_state(fps: float, player: CharacterBody3D, facility: FacilityMap) -> float:
	match state:
		0:
			return _wander(fps, player, facility)
		1:
			return _search(fps, player, facility)
		2:
			return _look_at_173(fps, player, facility)
		3:
			return _follow_route(fps, facility)
		4:
			return _flee(fps, player, facility)
		5:
			_look_at_spot(fps, player)
		6:
			_shoot_as_zombie(fps, player)
		7:
			_just_shoot(fps)
		9:
			return _shoot_zombie(fps, facility)
		8:
			return _look_away(fps, facility)
	return 0.0

func _wander(fps: float, player: CharacterBody3D, facility: FacilityMap, watching: bool = false) -> float:
	var move := 0.0
	speed = 0.015
	var statue := _statue()
	if path_timer <= 0.0:
		if leader != null and is_instance_valid(leader):
			path_status = _find_path(leader.global_position + Vector3(0.0, 0.1, 0.0))
		else:
			if statue == null or statue.idle != 2:
				var goal := _room_goal()
				path_status = _find_path(goal)
			else:
				var goal := _contain_goal(facility, statue)
				if path_goal == Vector3.INF and goal != Vector3.INF:
					path_status = _find_path(goal)
				elif path_goal == Vector3.INF:
					path_status = 0
		if path_status == 1:
			_skip_behind()
		path_timer = 70.0 * randf_range(6.0, 10.0)
	elif path_timer <= 70.0 * 2.5 and leader == null:
		path_timer -= fps
		curr_speed = 0.0
		_turn_randomly()
		_finish_walking(fps)
	else:
		if path_status == 2:
			path_timer -= fps * 2.0
			curr_speed = 0.0
			_turn_randomly()
			_finish_walking(fps)
		elif path_status == 1:
			move = _walk_route(fps, facility, 1.0)
			path_timer -= fps
		elif path_goal != Vector3.INF:
			var flat := Vector2(path_goal.x - global_position.x, path_goal.z - global_position.z)
			_face(path_goal)
			curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
			move = curr_speed * fps
			animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
			if flat.length() < 0.2:
				path_goal = Vector3.INF
				path_timer = 70.0 * randf_range(6.0, 10.0)
		else:
			path_timer -= fps * 2.0
			if leader == null or not is_instance_valid(leader):
				_turn_randomly()
				_finish_walking(fps)
				curr_speed = 0.0
			elif global_position.distance_to(leader.global_position) > 1.0:
				_face(leader.global_position)
				curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
				move = curr_speed * fps
				animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
			else:
				_turn_randomly()
				_finish_walking(fps)
				curr_speed = 0.0
	if watching:
		return move      # state 8 only walks; it does not look for the player or the other SCPs
	var seen := _sees_player(player)
	if no_target:
		seen = 0
	if seen > 0:
		if last_seen > 0.0 and last_seen < 70.0 * 15.0:
			if seen < 2:
				say("SFX/Character/MTF/ThereHeIs%d.ogg" % randi_range(1, 6))
		else:
			if seen == 1:
				say("SFX/Character/MTF/Stop%d.ogg" % randi_range(1, 6))
			elif seen == 2:
				say("SFX/Character/MTF/ClassD%d.ogg" % randi_range(1, 4))
		last_seen = 70.0 * randf_range(30.0, 40.0)
		state = 1
		enemy = player.global_position
		state2 = 70.0 * (15.0 * seen)    # give up after 15 seconds (30 if heard, 45 over a camera)
		path_timer = 0.0
		path_status = 0
		reload = 200.0 - (100.0 if GameState.aggressive_npcs() else 0.0)
	_notice_scps(facility, "SFX/Character/MTF/173/Spotted%d.ogg" % randi_range(1, 2), true)
	return move

func _search(fps: float, player: CharacterBody3D, facility: FacilityMap) -> float:
	var move := 0.0
	speed = 0.015
	state2 -= fps
	var player_dist := global_position.distance_to(player.global_position)
	if _sees_player(player) == 1:
		if player_dist < 4.0:
			move = _shoot_at_player(fps, player, player_dist)
		else:
			# toward the spot where it saw the player
			_face(enemy)
			curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
			move = curr_speed * fps
			animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
	else:
		last_seen -= fps
		if reload <= 7.0:
			reload = 7.0
		if path_timer <= 0.0:
			path_status = _find_path(enemy + Vector3(0.0, 0.1, 0.0))
			path_timer = 70.0 * randf_range(6.0, 10.0)
		elif path_timer <= 70.0 * 2.5:
			path_timer -= fps
			curr_speed = 0.0
			_turn_randomly()
			_finish_walking(fps)
		else:
			if path_status == 2:
				path_timer -= fps * 2.0
				curr_speed = 0.0
				_turn_randomly()
				_finish_walking(fps)
			elif path_status == 1:
				move = _walk_route(fps, facility, 1.0)
				path_timer -= fps
			else:
				var at_spot := Vector2(global_position.x - enemy.x, global_position.z - enemy.z).length() < 0.2
				if at_spot or not _visible_between(enemy + Vector3(0.0, 0.8, 0.0), global_position + Vector3(0.0, 0.8, 0.0)):
					_turn_randomly()
					_finish_walking(fps)
					if randi_range(1, 35) == 1:
						_pick_nearby_waypoint(facility)
					path_timer -= fps
				else:
					_face(enemy)
					curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
					move = curr_speed * fps
					animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
		if leader == null and last_seen < 70.0 * 30.0 and last_seen + fps >= 70.0 * 30.0:
			if randi_range(1, 2) == 1:
				say("SFX/Character/MTF/Searching%d.ogg" % randi_range(1, 6))
	if state2 <= 0.0 and state2 + fps > 0.0:
		if leader == null:
			say("SFX/Character/MTF/Targetlost%d.ogg" % randi_range(1, 3))
			_facility().mtf.start_camera_check(fps)
		state = 0
	if state == 1:
		_notice_scps(facility, "SFX/Character/MTF/173/Spotted3.ogg", false)
	return move

# It shoots when the player is within 4 and in the line of fire, and calls the others.
func _shoot_at_player(fps: float, player: CharacterBody3D, player_dist: float) -> float:
	var to_player := player.global_position - global_position
	var wanted := atan2(-to_player.x, -to_player.z)
	rotation.y = _curve_angle(wanted, rotation.y, 10.0, fps)
	angle = rotation.y
	if reload <= 0.0 and not player.dead:
		if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), player.camera.global_position):
			var off := absf(rad_to_deg(wrapf(wanted - rotation.y, -PI, PI)))
			if off < 5.0:
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 15.0)
				shots_fired += 1
				GameState.death_msg = "Subject D-9341. Died of blood loss after being shot by Nine-Tailed Fox."
				Gunfire.shoot(self, _muzzle(), 5.0 / maxf(player_dist, 0.001), "Subject D-9341. Terminated by Nine-Tailed Fox.", false)
				reload = 7.0
				if player.dead:
					say("SFX/Character/MTF/Targetterminated%d.ogg" % randi_range(1, 4))
	for other in get_tree().get_nodes_in_group("mtf"):
		if other == self or other.state != 0:
			continue
		if global_position.distance_to(other.global_position) < 6.0:
			prev_state = 1
			other.last_seen = 70.0 * randf_range(30.0, 40.0)
			other.state = 1
			other.enemy = player.global_position
			other.state2 = state2
			other.path_timer = 0.0
			other.path_status = 0
			other.reload = 200.0 - (100.0 if GameState.aggressive_npcs() else 0.0)
			other.prev_state = 0
	curr_speed = _curve_value(0.0, curr_speed, 20.0, fps)
	if prev_state == 1:
		set_frame(423.0)
		prev_state = 2
	elif prev_state == 2:
		if frame > 200.0:
			animate(423.0, 463.0, 0.4, fps, false)
			if frame > 462.9:
				set_frame(78.0)
		else:
			animate(78.0, 193.0, 0.2, fps, false)
	else:
		if frame > 958.0:
			animate(1374.0, 1383.0, 0.3, fps, false)
			if frame > 1382.9:
				set_frame(78.0)
		else:
			animate(78.0, 193.0, 0.2, fps, false)
	return 0.0

func _look_at_173(fps: float, player: CharacterBody3D, facility: FacilityMap) -> float:
	var statue := _statue()
	if statue == null or statue.idle == 2:
		state = 0
		return 0.0
	for other in get_tree().get_nodes_in_group("mtf"):
		if other != self:
			other.state = 2
	var dist173 := Vector2(global_position.x - statue.global_position.x, global_position.z - statue.global_position.z).length()
	var move := 0.0
	if dist173 < 5.0:
		if statue.idle != 2:
			statue.idle = 1
		state2 = 70.0 * 15.0
		path_timer = 0.0
		var limit := 2.0 if leader != null else 1.0
		if dist173 < limit:
			if leader == null:
				state3 += fps
				if state3 >= 70.0 * 15.0:
					statue.idle = 2
					statue.target_node = self
					say("SFX/Character/MTF/173/Box%d.ogg" % randi_range(1, 3))
			_face(statue.global_position)
			_finish_walking(fps)
		else:
			_face(statue.global_position)
			curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
			move = curr_speed * fps
			animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
	else:
		if statue.idle != 2:
			statue.idle = 0
		if path_timer <= 0.0:
			path_status = _find_path(statue.global_position + Vector3(0.0, 0.1, 0.0))
			path_timer = 70.0 * randf_range(6.0, 10.0)
		elif path_timer <= 70.0 * 2.5:
			path_timer -= fps
			curr_speed = 0.0
			_turn_randomly()
			_finish_walking(fps)
		elif path_status == 1:
			move = _walk_route(fps, facility, 1.0)
			path_timer -= fps
		else:
			path_timer -= fps * 2.0
			curr_speed = 0.0
			_turn_randomly()
			_finish_walking(fps)
	return move

func _follow_route(fps: float, facility: FacilityMap) -> float:
	var move := 0.0
	angle = _curve_angle(0.0, angle, 40.0, fps)
	# NPCs.bb 6195-6240: `dist` is only assigned in state 5, so it is 0 here; the far branch that hops along the route (Rand(20)) never
	# runs and the unit always walks, and the animation is never skipped for distance.
	if path_status == 2:
		state = 5
		curr_speed = 0.0
	elif path_status == 1:
		if path_location >= path.size():
			path_location = 0
			path_status = 0
			if last_seen > 0.0:
				state = 5
		else:
			_open_route_doors(facility, 1.0)
			var point := path[path_location]
			var gap := Vector2(point.x - global_position.x, point.z - global_position.z).length()
			_face_smooth(point, fps, 10.0)
			if idle == 0.0:
				curr_speed = _curve_value(speed * maxf(minf(gap, 1.0), 0.1), curr_speed, 20.0, fps)
				move = curr_speed * fps
				if gap < 0.5:
					path_location += 1
	else:
		curr_speed = 0.0
		state = 5
	if idle == 0.0 and path_status == 1:
		if frame > 959.0:
			animate(1376.0, 1383.0, 0.2, fps, false)
			if frame > 1382.9:
				set_frame(WALK.x)
		else:
			animate(WALK.x, WALK.y, curr_speed * 30.0, fps)
	else:
		if last_seen > 0.0:
			animate(78.0, 312.0, 0.2, fps)
		elif frame < 962.0:
			if frame > 487.0:
				set_frame(463.0)
			animate(463.0, 487.0, 0.3, fps, false)
			if frame > 486.9:
				set_frame(962.0)
		else:
			animate(962.0, 1259.0, 0.3, fps)
		curr_speed = _curve_value(0.0, curr_speed, 20.0, fps)
	angle = rotation.y
	return move

func _flee(fps: float, player: CharacterBody3D, facility: FacilityMap) -> float:
	var move := 0.0
	speed = 0.03
	state2 -= fps
	if state2 <= 0.0 or target == null or not is_instance_valid(target):
		state = 0
		return 0.0
	if _other_sees_me(target):
		state2 = 70.0 * 15.0
	var target_dist := global_position.distance_to(target.global_position)
	if target_dist > HIDE_DISTANCE and state2 > 70.0:
		state2 = 70.0
	if target_dist < 3.0 and state3 >= 0.0:
		state3 = 70.0 * 5.0
	if state3 > 0.0:
		# backs away facing it
		path_status = 0
		path_location = 0
		speed = 0.02
		_face(target.global_position)
		curr_speed = _curve_value(-speed, curr_speed, 20.0, fps)
		move = curr_speed * fps
		animate(WALK.y, WALK.x, curr_speed * 26.0, fps)
		path_timer = 1.0
		state3 = maxf(state3 - fps, 0.0)
		# a wall behind it: stop backing up
		var from := global_position + Vector3(0.0, 0.8, 0.0)
		var behind := PhysicsRayQueryParameters3D.create(from, from + global_transform.basis.z * 1.0)
		behind.collision_mask = 1
		behind.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(behind).is_empty():
			state3 = -70.0 * 2.0
	elif state3 < 0.0:
		state3 = minf(state3 + fps, 0.0)
	if path_timer <= 0.0:
		if leader != null and is_instance_valid(leader):
			path_status = _find_path(leader.global_position + Vector3(0.0, 0.1, 0.0))
		else:
			path_status = _find_path(_room_goal(target))
		if path_status == 1:
			_skip_behind()
		path_timer = 70.0 * 10.0
	elif path_status == 1:
		move = _walk_route(fps, facility, 2.0)
		path_timer -= fps
	else:
		path_timer = 0.0
	return move

func _look_at_spot(fps: float, player: CharacterBody3D) -> void:
	if global_position.distance_to(player.global_position) < HIDE_DISTANCE:
		animate(346.0, 351.0, 0.2, fps, false)
	var to_spot := enemy - global_position
	if absf(to_spot.x) < 55.0 and absf(to_spot.z) < 55.0 and absf(to_spot.y) < 20.0:
		rotation.y = _curve_angle(atan2(-to_spot.x, -to_spot.z), rotation.y, 30.0, fps)
	angle = rotation.y

func _shoot_as_zombie(fps: float, player: CharacterBody3D) -> void:
	_face(player.global_position)
	angle = rotation.y
	animate(346.0, 351.0, 0.2, fps, false)
	if reload <= 0.0 and not player.dead:
		if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), player.global_position + Vector3(0.0, 0.3, 0.0)):
			var to_player := player.global_position - global_position
			if absf(rad_to_deg(wrapf(atan2(-to_player.x, -to_player.z) - rotation.y, -PI, PI))) < 50.0:
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 15.0)
				shots_fired += 1
				Gunfire.shoot(self, _muzzle(), 0.9, "", false)
				reload = 7.0

func _just_shoot(fps: float) -> void:
	animate(346.0, 351.0, 0.2, fps, false)
	rotation.y = _curve_angle(deg_to_rad(state2), rotation.y, 20.0, fps)
	angle = rotation.y
	if reload <= 0.0:
		Gunfire.light_up(self)
		Sfx.play_at(self, "SFX/General/Gunshot.ogg", 20.0)
		shots_fired += 1
		Gunfire.flash(self, _muzzle())
		reload = 7.0

# ---- after the state --------------------------------------------------------------------------------------------------------

func _post_state(fps: float, before: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	if curr_speed > 0.01:
		if before > 500.0 and frame < 495.0:
			_step()
		elif before < 505.0 and frame >= 505.0:
			_step()
	if no_target and state == 1:
		state = 0
	# crowding: a unit too close to its leader steps aside; a leader pushes whoever is in front of him
	if state != 3 and state != 5 and state != 6 and state != 7:
		if leader != null and is_instance_valid(leader):
			if global_position.distance_to(leader.global_position) < 0.7:
				_face(leader.global_position)
				global_position += _forward(rotation.y - deg_to_rad(135.0)) * 0.01 * fps
		else:
			for other in get_tree().get_nodes_in_group("mtf"):
				if other == self or other.is_dead:
					continue
				if absf(rad_to_deg(_yaw_to(other.global_position))) < 80.0 and global_position.distance_to(other.global_position) < 0.7:
					other.global_position += _forward(rotation.y) * 0.01 * fps

# Blitz (Cos(yaw + 90), 0, Sin(yaw + 90)) is the way a body of that yaw faces; here, node forward (-Z).
func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

# MeNPCSeesPlayer: 0 nothing, 1 sight, 2 sound (3 camera: the camera check is not ported).
func _sees_player(player: CharacterBody3D) -> int:
	if no_target or player.dead:
		return 0
	if _facility().mtf.player_detected:
		# found by a security camera: units know where the player is, whatever the distance
		if global_position.distance_to(player.global_position) > 8.0 - player.crouch_state + player.sound_volume:
			return 3
		if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), player.camera.global_position):
			return 1
		return 2 if player.sound_volume > 1.0 else 3
	if blink_timer <= 0.0:
		return 0
	var dist := global_position.distance_to(player.global_position)
	if dist > 8.0 - player.crouch_state + player.sound_volume:
		return 0
	var visible := _visible_between(global_position + Vector3(0.0, 0.8, 0.0), player.global_position + Vector3(0.0, 0.3, 0.0))
	var off := absf(rad_to_deg(_yaw_to(player.global_position)))
	if player.sound_volume > 1.0:
		if off > 60.0 and visible:
			return 1
		elif not visible:
			return 2
	elif off > 60.0:
		return 0
	return 1 if visible else 0

# OtherNPCSeesMeNPC: the other one looks my way from less than 6 units.
func _other_sees_me(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	if "blink_timer" in other and other.blink_timer <= 0.0:
		return false
	if other.global_position.distance_to(global_position) < 6.0:
		var to_me := global_position - other.global_position
		var yaw := wrapf(atan2(-to_me.x, -to_me.z) - other.rotation.y, -PI, PI)
		return absf(rad_to_deg(yaw)) < 60.0
	return false

func _visible_between(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _statue() -> Node3D:
	var statue: Node3D = GameState.scp173
	return statue if statue != null and is_instance_valid(statue) else null

# The 173 / 106 / 049 checks of states 0 and 1 (zombies and SCP-096 are not in the game yet).
func _notice_scps(facility: FacilityMap, statue_voice: String, state0: bool) -> void:
	var statue := _statue()
	if statue != null and statue.idle < 2:
		var here := Vector2(statue.global_position.x, statue.global_position.z)
		var moved := 0.0 if _prev_173 == Vector2.INF else clampf(here.distance_to(_prev_173) * 2.5 / maxf(get_physics_process_delta_time() * 70.0, 0.001), 0.0, 1.0)
		_prev_173 = here
		if _other_sees_me(statue) or (moved > 0.0 and global_position.distance_to(statue.global_position) < 6.0):
			if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), statue.global_position + Vector3(0.0, 0.5, 0.0)) or moved > 0.0:
				state = 2
				enemy = statue.global_position
				state2 = 70.0 * 15.0
				state3 = 0.0
				path_timer = 0.0
				path_status = 0
				say(statue_voice)
	var scp106: Node = facility.scp106
	if scp106 != null and is_instance_valid(scp106) and scp106.state <= 0.0 and not scp106.idle:
		if _other_sees_me(scp106) or global_position.distance_to(scp106.global_position) < 3.0:
			if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), scp106.global_position + Vector3(0.0, 0.5, 0.0)):
				_flee_from(scp106, "SFX/Character/MTF/106/Spotted%d.ogg" % (randi_range(1, 3) if state0 else 4), state0)
	var scp096: Node = facility.scp096
	if scp096 != null and is_instance_valid(scp096) and _other_sees_me(scp096) and _visible_between(global_position + Vector3(0.0, 0.8, 0.0), scp096.global_position + Vector3(0.0, 0.5, 0.0)):
		state = 8
		enemy = scp096.global_position
		state2 = 70.0 * 15.0
		state3 = 0.0
		path_timer = 0.0
		path_status = 0
		say("SFX/Character/MTF/096/Spotted%d.ogg" % randi_range(1, 2))
		return
	var scp049: Node = facility.scp049
	if scp049 != null and is_instance_valid(scp049) and scp049.idle <= 0.1:
		if _other_sees_me(scp049) and _visible_between(global_position + Vector3(0.0, 0.8, 0.0), scp049.global_position + Vector3(0.0, 0.8, 0.0)):
			_flee_from(scp049, "SFX/Character/MTF/049/Spotted%d.ogg" % randi_range(1, 5), true)
			return
	# an SCP-008-1: shoot it (the original has no line for it yet)
	for zombie in facility.zombies008:
		if not is_instance_valid(zombie) or zombie.is_dead or zombie.state == 4:
			continue
		if _other_sees_me(zombie) and _visible_between(global_position + Vector3(0.0, 0.8, 0.0), zombie.global_position + Vector3(0.0, 0.5, 0.0)):
			state = 9
			enemy = zombie.global_position
			state2 = 70.0 * 15.0
			state3 = 0.0
			path_timer = 0.0
			path_status = 0
			target = zombie
			reload = 70.0 * 5.0
			return

# Case 9 of UpdateNPCs for an MTF unit: an SCP-008-1 (or 049-2) was seen. Backs away while it is within 1.3 and shoots it
# (5-10 HP a shot, 7 frames apart) until it drops; walks a route to it when it is out of sight.
func _shoot_zombie(fps: float, facility: FacilityMap) -> float:
	var move := 0.0
	if target == null or not is_instance_valid(target) or target.is_dead:
		target = null
		state = 0
		return 0.0
	if _visible_between(global_position + Vector3(0.0, 0.8, 0.0), target.global_position + Vector3(0.0, 0.5, 0.0)):
		_face_smooth(target.global_position, fps, 20.0)
		angle = rotation.y
		if global_position.distance_to(target.global_position) < 1.3:
			state3 = 70.0 * 2.0
		if state3 > 0.0:
			path_status = 0
			path_location = 0
			speed = 0.02
			curr_speed = _curve_value(-speed, curr_speed, 20.0, fps)
			move = curr_speed * fps
			animate(522.0, 488.0, curr_speed * 26.0, fps)
			path_timer = 1.0
			state3 = maxf(state3 - fps, 0.0)
		else:
			state3 = 0.0
			animate(346.0, 351.0, 0.2, fps, false)
		if reload <= 0.0 and not target.is_dead:
			var to_target: Vector3 = target.global_position - global_position
			if absf(rad_to_deg(wrapf(atan2(-to_target.x, -to_target.z) - rotation.y, -PI, PI))) < 50.0:
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 15.0)
				shots_fired += 1
				Gunfire.flash(self, _muzzle())
				if target.hp > 0.0:
					target.hp = maxf(target.hp - randf_range(5.0, 10.0), 0.0)
				else:
					if target.has_method("die"):
						target.die()
					target = null
					state = 0
					return 0.0
				reload = 7.0
		path_status = 0
	else:
		if path_timer <= 0.0:
			_find_path(target.global_position + Vector3(0.0, 0.1, 0.0))
			if path_status == 1:
				_skip_behind()
			path_timer = 70.0 * 10.0
		elif path_status == 1:
			move = _walk_route(fps, facility, 1.0)
			path_timer -= fps
		else:
			path_timer = 0.0
	return move

# Case 8 of UpdateNPCs for an MTF unit: SCP-096 was seen. The unit goes about its walk (the head turns away in the
# original) and snaps out of it once 096 is out of sight or more than 6 away.
func _look_away(fps: float, facility: FacilityMap) -> float:
	var move := _wander(fps, GameState.player, facility, true)
	var scp096: Node = facility.scp096
	if scp096 == null or not is_instance_valid(scp096) or not _visible_between(global_position + Vector3(0.0, 0.8, 0.0), scp096.global_position + Vector3(0.0, 0.5, 0.0)) or global_position.distance_to(scp096.global_position) > 6.0:
		state = 0
	return move

func _flee_from(scp: Node3D, voice: String, always_speak: bool) -> void:
	state = 4
	enemy = scp.global_position
	state2 = 70.0 * 15.0
	state3 = 0.0
	path_timer = 0.0
	path_status = 0
	target = scp
	if always_speak or leader == null:
		say(voice)

func _find_path(goal: Vector3) -> int:
	var facility := _facility()
	path.clear()
	path_location = 0
	_last_route_gap = 99.0
	if facility == null:
		path_status = 2
		return 2
	var result: Dictionary = facility.find_path(global_position, goal, true)
	path_status = int(result.status)
	var points: Array = result.points
	var kept := points.size() if points.size() <= 1 else mini(points.size() - 1, 19)   # Path[] holds 19 nodes from the start and never the end node (MapSystem.bb 6162-6176)
	for i in kept:
		path.append(points[i])
	return path_status

# The first waypoint is skipped when the second is nearer the way it faces.
func _skip_behind() -> void:
	if path.size() > 1:
		if absf(_yaw_to(path[0])) > absf(_yaw_to(path[1])):
			path_location = 1

# PathStatus = 1 in states 0, 1, 2, 4: walk to the next waypoint, open the door there.
func _walk_route(fps: float, facility: FacilityMap, door_distance: float) -> float:
	if path_location >= path.size():
		path_location = 0
		path_status = 0
		return 0.0
	var point := path[path_location]
	_face(point)
	curr_speed = _curve_value(speed, curr_speed, 20.0, fps)
	animate(WALK.x, WALK.y, curr_speed * 26.0, fps)
	_open_route_doors(facility, door_distance)
	var now := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	if now < 0.2 or (_last_route_gap < now and _last_route_gap < 1.0):
		path_location += 1
		_last_route_gap = 99.0
	else:
		_last_route_gap = now
	return curr_speed * fps

var _last_route_gap := 99.0

# Doors on the way open for it (any lock) and shut again after five seconds.
func _open_route_doors(facility: FacilityMap, distance: float) -> void:
	for node in facility.doors_near(global_position, 2.2):
		var door := node as Node3D
		if door == null or absf(door.global_position.y - global_position.y) > 2.0:
			continue
		var flat := Vector2(door.global_position.x - global_position.x, door.global_position.z - global_position.z)
		if flat.length() >= distance:
			continue
		var ahead := -global_transform.basis.z
		if Vector2(ahead.x, ahead.z).dot(flat.normalized()) < -0.2:
			continue
		if not door.open:
			say("SFX/Character/MTF/Beep.ogg", false)
		door.npc_open(70.0 * 5.0)

# NPCs.bb 5343-5349: the first room in creation order that is more than 12 away on x or z and passes the dice. The z term is
# written Abs(r\z - z / 8) in the original, so the dice are almost always 1 in 2. No room passing leaves the goal at the origin
# (x, y, z unset).
func _room_goal(avoid: Node3D = null) -> Vector3:
	for record in _facility().generator.rooms:
		var at: Vector3 = record.position
		var far := absf(at.x - global_position.x) > 12.0 or absf(at.z - global_position.z) > 12.0
		if far and randi_range(1, maxi(4 - int(absf(at.z - global_position.z / 8.0)), 2)) == 1:
			if avoid == null or at.distance_to(avoid.global_position) > 6.0:
				return Vector3(at.x, 0.1, at.z)
	return Vector3.ZERO

# Once 173 is boxed the leader takes it back to its chamber in the start room.
func _contain_goal(facility: FacilityMap, statue: Node3D) -> Vector3:
	var far_or_hidden := global_position.distance_to(statue.global_position) > 4.0 and not _visible_between(global_position + Vector3(0.0, 0.8, 0.0), statue.global_position + Vector3(0.0, 0.5, 0.0))
	if far_or_hidden:
		return statue.global_position + Vector3(0.0, 0.1, 0.0)
	var start: Node3D = facility.start_node
	var chamber := start.to_global(Vector3(4736.0 * RS, 0.5, -1692.0 * RS))
	var gap := Vector2(global_position.x - chamber.x, global_position.z - chamber.z).length()
	if statue.idle == 3 and gap > 4.0 and start.door_slots.has(1) and start.door_slots[1].open:
		start.door_slots[1].toggle()
	if gap > 3.5 and gap > 1.6:
		return Vector3(chamber.x, global_position.y + 0.1, chamber.z)
	if gap > 1.6:
		path_goal = chamber       # inside the chamber: walk straight to the middle
		return Vector3.INF
	statue.idle = 3
	statue.target_node = null
	statue.contained = true
	say("SFX/Character/MTF/173/Cont%d.ogg" % randi_range(1, 4))
	facility.mtf.play_announcement("SFX/Character/MTF/Announc173Contain.ogg")
	return Vector3.INF

# NPCs.bb 5884-5895: Rand(1, 3) = 1 on every waypoint (doors included) within 6 of the unit.
func _pick_nearby_waypoint(facility: FacilityMap) -> void:
	for id in facility.graph.point_ids():
		var point := facility.graph.position_of(id)
		if randi_range(1, 3) == 1 and global_position.distance_to(point) < 6.0:
			enemy = point
			path_timer = 0.0
			return

# NPCs.bb 6811-6815: a unit that fell through the floor shows up at a waypoint near it (TeleportMTFGroup is commented out in 1.3.11).
func _check_ground() -> void:
	if global_position.y < -10.0 and state != 6 and state != 7 and TeleportCloser.run(self):
		velocity = Vector3.ZERO
		path_status = 0
		path_timer = 0.0
		path_location = 0

func _gravity_step(delta: float, flat_velocity: Vector3) -> void:
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

# PointEntity n\Collider + RotateEntity 0: face the point at once.
func _face(point: Vector3) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() > 0.001:
		rotation.y = atan2(-flat.x, -flat.z)

func _face_smooth(point: Vector3, fps: float, smooth: float) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() > 0.001:
		rotation.y = _curve_angle(atan2(-flat.x, -flat.z), rotation.y, smooth, fps)

func _turn_randomly() -> void:
	if randi_range(1, 35) == 1:
		rotation.y = randf() * TAU

# n\Angle = CurveAngle(EntityYaw(collider), n\Angle, 20): the body lags behind the heading.
func _apply_angle(fps: float) -> void:
	angle = _curve_angle(rotation.y, angle, 20.0, fps)
	_visual.rotation = Vector3(MODEL_PITCH, angle - rotation.y, 0.0)

func _yaw_to(point: Vector3) -> float:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	return wrapf(atan2(-flat.x, -flat.z) - rotation.y, -PI, PI)

func _curve_angle(wanted: float, current: float, smooth: float, fps: float) -> float:
	return lerp_angle(current, wanted, minf(fps / smooth, 1.0))

func _curve_value(wanted: float, current: float, smooth: float, fps: float) -> float:
	var step := (wanted - current) * (fps / smooth)
	if wanted < current:
		return maxf(current + step, wanted)
	return minf(current + step, wanted)

func _muzzle() -> Vector3:
	var basis_yaw := Basis(Vector3.UP, rotation.y)
	return global_position + basis_yaw * Vector3(0.8 * 0.079, _visual.position.y + 10.75 * 0.079, -6.9 * 0.079)

func _step() -> void:
	steps_played += 1
	Sfx.play_at(self, "SFX/Character/MTF/Step%d.ogg" % randi_range(1, 3), 8.0, randf_range(0.5, 0.7))

# PlayMTFSound: what it says is heard around it (and logged for the tests).
func say(relative: String, log_it: bool = true) -> void:
	var source := Sfx.stream(relative)
	if log_it:
		voices.append(relative)
	if source != null:
		_voice.stream = source
		_voice.play()

# ---- animation (AnimateNPC / FinishWalking) --------------------------------------------------------------------------------------------

func _finish_walking(fps: float) -> void:
	var center := (WALK.y - WALK.x) / 2.0
	if frame >= center:
		animate(WALK.x, WALK.y, 0.015 * 26.0, fps, false)
	else:
		animate(WALK.y, WALK.x, -0.015 * 26.0, fps, false)

func animate(start: float, quit: float, anim_speed: float, fps: float, loop: bool = true) -> void:
	var new_time := frame
	if anim_speed > 0.0:
		new_time = maxf(minf(frame + anim_speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		if loop:
			new_time = frame + anim_speed * fps
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = maxf(minf(frame + anim_speed * fps, high), low)
	set_frame(new_time)

func set_frame(value: float) -> void:
	if absf(frame - value) < 0.001:
		return
	frame = value
	_visual.set_frame(frame)
