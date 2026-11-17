class_name RoomDrawing
extends RefCounted
# Which rooms are drawn (MapSystem.bb UpdateRooms). Blitz3D draws everything in view, so the original hides what cannot be
# seen: every room beyond the player's room, its neighbours and their neighbours is hidden (HideEntity r\obj). Of the rest only
# the player's room has its mesh drawn (EntityAlpha(GetChild(r\obj, 2))): a neighbour's only while the door between is open and
# its frame in view, a neighbour's neighbour's never. Room\Adjacent[] is geometric (the room 8 units away on the grid), not
# "joined by a door". HideEntity also takes a room out of collisions, so a hidden room is not solid either: every room is built
# at load and the ones outside the neighbourhood stay hidden and passable until the player comes near.

var facility: FacilityMap

func _init(owner_facility: FacilityMap) -> void:
	facility = owner_facility

const FRAME_RADIUS := 1.5            # EntityInView(frameobj): the frame's bounding sphere
var enabled := true             # the console's `culling`; tests that look at far rooms switch it off
var drawn_from: Dictionary = {}     # PlayerRoom: it stays when the player is in no room (the forest, the pocket dimension)
var ring_rooms: Array = []          # the player's room, its neighbours and theirs, whether or not the rule is on
var player_room: Node3D = null      # PlayerRoom
var _applied_key := ""              # the PlayerRoom whose neighbourhood the rooms' shown state was last set for, or ALL_DRAWN
var _ring_key := ""                 # the PlayerRoom that ring_rooms and _shown were last built for
var _ring_built := 0
var _shown: Dictionary = {}
var _neighbours: Dictionary = {}    # record key -> its four neighbour records (Room\Adjacent[])

const TUNNELS_KEY := "mt"
const ALL_DRAWN := "*"              # every room has been put back (the rule is off or noclip is on)

# Noclip flies through walls and floors, so what the rule hides would be seen: it stands aside while noclip is on.
func active() -> bool:
	return enabled and not GameState.noclip

func show_all_rooms() -> void:
	_applied_key = ALL_DRAWN
	for key in facility.rooms.built:
		var room: FacilityRoom = facility.rooms.built[key]
		if is_instance_valid(room):
			_show(room, true)
			if room.visual != null:
				room.visual.visible = true

# Every room hidden and passable, as after CreateMap before the first UpdateRooms.
func hide_all() -> void:
	_applied_key = ""
	for key in facility.rooms.built:
		var room: FacilityRoom = facility.rooms.built[key]
		if is_instance_valid(room):
			_show(room, false)
	drawn_from = {}

func _show(room: FacilityRoom, shown: bool) -> void:
	room.visible = shown
	room.set_collidable(shown)

func neighbour_of(record: Dictionary, index: int) -> Dictionary:
	var cached: Array = _neighbours.get(record.key, [])
	if cached.is_empty():
		for step in RoomRegistry.ADJACENT_ORDER:
			var found: Dictionary = facility.rooms.by_grid.get("%d,%d" % [record.grid.x + step.x, record.grid.y + step.y], {})
			if not found.is_empty() and facility.rooms.inside_start(found):    # the start chamber's footprint holds no rooms of its own
				found = {}
			cached.append(found)
		_neighbours[record.key] = cached
	return cached[index]

func forget_neighbours() -> void:
	_neighbours.clear()
	_ring_key = ""

# Room\AdjDoor[index]: the door on that side, if the room's shape leaves it open.
func door_toward(record: Dictionary, index: int) -> Node3D:
	var gx: int = record.grid.x
	var gy: int = record.grid.y
	var edge := ""
	match index:
		0:
			edge = "%d,%d|e" % [gx, gy]
		1:
			edge = "%d,%d|n" % [gx, gy - 1]
		2:
			edge = "%d,%d|e" % [gx - 1, gy]
		_:
			edge = "%d,%d|n" % [gx, gy]
	var door: Node3D = facility.rooms.doors.get(edge)
	return door if door != null and is_instance_valid(door) else null

# A room outside the grid (the 1499 church, the intro chamber) is PlayerRoom with no neighbours: every other room is hidden (UpdateEvents
# does it for dimension1499) and it is never hidden from the player standing in it.
func _show_only(inside: Node3D) -> void:
	if _applied_key != str(inside.name):
		_applied_key = str(inside.name)
		for key in facility.rooms.built:
			var node: FacilityRoom = facility.rooms.built[key]
			if is_instance_valid(node):
				_show(node, node == inside)
	_show(inside as FacilityRoom, true)
	if inside.visual != null:
		inside.visual.visible = true

# UpdateEvents room2tunnel with the player above y 4: every room but that one is hidden, and its own mesh is clear (EntityAlpha 0).
func _show_only_tunnels(room: FacilityRoom) -> void:
	drawn_from = facility.rooms.record_of(room)
	ring_rooms = [room]
	player_room = room
	_ring_key = ""
	if _applied_key != TUNNELS_KEY:
		_applied_key = TUNNELS_KEY
		for key in facility.rooms.built:
			var node: FacilityRoom = facility.rooms.built[key]
			if is_instance_valid(node):
				_show(node, node == room)
	room.visual.visible = false

func set_mesh_drawn(key: String, drawn: bool) -> void:
	var node: Node3D = facility.rooms.built.get(key)
	if node != null and is_instance_valid(node) and node.visual != null:
		node.visual.visible = drawn

func frame_in_view(door: Node3D, camera: Camera3D) -> bool:
	var centre := door.global_position + Vector3(0.0, 1.0, 0.0)
	for plane in camera.get_frustum():
		if plane.distance_to(centre) > FRAME_RADIUS:
			return false
	return true

# Teleports set PlayerRoom outright instead of walking from the old one.
func after_teleport() -> void:
	update(true)

# PlayerRoom (MapSystem.bb 5575-5603) stays while the player is within 4 of its origin on x and z, and also when they are 1.5 or more above
# or below it, so a pit under a room's neighbour does not make that neighbour the player's room.
func _keeps_room(previous: Dictionary, found: Dictionary, at: Vector3) -> bool:
	if previous.is_empty() or previous.key == found.key:
		return false
	if absf(at.y - previous.position.y) >= 1.5:
		return true
	return absf(at.x - previous.position.x) < 4.0 and absf(at.z - previous.position.z) < 4.0

func update(teleported := false) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or player.camera == null:
		return
	var on := active()
	if not on and _applied_key != ALL_DRAWN:
		show_all_rooms()    # rooms the rule had hidden come back, once; rooms built later are drawn from the start
	var tunnels := facility.rooms.tunnels
	if on and tunnels != null and tunnels.hides_rooms(player.global_position):
		_show_only_tunnels(tunnels.room)
		return
	var dimension := facility.dimension
	var inside: Node3D = dimension.room if dimension != null and dimension.inside and dimension.room != null else facility.room_at(player.global_position)
	var here: Dictionary = facility.rooms.record_of(inside)
	if inside == null:
		here = facility.record_at(player.global_position)      # the grid cell, where the room's mesh does not reach (a corridor room's narrow bounds)
	elif here.is_empty():
		ring_rooms = [inside]
		player_room = inside
		_ring_key = ""
		if on:
			_show_only(inside)
		return
	if here.is_empty() or (not teleported and _keeps_room(drawn_from, here, player.global_position)):
		here = drawn_from
	if here.is_empty():
		return
	drawn_from = here
	if _ring_key != here.key or _ring_built != facility.rooms.built.size():
		_rebuild_ring(here)
	if not on:
		return
	if _applied_key != here.key:
		_applied_key = here.key
		for key in facility.rooms.built:
			var node: FacilityRoom = facility.rooms.built[key]
			if is_instance_valid(node):
				_show(node, _shown.has(key))
	set_mesh_drawn(here.key, true)
	for i in 4:
		var first := neighbour_of(here, i)
		if first.is_empty():
			continue
		var door := door_toward(here, i)
		if door != null:
			set_mesh_drawn(first.key, door.openstate > 0.0 and frame_in_view(door, player.camera))
		for j in 4:
			var second := neighbour_of(first, j)
			if not second.is_empty() and second.key != here.key:
				set_mesh_drawn(second.key, false)
	if neighbours_hidden_by != null and is_instance_valid(neighbours_hidden_by) and facility.rooms.record_of(neighbours_hidden_by).get("key", "") == here.key:
		hide_neighbour_meshes(neighbours_hidden_by)

func _rebuild_ring(here: Dictionary) -> void:
	_ring_key = here.key
	_ring_built = facility.rooms.built.size()
	_shown = {here.key: true}
	if not bool(here.get("off_grid", false)):    # gate A's and the church's events hide every other room
		for i in 4:
			var first := neighbour_of(here, i)
			if first.is_empty():
				continue
			_shown[first.key] = true
			for j in 4:
				var second := neighbour_of(first, j)
				if not second.is_empty():
					_shown[second.key] = true
	ring_rooms.clear()
	player_room = facility.rooms.built.get(here.key)
	for key in _shown:
		var node: Node3D = facility.rooms.built.get(key)
		if node != null and is_instance_valid(node):
			ring_rooms.append(node)

# UpdateEvents room2sl, while the player is on another level than the hall: the neighbours' meshes are not drawn at all.
var neighbours_hidden_by: Node3D = null

func hide_neighbour_meshes(room: Node3D) -> void:
	var here: Dictionary = facility.rooms.record_of(room)
	if here.is_empty():
		return
	for i in 4:
		var first := neighbour_of(here, i)
		if not first.is_empty():
			set_mesh_drawn(first.key, false)
