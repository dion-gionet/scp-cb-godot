extends RefCounted
# The drinks of SCP-294 (Data/SCP-294.ini). A section is "[Name|Other name|...]" and the original's GetINISectionLocation finds
# the first section line in which the typed text appears right after the "[" or a "|" (the first occurrence in the line only,
# so a typed prefix of a name is enough: "coff" gets the coffee).

static var _ini: IniFile = null

static func _load() -> void:
	if _ini == null:
		_ini = IniFile.parse(ContentPaths.existing_file("Data/SCP-294.ini"))

# The section's keys (lower case) for what was typed, or {} when 294 has no such drink ("OUT OF RANGE").
static func find(typed: String) -> Dictionary:
	_load()
	var query := typed.strip_edges().to_lower()
	if query.is_empty():
		return {}
	for section in _ini.sections:
		var line := "[" + str(section) + "]"
		var at := line.find(query)
		if at > 0 and (line[at - 1] == "[" or line[at - 1] == "|"):
			return _ini.sections[section]
	return {}

static func get_float(drink: Dictionary, key: String, default_value: float = 0.0) -> float:
	if not drink.has(key) or str(drink[key]).is_empty():
		return default_value
	return float(str(drink[key]))

# GetINIInt2: "true" and numbers count, anything else is 0.
static func get_int(drink: Dictionary, key: String) -> int:
	var raw := str(drink.get(key, "")).strip_edges().to_lower()
	if raw == "true":
		return 1
	if raw == "false" or raw.is_empty():
		return 0
	return int(raw)

# "r, g, b" of the liquid as 0..1 floats.
static func get_color(drink: Dictionary) -> Color:
	var parts := str(drink.get("color", "0,0,0")).split(",")
	if parts.size() < 3:
		return Color.BLACK
	return Color(clampf(float(parts[0].strip_edges()) / 255.0, 0.0, 1.0), clampf(float(parts[1].strip_edges()) / 255.0, 0.0, 1.0), clampf(float(parts[2].strip_edges()) / 255.0, 0.0, 1.0))
