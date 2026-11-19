extends "res://scripts/tests/bot_173.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_itemguard() -> void:
	log_line("== items beyond HideDistance * 0.5 are hidden and still (Items.bb UpdateItems)")
	statue.active = false
	revive()
	var origin := Vector3(500.0, 200.0, 500.0)
	var arena := _arena(origin)
	place_player(origin + Vector3(0.0, 0.05, 0.0))
	await secs(0.5)
	var item: StaticBody3D = RoomFill.make_pickup("Level 2 Key Card", "key2")
	arena.add_child(item)
	item.position = Vector3(12.0, 2.0, 0.0)
	await secs(1.0)
	check("an item 12 away is hidden, without collision", not item.visible and item.collision_layer == 0, "visible %s layer %d dist %.1f" % [str(item.visible), item.collision_layer, item.dist])
	check("and it does not fall", absf(item.position.y - 2.0) < 0.001 and not item.resting, "y %.2f" % item.position.y)
	item.position = Vector3(5.0, 2.0, 0.0)
	await secs(0.9)
	check("within 8 it is shown and pickable again", item.visible and item.collision_layer == 8, "visible %s layer %d dist %.1f" % [str(item.visible), item.collision_layer, item.dist])
	await secs(1.2)
	check("and it falls to the floor", item.resting and item.position.y < 0.1, "y %.2f" % item.position.y)
	item.queue_free()
	arena.queue_free()

func _scn_items() -> void:
	log_line("== items")
	statue.active = false
	revive()
	var hud := get_tree().get_first_node_in_group("hud")
	var origin := Vector3(500.0, 200.0, 500.0)
	var arena := _arena(origin)
	place_player(origin + Vector3(0.0, 0.05, 0.0))    # items beyond 8 of the camera are hidden and still
	# 1. falls at 0.0004 per frame^2 = 1.96 m/s^2 and stops 0.01 above the floor
	var faller: StaticBody3D = RoomFill.make_pickup("Level 2 Key Card", "key2")
	arena.add_child(faller)
	faller.position = Vector3(5.0, 1.0, 5.0)
	var t := 0.0
	while t < 3.0 and not faller.resting:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var expected := sqrt(2.0 * 1.0 / 1.96)
	check("item falls at 1.96 m/s^2 (expect %.2fs)" % expected, faller.resting and absf(t - expected) < 0.15, "landed after %.2fs" % t)
	check("item rests 0.01 above the floor", absf(faller.global_position.y - (origin.y + 0.01)) < 0.005, "y=%.3f" % (faller.global_position.y - origin.y))
	# 2. no ground within 10 units below: it stays where it is
	var hanging: StaticBody3D = RoomFill.make_pickup("Level 1 Key Card", "key1")
	arena.add_child(hanging)
	hanging.position = Vector3(5.0, 14.0, -5.0)
	await secs(0.5)
	check("item over a >10 unit drop does not fall", absf(hanging.position.y - 14.0) < 0.001, "y=%.2f" % hanging.position.y)
	faller.queue_free()
	hanging.queue_free()
	place_player(origin + Vector3(0.0, 0.05, 0.0))
	await secs(0.5)
	player.rotation.y = 0.0
	player.camera.rotation.x = 0.0
	var near: StaticBody3D = RoomFill.make_pickup("Level 3 Key Card", "key3")
	arena.add_child(near)
	near.position = Vector3(0.0, 0.7, -0.6)
	var far: StaticBody3D = RoomFill.make_pickup("Level 4 Key Card", "key4")
	arena.add_child(far)
	far.position = Vector3(0.0, 0.7, -2.5)
	player.camera.rotation.x = -deg_to_rad(45.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await secs(1.5)
	check("nearest item in view is the pickup target", player.closest_item() == near, str(player.closest_item()))
	check("item beyond 1.2 is not a target", player.closest_item() != far, "")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(2.0, 2.0, 0.1)
	wcol.shape = wbox
	wall.add_child(wcol)
	arena.add_child(wall)
	wall.position = Vector3(0.0, 1.0, -0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("item behind a wall is not a target", player.closest_item() == null, str(player.closest_item()))
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.rotation.y = PI
	await get_tree().physics_frame
	check("item outside the view is not a target", player.closest_item() == null, "")
	player.rotation.y = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before: int = hud.items.filter(func(s: String) -> bool: return not s.is_empty()).size()
	await tap("interact")
	await get_tree().physics_frame
	var after: int = hud.items.filter(func(s: String) -> bool: return not s.is_empty()).size()
	check("E picks the item up into the inventory (not auto-used)", after == before + 1 and hud.selected_tempname() == "", "slots %d -> %d" % [before, after])
	var slot := -1
	for i in hud.items.size():
		if hud.item_data[i].get("tempname", "") == "key3":
			slot = i
	hud.set_selected(slot)
	check("selecting the key card readies it", hud.selected_tempname() == "key3", hud.selected_tempname())
	await tap("drop_item")
	await secs(1.2)
	var dropped: Node3D = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if node.get_meta("tempname", "") == "key3" and is_instance_valid(node) and not node.is_queued_for_deletion():
			dropped = node
	check("Q drops the item back into the world", dropped != null and hud.selected_tempname() == "", "")
	if dropped:
		check("dropped item has fallen to the floor", dropped.resting and absf(dropped.global_position.y - (origin.y + 0.01)) < 0.02, "y=%.3f" % (dropped.global_position.y - origin.y))
	arena.queue_free()

func _scn_use() -> void:
	log_line("== using items")
	statue.active = false
	revive()
	var hud := get_tree().get_first_node_in_group("hud")
	var s := GameState
	s.wearing_gas_mask = 0
	s.wearing_vest = 0
	s.wearing_hazmat = 0
	s.injuries = 0.0
	s.bloodloss = 0.0
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(0.5)
	var mask := _give(hud, "Gas Mask", "gasmask")
	hud.set_selected(mask)
	check("gas mask goes on", s.wearing_gas_mask == 1 and hud.selected == -1 and hud.message_label.text == "You put on the gas mask.", hud.message_label.text)
	await get_tree().process_frame
	await get_tree().process_frame
	check("gas mask overlay is shown", hud._gas_overlay.visible, "texture=%s path=%s" % [str(hud._gas_overlay.texture), ContentPaths.existing_image("GFX/GasmaskOverlay.jpg")])
	await shot("use_gasmask")
	hud.set_selected(mask)
	check("gas mask comes off", s.wearing_gas_mask == 0 and hud.message_label.text == "You removed the gas mask.", hud.message_label.text)
	# vest: progress bar, movement held, then worn; turning slows
	var vest := _give(hud, "Ballistic Vest", "vest")
	if vest < 0:
		vest = _give(hud, "Kevlar Vest", "vest")
	hud.set_selected(vest)
	var held := player.global_position
	Input.action_press("move_forward")
	var t := 0.0
	while t < 5.0 and s.wearing_vest == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	check("vest takes about 2.9 s and holds you still", s.wearing_vest == 1 and t > 2.3 and t < 3.6 and player.global_position.distance_to(held) < 0.3, "t=%.1fs moved %.2f" % [t, player.global_position.distance_to(held)])
	check("vest message", hud.message_label.text.begins_with("You put on the vest"), hud.message_label.text)
	# taking the vest off drops it into the world (DropItem after clearing the flag)
	hud.set_selected(vest)
	t = 0.0
	while t < 5.0 and s.wearing_vest != 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("removing the vest drops it", s.wearing_vest == 0 and hud.items[vest] == "", "wearing=%d slot='%s'" % [s.wearing_vest, hud.items[vest]])
	vest = _give(hud, "Ballistic Vest", "vest")
	s.wearing_vest = 1
	s.wearing_hazmat = 1
	hud.set_selected(mask)
	check("gas mask needs the hazmat suit off", s.wearing_gas_mask == 0 and hud.message_label.text.begins_with("You need to take off the hazmat suit"), hud.message_label.text)
	var drop_slot := _give(hud, "Level 1 Key Card", "key1")
	hud.set_selected(drop_slot)
	await tap("drop_item")
	check("cannot drop items in a hazmat suit", hud.items[drop_slot] == "Level 1 Key Card" and hud.message_label.text.begins_with("You cannot drop"), hud.message_label.text)
	hud.deselect()
	s.wearing_hazmat = 0
	var aid := _give(hud, "First Aid Kit", "firstaid")
	hud.set_selected(aid)
	check("first aid kit refused when unhurt", hud.items[aid] == "First Aid Kit" and hud.message_label.text == "You do not need to use a first aid kit right now.", hud.message_label.text)
	s.injuries = 2.0
	s.bloodloss = 40.0
	hud.set_selected(aid)
	t = 0.0
	while t < 12.0 and hud.items[aid] == "First Aid Kit":
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("first aid takes about 7 s, heals and is used up", hud.items[aid] == "" and s.injuries < 2.0 and s.bloodloss < 40.0 and t > 6.0 and t < 9.0, "t=%.1fs injuries=%.2f bloodloss=%.1f" % [t, s.injuries, s.bloodloss])
	var drops := _give(hud, "Eyedrops", "eyedrops")
	if drops < 0:
		drops = _give(hud, "ReVision Eyedrops", "eyedrops")
	hud.set_selected(drops)
	check("eye drops slow blinking and are consumed", is_equal_approx(s.blink_effect, 0.6) and s.blink_effect_timer >= 20.0 and hud.items[drops] == "", "effect %.1f timer %.1f" % [s.blink_effect, s.blink_effect_timer])
	player.blink_timer = 300.0
	var before: float = player.blink_timer
	await secs(1.0)
	var spent: float = before - player.blink_timer
	check("blink timer runs at 0.6 speed (~25 per second)", spent > 20.0 and spent < 30.0, "%.1f" % spent)
	s.blink_effect = 1.0
	s.blink_effect_timer = 0.0
	# document: image shown, code written on the SCP-372 one
	var doc := _give(hud, "Document SCP-372", "paper")
	hud.set_selected(doc)
	var expected := (int(s.access_code) * 3) % 10000
	if expected < 1000:
		expected += 1000
	check("document is shown with the access code", hud._doc_rect.visible and hud._doc_code.text == str(expected), "visible=%s code='%s' expected %d" % [hud._doc_rect.visible, hud._doc_code.text, expected])
	await shot("use_document")
	hud.set_selected(doc)
	check("document closes when put away", not hud._doc_rect.visible, "")
	s.wearing_vest = 0

func _scn_keypad() -> void:
	log_line("== keypad")
	statue.active = false
	revive()
	var arena := _arena(Vector3(700.0, 200.0, 700.0))
	var door := Node3D.new()
	door.set_script(load("res://scripts/world/facility_door.gd"))
	door.code = "1234"
	arena.add_child(door)
	door.place_in_room(Vector3.ZERO, 0.0, false, false)
	var pad: Node = get_tree().get_first_node_in_group("keypad")
	check("keypad exists in the HUD", pad != null, "")
	if pad == null:
		return
	door.use()
	check("pressing a code door's button opens the keypad and pauses the game", pad.is_open() and get_tree().paused, "open=%s paused=%s" % [str(pad.is_open()), str(get_tree().paused)])
	var pad_button: Node3D = door.buttons[0]
	var camera_gap: float = player.camera.global_position.distance_to(pad_button.global_position)
	var looks_at: float = (-player.camera.global_transform.basis.z).dot((pad_button.global_position - player.camera.global_position).normalized())
	check("the camera stands 0.22 in front of the keypad and looks at it (Main.bb 4889-4894)", absf(camera_gap - 0.22) < 0.01 and looks_at > 0.999, "gap=%.3f dot=%.4f" % [camera_gap, looks_at])
	var half := Vector3(0.0, 5.04473 * 0.015, 0.0)
	var expected_scale: float = absf(player.camera.unproject_position(pad_button.global_position - half).y - player.camera.unproject_position(pad_button.global_position + half).y) / 462.0
	check("keypad scale comes from the button's projected height (Main.bb 4897-4900)", pad._scale > 0.0 and absf(pad._scale - expected_scale) < 0.001, "scale=%.3f expected=%.3f" % [pad._scale, expected_scale])
	var camera_before: Transform3D = pad._camera_saved
	await shot("keypad_open")
	await _type_code(pad, "12345")
	check("input is limited to four digits", pad.input == "1234", "'%s'" % pad.input)
	await _click_key(pad, 12)
	check("CLEAR empties the input", pad.input == "", "'%s'" % pad.input)
	await _type_code(pad, "1111")
	await _click_key(pad, 8)
	check("wrong code shows ACCESS DENIED and clears", pad.message == "ACCESS DENIED" and pad.input == "" and not door.open, pad.message)
	var t := 0.0
	while t < 4.5 and pad.is_open():
		await get_tree().process_frame
		t += get_process_delta_time()
	check("denied screen closes after 3 s", not pad.is_open() and not get_tree().paused and t > 2.5 and t < 4.0, "t=%.1fs" % t)
	check("closing the keypad gives the camera back", player.camera.transform.is_equal_approx(camera_before), "")
	door.use()
	await _type_code(pad, "1234")
	await _click_key(pad, 8)
	await get_tree().process_frame
	check("right code opens the door and closes the keypad", door.open and not pad.is_open() and not get_tree().paused, "open=%s pad=%s" % [str(door.open), str(pad.is_open())])
	# put away with the right mouse button
	door.use()
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	Input.parse_input_event(rc)
	await get_tree().process_frame
	await get_tree().process_frame
	check("right click puts the keypad away", not pad.is_open() and not get_tree().paused, "")
	arena.queue_free()

func _right_click() -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = pressed
		Input.parse_input_event(click)
		await get_tree().process_frame
		await get_tree().process_frame

func _scn_putaway() -> void:
	log_line("== right click puts the held item away (Main.bb 7062)")
	statue.active = false
	var hud := get_tree().get_first_node_in_group("hud")
	var s := GameState
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	s.wearing_vest = 0
	s.wearing_hazmat = 0
	var nav := _give(hud, "S-NAV Navigator", "nav")
	hud.set_selected(nav)
	check("the navigator is in the hand", hud.selected == nav, "")
	await _right_click()
	check("right click puts the navigator away and keeps it", hud.selected == -1 and hud.items[nav] == "S-NAV Navigator", "selected %d" % hud.selected)
	var vest := _give(hud, "Ballistic Vest", "vest")
	hud.set_selected(vest)
	await get_tree().physics_frame
	await _right_click()
	check("right click while putting on a vest drops it", hud.selected == -1 and hud.items[vest] == "" and s.wearing_vest == 0, "slot '%s' wearing %d" % [hud.items[vest], s.wearing_vest])
	var doc := _give(hud, "Document SCP-173", "paper")
	hud.set_selected(doc)
	hud.open_inventory()
	await get_tree().physics_frame
	await _right_click()
	check("right click in the open inventory leaves the hand alone", hud.selected == doc, "selected %d" % hud.selected)
	hud.close_inventory()
	await _right_click()
	check("right click puts the document away", hud.selected == -1 and hud.items[doc] == "Document SCP-173", "selected %d" % hud.selected)

func _scn_uishots() -> void:
	log_line("== UI screenshots")
	statue.active = false
	var hud := get_tree().get_first_node_in_group("hud")
	_give(hud, "Level 1 Key Card", "key1")
	_give(hud, "First Aid Kit", "firstaid")
	_give(hud, "Gas Mask", "gasmask")
	_give(hud, "Document SCP-173", "paper")
	GameState.wearing_gas_mask = 1
	player.stamina = 55.0
	player.blink_timer = 200.0
	hud.message("You pushed the button but nothing happened.", 5.0)
	await secs(0.5)
	await shot("ui_hud")
	hud.open_inventory()
	await secs(0.4)
	await shot("ui_inventory")
	if hud._inventory != null and not hud.items[0].is_empty():
		hud._inventory._drag_index = 0     # an item held by the mouse: drawn at 64 px like the slots
		await secs(0.2)
		await shot("ui_inventory_drag")
		hud._inventory._drag_index = -1
	hud.close_inventory()
	hud.open_pause_menu()
	await secs(0.4)
	await shot("ui_pause")
	hud.pause_menu.mode = hud.pause_menu.Mode.OPTIONS
	hud.pause_menu.rebuild()
	await secs(0.3)
	await shot("ui_options")
	hud.close_pause_menu()
	GameState.wearing_gas_mask = 0
	player.kill("Subject D-9341. Cause of death: Fatal cervical fracture. Assumed to be attacked by SCP-173.")
	await secs(2.0)
	await shot("ui_death")

func _scn_ui() -> void:
	log_line("== inventory and menus")
	statue.active = false
	var hud := get_tree().get_first_node_in_group("hud")
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	var key_slot := _give(hud, "Level 1 Key Card", "key1")
	var aid_slot := _give(hud, "First Aid Kit", "firstaid")
	hud.open_inventory()
	await get_tree().physics_frame
	check("Tab opens the inventory and stops the game", hud.inventory_open and get_tree().paused, "")
	var from_rect: Rect2 = hud._inventory.slot_rect(key_slot)
	var to_rect: Rect2 = hud._inventory.slot_rect(7)
	var motion := InputEventMouseMotion.new()
	motion.position = from_rect.get_center()
	hud._inventory._gui_input(motion)
	check("hovering follows the mouse events (the name is drawn for that slot)", hud._inventory.hover_slot() == key_slot, "hover %d, slot %d" % [hud._inventory.hover_slot(), key_slot])
	_click(hud, from_rect.get_center(), true)
	_click(hud, to_rect.get_center(), false)
	check("dragging an item to an empty slot moves it", hud.items[7] == "Level 1 Key Card" and hud.items[key_slot].is_empty(), str(hud.items))
	# dropped outside the slots: it falls into the world
	var pickups_before := get_tree().get_nodes_in_group("pickup").size()
	var aid_rect: Rect2 = hud._inventory.slot_rect(aid_slot)
	_click(hud, aid_rect.get_center(), true)
	_click(hud, Vector2(20.0, 20.0), false)
	check("releasing outside the slots drops the item", hud.items[aid_slot].is_empty() and get_tree().get_nodes_in_group("pickup").size() == pickups_before + 1 and not hud.inventory_open, "")
	check("closing the inventory resumes the game", not get_tree().paused, "")
	# double click on an item uses (selects) it and closes the inventory
	hud.open_inventory()
	await get_tree().physics_frame
	var rect: Rect2 = hud._inventory.slot_rect(7)
	_click(hud, rect.get_center(), true)
	_click(hud, rect.get_center(), false)
	_click(hud, rect.get_center(), true)
	_click(hud, rect.get_center(), false)
	check("double click uses the item and closes the inventory", hud.selected == 7 and not hud.inventory_open, "selected %d" % hud.selected)
	hud.deselect()
	# pause menu
	hud.open_pause_menu()
	await get_tree().physics_frame
	check("Esc opens the pause menu and stops the game", hud.pause_menu.visible and get_tree().paused, "")
	hud.close_pause_menu()
	check("Resume continues the game", not hud.pause_menu.visible and not get_tree().paused, "")

# A clickable screen shows its picture and, on Euclid, is where the game can be saved.
func _scn_screens() -> void:
	log_line("== screens")
	statue.active = false
	var MeshLoader = load("res://scripts/io/mesh_loader.gd")
	var record: Dictionary = {}
	var entity: Dictionary = {}
	for r in facility.generator.rooms:
		if facility.rooms.inside_start(r):
			continue
		var parsed: Dictionary = MeshLoader.parse_rmesh_cached(facility.rooms.mesh_path(r))
		for e in parsed.entities:
			if str(e.kind) == "screen" and not str(e.get("image", "")).is_empty():
				record = r
				entity = e
				break
		if not record.is_empty():
			break
	check("the map has a room with a screen", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	var screen_world: Vector3 = room.to_global(entity.position)
	place_player(screen_world + Vector3(0.0, 0.2, 0.0))
	await secs(0.5)
	# stand 0.6 away in the room's open floor and look at it
	var stand := Vector3.INF
	for angle in 12:
		var offset := Vector3(cos(TAU * angle / 12.0), 0.0, sin(TAU * angle / 12.0)) * 0.6
		var spot := screen_world + offset
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.5, 0), spot + Vector3(0, -3.0, 0))
		q.collision_mask = 1
		var floor_hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		if floor_hit.is_empty():
			continue
		var feet: Vector3 = floor_hit.position + Vector3(0, 0.05, 0)
		if not blocked(feet + Vector3(0, 0.1, 0)) and not ray_blocked(feet + Vector3(0, 0.9, 0), screen_world):
			stand = feet
			break
	check("a spot to read the screen from", stand != Vector3.INF, "")
	if stand == Vector3.INF:
		return
	place_player(stand)
	await secs(0.6)
	face_point(screen_world)
	var look: Vector3 = screen_world - player.camera.global_position
	player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	await secs(0.3)
	var hud := get_tree().get_first_node_in_group("hud")
	player._interact()
	check("using a screen opens its picture and stops the game", hud.screen_open and get_tree().paused, "")
	GameState.difficulty = 1
	main.hud.quick_save()
	check("Euclid saves while a screen is open", FileAccess.file_exists(SaveGame.path_of(SaveGame.LEGACY_SLOT)), "")
	hud.close_screen()
	check("closing the screen resumes the game", not hud.screen_open and not get_tree().paused, "")
	GameState.difficulty = 1
	hud.quick_save()
	check("Euclid refuses to save away from a screen", hud.message_label.text.contains("clickable monitors"), hud.message_label.text)

# Menu.bb / DrawMenu: the four options tabs in both layouts, their tooltips, what the options change, the custom
# difficulty, the loading screen and the menu's music.
func _scn_menus() -> void:
	log_line("== main menu, options and loading screens")
	statue.active = false
	var menu: Control = main.menu
	check("a new menu starts on Safe", menu.difficulty == 0, str(menu.difficulty))
	menu.visible = true
	menu._open_new_game()
	check("NEW GAME rolls a seed and opens the form", menu.tab == 1 and menu.seed_text.length() >= 2, menu.seed_text)
	var rows := {3: "VSync:", 5: "Music volume:", 6: "Control configuration:", 7: "Show HUD:"}
	for tab in [3, 5, 6, 7]:
		menu._set_tab(tab)
		var panel: Control = menu._options
		var labels := []
		for entry in panel._texts:
			labels.append(entry[1] if entry[1] is String else "")
		check("options tab %d has its rows" % tab, panel != null and rows[tab] in labels and panel._tips.size() >= 3, str(labels))
	menu._set_tab(7)
	var hud_tick: UITick = null
	for child in menu._options.get_children():
		if child is UITick:
			hud_tick = child
			break
	hud_tick.toggled.emit(false)
	check("the Show HUD tick turns the meters off", not GameState.hud_enabled, "")
	GameState.hud_enabled = true
	var gamma_tip: Array = OptionsPanel.tooltip_text("gamma", 1.0)
	check("the gamma tooltip reads its value", gamma_tip[1] == "Current value: 100% (default is 100%)", gamma_tip[1])
	var particle_tip: Array = OptionsPanel.tooltip_text("particleamount", 0.0)
	check("the particle tooltip is red at MINIMAL", particle_tip[2] == Color8(255, 0, 0) and particle_tip[1] == "Only smoke emitters will produce particles.", str(particle_tip))
	menu._set_tab(0)
	menu.visible = false
	GameState.binds.up = 18
	GameState.apply_binds()
	var forward_keys := []
	for event in InputMap.action_get_events("move_forward"):
		if event is InputEventKey:
			forward_keys.append(event.physical_keycode)
	check("a rebound key moves the player", forward_keys == [KEY_E], str(forward_keys))
	GameState.binds.up = 17
	GameState.apply_binds()
	GameState.texture_details = 0
	check("Texture LOD Bias 0 is +0.8", is_equal_approx(GameState.texture_lod_bias(), 0.8), "")
	GameState.texture_details = 3
	var difficulty_before := GameState.difficulty
	GameState.difficulty = GameState.CUSTOM
	GameState.custom_perma_death = true
	GameState.custom_save_anywhere = true
	check("custom permadeath saves only on screens", GameState.perma_death() and GameState.save_type() == 1, "")
	GameState.custom_perma_death = false
	check("custom without permadeath saves anywhere", not GameState.perma_death() and GameState.save_type() == 0 and GameState.aggressive_npcs(), "")
	GameState.difficulty = difficulty_before
	var hud := get_tree().get_first_node_in_group("hud")
	hud.open_pause_menu()
	hud.pause_menu.mode = hud.pause_menu.Mode.OPTIONS
	hud.pause_menu.rebuild()
	var pause_panel: Control = null
	for child in hud.pause_menu.get_children():
		if child is OptionsPanel:
			pause_panel = child
	check("the pause menu has the options panel in its own layout", pause_panel != null and pause_panel.layout == OptionsPanel.Layout.PAUSE, "")
	GameState.achievements.clear()
	for name in ["008", "snav", "pd"]:
		GameState.give_achievement(name)
	hud.pause_menu.open_achievements()
	var achv_panel: AchievementsPanel = null
	for child in hud.pause_menu.get_children():
		if child is AchievementsPanel and not child.is_queued_for_deletion():
			achv_panel = child
	check("the achievements list opens on page 1 with 12 cells", achv_panel != null and achv_panel.page == 1 and AchievementsPanel.cells_on(1) == 12, "")
	check("the last page holds one cell", AchievementsPanel.last_page() == 4 and AchievementsPanel.cells_on(4) == 1, "%d pages" % AchievementsPanel.last_page())
	var under := []
	for child in hud.pause_menu.get_children():
		if child is UIButton and not child.is_queued_for_deletion() and child.z_index >= achv_panel.z_index:
			under.append(child.text)
	check("the achievement tooltip draws over Back, < and >, as the original draws it after them", achv_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and under.is_empty(), "drawn over the tooltip: %s" % str(under))
	check("three unlocked achievements are counted", GameState.achievements_unlocked() == 3, str(GameState.achievements_unlocked()))
	var arrows := func() -> Array:
		var found := []
		for child in hud.pause_menu.get_children():
			if child is UIButton and not child.is_queued_for_deletion() and (child.text == "<" or child.text == ">"):
				found.append(child.text)
		return found
	check("page 1 has only the > arrow", arrows.call() == [">"], str(arrows.call()))
	for i in 3:
		for child in hud.pause_menu.get_children():
			if child is UIButton and not child.is_queued_for_deletion() and child.text == ">":
				child.pressed.emit()
				break
	check("> clamps at the last page", hud.pause_menu.achievements_page == 4 and arrows.call() == ["<"], "%d %s" % [hud.pause_menu.achievements_page, str(arrows.call())])
	hud.pause_menu.mode = hud.pause_menu.Mode.PAUSED
	GameState.achievements.clear()
	var popups: AchievementPopups = null
	for child in hud.get_children():
		if child is AchievementPopups:
			popups = child
	popups.messages.clear()
	GameState.achievement_popups = true
	GameState.give_achievement("012")
	GameState.give_achievement("012")
	check("a first-time achievement raises one popup", popups != null and popups.messages.size() == 1, str(popups.messages.size() if popups != null else -1))
	GameState.achievement_popups = false
	GameState.give_achievement("035")
	check("no popup with the option off", popups.messages.size() == 1, str(popups.messages.size()))
	GameState.achievement_popups = true
	popups.messages.clear()
	GameState.achievements.clear()
	var console: Control = null
	for child in hud.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("debug_overlay.gd"):
			console = child.console
	GameState.console_on_error = false
	Sfx.stream("SFX/NoSuchSound%d.ogg" % randi())
	check("a missing sound is logged in the console without opening it", console != null and not console.is_open and str(console.messages.back().text).contains("not found"), "")
	GameState.console_on_error = true
	Sfx.stream("SFX/NoSuchSound%d.ogg" % randi())
	check("console_on_error opens the console on a missing sound", console != null and console.is_open, "")
	console._toggle()
	GameState.console_on_error = false
	hud.close_pause_menu()
	var kept_autosave := PackedByteArray()
	if SaveGame.exists(SaveGame.LEGACY_SLOT):
		kept_autosave = FileAccess.get_file_as_bytes(SaveGame.path_of(SaveGame.LEGACY_SLOT))
	SaveGame.delete(SaveGame.LEGACY_SLOT)
	check("a legacy autosave.json is slot 0 and still loads", SaveGame.write({"version": SaveGame.VERSION, "name": "Legacy", "saved_at": "2026-01-01T10:00:00", "seed": 5}, SaveGame.LEGACY_SLOT) and int(SaveGame.read().get("seed", 0)) == 5 and SaveGame.list().any(func(entry: Dictionary) -> bool: return entry.slot == SaveGame.LEGACY_SLOT and entry.name == "Legacy"), "")
	SaveGame.write({"version": SaveGame.VERSION + 1, "name": "Old", "saved_at": "2026-01-02T10:00:00"}, "zz_old")
	check("a save of another version is listed but does not read", SaveGame.read("zz_old").is_empty() and SaveGame.list().any(func(entry: Dictionary) -> bool: return entry.slot == "zz_old" and not entry.compatible), "")
	SaveGame.write({"version": SaveGame.VERSION, "name": "Dup", "saved_at": "2026-02-01T10:00:00"}, "zz_dup")
	check("a repeated name gets (2) appended", SaveGame.unique_name("Dup") == "Dup (2)" and SaveGame.unique_name("Fresh") == "Fresh", SaveGame.unique_name("Dup"))
	for i in 8:
		SaveGame.write({"version": SaveGame.VERSION, "name": "Test %d" % i, "saved_at": "2026-03-0%dT10:00:00" % (i + 1)}, "zz_t%d" % i)
	menu.visible = true
	menu._set_tab(2)
	var total: int = menu.saves.size()
	check("more than six saves make two or more pages", total >= 11 and menu.page_count() == ceili(total / 6.0) and menu.page_count() >= 2, "%d saves, %d pages" % [total, menu.page_count()])
	check("the list is newest first", menu.saves[0].saved_at >= menu.saves[1].saved_at, "")
	menu.load_page = menu.page_count() - 1
	menu._rebuild()
	var yes_clicks := 0
	while menu.saves.any(func(entry: Dictionary) -> bool: return entry.slot.begins_with("zz_")) and yes_clicks < 20:
		var victim: String = ""
		for entry in menu.saves:
			if entry.slot.begins_with("zz_"):
				victim = entry.slot
		menu.delete_asked = true
		menu.delete_slot = victim
		menu._rebuild()
		for child in menu.get_children():
			if child is UIButton and not child.is_queued_for_deletion() and child.text == "Yes":
				child.pressed.emit()
		yes_clicks += 1
		if menu.load_page >= menu.page_count():
			check("deleting keeps the page in range", false, "%d of %d" % [menu.load_page, menu.page_count()])
	check("every test save is deleted through the confirm and the page stays in range", menu.saves.size() <= total - 10 and menu.load_page < menu.page_count() and menu.load_page == clampi(menu.load_page, 0, menu.page_count() - 1), "%d left, page %d/%d" % [menu.saves.size(), menu.load_page, menu.page_count()])
	check("the delete confirm removed the chosen row", not menu.saves.any(func(entry: Dictionary) -> bool: return entry.slot.begins_with("zz_")), "")
	SaveGame.delete(SaveGame.LEGACY_SLOT)
	if not kept_autosave.is_empty():
		var restore := FileAccess.open(SaveGame.path_of(SaveGame.LEGACY_SLOT), FileAccess.WRITE)
		restore.store_buffer(kept_autosave)
		restore.close()
	menu._set_tab(0)
	menu.visible = false
	check("the loading screens are read", LoadingScreen.available(), "Loadingscreens/loadingscreens.ini")
	var screen: Node = main._loading_screen()
	screen.show_percent(0)
	var picked: Dictionary = screen._screen
	check("0 % picks a screen", not picked.is_empty() and screen.percent == 0 and not screen.waiting, str(picked.get("title", "")))
	if int(picked.get("amount", 0)) >= 2:
		screen.show_percent(80)
		check("the next text once the percent passes 100 / texts", screen._text_index == 1, str(screen._text_index))
	screen.show_percent(100)
	check("100 % waits for a key", screen.waiting, "")
	var closed := [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	screen._input(key)
	check("a key closes it", closed[0], "")
	menu.visible = true
	await secs(0.5)
	check("the menu plays its track", menu._music_now == "Menu", menu._music_now)
	menu.visible = false
	await secs(4.5)
	check("and fades it out once the game runs", menu._music_now == "", menu._music_now)

# Menu.bb UpdateLauncher / Main.bb start-up: the mode list, the tick rules, what LAUNCH stores, EXIT, and that the
# bot's own boot never shows the launcher.
func _scn_startup() -> void:
	log_line("== startup videos")
	var ini := IniFile.new()
	ini.sections = {"options": {"play startup video": "false"}}
	check("the option reads like GetINIInt", GameState.ini_int(ini, "options", "play startup video", 1) == 0, "")
	check("the bot's boot does not play them", not main._interactive(), "")
	check("the clips are Undertow, then TSS", StartupVideos.CLIPS == ["startup_Undertow", "startup_TSS"], str(StartupVideos.CLIPS))
	if not StartupVideos.available():
		check("the .ogv videos and .ogg soundtracks are in the pack", false, "the asset pack has them; see tools/build_asset_pack.py")
		return
	var videos := StartupVideos.new()
	main.add_child(videos)
	var ended := [false]
	videos.finished.connect(func() -> void: ended[0] = true)
	videos.play()
	await secs(0.5)
	check("the first clip plays with its soundtrack", videos.running and videos.clip_index == 0 and videos._video.is_playing() and videos._audio.playing, str(videos.clip_index))
	var screen := videos.get_viewport().get_visible_rect().size
	check("the picture is screen-wide at 16:9, centred", is_equal_approx(videos._video.size.x, screen.x) and is_equal_approx(videos._video.size.y, screen.x * 9.0 / 16.0) and is_equal_approx(videos._video.position.y, (screen.y - videos._video.size.y) / 2.0), str(videos._video.size))
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	videos._input(key)
	await secs(0.3)
	check("a key skips to the second clip", videos.running and videos.clip_index == 1 and videos._video.is_playing() and videos._audio.playing, str(videos.clip_index))
	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	videos._input(echo)
	check("a held key does not skip again", videos.clip_index == 1 and not ended[0], "")
	videos._audio.finished.emit()
	await secs(0.1)
	check("the end of the soundtrack ends the last clip", ended[0] and not videos.running and videos.skipped_clips == 0, "")
	videos.queue_free()

func _scn_launcher() -> void:
	log_line("== launcher")
	var keep := {}
	for key in GameState.SAVED_OPTIONS:
		keep[key] = GameState.get(key)
	var keep_size := Vector2i(GameState.launcher_width, GameState.launcher_height)
	GameState.graphic_width = 1280
	GameState.graphic_height = 720
	GameState.fullscreen = false
	GameState.borderless_windowed = false
	GameState.gfx_driver = 1
	var launcher := Launcher.new()
	main.add_child(launcher)
	var screen := launcher.screen
	var sorted := true
	var inside := true
	for i in launcher.modes.size():
		inside = inside and launcher.modes[i].x <= screen.x and launcher.modes[i].y <= screen.y
		if i > 0:
			sorted = sorted and (launcher.modes[i - 1].x < launcher.modes[i].x or (launcher.modes[i - 1].x == launcher.modes[i].x and launcher.modes[i - 1].y < launcher.modes[i].y))
	check("the mode list ascends without duplicates", sorted, str(launcher.modes))
	check("no mode exceeds the screen", inside, "%s on %s" % [str(launcher.modes), str(screen)])
	check("the screen's own size is listed", launcher.modes.has(screen), str(screen))
	check("a small screen lists only what fits", Launcher.modes_for(Vector2i(1024, 768)) == [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768)], str(Launcher.modes_for(Vector2i(1024, 768))))
	check("an odd screen size is added in order", Launcher.modes_for(Vector2i(1500, 1000)).back() == Vector2i(1500, 1000), str(Launcher.modes_for(Vector2i(1500, 1000))))
	check("the saved resolution is pre-selected", launcher.selected_resolution() == Vector2i(1280, 720) or not launcher.modes.has(Vector2i(1280, 720)), str(launcher.selected_resolution()))
	launcher.fullscreen_tick.toggled.emit(true)
	launcher.borderless_tick.toggled.emit(true)
	check("borderless turns fullscreen off", not launcher.fullscreen and launcher.fullscreen_tick.locked and not launcher.fullscreen_tick.on, "")
	var rects := launcher.mode_rects()
	check("the mode grid wraps into columns of 20 px rows", rects.size() == launcher.modes.size() and rects[0].position == Vector2(39, 204) and rects[1].position.y == 224, str(rects.slice(0, 3)))
	var pick := 0
	launcher.click_at(rects[pick].position + Vector2(5, 5))
	check("clicking a mode selects it", launcher.selected_mode == pick, "")
	launcher.borderless_tick.toggled.emit(false)
	launcher.fullscreen_tick.toggled.emit(true)
	launcher.launcher_tick.toggled.emit(false)
	var launched := [false]
	launcher.launched.connect(func() -> void: launched[0] = true)
	launcher.launch_button.pressed.emit()
	check("LAUNCH stores the choice", launched[0] and GameState.graphic_width == launcher.modes[pick].x and GameState.graphic_height == launcher.modes[pick].y and GameState.fullscreen and not GameState.borderless_windowed and not GameState.launcher_enabled, "%dx%d" % [GameState.graphic_width, GameState.graphic_height])
	var saved := GameState.settings_config()
	check("save_settings carries the launcher keys", saved.get_value("options", "graphic_width") == launcher.modes[pick].x and saved.get_value("options", "fullscreen") == true and saved.get_value("options", "launcher_enabled") == false and saved.get_value("options", "gfx_driver") == 1, "")
	var exited := [false]
	launcher.exited.connect(func() -> void: exited[0] = true)
	launcher.exit_button.pressed.emit()
	check("EXIT asks to quit", exited[0], "")
	launcher.queue_free()
	var ini := IniFile.new()
	ini.sections = {"options": {"width": "1024", "fullscreen": "true", "borderless windowed": "false", "gfx driver": "0"}, "launcher": {"launcher width": "2000", "launcher enabled": "false"}}
	GameState._load_launcher_settings(ini)
	check("the ini bools and limits read like GetINIInt", GameState.graphic_width == 1024 and GameState.fullscreen and not GameState.borderless_windowed and GameState.gfx_driver == 1 and GameState.launcher_width == 1024 and not GameState.launcher_enabled, "")
	check("the bot's boot does not show the launcher", not main._interactive(), "")
	var window := main.get_window()
	var window_keep := {"content_scale_size": window.content_scale_size, "content_scale_aspect": window.content_scale_aspect, "content_scale_mode": window.content_scale_mode, "title": window.title, "scaling_3d_scale": window.scaling_3d_scale}
	WindowSetup.show_launcher(main.get_window())
	for borderless in [false, true]:
		GameState.borderless_windowed = borderless
		GameState.fullscreen = not borderless
		WindowSetup.apply_game(main.get_window())
	GameState.graphic_width = 1280
	GameState.graphic_height = 720
	GameState.fullscreen = false
	GameState.borderless_windowed = false
	WindowSetup.apply_game(main.get_window())
	check("applying the window settings keeps the content size", main.get_window().content_scale_size == Vector2i(1280, 720), str(main.get_window().content_scale_size))
	for key in window_keep:
		window.set(key, window_keep[key])
	for key in keep:
		GameState.set(key, keep[key])
	GameState.launcher_width = keep_size.x
	GameState.launcher_height = keep_size.y
