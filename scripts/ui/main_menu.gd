extends Control
# Menu.bb UpdateMainMenu: the back picture with SCP-173 blinking in the corner, a flickering line of text, the
# title strip at the bottom, the version in the corner and four framed buttons on the left. The other tabs
# (MainMenuTab) frame their title where the buttons were, with BACK beside it: 1 NEW GAME, 2 LOAD GAME,
# 3/5/6/7 OPTIONS (options_panel.gd), 4 LOAD MAP. The menu track (Music(11)) plays while the menu is open.

signal new_game_pressed
signal load_game_pressed


# Select Rand(0, 22); case 1 has no line and leaves the last one
const FLICKER_LINES := [
	"DON'T BLINK", "", "DON'T BLINK", "DON'T BLINK", "Secure. Contain. Protect.", "Secure. Contain. Protect.",
	"You want happy endings? Fuck you.", "You want happy endings? Fuck you.", "You want happy endings? Fuck you.",
	"Sometimes we would have had time to scream.", "Sometimes we would have had time to scream.",
	"Sometimes we would have had time to scream.", "NIL", "NO", "black white black white black white gray",
	"Stone does not care", "9341", "It controls the doors", "e8m106]af173o+079m895w914", "NIL",
	"It has taken over everything", "The spiral is growing",
	"\"Some kind of gestalt effect due to massive reality damage.\"",
]
const SEED_WORDS := ["NIL", "NO", "d9341", "5CP_I73", "DONTBLINK", "CRUNCH", "die", "HTAED", "rustledjim", "larry", "JORGE", "dirtymetal", "whatpumpkin"]
# Difficulty.bb: name, colour, description
const DIFFICULTIES := [
	["Safe", Color8(120, 150, 50), "The game can be saved any time. However, as in the case of SCP Objects, a Safe classification does not mean that handling it does not pose a threat."],
	["Euclid", Color8(200, 200, 0), "In Euclid difficulty, saving is only allowed at specific locations marked by lit up computer screens. Euclid-class objects are inherently unpredictable, so that reliable containment is not always possible."],
	["Keter", Color8(200, 0, 0), "Keter-class objects are considered the most dangerous ones in Foundation containment. The same can be said for this difficulty level: the SCPs are more aggressive, and you have only one life - when you die, the game is over. "],
	["Custom", Color8(255, 255, 255), ""],
]
const MENU_TRACK := "Menu"

var tab := 0
var seed_text := ""
var difficulty := 0          # SelectedDifficulty starts at SAFE
var save_name := ""
var delete_asked := false    # SaveMSG
var delete_slot := ""
var load_page := 0           # CurrLoadGamePage
var saves: Array[Dictionary] = []

const SAVES_PER_PAGE := 6

func page_count() -> int:
	return maxi(ceili(saves.size() / float(SAVES_PER_PAGE)), 1)
var after_ending := false    # ShouldPlay 21: MenuBreath once, then the menu track

var _back: TextureRect
var _blink_173: TextureRect
var _title: TextureRect
var _canvas: Control
var _options: Control
var _panel_nodes: Array[Node] = []
var _blink_timer := 1
var _blink_duration := 0
var _flicker_timer := 1.0
var _flicker_duration := 0.0
var _flicker_text := ""
var _flicker_pos := Vector2.ZERO
var _flicker_jitter := Vector2.ZERO
var _music: AudioStreamPlayer
var _music_now := ""
var _music_fade := 0.0
var _breath: AudioStreamPlayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	_back = _picture("GFX/menu/back.jpg")
	_back.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_back)
	_blink_173 = _picture("GFX/menu/173back.png")
	add_child(_blink_173)
	_title = _picture("GFX/menu/scptext.jpg")
	add_child(_title)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	_music = AudioStreamPlayer.new()
	_music.set_meta("music", true)
	add_child(_music)
	if not ContentPaths.assets_found:
		var warning := Label.new()
		warning.text = "The original game files were not found.\nPut the 'assets' folder next to the game (tools/fetch_assets.py fetches it)."
		warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		warning.position = Vector2(160.0, 100.0)
		warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(warning)
	resized.connect(_rebuild)
	_rebuild()

func _picture(relative: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = UIKit.texture(relative)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# Rand(n) is Rand(1, n); Rand(0) gives 0 or 1.
static func _rand(n: int) -> int:
	return randi_range(mini(1, n), maxi(1, n))

func _process(delta: float) -> void:
	var fps := delta * 70.0
	_update_music(fps)
	if not is_visible_in_tree():
		return
	_blink_173.visible = Time.get_ticks_msec() % _blink_timer >= _rand(_blink_duration)
	if randi_range(1, 300) == 1:
		_blink_timer = randi_range(4000, 8000)
		_blink_duration = randi_range(200, 500)
	_flicker_timer -= fps
	if _flicker_timer < _flicker_duration:
		_flicker_jitter = Vector2(randi_range(-5, 5), randi_range(-5, 5))
		if _flicker_timer < 0.0:
			_flicker_timer = randi_range(700, 800)
			_flicker_duration = randi_range(10, 35)
			var s := UIKit.menu_scale(self)
			_flicker_pos = Vector2(int(randi_range(700, 1000) * s), int(randi_range(100, 600) * s))
			var line: String = FLICKER_LINES[randi_range(0, 22)]
			if line != "":
				_flicker_text = line
	_canvas.queue_redraw()

# UpdateMusic with ShouldPlay = 11 while the menu is open: a wrong clip fades out by FPSfactor / 250, the right
# one fades towards MusicVolume by 0.1 * FPSfactor. Once the game runs the menu track fades out the same way.
func _update_music(fps: float) -> void:
	var wanted := MENU_TRACK if is_visible_in_tree() and (_breath == null or not _breath.playing) else ""
	if _music_now != wanted:
		_music_fade = maxf(_music_fade - fps / 250.0, 0.0)
		if _music_fade == 0.0 or not _music.playing:
			_music.stop()
			_music_now = wanted
			_music_fade = 0.0
			if wanted != "":
				var path := ContentPaths.existing_file("SFX/Music/%s.ogg" % wanted)
				if FileAccess.file_exists(path):
					var stream := AudioStreamOggVorbis.load_from_file(path)
					stream.loop = true
					_music.stream = stream
					_music.play()
	else:
		_music_fade += (GameState.music_volume - _music_fade) * minf(0.1 * fps, 1.0)
	_music.volume_db = linear_to_db(maxf(_music_fade, 0.0001))

# Main.bb starts Music(2) (EntranceZone) at full volume before the menu opens; ShouldPlay = 11 then fades it out.
func start_boot_music() -> void:
	var path := ContentPaths.existing_file("SFX/Music/EntranceZone.ogg")
	if not FileAccess.file_exists(path):
		return
	_music.stream = AudioStreamOggVorbis.load_from_file(path)
	_music_now = "EntranceZone"
	_music_fade = 1.0
	_music.volume_db = 0.0
	_music.play()

# The ending's way back: MenuBreath.ogg plays to its end before the menu track starts.
func play_end_breath() -> void:
	_breath = Sfx.play_global(self, "SFX/Ending/MenuBreath.ogg")

func _rebuild() -> void:
	if _back == null:
		return
	var s := UIKit.menu_scale(self)
	var view := size
	var back_texture := UIKit.texture("GFX/menu/back.jpg")
	_back.position = Vector2.ZERO
	_back.size = back_texture.get_size() * s if back_texture != null else Vector2.ZERO
	var blink_texture := UIKit.texture("GFX/menu/173back.png")
	_blink_173.size = (blink_texture.get_size() if blink_texture != null else Vector2(312, 441)) * s
	_blink_173.position = view - _blink_173.size
	var title_texture := UIKit.texture("GFX/menu/scptext.jpg")
	_title.size = title_texture.get_size() * s if title_texture != null else Vector2.ZERO
	_title.position = Vector2((view.x - _title.size.x) * 0.5, view.y - 20.0 * s - _title.size.y)
	for node in _panel_nodes:
		node.queue_free()
	_panel_nodes.clear()
	_options = null
	if tab == 0:
		var labels := ["NEW GAME", "LOAD GAME", "OPTIONS", "QUIT"]
		for i in 4:
			var button := _button(labels[i], Rect2(159.0 * s, (286.0 + 100.0 * i) * s, 400.0 * s, 70.0 * s), true)
			button.locked = i == 0 and not ContentPaths.assets_found
			match i:
				0:
					button.pressed.connect(func() -> void: _open_new_game())
				1:
					button.pressed.connect(func() -> void: _set_tab(2))
				2:
					button.pressed.connect(func() -> void: _set_tab(3))
				3:
					button.pressed.connect(func() -> void: get_tree().quit())
	else:
		var back := _button("BACK", Rect2((159.0 + 400.0 + 20.0) * s, 286.0 * s, (580.0 - 400.0 - 20.0) * s, 70.0 * s), false)
		back.pressed.connect(_back_pressed)
		match tab:
			1:
				_build_new_game(s)
			2:
				_build_load_game(s)
			4:
				_build_load_map(s)
			_:
				_options = OptionsPanel.new()
				_options.layout = OptionsPanel.Layout.MENU
				_options.anchor = Vector2(160.0, 376.0) * s
				_options.tab = [0, 0, 0, 0, 0, 1, 2, 3][tab]
				add_child(_options)
				_panel_nodes.append(_options)
				_options.rebuild()
	_canvas.queue_redraw()

func _back_pressed() -> void:
	match tab:
		1:
			GameState.save_settings()
			_set_tab(0)
		4:
			_set_tab(1)
		_:
			if tab >= 3:
				GameState.save_settings()
			delete_asked = false
			load_page = 0
			_set_tab(0)

func _button(text: String, rect: Rect2, big: bool) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.big = big
	button.position = rect.position
	button.size = rect.size
	add_child(button)
	_panel_nodes.append(button)
	return button

func _tick(at: Vector2, s: float, on: bool, locked := false) -> UITick:
	var tick := UITick.new()
	tick.position = at
	tick.size = Vector2(20.0, 20.0) * s
	tick.on = on
	tick.locked = locked
	add_child(tick)
	_panel_nodes.append(tick)
	return tick

func _input_box(rect: Rect2, text: String) -> UIInputBox:
	var box := UIInputBox.new()
	box.position = rect.position
	box.size = rect.size
	box.text = text
	add_child(box)
	_panel_nodes.append(box)
	return box

func _set_tab(value: int) -> void:
	tab = value
	_rebuild()

# NEW GAME rolls a new seed every time: one of the words (1 in 15), else 4-8 characters, a digit 1 in 3.
func _open_new_game() -> void:
	seed_text = ""
	if randi_range(1, 15) == 1:
		seed_text = SEED_WORDS[randi_range(1, 13) - 1]
	else:
		for _i in randi_range(4, 8):
			seed_text += str(randi_range(0, 9)) if randi_range(1, 3) == 1 else char(randi_range(97, 122))
	_set_tab(1)

func _build_new_game(s: float) -> void:
	var x := 160.0 * s
	var y := 376.0 * s
	var name_box := _input_box(Rect2(x + 150.0 * s, y + 15.0 * s, 200.0 * s, 30.0 * s), save_name)
	name_box.text_changed.connect(func(text: String) -> void:
		for bad in [":", ".", "/", "\\", "<", ">", "|", "?", "\"", "*"]:
			text = text.replace(bad, "")
		save_name = text.left(15)
		name_box.text = save_name)
	var seed_box := _input_box(Rect2(x + 150.0 * s, y + 55.0 * s, 200.0 * s, 30.0 * s), seed_text)
	seed_box.text_changed.connect(func(text: String) -> void: seed_text = text.left(15))
	var intro := _tick(Vector2(x + 280.0 * s, y + 110.0 * s), s, GameState.intro_enabled)
	intro.toggled.connect(func(value: bool) -> void: GameState.intro_enabled = value)
	for i in 4:
		var tick := _tick(Vector2(x + 20.0 * s, y + (180.0 + 30.0 * i) * s), s, difficulty == i)
		var index := i
		tick.toggled.connect(func(on: bool) -> void:
			if on:
				difficulty = index
			_rebuild())
	if difficulty == GameState.CUSTOM:
		var perma := _tick(Vector2(x + 160.0 * s, y + 165.0 * s), s, GameState.custom_perma_death)
		perma.toggled.connect(func(on: bool) -> void: GameState.custom_perma_death = on; _rebuild())
		var anywhere := _tick(Vector2(x + 160.0 * s, y + 195.0 * s), s, GameState.custom_save_anywhere and not GameState.custom_perma_death, GameState.custom_perma_death)
		anywhere.toggled.connect(func(on: bool) -> void: GameState.custom_save_anywhere = on)
		var aggressive := _tick(Vector2(x + 160.0 * s, y + 225.0 * s), s, GameState.custom_aggressive_npcs)
		aggressive.toggled.connect(func(on: bool) -> void: GameState.custom_aggressive_npcs = on)
		var arrow := _arrow(Vector2(x + 155.0 * s, y + 251.0 * s))
		arrow.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameState.custom_other_factors = (GameState.custom_other_factors + 1) % 3
				UIKit.play_button_sound(self)
				_canvas.queue_redraw())
	var load_map := _button("Load map", Rect2(x, y + 350.0 * s, 160.0 * s, 70.0 * s), false)
	load_map.pressed.connect(func() -> void: _set_tab(4))
	var start := _button("START", Rect2(x + 420.0 * s, y + 350.0 * s, 160.0 * s, 70.0 * s), false)
	start.pressed.connect(func() -> void: _start())

# ArrowIMG(1): arrow.png turned 90 degrees, unscaled
func _arrow(at: Vector2) -> Control:
	var texture := UIKit.texture("GFX/menu/arrow.png")
	var arrow := Control.new()
	arrow.position = at
	arrow.size = Vector2(texture.get_height(), texture.get_width()) if texture != null else Vector2(16, 16)
	arrow.draw.connect(func() -> void:
		if texture != null:
			arrow.draw_set_transform(Vector2(texture.get_height(), 0.0), PI * 0.5)
			arrow.draw_texture(texture, Vector2.ZERO)
			arrow.draw_set_transform(Vector2.ZERO))
	add_child(arrow)
	_panel_nodes.append(arrow)
	return arrow

func _start() -> void:
	GameState.save_name = SaveGame.unique_name(save_name if save_name != "" else "untitled")
	SaveGame.current_slot = GameState.save_name
	GameState.requested_seed = BlitzRng.seed_number(seed_text) if not seed_text.is_empty() else -1
	GameState.difficulty = difficulty
	GameState.save_settings()
	new_game_pressed.emit()

func _build_load_game(s: float) -> void:
	var x := 160.0 * s
	var y := 376.0 * s
	saves = SaveGame.list()
	load_page = clampi(load_page, 0, page_count() - 1)
	if not delete_asked:
		if load_page < page_count() - 1:
			_button(">", Rect2(x + 530.0 * s, y + 510.0 * s, 50.0 * s, 55.0 * s), true).pressed.connect(func() -> void: load_page += 1; _rebuild())
		if load_page > 0:
			_button("<", Rect2(x, y + 510.0 * s, 50.0 * s, 55.0 * s), true).pressed.connect(func() -> void: load_page -= 1; _rebuild())
	var first := load_page * SAVES_PER_PAGE
	for row in mini(SAVES_PER_PAGE, saves.size() - first):
		var entry := saves[first + row]
		var row_y := y + (20.0 + 80.0 * row) * s
		if delete_asked:
			continue
		if entry.compatible:
			var load_button := _button("Load", Rect2(x + 300.0 * s, row_y + 20.0 * s, 100.0 * s, 30.0 * s), false)
			load_button.pressed.connect(func() -> void:
				SaveGame.current_slot = entry.slot
				load_game_pressed.emit())
		var delete_button := _button("Delete", Rect2(x + 420.0 * s, row_y + 20.0 * s, 100.0 * s, 30.0 * s), false)
		delete_button.pressed.connect(func() -> void:
			delete_asked = true
			delete_slot = entry.slot
			_rebuild())
	if delete_asked:
		var yes := _button("Yes", Rect2(790.0 * s, 526.0 * s, 100.0 * s, 30.0 * s), false)
		yes.pressed.connect(func() -> void:
			SaveGame.delete(delete_slot)
			delete_asked = false
			_rebuild())
		var no := _button("No", Rect2(990.0 * s, 526.0 * s, 100.0 * s, 30.0 * s), false)
		no.pressed.connect(func() -> void: delete_asked = false; _rebuild())

func _build_load_map(_s: float) -> void:
	pass

# CurrentTime() "HH:MM:SS" and CurrentDate() "DD Mon YYYY" of the save
static func _save_stamp(saved_at: String) -> PackedStringArray:
	var parts := saved_at.split("T")
	if parts.size() != 2:
		return PackedStringArray(["", ""])
	var date := parts[0].split("-")
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	if date.size() != 3:
		return PackedStringArray([parts[1], ""])
	return PackedStringArray([parts[1], "%s %s %s" % [date[2], months[clampi(int(date[1]) - 1, 0, 11)], date[0]]])

func _draw_canvas() -> void:
	var s := UIKit.menu_scale(self)
	var view := size
	var white := UIKit.texture("GFX/menu/menuwhite.jpg")
	if view.x > 1240.0 * s and white != null:
		# DrawTiledImageRect(MenuWhite, 0, 5, 512, 7 * MenuScale, ...): the line of the back picture carried on to the right edge
		var strip := Rect2(985.0 * s, 407.0 * s, view.x - 1240.0 * s + 300.0, 7.0 * s)
		var x := strip.position.x
		while x < strip.end.x:
			var w := minf(512.0, strip.end.x - x)
			_canvas.draw_texture_rect_region(white, Rect2(x, strip.position.y, w, strip.size.y), Rect2(0.0, 5.0, w, strip.size.y))
			x += w
	if _flicker_timer < _flicker_duration and _flicker_text != "":
		UIKit.draw_text(_canvas, _flicker_pos + _flicker_jitter, _flicker_text, Color8(50, 50, 50), "regular", s, true)
	if tab != 0:
		var frame := Rect2(159.0 * s, 286.0 * s, 400.0 * s, 70.0 * s)
		UIKit.draw_frame(_canvas, frame, s)
		var titles := {1: "NEW GAME", 2: "LOAD GAME", 4: "LOAD MAP"}
		UIKit.draw_text(_canvas, frame.get_center(), titles.get(tab, "OPTIONS"), Color.WHITE, "bold", s, true, true)
	match tab:
		1:
			_draw_new_game(s)
		2:
			_draw_list(s, "No saved games.")
		4:
			_draw_list(s, "No saved maps. Use the Map Creator to create new maps.")
	UIKit.draw_text(_canvas, Vector2(20.0, view.y - 30.0), "v" + GameVersion.full(), Color.WHITE, "console", s)

func _draw_new_game(s: float) -> void:
	var x := 160.0 * s
	var y := 376.0 * s
	UIKit.draw_frame(_canvas, Rect2(x, y, 580.0 * s, 330.0 * s), s)
	UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, y + 20.0 * s), "Name:", Color.WHITE, "regular", s)
	UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, y + 60.0 * s), "Map seed:", Color.WHITE, "regular", s)
	UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, y + 110.0 * s), "Enable intro sequence:", Color.WHITE, "regular", s)
	UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, y + 150.0 * s), "Difficulty:", Color.WHITE, "regular", s)
	for i in 4:
		UIKit.draw_text(_canvas, Vector2(x + 60.0 * s, y + (180.0 + 30.0 * i) * s), DIFFICULTIES[i][0], DIFFICULTIES[i][1], "regular", s)
	UIKit.draw_frame(_canvas, Rect2(x + 150.0 * s, y + 155.0 * s, 410.0 * s, 150.0 * s), s)
	if difficulty == GameState.CUSTOM:
		UIKit.draw_text(_canvas, Vector2(x + 200.0 * s, y + 165.0 * s), "Permadeath", Color.WHITE, "regular", s)
		UIKit.draw_text(_canvas, Vector2(x + 200.0 * s, y + 195.0 * s), "Save anywhere", Color.WHITE, "regular", s)
		UIKit.draw_text(_canvas, Vector2(x + 200.0 * s, y + 225.0 * s), "Aggressive NPCs", Color.WHITE, "regular", s)
		var factor: String = ["Easy", "Normal", "Hard"][clampi(GameState.custom_other_factors, 0, 2)]
		UIKit.draw_text(_canvas, Vector2(x + 200.0 * s, y + 255.0 * s), "Other difficulty factors: " + factor, Color.WHITE, "regular", s)
	else:
		UIKit.draw_row_text(_canvas, Vector2(x + 160.0 * s, y + 160.0 * s), DIFFICULTIES[difficulty][2], (410.0 - 20.0) * s, 200.0, Color.WHITE, s)

# The LOAD GAME / LOAD MAP list: a frame 510 high, a page bar under it (both arrows greyed unless there is a page to go to),
# and a framed row per save with its name, time, date and version.
func _draw_list(s: float, empty_text: String) -> void:
	var x := 160.0 * s
	var y := 376.0 * s
	var width := 580.0 * s
	UIKit.draw_frame(_canvas, Rect2(159.0 * s, y, width, 510.0 * s), s)
	var grey := Color8(100, 100, 100)
	UIKit.draw_frame(_canvas, Rect2(x + 530.0 * s, y + 510.0 * s, 50.0 * s, 55.0 * s), s)
	UIKit.draw_text(_canvas, Vector2(x + 555.0 * s, y + 537.5 * s), ">", grey, "bold", s, true, true)
	UIKit.draw_frame(_canvas, Rect2(x, y + 510.0 * s, 50.0 * s, 55.0 * s), s)
	UIKit.draw_text(_canvas, Vector2(x + 25.0 * s, y + 537.5 * s), "<", grey, "bold", s, true, true)
	UIKit.draw_frame(_canvas, Rect2(x + 50.0 * s, y + 510.0 * s, width - 100.0 * s, 55.0 * s), s)
	var shown := saves if tab == 2 else []
	UIKit.draw_text(_canvas, Vector2(x + width * 0.5, y + 536.0 * s), "Page %d/%d" % [load_page + 1, page_count()], grey if tab == 4 else Color.WHITE, "bold", s, true, true)
	if shown.is_empty():
		UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, y + 20.0 * s), empty_text, Color.WHITE, "regular", s)
		return
	x += 20.0 * s
	y += 20.0 * s
	var first := load_page * SAVES_PER_PAGE
	for row in mini(SAVES_PER_PAGE, shown.size() - first):
		var entry: Dictionary = shown[first + row]
		var row_y := y + 80.0 * row * s
		var ink := Color.WHITE if entry.compatible else Color8(255, 0, 0)
		UIKit.draw_frame(_canvas, Rect2(x, row_y, 540.0 * s, 70.0 * s), s)
		var stamp := _save_stamp(str(entry.saved_at))
		UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, row_y + 10.0 * s), str(entry.name), ink, "regular", s)
		UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, row_y + 28.0 * s), stamp[0], ink, "regular", s)
		UIKit.draw_text(_canvas, Vector2(x + 120.0 * s, row_y + 28.0 * s), stamp[1], ink, "regular", s)
		UIKit.draw_text(_canvas, Vector2(x + 20.0 * s, row_y + 46.0 * s), GameVersion.full() if entry.compatible else str(entry.version), ink, "regular", s)
		if delete_asked:
			UIKit.draw_frame(_canvas, Rect2(x + 280.0 * s, row_y + 20.0 * s, 100.0 * s, 30.0 * s), s)
			UIKit.draw_text(_canvas, Vector2(x + 330.0 * s, row_y + 34.0 * s), "Load", grey if entry.compatible else Color8(255, 0, 0), "regular", s, true, true)
			UIKit.draw_frame(_canvas, Rect2(x + 400.0 * s, row_y + 20.0 * s, 100.0 * s, 30.0 * s), s)
			UIKit.draw_text(_canvas, Vector2(x + 450.0 * s, row_y + 34.0 * s), "Delete", grey, "regular", s, true, true)
		elif not entry.compatible:
			UIKit.draw_frame(_canvas, Rect2(x + 280.0 * s, row_y + 20.0 * s, 100.0 * s, 30.0 * s), s)
			UIKit.draw_text(_canvas, Vector2(x + 330.0 * s, row_y + 34.0 * s), "Load", Color8(255, 0, 0), "regular", s, true, true)
	if delete_asked:
		var dialog := Rect2(740.0 * s, 376.0 * s, 420.0 * s, 200.0 * s)
		UIKit.draw_frame(_canvas, dialog, s)
		UIKit.draw_row_text(_canvas, dialog.position + Vector2(20.0, 15.0) * s, "Are you sure you want to delete this save?", 400.0 * s, 200.0 * s, Color.WHITE, s)
