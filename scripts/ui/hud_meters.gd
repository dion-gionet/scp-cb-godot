extends Control
# The always-visible HUD (Main.bb DrawGUI): blink and stamina meters with their icons, and the hand icons that point at the
# nearest door button (HandIcon) and item (HandIcon2). Pixel numbers are the original's screen pixels (UIKit.pixel_scale).


var hud: Node
var _hand_button := Vector3.INF
var _hand_item := Vector3.INF
var _hand_centre := false   # a screen is under the centre (DrawHandIcon)
var arrows_shown: Array[bool] = [false, false, false, false]
var _hand_icon := false
var _consumed_tick := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _k() -> float:
	return UIKit.pixel_scale(self)

# Called by the HUD every frame: finds what the hand icons point at.
func update_hands(player: Node3D) -> void:
	_hand_button = Vector3.INF
	_hand_item = Vector3.INF
	_hand_centre = false
	if hud.inventory_open or get_tree().paused:
		_hand_icon = false
		arrows_shown.fill(false)
		queue_redraw()
		return
	var pressed: Dictionary = player.closest_door_button() if player.has_method("closest_door_button") else {}
	if not pressed.is_empty():
		_hand_button = pressed.button.global_position
	elif player.has_method("closest_plain_button"):
		var plain: Node3D = player.closest_plain_button()
		if plain != null:
			_hand_button = plain.global_position
	var ray: RayCast3D = player.interact_ray
	var hit := ray.get_collider() if ray.is_colliding() else null
	if is_instance_valid(hit) and hit.has_meta("screen_image"):
		_hand_centre = true
	var tick := Engine.get_physics_frames()
	if tick != _consumed_tick:
		_consumed_tick = tick
		_hand_icon = GameState.hand_icon
		GameState.hand_icon = false
		arrows_shown = GameState.arrow_icons.duplicate()
		GameState.arrow_icons.fill(false)
	if _hand_icon:
		_hand_centre = true
	var item: Node3D = player.closest_item()
	if item != null:
		_hand_item = item.global_position
	queue_redraw()

func _draw() -> void:
	var player := GameState.player
	if player == null or hud.inventory_open:
		return
	var k := _k()
	if GameState.hud_enabled:
		_draw_meters(k)
	_draw_hands(player, k)
	if _hand_centre:
		var hand := UIKit.texture("GFX/handsymbol.png")
		if hand != null:
			draw_texture_rect(hand, Rect2(size * 0.5 - Vector2(32.0, 32.0) * k, Vector2(64.0, 64.0) * k), false)
	_draw_arrow_icons(k)

# DrawArrowIcon(0..3): a hand frame with a black square and the arrow turned 90 degrees a step, above, right of, below and left of the centre
func _draw_arrow_icons(k: float) -> void:
	var hand := UIKit.texture("GFX/handsymbol.png")
	var arrow := UIKit.texture("GFX/menu/arrow.png")
	for i in 4:
		if not arrows_shown[i]:
			continue
		var at := size * 0.5 - Vector2(32.0, 32.0) * k
		at += Vector2([0.0, 69.0, 0.0, -69.0][i], [-69.0, 0.0, 69.0, 0.0][i]) * k
		if hand != null:
			draw_texture_rect(hand, Rect2(at, Vector2(64.0, 64.0) * k), false)
		draw_rect(Rect2(at + Vector2(4.0, 4.0) * k, Vector2(56.0, 56.0) * k), Color.BLACK)
		if arrow != null:
			var side := Vector2(arrow.get_width(), arrow.get_height()) * k
			draw_set_transform(at + Vector2(21.0, 21.0) * k + side * 0.5, i * PI * 0.5, Vector2.ONE)
			draw_texture_rect(arrow, Rect2(-side * 0.5, side), false)
			draw_set_transform(Vector2.ZERO)

# HUDenabled: the blink and stamina meters with their icons
func _draw_meters(k: float) -> void:
	var player := GameState.player
	var width := 204.0 * k
	var bar_height := 20.0 * k
	var x := 80.0 * k
	var y := size.y - 95.0 * k
	_frame(Rect2(x, y, width, bar_height), k)
	_segments("GFX/BlinkMeter.png", Rect2(x, y, width, bar_height), clampf(player.blink_timer / player.blink_freq, 0.0, 1.0), k)
	if GameState.eye_irritation > 0.0:
		draw_rect(Rect2(Vector2(x - 50.0 * k, y) - Vector2(3.0, 3.0) * k, Vector2(36.0, 36.0) * k), Color8(200, 0, 0))   # the eyes sting
	_icon("GFX/BlinkIcon.png", Vector2(x - 50.0 * k, y), k)
	y = size.y - 55.0 * k
	_frame(Rect2(x, y, width, bar_height), k)
	_segments("GFX/StaminaMeter.png", Rect2(x, y, width, bar_height), clampf(player.stamina / 100.0, 0.0, 1.0), k)
	_icon("GFX/sneakicon.png" if player.crouching else "GFX/sprinticon.png", Vector2(x - 50.0 * k, y), k)

func _frame(rect: Rect2, k: float) -> void:
	draw_rect(rect, Color.WHITE, false, maxf(1.0, k))

# Int(((width - 2) * ratio) / 10) segments of the 10 pixel meter picture.
func _segments(relative: String, rect: Rect2, ratio: float, k: float) -> void:
	var texture := UIKit.texture(relative)
	var count := int(((204.0 - 2.0) * ratio) / 10.0)
	for i in count:
		var at := Vector2(rect.position.x + (3.0 + 10.0 * i) * k, rect.position.y + 3.0 * k)
		if texture != null:
			draw_texture_rect(texture, Rect2(at, Vector2(10.0, 14.0) * k), false)
		else:
			draw_rect(Rect2(at, Vector2(10.0, 14.0) * k), Color.WHITE)

func _icon(relative: String, at: Vector2, k: float) -> void:
	var box := Rect2(at, Vector2(30.0, 30.0) * k)
	draw_rect(box, Color.BLACK)
	draw_rect(box.grow(k), Color.WHITE, false, maxf(1.0, k))
	var texture := UIKit.texture(relative)
	if texture != null:
		draw_texture_rect(texture, box, false)

func _clamp_wrapped(angle: float) -> float:
	var wrapped := fposmod(angle, 360.0)
	if wrapped > 90.0 and wrapped <= 180.0:
		return 90.0
	if wrapped > 180.0 and wrapped < 270.0:
		return 270.0
	return wrapped

# Yaw and pitch offsets (world angle differences, Main.bb:4685-4720) clamped to 90 degrees, sin() of them times a third of the screen.
func _draw_hands(player: Node3D, k: float) -> void:
	var camera: Camera3D = player.camera
	for pair in [[_hand_button, "GFX/handsymbol.png"], [_hand_item, "GFX/handsymbol2.png"]]:
		var target: Vector3 = pair[0]
		if target == Vector3.INF:
			continue
		var offset := target - camera.global_position
		var target_yaw := rad_to_deg(atan2(-offset.x, -offset.z))
		var target_pitch := -rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length()))
		var yaw := _clamp_wrapped(rad_to_deg(camera.global_rotation.y) - target_yaw)
		var pitch := _clamp_wrapped(-rad_to_deg(camera.global_rotation.x) - target_pitch)
		var at := Vector2(size.x * 0.5 + sin(deg_to_rad(yaw)) * (size.x / 3.0), size.y * 0.5 - sin(deg_to_rad(pitch)) * (size.y / 3.0))
		var texture := UIKit.texture(str(pair[1]))
		if texture != null:
			draw_texture_rect(texture, Rect2(at - Vector2(32.0, 32.0) * k, Vector2(64.0, 64.0) * k), false)
