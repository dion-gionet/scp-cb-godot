extends RefCounted
class_name RoomCatalog


const SHAPE_1 := 1
const SHAPE_2 := 2
const SHAPE_2C := 3
const SHAPE_3 := 4
const SHAPE_4 := 5

var templates: Array[Dictionary] = []
var by_name: Dictionary = {}

func load_from_ini() -> void:
	templates.clear()
	by_name.clear()
	var ini: RefCounted = IniFile.parse(ContentPaths.existing_file("Data/rooms.ini"))
	for section in ini.sections.keys():
		var mesh := str(ini.get_value(section, "mesh path", "")).replace("\\", "/")
		if mesh.is_empty():
			continue
		var shape := _shape(ini.get_value(section, "shape", ""))
		if shape == 0:
			continue
		var zones: Array[int] = []
		for slot in 5:
			zones.append(int(ini.get_value(section, "zone%d" % (slot + 1), "0")))
		var entry := {
			"name": section.to_lower(),
			"mesh": mesh,
			"shape": shape,
			"commonness": clampi(int(ini.get_value(section, "commonness", "0")), 0, 100),
			"zones": zones,
			"large": _flag(ini.get_value(section, "large", "0")),
			"disable_overlap": _flag(ini.get_value(section, "disableoverlapcheck", "0")),
			"disable_decals": _flag(ini.get_value(section, "disabledecals", "0")),
		}
		templates.append(entry)
		by_name[entry.name] = entry

func get_template(room_name: String) -> Dictionary:
	return by_name.get(room_name.to_lower(), {})

# CreateRoom (MapSystem.bb:2023) without a name: Rand(total commonness of the shape in the zone), then the template whose
# share holds the roll, in rooms.ini order. The roll is drawn even when nothing fits.
func pick(shape: int, zone: int, rng: BlitzRng) -> Dictionary:
	var total := 0
	for entry in templates:
		if int(entry.shape) == shape and _in_zone(entry, zone):
			total += int(entry.commonness)
	var roll: int = rng.rand(total)
	var cursor := 0
	for entry in templates:
		if int(entry.shape) != shape:
			continue
		for value in entry.zones:
			if int(value) != zone:
				continue
			cursor += int(entry.commonness)
			if roll > cursor - int(entry.commonness) and roll <= cursor:
				return entry
	return {}

func _in_zone(entry: Dictionary, zone: int) -> bool:
	var zones: Array = entry.zones
	for value in zones:
		if int(value) == zone:
			return true
	return false

func _shape(raw: String) -> int:
	match raw.strip_edges().to_lower():
		"1", "room1":
			return SHAPE_1
		"2", "room2":
			return SHAPE_2
		"2c", "room2c":
			return SHAPE_2C
		"3", "room3":
			return SHAPE_3
		"4", "room4":
			return SHAPE_4
		_:
			return 0

func _flag(raw: String) -> bool:
	var text := raw.strip_edges().to_lower()
	return text == "true" or text == "1"
