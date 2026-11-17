extends Node

var assets_root: String = ""
var assets_found := false

# The game files live in an `assets` folder next to the project (tools/fetch_assets.py puts them there) or next to
# the exported executable.
func _ready() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	var exe_dir := OS.get_executable_path().get_base_dir()
	var candidates: Array[String] = [project_dir.path_join("assets"), exe_dir.path_join("assets")]
	assets_root = candidates[0]
	for candidate in candidates:
		if DirAccess.dir_exists_absolute(candidate.path_join("GFX")):
			assets_root = candidate
			break
	assets_found = DirAccess.dir_exists_absolute(assets_root.path_join("GFX"))
	_ensure_actions()

var _resolved := {}

signal load_failed(text: String)

var load_errors: Array[String] = []

func report_error(text: String) -> void:
	load_errors.append(text)
	load_failed.emit(text)

func existing_file(relative: String) -> String:
	return _match_case(relative.replace("\\", "/"))

# A path under the assets folder with the case of the files on disk; any other path comes back as it is.
func match_case_absolute(path: String) -> String:
	var prefix := assets_root + "/"
	if not path.begins_with(prefix) or FileAccess.file_exists(path):
		return path
	return _match_case(path.trim_prefix(prefix))

# The original ran on Windows, where "Sl_monitors.jpg" finds SL_monitors.jpg; on Linux the case has to match.
func _match_case(relative: String) -> String:
	var path := assets_root.path_join(relative)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return path
	if _resolved.has(relative):
		return _resolved[relative]
	var current := assets_root
	for part in relative.split("/", false):
		var found := ""
		var directory := DirAccess.open(current)
		if directory != null:
			for entry in directory.get_files() + directory.get_directories():
				if entry.nocasecmp_to(part) == 0:
					found = entry
					break
		if found.is_empty():
			_resolved[relative] = path
			return path
		current = current.path_join(found)
	_resolved[relative] = current
	return current

# options.ini [binds] defaults of the original: W A S D (scancodes 17, 30, 31, 32), Shift sprint (42), Ctrl
# crouch (29), Space blink (57), Tab inventory (15), F5 save (63), F3 console (61); Escape is the menu. Doors,
# buttons, items and screens are used with the left mouse button (MouseHit1 / MouseUp1); items are dropped by
# dragging them out of the inventory, so `drop_item` has no key (tests trigger it directly).
func _ensure_actions() -> void:
	_bind("move_forward", [KEY_W])
	_bind("move_back", [KEY_S])
	_bind("move_left", [KEY_A])
	_bind("move_right", [KEY_D])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_CTRL])
	_bind("blink", [KEY_SPACE])
	_bind_mouse("interact", MOUSE_BUTTON_LEFT)
	_bind("drop_item", [])
	_bind("pause", [KEY_ESCAPE])
	_bind("inventory", [KEY_TAB])
	_bind("quick_save", [KEY_F5])

func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventMouseButton and existing.button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var duplicate := false
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey and existing.physical_keycode == key:
				duplicate = true
				break
		if duplicate:
			continue
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

# Many textures exist as both .jpg and .png (some of the .jpg files are unreadable): the first name that exists wins.
func existing_image(relative: String) -> String:
	var wanted := relative.replace("\\", "/")
	var base := wanted.get_basename()
	for candidate in [wanted, base + ".png", base + ".jpg", base + ".jpeg"]:
		var path := _match_case(candidate)
		if FileAccess.file_exists(path):
			return path
	return assets_root.path_join(wanted)
