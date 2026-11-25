extends Node
# The intro (UpdateEvents.bb, event "173"): waking up in the Class D cell, the escort to SCP-173's
# chamber, the demonstration that goes wrong and the breach that carries on in the start room.
# Variable names follow the original: event_state (EventState), event_state2, event_state3,
# event_str (EventStr). The room sits at the world origin; x and z are in RoomScale units (suffix
# `rs`) the way the source writes them, y in metres. NPC[0..10] keep their original numbers:
#   0 guard on the balcony, 1 and 2 the Class D of the demonstration, 3 Ulgrin (the escort),
#   4 the second escort guard, 5 the guard in the far hall, 6 Franklin (the scientist in the chamber),
#   7 the scientist at his desk, 8 and 10 guards and 9 a Class D in the lower hall


signal finished

const RS := MeshLoader.ROOM_SCALE

var room: Node3D                 # the intro room (chamber.gd)
var facility: FacilityMap
var player: CharacterBody3D
var statue: CharacterBody3D
var npc: Array = []              # NPC[0..10]
var started := false
var done := false
var event_state := 0.0
var event_state2 := 0
var event_state3 := 0.0
var event_str := ""
var _pa: AudioStreamPlayer
var _ambience: AudioStreamPlayer3D
var _voices: Dictionary = {}     # npc index * 10 + slot -> AudioStreamPlayer3D
var _voice_end: Dictionary = {}  # the same keys -> game time (ms) a clip ends: logic follows game time, not the audio device
var _pa_end := 0.0
var _wake_started := false
var _frame_start_state := 0.0
var _see_173_played := false
var _gas_emitters: Array = []
var _terminated_played := false
var test_interact := false        # a test presses the interact key for the document

func begin(chamber: Node3D, facility_node: Node) -> void:
	room = chamber
	facility = facility_node
	facility.intro_active = true
	player = GameState.player
	statue = GameState.scp173
	npc.resize(11)
	started = true

# A point of the room: x, z in RoomScale units, y in metres.
func at(x_rs: float, y: float, z_rs: float) -> Vector3:
	return room.to_global(Vector3(x_rs * RS, y, -z_rs * RS))

# The room's own x and z (RoomScale units) of a world point.
func rs_of(world: Vector3) -> Vector2:
	var local := room.to_local(world)
	return Vector2(local.x / RS, -local.z / RS)

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _spawn(kind: int, pos: Vector3, texture: int = -1) -> CharacterBody3D:
	return facility.spawn_human(kind, pos, texture)

func door(slot: int) -> Node3D:
	return room.door_slots.get(slot)

# UseDoor(d, False): toggles with the sound; `force` lets a locked door move (the scene's locks
# are for the player).
func use_door(d: Node3D, force: bool = false) -> void:
	if d == null:
		return
	if force:
		var was_locked: bool = d.locked
		d.locked = false
		d.toggle(true)
		d.locked = was_locked
	else:
		d.toggle(true)

# n.rotation.y chases the bearing to a point (RotateEntity ..., CurveValue(EntityYaw(PointEntity ...)))
func face(n: CharacterBody3D, point: Vector3, smooth: float, fps: float) -> void:
	var to: Variant = point - n.global_position
	if Vector2(to.x, to.z).length() < 0.001:
		return
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(fps / smooth, 1.0))

func set_yaw(n: CharacterBody3D, degrees: float) -> void:
	n.rotation.y = deg_to_rad(degrees) + room.rotation.y

func voice(index: int, slot: int, relative: String, loop: bool = false, range: float = 10.0, volume: float = 1.0) -> void:
	var holder: Node3D = npc[index]
	if holder == null:
		return
	var key := index * 10 + slot
	var audio: AudioStreamPlayer3D = _voices.get(key)
	if audio == null or not is_instance_valid(audio):
		audio = AudioStreamPlayer3D.new()
		holder.add_child(audio)
		_voices[key] = audio
	var source := Sfx.stream(relative)
	if source == null:
		return
	if loop:
		source = source.duplicate()
		source.loop = true
	audio.stream = source
	audio.max_distance = range
	audio.volume_db = linear_to_db(maxf(volume, 0.0001))
	audio.play()
	_voice_end[key] = INF if loop else GameState.clock_ms() + source.get_length() * 1000.0

func voice_playing(index: int, slot: int) -> bool:
	return float(_voice_end.get(index * 10 + slot, 0.0)) > GameState.clock_ms()

func voice_stop(index: int, slot: int) -> void:
	_voice_end[index * 10 + slot] = 0.0
	var audio: AudioStreamPlayer3D = _voices.get(index * 10 + slot)
	if audio != null and is_instance_valid(audio):
		audio.stop()

func sound(relative: String) -> void:
	Sfx.play_global(self, relative)

func intro_sfx(index: int) -> void:
	match index:
		0: sound("SFX/Room/Intro/Scientist/Franklin/EnterChamber.ogg")
		1: sound("SFX/Room/Intro/Scientist/Franklin/Approach173.ogg")
		2: sound("SFX/Room/Intro/Scientist/Franklin/Problem.ogg")
		4, 5, 6: sound("SFX/Room/Intro/Scientist/Franklin/Refuse%d.ogg" % (index - 3))
		7, 8, 9: sound("SFX/Room/Intro/Bang%d.ogg" % (index - 6))
		10, 11, 12: sound("SFX/Room/Intro/Light%d.ogg" % (index - 9))
		15: sound("SFX/Room/Intro/173Vent.ogg")
		16: sound("SFX/Room/Intro/Horror.ogg")
		17: sound("SFX/Room/Intro/See173.ogg")

func message(text: String, seconds: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.message(text, seconds)

func _key_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "?"

func neck_snap(at_node: Node3D, file_index: int = 0, range_: float = 8.0) -> void:
	if file_index == 0:
		file_index = randi_range(1, 3)
	Sfx.play_at(at_node, "SFX/SCP/173/NeckSnap%d.ogg" % file_index, range_)

func _statue_pin(spot: Vector3) -> void:
	statue.velocity = Vector3.ZERO
	statue.global_position = spot

func _physics_process(delta: float) -> void:
	if not started or done or player == null or not is_instance_valid(room):
		return
	var fps := delta * 70.0
	_frame_start_state = event_state
	if not player.dead and event_state2 == 0:
		if event_state3 > 0.0:
			_cell_phase(fps)
		else:
			_chamber_phase(fps)
	elif player.dead and event_state2 == 0:
		if npc[3] != null and npc[3].state == 1 and not _terminated_played:
			_terminated_played = true
			sound("SFX/Room/Intro/Guard/Ulgrin/EscortTerminated.ogg")
		event_state2 = 1
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and event_state3 <= 0.0 and hud.flash_alpha > 0.0:
		hud.flash_alpha = 0.0

# ---- setup: EventState = 0 ---------------------------------------------------------------------------

func _setup() -> void:
	statue.active = false
	npc[3] = _spawn(HumanNpc.Kind.GUARD, at(-4096.0 + randf_range(-0.3, 0.3) / RS, 0.3, randi_range(860, 896)))
	set_yaw(npc[3], 180.0)
	npc[3].state = 7
	npc[4] = _spawn(HumanNpc.Kind.GUARD, at(-3840.0, 0.3, 768.0))
	set_yaw(npc[4], 135.0)
	npc[4].state = 7
	npc[5] = _spawn(HumanNpc.Kind.GUARD, at(-8288.0, 0.3, 1096.0))
	set_yaw(npc[5], 180.0)
	npc[5].state = 7
	npc[6] = _spawn(HumanNpc.Kind.CLASS_D, at(-3712.0, -0.3, -2208.0), 3)
	npc[7] = _spawn(HumanNpc.Kind.CLASS_D, at(-3712.0, -0.3, -2208.0), 2)
	npc[8] = _spawn(HumanNpc.Kind.GUARD, at(-3800.0, 1.0, -3900.0))
	npc[8].state = 7
	npc[9] = _spawn(HumanNpc.Kind.CLASS_D, at(-4000.0, 1.1, -3900.0), 100)
	npc[9].state2 = 1.0
	npc[10] = _spawn(HumanNpc.Kind.GUARD, at(-4200.0, 1.0, -3900.0))
	npc[10].state = 7
	for i in range(8, 11):
		set_yaw(npc[i], 90.0)
	# the music in the far hall and the voice that follows an escaping player
	npc[5].set_meta("music", "SFX/Room/Intro/Guard/Music%d.ogg" % randi_range(1, 5))
	statue_to_chamber()
	player.global_position = at(-(3072.0 + 1024.0), 0.0, 192.0)
	player.global_position.y = room.floor_height(player.global_position.x - room.global_position.x, player.global_position.z - room.global_position.z, 1.05) + 0.02
	player.velocity = Vector3.ZERO
	event_state = 1.0
	event_state3 = 1.0
	_ambience = AudioStreamPlayer3D.new()
	add_child(_ambience)
	var loop := Sfx.stream("SFX/Room/Intro/173Chamber.ogg")
	if loop != null:
		loop = loop.duplicate()
		loop.loop = true
		_ambience.stream = loop
		_ambience.max_distance = 6.0
		_ambience.global_position = room.objects[4]
		_ambience.play()

# Curr173 stands at Objects[5], on the chamber floor.
func statue_to_chamber() -> void:
	var local := room.to_local(room.objects[5])
	var floor_world: float = room.global_position.y + room.floor_height(local.x, local.z, 1.05)
	_statue_pin(Vector3(room.objects[5].x, floor_world + 0.01, room.objects[5].z))

# ---- the cell and the escort (EventState3 > 0) ------------------------------------------------------------

func _cell_phase(fps: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	# slow the player down to match his speed to the guards
	var near := player.global_position.distance_to(npc[3].global_position)
	player.drag_factor = 0.008 / maxf(near, 0.05) * fps
	if event_state3 < 170.0:
		_wake_and_read(fps, hud)
	elif event_state3 >= 150.0 and event_state3 < 700.0:
		_guard_opens_cell(fps)
	elif event_state3 < 800.0:
		_escort_start(fps)
	elif event_state3 < 900.0:
		_escort(fps)
	elif event_state3 <= 905.0:
		_guard_handover(fps)
	else:
		_escort_end(fps)
	_desk_scientist(fps)

# The first 15 units of EventState3: the view from the floor of the cell.
func _wake_and_read(fps: float, hud: Node) -> void:
	if event_state3 == 1.0 and not _wake_started:
		_wake_started = true
		player.scripted = true
		GameState.blur_timer = 500.0
		intro_sfx(11)
		if hud != null:
			hud.flash_alpha = 0.5
	if event_state3 < 3.0:
		event_state3 += fps / 100.0
	elif event_state3 < 15.0 or event_state3 >= 50.0:
		event_state3 += fps / 30.0
	if event_state3 < 15.0:
		var x := -(3224.0 + 1024.0)
		var y := 136.0 * RS
		var z := 8.0
		if event_state3 < 14.0:
			if event_state3 - fps / 30.0 < 12.0 and event_state3 > 12.0:
				Sfx.play_at(player, "SFX/Step/Step1.ogg", 8.0, 0.3)
			if hud != null:
				hud.flash_alpha = clampf(0.9 - event_state3 / 2.0, 0.0, 1.0)
			x = x + (-(3048.0 + 1024.0) - x) * maxf((event_state3 - 10.0) / 4.0, 0.0)
			if event_state3 < 10.0:
				y = y + 0.2 * minf(maxf((event_state3 - 3.0) / 5.0, 0.0), 1.0)
			else:
				y = (y + 0.2) + (0.302 + 0.6 - (y + 0.2)) * maxf((event_state3 - 10.0) / 4.0, 0.0)
			z = z + (104.0 - z) * minf(maxf((event_state3 - 3.0) / 5.0, 0.0), 1.0)
			var pitch := -70.0 + 70.0 * minf(maxf((event_state3 - 3.0) / 5.0, 0.0), 1.0) + sin(deg_to_rad(event_state3 * 12.857)) * 5.0
			var yaw := -60.0 * maxf((event_state3 - 10.0) / 4.0, 0.0)
			var roll := sin(deg_to_rad(event_state3 * 25.7)) * 8.0
			var floor_y: float = room.global_position.y   # the cell floor is y = 0 (the bed sits above the start)
			var camera_at := at(x, 0.0, z)
			player.global_position = Vector3(camera_at.x, floor_y + 0.02, camera_at.z)
			player.velocity = Vector3.ZERO
			player.camera.global_position = Vector3(camera_at.x, floor_y + y, camera_at.z)
			player.rotation.y = deg_to_rad(yaw)
			player.camera.rotation = Vector3(deg_to_rad(-pitch), 0.0, deg_to_rad(-roll))
			player.user_pitch = 0.0
		else:
			if hud != null:
				hud.flash_alpha = 0.0
			player.scripted = false
			player.camera.position = Vector3(0.0, 0.9, 0.0)
			player.camera.rotation = Vector3.ZERO
			event_state3 = 15.0
			message("Pick up the paper on the desk.", 7.0)
	elif event_state3 < 40.0:
		if hud != null and not str(hud.items[0]).is_empty():
			message("Press Tab to open the inventory.", 7.0)
			event_state3 = 40.0
	if hud != null and hud.selected >= 0:
		event_state3 += fps / 5.0

# 150..700: Ulgrin opens the cell door, calls the player out, gases the cell if they refuse.
func _guard_opens_cell(fps: float) -> void:
	var ulgrin: CharacterBody3D = npc[3]
	if ulgrin.state == 7:
		if not _voices.has(3 * 10 + 2):
			voice(3, 2, "SFX/Room/Intro/Guard/Ulgrin/BeforeDoorOpen.ogg", false, 10.0)
		if not voice_playing(3, 2):
			voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/ExitCell.ogg")
			ulgrin.state = 9
			npc[4].state = 9
			npc[5].state = 9
			use_door(door(6), true)
	else:
		event_state3 = minf(event_state3 + fps / 4.0, 699.0)
		var cell_centre := at(-(3072.0 + 1024.0), 0.0, 192.0)
		if flat_distance(player.global_position, cell_centre) > 1.5:
			# outside the cell
			if event_state3 > 250.0:
				voice_stop(3, 1)
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/Escort%d.ogg" % randi_range(1, 2))
				ulgrin.find_path_to(at(-320.0, 0.0, -704.0))
				npc[4].find_path_to(at(-320.0, 0.0, -704.0))
				event_state3 = 710.0
		else:
			ulgrin.state = 9
			if event_state3 - fps / 4.0 < 350.0 and event_state3 >= 350.0:
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/ExitCellRefuse%d.ogg" % randi_range(1, 2))
			elif event_state3 - fps / 4.0 < 550.0 and event_state3 >= 550.0:
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/CellGas%d.ogg" % randi_range(1, 2))
			elif event_state3 > 630.0:
				var local_z := rs_of(player.global_position).y
				if local_z > 490.0:
					var back := at(rs_of(player.global_position).x, 0.0, 490.0)
					player.global_position.z = back.z
				var cell_door := door(6)
				if cell_door != null and cell_door.open:
					use_door(cell_door, true)
					_gas(at(-(2976.0 + 1024.0), 373.0 * RS, 204.0))
					_gas(at(-(3168.0 + 1024.0), 373.0 * RS, 204.0))
				GameState.eye_irritation = maxf(GameState.eye_irritation + fps * 4.0, 1.0)

# Gas pours out of two vents in the cell ceiling (CreateEmitter, particle type 0).
func _gas(pos: Vector3) -> void:
	var emitter := CPUParticles3D.new()
	emitter.amount = 40
	emitter.lifetime = 4.0
	emitter.direction = Vector3.DOWN
	emitter.spread = 20.0
	emitter.initial_velocity_min = 0.5
	emitter.initial_velocity_max = 1.2
	emitter.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.4
	emitter.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(0.9, 0.9, 0.85, 0.25)
	emitter.material_override = material
	emitter.scale_amount_min = 0.5
	emitter.scale_amount_max = 2.5
	room.add_child(emitter)
	emitter.global_position = pos
	_gas_emitters.append(emitter)

# 710..800: the escort walks; the far-hall guard notices a player who runs.
func _escort_start(fps: float) -> void:
	event_state3 += fps / 4.0
	_guard5_notices()

func _guard5_notices() -> void:
	if npc[5].state != 11:
		if npc[3].global_position.distance_to(npc[5].global_position) > 5.0 and npc[4].global_position.distance_to(npc[5].global_position) > 0.0:
			if npc[5].global_position.distance_to(player.global_position) < 3.5:
				npc[5].state = 11
				npc[5].state3 = 1.0
				voice(5, 2, "SFX/Room/Intro/Guard/PlayerEscape.ogg", false, 10.0)
				npc[5].reload = 70.0 * 3.0

# 800..900: along the corridors to the door of the office.
func _escort(fps: float) -> void:
	npc[4].angle = 0.0
	var ulgrin: CharacterBody3D = npc[3]
	# the PA announcement, once the player is past the cell block
	if rs_of(player.global_position).x < -5376.0 and event_str == "":
		if randi_range(1, 3) == 1:
			event_str = "scripted/scripted%d.ogg|off.ogg|" % randi_range(1, 5)
		else:
			var kind: String = ["crew", "scientist", "security"][randi_range(0, 2)]
			event_str = "1/attention%d.ogg" % randi_range(1, 2)
			match kind:
				"crew":
					event_str += "|2/crew%d.ogg" % randi_range(0, 5)
				"scientist":
					event_str += "|2/scientist%d.ogg" % randi_range(0, 19)
				"security":
					event_str += "|2/security%d.ogg" % randi_range(0, 5)
			if randi_range(1, 2) == 1 and kind == "scientist":
				event_str += "|3/callonline.ogg"
				event_str += "|numbers/%d.ogg" % randi_range(1, 9)
				if randi_range(1, 2) == 1:
					event_str += "|numbers/%d.ogg" % randi_range(1, 9)
			else:
				event_str += "|3/report%d.ogg" % randi_range(0, 1)
				match kind:
					"crew":
						event_str += "|4/crew%d.ogg" % randi_range(0, 6)
						if randi_range(1, 2) == 1:
							event_str += "|5/crew%d.ogg" % randi_range(0, 6)
					"scientist":
						event_str += "|4/scientist%d.ogg" % randi_range(0, 7)
						if randi_range(1, 2) == 1:
							event_str += "|5/scientist0.ogg"
					"security":
						event_str += "|4/security%d.ogg" % randi_range(0, 5)
						if randi_range(1, 2) == 1:
							event_str += "|5/security%d.ogg" % randi_range(1, 2)
			event_str += "|off.ogg|"
	if npc[6] != null:
		var scientist: CharacterBody3D = npc[6]
		if scientist.state == 0:
			if door(7) != null and door(7).open:
				if flat_distance(player.global_position, at(-3328.0, 0.0, -1232.0)) < 5.0:
					scientist.state = 1
					if event_str == "done":
						sound("SFX/Room/Intro/PA/scripted/announcement%d.ogg" % randi_range(1, 7))
		else:
			if rs_of(scientist.global_position).y > -64.0:
				scientist.rotation.y = lerp_angle(scientist.rotation.y, deg_to_rad(90.0), minf(1.0 / 15.0, 1.0))
				if door(7) != null and door(7).open:
					use_door(door(7))
				if door(7) != null and door(7).openstate < 1.0:
					scientist.state = 0
	if npc[8] != null:
		if npc[8].state == 7:
			if flat_distance(player.global_position, at(-6688.0, 0.0, -1252.0)) < 2.5:
				npc[8].state = 10
				npc[9].state = 1
				npc[10].state = 10
		else:
			if rs_of(npc[8].global_position).x < -7100.0:
				for i in range(8, 11):
					npc[i].state = 0
	_loop_voice(5, 1, npc[5].get_meta("music", ""), 2.0, 0.5)
	_play_pa()
	_escort_ulgrin(fps)
	_escort_arrival(fps)

func _loop_voice(index: int, slot: int, relative: String, range: float, volume: float) -> void:
	if relative.is_empty() or npc[index] == null:
		return
	if not _voices.has(index * 10 + slot) or not voice_playing(index, slot):
		voice(index, slot, relative, true, range, volume)

# EventStr is a queue of PA clips separated by "|".
func _play_pa() -> void:
	if event_str == "" or event_str == "done":
		return
	if _pa == null:
		_pa = AudioStreamPlayer.new()
		add_child(_pa)
		var on := Sfx.stream("SFX/Room/Intro/PA/on.ogg")
		if on != null:
			_pa.stream = on
			_pa.play()
			_pa_end = GameState.clock_ms() + on.get_length() * 1000.0
		return
	if GameState.clock_ms() >= _pa_end:
		var next := event_str.get_slice("|", 0)
		var clip := Sfx.stream("SFX/Room/Intro/PA/" + next)
		if clip != null:
			_pa.stream = clip
			_pa.play()
			_pa_end = GameState.clock_ms() + clip.get_length() * 1000.0
		event_str = event_str.substr(next.length() + 1)
		if event_str == "":
			voice_stop(3, 1)
			var pick := randi_range(1, 5)
			voice(3, 1, "SFX/Room/Intro/Guard/Conversation%da.ogg" % pick)
			voice(4, 1, "SFX/Room/Intro/Guard/Conversation%db.ogg" % pick)
			event_str = "done"

# Ulgrin stays near the player, nags when they dawdle and shoots when they refuse (State2 counts the warnings).
func _escort_ulgrin(fps: float) -> void:
	var ulgrin: CharacterBody3D = npc[3]
	var dist := flat_distance(player.global_position, ulgrin.global_position)
	if dist < 3.0:
		ulgrin.state3 = minf(maxf(ulgrin.state3 - fps, 0.0), 50.0)
	else:
		ulgrin.state3 = maxf(ulgrin.state3 + fps, 50.0)
		if ulgrin.state3 >= 70.0 * 8.0 and ulgrin.state3 - fps < 70.0 * 8.0 and ulgrin.state == 7:
			if voice_playing(4, 1):
				voice_stop(4, 1)
			if ulgrin.state2 < 2.0:
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/EscortRefuse%d.ogg" % randi_range(1, 2))
				ulgrin.state3 = 50.0
				ulgrin.state2 = 3.0
			elif ulgrin.state2 == 3.0:
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/EscortPissedOff%d.ogg" % randi_range(1, 2))
				ulgrin.state3 = 50.0
				ulgrin.state2 = 4.0
			elif ulgrin.state2 == 4.0:
				voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/EscortKill%d.ogg" % randi_range(1, 2))
				ulgrin.state3 = 50.0 + 70.0 * 2.5
				ulgrin.state2 = 5.0
			elif ulgrin.state2 == 5.0:
				npc[3].state = 11
				npc[4].state = 11
				npc[5].state = 11
				npc[3].state3 = 1.0
				npc[4].state3 = 1.0
				npc[5].state3 = 1.0
		_guard5_notices()
	if ulgrin.state != 11:
		if dist < minf(maxf(4.0 - ulgrin.state3 * 0.05, 1.5), 4.0):
			if ulgrin.path_status != 1:
				ulgrin.state = 7
				face(ulgrin, player.global_position, 20.0, fps)
				if ulgrin.path_status == 2:
					ulgrin.find_path_to(at(-320.0, 0.0, -704.0))
					npc[4].find_path_to(at(-320.0, 0.0, -704.0))
					ulgrin.state = 3
			else:
				ulgrin.state = 3
		else:
			ulgrin.state = 7
			face(ulgrin, player.global_position, 20.0, fps)
			if dist > 5.5:
				ulgrin.path_status = 2
				if ulgrin.state2 == 0.0:
					voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/EscortRun.ogg")
					ulgrin.state2 = 1.0
				ulgrin.state = 5
				ulgrin.enemy = player.global_position
		var second_dist := player.global_position.distance_to(npc[4].global_position)
		if second_dist > 1.5 and ulgrin.global_position.distance_to(player.global_position) < ulgrin.global_position.distance_to(npc[4].global_position):
			npc[4].state = 3
		else:
			npc[4].state = 5
			npc[4].enemy = player.global_position

# Ulgrin and the guard with him reach the door of the anteroom: the others vanish and the scene moves on.
func _escort_arrival(fps: float) -> void:
	var anteroom := door(2)
	if anteroom == null:
		return
	var frame_pos := anteroom.global_position
	var ulgrin: CharacterBody3D = npc[3]
	if flat_distance(ulgrin.global_position, frame_pos) < 4.5 and flat_distance(player.global_position, frame_pos) < 5.0:
		npc[0] = _spawn(HumanNpc.Kind.GUARD, room.objects[0])
		npc[0].angle = 180.0
		npc[1] = _spawn(HumanNpc.Kind.CLASS_D, Vector3(room.objects[1].x, room.global_position.y + 0.5, room.objects[1].z))
		face(npc[1], room.objects[5], 1.0, 70.0)
		npc[2] = _spawn(HumanNpc.Kind.CLASS_D, Vector3(room.objects[2].x, room.global_position.y + 0.5, room.objects[2].z), 6)
		face(npc[2], room.objects[5], 1.0, 70.0)
		ulgrin.state = 9
		if npc[7] != null and _voices.has(7 * 10 + 1):
			voice_stop(7, 1)
		if room.map_prop != null:
			room.map_prop.queue_free()
			room.map_prop = null
		if room.labels != null:
			room.labels.queue_free()
			room.labels = null
		for i in [5, 8, 9, 10]:
			if npc[i] != null:
				facility.remove_human(npc[i])
				npc[i] = null
		voice_stop(3, 1)
		voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/EscortDone%d.ogg" % randi_range(1, 5))
		npc[6].global_position = at(-1190.0, 450.0 * RS, 456.0)
		npc[6].velocity = Vector3.ZERO
		face(npc[6], room.global_position, 1.0, 70.0)
		npc[6].curr_speed = 0.0
		npc[6].state = 0
		event_state3 = 905.0
		use_door(door(3), true)
		npc[4].state = 9

# 900..905: Ulgrin hands over the document.
func _guard_handover(fps: float) -> void:
	var ulgrin: CharacterBody3D = npc[3]
	if not voice_playing(3, 1) and ulgrin.frame < 358.0:
		ulgrin.state = 8
		voice(3, 1, "SFX/Room/Intro/Guard/Ulgrin/OhAndByTheWay.ogg")
		ulgrin.set_frame(358.0)
	elif ulgrin.frame >= 358.0:
		var to: Vector3 = player.global_position - ulgrin.global_position
		ulgrin.rotation.y = atan2(-to.x, -to.z)
		if ulgrin.frame <= 481.5:
			ulgrin.animate(358.0, 482.0, 0.4, fps, false)
		else:
			ulgrin.animate(483.0, 607.0, 0.2, fps, true)
			if player.global_position.distance_to(ulgrin.global_position) < 1.5:
				var camera: Camera3D = player.camera
				if ulgrin.in_view(camera):
					GameState.hand_icon = true
					if Input.is_action_just_pressed("interact") or test_interact:
						test_interact = false
						_give_document()
						use_door(door(2), true)
						event_state3 = 910.0
						ulgrin.set_frame(608.0)

func _give_document() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var item := RoomFill.make_pickup("Document SCP-173", "paper")
	if hud.try_pickup(item):
		for i in hud.items.size():
			if hud.items[i] == "Document SCP-173":
				hud.set_selected(i)
				break
	item.queue_free()

# 910 and on: the guards wait at the chamber door until the player is close, then the door opens.
func _escort_end(fps: float) -> void:
	var ulgrin: CharacterBody3D = npc[3]
	if ulgrin.frame <= 620.5 and ulgrin.state == 8:
		ulgrin.animate(608.0, 621.0, 0.4, fps, false)
	else:
		ulgrin.angle = rad_to_deg(ulgrin.rotation.y)
		ulgrin.state = 9
		npc[4].state = 9
		if flat_distance(player.global_position, room.global_position) < 4.0:
			use_door(door(2), true)
			event_state3 = 0.0
			ulgrin.state = 0
			npc[4].state = 0
			use_door(door(1))

# The scientist sitting at his desk, talking to himself.
func _desk_scientist(fps: float) -> void:
	var sitter: CharacterBody3D = npc[7]
	if sitter == null:
		return
	sitter.rotation.y = deg_to_rad(180.0 + sin(deg_to_rad(GameState.clock_ms() / 20.0)) * 3.0)
	# -315 is the collider's centre; the model hangs 0.32 below it (NPCs.bb NPCtypeD) and the port's node is the model's origin
	sitter.global_position = at(-3361.0, -315.0 * RS - 0.32, -2165.0)
	sitter.velocity = Vector3.ZERO
	sitter.state = 6
	sitter.set_frame(182.0)
	if npc[6] != null and npc[6].state == 1:
		_loop_voice(7, 1, "SFX/Room/Intro/Scientist/Conversation.ogg", 7.0, 1.0)

# ---- the chamber (EventState3 = 0) ---------------------------------------------------------------------------

func _chamber_phase(fps: float) -> void:
	player.drag_factor = 0.0
	if event_state == 0.0:
		if started:
			_setup()
		return
	if event_state < 10000.0:
		_approach(fps)
	elif event_state < 14000.0:
		_inside(fps)
	elif event_state < 20000.0:
		_173_kills(fps)
	elif event_state < 30000.0:
		_balcony(fps)

# 1..10000: Franklin waits in the chamber and the player is told to go in.
func _approach(fps: float) -> void:
	var franklin: CharacterBody3D = npc[6]
	if _voices.has(6 * 10 + 1) and voice_playing(6, 1):
		franklin.state = 6
		if franklin.frame >= 325.0:
			franklin.animate(326.0, 328.0, 0.02, fps, false)
		else:
			franklin.animate(320.0, 328.0, 0.05, fps, false)
	elif _voices.has(6 * 10 + 1):
		franklin.animate(328.0, 320.0, -0.02, fps, false)
	if not _see_173_played:
		if statue._line_of_sight(player) and statue.in_view(player.camera):
			message("Press %s to blink." % _key_name("blink"), 4.0)
			intro_sfx(17)
			_see_173_played = true
	event_state = minf(event_state + fps / 3.0, 5000.0)
	if event_state >= 130.0 and event_state - fps / 3.0 < 130.0:
		voice(6, 1, "SFX/Room/Intro/Scientist/Franklin/EnterChamber.ogg", false, 20.0)
	elif event_state > 230.0:
		var temp := true
		for i in range(1, 3):
			var d: CharacterBody3D = npc[i]
			var target: Vector3 = room.objects[i + 2]
			if flat_distance(d.global_position, target) > 0.3:
				face(d, target, 15.0, fps)
				if event_state > 200.0 + i * 30.0:
					d.state = 1
				temp = false
			else:
				d.state = 0
				face(d, room.objects[5], 15.0, fps)
		if rs_of(player.global_position).x < 408.0:
			if event_state >= 450.0 and event_state - fps / 3.0 < 450.0:
				intro_sfx(4)
			elif event_state >= 650.0 and event_state - fps / 3.0 < 650.0:
				intro_sfx(5)
			elif event_state >= 850.0 and event_state - fps / 3.0 < 850.0:
				use_door(door(1))
				intro_sfx(6)
			elif event_state > 1000.0:
				npc[0].state = 1
				npc[0].state2 = 10.0
				npc[0].state3 = 1.0
				npc[3].state = 11
				use_door(door(2), true)
				event_state2 = 1
				return
			if event_state > 850.0:
				var x_limit := room.global_position.x + 352.0 * RS
				if player.global_position.x > x_limit:
					player.global_position.x = x_limit
		elif temp:
			event_state = 10000.0
			use_door(door(1))
	npc[6].state = 7
	face(npc[6], player.global_position, 20.0, fps)
	_hold_173(fps)

func _hold_173(fps: float) -> void:
	statue.global_position = Vector3(room.objects[5].x, statue.global_position.y, room.objects[5].z)
	statue.rotation.y = 0.0
	statue.velocity = Vector3.ZERO

# 10000..14000: the player is in the chamber with Franklin and the two Class D.
func _inside(fps: float) -> void:
	event_state = minf(event_state + fps, 13000.0)
	if event_state < 10300.0:
		var x_limit := room.global_position.x + 352.0 * RS
		if player.global_position.x < x_limit:
			player.global_position.x = x_limit
	npc[6].state = 6
	face(npc[6], statue.global_position, 50.0, fps)
	if event_state >= 10300.0 and event_state - fps < 10300.0:
		voice(6, 1, "SFX/Room/Intro/Scientist/Franklin/Approach173.ogg", false, 20.0)
		var x_limit := room.global_position.x + 352.0 * RS
		if player.global_position.x < x_limit:
			player.global_position.x = x_limit
	elif event_state >= 10440.0 and event_state - fps < 10440.0:
		use_door(door(1))
		intro_sfx(7)
	elif event_state >= 10740.0 and event_state - fps < 10740.0:
		voice(6, 1, "SFX/Room/Intro/Scientist/Franklin/Problem.ogg", false, 20.0)
	elif event_state >= 11145.0 and event_state - fps < 11145.0:
		intro_sfx(10)
		voice(1, 1, "SFX/Room/Intro/ClassD/DontLikeThis.ogg", false, 10.0)
	elif event_state >= 11561.0 and event_state - fps < 11561.0:
		event_state = 14000.0
		intro_sfx(16)
		voice(2, 1, "SFX/Room/Intro/ClassD/Breen.ogg", false, 10.0)
	# the guard on the balcony shouts when the player is past the chamber door
	if event_state >= 10440.0 and event_state - fps < 11561.0:
		if player.global_position.x < door(1).global_position.x:
			if npc[0].state != 12:
				voice(0, 1, "SFX/Room/Intro/Guard/Balcony/Alert%d.ogg" % randi_range(1, 2), false, 20.0)
				npc[0].state = 12
				npc[0].state2 = 1.0
	if event_state > 10300.0:
		if event_state > 10560.0:
			if event_state < 10750.0:
				npc[1].state = 1
				npc[1].curr_speed = 0.005
			else:
				npc[1].state = 0
				npc[1].curr_speed = npc[1]._curve_value(0.0, npc[1].curr_speed, 10.0, fps)
		if npc[6].frame >= 325.0:
			npc[6].animate(326.0, 328.0, 0.02, fps, false)
		else:
			npc[6].animate(320.0, 328.0, 0.05, fps, false)
	_hold_173(fps)

# 14000..20000: the lights go out and 173 kills the first Class D, then the other.
func _173_kills(fps: float) -> void:
	var to: Variant = statue.global_position + Vector3(0.0, 0.2, 0.0) - player.camera.global_position
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(fps / 40.0, 1.0))
	var want_pitch := rad_to_deg(atan2(-to.y, Vector2(to.x, to.z).length()))
	player.user_pitch = lerpf(player.user_pitch, clampf(want_pitch, -70.0, 70.0), minf(fps / 40.0, 1.0))
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	npc[6].state = 6
	face(npc[6], statue.global_position, 20.0, fps)
	npc[6].animate(357.0, 381.0, 0.05, fps)
	event_state = minf(event_state + fps, 19000.0)
	if event_state < 14100.0:
		# lights go out and 173 kills the first Class D
		if event_state < 14060.0:
			player.blink_timer = maxf((14000.0 - event_state) / 2.0 - randf_range(0.0, 1.0), -10.0)
			if player.blink_timer == -10.0:
				face(statue, npc[1].global_position, 1.0, 70.0)
				var dir: Vector3 = (npc[1].global_position - statue.global_position)
				dir.y = 0.0
				statue.global_position += dir.normalized() * 1.0 * 0.6 * 70.0 * (fps / 70.0) * 0.0
				statue.move_state = statue._curve_value(1.0, statue.move_state, 3.0, fps) if statue.has_method("_curve_value") else statue.move_state
			else:
				statue.move_state = maxf(0.0, statue.move_state - fps / 20.0)
		elif event_state < 14065.0:
			player.blink_timer = -10.0
			if npc[1].state == 0:
				neck_snap(statue, 0, 10.0)
			npc[1].set_frame(0.0)
			npc[1].state = 6
			statue.global_position = Vector3(npc[1].global_position.x, statue.global_position.y, npc[1].global_position.z)
			face(statue, npc[2].global_position, 1.0, 70.0)
			npc[2].state = 3
			npc[2].animate(406.0, 382.0, -0.01 * 15.0, fps)
			npc[2].scene_move += -0.01 * fps
			npc[0].state = 12
			if _voices.has(0 * 10 + 1):
				voice_stop(0, 1)
			npc[0].angle = 180.0
			voice(0, 1, "SFX/Room/Intro/Guard/Balcony/WTF%d.ogg" % randi_range(1, 2), false, 20.0)
			npc[0].state2 = 0.0
		else:
			npc[1].animate(0.0, 19.0, 0.2, fps, false)
			if not _voices.has(2 * 10 + 1) or not voice_playing(2, 1):
				if not _voices.has(2 * 10 + 1):
					voice(2, 1, "SFX/Room/Intro/ClassD/Gasp.ogg", false, 8.0)
		if event_state > 14080.0 and event_state - fps < 14080.0:
			intro_sfx(12)
		player.camera_shake = 3.0
	elif event_state < 14200.0:
		npc[1].animate(0.0, 19.0, 0.2, fps, false)
		npc[0].state = 8
		if event_state > 14105.0:
			if npc[2].state != 6:
				neck_snap(npc[2], 2)
			npc[2].state = 6
			statue.global_position = Vector3(npc[2].global_position.x, statue.global_position.y, npc[2].global_position.z)
			face(statue, player.global_position, 1.0, 70.0)
		if event_state < 14130.0:
			npc[2].set_frame(50.0)
			player.blink_timer = -10.0
			GameState.light_blink = 1.0
		else:
			npc[2].animate(50.0, 60.0, 0.2, fps, false)
			statue.active = false
		if event_state > 14100.0 and event_state - fps < 14100.0:
			intro_sfx(8)
		if event_state < 14150.0:
			player.camera_shake = 5.0
	else:
		npc[2].animate(45.0, 60.0, 0.2, fps, false)
		if event_state > 14300.0:
			if event_state > 14600.0 and event_state < 14700.0:
				player.blink_timer = -10.0
				GameState.light_blink = 1.0
			if rs_of(player.global_position).x < 448.0:
				event_state = 20000.0

# 20000..30000: lights out again, 173 jumps beside the balcony guard, who dies; then the start room.
func _balcony(fps: float) -> void:
	event_state = minf(event_state + fps, 30000.0)
	if event_state < 20100.0:
		player.camera_shake = 2.0
		return
	if event_state < 20200.0:
		if event_state > 20105.0 and event_state - fps < 20105.0:
			intro_sfx(9)
			npc[0].global_position = Vector3(room.global_position.x - 160.0 * RS, npc[0].global_position.y + 0.1, room.global_position.z - 1280.0 * RS)
			npc[0].velocity = Vector3.ZERO
			if _voices.has(0 * 10 + 1):
				voice_stop(0, 1)
			voice(0, 1, "SFX/Room/Intro/Guard/Balcony/OhSh.ogg", false, 20.0)
		if event_state > 20105.0:
			statue.active = false
			face(npc[0], statue.global_position, 1.0, 70.0)
			_statue_pin(Vector3(room.global_position.x - 608.0 * RS, room.global_position.y + 480.0 * RS, room.global_position.z - 1312.0 * RS))
			face(statue, npc[0].global_position, 1.0, 70.0)
		player.blink_timer = -10.0
		GameState.light_blink = 1.0
		player.camera_shake = 3.0
	elif event_state < 20300.0:
		face(npc[0], statue.global_position, 1.0, 70.0)
		npc[0].scene_move += -0.002
		npc[0].state = 2
		if event_state > 20260.0 and event_state - fps < 20260.0:
			intro_sfx(12)
	else:
		if _frame_start_state < 20300.0:
			player.blink_timer = -10.0
			GameState.light_blink = 1.0
			player.camera_shake = 3.0
			intro_sfx(11)
			neck_snap(npc[0], 2)
			statue.active = true
			sound("SFX/Room/Intro/173Vent.ogg")
			_statue_pin(room.global_position + Vector3(-400.0 * RS, 100.0, -1072.0 * RS))
			_to_start_room()

# The breach carries on in the start room: everything moves by (3712, 384 RoomScale, 1312) from this
# room's origin and the room is thrown away.
func _to_start_room() -> void:
	facility.start_scene_adopt = {"guard": npc[0], "scientist": npc[6]}
	facility.enter_after_breach(player, statue, room, false)
	var start_room: Node3D = facility.start_node
	if start_room == null:
		return
	var shift_world := func(world: Vector3) -> Vector3:
		var local := room.to_local(world)
		var local_start := Vector3(local.x + 3712.0 * RS, 384.0 * RS + local.y + 0.4, local.z - 1312.0 * RS)
		return start_room.to_global(local_start)
	player.global_position = shift_world.call(player.global_position)
	player.velocity = Vector3.ZERO
	facility.after_teleport()
	for i in range(0, 3):
		if npc[i] != null:
			npc[i].global_position = shift_world.call(npc[i].global_position)
			npc[i].velocity = Vector3.ZERO
	player.rotation.y += start_room.rotation.y
	player.drag_factor = 0.0
	for i in [3, 4, 5, 7, 8, 9, 10]:
		if npc[i] != null:
			facility.remove_human(npc[i])
			npc[i] = null
	for emitter in _gas_emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	facility.unregister_intro_room()
	done = true
	event_state2 = 1
	finished.emit()

# The carried-over people of the scene for the start room's own scene (NPC[0] the guard, NPC[1] Franklin).
func carried_guard() -> CharacterBody3D:
	return npc[0]

func carried_scientist() -> CharacterBody3D:
	return npc[6]
