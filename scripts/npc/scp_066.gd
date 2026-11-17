extends CharacterBody3D
# SCP-066 (NPCs.bb NPCtype066, UpdateNPCs): a ball that turns its face (frames 2-450 spin through 360 degrees) to look at the player.
#   0 idle: while the player is farther than 20 it hops to a nearby waypoint every 5 s; within 8 it stares (1)
#   1 stares, now and then calling "Eric"; when the player is closer than 1 + LastDist (1 to 2.5) it goes to 2 or 3
#   2 turns its face up, rolls at the player (backwards, as it faces away) and at the player does one of six things (Eric / Notes
#     and: Beethoven that deafens the player, darkness, every free door nearby flipping, a thump that hurts), then goes to 3
#   3 rolls off in a wandering line for 250 frames and rolls to a stop, back to 0
# While 2 or 3 the rolling sound follows it. Darkness (State3) dims the light and quickens the heart.


const SPEED := 2.0 / 100.0
const MODEL_SCALE := 0.17 / 2.5
const GRAVITY := 0.005 * 70.0 * 70.0

var state := 0
var state2 := 0.0
var state3 := 0.0
var frame := 2.0
var curr_speed := 0.0
var last_dist := 1.5
var angle := 0.0                # n\Angle, degrees
var hop_at := 0.0               # the clock (ms) of the next hop
var _visual: Node3D
var _rolling: AudioStreamPlayer3D = null
var _beethoven: AudioStreamPlayer3D = null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp066")
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	body.shape = shape
	body.position.y = 0.2
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/scp-066.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(_visual)
	_visual.set_frame(frame)

func save_state() -> Dictionary:
	return {"state": state, "state2": state2, "state3": state3, "frame": frame, "curr_speed": curr_speed, "last_dist": last_dist, "angle": angle}

func load_state(data: Dictionary) -> void:
	state = int(data.state)
	state2 = float(data.state2)
	state3 = float(data.state3)
	curr_speed = float(data.curr_speed)
	last_dist = float(data.last_dist)
	angle = float(data.angle)
	_set_frame(float(data.frame))

func _exit_tree() -> void:
	for voice in [_rolling, _beethoven]:
		if voice != null and is_instance_valid(voice):
			voice.stop()

func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps

func _set_frame(value: float) -> void:
	if absf(frame - value) < 0.0001:
		return
	frame = value
	_visual.set_frame(frame)

func _animate(start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	var new_time := frame
	if speed > 0.0:
		new_time = maxf(minf(frame + speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		new_time = frame + speed * fps
		if loop:
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = clampf(new_time, low, high)
	_set_frame(new_time)

func _yaw_to(point: Vector3) -> float:
	return atan2(-(point.x - global_position.x), -(point.z - global_position.z))

# DeltaYaw(collider, player) in degrees (positive = the player is to the left)
func _delta_yaw(player: Node3D) -> float:
	return rad_to_deg(wrapf(_yaw_to(player.global_position) - rotation.y, -PI, PI))

func _turn(target_yaw: float, smooth: float, fps: float) -> void:
	rotation.y += wrapf(target_yaw - rotation.y, -PI, PI) / maxf(smooth, 1.0) * fps

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	var dist := flat.length()
	match state:
		0:
			if dist > 20.0:
				_animate(451.0, 612.0, 0.2, fps)
				if GameState.clock_ms() > hop_at:
					_hop(facility)
					hop_at = GameState.clock_ms() + 5000.0
			elif dist < 8.0:
				last_dist = randf_range(1.0, 2.5)
				state = 1
		1:
			if frame < 451.0:
				var current := (frame - 2.0) / 1.2445
				var face_angle := fposmod(current + wrapf(_delta_yaw(player) - 180.0 - current, -180.0, 180.0) / 15.0 * fps, 360.0)
				_set_frame(face_angle * 1.2445 + 2.0)
			else:
				_animate(636.0, 646.0, 0.4, fps, false)
				if frame == 646.0:
					_set_frame(2.0)
			if randf() < fps / 700.0:
				Sfx.play_at(self, "SFX/SCP/066/Eric%d.ogg" % randi_range(1, 3), 8.0)
			if dist < 1.0 + last_dist:
				state = randi_range(2, 3)
		2:
			_roll_at(player, dist, fps, delta)
		3:
			_roll_off(player, fps, delta)
	if state > 1:
		if _rolling == null or not is_instance_valid(_rolling):
			_rolling = Sfx.play_at(self, "SFX/SCP/066/Rolling.ogg", 20.0)
			if _rolling != null:
				_rolling.finished.connect(func() -> void: if is_instance_valid(_rolling): _rolling.play())
	if state3 > 0.0:
		state3 -= fps
		GameState.light_dim = minf(maxf(state3 / 500.0, 0.01), 0.6)
		var audio := get_tree().get_first_node_in_group("audio")
		if audio != null:
			audio.heartbeat(minf(state3 / 1000.0, 1.0), 130.0)
	if _beethoven != null and is_instance_valid(_beethoven) and _beethoven.playing:
		GameState.blur_timer = maxf(GameState.blur_timer, maxf((5.0 - dist) * 300.0, 0.0))

func _hop(facility: FacilityMap) -> void:
	var graph = facility.graph
	for id in graph.point_ids():
		if graph.is_door_point(id):
			continue
		var at: Vector3 = graph.position_of(id)
		if absf(at.x - global_position.x) < 4.0 and absf(at.z - global_position.z) < 4.0:
			global_position = Vector3(at.x, at.y + 0.3, at.z)
			velocity = Vector3.ZERO
			return

func _roll_at(player: CharacterBody3D, _dist: float, fps: float, delta: float) -> void:
	if frame < 647.0:
		var current := (frame - 2.0) / 1.2445
		var face_angle := fposmod(current + wrapf(0.0 - current, -180.0, 180.0) / 5.0 * fps, 360.0)
		if face_angle < 5.0 or face_angle > 355.0:
			_set_frame(647.0)
		else:
			_set_frame(face_angle * 1.2445 + 2.0)
		return
	if frame == 683.0:
		if state2 == 0.0:
			_arrive(player)
		state2 += fps
		if state2 > 70.0:
			state = 3
			state2 = 0.0
	else:
		curr_speed = _curve(SPEED * 1.5, curr_speed, 10.0, fps)
		_turn(_yaw_to(player.global_position) + PI, 10.0, fps)
		_animate(647.0, 683.0, curr_speed * 25.0, fps, false)
		var back := global_transform.basis.z
		velocity.x = back.x * curr_speed * 70.0
		velocity.z = back.z * curr_speed * 70.0
		NpcGravity.apply(self, delta, GRAVITY, 0.2 * 70.0)
		move_and_slide()

func _arrive(player: CharacterBody3D) -> void:
	if randi_range(1, 2) == 1:
		Sfx.play_at(self, "SFX/SCP/066/Eric%d.ogg" % randi_range(1, 3), 8.0)
	else:
		Sfx.play_at(self, "SFX/SCP/066/Notes%d.ogg" % randi_range(1, 6), 8.0)
	match randi_range(1, 6):
		1:
			_beethoven = Sfx.play_at(self, "SFX/SCP/066/Beethoven.ogg", 20.0)
			GameState.deaf_timer = 70.0 * (45.0 + 15.0 * (1.0 if GameState.aggressive_npcs() else 0.0))
			player.camera_shake = 10.0
		2:
			state3 = randf_range(700.0, 1400.0)
		3:
			var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
			for door in facility.doors_near(global_position, 24.0):
				if not door.locked and door.keycard == 0 and door.code == "" and absf(door.global_position.x - global_position.x) < 16.0 and absf(door.global_position.z - global_position.z) < 16.0:
					door.toggle(false)
		4:
			var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
			if facility.generator.room_disables_decals(facility.room_name_at(player.global_position)):
				return
			player.camera_shake = 5.0
			# 1.0, not the original's de\Size: nothing calls ScaleSprite with it, so the sprite keeps scale 1 (until a saved game is loaded, Save.bb 999)
			GrowingDecal.make(get_parent(), Vector3(global_position.x, global_position.y + 0.01, global_position.z), "GFX/decal2.png", 1.0, 0.0, 0.8, false)
			Sfx.play_global(self, "SFX/General/BodyFall.ogg")
			if Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() < 0.8:
				GameState.injuries += randf_range(0.3, 0.5)

func _roll_off(player: CharacterBody3D, fps: float, delta: float) -> void:
	_turn(_yaw_to(player.global_position) + deg_to_rad(angle) + PI, 10.0, fps)
	curr_speed = _curve(SPEED, curr_speed, 10.0, fps)
	var forward := -global_transform.basis.z
	velocity.x = forward.x * curr_speed * 70.0
	velocity.z = forward.z * curr_speed * 70.0
	NpcGravity.apply(self, delta, GRAVITY, 0.2 * 70.0)
	move_and_slide()
	if randf() < fps / 100.0:
		angle = randf_range(-20.0, 20.0)
	state2 += fps
	if state2 > 250.0:
		_animate(684.0, 647.0, -curr_speed * 25.0, fps, false)
		if frame == 647.0:
			state = 0
			state2 = 0.0
	else:
		_animate(684.0, 647.0, -curr_speed * 25.0, fps)
