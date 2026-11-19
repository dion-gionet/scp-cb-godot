extends Node3D
# SCP-049's containment chamber (MapSystem.bb FillRoom "room049", UpdateEvents.bb Case "room049"): the two elevators lead down to
# a dark, unpowered chamber. Down there (below -2848 units):
#  - the first time: a blackout, the map document appears at the nearer storage spot, the two SCP-049-2 on the floor and
#    SCP-049 (hidden, waiting) are made, EventState 1
#  - two levers, the power feed (starts up) and the generator (starts down); for the first second nothing happens, then the
#    elevators are dead (their lower doors locked) until the power feed is down and the generator up. The generator on makes
#    the lights come back (SecondaryLightOn fades to 1) with the fuel pump humming, music "Room049", the three storage room
#    doors unlock; the first moment it is on the event jumps to 180 s: the lower doors are shut and the upper ones opened, and
#    the next frame the zombies get up (EventState 241 * 70).
#  - with the power feed down and the generator up the elevators work again, and when the player comes within 3 of one of the
#    lower doors SCP-049 steps out of that cab and hunts them (DetectedInChamber)
#  - if 049 catches the player down here (EventState -1): they fall, and 4 s later (-280) they wake at the middle of the chamber as
#    one of the infected: the zombies are put at Objects[4] (State 4), 049 goes back to the upper elevator, three Nine-Tailed
#    Fox soldiers stand at Objects[5] (State 6) and the player walks to them by themselves (ForceMove 0.5) until they are shot
# Objects: 0-3 the elevator cabs, 4 and 5 the zombies' spots, 10 the generator's sound, 11 and 12 where the map document lies.


const RS := MeshLoader.ROOM_SCALE
const CHAMBER_Y := -2848.0 * RS

var room: FacilityRoom
var levers: Array[Node3D] = []       # power feed, generator
var _prev_generator := false
var _fuel_pump: AudioStreamPlayer3D = null
var _breath: AudioStreamPlayer = null
var _scene_done := false
var squad: Array[Node] = []          # the three soldiers (tests)

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var spots := [Vector3(852.0 * RS, -3374.0 * RS, 854.0 * RS), Vector3(-834.0 * RS, -3400.0 * RS, -1093.0 * RS)]
	var yaws := [90.0, 0.0]
	for n in 2:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		var start := 81.0 if n == 0 else -11.0
		if facility != null:
			start = float(facility.events.room049.pitches[n])
		lever.setup(spots[n], yaws[n], start, 0.03)
		levers.append(lever)
	_prev_generator = levers[1].is_on()

func _lifts_enabled(value: bool) -> void:
	for lift in room._lifts:
		if is_instance_valid(lift):
			lift.enabled = value

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or levers.is_empty() or not facility.active:
		return
	facility.events.room049.pitches = [levers[0].pitch, levers[1].pitch]
	var fps := delta * 70.0
	var inside: bool = room.world_bounds().has_point(player.global_position)
	var below: bool = inside and room.to_local(player.global_position).y <= CHAMBER_Y
	if below:
		_chamber(player, facility, fps)
	else:
		_lifts_enabled(true)
		_stop_pump()
		if GameState.music_override in ["SaveMeFrom", "Room049"]:
			GameState.music_override = ""
	if facility.events.room049.state < 0.0:
		_captured(player, facility, fps)

func _chamber(player: CharacterBody3D, facility: FacilityMap, fps: float) -> void:
	if GameState.music_override.is_empty() or GameState.music_override == "none":
		GameState.music_override = "SaveMeFrom"
	if facility.events.room049.state == 0.0:
		_first_visit(player, facility)
		return
	if facility.events.room049.state < 0.0:
		return
	var power_off: bool = not levers[0].is_on()      # temp = Not UpdateLever(power feed)
	var generator: bool = levers[1].is_on()
	var door1: Node3D = room.door_slots.get(1)
	var door3: Node3D = room.door_slots.get(3)
	var state: float = facility.events.room049.state
	door1.locked = true
	door3.locked = true
	_lifts_enabled(false)
	if generator != _prev_generator:
		Sfx.play_global(self, "SFX/Room/Tesla/PowerUp.ogg" if generator else "SFX/General/LightSwitch.ogg")
	_prev_generator = generator
	if state >= 70.0:
		if generator:
			GameState.music_override = "Room049"
			state = maxf(state, 70.0 * 180.0)
			GameState.secondary_light += (1.0 - GameState.secondary_light) * minf(fps / 10.0, 1.0)
			_pump(true)
			for slot in [4, 5, 6]:
				if room.door_slots.has(slot):
					room.door_slots[slot].locked = false
		else:
			GameState.secondary_light += (0.0 - GameState.secondary_light) * minf(fps / 10.0, 1.0)
			_pump(false)
			for slot in [4, 5, 6]:
				if room.door_slots.has(slot):
					room.door_slots[slot].locked = true
	else:
		state = minf(state + fps, 70.0)
	if power_off and generator:
		door1.locked = false
		door3.locked = false
		_lifts_enabled(true)
		_dispatch_049(player, facility, door1, door3)
	if state < 70.0 * 190.0:
		if state >= 70.0 * 180.0:
			door1.open = false
			door3.open = false
			room.door_slots[0].open = true
			room.door_slots[2].open = true
			state = 70.0 * 190.0
	elif state < 70.0 * 240.0:
		for zombie in facility.zombies008:
			if is_instance_valid(zombie) and zombie.get("kind") == "049-2" and zombie.state == 0:
				zombie.set_state(1)
				zombie.set_frame(155.0)
		state = 70.0 * 241.0
	facility.events.room049.state = state

func _first_visit(player: CharacterBody3D, facility: FacilityMap) -> void:
	Sfx.play_global(self, "SFX/Room/Blackout.ogg")
	var near_first := player.global_position.distance_to(room.object_point(11)) < player.global_position.distance_to(room.object_point(12))
	var spot: Vector3 = room.object_point(11 if near_first else 12)
	var scheme := RoomFill.make_pickup("Research Sector-02 Scheme", "paper")
	GameState.player.get_parent().add_child(scheme)
	scheme.global_position = spot
	# the two zombies, lying where the cells are, one turned 190 degrees from the room's centre and one 20
	for i in 2:
		var at: Vector3 = room.object_point(4 + i)
		var zombie: Node = facility.spawn_zombie049(NpcGravity.feet(at), 0)
		var toward: Vector3 = room.global_position - at
		zombie.rotation.y = atan2(-toward.x, -toward.z) + deg_to_rad(190.0 if i == 0 else 20.0)
	if facility.scp049 == null or not is_instance_valid(facility.scp049):
		facility.spawn_049(1.0)
	var man: Node = facility.scp049
	man.state = 2
	man.idle = 1.0
	man.global_position = room.object_point(4) + Vector3(0.0, 3.0, 0.0)
	facility.events.room049.state = 1.0

# 049 comes out of the elevator the player is near, once the chamber has power.
func _dispatch_049(player: CharacterBody3D, facility: FacilityMap, door1: Node3D, door3: Node3D) -> void:
	var man: Node = facility.scp049
	if man == null or not is_instance_valid(man) or man.idle <= 0.0:
		return
	var which := 0
	if player.global_position.distance_to(door1.global_position) < 3.0:
		which = 1
	elif player.global_position.distance_to(door3.global_position) < 3.0:
		which = 3
	if which == 0:
		return
	man.global_position = room.object_point(which)
	man.velocity = Vector3.ZERO
	Sfx.play_at(man, "SFX/General/Elevator/Beep.ogg", 4.0)
	var door: Node3D = room.door_slots[which]
	door.locked = false
	door.open = true
	room.door_slots[which - 1].open = false
	man.idle = 0.0
	man.prev_state = 2
	man.state = 2
	man._speak("SFX/SCP/049/DetectedInChamber.ogg")

func _pump(on: bool) -> void:
	if not on:
		_stop_pump()
		return
	if _fuel_pump == null or not is_instance_valid(_fuel_pump):
		_fuel_pump = Sfx.play_at(self, "SFX/Ambient/Room ambience/fuelpump.ogg", 6.0)
		if _fuel_pump != null:
			_fuel_pump.global_position = room.object_point(10)
			var stream := _fuel_pump.stream as AudioStreamOggVorbis
			if stream != null:
				stream.loop = true
	elif not _fuel_pump.playing:
		_fuel_pump.play()

func _stop_pump() -> void:
	if _fuel_pump != null and is_instance_valid(_fuel_pump):
		_fuel_pump.stop()
	_fuel_pump = null

func _captured(player: CharacterBody3D, facility: FacilityMap, fps: float) -> void:
	var state: float = facility.events.room049.state
	if _scene_done:
		return
	if state > -70.0 * 4.0:
		GameState.infect = 0.0
		if player.fall_timer >= 0.0:
			player.start_fall()
		elif player.fall_timer < -230.0:
			player.fall_timer = -231.0
			player.blink_timer = 0.0
			state -= fps
			if state <= -70.0 * 4.0:
				_wake_as_zombie(player, facility)
			facility.events.room049.state = state
		return
	var s := GameState
	s.blur_timer = 800.0
	s.force_move = 0.5
	s.injuries = maxf(2.0, s.injuries)
	s.bloodloss = 0.0
	s.infect = 0.0
	if squad.is_empty() or not is_instance_valid(squad[0]):
		return
	var to_first: Vector3 = squad[0].global_position + Vector3(0.0, 0.2, 0.0) - player.camera.global_position
	player.rotation.y = atan2(-to_first.x, -to_first.z)
	var pitch := atan2(to_first.y, Vector2(to_first.x, to_first.z).length())
	player.camera.rotation.x = pitch
	player.user_pitch = -rad_to_deg(pitch)
	if player.dead:
		Sfx.play_global(self, "SFX/Character/MTF/049/Player0492_2.ogg")
		_scene_done = true
		if _breath != null and is_instance_valid(_breath):
			_breath.stop()
	elif _breath == null or not is_instance_valid(_breath) or not _breath.playing:
		_breath = Sfx.play_global(self, "SFX/SCP/049/0492Breath.ogg")

func _wake_as_zombie(player: CharacterBody3D, facility: FacilityMap) -> void:
	player.fall_timer = 0.0
	player.blink_timer = -10.0
	var centre: Vector3 = room.global_position
	var floor_spot: Vector3 = room.object_point(5)
	player.global_position = Vector3(centre.x, floor_spot.y + 0.2, centre.z)
	player.velocity = Vector3.ZERO
	var man: Node = facility.scp049
	if man != null and is_instance_valid(man):
		man.global_position = room.object_point(0)
		man.velocity = Vector3.ZERO
	for zombie in facility.zombies008:
		if is_instance_valid(zombie) and zombie.get("kind") == "049-2":
			zombie.global_position = room.object_point(4)
			zombie.velocity = Vector3.ZERO
			zombie.set_state(4)
	squad.clear()
	var at: Vector3 = room.object_point(5) + Vector3(0.0, 0.2, 0.0)
	var yaw := atan2(-(player.global_position.x - at.x), -(player.global_position.z - at.z))
	for i in 3:
		var unit: Node = facility.mtf.spawn(at)
		unit.state = 6
		unit.reload = 70.0 * 6.0 + (randf_range(15.0, 30.0) if i > 0 else 0.0)
		unit.rotation.y = yaw
		unit.angle = yaw
		if i == 1:
			unit.global_position += Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.5
		elif i == 2:
			unit.global_position += Vector3(cos(yaw), 0.0, -sin(yaw)) * -0.65
			unit.state2 = yaw
		squad.append(unit)
	Sfx.play_global(self, "SFX/Character/MTF/049/Player0492_1.ogg")
	GameState.is_zombie = true
	facility.events.room049.state = -70.0 * 4.0

func _exit_tree() -> void:
	if GameState.music_override in ["SaveMeFrom", "Room049"]:
		GameState.music_override = ""
