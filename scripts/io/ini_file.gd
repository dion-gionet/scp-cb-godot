class_name IniFile
extends RefCounted

var sections: Dictionary = {}

static func parse(path: String) -> IniFile:
	var ini := IniFile.new()
	if not FileAccess.file_exists(path):
		push_warning("INI not found: %s" % path)
		return ini
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("INI unreadable: %s" % path)
		return ini
	var section := ""
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			if not ini.sections.has(section):
				ini.sections[section] = {}
			continue
		var eq := line.find("=")
		if eq < 0 or section.is_empty():
			continue
		var key := line.substr(0, eq).strip_edges().to_lower()
		var value := line.substr(eq + 1).strip_edges()
		ini.sections[section][key] = value
	return ini

func get_value(section: String, key: String, default_value: String = "") -> String:
	section = section.to_lower()
	key = key.to_lower()
	if not sections.has(section):
		return default_value
	return str(sections[section].get(key, default_value))

func get_float(section: String, key: String, default_value: float = 0.0) -> float:
	var raw := get_value(section, key, "")
	if raw.is_empty():
		return default_value
	return float(raw)
