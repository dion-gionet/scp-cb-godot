extends CharacterBody3D
# SCP-939 (NPCs.bb NPCtype939, UpdateNPCs). Three of them live in room3storage's lower level and are run by its event
# (room3storage_event.gd), which sets the patrol (`state2` = the waypoint it walks to, `prev_state` = the last waypoint of its loop,
# `waypoints` = the room's Objects). They go by sound, not sight:
#   0 idle   1 alerted (a heard step): stands up (frames 175-297), then walks on
#   2 patrols its three waypoints at 0.3 of its speed, now and then a lure call
#   3 hunts: runs (449-464) to where it last saw the player and bites (18-68, the blows at 24 and 57, 1.5-2.5 injuries each)
#   5 has killed: finishes the bite and settles    66 away from the player's level (does nothing)
# Heard within PlayerSoundVolume * 1.2 (or 1.5 m) it attacks, within * 1.6 it is alerted. `ignore_player` is set by the room's trigger boxes.


const SPEED := 4.0 / 100.0
const MODEL_SCALE := 0.5 / 2.5
const GRAVITY := 0.005 * 70.0 * 70.0
const DEATH := "\"All four (4) escaped SCP-939 specimens have been captured and recontained successfully. Three (3) of them made quite a mess at Storage Area 6. A cleaning team has been dispatched.\""

var index := 0                       # n\ID mod 3: picks the voice set
var state := 66
var state2 := 0
var prev_state := 0
var state3 := 0
var reload := 0.0
var last_seen := 0.0
var enemy := Vector2.ZERO            # EnemyX / EnemyZ (world x, z)
var curr_speed := 0.0
var ignore_player := false
var waypoints: Array = []
var frame := 290.0
var bites := 0                       # blows that landed (tests)
var top_speed := SPEED

var _visual: Node3D
var _voice: AudioStreamPlayer3D = null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp939")
	top_speed = SPEED * GameState.npc_speed_factor()
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	body.shape = shape
	body.position.y = 0.3
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/scp-939.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_visual.position = Vector3(0.0, 0.02, 0.0)
	add_child(_visual)
	_visual.set_frame(frame)

func save_state() -> Dictionary:
	return {"index": index, "state": state, "state2": state2, "prev_state": prev_state, "state3": state3, "reload": reload,
		"last_seen": last_seen, "enemy": [enemy.x, enemy.y], "curr_speed": curr_speed, "ignore": ignore_player, "frame": frame}

func load_state(data: Dictionary) -> void:
	index = int(data.index)
	state = int(data.state)
	state2 = int(data.state2)
	prev_state = int(data.prev_state)
	state3 = int(data.state3)
	reload = float(data.reload)
	last_seen = float(data.last_seen)
	enemy = Vector2(float(data.enemy[0]), float(data.enemy[1]))
	curr_speed = float(data.curr_speed)
	ignore_player = bool(data.ignore)
	_set_frame(float(data.frame))

func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps

func _turn_to(point: Vector2, smooth: float, fps: float) -> void:
	var flat := Vector2(point.x - global_position.x, point.y - global_position.z)
	if flat.length() < 0.0001:
		return
	rotation.y += wrapf(atan2(-flat.x, -flat.y) - rotation.y, -PI, PI) / maxf(smooth, 1.0) * fps

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

func _sees(player: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.3, 0.0), player.global_position + Vector3(0.0, 0.3, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _voice_playing() -> bool:
	return _voice != null and is_instance_valid(_voice) and _voice.playing

func _say(relative: String) -> void:
	if _voice != null and is_instance_valid(_voice):
		_voice.stop()
		_voice.queue_free()
	_voice = Sfx.play_at(self, relative, 10.0)

func _walk_step() -> void:
	Sfx.play_at(self, "SFX/Step/SCP/StepSCP%d.ogg" % randi_range(1, 4), 12.0)

func _run_step() -> void:
	Sfx.play_at(self, "SFX/Step/RunMetal%d.ogg" % randi_range(1, 8), 12.0)

func _move(fps: float, delta: float) -> void:
	var forward := -global_transform.basis.z
	velocity.x = forward.x * curr_speed * 70.0
	velocity.z = forward.z * curr_speed * 70.0
	NpcGravity.apply(self, delta, GRAVITY, 0.2 * 70.0)
	move_and_slide()

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null:
		return
	if str(facility.room_name_at(player.global_position)) != "room3storage":
		state = 66
	visible = state < 66
	if state >= 66:
		return
	var fps := delta * 70.0
	var before := frame
	var no_target: bool = GameState.no_target_mode()
	match state:
		0:
			_animate(290.0, 405.0, 0.1, fps)
		1:
			if frame >= 644.0 and frame < 683.0:
				curr_speed = _curve(top_speed * 0.05, curr_speed, 10.0, fps)
				_animate(644.0, 683.0, 28.0 * curr_speed * 4.0, fps, false)
				if frame >= 682.0:
					_set_frame(175.0)
			else:
				curr_speed = _curve(0.0, curr_speed, 5.0, fps)
				_animate(175.0, 297.0, 0.22, fps, false)
				if frame >= 296.0:
					state = 2
			last_seen = 0.0
			_move(fps, delta)
		2:
			_patrol(fps, delta, before)
		3:
			_hunt(player, fps, delta, before, no_target)
		5:
			if frame < 68.0:
				_animate(18.0, 68.0, 0.5, fps, false)
			else:
				_animate(464.0, 473.0, 0.5, fps, false)
	if state < 3 and not no_target and not ignore_player:
		_listen(player, fps)
	rotation.x = 0.0
	rotation.z = 0.0

func _patrol(fps: float, delta: float, before: float) -> void:
	state2 = maxi(state2, prev_state - 3)
	var target: Vector3 = waypoints[state2]
	var dist := (global_position + Vector3(0.0, 0.3, 0.0)).distance_to(target)
	curr_speed = _curve(top_speed * 0.3 * minf(dist, 1.0), curr_speed, 10.0, fps)
	_move(fps, delta)
	_animate(644.0, 683.0, 28.0 * curr_speed, fps)
	if (before < 664.0 and frame >= 664.0) or (before > 673.0 and frame < 654.0):
		_walk_step()
		if randi_range(1, 10) == 1 and not _voice_playing():
			_say("SFX/SCP/939/%dLure%d.ogg" % [index, randi_range(1, 10)])
	_turn_to(Vector2(target.x, target.z), 20.0, fps)
	if dist < 0.4:
		state2 += 1
		if state2 > prev_state:
			state2 = prev_state - 3
		state = 1

func _hunt(player: CharacterBody3D, fps: float, delta: float, before: float, no_target: bool) -> void:
	if _sees(player):
		enemy = Vector2(player.global_position.x, player.global_position.z)
		last_seen = 10.0 * 7.0
	if last_seen <= 0.0 or no_target:
		state = 2
		return
	var flat := Vector2(global_position.x, global_position.z)
	if frame >= 18.0 and frame < 68.0:
		curr_speed = _curve(0.0, curr_speed, 5.0, fps)
		_animate(18.0, 68.0, 0.5, fps)
		if (before < 24.0 and frame >= 24.0) or (before < 57.0 and frame >= 57.0):
			if enemy.distance_to(flat) < 1.5:
				Sfx.play_global(self, "SFX/General/Slash1.ogg")
				GameState.injuries += randf_range(1.5, 2.5) - GameState.wearing_vest * 0.5
				GameState.blur_timer = 500.0
				bites += 1
			else:
				_set_frame(449.0)
		if GameState.injuries > 4.0:
			GameState.death_msg = DEATH
			player.kill(DEATH)
			if not GameState.god_mode:
				state = 5
	else:
		if last_seen == 70.0:
			curr_speed = _curve(top_speed, curr_speed, 20.0, fps)
			_animate(449.0, 464.0, 6.0 * curr_speed, fps)
			if (before < 452.0 and frame >= 452.0) or (before < 459.0 and frame >= 459.0):
				_run_step()
			if enemy.distance_to(flat) < 1.1:
				_set_frame(18.0)
		else:
			curr_speed = _curve(0.0, curr_speed, 5.0, fps)
			_animate(175.0, 297.0, 5.0 * curr_speed, fps)
	_turn_to(enemy, 15.0, fps)
	_move(fps, delta)
	last_seen -= fps

func _listen(player: CharacterBody3D, fps: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist < 4.0 and _sees(player):
		dist -= 1.0
	if player.sound_volume * 1.2 > dist or dist < 1.5:
		if state3 == 0:
			_say("SFX/SCP/939/%dAttack%d.ogg" % [index, randi_range(1, 3)])
			Sfx.play_global(self, "SFX/SCP/939/attack.ogg")
			state3 = 1
		state = 3
	elif player.sound_volume * 1.6 > dist:
		if state != 1 and reload <= 0.0:
			_say("SFX/SCP/939/%dAlert%d.ogg" % [index, randi_range(1, 3)])
			_set_frame(175.0)
			reload = 70.0 * 3.0
		state = 1
	reload -= fps
