extends Node
# The events of UpdateEvents.bb that the rooms run on their own: scares, relocations of the SCPs and small set pieces. The event
# plan (event_plan.gd, InitEvents) says which room holds which one; this node runs them every physics frame, the way
# UpdateEvents does, and keeps their EventState / EventState2 / EventState3 (`states[key]` = {s, s2, s3}). RemoveEvent is
# `removed[key]`. Both are saved. An event's handler is `_ev_<name>(rec, st, c)`: `rec` is the room's record, `st` its state, and `c`
# says where the player is: dist (r\dist, the larger of the x and z offsets), in_room (PlayerRoom = e\room), room (the room node),
# fps, player, key.
# Local positions in the original are in the room's own scaled space (RoomScale applies to a child of the room); here
# `to_world(room, x, y, z)` takes the raw numbers and flips z.


const RS := 8.0 / 2048.0
const HIDE_DISTANCE := NpcGravity.HIDE_DISTANCE

var facility: FacilityMap
var plan: RefCounted
var states: Dictionary = {}
var removed: Dictionary = {}
var _records: Dictionary = {}          # key -> room record
var _nodes: Dictionary = {}            # key -> {name: Node} things an event made (not saved)
var _handlers: Dictionary = {}         # key -> Callable
var enabled := true                    # the other test scenarios switch the events off so that nothing moves what they set up
var packs: Array = []                  # the nodes whose _ev_<name> methods are the events: this one and the packs below

const PACKS := [preload("res://scripts/world/ambient_events_106.gd"), preload("res://scripts/world/ambient_events_rooms.gd"), preload("res://scripts/world/ambient_events_gw_b.gd")]

func setup(facility_node: Node3D) -> void:
	facility = facility_node
	plan = EventPlan.build(facility.generator.rooms, int(facility.generator.rng_before_events), GameState.aggressive_npcs())
	_records.clear()
	for room in facility.generator.rooms:
		_records[room.key] = room
	_handlers.clear()
	packs = [self]
	for script in PACKS:
		var pack: Node = script.new()
		pack.host = self
		pack.name = "Pack%d" % packs.size()
		add_child(pack)
		packs.append(pack)
	for key in plan.plan:
		_register(key, str(plan.plan[key]))

func _register(key: String, event_name: String) -> void:
	var handler := "_ev_" + event_name
	for pack in packs:
		if pack.has_method(handler):
			_handlers[key] = Callable(pack, handler)
			return

func event_of(key: String) -> String:
	return "" if removed.has(key) else plan.event_of(key)

# Tests (and nothing else) give a room an event of their choosing.
func force(key: String, event_name: String) -> void:
	plan.plan[key] = event_name
	removed.erase(key)
	states.erase(key)
	_nodes.erase(key)
	_handlers.erase(key)
	_register(key, event_name)

func state_of(key: String) -> Dictionary:
	if not states.has(key):
		states[key] = {"s": 0.0, "s2": 0.0, "s3": 0.0}
	return states[key]

func _remove(key: String) -> void:
	removed[key] = true
	_handlers.erase(key)

func save_data() -> Dictionary:
	return {"states": states, "removed": removed.keys()}

func load_data(data: Dictionary) -> void:
	states = (data.get("states", {}) as Dictionary).duplicate(true)
	removed = {}
	for key in data.get("removed", []):
		removed[str(key)] = true
		_handlers.erase(str(key))

func _physics_process(delta: float) -> void:
	if not enabled or facility == null or not facility.active or GameState.player == null or plan == null:
		return
	var player: CharacterBody3D = GameState.player
	var ppos := player.global_position
	if _updates_endings_only(ppos):
		return
	var player_key := str(facility.drawing.drawn_from.get("key", ""))      # PlayerRoom
	var c := {"player": player, "fps": delta * 70.0, "in_room": false, "dist": 0.0, "room": null, "key": ""}
	for key in _handlers.keys():
		if not _handlers.has(key):
			continue             # removed by an earlier handler this frame
		var rec: Dictionary = _records[key]
		c.key = key
		c.dist = RoomRegistry.room_dist(rec.position, ppos)
		c.in_room = key == player_key
		c.room = facility.rooms.built.get(key)
		(_handlers[key] as Callable).call(rec, state_of(key), c)

# Main.bb 2965-2985: in dimension 1499, in gate A and above ground at exit1 the main loop runs UpdateDimension1499 / UpdateEndings
# instead of UpdateEvents.
func _updates_endings_only(ppos: Vector3) -> bool:
	var here: String = facility.room_name_at(ppos)
	return here == "dimension1499" or here == "gatea" or (here == "exit1" and ppos.y > 1040.0 * RS)

# Raw local numbers of the original (x, y, z) in a room's scaled space -> world.
func to_world(rec: Dictionary, x: float, y: float, z: float) -> Vector3:
	var angle := deg_to_rad(float(rec.angle))
	var local := Vector3(x * RS, y * RS, -z * RS)
	return Vector3(rec.position.x, rec.position.y, rec.position.z) + local.rotated(Vector3.UP, angle)

func _statue() -> Node3D:
	return GameState.scp173 as Node3D

func _in_view(player: CharacterBody3D, point: Vector3) -> bool:
	return player.camera.is_position_in_frustum(point)

func _statue_in_view(player: CharacterBody3D) -> bool:
	var s := _statue()
	return s != null and _in_view(player, s.global_position + Vector3(0.0, 0.8, 0.0))

func _put_173(centre: Vector3) -> void:
	var s := _statue()
	if s != null:
		s.put_at_collider(centre)

func _valid(node: Variant) -> Node3D:
	return node as Node3D if node != null and is_instance_valid(node) else null

func _visible_between(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b)
	query.collision_mask = 1
	return facility.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _loop_at(parent: Node3D, relative: String, range_m: float, volume: float = 1.0) -> AudioStreamPlayer3D:
	var source := Sfx.stream(relative)
	if source == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = source
	voice.max_distance = range_m
	voice.volume_db = linear_to_db(volume)
	parent.add_child(voice)
	voice.finished.connect(func() -> void: if is_instance_valid(voice): voice.play())
	voice.play()
	return voice

func _dead_guard(at: Vector3, yaw: float, frame: float) -> Node3D:
	var guard: Node3D = facility.spawn_human(0, at)
	guard.state = 8
	guard.is_dead = true
	guard.rotation.y = yaw
	guard.set_frame(frame)
	return guard

# PointEntity of an entity toward a point, as the yaw of a node (the node's -Z is the way it looks)
func _yaw_toward(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

# "096spawn": once 096 has been put somewhere, it can be put into another room the player is near, standing with its back to them
# (State 5), unless it is close, enraged, in the way of the servers scene or the checkpoint, or the room is farther from it than the
# player. EventState 0 free, 1 placed, 2 resting, 3 resting until the player has been away.
func _ev_096spawn(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	if c.dist >= HIDE_DISTANCE:
		if st.s == 2.0:
			var aggressive := GameState.aggressive_npcs()
			st.s = 0.0 if randi_range(-1, 1 + (2 if aggressive else 0)) > 0 else 3.0
		return
	var centre := Vector3(rec.position.x, rec.position.y, rec.position.z)
	if st.s != 2.0:
		var big := _valid(facility.scp096)
		if big != null:
			if big.global_position.distance_to(player.global_position) < 40.0:
				st.s = 2.0
			if facility.events.servers.state > 0.0 and facility.events.servers.guard != null and is_instance_valid(facility.events.servers.guard):
				st.s = 2.0
			for other in facility.generator.rooms:
				if str(other.name) == "checkpoint1" and RoomRegistry.room_dist(other.position, player.global_position) < 10.0:
					st.s = 2.0
			if big.state != 5:
				st.s = 2.0
			if big.global_position.distance_to(centre) > big.global_position.distance_to(player.global_position):
				st.s = 2.0
		if facility.events.servers.state == 0.0:
			st.s = 2.0
		if c.in_room:
			st.s = 2.0
	if st.s == 0.0:
		var local := Vector2.ZERO
		match str(rec.name):
			"room4pit", "room3pit", "room3z2", "room4tunnels", "room3tunnel":
				var place := randi_range(0, 3) if str(rec.name) in ["room4pit", "room4tunnels"] else randi_range(0, 2)
				local = [Vector2(-608.0, 0.0), Vector2(0.0, -608.0), Vector2(608.0, 0.0), Vector2(0.0, 608.0)][place]
			_:
				local = Vector2(randf_range(-100.0, 100.0), randf_range(-100.0, 100.0))
		var at: Vector3 = to_world(rec, local.x, 0.0, local.y)
		at.y = rec.position.y + 0.05
		var away := _yaw_toward(at, player.global_position) + PI
		var shy := _valid(facility.scp096)
		if shy == null:
			shy = facility.spawn_096(at, 5, away)
		else:
			shy.global_position = at
			shy.velocity = Vector3.ZERO
			shy.rotation.y = away
		shy.state = 5
		st.s = 1.0
	elif st.s == 1.0:
		var shy := _valid(facility.scp096)
		if shy == null:
			return
		shy.rotation.y = _yaw_toward(shy.global_position, player.global_position) + PI
		if shy.global_position.distance_to(player.global_position) < HIDE_DISTANCE * 0.5 and _visible_between(shy.global_position + Vector3(0.0, 0.5, 0.0), player.camera.global_position):
			shy.rotation.y = _yaw_toward(shy.global_position, player.global_position) + deg_to_rad(randf_range(170.0, 190.0))
			st.s = 2.0
	elif st.s == 3.0:
		st.s = 2.0

# "lockroom173": when the player comes near a lock room, 173 is put inside it unless it is seen (or far from them)
func _ev_lockroom173(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if c.dist >= 6.0 or c.dist <= 0.0:
		return
	var s := _statue()
	if s == null:
		return
	if s.idle > 1:
		_remove(c.key)
	elif not _statue_in_view(c.player) or s.global_position.distance_to(c.player.global_position) > 15.0:
		var a := deg_to_rad(225.0 - 90.0 + float(rec.angle))
		_put_173(Vector3(rec.position.x + cos(a) * 2.0, rec.position.y + 0.6, rec.position.z - sin(a) * 2.0))
		_remove(c.key)

# "room2doors173": 173 waits at Objects[0] the first time the player is in the room and it is not in view
func _ev_room2doors173(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var s := _statue()
	if s != null and st.s == 0.0 and s.idle == 0 and not _statue_in_view(c.player):
		st.s = 1.0
		var spot: Vector3 = c.room.object_point(0)
		_put_173(Vector3(spot.x, rec.position.y + 0.5, spot.z))
		_remove(c.key)

# "tunnel2": a light scare. Within 3.5 of the middle the lights flicker, the eyes shut, and 173 is put in the middle of the room
# while they are shut.
func _ev_tunnel2(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	var s := _statue()
	if c.in_room:
		if s != null and s.idle > 1:
			_remove(c.key)
			return
		if st.s == 0.0:
			if Vector2(player.global_position.x - rec.position.x, player.global_position.z - rec.position.z).length() < 3.5:
				Sfx.play_global(self, "SFX/General/LightSwitch.ogg")
				GameState.light_blink = 0.0
				st.s = 1.0
	if st.s > 0.0 and st.s < 200.0:
		player.blink_timer = -10.0
		if st.s > 30.0:
			GameState.light_blink = 1.0
			if st.s - c.fps <= 30.0:
				Sfx.play_global(self, "SFX/Ambient/General/ambient3.ogg")
		if st.s - c.fps <= 100.0 and st.s > 100.0:
			Sfx.play_global(self, "SFX/Ambient/General/ambient6.ogg")
			if s != null:
				_put_173(Vector3(rec.position.x, rec.position.y + 0.6, rec.position.z))
				s.idle = 1
		GameState.light_blink = 1.0
		st.s += c.fps
	elif st.s != 0.0:
		player.blink_timer = player.blink_freq
		if s != null:
			s.idle = 0
		_remove(c.key)

# "room2trick": at the middle of the room the player is carried to the opposite side and turned round, unless 173 or 106 are close
func _ev_room2trick(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var player: CharacterBody3D = c.player
	var centre := Vector3(rec.position.x, rec.position.y + 0.5, rec.position.z)
	if (player.global_position + Vector3(0.0, 0.5, 0.0)).distance_to(centre) >= 2.0:
		return
	var s := _statue()
	var old_man := _valid(facility.scp106)
	if (s != null and s.global_position.distance_to(player.global_position) < 6.0) or (old_man != null and old_man.global_position.distance_to(player.global_position) < 6.0):
		_remove(c.key)
		return
	var p := player.global_position
	player.blink_timer = -10.0
	Sfx.play_global(self, "SFX/Horror/Horror11.ogg")
	player.global_position = Vector3(2.0 * rec.position.x - p.x, p.y + 0.05, 2.0 * rec.position.z - p.z)
	player.velocity = Vector3.ZERO
	facility.after_teleport()
	player.rotate_y(PI)
	_remove(c.key)

# "room3door": near the middle of the room the nearest open door closes behind the player's back, with a jolt
func _ev_room3door(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var player: CharacterBody3D = c.player
	if (player.global_position + Vector3(0.0, 0.5, 0.0)).distance_to(Vector3(rec.position.x, rec.position.y + 0.5, rec.position.z)) >= 2.5:
		return
	var near: Node3D = null
	var near_dist := INF
	for door in facility.doors_near(player.global_position, 3.0):
		if door.elevator or absf(door.global_position.x - player.global_position.x) >= 2.0 or absf(door.global_position.z - player.global_position.z) >= 2.0:
			continue
		var d: float = door.global_position.distance_to(player.global_position)
		if d < near_dist:
			near = door
			near_dist = d
	if near != null and not _in_view(player, near.global_position) and near.open:
		near.snap_shut()
		GameState.blur_timer = 100.0
		player.camera_shake = 3.0
	_remove(c.key)

# "room1archive" (UpdateEvents.bb 8686): the first pass rolls the card level, every later pass sets the door to it
func _ev_room1archive(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if st.s == 0.0:
		st.s = float(randi_range(1, 3))
		return
	var room: FacilityRoom = c.room
	if room != null and not room._fill_doors.is_empty():
		room._fill_doors[0].keycard = int(st.s)

# "room2offices3": 700 frames into the player's stay the door shuts by itself once they are away from it and not looking at it
func _ev_room2offices3(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	st.s += c.fps
	if st.s > 700.0:
		var door: Node3D = c.room.door_slots.get(0)
		var player: CharacterBody3D = c.player
		if door == null:
			_remove(c.key)
			return
		if door.global_position.distance_to(player.global_position + Vector3(0.0, 0.5, 0.0)) > 0.5 and not _in_view(player, door.global_position):
			if door.open:
				door.toggle(false)
			_remove(c.key)

# "682roar": 5 to 17 minutes after the player first sets foot in the room, a roar sounds and the view shakes (not in the pocket
# dimension, SCP-860's room, SCP-1123's room or SCP-1499)
func _ev_682roar(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	if st.s == 0.0:
		if c.in_room:
			st.s = 70.0 * randi_range(300, 1000)
		return
	var here: String = facility.room_name_at(player.global_position)
	if here in ["pocketdimension", "room860", "room1123", "dimension1499"]:
		return
	st.s -= c.fps
	if st.s < 17.0 * 70.0:
		if st.s + c.fps >= 17.0 * 70.0:
			Sfx.play_global(self, "SFX/SCP/682/Roar.ogg")
		if st.s > 17.0 * 70.0 - 3.0 * 70.0:
			player.camera_shake = maxf(player.camera_shake, 0.5)
		if st.s < 17.0 * 70.0 - 7.5 * 70.0 and st.s > 17.0 * 70.0 - 11.0 * 70.0:
			player.camera_shake = maxf(player.camera_shake, 2.0)
		if st.s < 70.0:
			_remove(c.key)

# "buttghost": a ghost laughs behind the toilets (SCP-789-J) when the player passes Objects[0]
func _ev_buttghost(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var spot: Vector3 = c.room.object_point(0)
	if spot == Vector3.INF or c.player.global_position.distance_to(spot) >= 1.8:
		return
	var nodes: Dictionary = _nodes.get(c.key, {})
	if st.s == 0.0:
		GameState.give_achievement("789")
		var voice := Sfx.play_at(c.room, "SFX/SCP/Joke/789J.ogg", 10.0)
		if voice != null:
			voice.global_position = spot
		nodes["voice"] = voice
		_nodes[c.key] = nodes
		st.s = 1.0
	else:
		var voice: Variant = nodes.get("voice")
		if voice == null or not is_instance_valid(voice) or not (voice as AudioStreamPlayer3D).playing:
			_remove(c.key)

# "room3tunnel": a dead guard lies at Objects[0]
func _ev_room3tunnel(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	var spot: Vector3 = c.room.object_point(0)
	if spot == Vector3.INF:
		_remove(c.key)
		return
	var at := Vector3(spot.x, rec.position.y + 0.2, spot.z)
	var centre := Vector3(rec.position.x, at.y, rec.position.z)
	_dead_guard(at, _yaw_toward(at, centre) + deg_to_rad(randf_range(-20.0, 20.0)), 288.0)
	_remove(c.key)

# "toiletguard": a guard who shot himself in the stall at Objects[1]. His last words loop while the player is 4 to 15 away; close
# by and making noise, they end, a splatter shows on the wall at Objects[2], and the event is over when he has spoken.
func _ev_toiletguard(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = _nodes.get(c.key, {})
	if st.s == 0.0:
		if c.dist < 8.0 and c.dist > 0.0:
			st.s = 1.0
		return
	if st.s == 1.0:
		var spot: Vector3 = c.room.object_point(1)
		if spot == Vector3.INF:
			_remove(c.key)
			return
		var at := Vector3(spot.x, rec.position.y + 0.2, spot.z)
		var centre := Vector3(rec.position.x, at.y, rec.position.z)
		nodes["guard"] = _dead_guard(at, _yaw_toward(at, centre) - deg_to_rad(20.0), 287.0)
		_nodes[c.key] = nodes
		st.s = 2.0
		return
	var guard := _valid(nodes.get("guard"))
	if guard == null:
		return
	if not nodes.has("last") and c.dist < 15.0 and c.dist >= 4.0:
		if not nodes.has("loop") or not is_instance_valid(nodes.get("loop")):
			nodes["loop"] = _loop_at(guard, "SFX/Character/Guard/SuicideGuard1.ogg", 15.0)
	elif c.dist < 4.0 and player.sound_volume > 1.0:
		if st.s2 == 0.0:
			var splat: Vector3 = c.room.object_point(2)
			if splat != Vector3.INF:
				var decal := GrowingDecal.make(facility.get_parent(), splat, "GFX/decal4.png", 0.3, 0.0, 1.0, false, Vector3(0.0, deg_to_rad(float(rec.angle) + 270.0), 0.0))
				decal.global_position = splat
			st.s2 = 1.0
		if not nodes.has("last"):
			var loop: Variant = nodes.get("loop")
			if loop != null and is_instance_valid(loop):
				(loop as AudioStreamPlayer3D).queue_free()
			nodes["last"] = Sfx.play_at(guard, "SFX/Character/Guard/SuicideGuard2.ogg", 15.0)
		var last: Variant = nodes.get("last")
		if last == null or not is_instance_valid(last) or not (last as AudioStreamPlayer3D).playing:
			_remove(c.key)

# "room4": every 5 s, if 049 is hunting but more than 16 from the player, who is within 16 of the room (and not in it), 049 is
# put on the ledge of the room (368, 528, 176), where he stands (state 4) and watches until the player walks away.
func _ev_room4(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	st.s -= c.fps
	if st.s > 0.0:
		return
	st.s = 70.0 * 5.0
	if c.in_room:
		return
	var player: CharacterBody3D = c.player
	if Vector2(player.global_position.x - rec.position.x, player.global_position.z - rec.position.z).length() >= 16.0:
		return
	var big := _valid(facility.scp049)
	if big != null and big.state == 2 and big.global_position.distance_to(player.global_position) > 16.0:
		big.global_position = to_world(rec, 368.0, 528.0, 176.0)
		big.velocity = Vector3.ZERO
		big.path_timer = 0.0
		big._clear_path()
		big.state = 4
		big.state2 = 0.0
		big.state3 = 0.0
		_remove(c.key)

# "room2pit": 173 is put on the ledge at Objects[6] when the player comes within 8 of the room and neither it nor the spot is in
# the camera's line of sight
func _ev_room2pit(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	var s := _statue()
	if s == null or s.idle != 0 or c.dist >= 8.0 or c.dist <= 0.0:
		return
	var spot: Vector3 = c.room.object_point(6)
	if spot == Vector3.INF:
		return
	var eye: Vector3 = c.player.camera.global_position
	if _visible_between(eye, s.global_position + Vector3(0.0, 0.5, 0.0)) or _visible_between(eye, spot + Vector3(0.0, 0.1, 0.0)):
		return
	_put_173(Vector3(spot.x, rec.position.y + 0.5, spot.z))
	_remove(c.key)

const PARTICLE_AMOUNT := 2        # options.ini "particle amount"

# "tunnel2smoke": when the player is within 3.5 of the middle, two pipes in the ceiling burst: a bang, a puff each, and they hiss
# gas from then on
func _ev_tunnel2smoke(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if not c.in_room or c.dist >= 3.5:
		return
	Sfx.play_at(c.room, "SFX/Room/TunnelBurst.ogg", 10.0)
	for i in 2:
		var at: Vector3 = c.room.object_point(i)
		if at == Vector3.INF:
			continue
		facility.particles.add_emitter(at, Vector3.DOWN, c.room, c.key, {"size": 0.05, "rand_angle": 10.0, "speed": 0.06, "size_change": 0.007})
		for k in int(ceil(3.3333 * (PARTICLE_AMOUNT + 1))) + 1:
			var p = facility.particles.create(Vector3(at.x, rec.position.y + 448.0 * RS, at.z), 0, 0.05, -0.2, 200.0)
			if p != null:
				p.speed = 0.06
				p.dir = Particles.random_heading()
				p.size_change = 0.008
	_remove(c.key)

const TESLA_COIL_REACH := 300.0 * RS        # a step this close to a coil winds the gate up
const TESLA_KILL_REACH := 250.0 * RS        # and what the discharge kills
const TESLA_CLERK_REACH := 400.0 * RS       # the clerk winds it up from here

# The gate's two sprites (FillRoom Objects[3] and [4]): the arc across it (EntityBlend 3, scrolled) and the small light on the
# coil. Made with the room, hidden until the gate does something.
func _tesla_sprites(key: String, room: Node3D) -> Dictionary:
	var nodes: Dictionary = _nodes.get(key, {})
	if nodes.has("arc") and is_instance_valid(nodes["arc"]):
		return nodes
	var arc := MeshInstance3D.new()
	var arc_quad := QuadMesh.new()
	arc_quad.size = Vector2(2.0, 2.0)
	arc.mesh = arc_quad
	arc.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/tesla.jpg")), Color.WHITE, true, false)
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.visible = false
	room.add_child(arc)
	arc.position = Vector3(0.0, 0.8, 0.0)
	var light := MeshInstance3D.new()
	var light_quad := QuadMesh.new()
	light_quad.size = Vector2(2.0, 2.0)
	light.mesh = light_quad
	light.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/light2.jpg")), Color.WHITE, true, true)
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.scale = Vector3.ONE * 0.03
	light.visible = false
	room.add_child(light)
	light.position = Vector3(-32.0 * RS, 568.0 * RS, 0.0)
	nodes["arc"] = arc
	nodes["light"] = light
	_nodes[key] = nodes
	return nodes

func _tesla_voice(key: String, room: Node3D, relative: String, range_m: float = 4.0, volume: float = 0.5) -> void:
	var nodes: Dictionary = _nodes.get(key, {})
	if nodes.has("voice") and is_instance_valid(nodes["voice"]):
		(nodes["voice"] as Node).queue_free()
	var voice := Sfx.play_at(room, relative, range_m, volume)
	if voice != null:
		voice.global_position = room.object_point(3)
	nodes["voice"] = voice
	_nodes[key] = nodes

func _tesla_wind_up(key: String, room: Node3D, nodes: Dictionary, st: Dictionary) -> void:
	if nodes.has("hum") and is_instance_valid(nodes["hum"]):
		(nodes["hum"] as Node).queue_free()
	nodes.erase("hum")
	_tesla_voice(key, room, "SFX/Room/Tesla/WindUp.ogg")
	(nodes["light"] as Node3D).visible = false
	st.s = 1.0

func _within_coils(point: Vector3, coils: Array, reach: float) -> bool:
	for coil in coils:
		if Vector2(point.x - coil.x, point.z - coil.z).length() < reach:
			return true
	return false

# "room2tesla": a gate of the facility. Stepping within 300 units' reach of a coil (or the clerk's or 106's) winds it up: 40 frames
# of charging and flicker, then until frame 70 the discharge kills whoever is within 250 of a coil (106 is banished instead); the
# gate rests until frame 150 and starts again. The first time the player comes to a gate a clerk runs at it from the far end and is
# killed by it (once in the whole facility). Nine-Tailed Fox units standing near a gate make it harmless for a while (they say so).
func _ev_room2tesla(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var room: Node3D = c.room
	var player: CharacterBody3D = c.player
	var fps: float = c.fps
	var coils: Array = [room.object_point(0), room.object_point(1), room.object_point(2)]
	if coils[2] == Vector3.INF or room.object_point(3) == Vector3.INF:
		return
	if not st.has("str"):
		st["str"] = ""
	var nodes := _tesla_sprites(c.key, room)
	var arc: MeshInstance3D = nodes["arc"]
	var light: MeshInstance3D = nodes["light"]
	var old_man := _valid(facility.scp106)
	var armed: bool = not (st.s2 > 70.0 * 3.5 and st.s2 < 70.0 * 90.0)
	var level: float = player.global_position.y + 0.45
	if armed and level > rec.position.y and level < 4.0:
		if st.s == 0.0:
			if c.dist < 8.0:
				arc.visible = false
				light.visible = (Time.get_ticks_msec() % 1500) < 800
				if not nodes.has("hum") or not is_instance_valid(nodes["hum"]):
					var hum := _loop_at(room, "SFX/Room/Tesla/Idle.ogg", 4.0, 0.5)
					if hum != null:
						hum.global_position = room.object_point(3)
					nodes["hum"] = hum
				if not player.dead and _within_coils(player.global_position, coils, TESLA_COIL_REACH):
					player.sound_volume = maxf(8.0, player.sound_volume)
					_tesla_wind_up(c.key, room, nodes, st)
				# the clerk comes for the first gate the player visits
				var other_has_clerk := false
				for other_key in plan.rooms_with("room2tesla"):
					if other_key != c.key and str(state_of(other_key).get("str", "")) != "":
						other_has_clerk = true
				if other_has_clerk:
					st["str"] = "done"
				elif st["str"] == "" and c.in_room:
					var from_five: Vector3 = room.object_point(5)
					var from_six: Vector3 = room.object_point(6)
					var start: Vector3 = from_six if from_five.distance_to(player.global_position) < from_six.distance_to(player.global_position) else from_five
					var clerk: Node3D = facility.spawn_human(HumanNpc.Kind.CLERK, Vector3(start.x, rec.position.y + 0.2, start.z))
					clerk.rotation.y = _yaw_toward(clerk.global_position, coils[2])
					clerk.state = 2
					nodes["clerk"] = clerk
					st["str"] = "step1"
					st.s = 0.0
					st.s2 = 0.0
					st.s3 = 0.0
			else:
				light.visible = false
			if old_man != null and old_man.state < -10.0 and st.s == 0.0 and not player.dead and _within_coils(old_man.global_position, coils, TESLA_COIL_REACH):
				_tesla_wind_up(c.key, room, nodes, st)
				old_man.state = 70.0 * 60.0 * randi_range(10, 13)
				GameState.give_achievement("tesla")
		else:
			st.s += fps
			if st.s <= 40.0:
				arc.visible = false
				light.visible = (Time.get_ticks_msec() % 100) < 50
			else:
				if st.s - fps <= 40.0:
					if c.dist < 2.0:
						Sfx.play_global(self, "SFX/Room/Tesla/Shock.ogg")
					else:
						var shock := Sfx.play_at(room, "SFX/Room/Tesla/Shock.ogg", 10.0)
						if shock != null:
							shock.global_position = coils[2]
				if st.s < 70.0:
					if not player.dead and _within_coils(player.global_position, coils, TESLA_KILL_REACH):
						GameState.light_flash = 0.4
						player.camera_shake = 1.0
						player.kill("Subject D-9341 killed by the Tesla gate at [REDACTED].")
					var clerk_now := _valid(nodes.get("clerk"))
					if st["str"] == "step1" and clerk_now != null:
						clerk_now.state = 3
					if old_man != null and old_man.state < -10.0 and _within_coils(old_man.global_position, coils, TESLA_KILL_REACH):
						GameState.light_flash = 0.3
						_tesla_burn(old_man.global_position)
						old_man.state = -20000.0
						old_man.global_position.y -= 50.0
					light.visible = false
					arc.visible = false
					if randi_range(1, 5) < 5:
						(arc.material_override as ShaderMaterial).set_shader_parameter("uv_offset", Vector2(0.0, randf()))
						arc.visible = true
				else:
					if st.s - fps < 70.0:
						_tesla_voice(c.key, room, "SFX/Room/Tesla/PowerUp.ogg")
					arc.visible = false
					if st.s > 150.0:
						st.s = 0.0
	else:
		light.visible = false
	_tesla_clerk(c.key, st, nodes, room, coils, fps)
	_tesla_squad(rec, st, c)

# 106 burns up in the gate: a cloud of smoke flies off, much faster than gravity alone would send it (p\gravity is set raw)
func _tesla_burn(at: Vector3) -> void:
	for i in 5 + 5 * (PARTICLE_AMOUNT - 1) + 1:
		var smoke = facility.particles.create(at, 0, 0.03, 0.0, 200.0)
		if smoke != null:
			smoke.gravity = -0.2
			smoke.size_change = 0.005
			smoke.speed = 0.001
			smoke.dir = Particles.random_heading()

# the clerk's part: he winds the gate up as he nears it, falls when it fires, and smokes where he lies
func _tesla_clerk(key: String, st: Dictionary, nodes: Dictionary, room: Node3D, coils: Array, fps: float) -> void:
	var clerk := _valid(nodes.get("clerk"))
	if clerk == null:
		return
	var step: String = st["str"]
	if step == "step1" and clerk.state != 3:
		if st.s == 0.0 and _within_coils(clerk.global_position, coils, TESLA_CLERK_REACH):
			_tesla_wind_up(key, room, nodes, st)
	elif step == "step1":
		clerk.curr_speed = 0.0
		clerk.animate(41.0, 60.0, 0.5, fps, false)
		if clerk.frame >= 59.99:
			clerk.is_dead = true
			st["str"] = "step2"
			clerk.set_frame(57.0)
	elif step == "step2":
		clerk.animate(57.0, 60.0, 0.5, fps, false)
		if clerk.frame >= 59.99:
			st["str"] = "0"
	elif step != "" and step != "done":
		if float(step) < 70.0 * 10.0:
			if randi_range(1, 10) == 1:
				var yaw := clerk.rotation.y
				var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
				var side := Vector3(cos(yaw), 0.0, -sin(yaw))
				var at: Vector3 = clerk.global_position + Vector3(0.0, 0.05, 0.0) + side * randf_range(-0.1, 0.1) + forward * (0.1 + randf_range(0.0, 0.5))
				var smoke = facility.particles.create(at, 0, 0.05, 0.0, 60.0)
				if smoke != null:
					smoke.speed = 0.002
					smoke.dir = Vector3.UP
					smoke.a_change = -0.02
			st["str"] = str(float(step) + fps)
		else:
			st["str"] = "done"

# Nine-Tailed Fox units near a gate: one says so and stands still for 10 s, and the gate is off for the next 87 s or so
func _tesla_squad(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var here: String = facility.room_name_at(c.player.global_position)
	if here == "pocketdimension" or here == "room860":
		return
	if st.s2 == 0.0:
		if st.s3 <= 0.0:
			var near := false
			for unit in facility.mtf.units:
				if is_instance_valid(unit) and absf(unit.global_position.x - rec.position.x) < 4.0 and absf(unit.global_position.z - rec.position.z) < 4.0:
					near = true
					if st.s2 == 0.0:
						unit.say("SFX/Character/MTF/Tesla0.ogg")
						unit.idle = 70.0 * 10.0
						st.s2 = 70.0 * 100.0
			if not near:
				st.s2 = 70.0 * 3.5
			st.s3 += 140.0
		else:
			st.s3 -= c.fps
	else:
		if st.s2 >= 70.0 * 92.0 and st.s2 - c.fps < 70.0 * 92.0:
			facility.mtf.play_announcement("SFX/Character/MTF/Tesla%d.ogg" % randi_range(1, 3))
		st.s2 = maxf(st.s2 - c.fps, 0.0)


# Animate2: the frame climbs by `speed` a frame inside start..end (a loop wraps, otherwise it stops at the end)
func _animate_frame(frame: float, start: float, finish: float, speed: float, fps: float, loop: bool = true) -> float:
	var next := frame + speed * fps
	if loop:
		if next > finish or next < start:
			return start + fposmod(next - start, maxf(finish - start, 0.001))
		return next
	return clampf(next, start, finish)

func _make_1048a(rec: Dictionary, room: Node3D) -> Node3D:
	var model := B3DModel.new()
	model.load_file(ContentPaths.existing_file("GFX/npcs/scp-1048a.b3d"))
	model.scale = Vector3.ONE * 0.05
	room.add_child(model)
	model.global_position = Vector3(rec.position.x, rec.position.y, rec.position.z)
	model.rotation = Vector3(deg_to_rad(90.0), deg_to_rad(randf_range(0.0, 360.0)), 0.0)      # RotateEntity(-90, yaw, 0): it lies upright
	model.set_frame(2.0)
	return model

# "1048a": a lump of ears lies in the middle of the room (every plain corridor has one). It is made while the player blinks within 16
# of the room, out of it. When they come within 2.5 it wakes (frames 2-647: a shriek at 400, the view smears and shakes around frame
# 600) and turns to them; if they are in the room when it is done, ears grow over them and they suffocate in 15 s. It goes 25 s after
# the player has left.
func _ev_1048a(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = _nodes.get(c.key, {})
	var model := _valid(nodes.get("model")) as Node3D
	if model == null:
		if st.s > 0.0 and st.s < 4.0:
			model = _make_1048a(rec, c.room)          # restored from a save while it was awake
			nodes["model"] = model
			_nodes[c.key] = nodes
		elif st.s == 0.0 and not c.in_room and player.blink_timer < -10.0:
			if Vector2(player.global_position.x - rec.position.x, player.global_position.z - rec.position.z).length() < 16.0:
				nodes["model"] = _make_1048a(rec, c.room)
				nodes["frame"] = 2.0
				_nodes[c.key] = nodes
				st.s = 1.0
		return
	st.s3 = 1.0
	var frame: float = float(nodes.get("frame", 2.0))
	match int(st.s):
		1:
			frame = _animate_frame(frame, 2.0, 395.0, 1.0, c.fps)
			if player.global_position.distance_to(model.global_position) < 2.5:
				st.s = 2.0
		2:
			var before := frame
			frame = _animate_frame(frame, 2.0, 647.0, 1.0, c.fps, false)
			if before <= 400.0 and frame > 400.0:
				Sfx.play_global(self, "SFX/SCP/1048A/Shriek.ogg")
			var volume := maxf(1.0 - absf(before - 600.0) / 100.0, 0.0)
			GameState.blur_timer = volume * 1000.0
			player.camera_shake = volume * 10.0
			var yaw := atan2(-(player.global_position.x - model.global_position.x), -(player.global_position.z - model.global_position.z))
			model.global_rotation = Vector3(deg_to_rad(90.0), yaw, 0.0)
			if before > 646.0:
				if c.in_room:
					st.s = 3.0
					Sfx.play_global(self, "SFX/SCP/1048A/Growth.ogg")
					_hud_message("Something is growing all around your body.", 3.0)
				else:
					st.s3 = 70.0 * 30.0
		3:
			st.s2 += c.fps
			GameState.blur_timer = st.s2 * 2.0
			if st.s2 > 250.0 and st.s2 - c.fps <= 250.0:
				_hud_message(["Ears are growing all over your body.", "Ear-like organs are growing all over your body.", "Ears are growing all over your body. They are crawling on your skin."][randi_range(0, 2)], 3.0)
			elif st.s2 > 600.0 and st.s2 - c.fps <= 600.0:
				_hud_message(["It is becoming difficult to breathe.", "You have excellent hearing now. Also, you are dying.", "The ears are growing inside your body.", "\"Can't... Breathe...\""][randi_range(0, 3)], 5.0)
			if st.s2 > 70.0 * 15.0:
				st.s = 4.0
				_remove(c.key)
				player.kill("A dead body covered in ears was found in [REDACTED]. Subject was presumably attacked by an instance of SCP-1048-A and suffocated to death by the ears. Body was sent for autopsy.")
				return
	nodes["frame"] = frame
	model.set_frame(frame)
	if not c.in_room and st.s3 > 0.0:
		st.s3 += c.fps
		if st.s3 > 70.0 * 25.0:
			model.queue_free()
			nodes.erase("model")
			_remove(c.key)

func _hud_message(text: String, seconds: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.message(text, seconds)
