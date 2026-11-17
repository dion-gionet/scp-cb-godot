extends RefCounted
class_name UIKit
# The menu look of the original (Menu.bb DrawFrame / DrawButton / DrawTick, Main.bb fonts).
# Everything is laid out in a 1024-high reference space: MenuScale = viewport height / 1024.


static var _textures: Dictionary = {}
static var _fonts: Dictionary = {}
static var _antialiased := true

static func menu_scale(control: Control) -> float:
	return control.get_viewport_rect().size.y / 1024.0

# Canvas units per screen pixel. The original draws its HUD, inventory, radio, ending and blink pictures with plain DrawImage /
# Rect at fixed pixel numbers (no MenuScale), so they keep their pixel size at every resolution; the stretched canvas
# (canvas_items) is undone with this.
static var _headless := DisplayServer.get_name() == "headless"

static func pixel_scale(item: Node) -> float:
	var window := item.get_window()
	# the headless display reports a 100 x 100 window under a 1152 canvas: there are no real pixels to keep
	if window == null or window.size.y <= 0 or _headless:
		return 1.0
	return window.get_visible_rect().size.y / float(window.size.y)

const FRAME_WHITE := "GFX/menu/menuwhite.jpg"
const FRAME_BLACK := "GFX/menu/menublack.jpg"

static func texture(relative: String) -> Texture2D:
	if _textures.has(relative):
		return _textures[relative]
	var texture: Texture2D = null
	var path := ContentPaths.existing_image(relative)
	if FileAccess.file_exists(path):
		var image := MeshLoader.load_image(path)
		if image != null:
			texture = ImageTexture.create_from_image(image)
	_textures[relative] = texture
	return texture

# Font1 Courier New 19, Font2 Courier New Bold 58 (both scaled by MenuScale), Font3 DS-Digital 22,
# Font4 DS-Digital 60, Font5 Journal 58. Font2 is loaded from courbd\Courier New.ttf, but Blitz picks the font by its
# family name without the bold flag, so the original draws it in the regular weight.
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var relative := "GFX/font/cour/Courier New.ttf"
	match kind:
		"digital", "digital_large":
			relative = "GFX/font/DS-DIGI/DS-Digital.TTF"
		"journal":
			relative = "GFX/font/Journal/Journal.ttf"
	var path := ContentPaths.existing_file(relative)
	var result: Font = ThemeDB.fallback_font
	if FileAccess.file_exists(path):
		var file := FontFile.new()
		file.load_dynamic_font(path)
		file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if _antialiased else TextServer.FONT_ANTIALIASING_NONE
		result = file
	_fonts[kind] = result
	return result

# DrawFrame: a white tiled border with a black tiled inset 3 (scaled) units in.
# The frame's pictures took 65 ms to read on the first in-game popup when the game was started without the main menu.
static func prewarm() -> void:
	texture(FRAME_WHITE)
	texture(FRAME_BLACK)

static func draw_frame(item: CanvasItem, rect: Rect2, scale_value: float) -> void:
	var white := texture(FRAME_WHITE)
	var black := texture(FRAME_BLACK)
	if white != null:
		item.draw_texture_rect(white, rect, true)
	else:
		item.draw_rect(rect, Color.WHITE)
	var inset := 3.0 * scale_value
	var inner := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	if black != null:
		item.draw_texture_rect(black, inner, true)
	else:
		item.draw_rect(inner, Color.BLACK)

# Antialiased text (AATextEnable): off, the original draws its text with Blitz's unsmoothed Text.
static func set_antialiased(on: bool) -> void:
	_antialiased = on
	for kind in _fonts:
		var font: Font = _fonts[kind]
		if font is FontVariation:
			font = font.base_font
		if font is FontFile:
			font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if on else TextServer.FONT_ANTIALIASING_NONE

# Blitz's LoadFont height is the whole cell (tmHeight); Godot's font size is the em. Courier New's cell is
# (winAscent 1705 + winDescent 615) / 2048 = 1.1328 em, so Font1's 19 is a 16.8 em.
const COURIER_CELL_PER_EM := 1.1328125

static func courier_size(cell_height: float) -> int:
	return maxi(int(round(cell_height / COURIER_CELL_PER_EM)), 1)

# AAText / Text: Font1 (cell Int(19 * MenuScale)), Font2 (58), ConsoleFont and Font3 (22), Font4 (60).
static func font_size(kind: String, scale_value: float) -> int:
	match kind:
		"bold":
			return int(58.0 * 0.78 * scale_value)
		"console", "digital":
			return int(22.0 * scale_value)
		"digital_large":
			return int(60.0 * scale_value)
	return courier_size(int(19.0 * scale_value))

# AAText(x, y, txt, centre_x, centre_y) with the given font, the text's top at y unless centred.
static func draw_text(item: CanvasItem, at: Vector2, text: String, color: Color, kind: String, scale_value: float, centre_x := false, centre_y := false) -> void:
	var used := font(kind)
	var size_value := font_size(kind, scale_value)
	var width := used.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x
	var x := at.x - width * 0.5 if centre_x else at.x
	var top := at.y - used.get_height(size_value) * 0.5 if centre_y else at.y
	item.draw_string(used, Vector2(x, top + used.get_ascent(size_value)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

static func text_width(text: String, kind: String, scale_value: float) -> float:
	return font(kind).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size(kind, scale_value)).x

# RowText: words wrapped to width w, at most h high; centred lines when align.
static func wrap_text(text: String, width: float, kind: String, scale_value: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and text_width(candidate, kind, scale_value) > width:
			lines.append(line)
			line = word
		else:
			line = candidate
	if not line.is_empty():
		lines.append(line)
	return lines

static func line_height(kind: String, scale_value: float) -> float:
	return font(kind).get_height(font_size(kind, scale_value))

static func draw_row_text(item: CanvasItem, at: Vector2, text: String, width: float, height: float, color: Color, scale_value: float, align := false) -> void:
	var step := line_height("regular", scale_value) + 1.0
	var lines := wrap_text(text, width, "regular", scale_value)
	for i in lines.size():
		if (i + 1) * step > height:
			break
		var x := at.x + (width - text_width(lines[i], "regular", scale_value)) * 0.5 if align else at.x
		draw_text(item, Vector2(x, at.y + i * step), lines[i], color, "regular", scale_value)

static func play_button_sound(parent: Node) -> void:
	Sfx.play_global(parent, "SFX/Interact/Button.ogg")
