extends Node3D
# The tentacle of SCP-035 (NPCs.bb NPCtypeTentacle, UpdateNPCs): a fixed point on the floor, 035tentacle.b3d at 0.065.
#   0 spawn: waits (frame 283) until the player is within 2.5, then rises (frames 284-389 at 0.3) turning to the player, the heart
#     racing, with TentacleSpawn.ogg
#   1 idle (frames 33-174 at 0.3, looping) turning to the player (smooth 25), with TentacleIdle.ogg; within 1.8 and in front of
#     it (20 degrees) it strikes
#   2 attack: finishes the idle turn quickly, then frames 2-32 at 0.3; at frame 5 a blow within 1.8 and 20 degrees: 1-1.5 injuries
#     and a blur (a hazmat suit: 0-0.5), and above 3 injuries death; back to idle at frame 32
# It does nothing beyond HideDistance (15).


const MODEL_SCALE := 0.065
const HIDE_DISTANCE := 15.0

var state := 0
var frame := 283.0
var room_yaw_limit := NAN         # the second tentacle of the chamber may only face within a quarter of the room (the event sets the room's yaw)
var in_offices := false           # PlayerRoom is room2offices: the other death text
var _visual: Node3D
var _yaw := 0.0                   # the collider's yaw
var _idle_voice: AudioStreamPlayer3D = null
var _spawn_voice: AudioStreamPlayer = null

func _ready() -> void:
	add_to_group("tentacle")
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/035tentacle.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	_visual.rotation = Vector3(PI * 0.5, PI, 0.0)           # RotateEntity n\obj, pitch - 90, yaw - 180
	add_child(_visual)
	_visual.set_frame(frame)
	_yaw = rotation.y

func save_state() -> Dictionary:
	return {"state": state, "frame": frame, "offices": in_offices, "limit": -999.0 if is_nan(room_yaw_limit) else room_yaw_limit}

func load_state(data: Dictionary) -> void:
	state = int(data.state)
	in_offices = bool(data.offices)
	room_yaw_limit = NAN if float(data.limit) <= -998.0 else float(data.limit)
	frame = float(data.frame)
	_visual.set_frame(frame)
	_yaw = rotation.y

func face(yaw: float) -> void:
	_yaw = yaw
	rotation.y = yaw

func _exit_tree() -> void:
	_stop_voices()

func _stop_voices() -> void:
	for voice in [_idle_voice, _spawn_voice]:
		if voice != null and is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_idle_voice = null
	_spawn_voice = null

func _animate(start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	var new_time := maxf(minf(frame + speed * fps, quit), start)
	if loop and new_time >= quit:
		new_time = start
	_set_frame(new_time)

func _set_frame(value: float) -> void:
	if absf(frame - value) < 0.0001:
		return
	frame = value
	_visual.set_frame(frame)

# PointEntity, then RotateEntity the collider by CurveAngle(yaw, collider yaw, smooth)
func _turn_to(player: Node3D, smooth: float, fps: float) -> float:
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if flat.length() < 0.0001:
		return 0.0
	var yaw_to := atan2(-flat.x, -flat.y)
	_yaw += wrapf(yaw_to - _yaw, -PI, PI) / maxf(smooth, 1.0) * fps
	rotation.y = _yaw
	return rad_to_deg(wrapf(yaw_to - _yaw, -PI, PI))

# DeltaYaw(collider, player): how far the collider is from facing the player
func _delta_yaw(player: Node3D) -> float:
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if flat.length() < 0.0001:
		return 0.0
	return rad_to_deg(wrapf(atan2(-flat.x, -flat.y) - _yaw, -PI, PI))

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or not visible:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	if dist >= HIDE_DISTANCE:
		return
	_run(player, dist, fps)
	if not is_nan(room_yaw_limit):
		var room_deg := rad_to_deg(room_yaw_limit)
		var angle := fposmod(rad_to_deg(_yaw) - room_deg, 360.0)
		if angle > 90.0:
			if angle < 225.0:
				_yaw = deg_to_rad(room_deg - 89.0 - 180.0)
			else:
				_yaw = deg_to_rad(room_deg - 1.0)
			rotation.y = _yaw

func _run(player: CharacterBody3D, dist: float, fps: float) -> void:
	match state:
		0:
			if frame > 283.0:
				var audio := get_tree().get_first_node_in_group("audio")
				if audio != null:
					audio.heartbeat(1.0, 130.0)
				_turn_to(player, 25.0, fps)
				_animate(283.0, 389.0, 0.3, fps, false)
				if frame > 388.0:
					state = 1
					if _spawn_voice != null and is_instance_valid(_spawn_voice):
						_spawn_voice.stop()
			elif dist < 2.5:
				_set_frame(284.0)
				_spawn_voice = Sfx.play_global(self, "SFX/Room/035Chamber/TentacleSpawn.ogg")
		1:
			if _idle_voice == null or not is_instance_valid(_idle_voice):
				_idle_voice = Sfx.play_at(self, "SFX/Room/035Chamber/TentacleIdle.ogg", 10.0)
				if _idle_voice != null:
					_idle_voice.finished.connect(func() -> void: if is_instance_valid(_idle_voice): _idle_voice.play())
			if dist < 1.8 and absf(_delta_yaw(player)) < 20.0:
				state = 2
				if _idle_voice != null and is_instance_valid(_idle_voice):
					_idle_voice.stop()
			_turn_to(player, 25.0, fps)
			_animate(33.0, 174.0, 0.3, fps)
		2:
			# finish the idle animation before playing the attack animation
			if frame > 33.0 and frame < 174.0:
				_animate(33.0, 174.0, 2.0, fps, false)
			else:
				_turn_to(player, 10.0, fps)
				if frame > 33.0:
					_set_frame(2.0)
					Sfx.play_global(self, "SFX/Room/035Chamber/TentacleAttack%d.ogg" % randi_range(1, 2))
				_animate(2.0, 32.0, 0.3, fps, false)
				if frame >= 5.0 and frame < 6.0:
					if dist < 1.8 and absf(_delta_yaw(player)) < 20.0:
						_strike(player)
					_set_frame(6.0)
				elif frame == 32.0:
					state = 1
					_set_frame(173.0)

func _strike(player: CharacterBody3D) -> void:
	var s := GameState
	if s.wearing_hazmat != 0:
		s.injuries += randf() * 0.5
		Sfx.play_global(self, "SFX/General/BodyFall.ogg")
		return
	s.blur_timer = 100.0
	s.injuries += randf_range(1.0, 1.5)
	Sfx.play_global(self, "SFX/Character/D9341/Damage%d.ogg" % randi_range(3, 4))
	if s.injuries > 3.0:
		if in_offices:
			s.death_msg = "\"One large and highly active tentacle-like appendage seems to have grown outside the dead body of a scientist within office area [REDACTED]. Its level of aggression is unlike anything we've seen before - it looks like it has beaten some unfortunate Class D to death at some point during the breach.\""
		else:
			s.death_msg = "\"We will need more than the regular cleaning team to take care of this. Two large and highly active tentacle-like appendages seem to have formed inside the chamber. Their level of aggression is unlike anything we've seen before - it looks like they have beaten some unfortunate Class D to death at some point during the breach.\""
		player.kill(s.death_msg)
