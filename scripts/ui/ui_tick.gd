extends Control
class_name UITick
# DrawTick: a small framed square, filled when on. A locked tick does not highlight or toggle.

signal toggled(on: bool)


var on := false
var locked := false
var _hover := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		UIKit.play_button_sound(self)
		toggled.emit(on)
		queue_redraw()
		accept_event()

func _draw() -> void:
	var highlight := _hover and not locked
	var white := UIKit.texture("GFX/menu/menuwhite.jpg")
	if white != null:
		draw_texture_rect(white, Rect2(Vector2.ZERO, size), true)
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color8(50, 50, 50) if highlight else Color.BLACK)
	if on:
		var tint := Color.WHITE if highlight else Color8(200, 200, 200)
		if white != null:
			draw_texture_rect(white, Rect2(Vector2(4, 4), size - Vector2(8, 8)), true, tint)
		else:
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), tint)
