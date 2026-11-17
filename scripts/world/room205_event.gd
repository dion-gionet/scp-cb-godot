extends Node3D
# SCP-205's chamber (UpdateEvents.bb Case "room205", Main.bb QuickLoad "room205", MapSystem.bb FillRoom "room205"). The chamber's own
# camera (Objects[1] is its monitor's picture) shows a woman who sits, lies down and stands over 60 s (EventState 1, 3, 5), then three
# demons arrive one by one (7, 9, 11) and at 85 s they all dance (13). Every odd step is followed by an even one that makes the monitor
# flicker for 50 frames. Walking into the chamber (within 2 of Objects[0], the pivot the models stand on) before the end sends the
# demons at the player: the monitor flickers, they lunge (66), the picture goes off for good (67) and, from then on, 1 time in 150
# frames the player is knocked about in the dark (0.4-0.8 injuries, a thrown step) and dies at more than 5.
# The state is the event's EventState / EventState2 / EventState3 (`facility.ambient.state_of`, saved). The original loads the models on
# the first visit (behind a QuickLoad screen); here they are loaded with the room, so walking in does not freeze the game for half a
# second. Positions are raw numbers in the room's scaled space (z flipped here).

const RS := 8.0 / 2048.0

const DEATH := "The SCP-205 cycle seems to have resumed its normal course after the anomalies observed during [REDACTED]. The body of subject D-9341 was discovered inside the chamber. The subject exhibits signs of blunt force trauma typical for personnel who have entered the chamber when the lights are off."
const MODEL_SCALE := 0.05
const SPOT := Vector3(-6.0, 2.8516, -0.75)      # Objects[0], the pivot the models stand on

var room: FacilityRoom
var _models: Array[Node3D] = []        # Objects[3] demon 1, [4] demon 2, [5] demon 3, [6] the woman
var _frames: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _was_here := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	for file in ["205_demon1", "205_demon2", "205_demon3", "205_woman"]:
		var pivot := Node3D.new()
		add_child(pivot)
		var model := B3DModel.new()
		model.load_file(ContentPaths.existing_file("GFX/npcs/%s.b3d" % file))
		model.scale = Vector3.ONE * MODEL_SCALE
		model.rotation = Vector3(PI * 0.5, 0.0, 0.0)           # RotateEntity -90, yaw: the models lie on their backs
		pivot.add_child(model)
		pivot.position = SPOT
		pivot.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)
		pivot.visible = false
		_models.append(pivot)

func _spot() -> Vector3:
	return room.to_global(SPOT)

# Animate2: positive speeds only here
func _animate(index: int, start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	var new_time := maxf(minf(_frames[index] + speed * fps, quit), start)
	if loop and new_time >= quit:
		new_time = start
	_set_frame(index, new_time)

func _set_frame(index: int, value: float) -> void:
	_frames[index] = value
	(_models[index].get_child(0) as Node3D).call("set_frame", value)

func _show(index: int, on: bool) -> void:
	_models[index].visible = on

func _hide_all() -> void:
	for pivot in _models:
		pivot.visible = false

func _screen_node() -> Node3D:
	if room.cams.is_empty():
		return null
	var screen: Node3D = room.cams[0]._screen
	return screen if screen != null and is_instance_valid(screen) else null

func _screen_show(on: bool) -> void:
	var screen := _screen_node()
	if screen != null:
		screen.visible = on

func _exit_tree() -> void:
	if GameState.music_override == "205":
		GameState.music_override = ""

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active:
		return
	var fps := delta * 70.0
	var here: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if not here:
		var st_now: Dictionary = facility.ambient.state_of(room.room_key)
		if _was_here:
			_was_here = false
			_hide_all()
			if st_now.s < 66.0:
				_screen_show(true)
			if GameState.music_override == "205":
				GameState.music_override = ""
		return
	_was_here = true
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	var door_in: Node3D = room.door_slots.get(1)
	var door_chamber: Node3D = room.door_slots.get(0)
	if st.s == 0.0:
		_hide_all()
		if door_in != null and door_in.open:
			st.s = 1.0
			GameState.give_achievement("205")
		return
	GameState.music_override = "205"
	var spot := _spot()
	if st.s < 65.0:
		var flat := Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
		if flat < 2.0:
			Sfx.play_global(self, "SFX/SCP/205/Enter.ogg")
			st.s = maxf(st.s, 65.0)
			_show(0, true)
			_show(1, true)
			_show(2, true)
			_show(3, false)
			_set_frame(0, 492.0)
			_set_frame(1, 434.0)
			_set_frame(2, 434.0)
			if door_chamber != null:
				door_chamber.open = false
		if st.s > 7.0 and door_chamber != null and randf() < fps / 301.0:
			door_chamber.open = not door_chamber.open
		st.s2 += fps
	match int(st.s):
		1:
			_screen_show(true)
			_show(2, false)
			_show(1, false)
			_show(0, false)
			_show(3, true)                # sitting
			_animate(3, 526.0, 530.0, 0.2, fps)
			if st.s2 > 20.0 * 70.0:
				st.s += 1.0
		3:
			_screen_show(true)
			_show(2, false)
			_show(1, false)
			_show(0, false)
			_show(3, true)                # laying down
			_animate(3, 377.0, 525.0, 0.2, fps)
			if st.s2 > 30.0 * 70.0:
				st.s += 1.0
		5:
			_screen_show(true)
			_show(2, false)
			_show(1, false)
			_show(0, false)
			_show(3, true)                # standing
			_animate(3, 228.0, 376.0, 0.2, fps)
			if st.s2 > 40.0 * 70.0:
				st.s += 1.0
				Sfx.play_at(_models[3], "SFX/SCP/205/Horror.ogg", 10.0, 0.3)
		7:
			_screen_show(true)
			_show(3, true)
			_show(1, false)
			_show(0, false)
			_show(2, true)                # the first demon
			_animate(2, 500.0, 648.0, 0.2, fps)
			if st.s2 > 60.0 * 70.0:
				st.s += 1.0
				Sfx.play_at(_models[3], "SFX/SCP/205/Horror.ogg", 10.0, 0.5)
		9:
			_screen_show(true)
			_show(3, true)
			_show(2, true)
			_show(0, false)
			_show(1, true)                # the second demon
			_animate(1, 2.0, 200.0, 0.2, fps)
			_animate(2, 4.0, 125.0, 0.2, fps)
			if st.s2 > 80.0 * 70.0:
				st.s += 1.0
				Sfx.play_global(self, "SFX/SCP/205/Horror.ogg")
		11:
			_screen_show(true)
			_show(3, true)
			_show(2, true)
			_show(1, true)
			_show(0, true)                # the third demon
			_animate(0, 2.0, 226.0, 0.2, fps)
			_animate(1, 2.0, 200.0, 0.2, fps)
			_animate(2, 4.0, 125.0, 0.2, fps)
			if st.s2 > 85.0 * 70.0:
				st.s += 1.0
		13:
			_screen_show(true)
			for i in 4:
				_show(i, true)
			if _frames[3] != 227.0:
				_set_frame(3, 227.0)
			_animate(0, 2.0, 491.0, 0.05, fps)
			_animate(1, 197.0, 433.0, 0.05, fps)
			_animate(2, 2.0, 433.0, 0.05, fps)
		66:
			_screen_show(true)
			_animate(0, 492.0, 534.0, 0.1, fps, false)
			_animate(1, 434.0, 466.0, 0.1, fps, false)
			_animate(2, 434.0, 494.0, 0.1, fps, false)
			if _frames[0] > 533.0:
				st.s = 67.0
				st.s2 = 0.0
				st.s3 = 0.0
				_screen_show(false)
		67:
			if randf() < fps / 150.0:
				GameState.death_msg = DEATH
				GameState.injuries += randf_range(0.4, 0.8)
				Sfx.play_global(self, "SFX/Character/D9341/Damage%d.ogg" % randi_range(3, 4))
				player.camera_shake = 0.5
				st.s2 = randf_range(-0.1, 0.1)
				st.s3 = randf_range(-0.1, 0.1)
				if GameState.injuries > 5.0:
					player.kill(DEATH)
			# TranslateEntity(Collider, x, 0, z) in world axes (a Blitz z is a Godot -z)
			player.global_position += Vector3(st.s2, 0.0, -st.s3) * fps
			st.s2 = _curve(0.0, st.s2, 10.0, fps)
			st.s3 = _curve(0.0, st.s3, 10.0, fps)
		_:
			# the monitor flickers between the steps
			_screen_show(randi_range(1, 3) != 1)
			st.s3 += fps
			if st.s3 > 50.0:
				_screen_show(true)
				st.s += 1.0
				st.s3 = 0.0

func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps
