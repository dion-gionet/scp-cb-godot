extends Node
# Scripted playtest. Run windowed:  SCP_BOT=1 SCP_SHOT=1 Godot --path .
# Drives the real game through input actions and physics, writes tests/bot_report.txt.

var main: Node
var facility: FacilityMap
var player: CharacterBody3D
var statue: CharacterBody3D
var lines: Array[String] = []
var failures := 0
var checks := 0
var frame_max := 0.0
var frame_sum := 0.0
var frame_count := 0

var _home_player := Vector3.ZERO
var _home_player_yaw := 0.0
var _home_statue := Vector3.ZERO
const FAST := ["spawn", "stamina_blink", "173", "rules173", "doors", "items", "use", "ui", "stairs", "audio", "pathfind"]
const FULL_EXTRA := ["fxplayer", "decalload", "spriteedges", "lockroom2blood", "fxrooms", "startsmoke", "fxgates", "blitzmap", "seedevents", "facing", "gaps", "173doors", "far173", "mtfcross", "registry", "persist", "keypad", "screens", "elevator", "controller", "debug", "scp049", "scp106", "spawn049", "securitycam", "pocket", "pocketkneel", "guard", "classd", "doorspam", "movedbuttons", "doorbuttons", "scp008room", "checkpoint2", "force106", "chase106", "pocketwalk", "mapmodels", "unlitx2", "infection", "lever", "mtfcamera", "checkpoint", "room2sl", "room2slsave", "pocketnote", "savegaps", "filldecals", "room2slwalk", "mtf", "mtfdirector", "mtfwalk", "startscene", "b3dtex", "facing106model", "facing049model", "hazmat049", "perf", "unlit", "saveload", "fog", "lightfx", "nvg", "zombie008", "medibay", "scp096", "slam096", "servers", "mouseopts", "ending", "gateb", "gateb2", "gatea", "gatea2", "gate079", "femur", "scp914", "scp294", "items2", "room049", "scp966", "scp1499", "radionav", "scp1025", "containers", "coffin", "room860", "console", "ambient", "particles", "tesla", "room012", "room1162", "ambient2", "ambient3", "ambient4", "sllockdown", "049doors", "roomdraw", "room205", "room035", "room939", "room2scps2", "room1123vision", "room3servers", "smallnpcs", "lastrooms", "pitduck", "offices2duck", "actorsave", "slresume", "distantevent", "room1archive", "menus", "launcher", "startup", "lift2cab", "proprotation", "storagebuttons", "booth914", "npcgravity", "doorguard", "itemguard", "broadcast", "sparks", "entitylight", "dreamblur", "viewfx", "pocketface", "npcmusic", "lockroomlamp", "lampflare", "room035lamp", "startscenesave", "startalarmend", "roomambience", "maintenance", "golden"]
const TOOLS := ["alphatex", "gateload", "cones", "mtfhitch", "glassview", "orbit", "strafe", "doorview", "fillview", "gapsall", "startroom", "startmap", "monprobe", "cafe", "glowview", "cafetop", "nearstart", "spawnview", "introview", "starttop", "startfloors", "lightsum", "rmeshtypes", "roomviews", "glowspawn", "leverview", "zombie049view", "buildall", "ablate", "hitchhunt"]
func _process(delta: float) -> void:
	frame_max = maxf(frame_max, delta)
	frame_sum += delta
	frame_count += 1

func run(main_node: Node) -> void:
	main = main_node
	facility = main.facility
	if OS.get_environment("SCP_INTRO") == "1":
		# the intro test plays the real intro; nothing else may reset the world around it
		player = GameState.player
		statue = GameState.scp173
		GameState.player_died.connect(func(message: String) -> void: log_line("   (the player died: %s)" % message.left(90)))
		await secs(0.3)
		await call("_scn_" + OS.get_environment("SCP_BOT_ONLY"))
		_finish()
		return
	var waited := 0.0
	while not facility.active and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	player = GameState.player
	statue = GameState.scp173
	if not facility.active:
		check("breach reaches facility", false, "facility never became active after %.0fs" % waited)
		_finish()
		return
	await secs(1.0)
	_home_player = player.global_position
	_home_player_yaw = player.rotation.y
	_home_statue = statue.global_position
	GameState.player_died.connect(func(message: String) -> void: log_line("   (the player died: %s)" % message.left(90)))
	var wanted := _selected_scenarios()
	var table := _scenario_table()
	for name in wanted:
		if not table.has(name):
			check("known scenario '%s'" % name, false, "see SCENARIOS in playtest_bot.gd")
			continue
		if not table[name].is_valid():
			check("scenario '%s' is defined" % name, false, "no method for it in the bot's scripts")
			continue
		await _reset_world()
		var began := Time.get_ticks_msec()
		await table[name].call()
		log_line("-- %s: %.1fs" % [name, (Time.get_ticks_msec() - began) / 1000.0])
	_finish()

# Every scenario starts from the same world: player and 173 at their spawn spots, alive,
# no god mode or noclip, no keys held, all rooms built.

func _reset_world() -> void:
	GameState.super_man = false
	GameState.super_man_timer = 0.0
	for action in InputMap.get_actions():
		Input.action_release(action)
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		Input.parse_input_event(release)
	GameState.god_mode = false
	GameState.noclip = false
	facility.drawing.enabled = true
	if facility.ambient != null:
		facility.ambient.enabled = false      # the ambient events move 173, 096 and the player; only their own scenario wants them
	facility.active = true   # the world is active
	facility.spawn_049_enabled = false   # tests place 049 themselves
	facility.spawn_106_enabled = false
	facility.start_scene_enabled = false
	if facility.start_scene != null and is_instance_valid(facility.start_scene):
		facility.start_scene.set_physics_process(false)
		facility.start_scene.queue_free()
	facility.start_scene = null
	for stray106 in get_tree().get_nodes_in_group("scp106"):
		stray106.queue_free()
	facility.scp106 = null
	for human in facility.humans.duplicate():
		facility.remove_human(human)
	for unit in facility.mtf.units.duplicate():
		facility.mtf.remove(unit)
	facility.mtf.timer = 0.0
	for node in [facility.events.room079.voice, facility.events.femur.voice, facility.events.femur.radio_static]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if facility.events.femur.subject != null and is_instance_valid(facility.events.femur.subject):
		facility.remove_human(facility.events.femur.subject)
	facility.events.reset()
	facility.events.sl.lever_on = false
	for stray_zombie in facility.zombies008.duplicate():
		facility.remove_zombie008(stray_zombie)
	for stray_966 in facility.scp966s.duplicate():
		facility.remove_scp966(stray_966)
	if facility.dimension != null:
		facility.dimension.reset()
	GameState.wearing_1499 = 0
	GameState.coffin_distance = 100.0
	GameState.restore_sanity = true
	GameState.step_set = 0
	GameState.is_zombie = false
	GameState.force_move = 0.0
	GameState.secondary_light = 1.0
	for stray096 in get_tree().get_nodes_in_group("scp096"):
		stray096.queue_free()
	facility.scp096 = null
	facility.spawn_096_rooms = false
	facility._lockroom096_done = false
	facility.contained_106 = false
	facility.rooms.reset_gate_a()
	facility.nuke_remote_on = false
	facility.nuke_lever_pitch = INF
	facility.explosion_ending = ""
	for stray_apache in get_tree().get_nodes_in_group("apache"):
		stray_apache.queue_free()
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.ambient_override = -1.0
	GameState.explosion_timer = 0.0
	GameState.light_flash = 0.0
	GameState.selected_ending = ""
	GameState.unable_to_move = false
	facility.remote_door_on = true
	facility.ccont_pitches = [10.0, 10.0, 10.0]
	facility.ccont_state = 0.0
	_reset_levers()
	facility.gate_a_unlocked = false
	facility.gate_b_unlocked = false
	GameState.secondary_light = 1.0
	GameState.infect = 0.0
	facility.mtf.camera_check_timer = 0.0
	facility.mtf.camera_check_detected = false
	facility.mtf.player_detected = false
	facility.mtf.enabled = false
	facility.mtf.announcements.clear()
	statue.idle = 0
	statue.target_node = null
	GameState.death_msg = ""
	player.fall_timer = 0.0
	if facility.pocket != null:
		facility.pocket.player_inside = false
		facility.pocket.set_shown(false)
		facility.pocket._unfog()
	GameState.music_override = ""
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	GameState.sanity = 0.0
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	GameState.heal_timer = 0.0
	GameState.vomit_timer = 0.0
	GameState.vomit = false
	GameState.death_timer = 0.0
	GameState.stamina_effect = 1.0
	GameState.stamina_effect_timer = 0.0
	GameState.blink_effect = 1.0
	GameState.blink_effect_timer = 0.0
	GameState.eye_irritation = 0.0
	GameState.i427_using = false
	GameState.i427_timer = 0.0
	GameState.scp1025 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if facility.scp049 != null and is_instance_valid(facility.scp049):
		facility.scp049.queue_free()
	facility.scp049 = null
	if facility.room2sl_scene != null and is_instance_valid(facility.room2sl_scene):
		facility.room2sl_scene.queue_free()
	facility.room2sl_scene = null
	for stray in get_tree().get_nodes_in_group("scp049"):
		stray.queue_free()
	revive()
	GameState.wearing_gas_mask = 0
	GameState.wearing_vest = 0
	GameState.wearing_hazmat = 0
	GameState.wearing_night_vision = 0
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	GameState.eye_stuck = 0.0
	player.stamina = 100.0
	player.crouching = false
	var hud_node := get_tree().get_first_node_in_group("hud")
	if hud_node != null and hud_node.item_use != null:
		hud_node.item_use.tempname = ""
		hud_node.item_use.progress = 0.0
	player.velocity = Vector3.ZERO
	player.global_position = _home_player
	player.rotation.y = _home_player_yaw
	player.camera.rotation.x = 0.0
	place_statue(_home_statue)
	facility.after_teleport()
	await secs(0.5)
	statue.active = true     # only now: 173 must not catch the player while the world is rebuilt
	revive()

# The levers keep their handles between scenarios: back to the pitches the event state holds, the others to the default 10.
func _reset_levers() -> void:
	facility.events.sl.lever_pitch = 10.0
	SaveGame._restore_event_nodes(main, facility)
	for key in facility.rooms.built:
		var room: FacilityRoom = facility.rooms.built[key]
		if room.extras == null:
			continue
		if room.room_name == "room2nuke":
			room.extras.levers[0].pitch = 10.0
		elif room.room_name == "coffin":
			room.extras.lever.pitch = 10.0

# SCP_BOT_ONLY: a scenario name, a comma list, or a set name. Default is "fast".
#   fast  - the checks worth running after every change (one seed, a couple of minutes)
#   full  - fast plus the slower or rarer ones (use before calling a phase done)
#   tools - screenshot and map dumpers, never part of a test run

func _selected_scenarios() -> Array:
	var raw := OS.get_environment("SCP_BOT_ONLY").strip_edges()
	if raw.is_empty() or raw == "fast":
		return FAST
	if raw == "full":
		return FAST + FULL_EXTRA
	if raw == "tools":
		return TOOLS
	return Array(raw.split(",", false))

func _scenario_table() -> Dictionary:
	# name -> the `_scn_<method>` it runs (looked up on the final class of the chain)
	var methods := {
		"spawn": "spawn", "stamina_blink": "stamina_blink", "golden": "golden", "173": "173", "rules173": "173_rules",
		"facing": "173_facing", "173doors": "173_doors", "far173": "far173", "mtfcross": "mtfcross", "doors": "doors", "gaps": "gaps",
		"registry": "registry", "items": "items", "use": "use", "persist": "persist",
		"keypad": "keypad", "screens": "screens", "elevator": "elevator", "controller": "controller", "debug": "debug",
		"stairs": "stairs", "audio": "audio", "pathfind": "pathfind", "perf": "perf", "buildall": "buildall", "ablate": "ablate",
		"scp049": "scp049", "introdoorview": "introdoorview", "introcam": "introcam", "securitycam": "securitycam", "introrefuse": "introrefuse", "introleaflet": "introleaflet", "introslow": "introslow", "cellfloor": "cellfloor", "intro": "intro", "spawn049": "spawn049", "startscene": "startscene", "startscenesave": "startscenesave", "startalarmend": "startalarmend", "triggers": "triggers", "humanshots": "humanshots", "guard": "guard", "classd": "classd", "doorspam": "doorspam", "movedbuttons": "movedbuttons", "doorbuttons": "doorbuttons", "scp008room": "scp008room", "force106": "force106", "infection": "infection", "checkpoint2": "checkpoint2", "lever": "lever", "mtfcamera": "mtfcamera", "checkpoint": "checkpoint", "slview": "slview", "room2sl": "room2sl", "room2slsave": "room2slsave", "pocketnote": "pocketnote", "savegaps": "savegaps", "filldecals": "filldecals", "room2slwalk": "room2slwalk", "pickupsnear": "pickupsnear", "mtf": "mtf", "mtfdirector": "mtfdirector", "mtfshots": "mtfshots", "mtfwalk": "mtfwalk", "humanview": "humanview", "b3dtex": "b3dtex", "view049head": "view049head", "scp106": "scp106", "chase106": "chase106", "npcmusic": "npcmusic", "pocketwalk": "pocketwalk", "pocketkneel": "pocketkneel", "pocketface": "pocketface", "pocketlook": "pocketlook", "pocket": "pocket", "facing106model": "facing_106_model", "hazmat049": "hazmat049", "ui": "ui", "uishots": "uishots", "menus": "menus",
		"saveload": "saveload", "monprobe": "monprobe", "cafe": "cafe", "glowview": "glowview", "cafetop": "cafetop", "nearstart": "nearstart", "spawnview": "spawnview", "introview": "introview", "starttop": "starttop", "startfloors": "startfloors", "lightsum": "lightsum", "rmeshtypes": "rmeshtypes", "roomviews": "roomviews", "glowspawn": "glowspawn", "leverview": "leverview", "zombie049view": "zombie049view", "fog": "fog", "gatea": "gatea", "gate079": "gate079", "femur": "femur", "scp914": "scp914", "roomambience": "roomambience", "maintenance": "maintenance", "scp294": "scp294", "items2": "items2", "room049": "room049", "scp966": "scp966", "scp1499": "scp1499", "radionav": "radionav", "scp1025": "scp1025", "containers": "containers", "coffin": "coffin", "room860": "room860", "console": "console", "ambient": "ambient", "particles": "particles", "tesla": "tesla", "room012": "room012", "room1162": "room1162", "room205": "room205", "room035": "room035", "room939": "room939", "room1123vision": "room1123vision", "room3servers": "room3servers", "smallnpcs": "smallnpcs", "lastrooms": "lastrooms", "pitduck": "pitduck", "offices2duck": "offices2duck", "actorsave": "actorsave", "slresume": "slresume", "distantevent": "distantevent", "room1archive": "room1archive", "room2scps2": "room2scps2", "ambient2": "ambient2", "ambient3": "ambient3", "ambient4": "ambient4", "sllockdown": "sllockdown", "049doors": "049doors", "drawperf": "drawperf", "roomdraw": "roomdraw", "gatea2": "gatea2", "gateb2": "gateb2", "gateb": "gateb", "ending": "ending", "mouseopts": "mouseopts", "launcher": "launcher", "startup": "startup", "servers": "servers", "slam096": "slam096", "scp096": "scp096", "medibay": "medibay", "zombie008": "zombie008", "nvg": "nvg", "entitylight": "entitylight", "lightfx": "lightfx", "lockroomlamp": "lockroomlamp", "lampflare": "lampflare", "room035lamp": "room035lamp", "alphatex": "alphatex", "gateload": "gateload", "cones": "cones", "mtfhitch": "mtfhitch", "hitchhunt": "hitchhunt", "glassview": "glassview", "brushfx": "brushfx", "see106": "see106", "filldoors": "filldoors", "orbit": "orbit", "strafe": "strafe", "soak": "soak", "deathcam": "deathcam", "roomprops": "roomprops", "blitzmap": "blitzmap", "seedevents": "seedevents", "checkpointgear": "checkpointgear",
		"doorview": "doorview", "doormesh": "doormesh", "fillview": "fillview", "gapsall": "gaps_all", "mapmodels": "mapmodels", "unlitx2": "unlitx2",
		"startroom": "startroom", "startmap": "startmap", "startdoors": "startdoors",
		"exitdoor": "exitdoor", "neighbors": "neighbors", "nextroom": "nextroom", "unlit": "unlit",
		"pockets": "pockets", "viewpoint": "viewpoint", "litview": "litview", "facing049": "facing049", "facing106": "facing106", "feet106": "feet106", "facing049model": "facing_049_model", "modelview": "modelview",
		"lift2cab": "lift2cab", "proprotation": "proprotation", "storagebuttons": "storagebuttons", "booth914": "booth914", "npcgravity": "npcgravity", "doorguard": "doorguard", "itemguard": "itemguard", "fxplayer": "fxplayer", "startsmoke": "startsmoke", "decalload": "decalload", "spriteedges": "spriteedges", "lockroom2blood": "lockroom2blood", "fxrooms": "fxrooms", "fxgates": "fxgates", "broadcast": "broadcast", "sparks": "sparks", "dreamblur": "dreamblur", "viewfx": "viewfx",
	}
	var table := {}
	for key in methods:
		table[key] = Callable(self, "_scn_" + methods[key])
	return table

func secs(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame

func shot(label: String) -> void:
	await main._shot(label)

func revive() -> void:
	player.dead = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.death.visible = false
		hud.pause_menu.close()
		hud._fade.color.a = 0.0
		get_tree().paused = false

func place_player(pos: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = pos
	facility.after_teleport()

func place_statue(pos: Vector3) -> void:
	statue.velocity = Vector3.ZERO
	statue.global_position = pos
	statue.floor_y = pos.y

func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func face_point(point: Vector3) -> void:
	var d: Vector3 = point - player.global_position
	player.rotation.y = atan2(-d.x, -d.z)
	player.camera.rotation.x = 0.0

func blocked(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.15
	shape.height = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3, 0))
	q.collision_mask = 1
	q.exclude = [player]
	return not get_viewport().world_3d.direct_space_state.intersect_shape(q, 1).is_empty()

func ray_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [player]
	return not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty()

func log_line(text: String) -> void:
	lines.append(text)
	print("BOT ", text)

# tests/fixtures/original.json: the original's numbers (derived from the Blitz code or measured in the running game).
var _fixtures: Dictionary = {}

func golden(name: String) -> Dictionary:
	if _fixtures.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original.json"))
		_fixtures = parsed if parsed is Dictionary else {"_broken": true}
	return _fixtures.get(name, {})

# Checks a port measurement against the original's value for `name`, within its tolerance.
func check_golden(name: String, measured: float) -> void:
	var want := golden(name)
	if want.is_empty():
		check("fixture '%s' exists in tests/fixtures/original.json" % name, false)
		return
	var ok := absf(measured - float(want.value)) <= float(want.tol)
	check("%s matches the original (%s, %s)" % [name, want.source, want.ref], ok, "port %.3f, original %.3f +- %.3f %s" % [measured, float(want.value), float(want.tol), want.unit])

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	var suffix := ("  [" + detail + "]") if not detail.is_empty() else ""
	log_line("%s  %s%s" % ["PASS" if ok else "FAIL", label, suffix])

func _finish() -> void:
	var avg := frame_sum / maxf(float(frame_count), 1.0)
	log_line("frames=%d avg=%.1fms  window focused=%s mouse_mode=%d no_focus_setting=%s override=%s" % [frame_count, avg * 1000.0, DisplayServer.window_is_focused(), Input.mouse_mode, str(ProjectSettings.get_setting("display/window/size/no_focus", "unset")), ProjectSettings.has_setting("display/window/size/no_focus")])
	if checks == 0:
		# nothing ran (a scenario died before its first check): that is not a pass
		failures += 1
		log_line("FAIL  no check ran")
	log_line("RESULT %s (%d failures, %d checks)" % ["PASS" if failures == 0 else "FAIL", failures, checks])
	var report := OS.get_environment("SCP_REPORT")
	if report.is_empty():
		report = "res://tests/bot_report.txt"
	var path := ProjectSettings.globalize_path(report)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines) + "\n")
	get_tree().quit(1 if failures > 0 else 0)

func plane_scan(door: Node3D) -> String:
	var dir: Vector3 = door.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var side: Vector3 = door.global_transform.basis.x
	var out := ""
	for h in [0.2, 0.7, 1.2, 1.8, 2.4]:
		var row := ""
		for dx in [-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2]:
			var base: Vector3 = door.global_position + side * dx + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(base + dir * 1.0, base - dir * 1.0)
			q.collision_mask = 1
			q.exclude = [player]
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				row += "."
			else:
				var c: Node = hit.collider
				var owner_name := str(c.get_parent().name) if c.get_parent() else ""
				row += "R" if owner_name.begins_with("Room_") else "D"
		out += " h%.1f:%s" % [h, row]
	return out

func _arena(origin: Vector3) -> Node3D:
	var arena := Node3D.new()
	arena.position = origin
	get_tree().root.add_child(arena)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	col.shape = box
	col.position.y = -0.5
	body.add_child(col)
	arena.add_child(body)
	return arena

func _give(hud: Node, item_name: String, tempname: String) -> int:
	var node := Node.new()
	node.set_meta("item_name", item_name)
	node.set_meta("tempname", tempname)
	node.set_meta("icon", str(RoomFill.item_template(item_name).get("icon", "GFX/items/INVpaper.png")))
	hud.try_pickup(node)
	node.free()
	var slot := -1
	for i in hud.items.size():
		if hud.items[i] == item_name:
			slot = i
	return slot

# Each button is a Control whose gui_input signal the real mouse reaches; emit it with a click.
func _click_key(pad: Node, index: int) -> void:
	var cell: Control = pad._cells[index - 1]
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = cell.size * 0.5
		cell.gui_input.emit(click)
	await get_tree().process_frame

func _type_code(pad: Node, digits: String) -> void:
	var index_of := {"1": 1, "2": 2, "3": 3, "0": 4, "4": 5, "5": 6, "6": 7, "7": 9, "8": 10, "9": 11}
	for ch in digits:
		await _click_key(pad, index_of[ch])

# Which way the statue's face points (its model is mounted at a half turn on the body).
func _statue_face_dir() -> Vector3:
	var visual: Node3D = statue.get_node("MeshInstance3D")
	var f: Vector3 = visual.global_transform.basis.z   # the face is on the model's +Z side
	f.y = 0.0
	return f.normalized()

func _ray_dist(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, exclude: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.5)
	q.collision_mask = 1
	q.exclude = exclude
	q.hit_from_inside = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 9.99
	return from.distance_to(hit.position)

# A point `distance` from `center` on the floor with a clear line between them.
func _clear_spot(center: Vector3, distance: float) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var spot := center + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.0, 0), spot + Vector3(0, -2.0, 0))
		q.collision_mask = 1
		var floor_hit := space.intersect_ray(q)
		if floor_hit.is_empty() or absf(floor_hit.position.y - center.y) > 0.4:
			continue
		var at: Vector3 = floor_hit.position
		if not ray_blocked(center + Vector3(0, 0.3, 0), at + Vector3(0, 0.3, 0)) and not blocked(at + Vector3(0, 0.3, 0)):
			return at
	return Vector3.INF

func _click(hud: Node, position_value: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position_value
	hud._inventory._gui_input(event)
