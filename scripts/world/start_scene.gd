extends Node
# The breach scene of the starting room (UpdateEvents.bb, event "alarm"). Coordinates are written
# in the room's own Blitz units (x, y, z; RoomScale units for x and z unless noted) and turned
# into world positions by B(), which flips z and goes through the room's transform.
#
# Setup: a scientist and Ulgrin (a guard) stand in the chamber; three bodies lie by the cell door
# (a guard and two Class D). The scene runs on `event_state`, which counts up while the player
# stands in the "173scene_timer" box and jumps to 500 in "173scene_activated":
#   >= 500   173 appears in the corridor
#   > 900    the scientist backs away ("What the..."); at 900 + 2.5 s Ulgrin backs away too
#   900 + 4 s  the lights flicker, 173 jumps from the corridor into the chamber behind Ulgrin; when
#            Ulgrin has left the room the door shuts, 173 jumps to the player if one is close, the
#            player is told to run
#   Ulgrin shoots the player at once when they are seen from the "173scene_end" box (the start room's
#   gunshot to the head), and the scene ends when the door has shut behind the guards.


const RS := MeshLoader.ROOM_SCALE

var room: Node3D
var door: Node3D                 # RoomDoors[5]: the door of the first neighbouring room
var event_state := 0.0
var event_state2 := 0            # 1 when the scene is over
var scientist: CharacterBody3D   # NPC[1]
var carried_guard: CharacterBody3D   # NPC[0] when the intro brought him
var ulgrin: CharacterBody3D      # NPC[2]
var bodies: Array[CharacterBody3D] = []
var desk: Node3D
var drawer: Node3D
var started := false
var message_shown := false
var light_blinks := 0
var commotion_played: Array[int] = []
var alarm_index := 0            # EventState3: the Alarm2_<n> clip last started
var _alarm_loop: AudioStreamPlayer
var _alarm_voice: AudioStreamPlayer
var _frame_start_state := 0.0   # EventState before this frame moved it: one-shot cues compare against it

func B(x: float, y: float, z: float) -> Vector3:
	return room.to_global(Vector3(x * RS, y, -z * RS))

# Blitz coordinates of a world point in the room: x and z in RoomScale units.
func local_blitz(world: Vector3) -> Vector3:
	var local := room.to_local(world)
	return Vector3(local.x / RS, local.y, -local.z / RS)

func begin(start_room: Node3D, neighbour_door: Node3D, adopt: Dictionary = {}) -> void:
	room = start_room
	door = neighbour_door
	if door != null:
		door.open = true
	_build_props()
	_populate(adopt)
	event_state = 1.0
	started = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if GameState.save_type() == 0:
			hud.message("Press F5 to save.", 4.0)
		elif GameState.save_type() == 1:
			hud.message("Saving is only permitted on clickable monitors scattered throughout the facility.", 8.0)

func save_data() -> Dictionary:
	return {"running": started, "event_state": event_state, "event_state2": event_state2, "message_shown": message_shown, "light_blinks": light_blinks, "commotion": commotion_played, "alarm_index": alarm_index}

# Loading a save: the scene carries on from the saved state. Its people come back as saved actors with a role, and nobody is spawned.
func resume(start_room: Node3D, neighbour_door: Node3D, saved: Dictionary) -> void:
	room = start_room
	door = neighbour_door
	event_state = float(saved.get("event_state", 1.0))
	event_state2 = int(saved.get("event_state2", 0))
	message_shown = bool(saved.get("message_shown", false))
	light_blinks = int(saved.get("light_blinks", 0))
	alarm_index = int(saved.get("alarm_index", 0))
	commotion_played.clear()
	for i in saved.get("commotion", []):
		commotion_played.append(int(i))
	_build_props()
	for human in (get_parent() as FacilityMap).humans:
		if not is_instance_valid(human):
			continue
		match str(human.get_meta("role", "")):
			"start_scientist":
				scientist = human
			"start_ulgrin":
				ulgrin = human
			"start_carried":
				carried_guard = human
			"start_body0", "start_body1", "start_body2":
				bodies.append(human)
	bodies.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_meta("role")) < str(b.get_meta("role")))
	if event_state2 == 0 and (scientist == null or ulgrin == null):
		event_state2 = 1
	started = true

# IntroDesk (272, 0, 400) and IntroDrawer (448, 0, 192): they sink into the floor later on.
func _build_props() -> void:
	desk = _prop("GFX/map/IntroDesk.b3d", Vector3(272.0, 0.0, 400.0))
	drawer = _prop("GFX/map/IntroDrawer.b3d", Vector3(448.0, 0.0, 192.0))

func _prop(relative: String, at: Vector3) -> Node3D:
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file(relative))
	var holder := MeshInstance3D.new()
	holder.mesh = mesh
	holder.scale = Vector3.ONE * RS
	room.add_child(holder)
	holder.position = Vector3(at.x * RS, at.y, -at.z * RS)
	return holder

func _populate(adopt: Dictionary = {}) -> void:
	var facility := get_parent() as FacilityMap
	var adopted_guard: CharacterBody3D = adopt.get("guard")
	if adopt.get("scientist") != null:
		scientist = adopt.scientist
		scientist.global_position = room.to_global(Vector3(0.0, 0.5, 1.0))
		scientist.velocity = Vector3.ZERO
	else:
		scientist = facility.spawn_human(HumanNpc.Kind.CLASS_D, room.to_global(Vector3(0.0, 0.5, 1.0)), 3)
	scientist.set_meta("role", "start_scientist")
	scientist.set_frame(210.0)
	if adopted_guard != null:
		adopted_guard.set_frame(74.0)
		adopted_guard.state = 8
		carried_guard = adopted_guard
		adopted_guard.set_meta("role", "start_carried")
	ulgrin = facility.spawn_human(HumanNpc.Kind.GUARD, room.to_global(Vector3(0.0, 0.5, -528.0 * RS)))
	ulgrin.set_meta("role", "start_ulgrin")
	ulgrin.state = 7
	var toward := scientist.global_position - ulgrin.global_position
	ulgrin.rotation.y = atan2(-toward.x, -toward.z)
	ulgrin.angle = rad_to_deg(ulgrin.rotation.y)
	if adopted_guard != null:
		return     # the intro's own dead are already here
	# the aftermath beside the cell door: a dead guard and two dead Class D
	var shift := Vector3(3712.0 * RS, 384.0 * RS, -1312.0 * RS)
	var guard_spot := Vector3(40.0 * RS, 460.0 * RS, -1072.0 * RS)
	var guard: CharacterBody3D = facility.spawn_human(HumanNpc.Kind.GUARD, Vector3.ZERO)
	guard.rotation.y = deg_to_rad(90.0)
	guard.set_frame(286.0)
	guard.state = 8
	var guard_local := guard_spot + Basis(Vector3.UP, deg_to_rad(90.0)) * Vector3(1.0, 0.0, 0.0)
	guard.global_position = room.to_global(shift + guard_local + Vector3(0.0, 0.4, 0.0))
	guard.rotation.y = room.rotation.y + deg_to_rad(90.0)
	guard.set_meta("role", "start_body0")
	bodies.append(guard)
	var d1: CharacterBody3D = facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3.ZERO, -1)
	d1.set_frame(19.0)
	d1.state = 3
	var d1_local := Vector3(-80.0 * RS, 100.0 * RS, -526.0 * RS) + Basis(Vector3.UP, deg_to_rad(270.0)) * Vector3(0.0, 0.0, -2.65)
	d1.global_position = room.to_global(shift + d1_local + Vector3(0.0, 0.4, 0.0))
	d1.rotation.y = room.rotation.y + deg_to_rad(270.0)
	d1.set_meta("role", "start_body1")
	bodies.append(d1)
	var d2: CharacterBody3D = facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3.ZERO, 6)
	d2.set_frame(19.0)
	d2.state = 3
	var d2_local := Vector3(-128.0 * RS, 100.0 * RS, -320.0 * RS) + Basis(Vector3.UP, deg_to_rad(270.0)) * Vector3(0.25, 0.0, -3.0)
	d2.global_position = room.to_global(shift + d2_local + Vector3(0.0, 0.4, 0.0))
	d2.rotation.y = room.rotation.y
	d2.set_meta("role", "start_body2")
	bodies.append(d2)

func _physics_process(delta: float) -> void:
	if not started:
		return
	var player: CharacterBody3D = GameState.player
	var statue: CharacterBody3D = GameState.scp173
	if player == null or statue == null or room == null or not is_instance_valid(room):
		return
	var fps := delta * 70.0
	_frame_start_state = event_state
	var trigger: String = room.trigger_at(player.global_position)
	if trigger == "173scene_timer":
		event_state += fps
	elif trigger == "173scene_activated":
		event_state = maxf(event_state, 500.0)
	if event_state < 850.0:
		_pin_173(statue, B(32.0, 0.0, 1072.0), 0.0, false)
	if event_state >= 500.0:
		event_state += fps
		_scene(fps, player, statue, trigger)
	if carried_guard != null and is_instance_valid(carried_guard):
		carried_guard.animate(249.0, 286.0, 0.4, fps, false)
	_sink_props()
	_alarm(player)
	_commotion(fps)

func _alarm(player: CharacterBody3D) -> void:
	if _alarm_loop == null:
		_alarm_loop = AudioStreamPlayer.new()
		_alarm_loop.stream = Sfx.stream("SFX/Alarm/Alarm.ogg")
		add_child(_alarm_loop)
		_alarm_voice = AudioStreamPlayer.new()
		add_child(_alarm_voice)
	if event_state < 2000.0 and _alarm_loop.stream != null and not _alarm_loop.playing:
		_alarm_loop.play()
	if alarm_index >= 11:
		return
	if not _alarm_voice.playing:
		alarm_index += 1
		var voice := Sfx.stream("SFX/Alarm/Alarm2_%d.ogg" % alarm_index)
		if voice != null:
			_alarm_voice.stream = voice
			_alarm_voice.play()
	elif alarm_index == 8:
		player.camera_shake = 1.0

# The facility in uproar (UpdateEvents.bb:316-340): the Blitz test adds one FPSfactor to an EventState that may already have moved twice this frame, so crossings can be skipped there too.
func _commotion(fps: float) -> void:
	if not (fposmod(event_state, 600.0) > 300.0 and fposmod(event_state + fps, 600.0) < 300.0):
		return
	var i := floori((event_state - 5000.0) / 600.0) + 1
	if i == 0:
		Sfx.play_global(self, "SFX/Room/Intro/PA/scripted/scripted6.ogg")
	elif i > 0 and i < 26:
		if not commotion_played.has(i):
			commotion_played.append(i)
			Sfx.play_global(self, "SFX/Room/Intro/Commotion/Commotion%d.ogg" % i)
	elif i > 26:
		if carried_guard != null and is_instance_valid(carried_guard):
			facility_remove(carried_guard)
		carried_guard = null
		if desk != null:
			desk.queue_free()
		if drawer != null:
			drawer.queue_free()
		desk = null
		drawer = null
		started = false

# Where 173 stands while the scene holds it (PositionEntity Curr173\Collider).
func _pin_173(statue: CharacterBody3D, spot: Vector3, yaw: float, shown: bool) -> void:
	statue.active = false
	statue.velocity = Vector3.ZERO
	statue.global_position = spot + Vector3(0.0, 0.01, 0.0)
	statue.floor_y = statue.global_position.y
	statue.visible = shown
	if yaw != 0.0:
		statue.rotation.y = room.rotation.y + deg_to_rad(yaw)

func _free_173(statue: CharacterBody3D) -> void:
	statue.visible = true
	statue.active = true

func _scene(fps: float, player: CharacterBody3D, statue: CharacterBody3D, trigger: String) -> void:
	if event_state2 != 0:
		return
	statue.visible = true
	var door_open: bool = door == null or door.open
	if event_state > 900.0 and door_open:
		if _frame_start_state <= 900.0:
			scientist.say("SFX/Room/Intro/WhatThe.ogg")
		scientist.state = 3
		scientist.curr_speed = scientist._curve_value(-0.008, scientist.curr_speed, 5.0, fps)
		scientist.animate(260.0, 236.0, scientist.curr_speed * 18.0, fps)
		scientist.rotation.y = room.rotation.y
		if event_state > 900.0 + 2.5 * 70.0:
			if ulgrin.state != 1:
				ulgrin.curr_speed = ulgrin._curve_value(-0.012, ulgrin.curr_speed, 5.0, fps)
				ulgrin.animate(39.0, 76.0, ulgrin.curr_speed * 40.0, fps)
				ulgrin.scene_move += ulgrin.curr_speed * fps
				ulgrin.state = 8
				var ulgrin_z := local_blitz(ulgrin.global_position).z
				if ulgrin_z < 0.0:
					var to_scientist := scientist.global_position - ulgrin.global_position
					ulgrin.rotation.y = lerp_angle(ulgrin.rotation.y, atan2(-to_scientist.x, -to_scientist.z) - PI, minf(fps / 15.0, 1.0))
				else:
					ulgrin.rotation.y = room.rotation.y
		if event_state < 900.0 + 4.0 * 70.0:
			_pin_173(statue, B(32.0, 0.0, 1072.0), 190.0, true)
			if event_state > 900.0 + 70.0 and event_state < 900.0 + 2.5 * 70.0:
				ulgrin.animate(1539.0, 1553.0, 0.2, fps, false)
				var to_173 := statue.global_position - ulgrin.global_position
				ulgrin.rotation.y = lerp_angle(ulgrin.rotation.y, atan2(-to_173.x, -to_173.z), minf(fps / 15.0, 1.0))
		else:
			if _frame_start_state < 900.0 + 4.0 * 70.0:
				Sfx.play_global(self, "SFX/Room/Intro/Light2.ogg")
				light_blinks += 1
				GameState.light_blink = 3.0
				_stone_drag_at(statue)
				var to_ulgrin := ulgrin.global_position - statue.global_position
				statue.rotation.y = atan2(-to_ulgrin.x, -to_ulgrin.z)
				if player.global_position.y < room.global_position.y + 320.0 * RS:
					player.blink_timer = -10.0
			_pin_173(statue, B(-96.0, 0.0, 592.0), 0.0, true)
			statue.rotation.y = room.rotation.y + deg_to_rad(190.0)
			if ulgrin.state != 1 and not player.dead:
				if local_blitz(ulgrin.global_position).z < -1150.0:
					if door != null:
						door.open = false
					light_blinks += 1
					GameState.light_blink = 3.0
					Sfx.play_global(self, "SFX/Room/Intro/Light2.ogg")
					player.blink_timer = -10.0
					_stone_drag_at(statue)
					if statue.global_position.distance_to(player.global_position) < 2.5 and absf(player.global_position.y - statue.global_position.y) < 1.0:
						statue.global_position = player.global_position
					else:
						statue.global_position = Vector3.ZERO   # PositionEntity Curr173Collider, 0, 0, 0: gone, and far enough to be teleported near the player later
					statue.velocity = Vector3.ZERO
					if not message_shown:
						message_shown = true
						var hud := get_tree().get_first_node_in_group("hud")
						if hud != null:
							hud.message("Hold %s to run." % _sprint_key(), 8.0)
		# Ulgrin shoots the player when he sees them from the end box
		if trigger == "173scene_end" and ulgrin._sees(player) and not ulgrin.no_target:
			ulgrin.state = 1
			ulgrin.state3 = 1.0
		elif ulgrin.state == 1 and not ulgrin._sees(player):
			ulgrin.state = 0
			ulgrin.state3 = 0.0
		if ulgrin.state == 1 and door != null:
			door.open = true
	else:
		if ulgrin.state != 1:
			if local_blitz(player.global_position).x < 1384.0:
				event_state = maxf(event_state, 900.0)
			if door == null or door.openstate == 0.0:
				facility_remove(scientist)
				facility_remove(ulgrin)
				scientist = null
				ulgrin = null
				event_state2 = 1
				_free_173(statue)

func facility_remove(human: Node) -> void:
	get_parent().remove_human(human)

func _stone_drag_at(statue: Node3D) -> void:
	Sfx.play_at(statue, "SFX/SCP/173/StoneDrag.ogg", 14.0)

func _sprint_key() -> String:
	for event in InputMap.action_get_events("sprint"):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "Shift"

func _sink_props() -> void:
	if desk != null:
		desk.position.y = -maxf(event_state - 1300.0, 0.0) / 4500.0
		desk.rotation = Vector3(deg_to_rad(-maxf(event_state - 1320.0, 0.0) / 130.0), 0.0, deg_to_rad(-maxf(event_state - 1300.0, 0.0) / 40.0))
	if drawer != null:
		drawer.position.y = -maxf(event_state - 1800.0, 0.0) / 5000.0
		drawer.rotation = Vector3(deg_to_rad(-maxf(event_state - 2040.0, 0.0) / 135.0), 0.0, deg_to_rad(-maxf(event_state - 2040.0, 0.0) / 43.0))
