extends CharacterBody3D
# SCP-049 (NPCs.bb UpdateNPCs, NPCtype049). State 2 is the hunting state; the rules, in order:
#  - Idle > 0.1: hidden and counting down (not while the player is inside room049); at 0.1, when the
#    player is somewhere it can reach, it teleports to the first neighbour of the player's first adjacent room
#  - within 30 units (HideDistance * 2) and reachable: it hunts. If it sees the player (in front
#    within 60 degrees, or heard when loud) or saw them in the last 2 s it turns and walks at
#    them, and inside 0.5 it kills (a hazmat suit holds it off for a while)
#  - otherwise it follows a waypoint route to the player, opening doors, and every 5 s without
#    a route tries again, falling back to the nearest neighbouring room
#  - farther away: 1 in 3 per frame it teleports to a nearby waypoint at least 16 units from the
#    player, otherwise it goes idle for 60 s
#  - state 4: standing on the catwalk of room4 (put there by that room's event), watching the player
#    within 8 units until they walk off, then back to state 2 in the room under it
# The model is a static pose: the loader reads no skeleton, so it glides rather than walks.

const PathFollower = preload("res://scripts/npc/path_follower.gd")

const SPEED := 1.5 / 100.0 * 70.0         # NPCs.ini [SCP-049] speed 1.5 per frame at 70 fps
const MODEL_SCALE := 1.2                  # NPCs.ini [SCP-049] scale
const HIDE_DISTANCE := 15.0
const KILL_DISTANCE := 0.5
const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0
const KILL_MESSAGE := "An active instance of SCP-049-2 was discovered in [REDACTED]. Terminated by Nine-Tailed Fox."

var idle := 0.0              # n\Idle
var state := 2               # nState: 0 nothing (events), 1 looking around, 2 active, 3 killed the player, 4 on the room4 catwalk, 5 the room2sl scene
var state2 := 0.0            # attacks while above 0 (frames)
var state3 := 0.0            # nState3: the stage of the room2sl walk (6 = coming for the player)
var path_spot := Vector3.INF # PathX / PathZ: where the room2sl scene left it
var _route_clock := 0.0
var prev_state := 0          # n\PrevState: which voice line has played (0 none, 1 searching, 2 spotted, 3 hazmat)
var curr_speed := 0.0
var top_speed := SPEED * GameState.npc_speed_factor()
var path_timer := 0.0
var steps_played := 0
var spotted_count := 0

var _follower: Node
var _voice: AudioStreamPlayer3D
var _loop: AudioStreamPlayer3D
var _visual: Node3D            # B3DModel
var _frame := 37.0                # nFrame (the model's own frame numbers)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp049")
	floor_max_angle = deg_to_rad(70.0)    # the catwalk stairs of room2sl are collision ramps; the original sphere slides up them
	var body := CollisionShape3D.new()
	var sphere := CapsuleShape3D.new()   # EntityRadius 0.2
	sphere.radius = 0.2
	sphere.height = 0.4
	body.shape = sphere
	body.position.y = 0.2
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/scp-049.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	_visual.rotation.y = 0.0         # the skinned model already faces -Z, the node's forward
	_visual.position.y = -0.02
	add_child(_visual)
	_visual.set_frame(_frame)
	_follower = PathFollower.new()
	_follower.body = self
	_follower.speed = top_speed
	add_child(_follower)
	_follower.set_physics_process(false)
	_loop = AudioStreamPlayer3D.new()
	_loop.max_distance = 10.0
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 10.0
	add_child(_voice)
	var loop_stream := Sfx.stream("SFX/Horror/Horror12.ogg")
	if loop_stream != null:
		loop_stream.loop = true   # only 049 plays Horror12
		_loop.stream = loop_stream

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	visible = idle <= 0.1 and global_position.y > -400.0
	if _follower != null:
		_follower.hop_when_stuck = state == 5
	if idle > 0.1:
		_hidden(fps, player, facility)
		return
	if idle == 0.1:
		_try_appear(player, facility)
		return
	match state:
		1:
			state2 = 0.0
			_looking_around(fps)
		2:
			_active(fps, delta, dist, player, facility)
		5:
			_room2sl(fps, delta, dist, player, facility)
		3:
			_after_kill(fps, player)
		4:
			_on_catwalk(fps, delta, dist, player, facility)
	state2 = maxf(state2 - fps, 0.0)

func _hidden(fps: float, player: Node3D, facility: FacilityMap) -> void:
	if facility.room_name_at(player.global_position) != "room049":
		idle = maxf(idle - (1.0 + float(GameState.aggressive_npcs())) * fps, 0.1)
	_stop_sounds()
	velocity = Vector3.ZERO
	global_position = Vector3(player.global_position.x, -500.0, player.global_position.z)

# Idle = 0.1: as soon as the player is somewhere reachable it appears in the first neighbour (Adjacent order) of the first room
# next to theirs, which can be the player's own room.
func _try_appear(player: Node3D, facility: FacilityMap) -> void:
	if not facility.reachable_room(player.global_position):
		return
	var firsts: Array = facility.adjacent_records(facility.record_at(player.global_position))
	if firsts.is_empty():
		return
	var seconds: Array = facility.adjacent_records(firsts[0])
	if seconds.is_empty():
		return
	var spot := _room_floor(seconds[0])
	if spot != Vector3.INF:
		_place(spot)

func _place(spot: Vector3) -> void:
	global_position = spot + Vector3(0.0, 0.25, 0.0)
	velocity = Vector3.ZERO
	idle = 0.0
	path_timer = 0.0
	_clear_path()

# TeleportEntity(x, 0.5, z): the floor under a generated room's centre, from the room's own collision faces.
func _room_floor(record: Dictionary) -> Vector3:
	var room := _facility().rooms.get_room(record) as FacilityRoom
	if room == null:
		return Vector3.INF
	var centre := room.global_position
	return Vector3(centre.x, centre.y + room.floor_y(0.0, 0.0), centre.z)

func _looking_around(fps: float) -> void:
	if _frame >= 538.0:
		_set_frame(37.0)
		return
	_animate(37.0, 269.0, 0.7, fps, false)
	if _frame > 268.9:
		state = 2

func _active(fps: float, delta: float, dist: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var in_range: bool = dist < HIDE_DISTANCE * 2.0 and facility.reachable_room(player.global_position, true)
	if not in_range:
		_far(player, facility)
		return
	if not _loop.playing and _loop.stream != null:
		_loop.play()
	var seen := _sees_player(player) == 1
	if seen or state2 > 0.0:
		_attack(fps, delta, dist, player, seen)
	else:
		_follow_route(fps, delta, player, facility)

func _attack(fps: float, delta: float, dist: float, player: CharacterBody3D, seen: bool) -> void:
	GameState.give_achievement("049")
	if prev_state <= 1 and not _voice.playing:
		_speak("SFX/SCP/049/Spotted%d.ogg" % randi_range(1, 7))
		spotted_count += 1
		prev_state = 2
	_clear_path()
	path_timer = 0.0
	if seen:
		state2 = 70.0 * 2.0
	_turn_toward(player.global_position, fps)
	if dist < KILL_DISTANCE:
		curr_speed = 0.0
		_reach_player(fps, player)
		_gravity_step(delta, Vector3.ZERO)
		return
	if prev_state == 3:
		prev_state = 2
	curr_speed += (top_speed - curr_speed) * minf(fps / 20.0, 1.0)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if dist < 3.0:
		_animate(maxf(minf(_frame, 428.0), 387.0), 463.0, _walk_anim_speed(), fps)
	elif _frame > 428.0:
		_animate(minf(_frame, 463.0), 498.0, _walk_anim_speed(), fps, false)
		if _frame > 497.9:
			_set_frame(358.0)
	else:
		_animate(maxf(minf(_frame, 358.0), 346.0), 393.0, _walk_anim_speed(), fps)
	_gravity_step(delta, forward.normalized() * curr_speed)

# Inside kill range: a hazmat suit or the ring makes it work through it first (BlurTimer climbs 2.5 a frame, which also blurs
# the view), otherwise it kills.
func _reach_player(fps: float, player: CharacterBody3D) -> void:
	var s := GameState
	if s.wearing_hazmat > 0 or s.wearing_714:
		s.blur_timer += fps * 2.5
		if s.blur_timer > 250.0 and s.blur_timer - fps * 2.5 <= 250.0 and prev_state != 3:
			_play_global("SFX/SCP/049/TakeOffHazmat.ogg" if s.wearing_hazmat > 0 else "SFX/SCP/049/714Equipped.ogg")
			prev_state = 3
		elif s.blur_timer >= 500.0:
			if s.wearing_hazmat > 0:
				_wear_down_hazmat(player)
			else:
				s.wearing_714 = false
		return
	player.add_camera_zoom(20.0)
	s.blur_timer = 500.0
	if s.god_mode:
		return
	_play_global("SFX/Horror/Horror13.ogg")
	_speak("SFX/SCP/049/Kidnap%d.ogg" % randi_range(1, 2))
	state = 3
	var facility := _facility()
	if facility != null and facility.in_049_zone(player.global_position):
		# down in his own chamber he does not kill: the event lays the player down, wakes them as one of the infected (room049_event.gd)
		s.death_msg = "Three (3) active instances of SCP-049-2 discovered in the tunnel outside SCP-049's containment chamber. Terminated by Nine-Tailed Fox."
		facility.events.room049.state = -1.0
	else:
		player.kill(KILL_MESSAGE)

func _after_kill(fps: float, player: Node3D) -> void:
	_animate(537.0, 660.0, 0.7, fps, false)
	# stands over the body, facing the player
	var target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	global_position = global_position.lerp(target, minf(fps / 20.0, 1.0))
	rotation.y = lerp_angle(rotation.y, player.rotation.y + PI, minf(fps / 40.0, 1.0))

# State 4: standing on the catwalk of room4, turning to the player within 8; once they are beyond 12 he climbs down into the room
# under him and hunts.
func _on_catwalk(fps: float, delta: float, dist: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	if dist < 8.0:
		_animate(18.0, 19.0, 0.05, fps)
		_turn_toward(player.global_position, fps, 45.0)
		state3 = 1.0
	elif dist > HIDE_DISTANCE * 0.8 and state3 > 0.0:
		state = 2
		state3 = 0.0
		for record in facility.generator.rooms:
			if global_position.distance_to(record.position) < 4.0:
				global_position = record.position + Vector3(0.0, 0.1, 0.0)
				velocity = Vector3.ZERO
				break
	_gravity_step(delta, Vector3.ZERO)

func _follow_route(fps: float, delta: float, player: Node3D, facility: FacilityMap) -> void:
	if _follower.status == 1 and not _follower.has_arrived():
		curr_speed += (top_speed - curr_speed) * minf(fps / 20.0, 1.0)
		_follower.speed = curr_speed
		_follower.set_physics_process(true)
		_animate(maxf(minf(_frame, 358.0), 346.0), 393.0, _walk_anim_speed(), fps)
		if prev_state == 0 and not _voice.playing:
			_speak("SFX/SCP/049/Searching%d.ogg" % (7 if randi() % 30 == 0 else randi_range(1, 6)))
			prev_state = 1
		if randi() % 600 == 0 and not _voice.playing:
			prev_state = 0
		if prev_state > 1:
			prev_state = 1
		if _follower.stuck_time > 1.2:
			_clear_path()      # a door it cannot open: give up the route
			path_timer = 0.0
		return
	_clear_path()
	curr_speed = 0.0
	path_timer += fps
	if path_timer > 70.0 * (5.0 - 2.0 * float(GameState.aggressive_npcs())):
		path_timer = 0.0
		_find_route(player, facility)
	_gravity_step(delta, Vector3.ZERO)

# NPCs.bb 1890-1951: FindPath to the player; if there is none, to the nearest of the player's room and its neighbours, and then
# (the original repeats it three times, always with the same answer) to the neighbour's first neighbour that is not the player's room.
func _find_route(player: Node3D, facility: FacilityMap) -> void:
	if _try_route(player.global_position):
		return
	var here: Dictionary = facility.record_at(player.global_position)
	var neighbours: Array = facility.adjacent_records(here)
	var closest := here
	var closest_dist := global_position.distance_to(here.position)
	for record in neighbours:
		var d := global_position.distance_to(record.position)
		if d < closest_dist:
			closest_dist = d
			closest = record
	if _try_room_route(closest):
		return
	closest = here
	closest_dist = 100.0
	for first in neighbours:
		var d := global_position.distance_to(first.position)
		if d < closest_dist:
			closest_dist = d
			for second in facility.adjacent_records(first):
				if second.grid != here.grid:
					closest = second
					break
	_try_room_route(closest)

func _try_room_route(record: Dictionary) -> bool:
	var spot := _room_floor(record)
	return spot != Vector3.INF and _try_route(spot + Vector3(0.0, 0.5, 0.0))

func _try_route(target: Vector3) -> bool:
	var status: int = _follower.path_to(target)
	# a route of a single waypoint right under it is no route
	if status == 1 and _follower.points.size() <= 1 and global_position.distance_to(target) < 0.4:
		_clear_path()
		return false
	if status != 1:
		_clear_path()
		return false
	return true

func _clear_path() -> void:
	if _follower != null:
		_follower.points.clear()
		_follower.index = 0
		_follower.status = 0
		_follower.set_physics_process(false)

# Beyond range: teleport to a waypoint nearby that is at least 16 units from the player, or go idle.
func _far(player: Node3D, facility: FacilityMap) -> void:
	_stop_sounds()
	if not facility.reachable_room(player.global_position, true) or not facility.active or NpcGravity.in_facility(player.global_position.y) != 1:
		return
	if randi_range(1, 3 - GameState.other_factors()) == 1:
		_teleport_closer()
	else:
		idle = 60.0 * 70.0

func _teleport_closer() -> void:
	if TeleportCloser.run(self):
		velocity = Vector3.ZERO
		path_timer = 0.0
		_clear_path()

# MeNPCSeesPlayer: 0 not detected, 1 seen, 2 heard through a wall.
func _sees_player(player: CharacterBody3D) -> int:
	var dist := global_position.distance_to(player.global_position)
	if dist > 8.0 - player.crouch_state + player.sound_volume:
		return 0
	var visible_line := _line_to(player)
	var yaw_off := absf(rad_to_deg(_yaw_to(player.global_position)))
	if player.sound_volume > 1.0:
		if yaw_off > 60.0 and visible_line:
			return 1
		if not visible_line:
			return 2 if not player.crouching else 0
	else:
		if yaw_off > 60.0:
			return 0
	return 1 if visible_line else 0

# Angle (radians, -pi..pi) the NPC would turn to face the point: Blitz DeltaYaw.
func _yaw_to(point: Vector3) -> float:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	return wrapf(atan2(-flat.x, -flat.z) - rotation.y, -PI, PI)

func _line_to(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 0.3, 0.0)
	var to := player.global_position + Vector3(0.0, 0.3, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _turn_toward(point: Vector3, fps: float, smooth: float = 10.0) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() < 0.01:
		return
	var wanted := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, wanted, minf(fps / smooth, 1.0))   # CurveAngle

func _gravity_step(delta: float, flat_velocity: Vector3) -> void:
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

func _speak(relative: String) -> void:
	var source := Sfx.stream(relative)
	if source != null:
		_voice.stream = source
		_voice.play()

func _speak_at(relative: String, volume: float) -> void:
	Sfx.play_at(self, relative, 8.0, volume)

func _play_global(relative: String) -> void:
	Sfx.play_global(self, relative)

func _stop_sounds() -> void:
	if _loop != null and _loop.playing:
		_loop.stop()
	if _voice != null and _voice.playing:
		_voice.stop()

# ---- animation (AnimateNPC / SetNPCFrame) ---------------------------------------------------

# speed is in frames per 70 Hz frame, like the original; `fps` is the elapsed 70 Hz frames.
func _animate(start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	var new_time := _frame
	if speed > 0.0:
		new_time = maxf(minf(_frame + speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		if loop:
			new_time = _frame + speed * fps
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = maxf(minf(_frame + speed * fps, high), low)
	_set_frame(new_time)

func _set_frame(frame: float) -> void:
	if absf(_frame - frame) < 0.001:
		return
	var before := _frame
	_frame = frame
	_visual.set_frame(_frame)
	# footsteps land on fixed frames of the walk and run cycles
	if curr_speed > 0.005 * 70.0 * 0.05:
		for mark in [361.0, 377.0, 431.0, 447.0]:
			if before < mark and _frame >= mark:
				steps_played += 1
				_speak_at("SFX/SCP/049/Step%d.ogg" % randi_range(1, 3), randf_range(0.8, 1.0))
				break

# frames of walk speed: CurrSpeed (per 70 Hz frame) * 38
func _walk_anim_speed() -> float:
	return curr_speed / 70.0 * 38.0

# BlurTimer >= 500 in a suit below the best one: the first suit in the inventory wears one step (the blur drops back to 260 and the
# view shakes); worn through, it is gone. The best suit (level 3) is never damaged.
func _wear_down_hazmat(player: CharacterBody3D) -> void:
	if GameState.wearing_hazmat >= 3:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	for i in hud.items.size():
		if not str(hud.item_data[i].get("tempname", "")).contains("hazmatsuit"):
			continue
		var wear := int(hud.item_data[i].get("state2", 0))
		if wear < 3:
			hud.item_data[i]["state2"] = wear + 1
			GameState.blur_timer = 260.0
			player.camera_shake = 2.0
		else:
			if hud.selected == i:
				hud.deselect()
			hud.items[i] = ""
			hud.item_data[i] = {}
			GameState.wearing_hazmat = 0
		return

# ---- state 5: the room2sl scene (NPCs.bb "used for room2sl") --------------------------------------------

# Following a route the scene gave it: seen in front -> the hunt starts (state 2); heard behind a wall while
# on its way (state3 > 0) -> a route to the player; walks the route closing doors behind it; otherwise
# plays the pose of the voice line (prev_state 0 stands, 1 and 2 are the two scripted gestures).
func _room2sl(fps: float, delta: float, dist: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	if facility.room_name_at(player.global_position) == "room2sl":
		GameState.request_npc_music("049Chase")
	if not _loop.playing and _loop.stream != null:
		_loop.play()
	var seen := _sees_player(player)
	if seen == 1:
		state = 2
		_clear_path()
		path_timer = 0.0
		state3 = 0.0
		state2 = 70.0 * 2.0
		prev_state = 0
		_play_global("SFX/Room/Room2SL049Spawn.ogg")
		return
	elif seen == 2 and state3 > 0.0:
		_route_clock -= fps    # FindPath every frame in the original; every tenth is plenty here
		if _route_clock <= 0.0:
			_route_clock = 10.0
			_follower.path_to(player.global_position)
	elif state3 == 6.0:
		if dist > HIDE_DISTANCE:
			state = 2
			_clear_path()
			path_timer = 0.0
			state3 = 0.0
			prev_state = 0
			return
		elif not walking():
			_follower.path_to(player.global_position)
	if walking():
		curr_speed += (top_speed - curr_speed) * minf(fps / 20.0, 1.0)
		_follower.speed = curr_speed
		_follower.set_physics_process(true)
		_animate(maxf(minf(_frame, 358.0), 346.0), 393.0, _walk_anim_speed(), fps)
		_close_doors_behind()
	else:
		curr_speed = 0.0
		match prev_state:
			0:
				_animate(269.0, 345.0, 0.2, fps)
			1:
				_animate(661.0, 891.0, 0.4, fps, false)
			2:
				_animate(892.0, 1119.0, 0.4, fps, false)
		_gravity_step(delta, Vector3.ZERO)

# PathStatus = 1: a route is being walked.
func walking() -> bool:
	return _follower != null and _follower.status == 1 and not _follower.has_arrived()

func route_to(target: Vector3) -> int:
	return _follower.path_to(target)

func frame() -> float:
	return _frame

func say(relative: String) -> void:
	_speak(relative)

# "closes doors behind him": the waypoint it just left, if it is a door that needs no keycard.
func _close_doors_behind() -> void:
	if _follower.index <= 0 or _follower.index > _follower.points.size():
		return
	var left: Vector3 = _follower.points[_follower.index - 1]
	if left.distance_to(global_position) <= 0.3:
		return
	var facility := _facility()
	for node in facility.doors_near(left, 0.6):
		var door := node as Node3D
		if door != null and door.keycard == 0 and door.open and absf(door.global_position.y - left.y) < 1.0 and Vector2(door.global_position.x - left.x, door.global_position.z - left.z).length() < 0.6:
			door.toggle()
			_follower.keep_shut = door    # the walker's own "open what is within 1.6" would otherwise swing it open again next frame
