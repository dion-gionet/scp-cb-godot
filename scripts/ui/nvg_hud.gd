extends Control
# The night vision goggles' readout (Main.bb RenderWorld2): the plain goggles show their battery bars on the left;
# the super pair also counts down to its next refresh and labels the NPCs it saw at the last refresh (name and
# distance, placed by the original's own yaw / pitch mapping); both flash "WARNING: LOW BATTERY" under 100.
# Positions are in screen pixels like the original's raw Rect / DrawImage calls; text is Font3 (DS-Digital, 22 at 1024 high).


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	visible = GameState.wearing_night_vision == 1 or GameState.wearing_night_vision == 2
	if visible:
		queue_redraw()

# MaskImage 255, 0, 255
var _icons: Texture2D

func _battery_icons() -> Texture2D:
	if _icons == null:
		var path := ContentPaths.existing_image("GFX/battery.png")
		if FileAccess.file_exists(path):
			var image := MeshLoader.load_image(path)
			image.convert(Image.FORMAT_RGBA8)
			for y in image.get_height():
				for x in image.get_width():
					var c := image.get_pixel(x, y)
					if c.r > 0.98 and c.g < 0.02 and c.b > 0.98:
						image.set_pixel(x, y, Color(0, 0, 0, 0))
			_icons = ImageTexture.create_from_image(image)
	return _icons

func _wrap(angle: float) -> float:
	return fposmod(angle, 360.0)

# The original maps (camera angle - angle to the NPC) to -1..1 with these pieces.
func _offset(angle: float) -> float:
	var value := _wrap(angle)
	if value > 90.0 and value <= 180.0:
		return sin(deg_to_rad(90.0)) / 90.0 * value
	elif value > 180.0 and value < 270.0:
		return sin(deg_to_rad(270.0)) / value * 270.0
	return sin(deg_to_rad(value))

func _draw() -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or facility.night_vision == null:
		return
	var kind := GameState.wearing_night_vision
	var nv: Node = facility.night_vision
	var eyes_open: bool = player.blink_timer < -16.0 or player.blink_timer > -6.0
	if not eyes_open:
		return
	var view := size
	var scale_menu := view.y / 1024.0
	var font := UIKit.font("digital")
	var font_size := int(22.0 * scale_menu)
	var dead := GameState.nvg_battery == 0
	var dark := Color8(0, 0, 55) if kind == 2 else Color8(0, 55, 0)
	var lit := Color8(0, 0, 255) if kind == 2 else Color8(0, 255, 0)
	if kind == 2 and not dead:
		_text(font, font_size, "REFRESHING DATA IN", Vector2(view.x * 0.5, (20.0 + (40.0 if GameState.nvg_battery == 1 else 0.0)) * scale_menu))
		_text(font, font_size, "%.1f" % maxf(nv.timer / 60.0, 0.0), Vector2(view.x * 0.5, (60.0 + (40.0 if GameState.nvg_battery == 1 else 0.0)) * scale_menu))
		_text(font, font_size, "SECONDS", Vector2(view.x * 0.5, (100.0 + (40.0 if GameState.nvg_battery == 1 else 0.0)) * scale_menu))
		if not GameState.nvg_blinking:
			_labels(player, nv, font, font_size, scale_menu)
	for k in 11:
		draw_rect(Rect2(45.0, view.y * 0.5 - k * 20.0, 54.0, 10.0), dark)
	for l in int(floor((nv.power + 50) * 0.01)) + 1:
		if l > 10:
			break
		draw_rect(Rect2(45.0, view.y * 0.5 - l * 20.0, 54.0, 10.0), lit)
	var icons := _battery_icons()
	if icons != null:
		var frame := 1 if kind == 2 else 0
		draw_texture_rect_region(icons, Rect2(40.0, view.y * 0.5 + 30.0, 64.0, 64.0), Rect2(frame * 64.0, 0.0, 64.0, 64.0))
	if GameState.nvg_battery == 1 and int(GameState.clock_ms()) % 800 < 400:
		_text(font, font_size, "WARNING: LOW BATTERY", Vector2(view.x * 0.5, 20.0 * scale_menu), Color.RED)

func _labels(player: CharacterBody3D, nv: Node, font: Font, font_size: int, scale_menu: float) -> void:
	var origin: Vector3 = player.global_position
	var camera_yaw := rad_to_deg(player.rotation.y)
	var camera_pitch := -rad_to_deg(player.camera.rotation.x)     # Blitz pitch: positive looks down
	for entry in nv.snapshot:
		var at: Vector3 = entry.pos
		var distance := origin.distance_to(at)
		if distance >= 23.5:
			continue
		var to := at - origin
		var yaw := rad_to_deg(atan2(-to.x, -to.z))
		var pitch := -rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
		var x := _offset(camera_yaw - yaw)
		var y := _offset(camera_pitch - pitch)
		var point := Vector2(size.x * 0.5 + x * size.x * 0.5, size.y * 0.5 - y * size.y * 0.5)
		_text(font, font_size, str(entry.name), point, Color.WHITE, true)
		_text(font, font_size, "%.1f m" % distance, point + Vector2(0.0, 30.0 * scale_menu), Color.WHITE, true)

# AAText x, y, text, centred (and vertically centred when `middle`)
func _text(font: Font, font_size: int, text: String, at: Vector2, color: Color = Color.WHITE, middle: bool = false) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var top := at.y + (font.get_ascent(font_size) - font.get_height(font_size) * 0.5 if middle else font.get_ascent(font_size))
	draw_string(font, Vector2(at.x - width * 0.5, top), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
