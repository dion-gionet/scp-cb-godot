class_name RoomRegistry
extends RefCounted
# Every room of the map, built once at load like CreateMap/FillRoom do (the generated rooms, gate A, the church of dimension 1499,
# the pocket dimension, every door between rooms), and the lookups from a point to a room. Rooms are never freed; room_drawing.gd
# hides the ones outside the player's neighbourhood.

var facility: FacilityMap

func _init(owner_facility: FacilityMap) -> void:
	facility = owner_facility

# r\dist (MapSystem.bb UpdateRooms): the larger of the x and z distances.
static func room_dist(origin: Vector3, pos: Vector3) -> float:
	return maxf(absf(origin.x - pos.x), absf(origin.z - pos.z))

var built: Dictionary = {}          # room key -> room node
var by_grid: Dictionary = {}
var door_defs: Dictionary = {}
var doors: Dictionary = {}
var start_rect := Rect2()
var room_bounds: Dictionary = {}
var _waypoint_rooms: Array[Node3D] = []   # the room each entry of _waypoints belongs to (w\room)
var _waypoints: Array[Vector3] = []   # every non-door waypoint, in creation order (the Waypoints list with w\door = Null)
var tunnels: MtEvent = null           # the maintenance tunnels: the box above the facility is their room, not whatever lies under it
var building := false                 # build_all is running: the waypoint graph is linked at its end, not on the way
var build_all_ms := 0.0
var graph_link_ms := 0.0

const LINK_CHUNKS := 8
const PROGRESS_ROOMS_END := 62.0
const PROGRESS_GRAPH_END := 79.0

# Builds everything. `progress` is called with the percentage of Main.bb's loading bar and may be a coroutine.
func build_all(progress: Callable = Callable()) -> void:
	building = true
	var began := Time.get_ticks_usec()
	var order: Array[Dictionary] = []
	var start: Dictionary = facility.generator.start_room
	if not start.is_empty():
		order.append(start)
	for record in facility.generator.rooms:
		if record != start:
			order.append(record)
	_parse_meshes(order)
	var total := float(order.size() + 2)
	var done := 0
	for record in order:
		if record != start and inside_start(record):
			continue
		_build_room(record)
		if record == start:
			compute_start_rect()
		done += 1
		if done % 4 == 0:
			await report(progress, 45.0 + (PROGRESS_ROOMS_END - 45.0) * float(done) / total)
	if not facility.gatea_record.is_empty():
		_build_room(facility.gatea_record)
	await report(progress, 45.0 + (PROGRESS_ROOMS_END - 45.0) * float(done + 1) / total)
	if facility.dimension != null and not facility.dimension.record.is_empty():
		_build_room(facility.dimension.record)
		facility.dimension.prepare()
	facility.build_pocket()
	spawn_all_doors()
	_link_gate_a()
	_add_door_waypoints()
	await report(progress, PROGRESS_ROOMS_END)
	await _link_graph(progress)
	facility.drawing.hide_all()
	_rebuild_door_cells()
	building = false
	build_all_ms = (Time.get_ticks_usec() - began) / 1000.0

static func report(progress: Callable, percent: float) -> void:
	if progress.is_valid():
		await progress.call(percent)

func _parse_meshes(order: Array[Dictionary]) -> void:
	var paths := {}
	for record in order:
		paths[mesh_path(record)] = true
		if str(record.name) == "room2tunnel":
			for piece in MtEvent.piece_paths():
				paths[piece] = true
	if not facility.gatea_record.is_empty():
		paths[mesh_path(facility.gatea_record)] = true
	if facility.dimension != null and not facility.dimension.record.is_empty():
		paths[mesh_path(facility.dimension.record)] = true
	var queue: Array = []
	for path in paths:
		if not MeshLoader.has_cached_rmesh(path):
			queue.append(path)
	# Plain threads: WorkerThreadPool ran these one after another in a headless run.
	var lock := Mutex.new()
	var threads: Array[Thread] = []
	for i in clampi(OS.get_processor_count(), 1, 8):
		var thread := Thread.new()
		thread.start(_parse_queue.bind(queue, lock))
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()

func _parse_queue(queue: Array, lock: Mutex) -> void:
	while true:
		lock.lock()
		var path: Variant = queue.pop_back() if not queue.is_empty() else null
		lock.unlock()
		if path == null:
			return
		MeshLoader.parse_rmesh_cached(str(path))

# The new bodies must be in the physics space before the line tests between waypoints.
func _link_graph(progress: Callable) -> void:
	await facility.get_tree().physics_frame
	var began := Time.get_ticks_usec()
	var space := facility.get_world_3d().direct_space_state
	var excluded := facility._door_bodies()
	var per_chunk := ceili(float(facility.graph.pending_count()) / float(LINK_CHUNKS))
	for chunk in LINK_CHUNKS:
		facility.graph.process_pending(space, excluded, per_chunk)
		await report(progress, PROGRESS_ROOMS_END + (PROGRESS_GRAPH_END - PROGRESS_ROOMS_END) * float(chunk + 1) / float(LINK_CHUNKS))
	facility.graph.process_pending(space, excluded, 1 << 30)
	graph_link_ms = (Time.get_ticks_usec() - began) / 1000.0

func _record_named(room_name: String) -> Dictionary:
	for record in facility.generator.rooms:
		if str(record.name) == room_name:
			return record
	return {}

func get_room(record: Dictionary) -> Node3D:
	var node: Variant = built.get(str(record.get("key", "")))
	return node if node != null and is_instance_valid(node) else null

func _build_room(record: Dictionary) -> void:
	var key: String = record.key
	var room := Node3D.new()
	room.set_script(FacilityRoom)
	facility.add_child(room)
	room.build(record)
	built[key] = room
	if str(record.name) == "start":
		facility.start_node = room
	set_bounds(key, room.world_bounds())
	for p in room.waypoint_positions():
		_waypoints.append(p)
		_waypoint_rooms.append(room)
		facility.graph.add_point(p, key, key, false)

# UpdateEvents "gateaentrance": its lift (RoomDoors[0], cab Objects[0]) and gate A's lift door (RoomDoors[1], the pivot at gate A's
# (1848, 240, -64)) are one elevator; the ride is one way (arriving locks the far door and the event goes).
const ElevatorScript = preload("res://scripts/world/elevator.gd")

var gate_a_lift: Node = null

func _link_gate_a() -> void:
	if facility.gatea_record.is_empty() or facility.events.gatea.state >= 1.0:
		return
	var gatea := get_room(facility.gatea_record)
	var entrance := get_room(_record_named("gateaentrance"))
	if gatea == null or entrance == null:
		return
	var door_here: Node3D = entrance.door_slots.get(0)
	var door_there: Node3D = gatea.door_slots.get(1)
	if door_here == null or door_there == null or not entrance.fill_objects.has(0):
		return
	var cab_here := Node3D.new()
	entrance.add_child(cab_here)
	cab_here.position = entrance.fill_objects[0]
	var cab_there := Node3D.new()
	gatea.add_child(cab_there)
	cab_there.position = Vector3(1848.0, 240.0, 64.0) * MeshLoader.ROOM_SCALE
	var lift := Node.new()
	lift.set_script(ElevatorScript)
	entrance.add_child(lift)
	lift.setup(door_here, door_there, cab_here, cab_there)
	lift.slam_096 = true
	lift.one_way = true
	gate_a_lift = lift

# Starts gate A over (tests, a new game on the same facility): its event state is cleared, the lift is linked afresh and the
# doors of both rooms go back to what FillRoom made them.
func reset_gate_a() -> void:
	facility.events.gatea.reset()
	if gate_a_lift != null and is_instance_valid(gate_a_lift):
		var lift_node := gate_a_lift
		for cab in [lift_node.cab1, lift_node.cab2]:
			if is_instance_valid(cab):
				cab.queue_free()
		lift_node.queue_free()
	gate_a_lift = null
	var entrance := get_room(_record_named("gateaentrance"))
	if entrance != null:
		entrance.restore_fill_doors()
	var gatea := get_room(facility.gatea_record) if not facility.gatea_record.is_empty() else null
	if gatea != null:
		gatea.restore_fill_doors()
	_link_gate_a()

# The doors CreateMap puts between rooms (map_generator.gd _create_map_doors). Map doors need no keycard.
func plan_doors() -> void:
	door_defs.clear()
	for def in facility.generator.doors:
		door_defs[str(def.key)] = def

# InitWayPoints makes the door waypoints after every room's: the rooms' own doors in room order, then CreateMap's.
func _add_door_waypoints() -> void:
	for key in built:
		for p in built[key].door_waypoint_positions():
			facility.graph.add_point(p, key, key, true)
	for edge in door_defs:
		if doors.has(edge):
			facility.graph.add_point(door_defs[edge].pos + Vector3(0.0, 0.18, 0.0), "edge|" + str(edge), str(door_defs[edge].a), true)

const DoorScript = preload("res://scripts/world/facility_door.gd")

func spawn_all_doors() -> void:
	for edge in door_defs:
		var def: Dictionary = door_defs[edge]
		if built.has(str(def.a)) or built.has(str(def.b)):
			_spawn_door(edge)

func spawn_doors(room_key: String) -> void:
	for edge in door_defs:
		var def: Dictionary = door_defs[edge]
		if str(def.a) == room_key or str(def.b) == room_key:
			_spawn_door(edge)

func _spawn_door(edge: String) -> void:
	if doors.has(edge):
		return
	var def: Dictionary = door_defs[edge]
	var door := Node3D.new()
	door.set_script(DoorScript)
	facility.add_child(door)
	door.setup(def.pos, def.yaw, false, bool(def.open), def.heavy, 0)
	door.auto_close = bool(def.get("auto_close", false))
	door.room_name = str(by_grid.get(str(def.a), {}).get("name", ""))
	doors[edge] = door

# The [start] chamber runs ~16m past its own grid cell. Rooms generated inside that space
# would put walls through the chamber, so they are never built.
func compute_start_rect() -> void:
	var faces: PackedVector3Array = facility.start_node.collision_faces
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in faces:
		var world: Vector3 = facility.start_node.to_global(v)
		lo = Vector2(minf(lo.x, world.x), minf(lo.y, world.z))
		hi = Vector2(maxf(hi.x, world.x), maxf(hi.y, world.z))
	start_rect = Rect2(lo, hi - lo)
	facility.drawing.forget_neighbours()
	var skipped := 0
	for room in facility.generator.rooms:
		if inside_start(room):
			skipped += 1
	print("FACILITY start footprint=", start_rect, " rooms_inside=", skipped)

func inside_start(record: Dictionary) -> bool:
	if str(record.name) == "start" or start_rect.size == Vector2.ZERO:
		return false
	var cell := Rect2(record.position.x - 3.5, record.position.z - 3.5, 7.0, 7.0)
	return start_rect.intersects(cell)

func waypoints() -> Array[Vector3]:
	return _waypoints

func waypoint_rooms() -> Array[Node3D]:
	return _waypoint_rooms

# A player standing on a floor has feet at y = 0 +- a few thousandths, just outside a room whose bounds start at the floor; without this
# slack the room the player is in flips to a bigger neighbour that overlaps there.
const BOUNDS_SLACK := 0.1

# Template name of the room the point is in: the room whose mesh bounds contain it
# (smallest first, since some rooms are much larger than their grid cell), else the grid cell.
func room_name_at(pos: Vector3) -> String:
	if facility.events.room860.state == 1.0:
		return "room860"        # the forest hangs 30 m above SCP-860's room; PlayerRoom stays that room
	if facility.dimension != null and facility.dimension.contains(pos):
		return "dimension1499"
	if facility.pocket != null and facility.pocket.player_inside and facility.pocket.contains(pos):
		return "pocketdimension"
	return str(record_at(pos).get("name", ""))

# Room bounds by 8 m cell (x, z): the keys of the rooms whose bounds, grown by BOUNDS_SLACK, overlap the cell.
const INDEX_CELL := 8.0
var _cells: Dictionary = {}
var _cells_of: Dictionary = {}

# The room's bounds as they are for lookups; gate A widens its own when the tunnel is built.
func set_bounds(key: String, box: AABB) -> void:
	room_bounds[key] = box
	for cell in _cells_of.get(key, []):
		(_cells[cell] as Array).erase(key)
	var covered: Array[Vector2i] = []
	if box.size != Vector3.ZERO:
		var grown := box.grow(BOUNDS_SLACK)
		for cx in range(int(floor(grown.position.x / INDEX_CELL)), int(floor(grown.end.x / INDEX_CELL)) + 1):
			for cz in range(int(floor(grown.position.z / INDEX_CELL)), int(floor(grown.end.z / INDEX_CELL)) + 1):
				var cell := Vector2i(cx, cz)
				covered.append(cell)
				if not _cells.has(cell):
					_cells[cell] = []
				(_cells[cell] as Array).append(key)
	_cells_of[key] = covered

# The key of the room whose mesh bounds contain the point (smallest first), or "".
func _key_at(pos: Vector3) -> String:
	if tunnels != null and tunnels.contains(pos):
		return tunnels.room.room_key
	var candidates: Variant = _cells.get(Vector2i(int(floor(pos.x / INDEX_CELL)), int(floor(pos.z / INDEX_CELL))))
	if candidates == null:
		return ""
	var best := ""
	var best_volume := INF
	for key in candidates:
		var box: AABB = room_bounds[key]
		if box.grow(BOUNDS_SLACK).has_point(pos):
			var volume := box.size.x * box.size.y * box.size.z
			if volume < best_volume:
				best_volume = volume
				best = key
	return best

# The built room whose mesh bounds contain the point (smallest first), or null.
func room_at(pos: Vector3) -> Node3D:
	var key := _key_at(pos)
	return built[key] if key != "" else null

func record_of(node: Node3D) -> Dictionary:
	if not node is FacilityRoom:
		return {}
	var key: String = node.room_key
	return by_grid[key] if built.get(key) == node and by_grid.has(key) else {}

# The generated room record whose grid cell holds the point, or {}.
func record_at(pos: Vector3) -> Dictionary:
	# the room whose mesh bounds hold the point (the start chamber spans several cells)
	var key := _key_at(pos)
	if by_grid.has(key):
		return by_grid[key]
	var cell := "%d,%d" % [int(round(pos.x / 8.0)), int(round(-pos.z / 8.0))]
	if by_grid.has(cell):
		return by_grid[cell]
	return {}

# Room\Adjacent[0..3] by grid step: +x, -z (grid y - 1), -x, +z.
const ADJACENT_ORDER: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)]

# Rooms sharing an open edge with the record (a door was planned between them), in Adjacent order.
func adjacent_records(record: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if record.is_empty():
		return out
	var here := "%d,%d" % [record.grid.x, record.grid.y]
	var linked := {}
	for edge in door_defs:
		var def: Dictionary = door_defs[edge]
		var other := ""
		if str(def.a) == here:
			other = str(def.b)
		elif str(def.b) == here:
			other = str(def.a)
		if not other.is_empty() and by_grid.has(other):
			linked[other] = true
	for step in ADJACENT_ORDER:
		var key := "%d,%d" % [record.grid.x + step.x, record.grid.y + step.y]
		if linked.erase(key):
			out.append(by_grid[key])
	for key in linked:
		out.append(by_grid[key])
	return out

# Doors never move, so NPCs, the hand icon and 173 ask for the ones near a point instead of
# walking the whole "door" group every frame. Rebuilt lazily after rooms or edge doors change.
const DOOR_CELL := 4.0
var _door_cells: Dictionary = {}
var door_version := 0       # changes whenever a door is built
var _door_cells_version := -1

func mark_doors_dirty() -> void:
	door_version += 1

func doors_near(pos: Vector3, radius: float) -> Array[Node3D]:
	if _door_cells_version != door_version:
		_rebuild_door_cells()
	var out: Array[Node3D] = []
	var span := int(ceil(radius / DOOR_CELL))
	var cx := int(floor(pos.x / DOOR_CELL))
	var cz := int(floor(pos.z / DOOR_CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell: Variant = _door_cells.get(Vector2i(cx + dx, cz + dz))
			if cell == null:
				continue
			for door in cell:
				if is_instance_valid(door) and not door.is_queued_for_deletion():
					out.append(door)
	return out

func _rebuild_door_cells() -> void:
	_door_cells_version = door_version
	_door_cells.clear()
	for node in facility.get_tree().get_nodes_in_group("door"):
		var door := node as Node3D
		if door == null or door.is_queued_for_deletion():
			continue
		var cell := Vector2i(int(floor(door.global_position.x / DOOR_CELL)), int(floor(door.global_position.z / DOOR_CELL)))
		if not _door_cells.has(cell):
			_door_cells[cell] = []
		(_door_cells[cell] as Array).append(door)

func mesh_path(record: Dictionary) -> String:
	if not record.has("mesh_path"):
		record["mesh_path"] = ContentPaths.existing_file(str(record.mesh))
	return record["mesh_path"]

func save_all_rooms() -> void:
	for key in built:
		var room: Node = built[key]
		if is_instance_valid(room) and room.has_method("save_state"):
			room.save_state()
