extends SceneTree
# Tests that need no game files: they run from a plain checkout (and in CI), unlike the playtest bot.
#   godot --headless --path . -s tests/test_units.gd
# Exits 1 when a check fails. Scripts that use the autoloads are loaded in _initialize, once the autoloads exist.

var _failures := 0
var _checks := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS  " if ok else "FAIL  ") + label + (("  [" + detail + "]") if not ok and not detail.is_empty() else ""))

func _initialize() -> void:
	_inflate()
	_ini_file()
	_blitz_string()
	_save_game()
	_event_states()
	_content_paths()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

# ---- scripts/io/inflate.gd, against Godot's own compressor ------------------------------------------------------------

# Godot's DEFLATE output is a zlib stream: two header bytes, the raw deflate data, four checksum bytes.
func _raw_deflate(data: PackedByteArray) -> PackedByteArray:
	var zlib := data.compress(FileAccess.COMPRESSION_DEFLATE)
	return zlib.slice(2, zlib.size() - 4)

func _noise(count: int, seed_value: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bytes := PackedByteArray()
	for i in count:
		bytes.append(rng.randi() & 255)
	return bytes

func _inflate() -> void:
	var Inflate = load("res://scripts/io/inflate.gd")
	var text := "The quick brown fox jumps over the lazy dog. ".repeat(60).to_utf8_buffer()
	var zeros := PackedByteArray()
	zeros.resize(70000)
	var cases := {
		"one byte": "a".to_utf8_buffer(),
		"repeated text (compressed blocks)": text,
		"zeros": zeros,
		"noise (a stored block)": _noise(5000, 1),
		"a lot of noise (several stored blocks)": _noise(200000, 2),
		"noise, text, zeros, noise": _noise(300, 3) + text + zeros.slice(0, 500) + _noise(300, 4),
	}
	for label in cases:
		var original: PackedByteArray = cases[label]
		var got: PackedByteArray = Inflate.inflate(_raw_deflate(original))
		check("inflate: " + label, got == original, "%d bytes back, %d expected" % [got.size(), original.size()])
	# damaged and cut-off data ends (a hang here would be a timeout of the whole run)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var packed := _raw_deflate(_noise(300, 5) + text)
	for attempt in 200:
		var damaged := packed.duplicate()
		if attempt % 2 == 0:
			damaged = damaged.slice(0, rng.randi_range(0, damaged.size()))
		else:
			for _flip in rng.randi_range(1, 6):
				damaged[rng.randi_range(0, damaged.size() - 1)] = rng.randi_range(0, 255)
		Inflate.inflate(damaged)
	check("inflate: damaged and cut-off data end", true)

# ---- scripts/io/ini_file.gd ---------------------------------------------------------------------------------------------

func _ini_file() -> void:
	var Ini = load("res://scripts/io/ini_file.gd")
	var path := "user://test_units.ini"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("; comment\n[Options]\nMap Size = 20\n[audio]\nmusic volume=0.5\n")
	file.close()
	var ini = Ini.parse(path)
	check("ini: section and key names ignore case, values are trimmed", ini.get_value("options", "map size", "") == "20" and ini.get_float("AUDIO", "Music Volume") == 0.5)
	check("ini: a missing key gives the default", ini.get_value("options", "nothing", "x") == "x")
	check("ini: a missing file gives an empty ini", Ini.parse("user://does_not_exist.ini").sections.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---- scripts/io/mesh_loader.gd ------------------------------------------------------------------------------------------

func _blitz_string() -> void:
	var mesh_loader = load("res://scripts/io/mesh_loader.gd")
	var path := "user://test_units.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(8)
	file.store_buffer("RoomMesh".to_utf8_buffer())
	file.store_32(5)
	file.store_buffer(PackedByteArray([0x61, 0x62, 0x00, 0x00, 0x00]))      # "ab" and padding
	file.store_32(0)
	file.close()
	var reader = mesh_loader._Reader.new(path)
	check("rmesh string: read by its length", reader.blitz_string() == "RoomMesh")
	check("rmesh string: a NUL ends the text", reader.blitz_string() == "ab")
	check("rmesh string: an empty one", reader.blitz_string() == "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---- scripts/game/save_game.gd ------------------------------------------------------------------------------------------

func _save_game() -> void:
	var SaveGame = load("res://scripts/game/save_game.gd")
	var had_save: bool = SaveGame.exists()
	var kept := PackedByteArray()
	if had_save:
		kept = FileAccess.get_file_as_bytes(SaveGame.path_of(SaveGame.LEGACY_SLOT))    # a player's own save is put back afterwards
	SaveGame.delete()
	check("save: a slot is written", SaveGame.write({"version": SaveGame.VERSION, "n": 1}) and SaveGame.exists())
	check("save: and read back", int(SaveGame.read().get("n", 0)) == 1)
	check("save: it is replaced, no temporary file is left", SaveGame.write({"version": SaveGame.VERSION, "n": 2}) and int(SaveGame.read().get("n", 0)) == 2 and not FileAccess.file_exists(SaveGame.path_of(SaveGame.LEGACY_SLOT) + ".tmp"))
	var stale := FileAccess.open(SaveGame.path_of(SaveGame.LEGACY_SLOT) + ".tmp", FileAccess.WRITE)
	stale.store_string("{half a save")
	stale.close()
	check("save: a temporary file from a crashed write is no obstacle", SaveGame.write({"version": SaveGame.VERSION, "n": 3}) and int(SaveGame.read().get("n", 0)) == 3)
	var damaged := FileAccess.open(SaveGame.path_of(SaveGame.LEGACY_SLOT), FileAccess.WRITE)
	damaged.store_string("{not json")
	damaged.close()
	check("save: a damaged slot reads as no save", SaveGame.read().is_empty())
	SaveGame.delete()
	if had_save:
		var restore := FileAccess.open(SaveGame.path_of(SaveGame.LEGACY_SLOT), FileAccess.WRITE)
		restore.store_buffer(kept)
		restore.close()

# ---- scripts/world/event_states.gd --------------------------------------------------------------------------------------

func _event_states() -> void:
	var EventStatesScript = load("res://scripts/world/event_states.gd")
	var events = EventStatesScript.new()
	events.room860.state = 1.0
	events.femur.magnets = false
	events.femur.levers = [1.0, 2.0]
	events.sl.lever_on = false
	events.coffin.lever_pitch = -5.0
	events.reset()
	check("events: reset restores the defaults", events.room860.state == 0.0 and events.femur.magnets and events.femur.levers == [81.0, -81.0] and events.sl.lever_on and events.coffin.lever_pitch == 10.0)
	var other = EventStatesScript.new()
	other.room049.pitches.append(1.0)
	check("events: every instance has its own arrays", EventStatesScript.new().room049.pitches.size() == 2)
	events.set_indexed("room860:state2", 3.0)
	check("events: a state is reached by its property path", events.get_indexed("room860:state2") == 3.0 and events.room860.state2 == 3.0)

# ---- autoload/content_paths.gd ---------------------------------------------------------------------------------------

func _content_paths() -> void:
	var paths: Node = root.get_node("ContentPaths")
	var kept: String = paths.assets_root
	var dir := ProjectSettings.globalize_path("user://case_test")
	DirAccess.make_dir_recursive_absolute(dir.path_join("GFX/Map"))
	FileAccess.open(dir.path_join("GFX/SL_monitors.jpg"), FileAccess.WRITE).close()
	FileAccess.open(dir.path_join("Credits.TXT"), FileAccess.WRITE).close()
	paths.assets_root = dir
	check("paths: a name finds the file of another case", paths.existing_file("GFX/Sl_Monitors.jpg") == dir.path_join("GFX/SL_monitors.jpg"))
	check("paths: so does a folder and a root file", paths.existing_file("gfx/map") == dir.path_join("GFX/Map") and paths.existing_file("Credits.txt") == dir.path_join("Credits.TXT"))
	check("paths: existing_image falls back through the case match", paths.existing_image("GFX/sl_monitors.png") == dir.path_join("GFX/SL_monitors.jpg"))
	check("paths: a missing file keeps the asked name", paths.existing_file("GFX/none.jpg") == dir.path_join("GFX/none.jpg"))
	paths.assets_root = kept
	paths._resolved.clear()
	for file in ["GFX/SL_monitors.jpg", "Credits.TXT", "GFX/Map", "GFX", ""]:
		DirAccess.remove_absolute(dir.path_join(file))
