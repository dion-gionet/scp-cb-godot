extends CanvasLayer
class_name LoadingScreen
# Menu.bb InitLoadingScreens / DrawLoading: a random screen of Loadingscreens\loadingscreens.ini (picked at 0 %)
# over loadingback.jpg, both at their own pixel size; a bar of blink meter segments, "LOADING - n %", the
# screen's title and one of its texts (the next one each time the percent passes 100 / texts * (shown + 1)).
# At 100 % Horror8 plays once and the screen waits for any key or click. The "CWM" screen has a scrambled title
# and text and its own sounds.

signal closed


# Chr(130) to Chr(159) in the Windows code page the original's fonts draw; 0x8D, 0x8F, 0x90 and 0x9D are
# undefined there and Windows maps them to the C1 controls, which keeps all 30 slots aligned
const CP1252 := "‚ƒ„…†‡ˆ‰Š‹Œ\u008dŽ\u008f\u0090‘’“”•–—˜™š›œ\u009džŸ"
const CWM_LINES := ["A very fine radio might prove to be useful.", "ThIS PLaCE WiLL BUrN", "You cannot control it.",
	"eof9nsd3jue4iwe1fgj", "YOU NEED TO TRUST IT", "Look my friend in the eye when you address him, isn't that the way of the gentleman?",
	"???____??_???__????n?", "Jorge has been expecting you.", "Jorge has been expecting you.", "???????????",
	"Make her a member of the midnight crew.", "oncluded that coming here was a mistake. We have to turn back.",
	"This alloy contains the essence of my life."]

static var _screens: Array = []

var percent := 0
var waiting := false
var _screen: Dictionary = {}
var _text_index := 0
var _short := false
var _view: Control

static func _load_screens() -> void:
	if not _screens.is_empty():
		return
	var path := ContentPaths.existing_file("Loadingscreens/loadingscreens.ini")
	if not FileAccess.file_exists(path):
		return
	var ini: RefCounted = IniFile.parse(path)
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.strip_edges()
		if not line.begins_with("["):
			continue
		var title := line.substr(1, line.length() - 2)
		var texts: Array[String] = []
		for i in 5:
			texts.append(str(ini.get_value(title, "text%d" % (i + 1), "")))
		var align_x := 0
		match str(ini.get_value(title, "align x", "")).to_lower():
			"left":
				align_x = -1
			"right":
				align_x = 1
		var align_y := 0
		match str(ini.get_value(title, "align y", "")).to_lower():
			"top", "up":
				align_y = -1
			"bottom", "down":
				align_y = 1
		var amount := 0
		for text in texts:
			if text != "":
				amount += 1
		_screens.append({"title": title, "image": str(ini.get_value(title, "image path", "")), "texts": texts, "amount": amount,
			"no_back": str(ini.get_value(title, "disablebackground", "0")).to_lower() in ["1", "true"], "align": Vector2i(align_x, align_y)})

static func available() -> bool:
	_load_screens()
	return not _screens.is_empty()

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	add_child(_view)

# DrawLoading(percent, shortloading)
func show_percent(value: int, short := false) -> void:
	_short = short
	if value == 0 or _screen.is_empty():
		_text_index = 0
		_load_screens()
		if not _screens.is_empty():
			_screen = _screens[randi_range(0, _screens.size() - 1)].duplicate(true)
		if _screen.get("title", "") == "CWM":
			_screen.texts[0] = _cwm_line()
			if not short and value == 0:
				Sfx.play_global(self, "SFX/SCP/990/cwm1.cwm")
	percent = value
	var amount: int = _screen.get("amount", 0)
	if not short and amount > 0 and percent > (100.0 / amount) * (_text_index + 1):
		_text_index += 1
	if percent == 100:
		if _screen.get("title", "") != "CWM":
			Sfx.play_global(self, "SFX/Horror/Horror8.ogg")
		elif not short:
			Sfx.play_global(self, "SFX/SCP/990/cwm2.cwm")
		waiting = true
	_view.queue_redraw()

func _cwm_line() -> String:
	if randi_range(1, 5) == 1:
		if randi_range(1, 2) == 1:
			var date := Time.get_date_dict_from_system()
			var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
			return "It will happen on %02d %s %d." % [date.day, months[date.month - 1], date.year]
		return Time.get_time_string_from_system()
	return CWM_LINES[randi_range(1, 13) - 1]

static func _blitz_char(code: int) -> String:
	if code >= 130 and code < 160:
		return CP1252[code - 130]
	return char(code)

func _process(_delta: float) -> void:
	if _screen.get("title", "") == "CWM":
		_view.queue_redraw()

func _input(event: InputEvent) -> void:
	if not waiting:
		get_viewport().set_input_as_handled()
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	get_viewport().set_input_as_handled()
	if pressed:
		waiting = false
		closed.emit()
		queue_free()

func _draw_view() -> void:
	var view := _view.size
	var s := UIKit.menu_scale(_view)
	_view.draw_rect(Rect2(Vector2.ZERO, view), Color.BLACK)
	if _screen.is_empty():
		_draw_bar(view, s)
		return
	if not _screen.no_back:
		var back := UIKit.texture("Loadingscreens/loadingback.jpg")
		if back != null:
			_view.draw_texture(back, ((view - back.get_size()) * 0.5).floor())
	var image := UIKit.texture("Loadingscreens/" + str(_screen.image))
	if image != null:
		var align: Vector2i = _screen.align
		var at := Vector2.ZERO
		at.x = floorf(view.x * 0.5 - image.get_width() * 0.5) if align.x == 0 else (view.x - image.get_width() if align.x == 1 else 0.0)
		at.y = floorf(view.y * 0.5 - image.get_height() * 0.5) if align.y == 0 else (view.y - image.get_height() if align.y == 1 else 0.0)
		_view.draw_texture(image, at)
	_draw_bar(view, s)
	var centre := (view * 0.5).floor()
	var text_box := Vector2(centre.x - 200.0, centre.y + 120.0)
	if _screen.title == "CWM":
		var title := ""
		for _i in randi_range(2, 9) + 1:
			title += char(randi_range(48, 122))
		UIKit.draw_text(_view, Vector2(centre.x, centre.y + 80.0), title, Color.WHITE, "bold", s, true, true)
		# For i = 0 To Rand(10, 15): only the last Replace survives, every copy of one letter swapped for a high character
		var line: String = _screen.texts[0]
		if line.length() > 1:
			var letter := line[randi_range(1, line.length() - 1) - 1]
			line = line.replace(letter, _blitz_char(randi_range(130, 250)))
		UIKit.draw_row_text(_view, text_box, line, 400.0, 300.0, Color.WHITE, s, true)
	else:
		var text: String = _screen.texts[clampi(_text_index, 0, 4)]
		UIKit.draw_text(_view, Vector2(centre.x + 1.0, centre.y + 81.0), _screen.title, Color.BLACK, "bold", s, true, true)
		UIKit.draw_row_text(_view, text_box + Vector2.ONE, text, 400.0, 300.0, Color.BLACK, s, true)
		UIKit.draw_text(_view, Vector2(centre.x, centre.y + 80.0), _screen.title, Color.WHITE, "bold", s, true, true)
		UIKit.draw_row_text(_view, text_box, text, 400.0, 300.0, Color.WHITE, s, true)
	var loading := "LOADING - %d %%" % percent
	UIKit.draw_text(_view, Vector2(centre.x + 1.0, centre.y - 99.0), loading, Color.BLACK, "regular", s, true, true)
	UIKit.draw_text(_view, Vector2(centre.x, centre.y - 100.0), loading, Color.WHITE, "regular", s, true, true)
	if percent == 100:
		UIKit.draw_text(_view, Vector2(centre.x, view.y - 50.0), "PRESS ANY KEY TO CONTINUE", Color.WHITE, "regular", s, true, true)

# Rect(x, y, width + 4, height, False) and Int((width - 2) * percent / 100 / 10) segments of BlinkMeterIMG
func _draw_bar(view: Vector2, _s: float) -> void:
	var width := 300.0
	var at := Vector2(floorf(view.x / 2.0 - width / 2.0), floorf(view.y / 2.0 + 30.0 - 100.0))
	_view.draw_rect(Rect2(at + Vector2(0.5, 0.5), Vector2(width + 4.0, 20.0) - Vector2.ONE), Color.WHITE, false, 1.0)
	var segment := UIKit.texture("GFX/blinkmeter.jpg")
	for i in int((width - 2.0) * (percent / 100.0) / 10.0):
		var cell := at + Vector2(3.0 + 10.0 * i, 3.0)
		if segment != null:
			_view.draw_texture(segment, cell)
		else:
			_view.draw_rect(Rect2(cell, Vector2(8, 14)), Color.WHITE)
