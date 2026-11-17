extends Control
# The Tab inventory (Main.bb DrawGUI, InvOpen): 5 x 2 framed slots, 70 px with 35 px spacing in
# screen pixels (UIKit.pixel_scale). Hovering shows the item name; dragging moves it to another slot or drops it
# when released outside the slots; a double click uses it. Worn items get a light border.


const SLOT_COUNT := 10
const DOUBLE_CLICK_MS := 400

var hud: Node              # items, item_data, use_from_inventory(), swap_items(), drop_from_inventory()
var container := -1          # >= 0: the pockets of the clipboard or wallet in that inventory slot are shown (OtherOpen)
var _drag_index := -1
var _last_click_slot := -1
var _last_click_ms := 0
# Hover and the dragged icon follow the positions of the same events that press and release use. In a Windows borderless
# fullscreen game get_local_mouse_position() was reported a constant offset away from them: no name showed under the cursor.
var _mouse := Vector2(-1.0, -1.0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func reset() -> void:
	_last_click_slot = -1
	_drag_index = -1
	_mouse = get_local_mouse_position()
	queue_redraw()

func _k() -> float:
	return UIKit.pixel_scale(self)

func slot_rect(index: int) -> Rect2:
	var k := _k()
	var width := 70.0 * k
	var spacing := 35.0 * k
	var x0 := size.x * 0.5 - (width * SLOT_COUNT / 2.0 + spacing * (SLOT_COUNT / 2.0 - 1.0)) * 0.5
	var row := index / 5
	var column := index % 5
	var top := size.y * 0.5 - width
	if container >= 0:
		top = size.y * 0.5 - (width * 2.0 + spacing) * 0.5      # y = H / 2 - (height * Size / 5 + spacing * (Size / 5 - 1)) / 2
	return Rect2(x0 + column * (width + spacing), top + row * width * 2.0, width, width)

# What slot i shows: {name, icon} or {}.
func _entry(i: int) -> Dictionary:
	if container >= 0:
		var held: Dictionary = hud.container_slots(container)[i]
		if held.is_empty():
			return {}
		return {"name": str(held.name), "icon": str(held.data.get("icon", ""))}
	if hud.items[i].is_empty():
		return {}
	return {"name": hud.items[i], "icon": str(hud.item_data[i].get("icon", ""))}

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	var k := _k()
	var s := size.y / 1024.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var mouse := _mouse
	var hover := -1
	for i in SLOT_COUNT:
		var rect := slot_rect(i)
		var hovering := rect.has_point(mouse)
		if hovering:
			hover = i
		var entry := _entry(i)
		if container < 0 and not entry.is_empty() and _is_worn(str(hud.item_data[i].get("tempname", ""))):
			draw_rect(rect.grow(3.0 * k), Color8(200, 200, 200))
		if hovering:
			draw_rect(rect.grow(k), Color.RED)
		UIKit.draw_frame(self, rect, s)
		if not entry.is_empty() and i != _drag_index:
			var texture: Texture2D = hud._icon(str(entry.icon))
			if texture != null:
				var icon := Vector2(64.0, 64.0) * k
				draw_texture_rect(texture, Rect2(rect.position + (rect.size - icon) * 0.5, icon), false)
	if hover >= 0 and not _entry(hover).is_empty() and _drag_index < 0:
		_draw_name(str(_entry(hover).name), slot_rect(hover), s)
	if _drag_index >= 0 and not _entry(_drag_index).is_empty():
		var dragged: Texture2D = hud._icon(str(_entry(_drag_index).icon))
		if dragged != null:
			var drag_size := Vector2(64.0, 64.0) * k   # DrawImage at the picture's own size: 64 px in the original
			draw_texture_rect(dragged, Rect2(mouse - drag_size * 0.5, drag_size), false)

func _draw_name(text: String, slot: Rect2, s: float) -> void:
	var font := UIKit.font("regular")
	var font_size := UIKit.font_size("regular", s)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(slot.position.x + (slot.size.x - width) * 0.5, slot.end.y + 35.0 * _k() - 15.0 * s + font.get_ascent(font_size))
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func is_worn(tempname: String) -> bool:
	return _is_worn(tempname)

func _is_worn(tempname: String) -> bool:
	match tempname:
		"gasmask":
			return GameState.wearing_gas_mask == 1
		"supergasmask":
			return GameState.wearing_gas_mask == 2
		"gasmask3":
			return GameState.wearing_gas_mask == 3
		"hazmatsuit":
			return GameState.wearing_hazmat == 1
		"hazmatsuit2":
			return GameState.wearing_hazmat == 2
		"hazmatsuit3":
			return GameState.wearing_hazmat == 3
		"vest":
			return GameState.wearing_vest == 1
		"finevest":
			return GameState.wearing_vest == 2
		"scp714":
			return GameState.wearing_714
		"scp427":
			return GameState.i427_using
		"scp1499":
			return GameState.wearing_1499 == 1
		"super1499":
			return GameState.wearing_1499 == 2
		"nvgoggles":
			return GameState.wearing_night_vision == 1
		"supernv":
			return GameState.wearing_night_vision == 2
		"finenvgoggles":
			return GameState.wearing_night_vision == 3
	return false

func hover_slot() -> int:
	return slot_at(_mouse)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		var slot := slot_at(event.position)
		if slot >= 0 and not _entry(slot).is_empty():
			_drag_index = slot
		return
	var from := _drag_index
	_drag_index = -1
	if from < 0:
		return
	var target := slot_at(event.position)
	var now := Time.get_ticks_msec()
	if target == from:
		# a click; twice in a row uses the item (the original's double click)
		if _last_click_slot == from and now - _last_click_ms < DOUBLE_CLICK_MS:
			_last_click_slot = -1
			if container >= 0:
				hud.use_from_container(from)
			else:
				hud.use_from_inventory(from)
		else:
			_last_click_slot = from
			_last_click_ms = now
	elif target >= 0 and container >= 0:
		var slots: Array = hud.container_slots(container)
		if (slots[target] as Dictionary).is_empty():
			slots[target] = slots[from]
			slots[from] = {}
		else:
			hud.message("You cannot combine these two items.", 5.0)
	elif target >= 0:
		hud.swap_items(from, target)
	elif container >= 0:
		hud.drop_from_container(from)
	else:
		hud.drop_from_inventory(from)

func slot_at(position_value: Vector2) -> int:
	for i in SLOT_COUNT:
		if slot_rect(i).has_point(position_value):
			return i
	return -1
