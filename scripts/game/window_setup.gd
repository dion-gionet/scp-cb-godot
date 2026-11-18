class_name WindowSetup
extends RefCounted
# The window half of Main.bb's start-up: the launcher's own window, then Graphics3DExt (windowed, exclusive
# fullscreen) or the borderless "fake fullscreen". Godot cannot change the display mode or render at a size other than
# the window's, so the chosen resolution is the root window's content scale size and the engine scales it to the
# screen: AspectRatioRatio's upscale / downscale, with bars where the aspects differ.

static func screen_count() -> int:
	return maxi(DisplayServer.get_screen_count(), 1)

static func screen_of_driver(driver: int) -> int:
	return clampi(driver - 1, 0, screen_count() - 1)

# Headless has no screens (a size of zero).
static func screen_size(screen: int) -> Vector2i:
	var size := DisplayServer.screen_get_size(screen)
	return size if size.x > 0 and size.y > 0 else Vector2i(1920, 1080)

static func screen_name(screen: int) -> String:
	var size := screen_size(screen)
	return "Display %d (%dx%d)" % [screen + 1, size.x, size.y]

static func show_launcher(window: Window) -> void:
	window.title = "SCP - Containment Breach Launcher"
	_place(window, DisplayServer.get_primary_screen(), Vector2i(GameState.launcher_width, GameState.launcher_height), Window.MODE_WINDOWED)

static func apply_game(window: Window) -> void:
	window.title = str(ProjectSettings.get_setting("application/config/name"))
	var screen := screen_of_driver(GameState.gfx_driver)
	var size := Vector2i(GameState.graphic_width, GameState.graphic_height)
	var mode := Window.MODE_WINDOWED
	if GameState.borderless_windowed:
		mode = Window.MODE_FULLSCREEN
	elif GameState.fullscreen:
		mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	_place(window, screen, size, mode)

static func _place(window: Window, screen: int, size: Vector2i, mode: Window.Mode) -> void:
	window.content_scale_size = size
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	window.mode = Window.MODE_WINDOWED
	window.unresizable = true
	window.current_screen = screen
	window.size = size
	window.position = DisplayServer.screen_get_position(screen) + (screen_size(screen) - size) / 2
	window.mode = mode
	if not window.size_changed.is_connected(_scale_3d.bind(window)):
		window.size_changed.connect(_scale_3d.bind(window))
	_scale_3d(window)

# canvas_items scaling only reaches the 2D canvas; the 3D view renders at the window's size unless scaled down (or up) to
# the chosen height.
static func _scale_3d(window: Window) -> void:
	var height := maxi(window.size.y, 1)
	window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	window.scaling_3d_scale = clampf(float(window.content_scale_size.y) / height, 0.25, 2.0)
