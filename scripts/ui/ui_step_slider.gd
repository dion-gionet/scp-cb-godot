extends Control
# Slider3 / Slider5: a grey bar (width + 14) x 10 with a notch per step, green while held, the blink meter
# picture on the chosen step and the step's name under it. The control spans y - 8 .. y + 10 of the original.

signal value_changed(value: int)


var value := 0
var labels: Array = []
var bar_width := 100.0
var _held := false
var _hover := false

func setup(at: Vector2, width: float, names: Array, start: int) -> void:
	position = at - Vector2(0.0, 8.0)
	bar_width = width
	size = Vector2(width + 14.0, 18.0)
	labels = names
	value = start

func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

func held() -> bool:
	return _held

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed
		if _held:
			_pick(event.position.x)
		queue_redraw()
	elif event is InputEventMouseMotion and _held:
		_pick(event.position.x)

# A step is taken only with the mouse on its notch (or beyond either end), as Slider3/Slider5 test it.
func _pick(mouse_x: float) -> void:
	var steps := labels.size() - 1
	var picked := -1
	if mouse_x <= 8.0:
		picked = 0
	elif mouse_x >= bar_width:
		picked = steps
	else:
		for i in range(1, steps):
			var notch := bar_width * float(i) / steps
			if mouse_x >= notch and mouse_x <= notch + 8.0:
				picked = i
	if picked >= 0 and picked != value:
		value = picked
		value_changed.emit(value)
	queue_redraw()

func _notch_x(i: int) -> float:
	var steps := labels.size() - 1
	return bar_width * float(i) / steps + 10.0 * float(i) / steps

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	var steps := labels.size() - 1
	var grey := Color8(200, 200, 200)
	draw_rect(Rect2(0.0, 8.0, bar_width + 14.0, 10.0), grey)
	for i in steps + 1:
		draw_rect(Rect2(_notch_x(i), 0.0, 4.0, 14.0), grey)
	if _held:
		draw_rect(Rect2(0.0, 8.0, bar_width + 14.0, 10.0), Color8(0, 255, 0))
	elif _hover:
		draw_rect(Rect2(0.5, 8.5, bar_width + 13.0, 9.0), Color8(0, 200, 0), false, 1.0)
	var handle := UIKit.texture("GFX/blinkmeter.jpg")
	var handle_x := 0.0 if value == 0 else (bar_width + 6.0 if value == steps else bar_width * float(value) / steps + 6.0 * float(value) / steps)
	if handle != null:
		draw_texture(handle, Vector2(handle_x, 0.0))
	var label_x := 2.0 if value == 0 else (bar_width + 12.0 if value == steps else _notch_x(value) + 2.0)
	UIKit.draw_text(self, Vector2(label_x, 18.0 + s), str(labels[value]), Color8(170, 170, 170), "regular", s, true)
