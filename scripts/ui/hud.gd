extends CanvasLayer
# The in-game HUD (Main.bb DrawGUI): blink and stamina meters, the hand icons that point at the
# nearest door button and item, the message line, the inventory screen (Tab) and the item UI
# (gas mask overlay, centred item picture, documents, progress bar). The pause and death panel
# is pause_menu.gd. Layout numbers are the original's screen pixels (UIKit.pixel_scale).

const ItemUseScript = preload("res://scripts/items/item_use.gd")
const KeypadScript = preload("res://scripts/ui/keypad.gd")
const Scp294PanelScript = preload("res://scripts/ui/scp294_panel.gd")
const DrinkEffectsScript = preload("res://scripts/game/drink_effects.gd")
const HudMetersScript = preload("res://scripts/ui/hud_meters.gd")
const InventoryScreenScript = preload("res://scripts/ui/inventory_screen.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")

const SLOT_COUNT := 10
const CONTAINERS := ["clipboard", "wallet"]     # items with a SecondInv of ten slots
const CONTAINER_SLOTS := 10

var items: Array[String] = []
var item_data: Array[Dictionary] = []
var selected := -1
var item_use: Node
var radio_nav: Control               # radio_nav_hud.gd: the radio and the navigators held up
var nv_picture := ""                  # a picture shown in place of the goggles' overlay (SCP-895's horror pictures)
var _nv_path := "GFX/NightVisionOverlay.jpg"
var message_label: Label
var hint_label: Label            # kept for the pick-up prompt; hidden, the hand icon replaces it
var death: Panel                 # kept for scripts that clear it; the death screen is the pause menu
var inventory_open := false
var container_index := -1         # OtherOpen: the slot of the clipboard or wallet whose pockets are shown
var _borrowed := {}                # an item taken out of a container to be used, still kept there: {slots, slot}
var pause_menu: Control
var _message_shadow: Label
var _message_time := 0.0         # seconds
var _textures: Dictionary = {}
var _icon_rect: TextureRect
var _doc_rect: TextureRect
var _doc_code: Label
var _progress_bar: ProgressBar
var _gas_overlay: TextureRect
var _meters: Control            # hud_meters.gd
var _inventory: Control         # inventory_screen.gd
var _blink_rect: ColorRect
var _fade: ColorRect             # darkens the view when the player dies
var _scp294_panel: CanvasLayer
var _dream_blur: DreamBlur          # UpdateBlur(BlurVolume): a compositor effect on the player's camera
var _infect_overlay: TextureRect
var _vignette: TextureRect          # the "Fog" sprite: fog.jpg multiplied over the view
var _vignette_atlas: AtlasTexture
var _vignette_view := Vector2.ZERO
var _vignette_nv := false
var _nv_overlay: TextureRect        # NVOverlay: NightVisionOverlay.jpg multiplied, tinted per goggles
var _nv_atlas: AtlasTexture
var _nv_black: ColorRect            # NVBlink: the goggles' screen blacks out
var _nv_view := Vector2.ZERO
var _gas_atlas: AtlasTexture
var _gas_view := Vector2.ZERO
var _flash: ColorRect             # the white sprite over the camera (Light), used when waking up
var flash_alpha := 0.0

func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	items.resize(SLOT_COUNT)
	item_data.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		items[i] = ""
		item_data[i] = {}
	_blink_rect = ColorRect.new()
	_blink_rect.name = "Blink"
	_blink_rect.color = Color(0, 0, 0, 0)
	_blink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blink_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_blink_rect)
	_build_item_ui()
	_meters = HudMetersScript.new()
	_meters.hud = self
	add_child(_meters)
	message_label = _make_message_label(false)
	_message_shadow = _make_message_label(true)
	move_child(_message_shadow, message_label.get_index())
	hint_label = Label.new()
	hint_label.visible = false
	add_child(hint_label)
	death = Panel.new()
	death.visible = false
	add_child(death)
	item_use = ItemUseScript.new()
	item_use.hud = self
	item_use.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(item_use)
	var keypad := KeypadScript.new()
	keypad.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(keypad)
	_scp294_panel = Scp294PanelScript.new()
	add_child(_scp294_panel)
	add_child(DrinkEffectsScript.new())
	_inventory = InventoryScreenScript.new()
	_inventory.hud = self
	add_child(_inventory)
	_infect_overlay = TextureRect.new()      # InfectOverlay: the green sprite over the view, added to it
	_infect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_infect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_infect_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_infect_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_infect_overlay.texture = _icon("GFX/InfectOverlay.jpg")
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_infect_overlay.material = additive
	_infect_overlay.visible = false
	var overlay_layer := CanvasLayer.new()      # below the HUD: DrawGUI is drawn after the view's overlays
	overlay_layer.layer = layer - 1
	add_child(overlay_layer)
	overlay_layer.add_child(_infect_overlay)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	pause_menu = PauseMenuScript.new()
	pause_menu.resume_requested.connect(close_pause_menu)
	pause_menu.quit_to_menu_requested.connect(_quit_to_menu)
	pause_menu.load_requested.connect(_load_game)
	pause_menu.save_quit_requested.connect(_save_and_quit)
	add_child(pause_menu)
	add_child(AchievementPopups.new())
	GameState.player_died.connect(_on_died)

func _make_message_label(shadow: bool) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIKit.font("regular"))
	label.add_theme_color_override("font_color", Color.BLACK if shadow else Color.WHITE)
	add_child(label)
	return label

func _build_item_ui() -> void:
	_gas_overlay = TextureRect.new()
	_gas_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gas_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gas_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_gas_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gas_overlay.visible = false
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_gas_overlay.material = multiply
	_gas_atlas = AtlasTexture.new()
	_gas_atlas.atlas = _icon("GFX/GasmaskOverlay.jpg")
	_gas_overlay.texture = _gas_atlas
	add_child(_gas_overlay)
	move_child(_gas_overlay, 0)
	_vignette = TextureRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = multiply
	_vignette_atlas = AtlasTexture.new()
	_vignette_atlas.atlas = _icon("GFX/fog.jpg")
	_vignette.texture = _vignette_atlas
	add_child(_vignette)
	move_child(_vignette, 0)
	_nv_overlay = TextureRect.new()
	_nv_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nv_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_nv_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_nv_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nv_overlay.material = multiply
	_nv_atlas = AtlasTexture.new()
	_nv_atlas.atlas = _icon("GFX/NightVisionOverlay.jpg")
	_nv_overlay.texture = _nv_atlas
	_nv_overlay.visible = false
	add_child(_nv_overlay)
	move_child(_nv_overlay, 0)
	_nv_black = ColorRect.new()
	_nv_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nv_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nv_black.color = Color.BLACK
	_nv_black.visible = false
	add_child(_nv_black)
	move_child(_nv_black, 0)
	var nvg_hud := preload("res://scripts/ui/nvg_hud.gd").new()
	add_child(nvg_hud)
	radio_nav = preload("res://scripts/ui/radio_nav_hud.gd").new()
	radio_nav.hud = self
	add_child(radio_nav)
	_icon_rect = TextureRect.new()
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	add_child(_icon_rect)
	_doc_rect = TextureRect.new()
	_doc_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doc_rect.visible = false
	_doc_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_doc_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Magenta (255, 0, 255) is the original's mask colour: drop it in the shader rather than
	# looping over a megapixel image in script.
	var mask_shader := Shader.new()
	mask_shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tif (c.r > 0.96 && c.g < 0.04 && c.b > 0.96) { discard; }\n\tCOLOR = c;\n}\n"
	var mask_material := ShaderMaterial.new()
	mask_material.shader = mask_shader
	_doc_rect.material = mask_material
	add_child(_doc_rect)
	_doc_code = Label.new()
	_doc_code.add_theme_font_size_override("font_size", 28)
	_doc_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doc_rect.add_child(_doc_code)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(300, 20)
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.visible = false
	add_child(_progress_bar)

func _process(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_message_time = maxf(_message_time - delta, 0.0)
	var s := viewport_size.y / 1024.0
	var font_size := UIKit.font_size("regular", s)
	for label in [message_label, _message_shadow]:
		label.add_theme_font_size_override("font_size", font_size)
		label.size = Vector2(viewport_size.x, font_size * 1.6)
	message_label.position = Vector2(0.0, viewport_size.y * 0.5 + 200.0 * s)
	_message_shadow.position = message_label.position + Vector2(1.0, 1.0)
	# Min(MsgTimer / 2, 255) / 255 with MsgTimer in 70 Hz frames
	var alpha := clampf(_message_time * 70.0 / 2.0, 0.0, 255.0) / 255.0
	message_label.modulate.a = alpha
	_message_shadow.modulate.a = alpha
	message_label.visible = _message_time > 0.0
	_message_shadow.visible = message_label.visible
	_message_shadow.text = message_label.text
	_gas_overlay.visible = (GameState.wearing_gas_mask != 0 or GameState.wearing_hazmat != 0 or GameState.wearing_1499 != 0) and _gas_overlay.texture != null
	_update_vignette(viewport_size)
	_progress_bar.position = Vector2(viewport_size.x * 0.5 - 150.0, viewport_size.y * 0.5 + 80.0)
	var player := GameState.player
	if player == null:
		return
	_blink_rect.color.a = player.blink_alpha()
	if GameState.save_type() == 1 and GameState.selected_monitor != null:
		var last := message_label.text
		if (last != "Game progress saved." and last != "You cannot save in this location." and last != "You cannot save at this moment.") or _message_time <= 0.0:
			message("Press F5 to save.", 4.0)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			GameState.selected_monitor = null
	if player.dead:
		_fade.color.a = minf(absf(player.kill_timer / 400.0), 1.0)
		if player.kill_timer < -360.0 and not pause_menu.visible and not ending_active():
			pause_menu.open(PauseMenuScript.Mode.DEAD)
			MouseCapture.release()
	else:
		# darkA: sanity below -200 (up to 0.6) and the fall that 106 starts (Abs(FallTimer / 400))
		var dark := 0.0
		if GameState.light_blink > 0.0:
			dark = minf(maxf(dark, GameState.light_blink * randf_range(0.3, 0.8)), 1.0)
		if GameState.sanity < -200.0:
			dark = maxf(dark, minf((-GameState.sanity - 200.0) / 700.0, 0.6))
			var audio := get_tree().get_first_node_in_group("audio")
			if audio != null:
				audio.heartbeat(minf(absf(GameState.sanity + 200.0) / 500.0, 1.0), 70.0 + absf(GameState.sanity + 200.0) / 6.0)
		if player.fall_timer < 0.0:
			var held := selected_tempname()
			if (held.contains("hazmatsuit") or held.contains("vest")) and GameState.wearing_hazmat == 0 and GameState.wearing_vest == 0:
				drop_selected(player)
			close_inventory()
			selected = -1
			GameState.selected_monitor = null
			GameState.blur_timer = absf(player.fall_timer * 10.0)
			dark =maxf(dark, minf(absf(player.fall_timer) / 400.0, 1.0))
		if GameState.eye_stuck > 0.0 and GameState.eye_stuck < 6000.0:
			dark = minf(maxf(dark, (6000.0 - GameState.eye_stuck) / 5000.0), 1.0)
		if GameState.wearing_night_vision == 0:
			dark = maxf(dark, (1.0 - GameState.secondary_light) * 0.9)      # the power is out
		if screen_open or selected_tempname() in ["nav", "navigator"]:
			dark = maxf(dark, 0.5)      # a monitor or the navigator is held up
		if _scp294_panel.is_open():
			dark = 1.0      # Using294
		_fade.color.a = dark
	_flash.color.a = maxf(flash_alpha, clampf(GameState.light_flash + randf_range(-0.2, 0.2), 0.0, 1.0) if GameState.light_flash > 0.0 else 0.0)
	_infect_overlay.visible = GameState.infect_overlay > 0.002
	_infect_overlay.modulate.a = clampf(GameState.infect_overlay, 0.0, 1.0)
	_update_blur(player)
	_meters.update_hands(player)

# ScaleSprite(Fog, Max(W / 1240, 1), Max(H / 960 * 0.8, 0.8)) one unit from a 90 degree camera: the sprite is a little
# wider than the view and much taller, so the view shows the middle of the picture. Hidden where the original hides it
# (the intro chamber, gate A and gate B's surface).
func _update_vignette(view: Vector2) -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var player := GameState.player
	var shown: bool = facility != null and facility.active
	if shown and player != null:
		var room: String = facility.room_name_at(player.global_position)
		if room == "gatea" or (room == "exit1" and player.global_position.y > 1040.0 * 8.0 / 2048.0):
			shown = false
	var goggles := GameState.wearing_night_vision != 0
	if goggles != _vignette_nv:
		_vignette_nv = goggles
		_vignette_atlas.atlas = _icon("GFX/fogNV.jpg" if goggles else "GFX/fog.jpg")
		_vignette_view = Vector2.ZERO
	_vignette.visible = shown and _vignette_atlas.atlas != null
	if _vignette.visible and view != _vignette_view:
		_vignette_view = view
		_crop(_vignette_atlas, view, 1240.0, 960.0)
	# the gas mask and the goggles' overlays are 1024 sprites
	if view != _gas_view and _gas_atlas.atlas != null:
		_gas_view = view
		_crop(_gas_atlas, view, 1024.0, 1024.0)
	var wanted_overlay := nv_picture if not nv_picture.is_empty() else "GFX/NightVisionOverlay.jpg"
	if wanted_overlay != _nv_path:
		_nv_path = wanted_overlay
		_nv_atlas.atlas = _icon(wanted_overlay)
		_nv_view = Vector2.ZERO
	_nv_overlay.visible = goggles and _nv_atlas.atlas != null
	if _nv_overlay.visible:
		_nv_overlay.modulate = [Color8(0, 255, 0), Color8(0, 100, 255), Color8(255, 0, 0)][GameState.wearing_night_vision - 1]
		if view != _nv_view:
			_nv_view = view
			_crop(_nv_atlas, view, 1024.0, 1024.0)
	_nv_black.visible = GameState.nvg_blinking and goggles

# A sprite one unit from a 90 degree camera, scaled Max(W / wdiv, 1) x Max(H / hdiv * 0.8, 0.8): the picture shows from its
# middle, cropped to what the view sees.
func _crop(atlas: AtlasTexture, view: Vector2, wdiv: float, hdiv: float) -> void:
	var half_width := maxf(view.x / wdiv, 1.0)
	var half_height := maxf(view.y / hdiv * 0.8, 0.8)
	var seen_x := 1.0 / half_width
	var seen_y := minf((view.y / view.x) / half_height, 1.0)
	var size := atlas.atlas.get_size()
	atlas.region = Rect2(size.x * (1.0 - seen_x) * 0.5, size.y * (1.0 - seen_y) * 0.5, size.x * seen_x, size.y * seen_y)

func message_time_left() -> float:
	return _message_time

func message(text: String, seconds: float = 5.0) -> void:
	message_label.text = text
	_message_shadow.text = text
	_message_time = seconds

func open_inventory() -> void:
	if inventory_open or (item_use != null and item_use.locks_movement()):
		return
	if GameState.is_zombie or GameState.unable_to_move:
		return     # (Not UnableToMove) And (Not IsZombie)
	inventory_open = true
	_inventory.visible = true
	_inventory.reset()
	get_tree().paused = true
	MouseCapture.release()

func close_inventory() -> void:
	if not inventory_open:
		return
	inventory_open = false
	container_index = -1
	_inventory.container = -1
	_inventory.visible = false
	_inventory.reset()
	get_tree().paused = false
	MouseCapture.capture()

# A double click: the item is used (selected) and the inventory closes.
func use_from_inventory(index: int) -> void:
	close_inventory()
	if GameState.wearing_hazmat > 0 and not str(item_data[index].get("tempname", "")).begins_with("hazmatsuit"):
		message("You cannot use any items while wearing a hazmat suit.")
		return
	_item_sound(items[index])
	set_selected(index)

# Dragging onto another slot: an empty one takes the item, an occupied one is a combine attempt (Main.bb DrawGUI).
func swap_items(a: int, b: int) -> void:
	if not items[b].is_empty():
		combine_items(a, b)
		return
	var name_a := items[a]
	var data_a := item_data[a]
	items[a] = items[b]
	item_data[a] = item_data[b]
	items[b] = name_a
	item_data[b] = data_a
	if selected == a:
		selected = b
	elif selected == b:
		selected = a

# Released outside the slots: the item is dropped (worn suits and vests have to be taken off).
func drop_from_inventory(index: int) -> void:
	var player := GameState.player
	if player == null:
		return
	var tempname := str(item_data[index].get("tempname", ""))
	if tempname in ["vest", "finevest", "hazmatsuit", "hazmatsuit2", "hazmatsuit3"] and _inventory.is_worn(tempname):
		message("Double click on this item to take it off.")
		return
	if tempname in ["scp1499", "super1499"] and GameState.wearing_1499 > 0:
		message("Double click on this item to take it off.")
		return
	var previous := selected
	selected = index
	close_inventory()
	drop_selected(player)
	if previous != index and previous >= 0 and not items[previous].is_empty():
		selected = previous

func selected_tempname() -> String:
	if selected < 0 or items[selected].is_empty():
		return ""
	return str(item_data[selected].get("tempname", ""))

# Selecting is what the original's click does: the item's rules run (item_use.gd).
# Selecting the selected item again puts it away.
func set_selected(index: int) -> void:
	if index == selected:
		deselect()
		return
	_return_borrowed()
	selected = index
	item_use.on_selected()

func deselect() -> void:
	selected = -1
	item_use.on_deselected()
	_return_borrowed()

# RemoveItem: consumed or destroyed.
func remove_selected() -> void:
	if selected >= 0:
		items[selected] = ""
		item_data[selected] = {}
	deselect()

func try_pickup(node: Node) -> bool:
	for i in SLOT_COUNT:        # not the hidden slot an item taken out of a container is borrowed into
		if items[i].is_empty():
			if str(node.get_meta("tempname", "")) == "paper":
				GameState.docs_found[str(node.get_meta("item_name", ""))] = true     # ItemTemplates\found
			var data := {
				"tempname": str(node.get_meta("tempname", "paper")),
				"icon": str(node.get_meta("icon", "GFX/items/INVpaper.png")),
				"state": float(node.get_meta("state", 0.0)),     # the goggles' battery
			}
			for key in ["cr", "cg", "cb", "ca"]:
				if node.has_meta(key):
					data[key] = float(node.get_meta(key))      # what a cup holds
			_pickup_achievement(data.tempname, str(node.get_meta("item_name", "")))
			if data.tempname in CONTAINERS:
				data["inv"] = node.get_meta("inv", _blank_slots())
				data["pose"] = float(node.get_meta("pose", WorldItem.CREATED_POSE[data.tempname]))
			items[i] = str(node.get_meta("item_name", "Paper"))
			item_data[i] = data
			_refresh_container_icons()
			_item_sound(items[i])
			return true
	message("You cannot carry any more items.")
	return false

func _pickup_achievement(tempname: String, item_name: String) -> void:
	match tempname:
		"scp148":
			GameState.give_achievement("148")
		"scp513":
			GameState.give_achievement("513")
		"scp860":
			GameState.give_achievement("860")
		"key6":
			GameState.give_achievement("omni")
		"navigator", "nav":
			if item_name == "S-NAV Navigator Ultimate":
				GameState.give_achievement("snav")

# DropItem: the item appears at the camera, 0.1 down and 0.1 ahead, with a random yaw
# (camera yaw +- 110), and then falls like any other world item.
func drop_selected(player: Node3D) -> void:
	if selected < 0 or items[selected].is_empty():
		return
	if GameState.wearing_hazmat > 0:
		message("You cannot drop any items while wearing a hazmat suit.")
		return
	var data: Dictionary = item_data[selected]
	_item_sound(items[selected])
	var pickup := RoomFill.make_pickup(items[selected], str(data.tempname), data)
	pickup.set_meta("dropped", true)        # it\Dropped = 1
	player.get_parent().add_child(pickup)
	var camera: Camera3D = player.camera
	pickup.global_position = camera.global_position + camera.global_transform.basis * Vector3(0.0, -0.1, -0.1)
	pickup.rotation.y = player.rotation.y + deg_to_rad(randf_range(-110.0, 110.0))
	pickup.set_meta("state", float(data.get("state", 0.0)))
	match str(data.tempname):
		"gasmask", "supergasmask", "gasmask3":
			GameState.wearing_gas_mask = 0
		"vest", "finevest":
			GameState.wearing_vest = 0
		"nvgoggles", "supernv":
			GameState.wearing_night_vision = 0     # DropItem (the very fine ones stay on, as in the original)
		"scp1499", "super1499":
			GameState.wearing_1499 = 0
	remove_selected()

# The pick-up hint is the hand icon now; the text stays available to scripts.
func set_hint(text: String) -> void:
	hint_label.text = text

func hide_item_ui() -> void:
	_icon_rect.visible = false
	_doc_rect.visible = false
	_doc_code.text = ""
	_progress_bar.visible = false

func show_item_icon(relative: String) -> void:
	var texture := _icon(relative)
	if texture == null:
		return
	_icon_rect.texture = texture
	# the pictures are 64 px in the original (the files here are larger)
	var icon_size := Vector2(64.0, 64.0) * UIKit.pixel_scale(self)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_icon_rect.size = icon_size
	var viewport_size := get_viewport().get_visible_rect().size
	_icon_rect.position = viewport_size * 0.5 - icon_size * 0.5
	_icon_rect.visible = true

func set_progress(value: float) -> void:
	_progress_bar.value = value
	_progress_bar.visible = true

# The document picture is drawn centred at MenuScale (screen height / 1024), magenta masked; the Burnt Note and the Movie
# Ticket are not resized and keep their pixel size. Two documents have the run's access code written on them (Main.bb, "paper").
const NATIVE_SIZE_DOCUMENTS := ["Burnt Note", "Movie Ticket"]

func show_document(image_relative: String, document_name: String) -> void:
	var path := ContentPaths.existing_image(image_relative)
	if not FileAccess.file_exists(path):
		message("The document cannot be read.")
		return
	var image := MeshLoader.load_image(path)     # the Burnt Note's bn.it is a JPEG
	if image == null:
		message("The document cannot be read.")
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var pixel := UIKit.pixel_scale(self)
	var screen_height := viewport_size.y / pixel
	var menu_scale := viewport_size.y / 1024.0
	var scale_value := pixel if document_name in NATIVE_SIZE_DOCUMENTS else menu_scale
	var size_value := Vector2(image.get_width(), image.get_height()) * scale_value
	_icon_rect.visible = false
	_doc_rect.texture = ImageTexture.create_from_image(image)
	_doc_rect.size = size_value
	_doc_rect.position = viewport_size * 0.5 - size_value * 0.5
	_doc_code.text = ""
	match document_name:
		"Document SCP-372":
			var code := (int(GameState.access_code) * 3) % 10000
			if code < 1000:
				code += 1000
			# Font5: Journal at Int(58 * GraphicHeight / 1024) pixels
			_place_code(str(code), Vector2(383.0, 734.0) * menu_scale, Color8(37, 45, 137), "journal", int(58.0 * screen_height / 1024.0) * pixel)
		"Burnt Note":
			# written into the unscaled picture with Font1: Courier New at Int(19 * GraphicHeight / 1024) pixels
			_place_code(GameState.access_code, Vector2(277.0, 469.0) * pixel, Color.BLACK, "regular", UIKit.courier_size(int(19.0 * screen_height / 1024.0)) * pixel)
	_doc_rect.visible = true

func _place_code(text: String, centre: Vector2, color: Color, font_kind: String, font_size: float) -> void:
	_doc_code.text = text
	_doc_code.add_theme_color_override("font_color", color)
	_doc_code.add_theme_font_override("font", UIKit.font(font_kind))
	_doc_code.add_theme_font_size_override("font_size", maxi(int(round(font_size)), 1))
	_doc_code.reset_size()
	_doc_code.position = centre - _doc_code.size * 0.5

func _icon(relative: String) -> Texture2D:
	if relative.is_empty():
		return null
	if _textures.has(relative):
		return _textures[relative]
	var path := ContentPaths.existing_image(relative)
	var texture: Texture2D = null
	if FileAccess.file_exists(path):
		var image := MeshLoader.load_image(path)
		if image != null:
			texture = ImageTexture.create_from_image(image)
	_textures[relative] = texture
	return texture

func open_pause_menu() -> void:
	if pause_menu.visible or inventory_open:
		return
	pause_menu.open(PauseMenuScript.Mode.PAUSED)
	get_tree().paused = true
	MouseCapture.release()

func close_pause_menu() -> void:
	pause_menu.close()
	get_tree().paused = false
	if GameState.player != null and not GameState.player.dead:
		MouseCapture.capture()

func _quit_to_menu(after_ending := false) -> void:
	get_tree().paused = false
	pause_menu.close()
	get_tree().root.get_node("Main").return_to_menu(after_ending)

# KillTimer: the view darkens, then the panel with the cause of death comes up.
func _on_died(msg: String) -> void:
	close_inventory()
	pause_menu.death_message = msg

# The console's revive: the dying view and the panel that was about to come up are gone.
func cancel_death() -> void:
	_fade.color.a = 0.0
	death.visible = false
	pause_menu.close()

const EndingScreenScript = preload("res://scripts/ui/ending_screen.gd")
var ending_screen: Control = null

# SelectedEnding = code, KillTimer = -0.1: the death fade, then the ending screen, the panel and the credits.
func start_ending(code: String) -> void:
	if ending_screen == null:
		ending_screen = EndingScreenScript.new()
		ending_screen.finished.connect(func() -> void: _quit_to_menu(true))
		pause_menu.end_continue_requested.connect(func() -> void: ending_screen.ending_timer = -2000.0)
		add_child(ending_screen)
	GameState.give_achievement("055")
	if GameState.difficulty == 2:
		GameState.give_achievement("keter")
	if not GameState.used_console:
		GameState.give_achievement("console")
	close_inventory()
	pause_menu.close()
	ending_screen.start(code)

func open_end_panel() -> void:
	pause_menu.z_index = 100       # over the ending picture
	pause_menu.open(PauseMenuScript.Mode.END)

func close_end_panel() -> void:
	pause_menu.close()
	pause_menu.z_index = 0

func ending_active() -> bool:
	return ending_screen != null and ending_screen.active

func _unhandled_input(event: InputEvent) -> void:
	if ending_active():
		return
	if GameState.player == null:
		return
	var dead: bool = GameState.player.dead
	if screen_open:
		if event.is_action_pressed("quick_save"):
			quick_save()
		elif (event is InputEventMouseButton and event.pressed) or event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			close_screen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not dead:
		if pause_menu.visible:
			close_pause_menu()
		elif inventory_open:
			close_inventory()
		else:
			open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if dead:
		return
	if event.is_action_pressed("quick_save") and not pause_menu.visible and not inventory_open:
		quick_save()
		return
	if event.is_action_pressed("inventory") and not pause_menu.visible:
		if inventory_open:
			close_inventory()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
		return
	if inventory_open or pause_menu.visible:
		return
	# the original has no item hotkeys: the number keys only change the radio's channel while it is held
	if event is InputEventKey and event.pressed and not event.echo:
		radio_nav.handle_key(event.keycode)

func _item_sound(item_name: String) -> void:
	var audio := get_tree().get_first_node_in_group("audio")
	if audio:
		audio.play_item_sound(item_name)

func _main() -> Node:
	return get_tree().root.get_node("Main")

func _load_game() -> void:
	get_tree().paused = false
	pause_menu.close()
	_main().load_game_with_loading()

func _save_and_quit() -> void:
	if _main().save_game():
		_quit_to_menu()

func _play_save_sound() -> void:
	Sfx.play_global(self, "SFX/General/Save2.ogg" if GameState.save_type() == 1 else "SFX/General/Save1.ogg")

# The quick-save key (KEY_SAVE) and the messages of the three save types.
func quick_save() -> void:
	match GameState.save_type():
		0:
			if not PauseMenuScript.can_save_here():
				message("You cannot save in this location.", 4.0)
			elif _main().save_game():
				_play_save_sound()
				message("Game progress saved.", 4.0)
			else:
				message("You cannot save at this moment.", 4.0)
		1:
			if not screen_open and GameState.selected_monitor == null:
				message("Saving is only permitted on clickable monitors scattered throughout the facility.", 4.0)
			elif not PauseMenuScript.can_save_here():
				message("You cannot save in this location.", 4.0)
			elif _main().save_game():
				_play_save_sound()
				message("Game progress saved.", 4.0)
			else:
				message("You cannot save at this moment.", 4.0)
		_:
			message("Quick saving is disabled.", 4.0)

# ---- screens (SelectedScreen) --------------------------------------------------------------

var screen_open := false
var _screen_rect: TextureRect

# A picture shown at MenuScale, magenta masked; the game stands still until a click closes it.
# On Euclid this is also where the game can be saved.
func show_screen(image_relative: String) -> void:
	if screen_open or pause_menu.visible or inventory_open:
		return
	var path := ContentPaths.existing_image(image_relative)
	if not FileAccess.file_exists(path):
		return
	var image := MeshLoader.load_image(path)
	if image == null:
		return
	if _screen_rect == null:
		_screen_rect = TextureRect.new()
		_screen_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_screen_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_rect.material = _doc_rect.material
		add_child(_screen_rect)
	var view := get_viewport().get_visible_rect().size
	var scaled := Vector2(image.get_width(), image.get_height()) * (view.y / 1024.0)
	_screen_rect.texture = ImageTexture.create_from_image(image)
	_screen_rect.size = scaled
	_screen_rect.position = view * 0.5 - scaled * 0.5
	_screen_rect.visible = true
	screen_open = true
	_play_button()
	get_tree().paused = true
	MouseCapture.release()
	if GameState.save_type() == 1:
		message("Press F5 to save.", 4.0)

func close_screen() -> void:
	if not screen_open:
		return
	screen_open = false
	_screen_rect.visible = false
	get_tree().paused = false
	MouseCapture.capture()

func _play_button() -> void:
	Sfx.play_global(self, "SFX/Interact/Button.ogg")

func _update_blur(player: Node3D) -> void:
	if OS.has_feature("web"):
		return
	if _dream_blur == null:
		_dream_blur = DreamBlur.new()
		var compositor := Compositor.new()
		compositor.compositor_effects = [_dream_blur]
		(player.get("camera") as Camera3D).compositor = compositor
	_dream_blur.volume = GameState.blur_volume

# The item in slot a dropped on the item in slot b. Only batteries into the navigator, the radio and the night vision goggles
# combine; papers, cards, keys and coins go into the clipboard and the wallet.
func combine_items(a: int, b: int) -> void:
	var dragged := str(item_data[a].get("tempname", ""))
	if str(item_data[b].get("tempname", "")) in CONTAINERS and dragged in ["paper", "key1", "key2", "key3", "key4", "key5", "key6", "misc", "oldpaper", "badge", "ticket", "25ct", "coin", "key", "scp860"]:
		_put_in_container(a, b)
		return
	var target_name := items[b]
	var target := str(item_data[b].get("tempname", ""))
	var text := "You cannot combine these two items."
	var consumed := false
	match dragged:
		"bat":
			match target_name:
				"S-NAV Navigator", "S-NAV 300 Navigator", "S-NAV 310 Navigator":
					item_data[b]["state"] = 100.0
					text = "You replaced the navigator's battery."
					consumed = true
				"S-NAV Navigator Ultimate":
					text = "There seems to be no place for batteries in this navigator."
				"Radio Transceiver":
					match target:
						"fineradio", "veryfineradio":
							text = "There seems to be no place for batteries in this radio."
						"18vradio":
							text = "The battery does not fit inside this radio."
						"radio":
							item_data[b]["state"] = 100.0
							text = "You replaced the radio's battery."
							consumed = true
				"Night Vision Goggles":
					if target == "nvgoggles" or target == "supernv":
						item_data[b]["state"] = 1000.0
						text = "You replaced the goggles' battery."
						consumed = true
					else:
						text = "There seems to be no place for batteries in these night vision goggles."
		"18vbat":
			match target_name:
				"S-NAV Navigator", "S-NAV 300 Navigator", "S-NAV 310 Navigator":
					text = "The battery does not fit inside this navigator."
				"S-NAV Navigator Ultimate":
					text = "There seems to be no place for batteries in this navigator."
				"Radio Transceiver":
					match target:
						"fineradio", "veryfineradio":
							text = "There seems to be no place for batteries in this radio."
						"18vradio":
							item_data[b]["state"] = 100.0
							text = "You replaced the radio's battery."
							consumed = true
	if consumed:
		_item_sound(items[a])
		items[a] = ""
		item_data[a] = {}
		if selected == a:
			selected = -1
	message(text, 5.0)

# ---- the clipboard and the wallet (SecondInv / OtherOpen) -------------------------------------

func _blank_slots() -> Array:
	var slots: Array = []
	for i in CONTAINER_SLOTS:
		slots.append({})
	return slots

# The ten pockets of the container in inventory slot `index`: {} or {name, data}.
func container_slots(index: int) -> Array:
	var data: Dictionary = item_data[index]
	if not data.has("inv"):
		data["inv"] = _blank_slots()
	return data["inv"]

# The clipboard shows INVclipboard2 while it holds nothing (CreateItem, and when the last item is taken out); an emptied
# container goes back to its created pose (Main.bb 5196-5210).
func _refresh_container_icons() -> void:
	for i in items.size():
		var tempname := str(item_data[i].get("tempname", ""))
		if items[i].is_empty() or not tempname in CONTAINERS:
			continue
		var empty := true
		for entry in container_slots(i):
			if not (entry as Dictionary).is_empty():
				empty = false
		if empty:
			item_data[i]["pose"] = WorldItem.CREATED_POSE[tempname]
		if tempname == "clipboard":
			item_data[i]["icon"] = "GFX/items/INVclipboard2.jpg" if empty else "GFX/items/INVclipboard.jpg"

# Using the clipboard or the wallet shows its pockets (the Default case: OtherOpen = SelectedItem).
func open_container(index: int) -> void:
	deselect()
	if GameState.player == null or inventory_open:
		return
	container_slots(index)
	container_index = index
	inventory_open = true
	_inventory.container = index
	_inventory.visible = true
	_inventory.reset()
	get_tree().paused = true
	MouseCapture.release()

# A double click on a pocket: the item is selected from where it lies (a document is read, a card shown) and stays there.
func use_from_container(slot: int) -> void:
	var slots := container_slots(container_index)
	var entry: Dictionary = slots[slot]
	close_inventory()
	if entry.is_empty():
		return
	if GameState.wearing_hazmat > 0:
		message("You cannot use any items while wearing a hazmat suit.")
		return
	_item_sound(str(entry.name))
	_return_borrowed()
	items.append(str(entry.name))
	item_data.append(entry.data)
	_borrowed = {"slots": slots, "slot": slot}
	selected = items.size() - 1
	item_use.on_selected()

func _return_borrowed() -> void:
	if _borrowed.is_empty():
		return
	var borrowed := _borrowed
	_borrowed = {}
	if items.size() > SLOT_COUNT:
		if items[SLOT_COUNT].is_empty():
			(borrowed.slots as Array)[int(borrowed.slot)] = {}      # it was used up
		items.resize(SLOT_COUNT)
		item_data.resize(SLOT_COUNT)
	if selected >= SLOT_COUNT:
		selected = -1
	_refresh_container_icons()

# Released outside the pockets: the item is dropped in front of the player and the pockets close.
func drop_from_container(slot: int) -> void:
	var slots := container_slots(container_index)
	var entry: Dictionary = slots[slot]
	var player := GameState.player
	close_inventory()
	if entry.is_empty() or player == null:
		return
	slots[slot] = {}
	_item_sound(str(entry.name))
	var pickup := RoomFill.make_pickup(str(entry.name), str(entry.data.get("tempname", "")), entry.data)
	pickup.set_meta("dropped", true)
	player.get_parent().add_child(pickup)
	var camera: Camera3D = player.camera
	pickup.global_position = camera.global_position + camera.global_transform.basis * Vector3(0.0, -0.1, -0.1)
	pickup.rotation.y = player.rotation.y + deg_to_rad(randf_range(-110.0, 110.0))
	pickup.set_meta("state", float(entry.data.get("state", 0.0)))
	_refresh_container_icons()

# A paper, card, key or coin dragged onto the clipboard or the wallet (Main.bb, the Case "paper", "key1"... block).
func _put_in_container(a: int, b: int) -> bool:
	var dragged := str(item_data[a].get("tempname", ""))
	var name_a := items[a]
	var card := name_a == "Playing Card" or name_a == "Mastercard"
	var clipboard := str(item_data[b].tempname) == "clipboard"
	var allowed := false
	if clipboard:
		allowed = not (dragged in ["misc", "25ct", "coin", "key", "scp860", "scp714"]) or card
	else:
		allowed = not (dragged in ["misc", "paper", "oldpaper"]) or card
	if not allowed:
		message("You cannot combine these two items.", 5.0)
		return true
	var slots := container_slots(b)
	for c in slots.size():
		if (slots[c] as Dictionary).is_empty():
			slots[c] = {"name": name_a, "data": item_data[a]}
			if clipboard:
				item_data[b]["pose"] = 0.0
			elif not (dragged in ["25ct", "coin", "key", "scp860"]):
				item_data[b]["pose"] = 3.0
			_item_sound(name_a)
			items[a] = ""
			item_data[a] = {}
			if selected == a:
				selected = -1
			_refresh_container_icons()
			if clipboard:
				if dragged == "paper" or dragged == "oldpaper":
					message("This document was added to the clipboard.", 5.0)
				elif dragged == "badge":
					message(name_a + " was added to the clipboard.", 5.0)
				else:
					message("The " + name_a + " was added to the clipboard.", 5.0)
			else:
				message("You put " + name_a + " into the wallet.", 5.0)
			return true
	message("The paperclip is not strong enough to hold any more items." if clipboard else "The wallet is full.", 5.0)
	return true
