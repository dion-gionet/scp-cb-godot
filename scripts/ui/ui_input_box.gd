extends Control
class_name UIInputBox
# InputBox: menuwhite tiled under a black inset ((50, 50, 50) under the mouse), the text centred in white. A click
# selects the box (SelectedInputBox), a click elsewhere deselects it; the selected box takes typed characters
# (rInput) and shows a caret blinking every 800 ms. A key box only reports the next key pressed while selected.

signal text_changed(text: String)
signal key_pressed(event: InputEventKey)


static var selected: Control = null

var text := ""
var max_length := 15
var key_box := false
var _hover := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

func _exit_tree() -> void:
	if selected == self:
		selected = null

func is_selected() -> bool:
	return selected == self

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = self
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and selected == self:
		if not get_global_rect().has_point(event.position):
			selected = null
	if selected != self or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if key_box:
		key_pressed.emit(event)
		selected = null
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_BACKSPACE:
		text = text.left(text.length() - 1)
	elif event.unicode >= 32 and event.unicode != 127:
		text = (text + char(event.unicode)).left(max_length)
	else:
		return
	text_changed.emit(text)
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if selected == self:
		queue_redraw()

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	var white := UIKit.texture("GFX/menu/menuwhite.jpg")
	if white != null:
		draw_texture_rect(white, Rect2(Vector2.ZERO, size), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color8(50, 50, 50) if _hover else Color.BLACK)
	if selected == self and Time.get_ticks_msec() % 800 < 400:
		var width := UIKit.text_width(text, "regular", s)
		draw_rect(Rect2(size.x * 0.5 + width * 0.5 + 2.0, size.y * 0.5 - 5.0, 2.0, 12.0), Color.WHITE)
	UIKit.draw_text(self, size * 0.5, text, Color.WHITE, "regular", s, true, true)
