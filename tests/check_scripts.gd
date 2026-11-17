extends SceneTree
# Loads every script and scene of the project, with the autoloads in place, and lists the ones that do not compile.
#   godot --headless --import                       (once, on a fresh checkout)
#   godot --headless --path . -s tests/check_scripts.gd
# Exits 1 when something is broken. A script with a parse error still loads as a resource (the playtest bot would then
# report a pass with no checks), so what is tested is whether it can make an instance; scenes are tested the same way.

const SKIPPED := [".godot", "assets", "build"]       # the game files fetched into assets/ are not the project's own

func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var broken := 0
	for path in files:
		if path == get_script().resource_path:
			continue        # reloading the script that is running would break it
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var ok := loaded != null
		if loaded is GDScript:
			ok = (loaded as GDScript).can_instantiate()
		elif loaded is PackedScene:
			ok = (loaded as PackedScene).can_instantiate()
		if not ok:
			broken += 1
			print("BROKEN  ", path)
	print("%d scripts and scenes checked, %d broken" % [files.size(), broken])
	quit(1 if broken > 0 else 0)

func _collect(folder: String, out: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not SKIPPED.has(sub):
			_collect(folder.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(folder.path_join(file))
