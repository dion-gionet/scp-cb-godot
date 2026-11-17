extends CharacterBody3D
# SCP-096, the Shy Guy (NPCs.bb UpdateNPCs, NPCtype096). Speed 9.0 / 100 a frame, scale 0.6 / 3, a sphere of 0.26.
#  state 0  sits crying (frames 936-1263, now and then the long one); when the player is in front of its face
#           on screen, in the line of sight and with open eyes (within 8) it is triggered; at the end of the long
#           cry it stands up (state 5)
#  state 1  triggered: gets up (frames 193-311 / 312-422, 677-736), then 2: the scream pose (737-822), 3: for 18 s
#  state 2  the same, a short way in; state 3 after 18 s goes on to 4
#  state 4  the chase: it screams (Scream.ogg, the chase music) and goes for the player (or the NPC in `target`); in the
#           open it runs at its speed, within 2.8 it jumps (frames 2-193 at 0.7) at twice the speed; at 1.0 it kills
#           (no hold off for anything but god mode); out of sight it plans a route every 5 s, tearing doors open
#  state 5  walks around slowly (1000-1600 frames of the timer) and turns to the player it sees; the player looking
#           at it (within 55 degrees of its face, on screen) triggers it (state 2)
#  state 6  put there by an event, doing nothing
# It is the only one of its kind (facility.scp096).


const SPEED := 9.0 / 100.0
const SCALE := 0.6 / 3.0
const RADIUS := 0.26
const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0
const KILL_MESSAGE := "A large amount of blood found in [DATA REDACTED]. DNA indentified as Subject D-9341. Most likely [DATA REDACTED] by SCP-096."

var state := 0
var state2 := 0.0
var state3 := 0.0            # a frame counter (state 0/3) or the millisecond deadline of the next sight check (state 4/5)
var frame := 936.0
var curr_speed := 0.0
var top_speed := SPEED * GameState.npc_speed_factor()
var angle := 0.0             # n\Angle (radians)
var last_seen := 0           # n\LastSeen: seen at the last check
var blink_timer := 1.0       # n\BlinkTimer: others see it
var target: Node = null      # n\Target: an NPC it chases instead of the player (events)
var path: Array[Vector3] = []
var path_status := 0
var path_location := 0
var path_timer := 0.0
var no_target := false
var kills := 0
var triggered_count := 0     # times the player's look set it off (tests)
var is_dead := false         # for the units that shoot at "targets"

var _visual: Node3D
var _scream: AudioStreamPlayer3D     # SoundChn
var _chase_music: AudioStreamPlayer  # SoundChn2
var _music_name := ""
var _killed_player := false

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp096")
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	body.shape = shape
	body.position.y = RADIUS
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/scp096.b3d"))
	_visual.scale = Vector3.ONE * SCALE
	_visual.position.y = RADIUS - 0.03       # PositionEntity obj, collider y - 0.03
	add_child(_visual)
	_visual.set_frame(frame)
	_scream = AudioStreamPlayer3D.new()
	_scream.max_distance = 10.0
	add_child(_scream)
	_chase_music = AudioStreamPlayer.new()
	add_child(_chase_music)
	angle = rotation.y

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	var move := 0.0
	match state:
		0:
			_sitting(fps, player, dist)
		1, 2, 3:
			_angered(fps, dist)
		4:
			move = _chase(fps, delta, player, facility, dist)
		5:
			move = _wander(fps, player, dist)
	_music_volume(dist)
	_gravity_step(delta, -global_transform.basis.z * move / maxf(delta, 0.0001))

func _sitting(fps: float, player: CharacterBody3D, dist: float) -> void:
	if dist >= 8.0:
		return
	GameState.give_achievement("096")
	_play_music("SFX/Music/096.ogg", 8.0)
	if state3 == -1.0:
		animate(936.0, 1263.0, 0.1, fps, false)
		if frame >= 1262.9:
			state = 5
			state3 = 0.0
			frame = 312.0
			_visual.set_frame(frame)
	else:
		animate(936.0, 1263.0, 0.1, fps)
		if state3 < 70.0 * 6.0:
			state3 += fps
		else:
			if randi_range(1, 5) == 1:
				state3 = -1.0
			else:
				state3 = 70.0 * randi_range(0, 3)
	if no_target:
		return
	var to_player := rad_to_deg(wrapf(_yaw_wanted(player.global_position) - rotation.y, -PI, PI))
	var front := absf(to_player) < 90.0
	if front and _on_screen(player, global_position + Vector3(0.0, 0.25, 0.0)) and _visible_from_player(player) and _eyes_open(player):
		_trigger(player, 194.0, 1)

func _angered(fps: float, dist: float) -> void:
	_play_music("SFX/Music/096Angered.ogg", 10.0)
	if state == 1:
		if frame < 312.0:
			animate(193.0, 311.0, 0.3, fps, false)
			if frame > 310.9:
				state = 2
				frame = 737.0
				_visual.set_frame(frame)
		elif frame >= 312.0 and frame <= 422.0:
			animate(312.0, 422.0, 0.3, fps, false)
			if frame > 421.9:
				frame = 677.0
				_visual.set_frame(frame)
		else:
			animate(677.0, 736.0, 0.3, fps, false)
			if frame > 735.9:
				state = 2
				frame = 737.0
				_visual.set_frame(frame)
	elif state == 2:
		animate(737.0, 822.0, 0.3, fps, false)
		if frame >= 822.0:
			state = 3
			state2 = 0.0
	elif state == 3:
		state2 += fps
		if state2 > 70.0 * 18.0:
			animate(823.0, 847.0, top_speed * 8.0, fps, false)
			if frame > 846.9:
				state = 4
				_stop_music()
		else:
			animate(737.0, 822.0, 0.3, fps)

func _chase(fps: float, delta: float, player: CharacterBody3D, facility: FacilityMap, dist: float) -> float:
	var move := 0.0
	player.camera_zoom = _curve_value(maxf(player.camera_zoom, (sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * 10.0), player.camera_zoom, 8.0, fps)
	if target == null or not is_instance_valid(target):
		target = null
		_play_scream()
		_play_chase_music(dist)
	if no_target and target == null:
		state = 5
		return 0.0
	if player.dead and not _killed_player:
		_killed_player = true
	if not player.dead:
		if GameState.clock_ms() > state3:
			last_seen = 0
			if target == null:
				if _visible_from_player(player):
					last_seen = 1
			elif _visible_between(target.global_position + Vector3(0.0, 0.5, 0.0), global_position + Vector3(0.0, 0.5, 0.0)):
				last_seen = 1
			state3 = GameState.clock_ms() + 3000.0
		if last_seen == 1:
			path_timer = maxf(70.0 * 3.0, path_timer)
			path_status = 0
			var aim: Vector3 = player.global_position if target == null else target.global_position
			if target != null:
				dist = global_position.distance_to(target.global_position)
			if dist < 2.8 or frame < 150.0:
				if frame > 193.0:
					frame = 2.0
					_visual.set_frame(frame)
				animate(2.0, 193.0, 0.7, fps)
				if dist > 1.0:
					curr_speed = _curve_value(top_speed * 2.0, curr_speed, 15.0, fps)
				else:
					curr_speed = 0.0
					if target == null and not GameState.god_mode and not player.dead:
						_kill_player(player)
				rotation.y = _yaw_wanted(aim)
			else:
				rotation.y = _curve_angle(_yaw_wanted(aim), rotation.y, 5.0, fps)
				if frame > 847.0:
					curr_speed = _curve_value(top_speed, curr_speed, 20.0, fps)
				if frame < 906.0:
					animate(737.0, 906.0, top_speed * 8.0, fps, false)
				else:
					animate(907.0, 935.0, curr_speed * 8.0, fps)
			move = curr_speed * fps
		else:
			move = _follow_route(fps, player, facility)
		if dist > 32.0 or global_position.y < -50.0:
			if randi_range(1, 50) == 1:
				teleport_closer()
	else:
		animate(minf(27.0, frame), 193.0, 0.5, fps)      # eating
	return move

func _follow_route(fps: float, player: CharacterBody3D, facility: FacilityMap) -> float:
	var move := 0.0
	if path_status == 1:
		while path_location < path.size() and path_location <= 19 and path[path_location] == Vector3.INF:
			path_location += 1
		if path_location >= path.size() or path_location > 19:
			path_location = 0
			path_status = 0
			return 0.0
		var point: Vector3 = path[path_location]
		rotation.y = _curve_angle(_yaw_wanted(point), rotation.y, 5.0, fps)
		if frame > 847.0:
			curr_speed = _curve_value(top_speed * 1.5, curr_speed, 15.0, fps)
		move = curr_speed * fps
		if frame < 906.0:
			animate(737.0, 906.0, top_speed * 8.0, fps, false)
		else:
			animate(907.0, 935.0, curr_speed * 8.0, fps)
		var flat := Vector2(point.x - global_position.x, point.z - global_position.z).length()
		if flat < 0.8:
			for node in facility.doors_near(point, 0.8):
				var door := node as Node3D
				if door != null and not door.open:
					door.fast_open = true
					door.open = true
					Sfx.play_at(door, "SFX/Door/DoorOpenFast.ogg", 10.0)
			if flat < 0.7:
				path_location += 1
	else:
		animate(737.0, 822.0, 0.2, fps)
		path_timer = maxf(0.0, path_timer - fps)
		if path_timer <= 0.0:
			var goal: Vector3 = player.global_position if target == null else target.global_position
			_find_path(goal + Vector3(0.0, 0.2, 0.0))
			path_timer = 70.0 * 5.0
	return move

func _wander(fps: float, player: CharacterBody3D, dist: float) -> float:
	var move := 0.0
	if dist >= 16.0:
		return 0.0
	_play_music("SFX/Music/096.ogg", 14.0)
	if frame >= 422.0:
		state2 += fps
		if state2 > 1000.0:
			if state2 > 1600.0:
				state2 = randf_range(0.0, 500.0)
			if frame < 1382.0:
				curr_speed = _curve_value(top_speed * 0.1, curr_speed, 5.0, fps)
				animate(1369.0, 1382.0, curr_speed * 45.0, fps, false)
			else:
				curr_speed = _curve_value(top_speed * 0.1, curr_speed, 5.0, fps)
				animate(1383.0, 1456.0, curr_speed * 45.0, fps)
			if GameState.clock_ms() > state3:
				last_seen = 0
				if _visible_from_player(player):
					last_seen = 1
				else:
					var ahead := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.5, 0.0), global_position + Vector3(0.0, 0.5, 0.0) + _forward() * 1.5)
					ahead.collision_mask = 1
					ahead.exclude = [get_rid()]
					if not get_world_3d().direct_space_state.intersect_ray(ahead).is_empty():
						angle = rotation.y + deg_to_rad(randf_range(80.0, 110.0))
				state3 = GameState.clock_ms() + 3000.0
			if last_seen == 1:
				rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 130.0, fps)
				if dist < 1.5:
					state2 = 0.0
			else:
				rotation.y = _curve_angle(angle, rotation.y, 50.0, fps)
		else:
			if frame > 472.0:
				curr_speed = _curve_value(top_speed * 0.05, curr_speed, 8.0, fps)
				animate(1383.0, 1469.0, curr_speed * 45.0, fps, false)
				if frame >= 1468.9:
					frame = 423.0
					_visual.set_frame(frame)
			else:
				curr_speed = _curve_value(0.0, curr_speed, 4.0, fps)
				animate(423.0, 471.0, 0.2, fps)
		move = curr_speed * fps
	else:
		animate(312.0, 422.0, 0.3, fps, false)
	if not no_target:
		var to_camera := rad_to_deg(wrapf(_yaw_wanted(player.camera.global_position) - rotation.y, -PI, PI))
		if absf(to_camera) < 55.0:
			var chest := Vector3(global_position.x, player.global_position.y + 5.8 * 0.2 - 0.25 + 0.0, global_position.z)
			if _on_screen(player, chest) and _visible_from_player(player) and _eyes_open(player):
				_trigger(player, 677.0 if frame >= 422.0 else frame, 2)
	return move

func _trigger(player: CharacterBody3D, new_frame: float, new_state: int) -> void:
	Sfx.play_global(self, "SFX/SCP/096/Triggered.ogg")
	player.camera_zoom = maxf(player.camera_zoom, 10.0)
	frame = new_frame
	_visual.set_frame(frame)
	_stop_music()
	state = new_state
	state3 = 0.0
	triggered_count += 1

func _kill_player(player: CharacterBody3D) -> void:
	Sfx.play_global(self, "SFX/Character/D9341/Damage5.ogg")
	player.camera_shake = 30.0
	GameState.blur_timer = 2000.0
	GameState.death_msg = KILL_MESSAGE
	kills += 1
	var floor_y := player.global_position.y
	for i in 7:
		var at := Vector3(player.global_position.x + randf_range(-0.1, 0.1), floor_y + 0.005, player.global_position.z + randf_range(-0.1, 0.1))
		var blood := GrowingDecal.make(get_parent(), at, "GFX/blooddrop%d.png" % randi_range(1, 2), randf_range(0.2, 0.6), 0.0, 1.0, false)
		blood.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	player.kill(KILL_MESSAGE)

# CameraProject inside the viewport (and in front of the camera)
func _on_screen(player: CharacterBody3D, point: Vector3) -> bool:
	return player.camera.is_position_in_frustum(point)

func _visible_from_player(player: CharacterBody3D) -> bool:
	return _visible_between(player.camera.global_position, global_position + Vector3(0.0, 0.5, 0.0))

func _eyes_open(player: CharacterBody3D) -> bool:
	return (player.blink_timer < -16.0 or player.blink_timer > -6.0) and not GameState.nvg_blinking

func _visible_between(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _play_music(file: String, max_distance: float) -> void:
	if _music_name == file and _scream.playing:
		return
	var stream := Sfx.stream(file)
	if stream == null:
		return
	stream.loop = true
	_scream.stream = stream
	_scream.max_distance = max_distance
	_scream.play()
	_music_name = file

func _stop_music() -> void:
	_scream.stop()
	_music_name = ""

func _play_scream() -> void:
	_play_music("SFX/SCP/096/Scream.ogg", 7.5)
	if not _chase_music.playing:
		var chase := Sfx.stream("SFX/Music/096Chase.ogg")
		if chase != null:
			chase.loop = true
			_chase_music.stream = chase
			_chase_music.play()

func _play_chase_music(dist: float) -> void:
	_chase_music.volume_db = linear_to_db(clampf(8.0 - dist, 0.6, 1.0))

func _music_volume(dist: float) -> void:
	if state == 4:
		_play_chase_music(dist)
	elif _chase_music.playing:
		_chase_music.stop()

func _find_path(goal: Vector3) -> int:
	var facility := _facility()
	path.clear()
	path_location = 0
	if facility == null:
		path_status = 2
		return path_status
	var result: Dictionary = facility.find_path(global_position, goal)
	path_status = int(result.status)
	for point in result.points:
		path.append(point)
	return path_status

func teleport_closer() -> void:
	if TeleportCloser.run(self):
		velocity = Vector3.ZERO
		path_status = 0
		path_timer = 0.0
		path_location = 0

func _forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))

func _yaw_wanted(point: Vector3) -> float:
	return atan2(-(point.x - global_position.x), -(point.z - global_position.z))

func _curve_angle(wanted: float, current: float, smooth: float, fps: float) -> float:
	return lerp_angle(current, wanted, minf(fps / smooth, 1.0))

func _curve_value(wanted: float, current: float, smooth: float, fps: float) -> float:
	var step := (wanted - current) * (fps / smooth)
	if wanted < current:
		return maxf(current + step, wanted)
	return minf(current + step, wanted)

func _gravity_step(delta: float, flat_velocity: Vector3) -> void:
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

# ---- animation (AnimateNPC) ---------------------------------------------------------------------------------------------------

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
