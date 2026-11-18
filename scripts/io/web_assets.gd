class_name WebAssets
extends Control
# The web build has no assets folder next to it: the game files are served beside the page as small zips (tools/pack_web_assets.py)
# and extracted into the browser's own storage, where ContentPaths reads them. Done once; a later visit only compares versions.

signal _clicked

const FOLDER := "web-assets/"
const STAMP := "installed.json"
const TEMP := "user://web_part.zip"
const SLICE_MSEC := 12

const NOTE := "This is the web version of the port. It runs on the browser's compatibility renderer, so some features, effects and shaders may be missing or look different from the desktop version. It is mostly here for fun, because why not."

var _label := Label.new()
var _bar := ProgressBar.new()
var _note := Label.new()

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(400.0, 0.0)
	center.add_child(column)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_label)
	_bar.custom_minimum_size = Vector2(0.0, 16.0)
	_bar.max_value = 1.0
	column.add_child(_bar)
	_note.text = NOTE
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	_note.add_theme_font_size_override("font_size", 12)
	_note.visible = false
	column.add_child(_note)
	set_process_input(false)

# True once the game files are installed and the player has clicked; false (with the reason on the screen) when they could not be.
func run() -> bool:
	var base := _base_url()
	var got := await _download(base + "manifest.json")
	var problem: String = got[0]
	var manifest: Variant = JSON.parse_string((got[1] as PackedByteArray).get_string_from_utf8()) if problem.is_empty() else null
	if not manifest is Dictionary:
		return _fail("Could not download the game files list (%s)." % (problem if not problem.is_empty() else "not valid JSON"))
	if _installed_version() != str(manifest.get("version", "")) or not ContentPaths.refresh_assets():
		problem = await _install(base, manifest)
		if not problem.is_empty():
			return _fail(problem)
	await _wait_for_click()
	return true

func _install(base: String, manifest: Dictionary) -> String:
	var parts: Array = manifest.get("parts", [])
	var total := 0.0
	for part in parts:
		total += float(part.get("size", 0))
	var done := 0.0
	for part in parts:
		_label.text = "Downloading the game files (first visit only)\n%d / %d MB" % [int(done) >> 20, int(total) >> 20]
		_bar.value = done / maxf(total, 1.0)
		var problem := await _install_part(base, part)
		if not problem.is_empty():
			return "Could not install %s: %s." % [part.get("name", "a part"), problem]
		done += float(part.get("size", 0))
	var stamp := FileAccess.open(ContentPaths.web_root().path_join(STAMP), FileAccess.WRITE)
	if stamp == null:
		return "The browser would not store the game files (is private browsing on?)."
	stamp.store_string(JSON.stringify({"version": manifest.get("version", "")}))
	stamp.close()
	ContentPaths.refresh_assets()
	return ""

# Browsers start audio and allow the mouse to be captured only after a click or key press on the page.
func _wait_for_click() -> void:
	_bar.visible = false
	_label.text = "Click to start"
	_note.visible = true
	set_process_input(true)
	await _clicked

func _input(event: InputEvent) -> void:
	if MouseCapture.is_gesture(event):
		set_process_input(false)
		get_viewport().set_input_as_handled()
		_clicked.emit()

func _fail(text: String) -> bool:
	_label.text = text + "\nReload the page to try again."
	_bar.visible = false
	return false

func _base_url() -> String:
	return str(JavaScriptBridge.eval("new URL('%s', document.baseURI).href" % FOLDER, true))

func _installed_version() -> String:
	var path := ContentPaths.web_root().path_join(STAMP)
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return str(parsed.get("version", "")) if parsed is Dictionary else ""

# [problem, body]: the problem is empty when the download worked. The browser already undoes gzip (GitHub Pages compresses text
# files), so HTTPRequest must not try again.
func _download(url: String) -> Array:
	var request := HTTPRequest.new()
	request.accept_gzip = false
	add_child(request)
	request.request(url)
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return ["result %d, status %d" % [result[0], result[1]], PackedByteArray()]
	return ["", result[3]]

func _install_part(base: String, part: Dictionary) -> String:
	var got := await _download(base + str(part.name))
	if not (got[0] as String).is_empty():
		return "download failed (%s)" % got[0]
	var body: PackedByteArray = got[1]
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(body)
	if hash.finish().hex_encode() != str(part.sha256):
		return "checksum mismatch (%d bytes)" % body.size()
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	if file == null:
		return "could not write the download"
	file.store_buffer(body)
	file.close()
	body = PackedByteArray()
	var problem := await _extract(TEMP)
	DirAccess.remove_absolute(TEMP)
	return problem

# ZIPReader opens a file, not a buffer, which is why the part goes through TEMP.
func _extract(path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return "not a zip file"
	var root := ContentPaths.web_root()
	var slice_start := Time.get_ticks_msec()
	for name in zip.get_files():
		var target := root.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			zip.close()
			return "could not write " + name
		out.store_buffer(zip.read_file(name))
		out.close()
		if Time.get_ticks_msec() - slice_start > SLICE_MSEC:
			await get_tree().process_frame
			slice_start = Time.get_ticks_msec()
	zip.close()
	return ""
