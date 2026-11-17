extends Node3D
# SCP-035's chamber (UpdateEvents.bb Case "room035", MapSystem.bb FillRoom "room035"). The host (a Class D body in 035's own model)
# sits in the containment chamber, behind glass and two locked doors. The room has two levers (Levers[0] opens the chamber, Levers[1]
# lets the contamination gas in) and four doors: RoomDoors[0] / [1] the chamber, [2] the control room, [3] the storage room (code 5731).
#   EventState  0 not met, 1 the host lies in his chair (the player within 2 of Objects[3] makes him), 1.5 he has been seen getting
#               up, then the seconds of his talk (x70: Help, Idle...), 60*70 / 61*70 after the gas, -1 SCP-035 has left
#   EventState2 (before he leaves) 0, 1 the storage door has been opened, 20 the chamber is open and he walks to the door;
#               (after) how far the player's stay in the chamber has gone (0 to 1)
#   EventState3 the gas: the seconds (x70) since the valves were opened; negative while they are shut; (after) CurveValue of EventState2
# Gas on the host (valves open): a coughing fit (Gased1 / Gased2), he collapses over 15-35 s and the host dies at 35 s unless the
# valves are shut before. With the chamber lever pulled he walks to the door and out: the event ends (EventState -1) and the chamber
# is left to its two tentacles, which wake when the player steps into it. Positions are raw numbers in the room's scaled space (z
# flipped here). EventState / 2 / 3 are kept by facility.ambient (they outlive the room).

const RS := 8.0 / 2048.0
const Tentacle = preload("res://scripts/npc/scp_tentacle.gd")

const DEATH_GAS := "Class D Subject D-9341 found dead inside SCP-035's containment chamber. The subject exhibits heavy hemorrhaging of blood vessels around the eyes and inside the mouth and nose. Sent for autopsy."

var room: FacilityRoom
var levers: Array[Node3D] = []
var host: CharacterBody3D = null          # NPC[0]
var tentacles: Array[Node3D] = [null, null]   # NPC[0] and NPC[1] after the host has gone
var _voice: AudioStreamPlayer3D = null     # the host's SoundChn
var _whisper_a: AudioStreamPlayer3D = null
var _whisper_b: AudioStreamPlayer3D = null
var _restored := false
var _was_here := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	for i in 2:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		lever.setup(Vector3(210.0 * RS, 224.0 * RS, (208.0 - i * 76.0) * RS), -90.0, -80.0, 0.04)
		levers.append(lever)

func _point(x: float, y: float, z: float) -> Vector3:
	return room.to_global(Vector3(x * RS, y * RS, -z * RS))

func _object(index: int) -> Vector3:
	return room.object_point(index)

func _exit_tree() -> void:
	_stop_whispers()
	if GameState.music_override == "The Dread" and _was_here:
		GameState.music_override = ""

func _stop_whispers() -> void:
	for voice in [_whisper_a, _whisper_b]:
		if voice != null and is_instance_valid(voice):
			(voice as AudioStreamPlayer3D).stop()
			(voice as AudioStreamPlayer3D).queue_free()
	_whisper_a = null
	_whisper_b = null

func _spawn_host(facility: FacilityMap) -> CharacterBody3D:
	var at := _object(4)
	var body: CharacterBody3D = facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(at.x, room.global_position.y + 0.2, at.z), -1, "GFX/npcs/035.b3d")
	body.add_to_group("scp035_host")
	body.set_frame(501.0)
	body.state = 6
	body.rotation.y = room.rotation.y + deg_to_rad(270.0)
	return body

func _find_host() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("scp035_host"):
		if is_instance_valid(node):
			return node
	return null

func _say(relative: String) -> void:
	if _voice != null and is_instance_valid(_voice):
		_voice.stop()
		_voice.queue_free()
	_voice = Sfx.play_at(room, relative, 6.0)

func _voice_playing() -> bool:
	return _voice != null and is_instance_valid(_voice) and _voice.playing

# PointEntity host, target and RotateEntity the collider by CurveAngle(yaw, yaw of the collider, smooth)
func _turn_host_to(point: Vector3, smooth: float, fps: float) -> void:
	var flat := Vector2(point.x - host.global_position.x, point.z - host.global_position.z)
	if flat.length() < 0.0001:
		return
	var yaw_to := atan2(-flat.x, -flat.y)
	host.rotation.y += wrapf(yaw_to - host.rotation.y, -PI, PI) / maxf(smooth, 1.0) * fps

func _host_distance(point: Vector3) -> float:
	return host.global_position.distance_to(point)

func _gas(on: bool) -> void:
	var jets: Array = room.jets
	if jets.size() < 2:
		return
	for jet in jets:
		var local: Vector3 = room.to_local(jet.pos)
		local.y = 424.0 * RS if on else 10.0
		jet.pos = room.to_global(local)

func _crossed(before: float, after: float, seconds: float) -> bool:
	return after > seconds * 70.0 and before <= seconds * 70.0

func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active or levers.size() < 2:
		return
	var fps := delta * 70.0
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	if not _restored:
		_restored = true
		if st.has("lever0"):
			for i in 2:
				levers[i].pitch = float(st["lever%d" % i])
	for i in 2:
		st["lever%d" % i] = levers[i].pitch
	var here: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if not here:
		_outside(facility, player, st)
		return
	_was_here = true
	if st.s == 0.0:
		var spot := _object(3)
		if player.global_position.distance_to(spot) < 2.0:
			host = _spawn_host(facility)
			st.s = 1.0
		return
	if st.s > 0.0:
		_host_phase(facility, player, st, fps)
	else:
		_after_phase(facility, player, st, fps)

# not in the room: the host stays; before the first visit a sound is played from 20 m; after 035 left the tentacles are removed
func _outside(facility: FacilityMap, player: CharacterBody3D, st: Dictionary) -> void:
	if _was_here:
		_was_here = false
		_stop_whispers()
		if GameState.music_override == "The Dread":
			GameState.music_override = ""
	if st.s == 0.0:
		if not st.has("proximity") and player.global_position.distance_to(room.global_position) < 20.0:
			st.proximity = 1.0
			Sfx.play_global(self, "SFX/Room/035Chamber/InProximity.ogg")
	elif st.s < 0.0:
		for i in 2:
			if tentacles[i] != null and is_instance_valid(tentacles[i]):
				tentacles[i].queue_free()
			tentacles[i] = null

func _host_phase(facility: FacilityMap, player: CharacterBody3D, st: Dictionary, fps: float) -> void:
	if host == null or not is_instance_valid(host):
		host = _find_host()
		if host == null:
			# a loaded game: the host is not saved
			host = _spawn_host(facility)
			host.state = 0
			host.set_frame(210.0)
	var s := GameState
	var before: float = st.s
	if st.s == 1.0:
		var spot := _object(3)
		if player.global_position.distance_to(spot) < 1.2 and _host_in_view(player.camera):
			s.give_achievement("035")
			Sfx.play_global(self, "SFX/SCP/035/GetUp.ogg")
			st.s = 1.5
		return
	var storage: Node3D = room.door_slots.get(3)
	if storage != null and storage.open:
		st.s2 = maxf(st.s2, 1.0)
	var door_lever: Node3D = levers[0]
	var gas_lever: Node3D = levers[1]
	door_lever.locked = st.s2 == 20.0
	if not door_lever.is_on():
		_closed(player, st, fps, gas_lever.is_on(), before)
	else:
		_opened(facility, player, st, fps)

# EntityInView on a mesh tests its bounding box, not one point
func _host_in_view(camera: Camera3D) -> bool:
	var mesh_node: MeshInstance3D = host._visual.mesh_instance
	var box: AABB = mesh_node.global_transform * mesh_node.get_aabb()
	for plane in camera.get_frustum():
		var corner := Vector3(
			box.position.x if plane.normal.x > 0.0 else box.end.x,
			box.position.y if plane.normal.y > 0.0 else box.end.y,
			box.position.z if plane.normal.z > 0.0 else box.end.z)
		if plane.is_point_over(corner):
			return false
	return true

func _closed(player: CharacterBody3D, st: Dictionary, fps: float, valves: bool, before: float) -> void:
	var s := GameState
	var open_gas: bool = valves or (st.s3 > 25.0 * 70.0 and st.s3 < 50.0 * 70.0)
	if open_gas:
		_gas(valves)
		if st.s3 > -30.0 * 70.0:
			var prev: float = absf(st.s3)
			st.s3 = absf(st.s3) + fps
			if st.s3 > 1.0 and prev <= 1.0:
				host.state = 0
				_say("SFX/SCP/035/Gased1.ogg")
			elif st.s3 > 15.0 * 70.0 and st.s3 < 25.0 * 70.0:
				if prev <= 15.0 * 70.0:
					_say("SFX/SCP/035/Gased2.ogg")
					host.set_frame(553.0)
				host.state = 6
				host.animate(553.0, 529.0, -0.12, fps, false)
			elif st.s3 > 25.0 * 70.0 and st.s3 < 35.0 * 70.0:
				host.state = 6
				host.animate(529.0, 524.0, -0.08, fps, false)
			elif st.s3 > 35.0 * 70.0:
				if host.state == 6:
					s.sanity = -150.0 * sin(deg_to_rad(host.frame - 524.0)) * 9.0
					host.animate(524.0, 553.0, 0.08, fps, false)
					if host.frame == 553.0:
						host.state = 0
				if prev <= 35.0 * 70.0:
					_say("SFX/SCP/035/GasedKilled1.ogg")
					Sfx.play_global(self, "SFX/SCP/035/KilledGetUp.ogg")
					st.s = 60.0 * 70.0
		return
	# the gas valves are shut
	if host.state == 6:
		if host.frame >= 501.0 and host.frame <= 523.0:
			host.animate(501.0, 523.0, 0.08, fps, false)
			if host.frame == 523.0:
				host.state = 0
		if host.frame >= 524.0 and host.frame <= 553.0:
			host.animate(524.0, 553.0, 0.08, fps, false)
			if host.frame == 553.0:
				host.state = 0
	_gas(false)
	if host.state == 0:
		_turn_host_to(player.global_position, 15.0, fps)
		if randf() < fps / 500.0:
			host.state2 = 1.0 if _host_distance(_object(4)) > 2.0 else 0.0
			host.state = 1
	elif host.state == 1:
		if host.state2 == 1.0:
			_turn_host_to(_object(4), 15.0, fps)
			if _host_distance(_object(4)) < 0.2:
				host.state = 0
		else:
			host.rotation.y += wrapf(room.rotation.y + deg_to_rad(-180.0) - host.rotation.y, -PI, PI) / 15.0 * fps
			if _host_distance(_object(4)) > 2.0:
				host.state = 0
	if st.s3 > 0.0:
		st.s3 = -st.s3
		if st.s3 < -35.0 * 70.0:
			_say("SFX/SCP/035/GasedKilled2.ogg")
			st.s = 60.0 * 70.0
		else:
			if st.s3 < -20.0 * 70.0:
				_say("SFX/SCP/035/GasedStop2.ogg")
			else:
				st.s3 = -21.0 * 70.0
				_say("SFX/SCP/035/GasedStop1.ogg")
			st.s = 61.0 * 70.0
		return
	st.s += fps
	_talk(st, fps)

# the host's speeches (e\EventState counts up through them), with the closet (the storage room) lines
func _talk(st: Dictionary, fps: float) -> void:
	if _crossed(st.s - fps, st.s, 4.0):
		_say("SFX/SCP/035/Help1.ogg")
		st.s = 10.0 * 70.0
	elif _crossed(st.s - fps, st.s, 20.0):
		_say("SFX/SCP/035/Help2.ogg")
	elif _crossed(st.s - fps, st.s, 40.0):
		_say("SFX/SCP/035/Idle1.ogg")
	elif _crossed(st.s - fps, st.s, 50.0):
		_say("SFX/SCP/035/Idle2.ogg")
	elif _crossed(st.s - fps, st.s, 80.0):
		if st.s2 != 0.0:    # skip the closet part if the player has already opened it
			st.s = 130.0 * 70.0
		elif st.s3 < -30.0 * 70.0:    # the host is dead
			_say("SFX/SCP/035/GasedCloset.ogg")
		elif st.s3 == 0.0:    # the gas valves have not been opened
			_say("SFX/SCP/035/Closet1.ogg")
		else:    # the valves were opened but 035 is not dead
			_say("SFX/SCP/035/GasedCloset.ogg")
	elif st.s > 80.0 * 70.0:
		if st.s2 != 0.0:
			st.s = maxf(st.s, 100.0 * 70.0)
		if _crossed(st.s - fps, st.s, 110.0):
			if st.s2 != 0.0:
				_say("SFX/SCP/035/Closet2.ogg")
				st.s = 130.0 * 70.0
			else:
				_say("SFX/SCP/035/Idle3.ogg")
		elif _crossed(st.s - fps, st.s, 125.0):
			if st.s2 != 0.0:
				_say("SFX/SCP/035/Closet2.ogg")
			else:
				_say("SFX/SCP/035/Idle4.ogg")
		elif _crossed(st.s - fps, st.s, 150.0):
			_say("SFX/SCP/035/Idle5.ogg")
		elif _crossed(st.s - fps, st.s, 200.0):
			_say("SFX/SCP/035/Idle6.ogg")

# the player has pulled the chamber lever: the host is let out
func _opened(facility: FacilityMap, player: CharacterBody3D, st: Dictionary, fps: float) -> void:
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	var door_c: Node3D = room.door_slots.get(2)
	if st.s2 < 10.0:
		if door_c != null:
			door_c.open = false
			door_c.locked = true
		if door_b != null and not door_b.open:
			door_a.locked = false
			door_b.locked = false
			door_b.toggle()
			door_a.locked = true
			door_b.locked = true
		if st.s3 == 0.0:
			_say("SFX/SCP/035/Escape.ogg")
		elif absf(st.s3) > 35.0 * 70.0:
			_say("SFX/SCP/035/KilledEscape.ogg")
		else:
			_say("SFX/SCP/035/GasedEscape.ogg")
		st.s2 = 20.0
	if st.s2 != 20.0 or door_a == null or door_b == null:
		return
	var dist := _host_distance(door_a.global_position)
	host.state = 1
	if dist > 2.5:
		_turn_host_to(door_b.global_position, 15.0, fps)
	elif dist > 0.7:
		if _voice_playing():
			host.state = 0
			_turn_host_to(player.global_position, 15.0, fps)
		else:
			_turn_host_to(door_a.global_position, 15.0, fps)
	else:
		facility.remove_human(host)
		host = null
		st.s = -1.0
		st.s2 = 0.0
		st.s3 = 0.0
		door_a.locked = false
		door_b.locked = false
		if door_c != null:
			door_c.locked = false
		door_b.toggle(false)
		for door in facility.doors_near(room.global_position, 4.5):
			if door.heavy and absf(door.global_position.x - room.global_position.x) < 4.5 and absf(door.global_position.z - room.global_position.z) < 4.5:
				door.toggle(false)
				break

# 035 has left: the chamber belongs to the tentacles
func _after_phase(facility: FacilityMap, player: CharacterBody3D, st: Dictionary, fps: float) -> void:
	var s := GameState
	_gas(levers[1].is_on())
	var corner_a := _object(7)
	var corner_b := _object(8)
	var inside: bool = player.global_position.x > minf(corner_a.x, corner_b.x) and player.global_position.x < maxf(corner_a.x, corner_b.x) \
		and player.global_position.z > minf(corner_a.z, corner_b.z) and player.global_position.z < maxf(corner_a.z, corner_b.z)
	var chamber_floor := room.global_position.y
	var guard := false
	if tentacles[0] == null or not is_instance_valid(tentacles[0]):
		_adopt_tentacles()
	if inside:
		guard = true
		s.music_override = "The Dread"      # ShouldPlay = 0: Music(0)
		if tentacles[0] == null or not is_instance_valid(tentacles[0]):
			tentacles[0] = _spawn_tentacle(facility)
		var first := _object(4)
		tentacles[0].global_position = Vector3(first.x, chamber_floor, first.z)
		if tentacles[0].state > 0 and (tentacles[1] == null or not is_instance_valid(tentacles[1])):
			tentacles[1] = _spawn_tentacle(facility)
		player.stamina = _curve(minf(60.0, player.stamina), player.stamina, 20.0, fps)
		if not s.wearing_714 and s.wearing_hazmat < 3 and s.wearing_gas_mask < 3:
			s.sanity -= fps * 1.1
			s.blur_timer = maxf(sin(s.clock_ms() / 10.0 * PI / 180.0) * absf(s.sanity), 0.0)
		if s.wearing_hazmat == 0:
			s.injuries += fps / 5000.0
		else:
			s.injuries += fps / 10000.0
		st.s2 = minf(st.s2 + fps / 6000.0, 1.0)
		st.s3 = _curve(st.s2, st.s3, 50.0, fps)
		if s.bloodloss >= 100.0:
			s.death_msg = DEATH_GAS
		if _whisper_a == null or not is_instance_valid(_whisper_a):
			_whisper_a = _start_whisper("SFX/Room/035Chamber/Whispers1.ogg")
		if _whisper_b == null or not is_instance_valid(_whisper_b):
			_whisper_b = _start_whisper("SFX/Room/035Chamber/Whispers2.ogg")
	elif GameState.music_override == "The Dread":
		GameState.music_override = ""
	if tentacles[1] != null and is_instance_valid(tentacles[1]):
		tentacles[1].global_position = Vector3(room.global_position.x, chamber_floor, room.global_position.z)
		tentacles[1].room_yaw_limit = room.rotation.y
	if not guard:
		st.s2 = maxf(st.s2 - fps / 2000.0, 0.0)
		st.s3 = maxf(st.s3 - fps / 100.0, 0.0)
	var protected: bool = s.wearing_714 or s.wearing_hazmat >= 3 or s.wearing_gas_mask >= 3
	if st.s3 > 0.0 and not protected:
		if _whisper_a != null and is_instance_valid(_whisper_a):
			_whisper_a.volume_db = linear_to_db(maxf(st.s3, 0.0001))
		if _whisper_b != null and is_instance_valid(_whisper_b):
			_whisper_b.volume_db = linear_to_db(maxf((st.s3 - 0.5) * 2.0, 0.0001))
	else:
		for voice in [_whisper_a, _whisper_b]:
			if voice != null and is_instance_valid(voice):
				(voice as AudioStreamPlayer3D).volume_db = -80.0

# after a load the tentacles are back in the world: the one at Objects[4] is the first, the one at the room's middle the second
func _adopt_tentacles() -> void:
	for node in get_tree().get_nodes_in_group("tentacle"):
		if not is_instance_valid(node) or node.in_offices:
			continue
		var flat := Vector2(node.global_position.x - room.global_position.x, node.global_position.z - room.global_position.z)
		var first := _object(4)
		if Vector2(node.global_position.x - first.x, node.global_position.z - first.z).length() < 0.5:
			tentacles[0] = node
		elif flat.length() < 0.5:
			tentacles[1] = node

func _start_whisper(relative: String) -> AudioStreamPlayer3D:
	var stream := Sfx.stream(relative)
	if stream == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.max_distance = 10.0
	voice.volume_db = -80.0
	room.add_child(voice)
	voice.finished.connect(func() -> void: if is_instance_valid(voice): voice.play())
	voice.play()
	return voice

func _spawn_tentacle(facility: FacilityMap) -> Node3D:
	var tentacle := Node3D.new()
	tentacle.set_script(Tentacle)
	facility.get_parent().add_child(tentacle)
	var at := _object(4)
	tentacle.global_position = Vector3(at.x, room.global_position.y, at.z)
	return tentacle
