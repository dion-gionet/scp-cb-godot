extends Control
# DrawMenu: the pause picture in the middle, a title at its top and a column of buttons. The same
# panel is the death screen ("YOU DIED", the cause of death, Load Game greyed out, Quit to Menu).

signal resume_requested
signal quit_to_menu_requested
signal load_requested
signal save_quit_requested
signal end_continue_requested


enum Mode { PAUSED, OPTIONS, QUIT, DEAD, END, ACHIEVEMENTS }

var mode := Mode.PAUSED
var death_message := ""
var _options_tab := 0
var achievements_page := 1
var _achievements_from := Mode.PAUSED
var _nodes: Array[Node] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	resized.connect(rebuild)

func open(new_mode: int = Mode.PAUSED) -> void:
	mode = new_mode
	visible = true
	rebuild()

func open_achievements() -> void:
	achievements_page = 1
	_achievements_from = mode
	mode = Mode.ACHIEVEMENTS
	rebuild()

func close() -> void:
	visible = false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))
	var texture := UIKit.texture("GFX/menu/pausemenu.jpg")
	if texture == null:
		return
	var s := UIKit.menu_scale(self)
	var image_size := texture.get_size() * s
	draw_texture_rect(texture, Rect2((size - image_size) * 0.5, image_size), false)

func rebuild() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	if not visible:
		return
	queue_redraw()
	var texture := UIKit.texture("GFX/menu/pausemenu.jpg")
	var s := UIKit.menu_scale(self)
	var image_size := texture.get_size() * s if texture != null else Vector2(500, 700) * s
	var origin := (size - image_size) * 0.5
	var x := origin.x + 132.0 * s
	var y := origin.y + 122.0 * s
	var title := ""
	match mode:
		Mode.PAUSED:
			title = "PAUSED"
		Mode.OPTIONS:
			title = "OPTIONS"
		Mode.QUIT:
			title = "QUIT?"
		Mode.DEAD:
			title = "YOU DIED"
		Mode.END:
			title = "THE END"
		Mode.ACHIEVEMENTS:
			title = "ACHIEVEMENTS"
	_text(title, Vector2(x, y - (122.0 - 45.0) * s), true, s)
	var width := 390.0 * s
	var height := 60.0 * s
	match mode:
		Mode.PAUSED:
			_text("Difficulty: %s" % ["Safe", "Euclid", "Keter", "Custom"][clampi(GameState.difficulty, 0, 3)], Vector2(x, y), false, s)
			_text("Save: %s" % GameState.save_name, Vector2(x, y + 20.0 * s), false, s)
			_text("Map seed: %s" % str(_seed()), Vector2(x, y + 40.0 * s), false, s)
			var by := y + 10.0 + 72.0 * s
			_button("Resume", Rect2(x, by, width, height)).pressed.connect(func() -> void: resume_requested.emit())
			by += 75.0 * s
			var load_button := _button("Load Game", Rect2(x, by, width, height))
			load_button.locked = not (SaveGame.exists() and not GameState.perma_death())
			load_button.pressed.connect(func() -> void: load_requested.emit())
			by += 75.0 * s
			_button("Options", Rect2(x, by, width, height)).pressed.connect(func() -> void: mode = Mode.OPTIONS; rebuild())
			by += 75.0 * s
			_button("Achievements", Rect2(x, by, width, height)).pressed.connect(open_achievements)
			by += 75.0 * s
			_button("Quit", Rect2(x, by, width, height)).pressed.connect(func() -> void: mode = Mode.QUIT; rebuild())
		Mode.OPTIONS:
			var panel := OptionsPanel.new()
			panel.layout = OptionsPanel.Layout.PAUSE
			panel.anchor = Vector2(x, y)
			panel.tab = _options_tab
			add_child(panel)
			_nodes.append(panel)
			panel.rebuild()
			_button("Back", Rect2(x + 101.0 * s, y + 390.0 * s, 230.0 * s, height)).pressed.connect(func() -> void:
				_options_tab = panel.tab
				GameState.save_settings()
				mode = Mode.PAUSED
				rebuild())
		Mode.ACHIEVEMENTS:
			var panel := AchievementsPanel.new()
			panel.anchor = Vector2(x, y)
			panel.page = achievements_page
			panel.z_index = 1     # AchievementTooltip is drawn after Back, < and > (Main.bb 7623-7655), so it covers them
			add_child(panel)
			_nodes.append(panel)
			_button("Back", Rect2(x + 101.0 * s, y + 344.0 * s, 230.0 * s, height)).pressed.connect(func() -> void: mode = _achievements_from; rebuild())
			if achievements_page < AchievementsPanel.last_page():
				_button(">", Rect2(x + 341.0 * s, y + 344.0 * s, 50.0 * s, height)).pressed.connect(func() -> void: achievements_page += 1; rebuild())
			if achievements_page > 1:
				_button("<", Rect2(x + 41.0 * s, y + 344.0 * s, 50.0 * s, height)).pressed.connect(func() -> void: achievements_page -= 1; rebuild())
		Mode.QUIT:
			# Save & Quit where the difficulty allows saving and the place is not the 173 area or a gate
			var can_save := GameState.save_type() != 1 and can_save_here()
			var quit_y := 60.0 * s
			if can_save:
				_button("Save & Quit", Rect2(x, y + 60.0 * s, width, height)).pressed.connect(func() -> void: save_quit_requested.emit())
				quit_y = 140.0 * s
			else:
				_text("Unsaved progress will be lost.", Vector2(x, y), false, s)
			_button("Quit", Rect2(x, y + quit_y, width, height)).pressed.connect(func() -> void: quit_to_menu_requested.emit())
			_button("Back", Rect2(x + 101.0 * s, y + 344.0 * s, 230.0 * s, height)).pressed.connect(func() -> void: mode = Mode.PAUSED; rebuild())
		Mode.END:
			var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
			var rooms_total: int = facility.generator.rooms.size() if facility != null and facility.generator != null else 0
			var docs_total := 0
			for template in GameState.docs_templates():
				docs_total += 1
			var lines := [
				"SCPs encountered: %d" % GameState.scps_encountered(),
				"Achievements unlocked: %d/%d" % [GameState.achievements_unlocked(), GameState.MAX_ACHIEVEMENTS],
				"Rooms found: %d/%d" % [GameState.rooms_found.size(), rooms_total],
				"Documents discovered: %d/%d" % [GameState.docs_found.size(), docs_total],
				"Items refined in SCP-914: %d" % GameState.refined_items,
			]
			for i in lines.size():
				_text(lines[i], Vector2(x, y + 20.0 * s * i), false, s)
			_button("ACHIEVEMENTS", Rect2(x, origin.y + image_size.y - 300.0 * s, width, height)).pressed.connect(open_achievements)
			_button("MAIN MENU", Rect2(x, origin.y + image_size.y - 200.0 * s, width, height)).pressed.connect(func() -> void: end_continue_requested.emit())
		Mode.DEAD:
			var dy := y + 10.0 + 104.0 * s
			var load_dead := _button("Load Game", Rect2(x, dy, width, height))
			load_dead.locked = not (SaveGame.exists() and not GameState.perma_death())
			load_dead.pressed.connect(func() -> void: load_requested.emit())
			_button("Quit to Menu", Rect2(x, dy + 80.0 * s, width, height)).pressed.connect(func() -> void: quit_to_menu_requested.emit())
			var message := _text(death_message, Vector2(x, dy + 160.0 * s), false, s)
			message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message.custom_minimum_size = Vector2(width, 0.0)
			message.size = Vector2(width, 400.0 * s)
			# RowText steps AAStringHeight (Font1's 19 cell) + 1 a line
			var used := UIKit.font("regular")
			message.add_theme_constant_override("line_spacing", int(round(20.0 * s - used.get_height(UIKit.font_size("regular", s)))))

func _seed() -> Variant:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null and facility.generator != null:
		return facility.generator.seed_value
	return "-"

func _button(text: String, rect: Rect2) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.big = true
	button.position = rect.position
	button.size = rect.size
	add_child(button)
	_nodes.append(button)
	return button

func _text(value: String, position_value: Vector2, big: bool, s: float) -> Label:
	var label := Label.new()
	label.text = value
	label.position = position_value
	label.add_theme_font_override("font", UIKit.font("bold") if big else UIKit.font("regular"))
	label.add_theme_font_size_override("font_size", UIKit.font_size("bold" if big else "regular", s))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_nodes.append(label)
	return label

# SaveGame is refused in the 173 chamber and on the surface of gate B / gate A.
static func can_save_here() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var facility := tree.get_first_node_in_group("facility") as FacilityMap if tree != null else null
	var player: Node3D = GameState.player
	if facility == null or player == null or GameState.save_blocked:
		return false
	var room_name: String = facility.room_name_at(player.global_position)
	if room_name == "173" or room_name == "gatea":
		return false
	if room_name == "exit1" and player.global_position.y > 1040.0 * 8.0 / 2048.0:
		return false
	if room_name == "room860" and facility.events.room860.state == 1.0:
		return false      # the forest
	return true
