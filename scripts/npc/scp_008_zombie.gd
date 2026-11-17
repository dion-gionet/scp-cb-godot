extends CharacterBody3D
# SCP-008-1, the infected surgeon (NPCs.bb NPCtype008, UpdateNPCs "Case NPCtype008"). 120 HP, speed 2.0 / 100, a model of
# 0.5 across. State: 0 lying by the wall (collides with nothing), 1 getting up (frames 11-32), 2 active, 3 attacking,
# 4 gone (it gave up while the player was far away).
#  - active: it sees the player (the usual NPC sight, it never blinks) or saw them in the last 2 s: it turns at them
#    and walks at 0.7 of its speed; within 1 and facing them it attacks. Otherwise it follows a route to the player,
#    re-planned every 5 s (1-2 frames of timer per frame, 1-4 when aggressive), opening doors, and stands swaying
#    (frames 323-344) in between. More than 15 from the player for 15 s (25 aggressive) and it is gone.
#  - attacking (frames 126-165): at frame 146 a hit within 1.1 and 60 degrees injures the player (0.4-1.0) and adds
#    1 to the infection (2 aggressive); then it keeps swinging while the player stays in front of it.
#  - gone: hidden until the player is somewhere reachable, then 1 in 50 (30) frames it reappears at a waypoint 4-12 from the player
#    on both axes whose room is within 15 (and farther than 4) of them.
#  - dead: frames 344-363.
# SCP-049-2 style units of the Nine-Tailed Fox shoot it on sight (mtf_unit.gd state 9).


const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0
const HIDE_DISTANCE := NpcGravity.HIDE_DISTANCE
const DEATH_MESSAGE := "Subject D-9341. Cause of death: multiple lacerations and severe blunt force trauma caused by [DATA EXPUNGED], who was infected with SCP-008. Said subject was located by Nine-Tailed Fox and terminated."

var state := 0
var state2 := 0.0            # the player-sight timer (frames)
var state3 := 0.0            # frames spent far from the player
var idle := 0.0
var hp := 120.0
var always_near := false     # NPCtype1499 falls at any distance (NPCs.bb 5002)
var is_dead := false
var frame := 11.0
var speed := 2.0 / 100.0
var curr_speed := 0.0
var blink_timer := 1.0       # n\BlinkTimer = 1: it never blinks (others see it)
var no_target := false
var path: Array[Vector3] = []
var path_status := 0
var path_location := 0
var path_timer := 0.0
var steps_played := 0
var hits := 0                # attacks that landed (tests)

var _visual: Node3D
var _body: CollisionShape3D
var _loop: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _dead_sound_stopped := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	add_to_group("scp008z")
	_body = CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	_body.shape = shape
	_body.position.y = shape.radius
	add_child(_body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/zombiesurgeon.b3d"))
	var width := 0.5
	if _visual.mesh_instance != null:
		width = _visual.mesh_instance.get_aabb().size.x
	_visual.scale = Vector3.ONE * (0.5 / maxf(width, 0.001))
	_visual.rotation.y = PI    # RotateEntity n\obj, 0, EntityYaw(n\Collider) - 180
	_visual.position.y = -0.2 + 0.2     # PositionEntity obj, collider y - 0.2 (the collider is 0.2 above the feet)
	add_child(_visual)
	_visual.set_frame(frame)
	_loop = AudioStreamPlayer3D.new()
	_loop.max_distance = 10.0
	var breath := Sfx.stream("SFX/SCP/049/0492Breath.ogg")
	if breath != null:
		breath.loop = true
		_loop.stream = breath
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 14.0
	add_child(_voice)
	set_state(state)

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

# n\State = x. The lying one is HIT_DEAD (nothing collides with it); the others are HIT_PLAYER.
func set_state(value: int) -> void:
	state = value
	collision_layer = 0 if state == 0 or is_dead else 4

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var move := 0.0
	var before := frame
	if is_dead:
		if not _dead_sound_stopped:
			_dead_sound_stopped = true
			_loop.stop()
		collision_layer = 0
		animate(344.0, 363.0, 0.5, fps, false)
		_gravity_step(delta, Vector3.ZERO)
		return
	match state:
		0:
			set_frame(11.0)
		1:
			animate(11.0, 32.0, 0.1, fps, false)
			if frame >= 29.0:
				set_state(2)
		2:
			move = _active(fps, player, facility, before)
		3:
			_attack(fps, player, before)
		4:
			_gone(fps, player, facility)
			return
	if state == 2 and not _loop.playing and global_position.distance_to(player.global_position) < 10.0:
		_loop.play()
	elif _loop.playing and (state != 2 or global_position.distance_to(player.global_position) >= 10.0):
		_loop.stop()
	_gravity_step(delta, -global_transform.basis.z * move / maxf(delta, 0.0001))

func _active(fps: float, player: CharacterBody3D, facility: FacilityMap, before: float) -> float:
	var move := 0.0
	var seen := _sees_player(player)
	if seen == 1 or state2 > 0.0:
		if seen == 1:
			state2 = 70.0 * 2.0
		else:
			state2 = maxf(state2 - fps, 0.0)
		rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 20.0, fps)
		animate(64.0, 93.0, curr_speed * 30.0, fps)
		curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
		move = curr_speed * fps
		if global_position.distance_to(player.global_position) < 1.0 and absf(rad_to_deg(_yaw_to(player.global_position))) <= 60.0:
			set_state(3)
		path_timer = 0.0
		path_status = 0
		path_location = 0
		state3 = 0.0
	else:
		if path_status == 1:
			move = _follow_route(fps, facility)
		else:
			animate(323.0, 344.0, 0.2, fps)
			curr_speed = 0.0
			if path_timer < 70.0 * 5.0:
				path_timer += randf_range(1.0, 2.0 + 2.0 * float(GameState.aggressive_npcs())) * fps
			else:
				_find_path(player.global_position)
				path_timer = 0.0
		if global_position.distance_to(player.global_position) > HIDE_DISTANCE:
			if state3 < 70.0 * (15.0 + 10.0 * float(GameState.aggressive_npcs())):
				state3 += fps
			else:
				state3 = 70.0 * 360.0
				_vanish()
	if curr_speed > 0.005:
		if (before < 80.0 and frame >= 80.0) or (before > 92.0 and frame < 65.0):
			_step()
	return move

func _follow_route(fps: float, facility: FacilityMap) -> float:
	while path_location < path.size() and path_location <= 19 and path[path_location] == Vector3.INF:
		path_location += 1
	if path_location >= path.size() or path_location > 19:
		path_location = 0
		path_status = 0
		return 0.0
	var point: Vector3 = path[path_location]
	rotation.y = _curve_angle(_yaw_wanted(point), rotation.y, 20.0, fps)
	animate(64.0, 93.0, curr_speed * 30.0, fps)
	curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
	var move := curr_speed * fps
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	# doors in front of it that are free to open
	if flat < 0.6:
		var blocked := false
		for node in facility.doors_near(point, 0.6):
			var door := node as Node3D
			if door == null or door.elevator:
				continue
			if door.locked or door.keycard != 0 or not door.code.is_empty():
				blocked = true
			elif not door.open and (door.openstate <= 0.0 or door.openstate >= 180.0):
				door.npc_open()
		if flat < 0.2 and not blocked:
			path_location += 1
		elif flat < 0.5 and blocked:
			path_status = 0
			path_timer = 0.0
	return move

func _attack(fps: float, player: CharacterBody3D, before: float) -> void:
	animate(126.0, 165.0, 0.4, fps, false)
	var near := global_position.distance_to(player.global_position) < 1.1
	var facing := absf(rad_to_deg(_yaw_to(player.global_position))) <= 60.0
	if frame >= 146.0 and before < 146.0:
		if near and facing:
			Sfx.play_global(self, "SFX/Character/D9341/Damage%d.ogg" % randi_range(5, 8))
			GameState.injuries += randf_range(0.4, 1.0)
			GameState.infect += 1.0 + float(GameState.aggressive_npcs())
			GameState.death_msg = DEATH_MESSAGE
			hits += 1
	elif frame >= 164.0:
		if near and facing:
			set_frame(126.0)
		else:
			set_state(2)

func _vanish() -> void:
	set_state(4)
	velocity = Vector3.ZERO
	_loop.stop()

func _gone(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	visible = false
	velocity = Vector3.ZERO
	global_position = Vector3(player.global_position.x, -500.0, player.global_position.z)
	if idle > 0.0:
		idle = maxf(idle - (1.0 + float(GameState.aggressive_npcs())) * fps, 0.0)
		return
	if not facility.reachable_room(player.global_position):
		return
	if randi_range(1, 50 - 20 * int(GameState.aggressive_npcs())) != 1:
		return
	var points := facility.waypoints()
	var rooms := facility.rooms.waypoint_rooms()
	for i in mini(points.size(), rooms.size()):
		var room_dist := RoomRegistry.room_dist(rooms[i].global_position, player.global_position)
		if room_dist >= HIDE_DISTANCE or randi() % 3 != 0:
			continue
		var d: Vector3 = points[i] - player.global_position
		if absf(d.x) > 4.0 and absf(d.x) < 12.0 and absf(d.z) > 4.0 and absf(d.z) < 12.0 and room_dist > 4.0:
			global_position = points[i] + Vector3(0.0, 0.25, 0.0)
			velocity = Vector3.ZERO
			path_status = 0
			path_timer = 0.0
			path_location = 0
			visible = true
			set_state(2)
			state3 = 0.0
			return

# MeNPCSeesPlayer: 1 in sight (front 60 degrees, or any way when loud, within 8 - crouch + noise), 2 heard.
func _sees_player(player: CharacterBody3D) -> int:
	if no_target or player.dead:
		return 0
	var dist := global_position.distance_to(player.global_position)
	if dist > 8.0 - player.crouch_state + player.sound_volume:
		return 0
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0.0, 0.3, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var visible_to := get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var off := absf(rad_to_deg(_yaw_to(player.global_position)))
	if player.sound_volume > 1.0:
		if off > 60.0 and visible_to:
			return 1
		elif not visible_to:
			return 2
	elif off > 60.0:
		return 0
	return 1 if visible_to else 0

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

func _yaw_wanted(point: Vector3) -> float:
	return atan2(-(point.x - global_position.x), -(point.z - global_position.z))

# DeltaYaw in radians (-pi..pi): the turn that would face the point.
func _yaw_to(point: Vector3) -> float:
	return wrapf(_yaw_wanted(point) - rotation.y, -PI, PI)

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
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL, 10.0, always_near)
	move_and_slide()

func _step() -> void:
	steps_played += 1
	Sfx.play_at(self, "SFX/Step/Step%d.ogg" % randi_range(1, 8), 8.0, randf_range(0.3, 0.5))

# SetNPCFrame(target, 133) and IsDead: shot dead by the Nine-Tailed Fox.
func die() -> void:
	is_dead = true
	set_frame(133.0)
	collision_layer = 0

# ---- animation (AnimateNPC) -----------------------------------------------------------------------------------

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
