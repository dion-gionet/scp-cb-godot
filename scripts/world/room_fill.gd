extends RefCounted
class_name RoomFill
# Per-room contents from the 1.3.11 FillRoom function, extracted by tools/extract_fill_room.gd
# into data/room_fill.json. Positions are room-local Blitz metres (x, y, z).

static var _data: Dictionary = {}
static var _ready := false

static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	var path := "res://data/room_fill.json"
	if not FileAccess.file_exists(path):
		push_warning("room_fill.json missing; rooms will be empty. Run tools/extract_fill_room.gd")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("room_fill.json could not be read; rooms will be empty. Run tools/extract_fill_room.gd")

static func for_room(room_name: String) -> Dictionary:
	_ensure()
	var rooms: Dictionary = _data.get("rooms", {})
	return rooms.get(room_name.to_lower(), {})

# Every item the console can spawn: [{name, tempname}] (the templates and their variants).
# Every item template as [name, tempname], in the order the original defines them (CreateItemTemplate), which is the order ItemTemplates is
# walked in (SCP-1162 tries them one by one).
static func item_order() -> Array:
	_ensure()
	return _data.get("item_order", [])

static func spawnable() -> Array:
	_ensure()
	var out: Array = []
	var seen := {}
	for key in _data.get("item_variants", {}):
		var parts: PackedStringArray = str(key).split("|")
		if parts.size() == 2 and not seen.has(key):
			seen[key] = true
			out.append({"name": parts[0], "tempname": parts[1]})
	for name in _data.get("item_templates", {}):
		var template: Dictionary = _data.item_templates[name]
		var key2 := "%s|%s" % [name, template.get("tempname", "")]
		if not seen.has(key2):
			seen[key2] = true
			out.append({"name": name, "tempname": str(template.get("tempname", ""))})
	return out

static func item_template(item_name: String, tempname: String = "") -> Dictionary:
	_ensure()
	if item_name.begins_with("Cup of "):
		item_name = "cup"          # a cup of anything is the cup template under another name (it\name)
	if not tempname.is_empty():
		var variants: Dictionary = _data.get("item_variants", {})
		var key := "%s|%s" % [item_name, tempname]
		if variants.has(key):
			return variants[key]
	var templates: Dictionary = _data.get("item_templates", {})
	return templates.get(item_name, {})


# A world item (model, ambient lighting, falling physics); see world_item.gd.
static func make_pickup(item_name: String, tempname: String, extra: Dictionary = {}) -> StaticBody3D:
	var item := WorldItem.new()
	item.setup(item_name, tempname, item_template(item_name, tempname))
	if tempname == "cup":
		item.set_cup(item_name, Color(float(extra.get("cr", 1.0)), float(extra.get("cg", 1.0)), float(extra.get("cb", 1.0))), float(extra.get("ca", 1.0)))
	if extra.has("state"):
		item.set_meta("state", float(extra.state))
	if extra.has("pose"):
		item.set_pose(float(extra.pose))
	if extra.has("inv"):
		item.set_meta("inv", extra.inv)      # what a clipboard or a wallet holds
	return item
