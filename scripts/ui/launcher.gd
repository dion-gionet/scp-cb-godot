extends Control
class_name Launcher
# Menu.bb UpdateLauncher at MenuScale 1 in a LauncherWidth x LauncherHeight window: the resolution grid, the
# graphics driver (here: screen) list, the fullscreen / borderless / use launcher ticks, LAUNCH and EXIT. The 16 Bit and
# "check for updates" ticks are left out (Godot has no 16-bit back buffer, the port has no update server), so "Use
# launcher" moves up into 16 Bit's place and the resolution lines drop their colour depth.

signal launched
signal exited

# Godot cannot list display modes: the common ones that fit the screen, in CountGfxModes3D's ascending order.
const COMMON_MODES: Array[Vector2i] = [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1152, 864), Vector2i(1280, 720),
	Vector2i(1280, 768), Vector2i(1280, 800), Vector2i(1280, 960), Vector2i(1280, 1024), Vector2i(1360, 768),
	Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1600, 1200), Vector2i(1680, 1050),
	Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440),
	Vector2i(3840, 2160)]
const FONT_PIXELS := 18

var modes: Array[Vector2i] = []
var selected_mode := 0
var selected_driver := 1
var fullscreen := false
var borderless := false
var launcher_enabled := true
var screen := Vector2i.ZERO

var fullscreen_tick: UITick
var borderless_tick: UITick
var launcher_tick: UITick
var launch_button: UIButton
var exit_button: UIButton

static func modes_for(screen_size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for mode in COMMON_MODES:
		if mode.x <= screen_size.x and mode.y <= screen_size.y:
			out.append(mode)
	if not out.has(screen_size):
		out.append(screen_size)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out

func _ready() -> void:
	size = Vector2(GameState.launcher_width, GameState.launcher_height)
	selected_driver = clampi(GameState.gfx_driver, 1, WindowSetup.screen_count())
	fullscreen = GameState.fullscreen
	borderless = GameState.borderless_windowed
	launcher_enabled = GameState.launcher_enabled
	_rebuild_modes(Vector2i(GameState.graphic_width, GameState.graphic_height))
	var lw := GameState.launcher_width
	var lh := GameState.launcher_height
	fullscreen_tick = _tick(Vector2(40 + 430 - 15, 260 - 55 + 5 - 8), func(on: bool) -> void: fullscreen = on)
	borderless_tick = _tick(Vector2(40 + 430 - 15, 260 - 55 + 35), func(on: bool) -> void: borderless = on)
	launcher_tick = _tick(Vector2(40 + 430 - 15, 260 - 55 + 65 + 8), func(on: bool) -> void: launcher_enabled = on)
	launch_button = _button("LAUNCH", Rect2(lw - 30 - 90, lh - 50 - 55, 100, 30), _launch)
	exit_button = _button("EXIT", Rect2(lw - 30 - 90, lh - 50, 100, 30), func() -> void: exited.emit())
	_sync()

func _tick(at: Vector2, apply: Callable) -> UITick:
	var tick := UITick.new()
	tick.position = at
	tick.size = Vector2(20, 20)
	tick.toggled.connect(func(on: bool) -> void:
		apply.call(on)
		_sync())
	add_child(tick)
	return tick

func _button(text: String, rect: Rect2, action: Callable) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.big = false
	button.fixed_scale = 1.0
	button.font_pixels = FONT_PIXELS
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(action)
	add_child(button)
	return button

func selected_resolution() -> Vector2i:
	return modes[selected_mode]

func _rebuild_modes(keep: Vector2i) -> void:
	screen = WindowSetup.screen_size(WindowSetup.screen_of_driver(selected_driver))
	modes = modes_for(screen)
	var found := modes.find(keep)
	selected_mode = found if found >= 0 else 0

# The rule the original applies while drawing: borderless forces fullscreen off.
func _sync() -> void:
	if borderless:
		fullscreen = false
	fullscreen_tick.on = fullscreen
	fullscreen_tick.locked = borderless
	borderless_tick.on = borderless
	launcher_tick.on = launcher_enabled
	for tick: UITick in [fullscreen_tick, borderless_tick, launcher_tick]:
		tick.queue_redraw()
	queue_redraw()

func _launch() -> void:
	var mode := selected_resolution()
	GameState.graphic_width = mode.x
	GameState.graphic_height = mode.y
	GameState.fullscreen = fullscreen
	GameState.borderless_windowed = borderless
	GameState.launcher_enabled = launcher_enabled
	GameState.gfx_driver = selected_driver
	GameState.save_settings()
	launched.emit()

func mode_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x := 40
	var y := 270 - 65
	for i in modes.size():
		rects.append(Rect2(x - 1, y - 1, 100, 20))
		y += 20
		if y >= 250 - 65 + (GameState.launcher_height - 80 - 260):
			y = 270 - 65
			x += 100
	return rects

func driver_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for i in WindowSetup.screen_count():
		rects.append(Rect2(30 - 1, 369 + 10 + 20 * i - 1, 290, 20))
	return rects

func click_at(point: Vector2) -> void:
	var rects := mode_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			selected_mode = i
	rects = driver_rects()
	for i in rects.size():
		if rects[i].has_point(point) and selected_driver != i + 1:
			selected_driver = i + 1
			_rebuild_modes(selected_resolution())
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_at(event.position)

func _text(at: Vector2, text: String, color: Color) -> void:
	var font := UIKit.font("regular")
	draw_string(font, Vector2(at.x, at.y + font.get_ascent(FONT_PIXELS)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PIXELS, color)

func _outline(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(0.5, 0.5), rect.size - Vector2.ONE), color, false)

func _draw() -> void:
	var lw := GameState.launcher_width
	var lh := GameState.launcher_height
	var mouse := get_local_mouse_position()
	draw_rect(Rect2(0, 0, lw, lh), Color.BLACK)
	var backdrop := UIKit.texture("GFX/menu/launcher.jpg")
	if backdrop != null:
		draw_texture(backdrop, Vector2.ZERO)
	_text(Vector2(20, 240 - 65), "Resolution: ", Color.WHITE)
	var rects := mode_rects()
	for i in modes.size():
		if selected_mode == i:
			_outline(rects[i], Color.BLACK)
		_text(rects[i].position + Vector2(1, 1), "%dx%d" % [modes[i].x, modes[i].y], Color.BLACK)
		if rects[i].has_point(mouse):
			_outline(rects[i], Color8(100, 100, 100))

	draw_rect(Rect2(30 - 10, 369, 340, 95), Color.WHITE)
	_text(Vector2(30 - 10, 369 - 25), "Graphics:", Color.WHITE)
	var drivers := driver_rects()
	for i in drivers.size():
		if selected_driver == i + 1:
			_outline(drivers[i], Color.BLACK)
		_text(drivers[i].position + Vector2(1, 1), _limited(WindowSetup.screen_name(i), 290), Color.BLACK)
		if drivers[i].has_point(mouse):
			_outline(drivers[i], Color8(100, 100, 100))

	_text(Vector2(40 + 430 + 15, 262 - 55 + 5 - 8), "Fullscreen", Color(1, 0, 0) if borderless else Color.WHITE)
	_text(Vector2(40 + 430 + 15, 262 - 55 + 35 - 8), "Borderless", Color.WHITE)
	_text(Vector2(40 + 430 + 15, 262 - 55 + 35 + 12), "windowed mode", Color.WHITE)
	_text(Vector2(40 + 430 + 15, 262 - 55 + 65 + 8), "Use launcher", Color.WHITE)

	var mode := selected_resolution()
	_text(Vector2(40 + 260 + 15, 262 - 55 + 140), "Current Resolution: %dx%d" % [mode.x, mode.y], Color.WHITE)
	if borderless and mode.x != screen.x:
		var verb := "(upscaled to" if mode.x < screen.x else "(downscaled to"
		_text(Vector2(40 + 260 + 65, 262 - 55 + 160), verb, Color.WHITE)
		_text(Vector2(40 + 260 + 65, 262 - 55 + 180), "%dx%d)" % [screen.x, screen.y], Color.WHITE)

func _limited(text: String, width: float) -> String:
	var font := UIKit.font("regular")
	var total := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PIXELS).x
	var overflow := total - width
	if overflow <= 0.0:
		return text
	var letter := total / text.length()
	return text.left(maxi(int(text.length() - overflow / letter - 4), 1)) + "..."
