extends Node3D
class_name MtEvent
# room2tunnel (UpdateEvents.bb 3135-3919): the maintenance tunnels. The grid (mt_grid.gd) is made when the player is in the room and its
# pieces hang 8 units above the facility, at the room's x and z. While the player is up there (y 8 to 12, within 6 of the grid's box)
# the tunnels are PlayerRoom; with the player above y 4 every other room is hidden, the tunnels shown and the room's own mesh clear.
# Two lifts join the room (its doors 0 and 2) to the tunnels' two end cells.

const RS := 8.0 / 2048.0
const MESH_FILES := ["mt1", "mt2", "mt2c", "mt3", "mt4", "mt_elevator", "mt_generator"]
const FLOOR_Y := 8.0
const BOX_MARGIN := 6.0
const LEVEL_Y := 4.0
const LAMP_RANGE := 500.0 * RS
const ELEVATOR_LAMP_RANGE := 600.0 * RS
const ENTITY_LIGHT_GROUP := &"entity_lights"
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]
const DoorScript = preload("res://scripts/world/facility_door.gd")
const ElevatorScript = preload("res://scripts/world/elevator.gd")

var room: FacilityRoom
var facility: FacilityMap
var grid: MtGrid
var cells_root: Node3D
var ends: Array[Vector3] = [Vector3.INF, Vector3.INF]      # Objects[0] and Objects[1]: the first and the last elevator cell
var lamps: Array[Light3D] = []
static var _fixture_quad: QuadMesh
static var _fixture_material: Material
var _bodies: Array = []
var _cells: Array[Node3D] = []
var _shown := true
var _origin := Vector3.ZERO
var tunnel_doors: Array[Node3D] = [null, null]        # RoomDoors[1] (the last cell's) and [3] (the first's)
var tunnel_cabs: Array[Node3D] = [null, null]         # Objects[3] and [5]
var room_cabs: Array[Node3D] = [null, null]           # Objects[2] and [4]
var lifts: Array[Node] = []
var sleepers: Array[Node] = []                        # NPC[0] and NPC[1]: the two 966s made on the first visit
var playing_music := false                            # ShouldPlay = 7 ("Room3Storage") while the player is up in the tunnels
var _wp_ids: Dictionary = {}
var _wp_positions: Array[Vector3] = []
var _items: Array[Node3D] = []

func build(room_node: FacilityRoom) -> void:
	room = room_node
	facility = room_node.get_parent() as FacilityMap
	facility.rooms.tunnels = self
	# the pieces are built with the room (`build_all` parses them); the grid itself is still made on the first visit, as in the original
	_pieces()

static func piece_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in MESH_FILES:
		paths.append(ContentPaths.existing_file("GFX/map/%s.rmesh" % file))
	return paths

func _pieces() -> Array[Dictionary]:
	var loaded: Array[Dictionary] = []
	for path in piece_paths():
		loaded.append(MeshLoader.load_rmesh_cached(path))
	return loaded

func _exit_tree() -> void:
	if facility != null and facility.rooms != null and facility.rooms.tunnels == self:
		facility.rooms.tunnels = null
	_teardown()

func _teardown() -> void:
	_forget_waypoints()
	for lift in lifts:
		if is_instance_valid(lift):
			if is_instance_valid(room):
				room.release_lift(lift)
			lift.queue_free()
	for item in _items:
		if is_instance_valid(item) and item.is_in_group("pickup"):
			item.queue_free()
	_items.clear()
	for node: Node in [tunnel_doors[0], tunnel_doors[1], room_cabs[0], room_cabs[1], cells_root]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	lifts.clear()
	lamps.clear()
	sleepers.clear()
	_cells.clear()
	_bodies.clear()
	tunnel_doors = [null, null]
	tunnel_cabs = [null, null]
	room_cabs = [null, null]
	cells_root = null
	grid = null
	_shown = true

func _forget_waypoints() -> void:
	if facility == null or facility.rooms == null:
		return
	facility.graph.remove_owner("mt")
	for at in _wp_positions:
		var index := facility.rooms.waypoints().find(at)
		if index >= 0:
			facility.rooms.waypoints().remove_at(index)
			facility.rooms.waypoint_rooms().remove_at(index)
	_wp_positions.clear()
	_wp_ids.clear()

# The box the override of PlayerRoom covers: y 8 to 12 and within 6 of the grid's 38 x 38.
func contains(pos: Vector3) -> bool:
	if room == null:
		return false
	var at := room.global_position
	return pos.y >= FLOOR_Y and pos.y <= 12.0 and pos.x >= at.x - BOX_MARGIN and pos.x <= at.x + 2.0 * MtGrid.SIZE + BOX_MARGIN \
		and pos.z <= at.z + BOX_MARGIN and pos.z >= at.z - 2.0 * MtGrid.SIZE - BOX_MARGIN

# With the player above y 4 in the room (or the box over it) the other rooms are hidden and the room's own mesh is clear.
func hides_rooms(pos: Vector3) -> bool:
	if grid == null or pos.y <= LEVEL_Y:
		return false
	if contains(pos):
		return true
	var footprint := room.world_bounds()
	return facility.drawing.player_room == room and pos.x >= footprint.position.x and pos.x <= footprint.end.x and pos.z >= footprint.position.z and pos.z <= footprint.end.z

# World position of a point given in the original's offsets from the room (x right, z the other way round).
func _at(dx: float, y: float, dz: float) -> Vector3:
	return Vector3(_origin.x + dx, y, _origin.z - dz)

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or room == null or facility == null or not facility.active:
		return
	var here: bool = facility.drawing.player_room == room
	if grid != null and not facility.events.mt.generated:
		_teardown()
	if here and grid == null:
		_generate()
	if grid != null:
		var up := here and player.global_position.y > LEVEL_Y
		_show_cells(up)
		for lift in lifts:
			lift.enabled = here
		_update_music(up)
		if up and facility.events.mt.state == 0:
			_first_entry(player)

func _update_music(up: bool) -> void:
	if up:
		playing_music = true
		GameState.music_override = "Room3Storage"
	elif playing_music:
		playing_music = false
		if GameState.music_override == "Room3Storage":
			GameState.music_override = ""

# The first time the player is up there: 106 comes up under the nearer end, leaving a stain, and a 966 is put at a random waypoint
# in the first fifth of the cells and another in the rest (the rolls are Rand(2) = 1 on each cell in turn, from CELLS * i / 5).
func _first_entry(player: CharacterBody3D) -> void:
	facility.events.mt.state = 2
	var nearer := 0 if player.global_position.distance_to(ends[0]) < player.global_position.distance_to(ends[1]) else 1
	var end := ends[nearer]
	var old_man: Node3D = facility.scp106 if is_instance_valid(facility.scp106) else null
	if not facility.contained_106:
		GrowingDecal.make(room.get_parent(), Vector3(end.x, end.y + 0.05, end.z), "GFX/decal1.png", 0.05, 0.001, 0.8, true, Vector3(-PI * 0.5, randf() * TAU, 0.0))
		if old_man != null:
			old_man.global_position = Vector3(end.x, player.global_position.y - 3.0, end.z)
			old_man.set_frame(110.0)
			old_man.state = -0.1
			old_man.prev_y = player.global_position.y
	sleepers.clear()
	for i in 2:
		var spot := -1
		var index := roundi(i * (MtGrid.CELLS / 5.0))
		while index <= MtGrid.CELLS - 1:
			var rolled := randi_range(1, 2) == 1
			if rolled and _wp_ids.has(index):
				spot = index
				break
			index += 1
		if spot >= 0:
			sleepers.append(facility.spawn_scp966(NpcGravity.feet(_at((spot % MtGrid.SIZE) * 2.0, 8.2, (spot / MtGrid.SIZE) * 2.0))))

func _generate() -> void:
	_origin = Vector3(room.global_position.x, 0.0, room.global_position.z)
	grid = MtGrid.generate(int(facility.generator.seed_value))
	var loaded := _pieces()
	cells_root = Node3D.new()
	cells_root.name = "MaintenanceTunnels"
	room.get_parent().add_child(cells_root)
	var make_items := not facility.events.mt.generated
	_make_room_cabs()
	for y in MtGrid.SIZE:
		for x in MtGrid.SIZE:
			var kind := grid.cells[x + y * MtGrid.SIZE]
			if kind > 0:
				_place_cell(loaded, x, y, kind, make_items)
				_add_waypoint(x, y)
	_link_waypoints()
	_make_lifts()
	facility.events.mt.generated = true
	ends[0] = _at(grid.first.x * 2.0, FLOOR_Y, grid.first.y * 2.0)
	ends[1] = _at(grid.last.x * 2.0, FLOOR_Y, grid.last.y * 2.0)
	_bodies = cells_root.find_children("*", "StaticBody3D", true, false)
	_show_cells(false)

func _mesh_index(x: int, y: int, kind: int) -> int:
	match kind:
		1:
			return 0
		7:
			return 6
		2:
			return 1 if grid.is_straight(x, y) else 2
		5, 6:
			return 5
	return kind

func _place_cell(loaded: Array[Dictionary], x: int, y: int, kind: int, make_items: bool) -> void:
	var yaw := grid.angles[x + y * MtGrid.SIZE] * 90.0
	var mesh_index := _mesh_index(x, y, kind)
	var cell := Node3D.new()
	cell.position = _at(x * 2.0, FLOOR_Y, y * 2.0)
	cell.rotation.y = deg_to_rad(yaw)
	var piece: Dictionary = loaded[mesh_index]
	var visual := MeshInstance3D.new()
	visual.mesh = piece.visual
	cell.add_child(visual)
	for surface in visual.mesh.get_surface_count():
		var mat := visual.mesh.surface_get_material(surface)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("light_energy", GameState.light_energy)
	cell.add_child(MeshLoader.make_static_body_shared(piece))
	cells_root.add_child(cell)
	_cells.append(cell)
	if kind == 5 or kind == 6:
		_add_elevator_end(x, y, kind, yaw)
	if kind != 7:
		var lamp_height := 412.0 if kind == 3 or kind == 4 or mesh_index == 2 else 368.0
		_add_lamp(_at(x * 2.0, FLOOR_Y + lamp_height * RS, y * 2.0), LAMP_RANGE, Color.WHITE)
		return
	var cx := cos(deg_to_rad(yaw))
	var cy := sin(deg_to_rad(yaw))
	var lamp_dx := x * 2.0 - cy * 504.0 * RS + cx * 16.0 * RS
	var lamp_dz := y * 2.0 + cx * 504.0 * RS + cy * 16.0 * RS
	_add_lamp(_at(lamp_dx, FLOOR_Y + 396.0 * RS, lamp_dz), LAMP_RANGE, Color(1.0, 200.0 / 255.0, 200.0 / 255.0))
	if make_items:
		_make_items(Vector2(x * 2.0 + cx * -208.0 * RS - cy * 1226.0 * RS, y * 2.0 + cy * -208.0 * RS + cx * 1226.0 * RS), Vector2(lamp_dx, lamp_dz))

# FillRoom's cabs: Objects[2] (turned 180) and [4] of the room.
func _make_room_cabs() -> void:
	for slot in 2:
		var marker := Node3D.new()
		marker.position = room.fill_objects.get(2 + slot * 2, Vector3.ZERO)
		marker.rotation.y = PI if slot == 0 else 0.0
		room.add_child(marker)
		room_cabs[slot] = marker

# The last cell (kind 6) joins RoomDoors[0] and Objects[2], the first (kind 5) RoomDoors[2] and Objects[4]. The tunnel's door starts the other
# way round from the room's, so the car is at one end or the other.
func _add_elevator_end(x: int, y: int, kind: int, yaw: float) -> void:
	var slot := 0 if kind == 6 else 1
	var cx := cos(deg_to_rad(yaw))
	var cy := sin(deg_to_rad(yaw))
	var door := Node3D.new()
	door.set_script(DoorScript)
	door.elevator = true
	room.get_parent().add_child(door)
	var facility_door: Node3D = room.door_slots.get(slot * 2)
	door.setup(_at(x * 2.0 + cx * 240.0 * RS, FLOOR_Y, y * 2.0 + cy * 240.0 * RS), yaw + 90.0, false, facility_door != null and not facility_door.open, false, 0)
	if door.buttons.size() > 0:
		door.buttons[0].position.z += 0.05
	tunnel_doors[slot] = door
	_add_lamp(_at(x * 2.0 + cx * 555.0 * RS, FLOOR_Y + 469.0 * RS, y * 2.0 + cy * 555.0 * RS), ELEVATOR_LAMP_RANGE, Color.WHITE)
	var cab := Node3D.new()
	cells_root.add_child(cab)
	cab.global_position = _at(x * 2.0 + cx * 552.0 * RS, FLOOR_Y + 240.0 * RS, y * 2.0 + cy * 552.0 * RS)
	cab.rotation.y = deg_to_rad(yaw + 180.0)
	tunnel_cabs[slot] = cab

func _make_lifts() -> void:
	for slot in 2:
		var near_door: Node3D = room.door_slots.get(slot * 2)
		if near_door == null or tunnel_doors[slot] == null or room_cabs[slot] == null:
			continue
		var lift := Node.new()
		lift.set_script(ElevatorScript)
		room.add_child(lift)
		lift.setup(near_door, tunnel_doors[slot], room_cabs[slot], tunnel_cabs[slot])
		lift.rotates = true
		room.adopt_lift(lift)
		lifts.append(lift)

# CreateWaypoint at the cell, 8.2 up.
func _add_waypoint(x: int, y: int) -> void:
	var at := _at(x * 2.0, 8.2, y * 2.0)
	_wp_ids[x + y * MtGrid.SIZE] = facility.graph.add_point(at, "mt", room.room_key, false, false)
	_wp_positions.append(at)
	facility.rooms.waypoints().append(at)
	facility.rooms.waypoint_rooms().append(room)

# The slot tables of the original's linking, bug included: in the blocks for the cells above and beside, the second loop looks for the free slot
# in the new waypoint's list and writes it into the neighbour's, so a neighbour's link can be overwritten.
func _link_waypoints() -> void:
	var slots: Dictionary = {}
	for index in _wp_ids:
		slots[index] = [-1, -1, -1, -1]
	for y in MtGrid.SIZE:
		for x in MtGrid.SIZE:
			var index := x + y * MtGrid.SIZE
			if not _wp_ids.has(index):
				continue
			for step in NEIGHBOURS:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < 0 or nx >= MtGrid.SIZE or ny < 0 or ny >= MtGrid.SIZE:
					continue
				var other := nx + ny * MtGrid.SIZE
				if not _wp_ids.has(other) or other > index:
					continue
				var mine: Array = slots[index]
				var theirs: Array = slots[other]
				for i in 4:
					if mine[i] == other:
						break
					elif mine[i] == -1:
						mine[i] = other
						break
				for i in 4:
					if theirs[i] == index:
						break
					elif (theirs[i] if step == Vector2i(0, 1) else mine[i]) == -1:
						theirs[i] = index
						break
	for index in slots:
		for other in slots[index]:
			if other != -1:
				facility.graph.link(_wp_ids[index], _wp_ids[other])

func _make_items(spot_500: Vector2, spot_nvg: Vector2) -> void:
	var specs := [["SCP-500-01", "scp500", spot_500, grid.item_yaws[0]], ["Night Vision Goggles", "nvgoggles", spot_nvg, grid.item_yaws[1]]]
	for spec in specs:
		var pickup := RoomFill.make_pickup(spec[0], spec[1])
		room.get_parent().add_child(pickup)
		var spot: Vector2 = spec[2]
		pickup.global_position = _at(spot.x, FLOOR_Y + 80.0 * RS, spot.y)
		pickup.rotation.y = deg_to_rad(float(spec[3]))
		_items.append(pickup)

# AddLight(Null, ...): a light no room owns, always on, and the sprite of its fixture. Models are lit by the first eight (entity_lights.gd).
func _add_lamp(at: Vector3, light_range: float, colour: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.0
	lamp.light_cull_mask = 0
	lamp.omni_range = 2.0
	lamp.set_meta("blitz_range", light_range)
	lamp.set_meta("blitz_colour", colour)
	lamp.add_to_group(ENTITY_LIGHT_GROUP)
	cells_root.add_child(lamp)
	lamp.global_position = at
	lamps.append(lamp)
	if _fixture_quad == null:
		_fixture_quad = QuadMesh.new()
		_fixture_quad.size = Vector2.ONE * 0.26
		_fixture_material = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/light1.jpg")), Color.WHITE, true, true, false)
	var glow := MeshInstance3D.new()
	glow.mesh = _fixture_quad
	glow.material_override = _fixture_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cells_root.add_child(glow)
	glow.global_position = at

# HideEntity of the pieces also takes them out of collisions; the items in them stop falling until the floor is back.
func _show_cells(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	for cell in _cells:
		cell.visible = shown
	FacilityRoom.set_solid(_bodies, shown)
	for item in _items:
		if is_instance_valid(item) and item.is_in_group("pickup"):
			if shown:
				item.wake()
			else:
				item.set_physics_process(false)
