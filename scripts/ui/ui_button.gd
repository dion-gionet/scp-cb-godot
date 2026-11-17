extends Control
class_name UIButton
# DrawButton: framed, highlights (30,30,30) under the mouse, white text centred.

signal pressed


var text := ""
var big := true
var locked := false
var fixed_scale := 0.0   # > 0: a MenuScale of its own (the launcher draws at 1)
var font_pixels := 0
var _hover := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		UIKit.play_button_sound(self)
		pressed.emit()
		accept_event()

func _draw() -> void:
	var s := fixed_scale if fixed_scale > 0.0 else UIKit.menu_scale(self)
	UIKit.draw_frame(self, Rect2(Vector2.ZERO, size), s)
	if _hover and not locked:
		draw_rect(Rect2(Vector2(4, 4) * s, size - Vector2(8, 8) * s), Color8(30, 30, 30))
	var font := UIKit.font("bold") if big else UIKit.font("regular")
	var font_size := font_pixels if font_pixels > 0 else int((58.0 * 0.78 if big else 19.0) * s)   # Blitz sizes are cell heights, about 0.78 of the em
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var color := Color(0.4, 0.4, 0.4) if locked else Color.WHITE
	var ascent := font.get_ascent(font_size)
	var height := font.get_height(font_size)
	draw_string(font, Vector2((size.x - width) * 0.5, (size.y - height) * 0.5 + ascent), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
