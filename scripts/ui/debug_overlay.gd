extends Control
# The debug menu (F1) and the developer console (F3, debug_console.gd). Every control of the menu runs a console command, so the
# menu offers what the console does: Player, World, NPCs, Items, Places, Events. F2 god mode, F4 disable lighting, F6 force-spawn
# SCP-106, F7 noclip. The menu frees the mouse (the game goes on behind it; the console stops it).

const DebugConsole = preload("res://scripts/debug/debug_console.gd")

var panel: PanelContainer
var tabs: TabContainer
var console: Control
var status: Label
var fps_label: Label
var hud_label: Label
var info: Label
var _sync: Array = []            # [{box: CheckBox, get: Callable}]
var _item_list: ItemList
var _item_filter: LineEdit
var _room_list: ItemList
var _blit_fields: Array[LineEdit] = []
var _event_fields: Array[LineEdit] = []
var _items: Array = []
var _rooms: Array[String] = []
var hitches: HitchLogger

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("debug_overlay")
	console = DebugConsole.new()
	add_child(console)
	hitches = HitchLogger.new()
	add_child(hitches)
	status = Label.new()
	status.position = Vector2(1000, 8)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	fps_label = Label.new()
	fps_label.position = Vector2(8, 4)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(fps_label)
	hud_label = Label.new()
	hud_label.position = Vector2(8, 28)
	hud_label.add_theme_font_size_override("font_size", 13)
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_label)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 60)
	panel.custom_minimum_size = Vector2(560, 420)
	panel.visible = false
	var column := VBoxContainer.new()
	var title := Label.new()
	title.text = "Debug menu (F1 close, F3 console)   F2 god  F4 unlit  F6 106  F7 noclip"
	column.add_child(title)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 360)
	column.add_child(tabs)
	_build_player_tab()
	_build_world_tab()
	_build_npc_tab()
	_build_item_tab()
	_build_places_tab()
	_build_events_tab()
	info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	column.add_child(info)
	panel.add_child(column)
	add_child(panel)

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	tabs.add_child(scroll)
	return box

func run(command: String, echo: bool = true) -> void:
	console.execute(command, echo)
	var last: Array = console.messages
	if not last.is_empty():
		info.text = str(last[last.size() - 1].text)

func _check(box: Control, text: String, getter: Callable, command: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.set_pressed_no_signal(bool(getter.call()))
	check.toggled.connect(func(on: bool) -> void: run("%s %s" % [command, "on" if on else "off"]))
	box.add_child(check)
	_sync.append({"box": check, "get": getter})

func _button(box: Control, text: String, command: String) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: run(command))
	box.add_child(button)
	return button

func _row(box: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	box.add_child(row)
	return row

func _field(row: HBoxContainer, default_text: String, width: float = 60.0) -> LineEdit:
	var field := LineEdit.new()
	field.text = default_text
	field.custom_minimum_size = Vector2(width, 0)
	row.add_child(field)
	return field

func _command_row(box: Control, label_text: String, default_text: String, button_text: String, command: String, width: float = 80.0) -> void:
	var row := _row(box, label_text)
	var field := _field(row, default_text, width)
	var button := Button.new()
	button.text = button_text
	button.pressed.connect(func() -> void: run("%s %s" % [command, field.text]))
	row.add_child(button)

func _grid(box: Control, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	box.add_child(grid)
	return grid

func _build_player_tab() -> void:
	var box := _page("Player")
	_check(box, "God mode (godmode)", func() -> bool: return GameState.god_mode, "godmode")
	_check(box, "Noclip (noclip)   sprint = fast, crouch = slow", func() -> bool: return GameState.noclip, "noclip")
	_check(box, "Infinite stamina (infinitestamina)", func() -> bool: return GameState.infinite_stamina, "infinitestamina")
	_check(box, "Notarget: NPCs ignore you (notarget)", func() -> bool: return GameState.no_target, "notarget")
	var sanic := CheckBox.new()
	sanic.text = "Super speed (sanic)"
	sanic.set_pressed_no_signal(GameState.super_man)
	sanic.pressed.connect(func() -> void: run("sanic"))
	box.add_child(sanic)
	_sync.append({"box": sanic, "get": func() -> bool: return GameState.super_man})
	_command_row(box, "Noclip speed", "2", "Set", "noclipspeed")
	_command_row(box, "Injuries", "0", "Set", "injure")
	_command_row(box, "Infection", "0", "Set", "infect")
	var row := _row(box, "")
	for pair in [["Heal", "heal"], ["Revive", "revive"], ["Kill", "kill"], ["Status", "status"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func() -> void: run(pair[1]))
		row.add_child(button)
	var coords := _row(box, "Teleport to x y z")
	_blit_fields.clear()
	for i in 3:
		_blit_fields.append(_field(coords, "0", 56.0))
	var go := Button.new()
	go.text = "Go"
	go.pressed.connect(func() -> void: run("tele %s %s %s" % [_blit_fields[0].text, _blit_fields[1].text, _blit_fields[2].text]))
	coords.add_child(go)
	var here := Button.new()
	here.text = "Use mine"
	here.pressed.connect(func() -> void:
		var player: Node3D = GameState.player
		if player != null:
			_blit_fields[0].text = "%.1f" % player.global_position.x
			_blit_fields[1].text = "%.1f" % player.global_position.y
			_blit_fields[2].text = "%.1f" % -player.global_position.z)
	coords.add_child(here)
	_command_row(box, "Blink effect / seconds", "1 10", "Set", "setblinkeffect", 80.0)
	_command_row(box, "SCP-427 timer (seconds)", "0", "Set", "427state")

func _build_world_tab() -> void:
	var box := _page("World")
	var unlit_box := CheckBox.new()
	unlit_box.text = "Disable lighting (F4): every material unlit, no lightmaps"
	unlit_box.toggled.connect(func(on: bool) -> void: _set_unlit(on))
	box.add_child(unlit_box)
	_sync.append({"box": unlit_box, "get": func() -> bool: return unlit})
	var hitch_box := CheckBox.new()
	hitch_box.text = "Log stutters (frames over %d ms) to the console and %s" % [HitchLogger.THRESHOLD_MS, HitchLogger.LOG_PATH]
	hitch_box.toggled.connect(func(on: bool) -> void: hitches.enabled = on)
	box.add_child(hitch_box)
	_sync.append({"box": hitch_box, "get": func() -> bool: return hitches.enabled})
	var fog_box := CheckBox.new()
	fog_box.text = "Fog of war (the original's darkness fog; untick to see far)"
	fog_box.toggled.connect(func(on: bool) -> void: GameState.fog_of_war = on)
	box.add_child(fog_box)
	_sync.append({"box": fog_box, "get": func() -> bool: return GameState.fog_of_war})
	_check(box, "Wireframe (wireframe)", func() -> bool: return GameState.wireframe, "wireframe")
	_check(box, "Hide rooms out of sight (culling); noclip switches it off", func() -> bool:
		var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
		return facility == null or facility.drawing.enabled, "culling")
	var fps_box := CheckBox.new()
	fps_box.text = "Show FPS (showfps)"
	fps_box.pressed.connect(func() -> void: run("showfps"))
	box.add_child(fps_box)
	_sync.append({"box": fps_box, "get": func() -> bool: return GameState.show_fps})
	_check(box, "Debug HUD (debughud)", func() -> bool: return GameState.debug_hud, "debughud")
	_command_row(box, "Camera fog near / far", "15 20", "Set", "camerafog", 80.0)
	_command_row(box, "Gamma (0 - 2)", "1", "Set", "gamma")
	_button(box, "Fog back to normal (camerafog)", "camerafog")
	_button(box, "ASD: god + noclip + wireframe + fog 15/20", "asd")
	_button(box, "ASD2: god + infinite stamina + 173 and 106 off", "asd2")
	_button(box, "Stop all sounds (stopsound)", "stopsound")
	_command_row(box, "Play music (SFX/Music/Custom)", "", "Play", "playmusic", 140.0)
	var gates := _row(box, "Gates")
	for pair in [["Unlock A", "unlockexits a"], ["Unlock B", "unlockexits b"], ["Unlock both", "unlockexits"], ["Warhead lever", "toggle_warhead_lever"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func() -> void: run(pair[1]))
		gates.add_child(button)
func _build_npc_tab() -> void:
	var box := _page("NPCs")
	var spawn := _row(box, "Spawn state")
	var state_field := _field(spawn, "", 60.0)
	var label := Label.new()
	label.text = "(blank = default)"
	spawn.add_child(label)
	var grid := _grid(box, 4)
	for entry in [["008-1", "008zombie"], ["049", "049"], ["049-2", "049-2"], ["096", "096"], ["106", "106"], ["173", "173"], ["966", "966"], ["1499-1", "1499-1"],
			["Class D", "class-d"], ["Guard", "guard"], ["MTF", "mtf"], ["Apache", "apache"]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(func() -> void: run(("spawn %s %s" % [entry[1], state_field.text]).strip_edges()))
		grid.add_child(button)
	box.add_child(HSeparator.new())
	var contained := CheckBox.new()
	contained.text = "SCP-106 contained (disable106 / enable106)"
	contained.toggled.connect(func(on: bool) -> void: run("disable106" if on else "enable106"))
	box.add_child(contained)
	_sync.append({"box": contained, "get": func() -> bool:
		var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
		return facility != null and facility.contained_106})
	var off_173 := CheckBox.new()
	off_173.text = "SCP-173 off (disable173 / enable173)"
	off_173.toggled.connect(func(on: bool) -> void: run("disable173" if on else "enable173"))
	box.add_child(off_173)
	_sync.append({"box": off_173, "get": func() -> bool: return GameState.scp173 != null and GameState.scp173.idle == 3})
	var halloween := CheckBox.new()
	halloween.text = "173 jack-o'-lantern (halloween)"
	halloween.pressed.connect(func() -> void: run("halloween"))
	box.add_child(halloween)
	_sync.append({"box": halloween, "get": func() -> bool: return GameState.halloween})
	var actions := _grid(box, 4)
	for pair in [["173 to me", "teleport173"], ["106 to me", "teleport106"], ["Reset 096", "reset096"], ["Force 106 (F6)", "spawn 106"],
			["173 state", "173state"], ["106 state", "106state"], ["096 state", "096state"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func() -> void: run(pair[1]))
		actions.add_child(button)
	_command_row(box, "173 speed (per frame, 0.38)", "0.38", "Set", "173speed")
	_command_row(box, "106 speed (per frame, 0.012)", "0.012", "Set", "106speed")

func _build_item_tab() -> void:
	var box := _page("Items")
	_item_filter = LineEdit.new()
	_item_filter.placeholder_text = "filter..."
	_item_filter.text_changed.connect(func(_text: String) -> void: _fill_items())
	box.add_child(_item_filter)
	_item_list = ItemList.new()
	_item_list.custom_minimum_size = Vector2(520, 170)
	_item_list.item_activated.connect(func(_i: int) -> void: _spawn_selected_item())
	box.add_child(_item_list)
	_items = RoomFill.spawnable()
	_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) + str(a.tempname) < str(b.name) + str(b.tempname))
	_fill_items()
	var row := _row(box, "")
	var spawn := Button.new()
	spawn.text = "Spawn the selected item (spawnitem)"
	spawn.pressed.connect(_spawn_selected_item)
	row.add_child(spawn)
	var quick := _row(box, "Quick")
	for pair in [["Radio", "spawnradio"], ["NVG", "spawnnvg"], ["S-NAV Ultimate", "spawnnav"], ["SCP-420-J", "scp-420-j"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func() -> void: run(pair[1]))
		quick.add_child(button)
	_command_row(box, "Give achievement (id)", "0", "Give", "giveachievement")

func _fill_items() -> void:
	_item_list.clear()
	var wanted := _item_filter.text.to_lower()
	for entry in _items:
		var label := "%s  [%s]" % [entry.name, entry.tempname]
		if wanted.is_empty() or label.to_lower().contains(wanted):
			_item_list.add_item(label)
			_item_list.set_item_metadata(_item_list.item_count - 1, entry)

func _spawn_selected_item() -> void:
	var picked := _item_list.get_selected_items()
	if picked.is_empty():
		return
	var entry: Dictionary = _item_list.get_item_metadata(picked[0])
	var same_name := 0
	for other in _items:
		if str(other.name) == str(entry.name):
			same_name += 1
	run("spawnitem %s" % str(entry.tempname if same_name > 1 else entry.name).to_lower())

func _build_places_tab() -> void:
	var box := _page("Places")
	_room_list = ItemList.new()
	_room_list.custom_minimum_size = Vector2(520, 220)
	_room_list.item_activated.connect(func(_i: int) -> void: _teleport_selected())
	box.add_child(_room_list)
	var row := _row(box, "")
	var go := Button.new()
	go.text = "Teleport to the selected room (teleport)"
	go.pressed.connect(_teleport_selected)
	row.add_child(go)
	var quick := _row(box, "Quick")
	for pair in [["SCP-895", "teleport 895"], ["SCP-914", "teleport 914"], ["Offices", "teleport offices"], ["MTF leader (tp)", "tp"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(func() -> void: run(pair[1]))
		quick.add_child(button)

func _fill_rooms() -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or facility.generator == null:
		return
	_rooms.clear()
	_room_list.clear()
	for record in facility.generator.rooms:
		var name := str(record.name)
		if not _rooms.has(name):
			_rooms.append(name)
	_rooms.sort()
	for name in _rooms:
		_room_list.add_item(name)

func _teleport_selected() -> void:
	var picked := _room_list.get_selected_items()
	if not picked.is_empty():
		run("teleport %s" % _rooms[picked[0]])

func _build_events_tab() -> void:
	var box := _page("Events")
	var endings := _row(box, "Ending")
	for code in ["a1", "a2", "b1", "b2", "b3"]:
		var button := Button.new()
		button.text = code.to_upper()
		button.pressed.connect(func() -> void:
			panel.visible = false
			run("ending " + code))
		endings.add_child(button)
	var row := _row(box, "Event states of this room")
	_event_fields.clear()
	for i in 3:
		_event_fields.append(_field(row, "keep", 56.0))
	var set_button := Button.new()
	set_button.text = "Set (seteventstate)"
	set_button.pressed.connect(func() -> void: run("seteventstate %s %s %s" % [_event_fields[0].text, _event_fields[1].text, _event_fields[2].text]))
	row.add_child(set_button)
	_button(box, "Camera pick (camerapick)", "camerapick")
	_command_row(box, "Hide distance", "8", "Set", "hidedistance")
	_command_row(box, "Particle emitter id", "0", "Spawn", "spawnparticles")
	var open := Button.new()
	open.text = "Open the console (F3)"
	open.pressed.connect(func() -> void:
		panel.visible = false
		console._toggle())
	box.add_child(open)

func _process(_delta: float) -> void:
	if panel.visible and not GameState.console_enabled:
		panel.visible = false
	var parts: Array[String] = []
	if GameState.god_mode:
		parts.append("GOD")
	if GameState.noclip:
		parts.append("NOCLIP")
	if GameState.infinite_stamina:
		parts.append("STAMINA")
	if GameState.no_target:
		parts.append("NOTARGET")
	status.text = "  ".join(parts)
	status.position.x = maxf(get_viewport_rect().size.x - 280.0, 0.0)
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second() if GameState.show_fps else ""
	hud_label.text = _hud_text() if GameState.debug_hud else ""
	for entry in _sync:
		(entry.box as CheckBox).set_pressed_no_signal(bool(entry.get.call()))
	if panel.visible:
		info.text = _report_text()
		if _room_list.item_count == 0:
			_fill_rooms()

# The debug menu is the port's own (the original has none); it and its keys follow the console option.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not GameState.console_enabled:
		return
	match event.keycode:
		KEY_F1:
			panel.visible = not panel.visible
			var player: Node = GameState.player
			if player and not player.dead:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel.visible else Input.MOUSE_MODE_CAPTURED
		KEY_F2:
			run("godmode", false)
		KEY_F4:
			_set_unlit(not unlit)
		KEY_F7:
			run("noclip", false)
		KEY_F6:
			run("spawn 106", false)

# The debug HUD: the numbers the original's DebugHUD draws, plus the port's.
func _hud_text() -> String:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null:
		return ""
	var pos := player.global_position
	var lines: Array[String] = []
	lines.append("Player Position: (%.2f, %.2f, %.2f)  speed %.2f" % [pos.x, pos.y, -pos.z, player.curr_speed / 70.0])
	lines.append("Room: %s   zone %d   seed %d" % [facility.room_name_at(pos), facility.zone_at(pos), facility.generator.seed_value])
	lines.append("Stamina %.1f  blink %.1f  injuries %.2f  bloodloss %.1f  infect %.1f" % [player.stamina, player.blink_timer, GameState.injuries, GameState.bloodloss, GameState.infect])
	lines.append("Sanity %.0f  blur %.0f  vomit %.1f  death timer %.0f" % [GameState.sanity, GameState.blur_timer, GameState.vomit_timer, GameState.death_timer])
	lines.append("Fog override %s  music %s  step set %d" % [str(GameState.fog_override), GameState.music_override, GameState.step_set])
	var statue: Node3D = GameState.scp173
	if statue != null:
		lines.append("173: (%.1f, %.1f, %.1f) idle %d dist %.1f" % [statue.global_position.x, statue.global_position.y, -statue.global_position.z, statue.idle, statue.global_position.distance_to(pos)])
	var old_man: Node3D = facility.scp106
	if old_man != null and is_instance_valid(old_man):
		lines.append("106: state %.0f idle %s dist %.1f" % [old_man.state, str(old_man.idle), old_man.global_position.distance_to(pos)])
	var big: Node3D = facility.scp096
	if big != null and is_instance_valid(big):
		lines.append("096: state %d dist %.1f" % [big.state, big.global_position.distance_to(pos)])
	var old_049: Node3D = facility.scp049
	if old_049 != null and is_instance_valid(old_049):
		lines.append("049: state %d idle %.0f dist %.1f" % [old_049.state, old_049.idle, old_049.global_position.distance_to(pos)])
	lines.append("MTF timer %.0f   rooms built %d   draw calls %d" % [facility.mtf.timer, facility.rooms.built.size(), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
	return "\n".join(lines)

# Room materials are the lightmap shader (its `fullbright` uniform shows the albedo alone);
# entity, door and item materials are unshaded and tinted by the ambient level, so they go
# to plain white. Originals are kept in metadata and restored; meshes added while
# it is on are handled through node_added.
var unlit := false

func _set_unlit(on: bool) -> void:
	if on == unlit:
		return
	unlit = on
	if on:
		get_tree().node_added.connect(_unlit_node)
	else:
		get_tree().node_added.disconnect(_unlit_node)
	_unlit_tree(get_tree().root, on)

func _unlit_tree(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		_unlit_mesh(node as MeshInstance3D, on)
	for child in node.get_children():
		_unlit_tree(child, on)

func _unlit_node(node: Node) -> void:
	if node is MeshInstance3D:
		# the mesh is assigned right after the node is added
		_unlit_mesh.call_deferred(node as MeshInstance3D, true)

func _unlit_mesh(mesh_instance: MeshInstance3D, on: bool) -> void:
	if not is_instance_valid(mesh_instance):
		return
	if on and not unlit:
		return
	if mesh_instance.material_override != null:
		_unlit_material(mesh_instance.material_override, on)
	if mesh_instance.mesh != null:
		for surface in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.mesh.surface_get_material(surface)
			if mat != null:
				_unlit_material(mat, on)

func _unlit_material(mat: Material, on: bool) -> void:
	if mat is ShaderMaterial and not mat is EntityMaterial:
		var shader_material := mat as ShaderMaterial
		if shader_material.shader != null and shader_material.shader.get_shader_uniform_list().any(func(u: Dictionary) -> bool: return u.name == "fullbright"):
			shader_material.set_shader_parameter("fullbright", on)
	elif mat is StandardMaterial3D or mat is EntityMaterial:
		# lit entity materials: shown flat (no lights, no ambient), restored afterwards
		var standard = mat
		if on:
			if not standard.has_meta("lit_shading"):
				standard.set_meta("lit_shading", standard.shading_mode)
			standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		elif standard.has_meta("lit_shading"):
			standard.shading_mode = standard.get_meta("lit_shading")
			standard.remove_meta("lit_shading")

# What to quote in a bug report: map seed, the room and position, and the nearest door.
func _report_text() -> String:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var player: Node3D = GameState.player
	if facility == null or player == null or facility.generator == null:
		return ""
	var pos := player.global_position
	var text := "seed %d   room %s   pos (%.1f, %.1f, %.1f)" % [facility.generator.seed_value, facility.room_name_at(pos), pos.x, pos.y, pos.z]
	var nearest: Node3D = null
	var best := 6.0
	for node in get_tree().get_nodes_in_group("door"):
		var door := node as Node3D
		if door == null:
			continue
		var d := door.global_position.distance_to(pos)
		if d < best:
			best = d
			nearest = door
	if nearest != null:
		var owner_name := str(nearest.get_parent().name)
		text += "\nnearest door %.1f m: %s at (%.2f, %.2f, %.2f) yaw %.0f %s%s" % [best, "map edge" if owner_name == "Facility" else owner_name, nearest.global_position.x, nearest.global_position.y, nearest.global_position.z, nearest.rotation_degrees.y, "open" if nearest.get("open") == true else "closed", " heavy" if nearest.get("heavy") == true else ""]
	return text
