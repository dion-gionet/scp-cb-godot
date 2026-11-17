extends RefCounted
class_name FillRoomRng
# The random numbers FillRoom (MapSystem.bb:2102) draws for each room, in order. CreateMap calls FillRoom for every room it
# creates, so the template and angle of every later room depend on how many numbers the earlier ones used. Only the count
# matters except where a draw decides whether more draws follow.
# Each CreateDoor draws Rand(8) (Main.bb:1994: Blitz evaluates every operand of And), each CreateItem draws Rand(360)
# (Items.bb:391), and AddLight draws two per light of the room mesh (MapSystem.bb:5758, 5762), after the Select.

const MAX_ROOM_LIGHTS := 32

# name -> number of draws, for the rooms whose draws never branch
const FIXED := {
	"lockroom": 2, "lockroom3": 2, "lockroom2": 108,
	"gatea": 5, "gateaentrance": 2, "exit1": 7,
	"roompj": 3, "room079": 4,
	"room2testroom2": 4, "room2storage": 10, "room2sroom": 6, "room2shaft": 8,
	"room2poffices": 8, "room2poffices2": 8, "room2elevator": 1, "room2cafeteria": 5,
	"room2nuke": 6, "room2tunnel": 5, "008": 5, "room035": 9, "room513": 4, "room966": 3,
	"room3storage": 12, "room049": 14, "room012": 5, "room2servers": 4, "room3servers2": 2,
	"testroom": 3, "room2offices": 4, "room2offices2": 6, "start": 8, "room2scps": 56,
	"room205": 2, "endroom": 1, "endroomc": 1, "coffin": 4, "room2doors": 2, "914": 6, "173": 60,
	"room2ccont": 2, "room106": 6, "room1123": 7, "pocketdimension": 9, "room2servers2": 5,
	"room2gw_b": 3, "room2gw": 3, "room3gw": 4, "room1162": 2, "room2scps2": 7, "room3offices": 1,
	"room2offices4": 2, "room2sl": 3, "medibay": 4, "room2cpit": 2,
}

# ctx: "lights" (light entities of the room mesh), "below_empty" (MapTemp(x, y - 1) = 0, for the checkpoints).
# Returns extra results: room860 gives "forest_grid" and "forest_state" (the generator state PlaceForest started from).
static func consume(rng: BlitzRng, room_name: String, ctx: Dictionary) -> Dictionary:
	var out := {}
	match room_name:
		"checkpoint1", "checkpoint2":
			_skip(rng, 2)
			if bool(ctx.get("below_empty", false)):
				_skip(rng, 1)
		"room860":
			_skip(rng, 4)
			var grid: PackedInt32Array = Forest.generate_grid(rng)
			out["forest_grid"] = grid
			out["forest_state"] = rng.state
			Forest.consume_place(grid, rng)
			_skip(rng, 2)
		"room3storage":
			_skip(rng, 4)
			out["hand_spot"] = rng.rand(3)
			_skip(rng, 7)
		"room3servers":
			_skip(rng, 1)
			for _i in 2:
				if rng.rand(2) == 1:
					_skip(rng, 1)
			_skip(rng, 1)
		"room2closets":
			_skip(rng, 3)
			for _i in 2:
				if rng.rand(2) == 1:
					_skip(rng, 1)
			_skip(rng, 4)
		"room2offices3":
			_skip(rng, 5)
			_skip(rng, rng.rand(0, 1) + 1)
			_skip(rng, 1)
			for _i in 2:
				if rng.rand(2) == 1:
					_skip(rng, 1)
			_skip(rng, 1)
		"room1archive":
			out["items"] = _archive_items(rng)
			_skip(rng, 1)
		_:
			_skip(rng, int(FIXED.get(room_name, 0)))
	_skip(rng, 2 * mini(int(ctx.get("lights", 0)), MAX_ROOM_LIGHTS))
	return out

const ROOM_SCALE := 8.0 / 2048.0
const ARCHIVE_DOCS := ["1123", "1048", "939", "682", "079", "096"]

# MapSystem.bb:4654-4731: the shelf items of room1archive, with the draws in Blitz's order. "yaw" is CreateItem's Rand(360).
static func _archive_items(rng: BlitzRng) -> Array:
	var items: Array = []
	for xt in 2:
		for yt in 3:
			for zt in 3:
				var chance := rng.rand(-10, 100)
				if chance < 0:
					break
				var item_name := "9V Battery"
				var tempname := "bat"
				if chance < 40:
					item_name = "Document SCP-" + ARCHIVE_DOCS[rng.rand(1, 6) - 1]
					tempname = "paper"
				elif chance < 45:
					var level := rng.rand(1, 2)
					item_name = "Level %d Key Card" % level
					tempname = "key%d" % level
				elif chance < 50:
					item_name = "First Aid Kit"
					tempname = "firstaid"
				elif chance < 60:
					pass
				elif chance < 70:
					item_name = "S-NAV 300 Navigator"
					tempname = "nav"
				elif chance < 85:
					item_name = "Radio Transceiver"
					tempname = "radio"
				elif chance < 95:
					item_name = "Clipboard"
					tempname = "clipboard"
				else:
					item_name = ["Playing Card", "Mastercard", "Origami"][rng.rand(1, 3) - 1]
					tempname = "misc"
				var z := (480.0 - 352.0 * zt + rng.rnd(-96.0, 96.0)) * ROOM_SCALE
				items.append({"name": item_name, "tempname": tempname, "x": (-672.0 + 864.0 * xt) * ROOM_SCALE, "y": (96.0 + 96.0 * yt) * ROOM_SCALE, "z": z, "yaw": rng.rand(360)})
	return items

static func _skip(rng: BlitzRng, count: int) -> void:
	for _i in count:
		rng.rand(0, 1)

# LoadRMesh (MapSystem.bb:336) makes a light template of each "light" and "spotlight" point entity not at the origin.
static var _light_counts: Dictionary = {}

static func light_count(path: String) -> int:
	if _light_counts.has(path):
		return int(_light_counts[path])
	var count := _scan_lights(path)
	_light_counts[path] = count
	return count

static func _scan_lights(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var magic := _string(f)
	var drawn := f.get_32()
	for _i in drawn:
		for _slot in 2:
			if f.get_8() != 0:
				_string(f)
		var verts := f.get_32()
		f.seek(f.get_position() + verts * 31)
		var tris := f.get_32()
		f.seek(f.get_position() + tris * 12)
	var hidden := f.get_32()
	for _i in hidden:
		var verts := f.get_32()
		f.seek(f.get_position() + verts * 12)
		var tris := f.get_32()
		f.seek(f.get_position() + tris * 12)
	if magic == "RoomMesh.HasTriggerBox":
		var boxes := f.get_32()
		for _b in boxes:
			var meshes := f.get_32()
			for _m in meshes:
				var verts := f.get_32()
				f.seek(f.get_position() + verts * 12)
				var tris := f.get_32()
				f.seek(f.get_position() + tris * 12)
			_string(f)
	var count := 0
	var points := f.get_32()
	for _p in points:
		var kind := _string(f)
		if kind == "screen":
			f.seek(f.get_position() + 12)
			_string(f)
		elif kind == "waypoint":
			f.seek(f.get_position() + 12)
		elif kind == "light" or kind == "spotlight":
			var x := f.get_float()
			var y := f.get_float()
			var z := f.get_float()
			if x != 0.0 or y != 0.0 or z != 0.0:
				count += 1
			f.get_float()
			_string(f)
			f.get_float()
			if kind == "spotlight":
				_string(f)
				f.seek(f.get_position() + 8)
		elif kind == "soundemitter":
			f.seek(f.get_position() + 20)
		elif kind == "playerstart":
			f.seek(f.get_position() + 12)
			_string(f)
		elif kind == "model":
			if not _string(f).is_empty():
				f.seek(f.get_position() + 36)
			else:
				f.seek(f.get_position() + 12)
		else:
			break
	return count

static func _string(f: FileAccess) -> String:
	var n := f.get_32()
	return f.get_buffer(n).get_string_from_ascii()
