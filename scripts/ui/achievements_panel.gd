extends Control
class_name AchievementsPanel
# The in-game achievements list (Main.bb 7618-7660, Achievements.bb DrawAchvIMG / AchievementTooltip):
# twelve pictures a page, four to a row, rows 120 units apart.

const PER_PAGE := 12
const PER_ROW := 4

var anchor := Vector2.ZERO:
	set(value):
		anchor = value
		queue_redraw()
var page := 1:
	set(value):
		page = value
		queue_redraw()
var _hovered := -1
var _mouse := Vector2.ZERO

static func last_page() -> int:
	return int(floor(float(GameState.MAX_ACHIEVEMENTS - 1) / PER_PAGE)) + 1

static func cells_on(page_number: int) -> int:
	return clampi(GameState.MAX_ACHIEVEMENTS - (page_number - 1) * PER_PAGE, 0, PER_PAGE)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	var mouse := get_local_mouse_position()
	var s := UIKit.menu_scale(self)
	var hovered := -1
	for i in cells_on(page):
		if _cell_rect(i, s).has_point(mouse):
			hovered = (page - 1) * PER_PAGE + i
			break
	if hovered != _hovered or (hovered >= 0 and mouse != _mouse):
		queue_redraw()
	_hovered = hovered
	_mouse = mouse

func _cell_rect(i: int, s: float) -> Rect2:
	var side := 64.0 * s * 4.0 / 3.0
	var origin := Vector2(anchor.x + 22.0 * s + (i % PER_ROW) * 76.0 * s * 4.0 / 3.0, anchor.y + (i / PER_ROW) * 120.0 * s)
	return Rect2(origin, Vector2(side, side))

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	var hovered := -1
	var mouse := get_local_mouse_position()
	for i in cells_on(page):
		var index := (page - 1) * PER_PAGE + i
		var rect := _cell_rect(i, s)
		draw_rect(rect, Color.BLACK)
		var unlocked: bool = GameState.achievements.has(GameState.ACHIEVEMENT_ORDER[index])
		var picture := AchievementInfo.picture(index) if unlocked else AchievementInfo.locked_picture()
		if picture != null:
			draw_texture_rect(picture, rect, false)
		draw_rect(rect, Color8(50, 50, 50), false)
		if hovered < 0 and rect.has_point(mouse):
			hovered = index
	if hovered >= 0:
		_draw_tooltip(hovered, mouse, s)

func _draw_tooltip(index: int, mouse: Vector2, s: float) -> void:
	var title := AchievementInfo.title(index)
	var description := AchievementInfo.description(index)
	var width := maxf(UIKit.text_width(title, "digital", s), UIKit.text_width(description, "regular", s)) + 20.0 * s
	var rect := Rect2(mouse + Vector2(20.0, 20.0) * s, Vector2(width, 38.0 * s * 4.0 / 3.0))
	draw_rect(rect, Color8(25, 25, 25))
	draw_rect(rect, Color8(150, 150, 150), false)
	UIKit.draw_text(self, mouse + Vector2(20.0 * s + width * 0.5, 35.0 * s), title, Color.WHITE, "digital", s, true, true)
	UIKit.draw_text(self, mouse + Vector2(20.0 * s + width * 0.5, 55.0 * s), description, Color.WHITE, "regular", s, true, true)
