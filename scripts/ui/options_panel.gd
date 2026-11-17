extends Control
class_name OptionsPanel
# The OPTIONS tabs: GRAPHICS, AUDIO, CONTROLS and ADVANCED. Two layouts of the same rows: the main menu's
# (Menu.bb UpdateMainMenu, MainMenuTab 3/5/6/7: a framed tab bar and a framed panel, widgets at x + 310) and the
# pause menu's (Main.bb DrawMenu, OptionsMenu 1-4: on the pause picture, widgets at x + 270, the options that
# "cannot be changed in-game" greyed out and locked). Hovering a widget shows DrawOptionsTooltip to the right.

const UISlider = preload("res://scripts/ui/ui_slider.gd")
const UIStepSlider = preload("res://scripts/ui/ui_step_slider.gd")

enum Layout { MENU, PAUSE }

var layout := Layout.MENU
var tab := 0
# MENU: the top left of the tab bar (160, 376); PAUSE: the pause picture's x + 132, y + 122.
var anchor := Vector2.ZERO
var tooltip_at := Vector2.ZERO
var user_track_check := 0
var user_track_loaded := 0

var _nodes: Array[Node] = []
var _texts: Array = []         # [position, text, colour, font]
var _frames: Array[Rect2] = []
var _tips: Array = []          # {rect, tip, value (Callable), extra, held (Callable)}
var _tip_layer: Control
var _shown_tip := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func rebuild() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	_texts.clear()
	_frames.clear()
	_tips.clear()
	_shown_tip = -1
	if layout != Layout.MENU:
		user_track_check = 0
	var s := UIKit.menu_scale(self)
	var names := ["GRAPHICS", "AUDIO", "CONTROLS", "ADVANCED"]
	var y: float
	var x: float
	if layout == Layout.MENU:
		x = anchor.x
		_frames.append(Rect2(anchor, Vector2(580.0, 60.0) * s))
		for i in 4:
			var tab_button := _button(names[i], Rect2(x + (20.0 + 140.0 * i) * s, anchor.y + 15.0 * s, 580.0 * s / 5.0, 30.0 * s), false)
			var index := i
			tab_button.pressed.connect(func() -> void: _set_tab(index))
		y = anchor.y + 70.0 * s
		tooltip_at = Vector2(x + 580.0 * s, y)
		_frames.append(Rect2(x, y, 580.0 * s, [330.0, 220.0, 270.0, 320.0][tab] * s))
		y += 20.0 * s
	else:
		x = anchor.x
		for i in 4:
			var tab_button := _button(names[i], Rect2(x + (-5.0 + 110.0 * i) * s, anchor.y, 100.0 * s, 30.0 * s), false)
			var index := i
			tab_button.pressed.connect(func() -> void: _set_tab(index))
		y = anchor.y + 50.0 * s
		var picture := UIKit.texture("GFX/menu/pausemenu.jpg")
		var picture_width := picture.get_width() * s if picture != null else 500.0 * s
		tooltip_at = Vector2(size.x * 0.5 + picture_width * 0.5, anchor.y)
	match tab:
		0:
			_graphics(x, y, s)
		1:
			_audio(x, y, s)
		2:
			_controls(x, y, s)
		3:
			_advanced(x, y, s)
	if _tip_layer == null:
		_tip_layer = Control.new()
		_tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tip_layer.z_index = 10
		_tip_layer.draw.connect(_draw_tooltip)
		add_child(_tip_layer)
	move_child(_tip_layer, -1)
	queue_redraw()
	_tip_layer.queue_redraw()

func _set_tab(value: int) -> void:
	tab = value
	rebuild()

func _menu() -> bool:
	return layout == Layout.MENU

func _label_x(x: float, s: float) -> float:
	return x + 20.0 * s if _menu() else x

func _widget_x(x: float, s: float) -> float:
	return x + (310.0 if _menu() else 270.0) * s

func _slider_width(s: float) -> float:
	return (150.0 if _menu() else 100.0) * s

func _graphics(x: float, y: float, s: float) -> void:
	var lx := _label_x(x, s)
	var wx := _widget_x(x, s)
	_tick_row("VSync:", lx, wx, y, s, "vsync", "vsync")
	y += 30.0 * s
	_tick_row("Anti-aliasing:", lx, wx, y, s, "anti_alias", "antialias")
	y += 30.0 * s
	_tick_row("Enable room lights:", lx, wx, y, s, "room_lights", "roomlights")
	y += 30.0 * s
	_slide_row("Screen gamma", lx, Vector2(wx, y + 6.0 * s), s, GameState.screen_gamma / 2.0,
		func(v: float) -> void: GameState.screen_gamma = v * 2.0, "gamma", func() -> float: return GameState.screen_gamma)
	y += 50.0 * s
	_step_row("Particle amount:", lx, Vector2(wx, y + 6.0 * s), s, ["MINIMAL", "REDUCED", "FULL"], "particle_amount", "particleamount", 0.0)
	y += 50.0 * s
	_step_row("Texture LOD Bias:", lx, Vector2(wx, y + 6.0 * s), s, ["0.8", "0.4", "0.0", "-0.4", "-0.8"], "texture_details", "texquality", 100.0 * s)

func _audio(x: float, y: float, s: float) -> void:
	var lx := _label_x(x, s)
	var wx := _widget_x(x, s)
	var in_game := not _menu()
	var slider_x := wx if _menu() else x + 250.0 * s
	_slide_row("Music volume:", lx, Vector2(slider_x, y - 4.0 * s), s, GameState.music_volume,
		func(v: float) -> void: GameState.music_volume = v, "musicvol", func() -> float: return GameState.music_volume)
	y += (40.0 if _menu() else 30.0) * s
	_slide_row("Sound volume:", lx, Vector2(slider_x, y - 4.0 * s), s, GameState.sound_volume,
		func(v: float) -> void: GameState.sound_volume = v, "soundvol", func() -> float: return GameState.sound_volume)
	y += 30.0 * s
	_tick_row("Enable user tracks:", lx, wx, y, s, "enable_user_tracks", "usertrack", in_game, 0.0, true)
	if not GameState.enable_user_tracks:
		user_track_check = 0
		return
	y += 30.0 * s
	_tick_row("User track mode:", lx, wx, y, s, "user_track_mode", "usertrackmode", false, 0.0, true)
	var mode := "Repeat" if GameState.user_track_mode != 0 else "Random"
	if _menu():
		_text(Vector2(x + 350.0 * s, y + s), mode)
		var scan := _button("Scan for User Tracks", Rect2(x + 20.0 * s, y + 30.0 * s, 190.0 * s, 25.0 * s), false)
		scan.pressed.connect(func() -> void: _scan_user_tracks(); rebuild())
		_tips.append({"rect": Rect2(scan.position, scan.size), "tip": "usertrackscan"})
		if user_track_check > 0:
			_text(Vector2(x + 20.0 * s, y + 100.0 * s), "User tracks found (%d/%d successfully loaded)" % [user_track_loaded, user_track_check])
	else:
		_text(Vector2(x, y + 20.0 * s), mode)

func _scan_user_tracks() -> void:
	user_track_check = 0
	user_track_loaded = 0
	var folder := ContentPaths.existing_file("SFX/Radio/UserTracks")
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file_name in DirAccess.get_files_at(folder):
		user_track_check += 1
		var path := folder.path_join(file_name)
		var loaded: Resource = null
		match file_name.get_extension().to_lower():
			"ogg":
				loaded = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				loaded = AudioStreamMP3.load_from_file(path)
			"wav":
				loaded = AudioStreamWAV.load_from_file(path)
		if loaded != null:
			user_track_loaded += 1

func _controls(x: float, y: float, s: float) -> void:
	var lx := _label_x(x, s)
	var wx := _widget_x(x, s)
	_slide_row("Mouse sensitivity:", lx, Vector2(wx, y - 4.0 * s), s, GameState.mouse_sensitivity,
		func(v: float) -> void: GameState.mouse_sensitivity = v, "mousesensitivity", func() -> float: return GameState.mouse_sensitivity - 0.5)
	y += (40.0 if _menu() else 30.0) * s
	_tick_row("Invert mouse Y-axis:", lx, wx, y, s, "invert_mouse", "mouseinvert")
	y += 40.0 * s
	_slide_row("Mouse smoothing:", lx, Vector2(wx, y - 4.0 * s), s, GameState.mouse_smoothing / 2.0,
		func(v: float) -> void: GameState.mouse_smoothing = v * 2.0, "mousesmoothing", func() -> float: return GameState.mouse_smoothing)
	y += 30.0 * s
	_text(Vector2(lx, y), "Control configuration:")
	y += 10.0 * s
	var rows: Array
	if _menu():
		rows = [["Move Forward", "up", 0, 0], ["Strafe Left", "left", 0, 1], ["Move Backward", "down", 0, 2], ["Strafe Right", "right", 0, 3], ["Quick Save", "save", 0, 4],
			["Manual Blink", "blink", 1, 0], ["Sprint", "sprint", 1, 1], ["Open/Close Inventory", "inventory", 1, 2], ["Crouch", "crouch", 1, 3], ["Open/Close Console", "console", 1, 4]]
		_tips.append({"rect": Rect2(x + 20.0 * s, y, 580.0 * s - 40.0 * s, 120.0 * s), "tip": "controls"})
	else:
		rows = [["Move Forward", "up", 0, 0], ["Strafe Left", "left", 0, 1], ["Move Backward", "down", 0, 2], ["Strafe Right", "right", 0, 3], ["Manual Blink", "blink", 0, 4],
			["Sprint", "sprint", 0, 5], ["Open/Close Inventory", "inventory", 0, 6], ["Crouch", "crouch", 0, 7], ["Quick Save", "save", 0, 8], ["Open/Close Console", "console", 0, 9]]
		_tips.append({"rect": Rect2(x, y, 300.0 * s, 220.0 * s), "tip": "controls"})
	for row in rows:
		var row_y: float = y + (20.0 + 20.0 * row[3]) * s
		var label_x: float
		var box_x: float
		if _menu():
			label_x = x + (20.0 if row[2] == 0 else 280.0) * s
			box_x = x + (160.0 if row[2] == 0 else 470.0) * s
		else:
			label_x = x
			box_x = x + 200.0 * s
		_text(Vector2(label_x, row_y), row[0])
		var box := UIInputBox.new()
		box.key_box = true
		box.position = Vector2(box_x, row_y)
		box.size = Vector2(100.0, 20.0) * s
		box.text = KeyNames.name_of(int(GameState.binds[row[1]]))
		var bind_name: String = row[1]
		box.key_pressed.connect(func(event: InputEventKey) -> void:
			var scancode := KeyNames.scancode_of(event)
			if scancode != 0:
				GameState.binds[bind_name] = scancode
				GameState.save_settings()
			rebuild.call_deferred())
		_add(box)

func _advanced(x: float, y: float, s: float) -> void:
	var lx := _label_x(x, s)
	var wx := _widget_x(x, s)
	_tick_row("Show HUD:", lx, wx, y, s, "hud_enabled", "hud")
	y += 30.0 * s
	_tick_row("Enable console/debug:", lx, wx, y, s, "console_enabled", "consoleenable")
	y += 30.0 * s
	_tick_row("Open console on error:", lx, wx, y, s, "console_on_error", "consoleerror")
	y += 50.0 * s
	_tick_row("Achievement popups:", lx, wx, y, s, "achievement_popups", "achpopup", false, 0.0, false, _menu())
	y += 50.0 * s
	_tick_row("Show FPS:", lx, wx, y, s, "show_fps", "showfps", false, 0.0, false, _menu())
	y += 30.0 * s
	_text(Vector2(lx, y), "Framelimit:")
	var limit_tick := _tick(Vector2(wx, y), s, GameState.framelimit > 0, false)
	limit_tick.toggled.connect(func(on: bool) -> void:
		# turning it on: CurrFrameLimit = Max((Framelimit - 19) / 100, 0.01), so it starts at 20 FPS
		GameState.framelimit = 20 if on else 0
		GameState.save_settings()
		rebuild())
	_tips.append({"rect": Rect2(wx, y + s, 20.0 * s, 20.0 * s), "tip": "framelimit", "value": func() -> float: return float(GameState.framelimit)})
	if GameState.framelimit > 0:
		var current := maxf((GameState.framelimit - 19) / 100.0, 0.01)
		var slider := UISlider.new()
		slider.setup(Vector2(x + 150.0 * s, y + 30.0 * s), 100.0 * s, current * 99.0 / 100.0)
		slider.value_changed.connect(func(v: float) -> void:
			GameState.framelimit = 19 + roundi(maxf(v * 100.0 / 99.0, 0.01) * 100.0)
			GameState.save_settings()
			queue_redraw())
		_add(slider)
		_tips.append({"rect": Rect2(slider.position, slider.size), "tip": "framelimit", "value": func() -> float: return float(GameState.framelimit)})
		_texts.append([Vector2(x + (25.0 if _menu() else 5.0) * s, y + 25.0 * s), func() -> String: return "%d FPS" % GameState.framelimit, Color8(255, 255, 0)])
	y += 80.0 * s
	_tick_row("Antialiased text:", lx, wx, y, s, "aa_text", "antialiastext")

func _tick_row(label: String, lx: float, wx: float, y: float, s: float, property: String, tip: String, locked := false, extra := 0.0, rebuilds := false, tick_dy := true) -> void:
	_text(Vector2(lx, y), label, Color8(100, 100, 100) if locked else Color.WHITE)
	var at := Vector2(wx, y + (s if tick_dy else 0.0))
	var value: Variant = GameState.get(property)
	var tick := _tick(at, s, bool(value), locked)
	tick.toggled.connect(func(on: bool) -> void:
		GameState.set(property, (1 if on else 0) if value is int else on)
		GameState.save_settings()
		if rebuilds:
			rebuild())
	_tips.append({"rect": Rect2(wx, y + s, 20.0 * s, 20.0 * s), "tip": tip, "extra": extra})

func _tick(at: Vector2, s: float, on: bool, locked: bool) -> UITick:
	var tick := UITick.new()
	tick.position = at
	tick.size = Vector2(20.0, 20.0) * s
	tick.on = on
	tick.locked = locked
	_add(tick)
	return tick

func _slide_row(label: String, lx: float, at: Vector2, s: float, start: float, apply: Callable, tip: String, tip_value: Callable) -> void:
	var slider := UISlider.new()
	slider.setup(at, _slider_width(s), start)
	slider.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		GameState.save_settings()
		_tip_layer.queue_redraw())
	_add(slider)
	var label_y := at.y - (6.0 * s if tip == "gamma" else -4.0 * s)
	_text(Vector2(lx, label_y), label)
	_tips.append({"rect": Rect2(at, Vector2(_slider_width(s) + 14.0, 20.0)), "tip": tip, "value": tip_value})

func _step_row(label: String, lx: float, at: Vector2, s: float, names: Array, property: String, tip: String, extra: float) -> void:
	_text(Vector2(lx, at.y - 6.0 * s), label)
	var slider := UIStepSlider.new()
	slider.setup(at, _slider_width(s), names, int(GameState.get(property)))
	slider.value_changed.connect(func(v: int) -> void:
		GameState.set(property, v)
		GameState.save_settings()
		_tip_layer.queue_redraw())
	_add(slider)
	_tips.append({"rect": Rect2(at.x, at.y - 6.0 * s, _slider_width(s) + 14.0, 20.0), "tip": tip, "extra": extra,
		"value": func() -> float: return float(GameState.get(property)), "held": slider.held})

func _button(text: String, rect: Rect2, big: bool) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.big = big
	button.position = rect.position
	button.size = rect.size
	_add(button)
	return button

func _add(node: Control) -> void:
	add_child(node)
	_nodes.append(node)

func _text(at: Vector2, text: String, color := Color.WHITE) -> void:
	_texts.append([at, text, color])

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	for frame in _frames:
		UIKit.draw_frame(self, frame, s)
	if _menu():
		draw_rect(Rect2(anchor.x + (15.0 + 140.0 * tab) * s, anchor.y + 10.0 * s, 580.0 * s / 5.0 + 10.0 * s, 30.0 * s + 10.0 * s), Color8(0, 255, 0))
	else:
		draw_rect(Rect2(anchor.x + (-10.0 + 110.0 * tab) * s, anchor.y - 5.0 * s, 110.0 * s, 40.0 * s), Color8(0, 255, 0))
	for entry in _texts:
		var text: String = entry[1].call() if entry[1] is Callable else entry[1]
		UIKit.draw_text(self, entry[0], text, entry[2], "regular", s)

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var mouse := get_local_mouse_position()
	var found := -1
	for i in _tips.size():
		var held: Variant = _tips[i].get("held")
		if held is Callable and held.call():
			found = i
			break
	if found < 0:
		for i in _tips.size():
			if _tips[i].rect.has_point(mouse):
				found = i
				break
	if found != _shown_tip:
		_shown_tip = found
		_tip_layer.queue_redraw()

func _draw_tooltip() -> void:
	if _shown_tip < 0 or _shown_tip >= _tips.size():
		return
	var entry: Dictionary = _tips[_shown_tip]
	var value := 0.0
	if entry.has("value"):
		value = entry.value.call()
	draw_options_tooltip(_tip_layer, tooltip_at, entry.tip, value, float(entry.get("extra", 0.0)))

# DrawOptionsTooltip: the text in white, a second line in the option's colour, framed to fit.
static func tooltip_text(option: String, value: float) -> Array:
	var q := "\""
	var txt := ""
	var txt2 := ""
	var color := Color.BLACK
	match option:
		"vsync":
			txt = q + "Vertical sync" + q + " waits for the display to finish its current refresh cycle before calculating the next frame, preventing issues such as "
			txt += "screen tearing. This ties the game's frame rate to your display's refresh rate and may cause some input lag."
		"antialias":
			txt = q + "Anti-Aliasing" + q + " is used to smooth the rendered image before displaying in order to reduce aliasing around the edges of models."
			txt2 = "This option only takes effect in fullscreen."
			color = Color8(255, 0, 0)
		"roomlights":
			txt = "Toggles the artificial lens flare effect generated over specific light sources."
		"gamma":
			txt = q + "Gamma correction" + q + " is used to achieve a good brightness factor to balance out your display's gamma if the game appears either too dark or bright. "
			txt += "Setting it too high or low can cause the graphics to look less detailed."
			color = Color.WHITE
			txt2 = "Current value: %d%% (default is 100%%)" % int(value * 100.0)
		"texquality":
			txt = q + "Texture LOD Bias" + q + " affects the distance at which texture detail will change to prevent aliasing. Change this option if textures flicker or look too blurry."
		"particleamount":
			txt = "Determines the amount of particles that can be rendered per tick."
			match int(value):
				0:
					color = Color8(255, 0, 0)
					txt2 = "Only smoke emitters will produce particles."
				1:
					color = Color8(255, 255, 0)
					txt2 = "Only a few particles will be rendered per tick."
				2:
					color = Color8(0, 255, 0)
					txt2 = "All particles are rendered."
		"musicvol":
			txt = "Adjusts the volume of background music. Sliding the bar fully to the left will mute all music."
			color = Color.WHITE
			txt2 = "Current value: %d%% (default is 50%%)" % int(value * 100.0)
		"soundvol":
			txt = "Adjusts the volume of sound effects. Sliding the bar fully to the left will mute all sounds."
			color = Color.WHITE
			txt2 = "Current value: %d%% (default is 100%%)" % int(value * 100.0)
		"usertrack":
			txt = "Toggles the ability to play custom tracks over channel 1 of the radio. These tracks are loaded from the " + q + "SFX\\Radio\\UserTracks\\" + q
			txt += " directory. Press " + q + "1" + q + " when the radio is selected to change track."
			color = Color8(255, 0, 0)
			txt2 = "This option cannot be changed in-game."
		"usertrackmode":
			txt = "Sets the playing mode for the custom tracks. " + q + "Repeat" + q + " plays every file in alphabetical order. " + q + "Random" + q + " chooses the "
			txt += "next track at random."
			color = Color8(255, 255, 0)
			txt2 = "Note that the random mode does not prevent previously played tracks from repeating."
		"usertrackscan":
			txt = "Re-checks the user tracks directory for any new or removed sound files."
		"mousesensitivity":
			txt = "Adjusts the speed of the mouse pointer."
			color = Color.WHITE
			txt2 = "Current value: %d%% (default is 50%%)" % int((0.5 + value) * 100.0)
		"mouseinvert":
			txt = q + "Invert mouse Y-axis" + q + " is self-explanatory."
		"mousesmoothing":
			txt = "Adjusts the amount of smoothing of the mouse pointer."
			color = Color.WHITE
			txt2 = "Current value: %d%% (default is 100%%)" % int(value * 100.0)
		"controls":
			txt = "Configure the in-game control scheme."
		"hud":
			txt = "Display the blink and stamina meters."
		"consoleenable":
			txt = "Toggles the use of the developer console and the debug menu. The console opens in-game with " + KeyNames.name_of(int(GameState.binds.console)) + ", the debug menu with F1; F2 toggles god mode, F4 lighting, F6 spawns SCP-106 and F7 toggles noclip."
		"consoleerror":
			txt = q + "Open console on error" + q + " is self-explanatory."
		"achpopup":
			txt = "Displays a pop-up notification when an achievement is unlocked."
		"showfps":
			txt = "Displays the frames per second counter at the top left-hand corner."
		"framelimit":
			txt = "Limits the frame rate that the game can run at to a desired value."
			if value > 0.0 and value < 60.0:
				color = Color8(255, 255, 0)
				txt2 = "Usually, 60 FPS or higher is preferred. If you are noticing excessive stuttering at this setting, try lowering it to make your framerate more consistent."
		"antialiastext":
			txt = q + "Antialiased text" + q + " smooths out the text before displaying. Makes text easier to read at high resolutions."
	return [txt, txt2, color]

static func draw_options_tooltip(item: CanvasItem, at: Vector2, option: String, value: float, extra_height: float) -> void:
	var s := UIKit.menu_scale(item as Control)
	var parts := tooltip_text(option, value)
	var width := 400.0 * s
	var height := 150.0 * s + extra_height
	var fx := at.x + 6.0 * s
	var fy := at.y + 6.0 * s
	var fw := width - 12.0 * s
	var fh := height - 12.0 * s
	var step := UIKit.line_height("regular", s)
	var lines := mini(UIKit.wrap_text(parts[0], fw, "regular", s).size(), maxi(int(fh / (step + 1.0)), 1))
	var frame_height := step * lines + (10.0 + lines) * s
	var lines2 := 0
	if parts[1] != "":
		lines2 = mini(UIKit.wrap_text(parts[1], fw, "regular", s).size(), maxi(int(fh / (step + 1.0)), 1))
		frame_height += step * lines2 + (10.0 + lines2) * s
	UIKit.draw_frame(item, Rect2(at, Vector2(width, frame_height)), s)
	UIKit.draw_row_text(item, Vector2(fx, fy), parts[0], fw, fh, Color.WHITE, s)
	if parts[1] != "":
		UIKit.draw_row_text(item, Vector2(fx, fy + step * lines + (5.0 + lines) * s), parts[1], fw, fh, parts[2], s)
