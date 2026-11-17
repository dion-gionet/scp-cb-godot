extends RefCounted
# The waypoint graph NPCs path along (MapSystem.bb CreateWaypoint / InitWayPoints / FindPath).
# Points are the rmesh waypoint markers of every room plus one 0.18 above every door
# frame, added after every room's. Each point, in the order they were added, links to the later ones under 7 units
# away, in the same room (or one is a door), with a clear line between them (doors do not count), while it has a free
# link slot (5 each).
# Links are made a few at a time on physics frames, because the line test needs the room's collision to exist.

const LINK_DISTANCE := 7.0
const MAX_LINKS := 5
const CELL := 8.0

var astar := AStar3D.new()
var _next_id := 1
var _owner_of: Dictionary = {}     # id -> owner key (a room key or "edge|...")
var _room_of: Dictionary = {}      # id -> room key
var _is_door: Dictionary = {}      # id -> bool
var _by_owner: Dictionary = {}     # owner key -> Array[int]
var _cells: Dictionary = {}        # Vector2i -> Array[int]
var _incoming: Dictionary = {}     # id -> the ids that have a link to it
var _slots: Dictionary = {}        # id -> [[to, dist], ...] in Connected[0..4] order (AStar3D keeps the positions and the plain neighbour lists)
var _pending: Array[int] = []

func point_count() -> int:
	return _owner_of.size()

func pending_count() -> int:
	return _pending.size()

func add_point(pos: Vector3, owner_key: String, room_key: String, is_door: bool, queue_links := true) -> int:
	var id := _next_id
	_next_id += 1
	astar.add_point(id, pos)
	_owner_of[id] = owner_key
	_room_of[id] = room_key
	_is_door[id] = is_door
	_slots[id] = []
	if not _by_owner.has(owner_key):
		_by_owner[owner_key] = []
	(_by_owner[owner_key] as Array).append(id)
	var cell_key := _cell_of(pos)
	if not _cells.has(cell_key):
		_cells[cell_key] = []
	(_cells[cell_key] as Array).append(id)
	if queue_links:
		_pending.append(id)
	return id

func remove_owner(owner_key: String) -> void:
	if not _by_owner.has(owner_key):
		return
	for id in _by_owner[owner_key]:
		if not astar.has_point(id):
			continue
		var pos := astar.get_point_position(id)
		for other in _incoming.get(id, []):
			if _slots.has(other):
				_slots[other] = (_slots[other] as Array).filter(func(slot: Array) -> bool: return int(slot[0]) != id)
		_incoming.erase(id)
		var cell_key := _cell_of(pos)
		if _cells.has(cell_key):
			(_cells[cell_key] as Array).erase(id)
		astar.remove_point(id)
		_owner_of.erase(id)
		_room_of.erase(id)
		_is_door.erase(id)
		_slots.erase(id)
		_pending.erase(id)
	_by_owner.erase(owner_key)

# Links up to `budget` queued points. `exclude` are door bodies (the original hides doors
# while the graph is built, so they never block a link).
func process_pending(space: PhysicsDirectSpaceState3D, exclude: Array[RID], budget: int = 12) -> void:
	var done := 0
	while done < budget and not _pending.is_empty():
		var id: int = _pending.pop_front()
		done += 1
		if not astar.has_point(id):
			continue
		_link_point(id, space, exclude)

func _link_point(id: int, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	var pos := astar.get_point_position(id)
	var later: Array = []
	for other in _gather(pos, 1):
		if other > id and astar.has_point(other):
			later.append(other)
	later.sort()
	for other in later:
		var other_pos := astar.get_point_position(other)
		if pos.distance_to(other_pos) >= LINK_DISTANCE:
			continue
		if _room_of[id] != _room_of[other] and not _is_door[id] and not _is_door[other]:
			continue
		if not _visible(space, pos, other_pos, exclude):
			continue
		_connect(id, other)
		_connect(other, id)

# A link made by hand, for points that are not linked by distance (the maintenance tunnels' grid).
func link(from: int, to: int) -> void:
	_connect(from, to)

# Each end keeps its own five slots (Connected[0..4]), so a link can exist in one direction only.
func _connect(from: int, to: int) -> void:
	if (_slots[from] as Array).size() >= MAX_LINKS:
		return
	astar.connect_points(from, to, false)
	(_slots[from] as Array).append([to, astar.get_point_position(from).distance_to(astar.get_point_position(to))])
	if not _incoming.has(to):
		_incoming[to] = []
	(_incoming[to] as Array).append(from)

func _visible(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()

# The ids in the cells within `reach` cells of `pos`'s, in no particular order.
func _gather(pos: Vector3, reach: int) -> Array:
	var found: Array = []
	var centre := _cell_of(pos)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			found.append_array(_cells.get(Vector2i(centre.x + dx, centre.y + dz), []))
	return found

# The id nearest `pos` within `radius_sq` (3D, squared), the lower id on a tie, or -1: the first of the original's list walk.
func near(pos: Vector3, radius_sq: float) -> int:
	var best_id := -1
	var best := radius_sq
	for id in _gather(pos, int(ceil(sqrt(radius_sq) / CELL))):
		var d2 := pos.distance_squared_to(astar.get_point_position(id))
		if d2 < best or (d2 == best and best_id >= 0 and id < best_id):
			best = d2
			best_id = id
	return best_id

# FindPath: status 0 = already there, 1 = route found, 2 = unreachable.
# Returns {"status": int, "points": Array[Vector3]} (start waypoint ... end waypoint).
# `mtf`: the MTF's search, which adds 0.5 to every step onto a waypoint that is not a door's.
func find_path(space: PhysicsDirectSpaceState3D, exclude: Array[RID], from: Vector3, to: Vector3, mtf := false) -> Dictionary:
	var start_id := -1
	var best := 350.0
	var probe := from + Vector3(0.0, 0.15, 0.0)
	for id in _gather(probe, int(ceil(sqrt(350.0) / CELL))):
		var p := astar.get_point_position(id)
		var d2 := probe.distance_squared_to(p)
		if d2 < best or (d2 == best and start_id >= 0 and id < start_id):
			# prefer waypoints that are visible
			if not _visible(space, p, probe, exclude):
				d2 *= 3.0
			if d2 < best or (d2 == best and start_id >= 0 and id < start_id):
				best = d2
				start_id = id
	if start_id < 0:
		return {"status": 2, "points": []}
	var end_id := near(to, 400.0)
	if end_id < 0:
		return {"status": 2, "points": []}
	if end_id == start_id:
		if to.distance_squared_to(astar.get_point_position(end_id)) < 0.4:
			return {"status": 0, "points": []}
		return {"status": 1, "points": [astar.get_point_position(end_id)]}
	var route := search(start_id, end_id, mtf)
	if route.is_empty():
		return {"status": 2, "points": []}
	var points: Array[Vector3] = []
	for id in route:
		points.append(astar.get_point_position(id))
	return {"status": 1, "points": points}

# The open-list search of FindPath (MapSystem.bb 6066-6150), quirks kept because they choose the route:
# - the open point with the lowest Fcost is expanded, the first in creation order on a tie, and only below 10000;
# - a newly opened point gets Fcost = its parent's Gcost + its parent's Hcost (not its own), Hcost being the x/z
#   Manhattan distance to the end; only a re-scored open point gets its own Gcost + Hcost;
# - the search stops as soon as the end point is opened, not when it is expanded.
# Returns the ids from start to end, or [] when there is no route.
func search(start_id: int, end_id: int, mtf := false) -> Array[int]:
	var state := {start_id: 1}
	var g := {start_id: 0.0}
	var h := {start_id: 0.0}
	var f := {start_id: 0.0}
	var parent := {}
	var end_pos := astar.get_point_position(end_id)
	var heap: Array = [[0.0, start_id]]
	while true:
		var smallest := -1
		while not heap.is_empty():
			var top: Array = _heap_pop(heap)
			var id: int = top[1]
			if int(state.get(id, 0)) == 1 and float(top[0]) == float(f[id]):
				smallest = id
				break
		if smallest < 0 or float(f[smallest]) >= 10000.0:
			break
		state[smallest] = 2
		for slot in _slots[smallest]:
			var next: int = slot[0]
			var next_state := int(state.get(next, 0))
			if next_state >= 2:
				continue
			var gtemp: float = float(g[smallest]) + float(slot[1])
			if mtf and not bool(_is_door.get(next, false)):
				gtemp += 0.5
			if next_state == 1:
				if gtemp < float(g[next]):
					g[next] = gtemp
					f[next] = gtemp + float(h[next])
					parent[next] = smallest
					_heap_push(heap, [f[next], next])
			else:
				var p := astar.get_point_position(next)
				h[next] = absf(p.x - end_pos.x) + absf(p.z - end_pos.z)
				g[next] = gtemp
				f[next] = float(g[smallest]) + float(h[smallest])
				parent[next] = smallest
				state[next] = 1
				_heap_push(heap, [f[next], next])
		if int(state.get(end_id, 0)) > 0:
			var route: Array[int] = []
			var at := end_id
			while at != start_id:
				route.push_front(at)
				at = parent[at]
			route.push_front(start_id)
			return route
	return []

# A binary min-heap of [fcost, id], ordered by fcost then id (the creation order the original's list walk ties on).
static func _less(a: Array, b: Array) -> bool:
	return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1]))

static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var up := (i - 1) >> 1
		if not _less(heap[i], heap[up]):
			break
		var t = heap[i]
		heap[i] = heap[up]
		heap[up] = t
		i = up

static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < heap.size() and _less(heap[l], heap[m]):
			m = l
		if r < heap.size() and _less(heap[r], heap[m]):
			m = r
		if m == i:
			break
		var t = heap[i]
		heap[i] = heap[m]
		heap[m] = t
		i = m
	return top


func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL)), int(floor(pos.z / CELL)))

# For the NPCs that walk the waypoints directly (SCP-066, SCP-513-1): the points in the order they were added, where each is, which
# room (key) it belongs to, whether it is a door's, and its neighbours.
func point_ids() -> PackedInt64Array:
	return astar.get_point_ids()

func position_of(id: int) -> Vector3:
	return astar.get_point_position(id)

func room_key_of(id: int) -> String:
	return str(_room_of.get(id, ""))

func is_door_point(id: int) -> bool:
	return bool(_is_door.get(id, false))

func neighbours_of(id: int) -> PackedInt64Array:
	return astar.get_point_connections(id)
