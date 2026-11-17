extends RefCounted
class_name MapGenerator
# CreateMap (MapSystem.bb:7023) with Blitz's SeedRnd/Rand/Rnd (blitz_rng.gd), so a seed gives the original's facility.
# seed_value is the number SeedRnd gets: GenerateSeedNumber of the seed text in the menu (blitz_rng.gd seed_number).
# FillRoom runs inside CreateRoom in the original and draws numbers too; fill_room_rng.gd replays its draws so the rooms
# made after it come out the same. Blitz floats are 32-bit: the Floor(fraction * count) slots use float32 products.

const RoomOverlap = preload("res://scripts/world/room_overlap.gd")

const SHAPE_1 := 1
const SHAPE_2 := 2
const SHAPE_2C := 3
const SHAPE_3 := 4
const SHAPE_4 := 5
const ZONE_AMOUNT := 3

var width := 18
var height := 18
var seed_value := 0
var rooms: Array[Dictionary] = []
var start_room: Dictionary = {}
var rng_after_map := 0     # the generator state once the grid rooms and the four special rooms are filled
# CreateMap's map doors and InitNewGame's draws up to InitEvents (Main.bb:8406-8493), which the seed fixes too
var doors: Array[Dictionary] = []
var scp106_state := 0.0
var start_turn := 180
var rng_before_events := 0

var _grid: PackedInt32Array = PackedInt32Array()
var _rng := BlitzRng.new()
var _catalog: RefCounted

func room_disables_decals(room_name: String) -> bool:
	return bool(_catalog.get_template(room_name).get("disable_decals", false))

func generate(catalog: RefCounted, map_seed: int = -1, intro_enabled: bool = true) -> void:
	_catalog = catalog
	width = _map_size()
	height = width
	# an empty seed field: RandomSeed = Abs(MilliSecs())
	seed_value = map_seed if map_seed >= 0 else BlitzRng.seed_number(str(Time.get_ticks_msec()))
	_rng.seed_rnd(seed_value)
	rooms.clear()
	start_room = {}
	_grid = PackedInt32Array()
	_grid.resize((width + 2) * (height + 2))
	_grow()
	var amounts := _classify()
	_force_room1(amounts)
	_force_room4_and_2c(amounts)
	var names := _name_slots(amounts)
	_place(names)
	var specials := {
		"gatea": Vector2i(width - 1, 1),
		"pocketdimension": Vector2i(width - 1, height - 1),
		"173": Vector2i(1, height - 1),
		"dimension1499": Vector2i(1, 0),
	}
	for special in specials:
		if special == "173" and not intro_enabled:
			continue
		_fill(catalog.get_template(special), special, {})
	rng_after_map = _rng.state
	_prevent_overlap(specials, intro_enabled)
	_create_map_doors()
	scp106_state = 70.0 * 60.0 * float(_rng.rand(12, 17))
	_start_decals(specials, intro_enabled)
	start_turn = _rng.rand(160, 200)
	rng_before_events = _rng.state
	print("MAP seed=", seed_value, " size=", width, " rooms=", rooms.size(), " start=", start_room.get("grid", Vector2i(-1, -1)), " name=", start_room.get("name", ""))

func summarize() -> String:
	var shapes := [0, 0, 0, 0, 0, 0]
	var missing := 0
	var links := 0
	var occupied := {}
	for room in rooms:
		var shape := int(room.shape)
		if shape >= 1 and shape <= 5:
			shapes[shape] += 1
		if str(room.mesh).is_empty():
			missing += 1
		occupied[_key(room.grid)] = true
	for room in rooms:
		var grid: Vector2i = room.grid
		if occupied.has(_key(grid + Vector2i(1, 0))):
			links += 1
		if occupied.has(_key(grid + Vector2i(0, 1))):
			links += 1
	return "rooms=%d start=%s missing_mesh=%d links=%d shapes=%s" % [
		rooms.size(),
		str(start_room.get("name", "")),
		missing,
		links,
		str(shapes),
	]

func _map_size() -> int:
	var ini: RefCounted = IniFile.parse(ContentPaths.existing_file("options.ini"))
	var size := int(ini.get_value("options", "map size", "18"))
	return clampi(size, 12, 24)

func _grow() -> void:
	var x := width / 2
	var y := height - 2
	for i in range(y, height):
		_put(x, i, 1)
	var temp := 0
	var temp_height := 0
	while true:
		var span := _rng.rand(10, 15)
		if x > float(width) * 0.6:
			span = -span
		elif x > float(width) * 0.4:
			x = x - span / 2
		if x + span > width - 3:
			span = width - 3 - x
		elif x + span < 2:
			span = -x + 2
		x = mini(x, x + span)
		span = absi(span)
		for i in range(x, x + span + 1):
			_put(mini(i, width), y, 1)
		var drop := _rng.rand(3, 4)
		if y - drop < 1:
			drop = y - 1
		var halls := _rng.rand(4, 5)
		if _zone_band(y - drop) != _zone_band(y - drop + 1):
			drop -= 1
		for hall in range(1, halls + 1):
			var x2 := maxi(mini(_rng.rand(x, x + span - 1), width - 2), 2)
			var guard := 0
			while _occupied(x2, y - 1) or _occupied(x2 - 1, y - 1) or _occupied(x2 + 1, y - 1):
				x2 += 1
				guard += 1
				if guard > width + 2:
					break
			if x2 >= x + span:
				continue
			if hall == 1:
				temp_height = drop
				x2 = x if _rng.rand(2) == 1 else x + span
			else:
				temp_height = _rng.rand(1, drop)
			for y2 in range(y - temp_height, y + 1):
				_put(x2, y2, 255 if _zone_band(y2) != _zone_band(y2 + 1) else 1)
			if temp_height == drop:
				temp = x2
		x = temp
		y -= drop
		if y < 2:
			break

func _classify() -> Array:
	var amounts: Array = []
	for _shape in 6:
		var row: Array[int] = [0, 0, 0]
		amounts.append(row)
	for gy in range(1, height):
		var band := _zone_band(gy)
		for gx in range(1, width):
			if not _occupied(gx, gy):
				continue
			if _cell(gx, gy) < 255:
				_put(gx, gy, _neighbors(gx, gy))
			match _cell(gx, gy):
				1:
					amounts[SHAPE_1][band] += 1
				2:
					if _straight(gx, gy):
						amounts[SHAPE_2][band] += 1
					else:
						amounts[SHAPE_2C][band] += 1
				3:
					amounts[SHAPE_3][band] += 1
				4:
					amounts[SHAPE_4][band] += 1
	return amounts

func _force_room1(amounts: Array) -> void:
	var third := height / ZONE_AMOUNT
	for band in 3:
		var needed := 5 - int(amounts[SHAPE_1][band])
		if needed <= 0:
			continue
		for gy in range(third * (2 - band) + 1, third * (3 - band) - 2 + 1):
			for gx in range(2, width - 1):
				if _cell(gx, gy) == 0 and _neighbors(gx, gy) == 1:
					var host := _only_neighbor(gx, gy)
					var host_shape := _cell(host.x, host.y)
					var placed := false
					if host_shape == 2 and _straight(host.x, host.y):
						amounts[SHAPE_2][band] -= 1
						amounts[SHAPE_3][band] += 1
						placed = true
					elif host_shape == 3:
						amounts[SHAPE_3][band] -= 1
						amounts[SHAPE_4][band] += 1
						placed = true
					if placed:
						_put(host.x, host.y, host_shape + 1)
						_put(gx, gy, 1)
						amounts[SHAPE_1][band] += 1
						needed -= 1
				if needed == 0:
					break
			if needed == 0:
				break

func _force_room4_and_2c(amounts: Array) -> void:
	for band in 3:
		var y_start := 0
		var y_end := 0
		match band:
			2:
				y_start = 2
				y_end = height / 3
			1:
				y_start = height / 3 + 1
				y_end = _bint(_f32(float(height) * _f32(2.0 / 3.0)) - 1.0)
			0:
				y_start = _bint(_f32(float(height) * _f32(2.0 / 3.0)) + 1.0)
				y_end = height - 2
		if int(amounts[SHAPE_4][band]) < 1:
			var forced := false
			for gy in range(y_start, y_end + 1):
				for gx in range(2, width - 1):
					if _cell(gx, gy) == 3:
						var spot := _empty_arm(gx, gy)
						if spot.x >= 0:
							_put(spot.x, spot.y, 1)
							_put(gx, gy, 4)
							amounts[SHAPE_4][band] += 1
							amounts[SHAPE_3][band] -= 1
							amounts[SHAPE_1][band] += 1
							forced = true
					if forced:
						break
				if forced:
					break
		if int(amounts[SHAPE_2C][band]) < 1:
			var forced := false
			for gy in range(y_start + 1, y_end - 1 + 1):
				for gx in range(3, width - 2):
					if _cell(gx, gy) == 1 and _force_corner(gx, gy):
						amounts[SHAPE_2C][band] += 1
						amounts[SHAPE_2][band] += 1
						forced = true
					if forced:
						break
				if forced:
					break

# Select 0: the first arm whose four cells are all empty.
func _empty_arm(gx: int, gy: int) -> Vector2i:
	var arms := [
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, -1), Vector2i(2, 0)],
		[Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(-2, 0)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(0, 2)],
		[Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(0, -2)],
	]
	for arm in arms:
		var blocked := false
		for offset in arm:
			if _occupied(gx + offset.x, gy + offset.y):
				blocked = true
		if not blocked:
			return Vector2i(gx, gy) + arm[0]
	return Vector2i(-1, -1)

# Select True: only the first occupied neighbour's case runs; it turns this dead end and the next cell into a corner
# with a new dead end to one side, if the cells around are free.
func _force_corner(gx: int, gy: int) -> bool:
	var forward := Vector2i.ZERO
	if _occupied(gx - 1, gy):
		forward = Vector2i(1, 0)
	elif _occupied(gx + 1, gy):
		forward = Vector2i(-1, 0)
	elif _occupied(gx, gy - 1):
		forward = Vector2i(0, 1)
	elif _occupied(gx, gy + 1):
		forward = Vector2i(0, -1)
	else:
		return false
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1)]
	if forward.y != 0:
		sides = [Vector2i(-1, 0), Vector2i(1, 0)]
	var here := Vector2i(gx, gy)
	if _occupied_v(here + sides[0]) or _occupied_v(here + sides[1]) or _occupied_v(here + forward * 2):
		return false
	for side in sides:
		if _occupied_v(here + forward + side * 2) or _occupied_v(here + forward * 2 + side) or _occupied_v(here + forward + side):
			continue
		_put(gx, gy, 2)
		_put(gx + forward.x, gy + forward.y, 2)
		_put(gx + forward.x + side.x, gy + forward.y + side.y, 1)
		return true
	return false

func _name_slots(amounts: Array) -> Dictionary:
	var max_rooms := 55 * width / 20
	for shape in [SHAPE_1, SHAPE_2, SHAPE_2C, SHAPE_3, SHAPE_4]:
		max_rooms = maxi(max_rooms, int(amounts[shape][0]) + int(amounts[shape][1]) + int(amounts[shape][2]) + 1)
	var names := {}
	for shape in [SHAPE_1, SHAPE_2, SHAPE_2C, SHAPE_3, SHAPE_4]:
		var row: Array[String] = []
		row.resize(max_rooms + 1)
		row.fill("")
		names[shape] = row
	var r1: Array = amounts[SHAPE_1]
	var r2: Array = amounts[SHAPE_2]
	var r2c: Array = amounts[SHAPE_2C]
	var r3: Array = amounts[SHAPE_3]
	var r4: Array = amounts[SHAPE_4]
	var one: Array = names[SHAPE_1]
	var two: Array = names[SHAPE_2]
	var corner: Array = names[SHAPE_2C]
	var three: Array = names[SHAPE_3]
	var four: Array = names[SHAPE_4]

	var min_pos := 1
	var max_pos := int(r1[0]) - 1
	_assign(one, 0, "start")
	_set_room(one, "roompj", _part(0.1, r1[0]), min_pos, max_pos)
	_set_room(one, "914", _part(0.3, r1[0]), min_pos, max_pos)
	_set_room(one, "room1archive", _part(0.5, r1[0]), min_pos, max_pos)
	_set_room(one, "room205", _part(0.6, r1[0]), min_pos, max_pos)
	_assign(corner, 0, "lockroom")
	min_pos = 1
	max_pos = int(r2[0]) - 1
	_assign(two, 0, "room2closets")
	_set_room(two, "room2testroom2", _part(0.1, r2[0]), min_pos, max_pos)
	_set_room(two, "room2scps", _part(0.2, r2[0]), min_pos, max_pos)
	_set_room(two, "room2storage", _part(0.3, r2[0]), min_pos, max_pos)
	_set_room(two, "room2gw_b", _part(0.4, r2[0]), min_pos, max_pos)
	_set_room(two, "room2sl", _part(0.5, r2[0]), min_pos, max_pos)
	_set_room(two, "room012", _part(0.55, r2[0]), min_pos, max_pos)
	_set_room(two, "room2scps2", _part(0.6, r2[0]), min_pos, max_pos)
	_set_room(two, "room1123", _part(0.7, r2[0]), min_pos, max_pos)
	_set_room(two, "room2elevator", _part(0.85, r2[0]), min_pos, max_pos)
	_assign(three, int(floor(_f32(_rng.rnd(0.2, 0.8) * float(r3[0])))), "room3storage")
	_assign(corner, _part(0.5, r2c[0]), "room1162")
	_assign(four, _part(0.3, r4[0]), "room4info")

	min_pos = int(r1[0])
	max_pos = int(r1[0]) + int(r1[1]) - 1
	_set_room(one, "room079", int(r1[0]) + _part(0.15, r1[1]), min_pos, max_pos)
	_set_room(one, "room106", int(r1[0]) + _part(0.3, r1[1]), min_pos, max_pos)
	_set_room(one, "008", int(r1[0]) + _part(0.4, r1[1]), min_pos, max_pos)
	_set_room(one, "room035", int(r1[0]) + _part(0.5, r1[1]), min_pos, max_pos)
	_set_room(one, "coffin", int(r1[0]) + _part(0.7, r1[1]), min_pos, max_pos)
	min_pos = int(r2[0])
	max_pos = int(r2[0]) + int(r2[1]) - 1
	_assign(two, int(r2[0]) + _part(0.1, r2[1]), "room2nuke")
	_set_room(two, "room2tunnel", int(r2[0]) + _part(0.25, r2[1]), min_pos, max_pos)
	_set_room(two, "room049", int(r2[0]) + _part(0.4, r2[1]), min_pos, max_pos)
	_set_room(two, "room2shaft", int(r2[0]) + _part(0.6, r2[1]), min_pos, max_pos)
	_set_room(two, "testroom", int(r2[0]) + _part(0.7, r2[1]), min_pos, max_pos)
	_set_room(two, "room2servers", int(r2[0]) + _part(0.9, r2[1]), min_pos, max_pos)
	_assign(three, int(r3[0]) + _part(0.3, r3[1]), "room513")
	_assign(three, int(r3[0]) + _part(0.6, r3[1]), "room966")
	_assign(corner, int(r2c[0]) + _part(0.5, r2c[1]), "room2cpit")

	var ez1 := int(r1[0]) + int(r1[1])
	_assign(one, ez1 + int(r1[2]) - 2, "exit1")
	_assign(one, ez1 + int(r1[2]) - 1, "gateaentrance")
	_assign(one, ez1, "room1lifts")
	min_pos = int(r2[0]) + int(r2[1])
	max_pos = min_pos + int(r2[2]) - 1
	_assign(two, min_pos + _part(0.1, r2[2]), "room2poffices")
	_set_room(two, "room2cafeteria", min_pos + _part(0.2, r2[2]), min_pos, max_pos)
	_set_room(two, "room2sroom", min_pos + _part(0.3, r2[2]), min_pos, max_pos)
	_set_room(two, "room2servers2", min_pos + _part(0.4, r2[2]), min_pos, max_pos)
	_set_room(two, "room2offices", min_pos + _part(0.45, r2[2]), min_pos, max_pos)
	_set_room(two, "room2offices4", min_pos + _part(0.5, r2[2]), min_pos, max_pos)
	_set_room(two, "room860", min_pos + _part(0.6, r2[2]), min_pos, max_pos)
	_set_room(two, "medibay", min_pos + _part(0.7, r2[2]), min_pos, max_pos)
	_set_room(two, "room2poffices2", min_pos + _part(0.8, r2[2]), min_pos, max_pos)
	_set_room(two, "room2offices2", min_pos + _part(0.9, r2[2]), min_pos, max_pos)
	var ez2c := int(r2c[0]) + int(r2c[1])
	_assign(corner, ez2c, "room2ccont")
	_assign(corner, ez2c + 1, "lockroom2")
	var ez3 := int(r3[0]) + int(r3[1])
	_assign(three, ez3 + _part(0.3, r3[2]), "room3servers")
	_assign(three, ez3 + _part(0.7, r3[2]), "room3servers2")
	_assign(three, ez3 + _part(0.5, r3[2]), "room3offices")
	names["max"] = max_rooms
	return names

func _place(names: Dictionary) -> void:
	var cursor := {SHAPE_1: 0, SHAPE_2: 0, SHAPE_2C: 0, SHAPE_3: 0, SHAPE_4: 0}
	var max_rooms := int(names.max)
	for gy in range(height - 1, 0, -1):
		var zone := _placement_zone(gy)
		for gx in range(1, width - 1):
			if _cell(gx, gy) == 255:
				_add_room(gx, gy, zone, SHAPE_2, "checkpoint1" if gy > height / 2 else "checkpoint2")
				continue
			if not _occupied(gx, gy):
				continue
			var shape := SHAPE_1
			match _neighbors(gx, gy):
				1:
					shape = SHAPE_1
				2:
					if (_occupied(gx - 1, gy) and _occupied(gx + 1, gy)) or (_occupied(gx, gy - 1) and _occupied(gx, gy + 1)):
						shape = SHAPE_2
					else:
						shape = SHAPE_2C
				3:
					shape = SHAPE_3
				4:
					shape = SHAPE_4
				_:
					continue
			var room_name := ""
			if int(cursor[shape]) < max_rooms:
				var row: Array = names[shape]
				var index := int(cursor[shape])
				if index < row.size():
					room_name = str(row[index])
			var record := _add_room(gx, gy, zone, shape, room_name)
			record.angle = _angle(gx, gy, shape)
			cursor[shape] = int(cursor[shape]) + 1

# The rooms in CreateMap's creation order, specials last; PreventRoomOverlap may move or turn the grid rooms.
func _prevent_overlap(specials: Dictionary, intro_enabled: bool) -> void:
	var entries: Array = []
	for record in rooms:
		entries.append(_overlap_entry(str(record.name), int(record.zone), record.grid, int(record.angle)))
	for special in specials:
		if special == "173" and not intro_enabled:
			continue
		entries.append(_overlap_entry(special, 0, specials[special], 0))
	RoomOverlap.resolve(entries)
	for i in rooms.size():
		var entry: Dictionary = entries[i]
		var record := rooms[i]
		var grid := Vector2i(roundi(float(entry.x) / 8.0), roundi(float(entry.z) / 8.0))
		record.grid = grid
		record.position = Vector3(float(grid.x) * 8.0, 0.0, -float(grid.y) * 8.0)
		record.angle = posmod(int(entry.angle), 360)
		record.ext_size = Vector2(absf(entry.ext_max.x - entry.ext_min.x), absf(entry.ext_max.z - entry.ext_min.z))

# MapSystem.bb:7650: from the top-right cell down, the first room at each cell gets an east and a north door where its shape and
# angle leave that side open. Each draws Max(Rand(-3, 1), 0) for dopen, then CreateDoor's Rand(8) for AutoClose. Rows
# [6, 12) are zone 2 (Transition 7 and 13), whose doors are heavy, and a heavy door never auto-closes.
func _create_map_doors() -> void:
	doors.clear()
	var at := {}
	for record in rooms:
		var key := _key(record.grid)
		if not at.has(key):
			at[key] = record
	for gy in range(height, -1, -1):
		var heavy := gy >= 6 and gy < 12
		for gx in range(width, -1, -1):
			if not _occupied(gx, gy) or not at.has(_key(Vector2i(gx, gy))):
				continue
			var record: Dictionary = at[_key(Vector2i(gx, gy))]
			var angle := posmod(int(record.angle), 360)
			var east := true
			var north := true
			match int(record.shape):
				SHAPE_1:
					east = angle == 90
					north = angle == 180
				SHAPE_2:
					east = angle == 90 or angle == 270
					north = angle == 0 or angle == 180
				SHAPE_2C:
					east = angle == 0 or angle == 90
					north = angle == 180 or angle == 90
				SHAPE_3:
					east = angle == 0 or angle == 180 or angle == 90
					north = angle == 180 or angle == 90 or angle == 270
			if east and gx + 1 < width + 1 and _occupied(gx + 1, gy):
				doors.append(_map_door(gx, gy, Vector2i(gx + 1, gy), "e", heavy))
			if north and gy + 1 < height + 1 and _occupied(gx, gy + 1):
				doors.append(_map_door(gx, gy, Vector2i(gx, gy + 1), "n", heavy))

func _map_door(gx: int, gy: int, other: Vector2i, side: String, heavy: bool) -> Dictionary:
	var open := maxi(_rng.rand(-3, 1), 0) == 1
	var auto_close := _rng.rand(8) == 1 and open and not heavy
	var east := side == "e"
	return {
		"key": "%d,%d|%s" % [gx, gy, side],
		"pos": Vector3(gx * 8.0 + 4.0, 0.0, -gy * 8.0) if east else Vector3(gx * 8.0, 0.0, -gy * 8.0 - 4.0),
		"yaw": 90.0 if east else 0.0,
		"heavy": heavy, "open": open, "auto_close": auto_close,
		"a": "%d,%d" % [gx, gy], "b": _key(other),
	}

# Main.bb:8432: each room in creation order, specials last, two chances in 4 of a floor decal unless rooms.ini disables them
# (the port does not place them yet; only the draws are kept), and with the intro off the start room makes the two papers the
# player carries (CreateItem draws Rand(360) each).
func _start_decals(specials: Dictionary, intro_enabled: bool) -> void:
	var names: Array[String] = []
	for record in rooms:
		names.append(str(record.name))
	for special in specials:
		if special != "173" or intro_enabled:
			names.append(str(special))
	for room_name in names:
		if not bool(_catalog.get_template(room_name).get("disable_decals", false)):
			if _rng.rand(4) == 1:
				FillRoomRng._skip(_rng, 6)
			if _rng.rand(4) == 1:
				FillRoomRng._skip(_rng, 5)
		if room_name == "start" and not intro_enabled:
			FillRoomRng._skip(_rng, 2)

func _overlap_entry(room_name: String, zone: int, grid: Vector2i, angle: int) -> Dictionary:
	var template: Dictionary = _catalog.get_template(room_name)
	var mesh := str(template.get("mesh", ""))
	var extents: Array = RoomOverlap.mesh_extents(ContentPaths.existing_file(mesh) if not mesh.is_empty() else "")
	return {
		"name": room_name,
		"shape": int(template.get("shape", 0)),
		"zone": zone,
		"x": float(grid.x) * 8.0,
		"z": float(grid.y) * 8.0,
		"angle": angle,
		"disabled": bool(template.get("disable_overlap", false)),
		"mesh_min": extents[0],
		"mesh_max": extents[1],
	}

# The angle CreateMap turns the room to; a straight ROOM2 draws Rand(2) for it after CreateRoom.
func _angle(gx: int, gy: int, shape: int) -> int:
	match shape:
		SHAPE_1:
			if _occupied(gx, gy + 1):
				return 180
			elif _occupied(gx - 1, gy):
				return 270
			elif _occupied(gx + 1, gy):
				return 90
		SHAPE_2:
			if _occupied(gx - 1, gy) and _occupied(gx + 1, gy):
				return 90 if _rng.rand(2) == 1 else 270
			return 180 if _rng.rand(2) == 1 else 0
		SHAPE_2C:
			if _occupied(gx - 1, gy) and _occupied(gx, gy + 1):
				return 180
			elif _occupied(gx + 1, gy) and _occupied(gx, gy + 1):
				return 90
			elif _occupied(gx - 1, gy) and _occupied(gx, gy - 1):
				return 270
		SHAPE_3:
			if not _occupied(gx, gy - 1):
				return 180
			elif not _occupied(gx - 1, gy):
				return 90
			elif not _occupied(gx + 1, gy):
				return 270
	return 0

func _add_room(gx: int, gy: int, zone: int, shape: int, room_name: String) -> Dictionary:
	var template: Dictionary = _catalog.get_template(room_name) if not room_name.is_empty() else {}
	if template.is_empty():
		template = _catalog.pick(shape, zone, _rng)
	var record := {
		"name": str(template.get("name", room_name)),
		"mesh": str(template.get("mesh", "")),
		"shape": shape,
		"zone": zone,
		"grid": Vector2i(gx, gy),
		"angle": 0,
		"position": Vector3(float(gx) * 8.0, 0.0, -float(gy) * 8.0),
		"large": bool(template.get("large", false)),
	}
	rooms.append(record)
	if record.name == "start":
		start_room = record
	record["below_empty"] = not _occupied(gx, gy - 1)
	_fill(template, str(record.name), {"below_empty": record.below_empty}, record)
	return record

# FillRoom's draws; the state it started from is kept on the record for anything that wants to replay them.
func _fill(template: Dictionary, room_name: String, ctx: Dictionary, record: Dictionary = {}) -> void:
	record["fill_rng"] = _rng.state
	var mesh := str(template.get("mesh", ""))
	ctx["lights"] = FillRoomRng.light_count(ContentPaths.existing_file(mesh)) if not mesh.is_empty() else 0
	var extra := FillRoomRng.consume(_rng, room_name, ctx)
	record.merge(extra, true)

func _set_room(row: Array, room_name: String, pos: int, min_pos: int, max_pos: int) -> void:
	if max_pos < min_pos:
		return
	var looped := false
	while pos >= 0 and pos < row.size() and str(row[pos]) != "":
		pos += 1
		if pos > max_pos:
			if not looped:
				pos = min_pos + 1
				looped = true
			else:
				return
	_assign(row, pos, room_name)

func _assign(row: Array, pos: int, room_name: String) -> void:
	if pos >= 0 and pos < row.size():
		row[pos] = room_name

func _part(fraction: float, count: int) -> int:
	return int(floor(_f32(_f32(fraction) * float(count))))

func _placement_zone(gy: int) -> int:
	if gy < height / 3 + 1:
		return 3
	if float(gy) < _f32(float(height) * _f32(2.0 / 3.0)):
		return 2
	return 1

# GetZone: 0 for the bottom third (light containment) to 2 for the top.
func _zone_band(gy: int) -> int:
	return mini(int(floor(_f32(_f32(float(width - gy) / float(width)) * float(ZONE_AMOUNT)))), ZONE_AMOUNT - 1)

func _neighbors(gx: int, gy: int) -> int:
	return int(_occupied(gx + 1, gy)) + int(_occupied(gx - 1, gy)) + int(_occupied(gx, gy + 1)) + int(_occupied(gx, gy - 1))

func _straight(gx: int, gy: int) -> bool:
	var horizontal := int(_occupied(gx + 1, gy)) + int(_occupied(gx - 1, gy))
	var vertical := int(_occupied(gx, gy + 1)) + int(_occupied(gx, gy - 1))
	return horizontal == 2 or vertical == 2

func _only_neighbor(gx: int, gy: int) -> Vector2i:
	if _occupied(gx + 1, gy):
		return Vector2i(gx + 1, gy)
	if _occupied(gx - 1, gy):
		return Vector2i(gx - 1, gy)
	if _occupied(gx, gy + 1):
		return Vector2i(gx, gy + 1)
	return Vector2i(gx, gy - 1)

func _occupied(gx: int, gy: int) -> bool:
	return _cell(gx, gy) > 0

func _occupied_v(cell: Vector2i) -> bool:
	return _cell(cell.x, cell.y) > 0

func _cell(gx: int, gy: int) -> int:
	if gx < 0 or gy < 0 or gx > width + 1 or gy > height + 1:
		return 0
	return _grid[gx + gy * (width + 2)]

func _put(gx: int, gy: int, value: int) -> void:
	if gx < 0 or gy < 0 or gx > width + 1 or gy > height + 1:
		return
	_grid[gx + gy * (width + 2)] = value

func _key(grid: Vector2i) -> String:
	return "%d,%d" % [grid.x, grid.y]

static func _f32(value: float) -> float:
	return BlitzRng._f32(value)

# Blitz rounds a float to the nearest int when it is stored in an int.
static func _bint(value: float) -> int:
	return int(round(value))
