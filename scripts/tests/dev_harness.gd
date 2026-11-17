extends Node
# Development harness: the scripted probes (SCP_PROBE=1), the bot launcher (SCP_BOT=1) and the
# timed screenshots (SCP_AUTOSHOT=1). Kept out of main.gd so the game script stays the game.

var main: Node
var world: Node3D:
	get:
		return main.world
var facility: FacilityMap:
	get:
		return main.facility

func _shot(label: String) -> void:
	await main._shot(label)

func launch_bot() -> void:
	# A window is focused by the OS the moment it exists, so unless screenshots were asked
	# for, restart without one (headless). The child inherits the bot environment.
	if DisplayServer.get_name() != "headless" and OS.get_environment("SCP_SHOT") != "1" and OS.get_environment("SCP_BOT_CHILD") != "1":
		OS.set_environment("SCP_BOT_CHILD", "1")
		OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://")])
		get_tree().quit()
		return
	SaveGame.dir = "user://saves_bot_%d" % OS.get_process_id()
	# a parse error anywhere in the bot's chain of scripts still loads the last one, but it cannot make an instance: stop
	# with an error instead of leaving the process idle for a runner to wait on
	if OS.get_environment("SCP_DEV") == "1":
		_launch_dev_server()
		return
	var bot_script: GDScript = load("res://scripts/tests/playtest_bot.gd")
	if bot_script == null or not bot_script.can_instantiate():
		push_error("The playtest bot does not compile; `godot --headless --path . -s tests/check_scripts.gd` lists the scripts at fault.")
		get_tree().quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	AudioServer.set_bus_mute(0, true)
	# Never steal focus or the mouse: non-activating window, clicks pass through, cursor untouched.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if OS.get_name() == "Windows" and DisplayServer.get_name() != "headless":
		_send_window_to_back()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await main.start_game()
	var bot: Node = bot_script.new()
	add_child(bot)
	bot.run(main)
	return

func _launch_dev_server() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await main.start_game()
	var server: Node = load("res://scripts/debug/dev_server.gd").new()
	add_child(server)
	server.start(main)

func run_probe() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _shot("00_menu")
	await main.start_game()
	var room := world.get_node("Chamber")
	await get_tree().create_timer(0.6).timeout
	_dump_view(room)
	await _shot("01_chamber")
	await get_tree().create_timer(2.4).timeout
	await _shot("02_flicker")
	await get_tree().create_timer(2.2).timeout
	var player := GameState.player
	var door: Node = room.containment_door
	await _shot("03_blackout")
	print("PROBE player=", player.global_position, " floor=", player.is_on_floor(), " dead=", player.dead, " 173=", GameState.scp173.global_position, " door=", door.global_position, " locked=", door.locked, " open=", door.open, " openstate=", door.openstate)
	if door.leaf_a:
		print("PROBE leaf_a=", door.leaf_a.global_position, " leaf_b=", door.leaf_b.global_position)
	if facility and not facility.active:
		facility.enter_after_breach(player, GameState.scp173, room)
	await get_tree().create_timer(2.0).timeout
	print("PROBE facility ", facility.summarize() if facility else "missing", " loaded=", facility.rooms.built.size() if facility else 0, " player=", player.global_position, " floor=", player.is_on_floor(), " dead=", player.dead, " 173=", GameState.scp173.global_position)
	await _shot("04_facility")
	await _probe_doors()
	await _probe_passage()
	await _probe_door_view()
	await _probe_button_view()
	get_tree().quit()

func _dump_view(room: Node) -> void:
	var player: CharacterBody3D = GameState.player
	var cam: Camera3D = player.camera
	var origin := cam.global_position
	var forward := -cam.global_transform.basis.z
	print("VIEW origin=", origin, " forward=", forward)
	for degrees in [-80, -40, 0, 40, 80]:
		var dir := forward.rotated(Vector3.UP, deg_to_rad(degrees))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 8.0)
		query.collision_mask = 1
		query.exclude = [player]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			print("RAY ", degrees, " miss")
		else:
			print("RAY ", degrees, " dist=", origin.distance_to(hit.position), " pos=", hit.position, " n=", hit.normal)
	var door: Node = room.containment_door
	for leaf_name in ["a", "b"]:
		var leaf: Node3D = door.leaf_a if leaf_name == "a" else door.leaf_b
		var visual := leaf.get_child(0) as MeshInstance3D
		var aabb: AABB = visual.get_aabb()
		var world_aabb := visual.global_transform * aabb
		print("LEAF ", leaf_name, " local=", aabb, " world=", world_aabb, " scale=", visual.scale)

func _probe_doors() -> void:
	var hud_node := get_tree().get_first_node_in_group("hud")
	var door := Node3D.new()
	door.set_script(load("res://scripts/world/facility_door.gd"))
	world.add_child(door)
	door.setup(Vector3(0, -200, 0), 0.0, false, false, false, 1)
	door.use()
	print("PROBE door no-card open=", door.open, " msg=", hud_node.message_label.text)
	var card := Node.new()
	card.set_meta("item_name", "Level 1 Key Card")
	card.set_meta("tempname", "key1")
	hud_node.try_pickup(card)
	hud_node.set_selected(_last_item_slot(hud_node))
	print("PROBE selected=", hud_node.selected_tempname())
	door.use()
	print("PROBE door key1 open=", door.open, " selected_after=", hud_node.selected_tempname(), " msg=", hud_node.message_label.text)
	var heavy := Node3D.new()
	heavy.set_script(load("res://scripts/world/facility_door.gd"))
	world.add_child(heavy)
	heavy.setup(Vector3(5, -200, 0), 0.0, false, false, true, 3)
	hud_node.try_pickup(card)
	hud_node.set_selected(_last_item_slot(hud_node))
	heavy.use()
	print("PROBE heavy key1 open=", heavy.open, " msg=", hud_node.message_label.text)
	heavy.keycard = 0
	heavy.use()
	await get_tree().create_timer(1.5).timeout
	print("PROBE heavy plain open=", heavy.open, " openstate=", heavy.openstate, " leaf_a=", heavy.leaf_a.global_position)
	print("PROBE map doors=", facility.rooms.door_defs.size(), " spawned=", facility.rooms.doors.size())

func _probe_door_view() -> void:
	var player := GameState.player
	for edge in facility.rooms.doors:
		var door: Node3D = facility.rooms.doors[edge]
		if door.global_position.distance_to(player.global_position) > 14.0:
			continue
		player.global_position = door.global_position + door.global_transform.basis.z * 1.3 + Vector3(0, 0.3, 0)
		player.rotation.y = door.rotation.y
		player.camera.rotation.x = 0.0
		print("PROBE doorview edge=", edge, " keycard=", door.keycard, " heavy=", door.heavy, " buttons=", door.buttons.size())
		await get_tree().create_timer(1.0).timeout
		await _shot("05_door")
		return

func _probe_button_view() -> void:
	var player := GameState.player
	for edge in facility.rooms.doors:
		var door: Node3D = facility.rooms.doors[edge]
		if door.buttons.is_empty():
			continue
		var b: Node3D = door.buttons[0]
		player.global_position = b.global_position + door.global_transform.basis.z * 0.5 - Vector3(0, 0.6, 0)
		player.rotation.y = door.rotation.y
		player.camera.rotation.x = 0.0
		var visual := b.get_child(0) as MeshInstance3D
		print("PROBE button pos=", b.global_position, " aabb=", visual.get_aabb().size, " scale=", visual.scale, " surfaces=", visual.mesh.get_surface_count())
		await get_tree().create_timer(1.0).timeout
		await _shot("06_button")
		return

func autoshot() -> void:
	await get_tree().create_timer(7.0).timeout
	await _shot("auto_7s")
	await get_tree().create_timer(3.0).timeout
	await _shot("auto_10s")
	var p := GameState.player
	print("AUTO player=", p.global_position, " floor=", p.is_on_floor(), " rot=", p.rotation_degrees.y, " 173=", GameState.scp173.global_position, " dead=", p.dead)
	get_tree().quit()

func _capsule_blocked(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.15
	shape.height = 1.15
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.575, 0))
	q.collision_mask = 1
	return not get_viewport().world_3d.direct_space_state.intersect_shape(q, 1).is_empty()

func _probe_passage() -> void:
	for kind in ["normal", "heavy", "big_start_open"]:
		var door := Node3D.new()
		door.set_script(load("res://scripts/world/facility_door.gd"))
		world.add_child(door)
		var origin := Vector3(40.0 + 8.0 * ["normal", "heavy", "big_start_open"].find(kind), -300.0, 0.0)
		door.setup(origin, 0.0, kind == "big_start_open", kind == "big_start_open", kind == "heavy", 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var closed_blocked := _capsule_blocked(origin)
		if kind != "big_start_open":
			door.use()
			await get_tree().create_timer(2.5).timeout
		else:
			await get_tree().create_timer(0.3).timeout
		var open_blocked := _capsule_blocked(origin)
		print("PROBE passage ", kind, " closed_blocked=", closed_blocked, " open_blocked=", open_blocked, " leaf_a_dx=", snappedf(door.leaf_a.global_position.x - origin.x, 0.001), " leaf_b_dx=", snappedf(door.leaf_b.global_position.x - origin.x, 0.001), " leaf_z=", snappedf(door.leaf_a.global_position.z - origin.z, 0.001), "/", snappedf(door.leaf_b.global_position.z - origin.z, 0.001))

# Bot windows (screenshot runs): bottom of the z-order, far off every monitor, no taskbar entry,
# never activated. Windows only; the encoded command avoids shell quoting problems.
func _send_window_to_back() -> void:
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var source := "Add-Type 'using System;using System.Runtime.InteropServices;public class W{[DllImport(\"user32.dll\")]public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int cx,int cy,uint f);[DllImport(\"user32.dll\")]public static extern int GetWindowLong(IntPtr h,int i);[DllImport(\"user32.dll\")]public static extern int SetWindowLong(IntPtr h,int i,int v);}'; $h=[IntPtr]%d; [void][W]::SetWindowLong($h,-20,([W]::GetWindowLong($h,-20) -bor 0x80 -bor 0x08000000)); [void][W]::SetWindowPos($h,[IntPtr]1,-30000,-30000,0,0,0x0011)" % hwnd
	var encoded := Marshalls.raw_to_base64(source.to_utf16_buffer())
	OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", encoded])

func _last_item_slot(hud_node: Node) -> int:
	var last := -1
	for i in hud_node.items.size():
		if not hud_node.items[i].is_empty():
			last = i
	return last

func _launcher_shots() -> void:
	WindowSetup.show_launcher(get_window())
	var launcher := Launcher.new()
	main.add_child(launcher)
	await get_tree().create_timer(0.5).timeout
	await main._shot("launcher")
	launcher.borderless_tick.toggled.emit(true)
	launcher.selected_mode = 0
	await get_tree().create_timer(0.3).timeout
	await main._shot("launcher_borderless")
	launcher.borderless_tick.toggled.emit(false)
	launcher.fullscreen_tick.toggled.emit(true)
	await get_tree().create_timer(0.3).timeout
	await main._shot("launcher_fullscreen")
	launcher.queue_free()
	WindowSetup.apply_game(get_window())

# SCP_MENUSHOT=1 SCP_SHOT=1: screenshots of the main menu tabs, the options tabs (with a tooltip) and a loading screen.
func menu_shots() -> void:
	await _launcher_shots()
	await get_tree().create_timer(1.0).timeout
	main.menu._blink_173.visible = true
	await main._shot("menu_main")
	main.menu._open_new_game()
	await get_tree().create_timer(0.4).timeout
	await main._shot("menu_newgame")
	main.menu.difficulty = GameState.CUSTOM
	main.menu._rebuild()
	await get_tree().create_timer(0.4).timeout
	await main._shot("menu_newgame_custom")
	main.menu._set_tab(2)
	await get_tree().create_timer(0.4).timeout
	await main._shot("menu_loadgame")
	for tab in [3, 5, 6, 7]:
		main.menu._set_tab(tab)
		await get_tree().create_timer(0.3).timeout
		var panel: Control = main.menu._options
		if not panel._tips.is_empty():
			panel._shown_tip = 0
			panel._tip_layer.queue_redraw()
			panel.set_process(false)
		await get_tree().create_timer(0.2).timeout
		await main._shot("menu_options_%d" % tab)
	main.menu._set_tab(0)
	var screen: Node = main._loading_screen()
	screen.show_percent(0)
	screen.show_percent(100)
	await get_tree().create_timer(0.4).timeout
	await main._shot("loading_100")
	screen.queue_free()
	main.start_game_with_loading()
	await get_tree().create_timer(4.0).timeout
	await main._shot("loading_newgame")
	print("MENUSHOT paused behind the loading screen: ", get_tree().paused)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	Input.parse_input_event(key)
	await get_tree().create_timer(1.5).timeout
	print("MENUSHOT paused after a key: ", get_tree().paused, " menu visible: ", main.menu.visible)
	await main._shot("after_loading")
	get_tree().quit()
