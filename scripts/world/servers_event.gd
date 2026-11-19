extends Node3D
# The server room (MapSystem.bb FillRoom "room2servers", UpdateEvents.bb Case "room2servers"): the first time the player is
# inside, both doors shut and lock, SCP-096 sits crying in the middle (state 6) and a guard stands at the back. The scene
# runs on `facility.events.servers.state` (frames):
#   < 8 s   096 sways (frames 472-520); the guard faces it
#   8-10 s  096 turns to the side the player is on (521-555 / 556-590), then gets up (state 1) and steps toward them
#   10-20 s 096 is angered (state 1-3, its timer held at 12 s); at 15 s the guard walks to the doorway; once he sees it
#           he stops, the back door (RoomDoors[2]) shuts and he faces it
#   20 s on once 096 is chasing (state 4, which it is set to after 22 s) the guard shoots at it and it takes him as its target;
#           the guard is mauled where 096's jump passes frame 25: ServerRoom2, blood on the walls and floor, 096 walks
#           about (state 5)
#   40 s    the doors open once to let the player in/out; the player cannot walk past 1.3 from the middle without the
#           scene ending (50 s)
# After the scene the three levers matter: the power switch (Objects[0..1], starts up) must be thrown down, and the fuel pump
# and generator (starts down) up, before the two doors unlock; until then they keep shutting and locking.


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var levers: Array[Node3D] = []      # power switch, generator fuel pump, generator on/off
var _generator: AudioStreamPlayer3D
var _voice: AudioStreamPlayer
var _voice_name := ""

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var spots := [
		[Vector3(-1260.0, 234.0, 750.0), 81.0],      # power switch
		[Vector3(-920.0, 164.0, 898.0), -81.0],      # generator fuel pump
		[Vector3(-837.0, 152.0, 886.0), -81.0],      # generator on/off
	]
	for entry in spots:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		var at: Vector3 = entry[0]
		lever.setup(Vector3(at.x * RS, at.y * RS, -at.z * RS), -180.0, float(entry[1]), 0.03)
		levers.append(lever)
	_generator = AudioStreamPlayer3D.new()
	_generator.max_distance = 6.0
	var loop := Sfx.stream("SFX/General/GeneratorOn.ogg")
	if loop != null:
		loop.loop = true
		_generator.stream = loop
	_generator.position = levers[2].position
	add_child(_generator)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)

func _door(slot: int) -> Node3D:
	return room.door_slots.get(slot)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	var fps := delta * 70.0
	var inside: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if facility.events.servers.state == 0.0:
		if inside:
			_begin(facility)
	elif facility.events.servers.state < 70.0 * 45.0:
		_scene(fps, inside, player, facility)
	elif inside:
		_levers(fps)

func _begin(facility: FacilityMap) -> void:
	for slot in [0, 1]:
		var door := _door(slot)
		if door != null:
			door.open = false
			door.locked = true
	var spot: Vector3 = room.object_point(6)
	var yaw := room.rotation.y + deg_to_rad(270.0)
	var shy: Node = facility.scp096
	if shy == null or not is_instance_valid(shy):
		shy = facility.spawn_096(spot + Vector3(0.0, 0.1, 0.0), 6, yaw)
	else:
		shy.global_position = spot + Vector3(0.0, 0.1, 0.0)
		shy.velocity = Vector3.ZERO
	shy.rotation.y = yaw
	shy.state = 6
	shy.state2 = 70.0 * 10.0
	_speak("SFX/Character/Guard/096ServerRoom1.ogg")
	var guard_spot: Vector3 = room.object_point(7)
	facility.events.servers.guard = facility.spawn_human(HumanNpc.Kind.GUARD, NpcGravity.feet(guard_spot), -1)
	facility.events.servers.state = 1.0

func _scene(fps: float, inside: bool, player: CharacterBody3D, facility: FacilityMap) -> void:
	var shy: Node = facility.scp096
	var guard: Node = facility.events.servers.guard
	if guard != null and not is_instance_valid(guard):
		guard = null
		facility.events.servers.guard = null
	if inside:
		if randi_range(1, 200) < 5:
			GameState.light_blink = randf_range(1.0, 2.0)
			if randi_range(1, 5) == 1:
				Sfx.play_at(room, "SFX/Room/Intro/Light%d.ogg" % randi_range(1, 3), 8.0, randf_range(0.1, 0.3))
	facility.events.servers.state = minf(facility.events.servers.state + fps, 70.0 * 43.0)
	var t: float = facility.events.servers.state
	if guard != null and shy != null and is_instance_valid(shy):
		shy.target = guard
		if t < 70.0 * 8.0:
			shy.animate(472.0, 520.0, 0.25, fps)
			_face(guard, shy.global_position)
		elif t < 70.0 * 10.0:
			var near_a: float = player.global_position.distance_to(_door(0).global_position)
			var near_b: float = player.global_position.distance_to(_door(1).global_position)
			var finished := false
			if near_a < near_b:
				shy.animate(521.0, 555.0, 0.25, fps, false)
				finished = shy.frame >= 554.5
			else:
				shy.animate(556.0, 590.0, 0.25, fps, false)
				finished = shy.frame >= 589.5
			if finished:
				facility.events.servers.state = 70.0 * 10.0
				shy.set_frame(677.0)
				shy.state = 1
				shy.rotation.y += PI
				shy.global_position += -shy.global_transform.basis.z * 0.3
			_face(guard, shy.global_position)
		elif t < 70.0 * 20.0:
			shy.state = clampi(shy.state, 1, 3)
			shy.state2 = maxf(shy.state2, 70.0 * 12.0)
			if t - fps <= 70.0 * 15.0:
				if t > 70.0 * 15.0:
					guard.state = 14
					guard.find_path_to(shy.global_position + Vector3(0.0, 0.2, 0.0))
					guard.path_timer = 300.0
				else:
					_face(guard, shy.global_position)
			if _clear(guard.global_position + Vector3(0.0, 0.8, 0.0), shy.global_position + Vector3(0.0, 0.5, 0.0)):
				var back := _door(2)
				if back != null:
					back.open = false
				guard.state = 13
				guard.rotation.y = lerp_angle(guard.rotation.y, _yaw_to(guard, shy.global_position), minf(fps / 30.0, 1.0))
		else:
			if shy.state == 4:
				shy.last_seen = 1
				guard.state = 2
				guard.rotation.y = lerp_angle(guard.rotation.y, _yaw_to(guard, shy.global_position), minf(fps / 30.0, 1.0))
				if inside:
					GameState.light_blink = guard.reload + randf_range(0.5, 2.0)
				shy.target = guard
			else:
				if t > 70.0 * 22.0:
					shy.state = 4
				if guard.state == 13:
					guard.state = 14
					guard.find_path_to(room.global_position + Vector3(0.0, 0.4, 0.0))
					guard.path_timer = 300.0
					guard.speed *= 1.8
		if shy.frame > 25.0 and shy.frame < 150.0 and shy.state == 4:
			_maul(facility, guard, shy)
	else:
		if t >= 70.0 * 40.0 and t - fps < 70.0 * 40.0:
			for slot in [0, 1]:
				var door := _door(slot)
				if door != null:
					door.locked = false
					door.toggle()
					door.locked = true
		if inside:
			if _voice.playing:
				GameState.light_blink = randf_range(0.5, 6.0)
				if randi_range(1, 50) == 1:
					Sfx.play_at(room, "SFX/Room/Intro/Light%d.ogg" % randi_range(1, 3), 8.0, randf_range(0.1, 0.3))
			# the player may not walk out of the middle section along the room's x axis while 096 is crying: the scene is over once they do
			if absf(room.to_local(player.global_position).x) > 1.3:
				facility.events.servers.state = 70.0 * 50.0

func _maul(facility: FacilityMap, guard: Node, shy: Node) -> void:
	_speak("SFX/Character/Guard/096ServerRoom2.ogg")
	shy.curr_speed = 0.0
	for i in 7:
		for side in [-1.0, 1.0]:
			_wall_blood(Vector3(-randf_range(197.0, 199.0) * RS, 1.0, -140.0 * (i - 3) * RS), side * PI * 0.5)
		_floor_blood(guard.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), 1.0 if i < 6 else randf_range(0.5, 0.7))
	shy.state = 5
	shy._stop_music()
	shy.target = null
	facility.remove_human(guard)
	facility.events.servers.guard = null
	facility.events.servers.killed = true

# CreateDecal(Rand(2, 3), ..., size 0.8-0.85, growing 0.001 a frame) on the wall; the decal is a child of the room, so
# its yaw is the room-local angle +-90
func _wall_blood(local_at: Vector3, yaw: float) -> void:
	var texture := "GFX/decal%d.png" % randi_range(3, 4)
	var decal := GrowingDecal.make(room, room.to_global(local_at), texture, randf_range(0.8, 0.85), 0.001, 1.0, false, Vector3.INF, false, true)
	decal.rotation = Vector3(0.0, yaw, randf() * TAU)

func _floor_blood(at: Vector3, size: float) -> void:
	var decal := GrowingDecal.make(room, Vector3(at.x, room.global_position.y + randf_range(0.001, 0.003), at.z), "GFX/decal%d.png" % randi_range(3, 4), size, 0.0, 1.0, false)
	decal.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)

func _levers(fps: float) -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var power_on: bool = levers[0].is_on()
	var pump: bool = levers[1].is_on()
	var generator: bool = levers[2].is_on()
	if pump:
		facility.events.servers.state2 = minf(1.0, facility.events.servers.state2 + fps / 350.0)
		if generator:
			facility.events.servers.state3 = minf(1.0, facility.events.servers.state3 + fps / 450.0)
		else:
			facility.events.servers.state3 = minf(0.0, facility.events.servers.state3 - fps / 450.0)
	else:
		facility.events.servers.state2 = maxf(0.0, facility.events.servers.state2 - fps / 350.0)
		facility.events.servers.state3 = maxf(0.0, facility.events.servers.state3 - fps / 450.0)
	if facility.events.servers.state3 > 0.0:
		_generator.volume_db = linear_to_db(facility.events.servers.state3)
		if not _generator.playing:
			_generator.play()
	elif _generator.playing:
		_generator.stop()
	var door_a := _door(0)
	var door_b := _door(1)
	if not power_on and pump and generator:
		if door_a != null:
			door_a.locked = false
		if door_b != null:
			door_b.locked = false
	else:
		if randi_range(1, 200) < 5:
			GameState.light_blink = randf_range(0.5, 1.0)
		for door in [door_a, door_b]:
			if door != null:
				if door.open:
					door.locked = false
					door.open = false
				door.locked = true

func _speak(file: String) -> void:
	var stream := Sfx.stream(file)
	if stream != null:
		_voice.stream = stream
		_voice.play()
	_voice_name = file

func _face(human: Node3D, point: Vector3) -> void:
	human.rotation.y = _yaw_to(human, point)

func _yaw_to(from: Node3D, point: Vector3) -> float:
	return atan2(-(point.x - from.global_position.x), -(point.z - from.global_position.z))

func _clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
