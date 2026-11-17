extends Control
# SlideBar: a white outline (width + 14) x 20 with the blink meter picture as the handle, LOW and HIGH in grey
# either side. Dragging sets whole percents, (mouse x - x) * 100 / width in integers.

signal value_changed(value: float)


var value := 1.0     # 0..1
var bar_width := 100.0
var _dragging := false

func setup(at: Vector2, width: float, start: float) -> void:
	position = at
	bar_width = width
	size = Vector2(width + 14.0, 20.0)
	value = start

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from(event.position.x)
	elif event is InputEventMouseMotion and _dragging:
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			_set_from(event.position.x)

func _set_from(x: float) -> void:
	value = clampi(int(x) * 100 / int(maxf(bar_width, 1.0)), 0, 100) / 100.0
	value_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color.WHITE, false, 1.0)
	var handle := UIKit.texture("GFX/blinkmeter.jpg")
	var at := Vector2(bar_width * value + 3.0, 3.0)
	if handle != null:
		draw_texture(handle, at)
	else:
		draw_rect(Rect2(at, Vector2(8, 14)), Color.WHITE)
	var grey := Color8(170, 170, 170)
	UIKit.draw_text(self, Vector2(-50.0 * s, 4.0 * s), "LOW", grey, "regular", s)
	UIKit.draw_text(self, Vector2(bar_width + 38.0 * s, 4.0 * s), "HIGH", grey, "regular", s)
