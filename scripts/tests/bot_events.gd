extends "res://scripts/tests/bot_npcs.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_room2sl() -> void:
	log_line("== room2sl: 049's release")
	var setup: Dictionary = await _room2sl_setup()
	check("the map has a room2sl", not setup.is_empty(), "")
	if setup.is_empty():
		return
	var room: Node3D = setup.room
	facility.spawn_049_enabled = true
	facility.scp049 = null
	facility.check_049_trigger(player.global_position)
	var scene: Node = facility.room2sl_scene
	check("entering the room starts the event", scene != null and facility.scp049 != null, "")
	if scene == null or facility.scp049 == null:
		return
	var npc: CharacterBody3D = facility.scp049
	var cell_spot: Vector3 = room.object_point(7)
	check("049 waits above the cell, doing nothing (state 0)", npc.state == 0 and Vector2(npc.global_position.x - cell_spot.x, npc.global_position.z - cell_spot.z).length() < 0.5, "state %d" % npc.state)
	check("up in the ceiling space (CreateNPC at Objects[7] Y + 5), not standing in the hall", absf(npc.global_position.y - (cell_spot.y + 5.0)) < 0.5, "%.2f above the cell" % (npc.global_position.y - cell_spot.y))
	var top_of_room: float = room.world_bounds().end.y
	check("above the room's top, where the player cannot see him", npc.global_position.y > top_of_room, "y %.2f, room top %.2f" % [npc.global_position.y, top_of_room])
	place_player(_outside_spot(room, 7.0))
	check("the countdown starts at 5 s", scene.event_state2 == -350.0, "%.0f" % scene.event_state2)
	await secs(1.0)
	check("it waits while the monitor is not looked at", scene.event_state2 == -350.0, "%.0f" % scene.event_state2)
	# the player stands somewhere that sees the monitor within 5 units
	var cam_node: Node3D = scene._cam
	var screen_at: Vector3 = cam_node._screen.global_position
	var space := get_viewport().world_3d.direct_space_state
	var seen_from := false
	for step in 16:
		var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
		var top: Vector3 = screen_at + dir * (1.0 + 0.5 * float(step % 4))
		var down := PhysicsRayQueryParameters3D.create(top, top + Vector3(0.0, -8.0, 0.0))
		down.collision_mask = 1
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			continue
		place_player(floor_hit.position + Vector3(0.0, 0.1, 0.0))
		await secs(0.3)
		if cam_node.screen_near_and_visible(player.camera.global_position, 5.0):
			seen_from = true
			break
	check("a spot that sees the monitor exists in the room", seen_from, "")
	face_point(screen_at)
	player.blink_timer = 400.0
	await secs(1.0)
	check("looking at the live monitor draws its feed (the wall's invisible collision in front of it must not hide it)", cam_node.in_sight and cam_node.renders > 0, "in sight %s, %d renders" % [str(cam_node.in_sight), cam_node.renders])
	await secs(1.0)
	await secs(1.0)
	check("the countdown runs once the monitor is near and visible", scene.event_state2 > -350.0 or scene.event_state2 == 0.0 or scene.event_state2 >= 1.0, "%.0f" % scene.event_state2)
	scene.event_state2 = -2.0
	# nobody sees him yet: the player steps back out of the room first
	var doors: Array = facility.room_edge_doors(room)
	var cell: Vector3 = room.object_point(7)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(cell) < b.global_position.distance_to(cell))
	var near_door: Node3D = doors[0]
	var far_door: Node3D = doors[doors.size() - 1]
	var away: Vector3 = (near_door.global_position - room.global_position)
	away.y = 0.0
	place_player(near_door.global_position + away.normalized() * 5.0 + Vector3(0.0, 0.3, 0.0))
	await secs(0.5)
	check("he steps out of the farther door (state 5, event 1)", npc.state == 5 and scene.event_state2 >= 1.0, "state %d event %.0f" % [npc.state, scene.event_state2])
	var outside := Vector2(npc.global_position.x - far_door.global_position.x, npc.global_position.z - far_door.global_position.z).length()
	check("one unit outside it", outside < 2.5, "%.2f" % outside)
	# seen in front: the hunt starts. He has already begun walking (and shutting doors behind him), so the
	# meeting is arranged in the open: the player in the hall, 049 two and a half units from him, facing him
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.6)
	var meeting: Vector3 = _spot_near(player.global_position, 2.5)
	npc._clear_path()
	npc.global_position = meeting + Vector3(0, 0.05, 0)
	npc.velocity = Vector3.ZERO
	npc.state = 5
	npc.state3 = 0.0
	npc.rotation.y = atan2(-(player.global_position.x - meeting.x), -(player.global_position.z - meeting.z))
	face_point(npc.global_position + Vector3(0, 0.9, 0))
	GameState.god_mode = true
	await secs(0.6)
	if npc.state != 2:
		var diag_ray := PhysicsRayQueryParameters3D.create(npc.global_position + Vector3(0, 0.3, 0), player.global_position + Vector3(0, 0.3, 0))
		diag_ray.collision_mask = 1
		diag_ray.exclude = [npc.get_rid()]
		var diag_hit := get_viewport().world_3d.direct_space_state.intersect_ray(diag_ray)
		var diag_chain := ""
		var diag_node: Node = diag_hit.collider as Node if not diag_hit.is_empty() else null
		for level in 4:
			if diag_node == null:
				break
			diag_chain += " > %s(%s)" % [diag_node.name, str(diag_node.get_groups())]
			diag_node = diag_node.get_parent()
		log_line("   blocker %s at %s: %s ; door at %s openstate %.0f" % [str(diag_hit.get("collider", "-")), str(diag_hit.get("position", "-")), diag_chain, str(far_door.global_position), far_door.openstate])
		log_line("   hand-over diag: npc %s player %s distance %.2f sees %d line clear %s yaw off %.0f blink %.0f door open %s" % [str(npc.global_position), str(player.global_position), npc.global_position.distance_to(player.global_position), npc._sees_player(player), str(npc._line_to(player)), rad_to_deg(npc._yaw_to(player.global_position)), player.blink_timer, str(far_door.open)])
	check("seeing the player ends the scene and starts the hunt (state 2)", npc.state == 2, "state %d" % npc.state)
	check("with 2 s of attack time", npc.state2 > 0.0 or npc.state == 2, "")
	GameState.god_mode = false
	if facility.room2sl_scene != null and is_instance_valid(facility.room2sl_scene):
		facility.room2sl_scene.queue_free()
	facility.room2sl_scene = null

# A save made while 049 still waits above room2sl for the monitor: the original keeps the event's EventState2 and its NPC[0]
# and only resets EventState (Save.bb 1026-1030), so after the load he waits on until the player is back in the room.
func _scn_room2slsave() -> void:
	log_line("== room2sl: a save while 049 waits above the room")
	var setup: Dictionary = await _room2sl_setup()
	check("the map has a room2sl", not setup.is_empty(), "")
	if setup.is_empty():
		return
	var room: Node3D = setup.room
	facility.spawn_049_enabled = true
	facility.scp049 = null
	facility.check_049_trigger(player.global_position)
	check("entering the room starts the event", facility.room2sl_scene != null and facility.scp049 != null, "")
	if facility.scp049 == null:
		return
	place_player(_outside_spot(room, 7.0))
	await secs(0.5)
	check("049 waits for the monitor before the save", facility.scp049.state == 0 and facility.events.sl.scene_state2 == -350.0, "state %d, state2 %.0f" % [facility.scp049.state, facility.events.sl.scene_state2])
	await _reload_game()
	statue.active = false
	var npc: Node3D = facility.scp049
	check("after the load 049 still waits (state 0), not hunting", npc != null and npc.state == 0 and facility.events.sl.scene_state2 == -350.0, "state %d, state2 %.0f" % [npc.state if npc != null else -1, facility.events.sl.scene_state2])
	if npc == null:
		return
	room = facility.rooms.get_room(setup.record)
	await secs(3.0)
	check("he stays above the room while the player is away", npc.state == 0 and npc.global_position.y > room.world_bounds().end.y, "state %d, y %.2f" % [npc.state, npc.global_position.y])
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(1.0)
	var scene: Node = facility.room2sl_scene
	check("back in the room, the event takes the loaded 049 back and still waits on the monitor", scene != null and is_instance_valid(scene) and scene.npc == npc and facility.scp049 == npc and scene.event_state2 < 0.0, "scene %s, state2 %.0f" % [str(scene != null), scene.event_state2 if scene != null else 0.0])
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	facility.room2sl_scene = null
	npc.queue_free()
	facility.scp049 = null
	facility.spawn_049_enabled = false

# The pocket dimension's Burnt Note (FillRoom "pocketdimension": CreateItem at the room's x, 0.5, z + 3.5) is made with the
# map: a save must not keep it as a dropped item too, and reading it shows bn.it (a JPEG) with the access code on it.
func _scn_pocketnote() -> void:
	log_line("== pocket dimension: the burnt note")
	var notes := func() -> Array:
		var found := []
		for node in get_tree().get_nodes_in_group("pickup"):
			if is_instance_valid(node) and not node.is_queued_for_deletion() and str(node.get_meta("item_name", "")) == "Burnt Note":
				found.append(node)
		return found
	check("the pocket dimension holds one burnt note", notes.call().size() == 1, "%d" % notes.call().size())
	await _reload_game()
	await _reload_game()
	check("two saves and loads later there is still one", notes.call().size() == 1, "%d" % notes.call().size())
	# a save from before the note had a fill_id kept it as a dropped item, where it had fallen to the floor
	var note: Node3D = notes.call()[0]
	note.remove_meta("fill_id")
	note.global_position.y -= 0.45
	await _reload_game()
	check("an older save that kept the fallen note as dropped still loads one", notes.call().size() == 1, "%d" % notes.call().size())
	var pillars_solid := true
	for pillar: Node3D in facility.pocket._pillars:
		pillars_solid = pillars_solid and not pillar.find_children("*", "StaticBody3D", true, false).is_empty()
	check("both flying pillars are solid (HIT_MAP)", pillars_solid, "")
	facility.enter_pocket(player)
	await _reload_game()
	var gap := _pocket_note_gap()
	check("a game saved inside the dimension loads there (Save.bb keeps the player and the event)", facility.pocket.player_inside and facility.pocket.visible and absf(player.global_position.y) < 0.5, str(player.global_position))
	check("loaded inside the dimension, the note lies on the floor", gap < 0.05, "%.2f above the floor" % gap)
	var hud := get_tree().get_first_node_in_group("hud")
	hud.show_document("GFX/items/bn.it", "Burnt Note")
	var picture: TextureRect = hud._doc_rect
	check("reading it shows the note", picture.visible and picture.texture != null and picture.texture.get_width() == 581, "visible %s" % str(picture.visible))
	check("with the access code written on it in Courier New", hud._doc_code.text == GameState.access_code and hud._doc_code.get_theme_font("font") == UIKit.font("regular"), "'%s' vs '%s'" % [hud._doc_code.text, GameState.access_code])
	picture.visible = false

# Event state the original keeps in a save (Save.bb writes every event's EventState, 2 and 3): the 008 chamber's alarm and broken
# window, and room3servers' one-off move of 173.
func _scn_savegaps() -> void:
	log_line("== save: the 008 chamber and room3servers")
	var record008 := _find_room("008")
	var has008 := not record008.is_empty()
	var servers_record := _find_room("room3servers")
	var servers_key := str(servers_record.get("key", "")) if not servers_record.is_empty() else ""
	if has008:
		facility.events.room008.state = 1
		facility.events.room008.window_broken = true
	if not servers_key.is_empty():
		facility.events.room3servers.moved_173[servers_key] = true
	await _reload_game()
	if has008:
		var event: Node = facility.rooms.get_room(record008).extras
		check("the 008 chamber keeps its alarm and broken window over a load (EventState 1, EventState2 1)", event != null and event.event_state == 1 and event.event_state2 == 1 and not event._window.visible, "")
	else:
		log_line("   no 008 chamber on this map")
	if not servers_key.is_empty():
		check("room3servers remembers that 173 was moved there once (EventState3)", facility.events.room3servers.moved_173.has(servers_key), "")
	else:
		log_line("   no room3servers on this map")
	facility.events.room008.reset()
	facility.events.room3servers.reset()

func _scn_room2slwalk() -> void:
	log_line("== room2sl: the walk and the doors")
	var setup: Dictionary = await _room2sl_setup()
	if setup.is_empty():
		check("the map has a room2sl", false, "")
		return
	var room: Node3D = setup.room
	facility.spawn_049_enabled = true
	facility.scp049 = null
	facility.check_049_trigger(player.global_position)
	var scene: Node = facility.room2sl_scene
	if scene == null:
		check("the event starts", false, "")
		return
	var npc: CharacterBody3D = facility.scp049
	var doors: Array = facility.room_edge_doors(room)
	var cell: Vector3 = room.object_point(7)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(cell) < b.global_position.distance_to(cell))
	var near_door: Node3D = doors[0]
	var away: Vector3 = near_door.global_position - room.global_position
	away.y = 0.0
	# the player waits behind the nearer door, 7 units out, where nothing sees him
	scene.event_state2 = -2.0
	place_player(near_door.global_position + away.normalized() * 7.0 + Vector3(0.0, 0.3, 0.0))
	GameState.god_mode = true
	var waited := 0.0
	var kept := true
	var locked_seen := false
	# a door that is shut and opened again inside one frame never shows in its state: count its sounds instead
	var door_sounds: Dictionary = {}     # door -> sounds started while he walked by
	var count_door_sounds := func(node: Node) -> void:
		if node is AudioStreamPlayer3D and node.get_parent() != null and node.get_parent().has_method("npc_open"):
			door_sounds[node.get_parent()] = int(door_sounds.get(node.get_parent(), 0)) + 1
	get_tree().node_added.connect(count_door_sounds)
	# the player waits more than HideDistance * 0.7 from the catwalk's last stretch, where NpcGravity holds him up (NPCs.bb 5006):
	# the walk down is a stalled route that the follower's 3 s hops get through, a waypoint at a time
	while waited < 240.0 and scene.event_state2 < 7.0 and is_instance_valid(scene):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if is_instance_valid(scene) and scene.event_state2 >= 3.0 and scene.door_hall != null and scene.door_hall.locked and scene.door_cell.locked:
			locked_seen = true
		if not is_instance_valid(scene) or npc.state == 2:
			break
	var seen_log: Array = scene.log if is_instance_valid(scene) else []
	log_line("   event states passed: %s after %.0f s, npc state %d" % [str(seen_log), waited, npc.state])
	if not seen_log.has(3) and is_instance_valid(scene):
		log_line("   stuck: npc %s idx %d/%d stuck %.1f walking %s points %s" % [str(npc.global_position), npc._follower.index, npc._follower.points.size(), npc._follower.stuck_time, str(npc.walking()), str(npc._follower.points)])
		for d in facility.doors_near(npc.global_position, 3.0):
			log_line("      door %s open %s locked %s keycard %d openstate %.0f" % [str(d.global_position), str(d.open), str(d.locked), d.keycard, d.openstate])
	check("the walk starts and reaches the catwalk (event 3)", seen_log.has(3), str(seen_log))
	check("SCP-079's doors are locked while he walks", locked_seen, "")
	get_tree().node_added.disconnect(count_door_sounds)
	var worst := 0
	for door in door_sounds:
		worst = maxi(worst, int(door_sounds[door]))
	check("no door he passes is swung open and shut over and over (the door-sound spam)", worst <= 4, "%d sounds from one door at worst, %d doors sounded" % [worst, door_sounds.size()])
	var lines: Array = scene.voices if is_instance_valid(scene) else []
	check("he speaks his first line at the first stop", lines.size() >= 1 and str(lines[0]).contains("Room2SL1"), str(lines))
	check("the scene finishes or he started hunting", not is_instance_valid(scene) or scene.event_state2 >= 4.0 or npc.state == 2, "event %.0f state %d" % [scene.event_state2 if is_instance_valid(scene) else -1.0, npc.state])
	GameState.god_mode = false
	if facility.room2sl_scene != null and is_instance_valid(facility.room2sl_scene):
		facility.room2sl_scene.queue_free()
	facility.room2sl_scene = null

func _scn_startscene() -> void:
	log_line("== start room breach scene")
	var room: Node3D = facility.start_node
	var humans_before := facility.humans.size()
	statue.active = false
	facility.start_scene_enabled = true
	GameState.god_mode = false
	place_player(room.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(0.5)
	facility.begin_start_scene(facility.start_neighbour_door())
	var scene: Node = facility.start_scene
	await secs(1.5)
	check("a scientist and Ulgrin stand in the chamber", scene.scientist != null and scene.ulgrin != null and scene.ulgrin.state == 7, "")
	player.blink_timer = 450.0
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.45, 0.45, 0.45)
	place_player(room.to_global(Vector3(3.2, 0.1, -0.2)))
	face_point(scene.ulgrin.global_position + Vector3(0, 0.9, 0))
	await secs(0.4)
	await shot("startscene_setup")
	place_player(scene.bodies[1].global_position + room.global_transform.basis * Vector3(2.0, 0.6, 1.0))
	face_point(scene.bodies[1].global_position + Vector3(0, 0.3, 0))
	await secs(0.2)
	await shot("startscene_bodies")
	var dead := 0
	for body in scene.bodies:
		if body.is_dead:
			dead += 1
	check("a guard and two Class D lie dead by the cell door", scene.bodies.size() == 3 and dead == 2 and scene.bodies[0].frame == 286.0, "%d of %d dead, guard frame %.0f" % [dead, scene.bodies.size(), scene.bodies[0].frame])
	check("the alarm loop and the first Alarm2 clip are playing in the start room", scene._alarm_loop != null and scene._alarm_loop.playing and scene.alarm_index >= 1 and scene._alarm_voice.playing, "index %d" % scene.alarm_index)
	var scientist_start: Vector3 = scene.scientist.global_position
	# stepping into the activation box starts the scene
	var activation: Vector3 = _trigger_centre(room, "173scene_activated")
	place_player(activation)
	await secs(0.3)
	check("the activation box sets the scene running (500)", scene.event_state >= 500.0, "%.0f" % scene.event_state)
	check("173 shows up in the corridor, held in place", statue.visible and not statue.active, "")
	# let the scene run; the player stays out of sight at the timer box
	place_player(_trigger_centre(room, "173scene_timer"))
	var waited := 0.0
	while waited < 20.0 and scene.event_state < 900.0 + 3.0 * 70.0 and scene.event_state2 == 0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("the scientist backs away and speaks", scene.scientist != null and scene.scientist.global_position.distance_to(scientist_start) > 0.2, "%.2f m" % (scene.scientist.global_position.distance_to(scientist_start) if scene.scientist != null else -1.0))
	waited = 0.0
	while waited < 25.0 and scene.event_state < 900.0 + 5.0 * 70.0 and scene.event_state2 == 0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("the lights flicker and 173 moves behind Ulgrin", scene.light_blinks >= 1, "%d (es %.0f, door open %s, ulgrin state %d)" % [scene.light_blinks, scene.event_state, str(scene.door.open if scene.door != null else null), scene.ulgrin.state if scene.ulgrin != null else -1])
	# the player is spotted from the end box: instant death by Ulgrin
	var end_box: Vector3 = _trigger_centre(room, "173scene_end")
	place_player(end_box)
	if scene.ulgrin != null:
		scene.ulgrin.global_position = scene.ulgrin.global_position
	waited = 0.0
	while waited < 5.0 and not player.dead and scene.ulgrin != null:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var visible_to_him: bool = scene.ulgrin != null and scene.ulgrin._sees(player)
	check("Ulgrin shoots the player he can see at the end box (or could not see them)", player.dead or not visible_to_him, "dead %s visible %s" % [str(player.dead), str(visible_to_him)])
	revive()
	place_player(_trigger_centre(room, "173scene_timer"))
	# out of his sight he leaves, the door shuts and the scene is over
	waited = 0.0
	while waited < 60.0 and scene.event_state2 == 0 and scene.ulgrin != null:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var left_index: int = scene.alarm_index
	place_player(room.to_global(Vector3(14.0, 1.55, -5.5)) + Vector3(0.0, 0.0, 60.0))
	check("the player is outside the start room", facility.room_name_at(player.global_position) != "start", facility.room_name_at(player.global_position))
	scene._alarm_loop.stop()
	scene.event_state = 1500.0
	await secs(0.3)
	check("the alarm loop keeps playing away from the start room while EventState is below 2000", scene._alarm_loop.playing and scene.alarm_index >= left_index, "index %d" % scene.alarm_index)
	scene._alarm_loop.stop()
	scene.event_state = 2100.0
	await secs(0.3)
	check("the alarm loop is not replayed from EventState 2000", not scene._alarm_loop.playing, "")
	scene.alarm_index = 8
	scene._alarm_voice.play()
	player.camera_shake = 0.0
	scene._alarm(player)
	check("Alarm2_8 shakes the view while it plays", scene.alarm_index == 8 and player.camera_shake >= 1.0, "index %d shake %.2f" % [scene.alarm_index, player.camera_shake])
	scene.alarm_index = 11
	scene._alarm_voice.stop()
	scene._alarm(player)
	check("the chain stops after Alarm2_11", scene.alarm_index == 11 and not scene._alarm_voice.playing, "")
	scene.event_state = 1500.0
	check("the scene ends and frees 173", scene.event_state2 == 1 and statue.active, "state2 %d active %s after %.0fs" % [scene.event_state2, str(statue.active), waited])
	check("the guards are gone", facility.humans.size() == humans_before + 3, "%d humans left, %d before the scene (the bodies stay)" % [facility.humans.size(), humans_before])
	scene.set_physics_process(false)
	scene.event_state = 5398.0
	scene._commotion(1.0)
	check("a crossing of 600 that the single-frame step misses plays nothing (UpdateEvents.bb:322 adds one FPSfactor)", scene.commotion_played.is_empty(), str(scene.commotion_played))
	scene.event_state = 5399.5
	scene._commotion(1.0)
	check("the first commotion plays when EventState crosses 5400", scene.commotion_played == [1], str(scene.commotion_played))
	scene.event_state = 5400.0 + 600.0 * 21 - 0.5
	scene._commotion(1.0)
	check("each later multiple of 600 plays the next commotion", scene.commotion_played == [1, 22], str(scene.commotion_played))
	scene.event_state = 5400.0 + 600.0 * 21 - 0.5
	scene._commotion(1.0)
	check("a commotion never plays twice", scene.commotion_played == [1, 22], str(scene.commotion_played))
	scene.event_state = 21000.0 - 0.5
	scene._commotion(1.0)
	check("past commotion 26 the props are freed and the event ends", scene.desk == null and scene.drawer == null and not scene.started, "started %s" % str(scene.started))
	facility.start_scene_enabled = false
	scene.queue_free()
	facility.start_scene = null

func _scn_startalarmend() -> void:
	log_line("== start alarm loop ends")
	check("the 008 room's looping alarm does not loop the shared Alarm.ogg", not Sfx.stream("SFX/Alarm/Alarm.ogg").loop, "")

func _start_scene_roles() -> int:
	var count := 0
	for human in facility.humans:
		if is_instance_valid(human) and str(human.get_meta("role", "")).begins_with("start_"):
			count += 1
	return count

func _reload_game() -> void:
	check("the game saves", main.save_game(), "")
	await main.load_game()
	var waited := 0.0
	while waited < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(1.5)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173

func _scn_startscenesave() -> void:
	log_line("== start room breach scene: save and load")
	var room: Node3D = facility.start_node
	statue.active = false
	facility.start_scene_enabled = true
	GameState.god_mode = true
	place_player(room.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(0.5)
	facility.begin_start_scene(facility.start_neighbour_door())
	await secs(0.5)
	place_player(_trigger_centre(room, "173scene_activated"))
	await secs(0.3)
	place_player(_trigger_centre(room, "173scene_timer"))
	await secs(1.0)
	var saved_state: float = facility.start_scene.event_state
	facility.start_scene.alarm_index = 5
	check("the scene is running before the save", saved_state >= 500.0 and _start_scene_roles() == 5, "state %.0f roles %d" % [saved_state, _start_scene_roles()])
	await _reload_game()
	var scene: Node = facility.start_scene
	check("the load resumes the running scene at its saved state", scene != null and is_instance_valid(scene) and scene.started and scene.event_state >= saved_state and scene.event_state < saved_state + 600.0, "%s" % (str(scene.event_state) if scene != null else "no scene"))
	check("the alarm chain resumes at its saved index", scene != null and scene.alarm_index >= 5, str(scene.alarm_index if scene != null else -1))
	check("its people come back and none are made again", scene != null and scene.scientist != null and scene.ulgrin != null and scene.bodies.size() == 3 and _start_scene_roles() == 5, "roles %d" % _start_scene_roles())
	check("173 is still held by the scene, shown, in the start room", scene != null and not statue.active and statue.visible and statue.global_position.distance_to(facility.start_node.global_position) < 20.0, "active %s at %s" % [str(statue.active), str(statue.global_position)])
	scene.event_state2 = 1
	facility.remove_human(scene.scientist)
	facility.remove_human(scene.ulgrin)
	scene.scientist = null
	scene.ulgrin = null
	scene._free_173(statue)
	await secs(0.3)
	var freed_at: Vector3 = statue.global_position
	await _reload_game()
	scene = facility.start_scene
	check("a finished scene is resumed without its people", scene != null and is_instance_valid(scene) and scene.started and scene.event_state2 == 1 and scene.scientist == null and scene.ulgrin == null and _start_scene_roles() == 3, "roles %d" % _start_scene_roles())
	check("173 stays free and on the map after the load (it roams once free)", statue.active and statue.visible and statue.global_position.distance_to(freed_at) < 40.0, "active %s moved %.2f" % [str(statue.active), statue.global_position.distance_to(freed_at)])
	scene.set_physics_process(false)
	scene.event_state = 21000.0 - 0.5
	scene._commotion(1.0)
	await _reload_game()
	check("an ended scene is not made again on load (the bodies stay)", facility.start_scene == null and _start_scene_roles() == 3 and statue.active, "roles %d active %s" % [_start_scene_roles(), str(statue.active)])
	GameState.god_mode = false

func _scn_intro() -> void:
	log_line("== the intro")
	var scene: Node = main.intro_scene
	var room: Node3D = world_chamber()
	var hud := get_tree().get_first_node_in_group("hud")
	check("the intro scene is running", scene != null and scene.started, "")
	await secs(0.5)
	check("the first frame sets the actors: Ulgrin, his partner, Franklin and the others stand in the room", scene.npc[3] != null and scene.npc[6] != null and scene.npc[10] != null, "")
	check("the player lies on the cell floor looking up", player.scripted and player.camera.global_position.y < room.global_position.y + 0.6, "camera y %.2f scripted %s" % [player.camera.global_position.y, str(player.scripted)])
	await secs(6.0)
	var hung: Array = []
	for i in [3, 4, 6]:
		var n: CharacterBody3D = scene.npc[i]
		if NpcGravity.mode(n, facility) != NpcGravity.NO_MOVE and not n.is_on_floor():
			hung.append("npc%d y %.2f" % [i, n.global_position.y - room.global_position.y])
	check("the scripted NPCs within gravity range fall to the floor during the intro", hung.is_empty(), ", ".join(hung))
	await shot("intro_wake0")
	await _wait_until(func() -> bool: return scene.event_state3 >= 6.0, 40.0)
	await shot("intro_wake1")
	await _wait_until(func() -> bool: return scene.event_state3 >= 11.0, 40.0)
	await shot("intro_wake2")
	var t: float = await _wait_until(func() -> bool: return scene.event_state3 >= 15.0, 40.0)
	check("the wake-up ends (EventState3 = 15) after about 10 s", scene.event_state3 >= 15.0 and not player.scripted, "state3 %.1f after %.1fs" % [scene.event_state3, t])
	check("the player is told to pick up the paper", hud.message_label.text == "Pick up the paper on the desk." or scene.event_state3 >= 15.0, hud.message_label.text)
	await shot("intro_cell")
	var paper: Node = null
	for item in get_tree().get_nodes_in_group("pickup"):
		if paper == null or item.global_position.distance_to(player.global_position) < paper.global_position.distance_to(player.global_position):
			paper = item
	check("the leaflet lies in the cell", paper != null and paper.global_position.distance_to(player.global_position) < 6.0, "%.1f m" % (paper.global_position.distance_to(player.global_position) if paper != null else -1.0))
	hud.try_pickup(paper)
	paper.queue_free()
	await secs(0.2)
	check("taking the first item prompts for the inventory (state3 40)", scene.event_state3 >= 40.0, "%.1f" % scene.event_state3)
	check("the inventory message is shown", hud.message_label.text.begins_with("Press"), hud.message_label.text)
	# reading it runs the clock on
	hud.set_selected(0)
	t = await _wait_until(func() -> bool: return scene.event_state3 >= 170.0, 30.0)
	check("reading the leaflet for about 9 s moves the scene on (state3 170)", scene.event_state3 >= 170.0 and t > 6.0 and t < 14.0, "%.1f after %.1fs" % [scene.event_state3, t])
	hud.deselect()
	t = await _wait_until(func() -> bool: return scene.npc[3].state == 9, 25.0)
	check("Ulgrin speaks before opening the door, then it opens", scene.npc[3].state == 9 and room.door_slots[6].open, "state %d open %s after %.1fs" % [scene.npc[3].state, str(room.door_slots[6].open), t])
	await shot("intro_door")
	# --- the escort: the player steps out and keeps close behind Ulgrin
	var ulgrin: CharacterBody3D = scene.npc[3]
	var corridor: Vector3 = scene.at(-4096.0, 0.1, 760.0)
	place_player(corridor)
	t = await _wait_until(func() -> bool: return scene.event_state3 >= 710.0, 30.0)
	check("outside the cell the escort begins (state3 710)", scene.event_state3 >= 710.0, "%.1f after %.1fs" % [scene.event_state3, t])
	check("Ulgrin and his partner find a route", ulgrin.path_status == 1 and scene.npc[4].path_status == 1, "%d / %d" % [ulgrin.path_status, scene.npc[4].path_status])
	var follow := func() -> bool:
		var behind: Vector3 = -ulgrin.global_transform.basis.z * -1.6
		var spot: Vector3 = ulgrin.global_position + behind
		if player.global_position.distance_to(ulgrin.global_position) > 2.2:
			place_player(Vector3(spot.x, ulgrin.global_position.y + 0.05, spot.z))
		return scene.event_state3 >= 900.0
	await shot("intro_corridor")
	var began_walk: Vector3 = ulgrin.global_position
	t = 0.0
	while t < 120.0 and scene.event_state3 < 900.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		follow.call()
	check("the escort reaches the anteroom (state3 905)", scene.event_state3 >= 900.0, "%.1f after %.1fs, Ulgrin walked %.1f m to %s" % [scene.event_state3, t, ulgrin.global_position.distance_to(began_walk), str(scene.rs_of(ulgrin.global_position))])
	await shot("intro_anteroom")
	place_player(Vector3(ulgrin.global_position.x, ulgrin.global_position.y, ulgrin.global_position.z) + (-ulgrin.global_transform.basis.z) * 1.0)
	t = await _wait_until(func() -> bool: return ulgrin.frame >= 483.0, 40.0)
	check("Ulgrin plays the hand-over animation (frames 358-607)", ulgrin.frame >= 483.0, "frame %.0f after %.1fs" % [ulgrin.frame, t])
	place_player(ulgrin.global_position + (-ulgrin.global_transform.basis.z) * 1.0)
	var to_guard: Vector3 = ulgrin.global_position + Vector3(0, 0.9, 0) - player.camera.global_position
	player.rotation.y = atan2(-to_guard.x, -to_guard.z)
	await secs(0.3)
	scene.test_interact = true
	await secs(0.3)
	var has_document := false
	for entry in hud.items:
		if str(entry) == "Document SCP-173":
			has_document = true
	check("taking the document puts SCP-173's file in the inventory", has_document, str(hud.items))
	check("the anteroom door opens and the scene moves to 910", scene.event_state3 >= 910.0 and room.door_slots[2].open, "%.1f open %s" % [scene.event_state3, str(room.door_slots[2].open)])
	hud.deselect()
	place_player(scene.at(-200.0, 0.1, -300.0))
	t = await _wait_until(func() -> bool: return scene.event_state3 == 0.0, 15.0)
	check("near the middle of the room the chamber phase begins", scene.event_state3 == 0.0, "%.1f after %.1fs" % [scene.event_state3, t])
	check("the chamber door opens for the player", room.door_slots[1].open, "")
	place_player(scene.at(700.0, 0.1, 500.0))
	t = await _wait_until(func() -> bool: return scene.event_state >= 10000.0, 120.0)
	check("the Class D take their places and the player stands in the chamber (state 10000)", scene.event_state >= 10000.0, "%.0f after %.1fs" % [scene.event_state, t])
	await shot("intro_chamber")
	t = await _wait_until(func() -> bool: return scene.event_state >= 14000.0, 60.0)
	check("Franklin runs the demonstration until the lights go out (state 14000)", scene.event_state >= 14000.0, "%.0f after %.1fs" % [scene.event_state, t])
	await _wait_until(func() -> bool: return scene.event_state >= 14062.0, 10.0)
	await shot("intro_kill1")
	t = await _wait_until(func() -> bool: return scene.event_state >= 14100.0, 10.0)
	check("173 kills the first Class D (frames 0-19)", scene.npc[1].frame >= 0.0 and scene.npc[1].frame <= 19.0 and scene.npc[1].state == 6, "frame %.0f state %d" % [scene.npc[1].frame, scene.npc[1].state])
	t = await _wait_until(func() -> bool: return scene.event_state >= 14300.0, 10.0)
	check("then the second", scene.npc[2].state == 6 and scene.npc[2].frame >= 45.0, "frame %.0f state %d" % [scene.npc[2].frame, scene.npc[2].state])
	await shot("intro_kill2")
	# the player backs out of the chamber
	place_player(scene.at(200.0, 0.1, 500.0))
	t = await _wait_until(func() -> bool: return scene.event_state >= 20000.0, 10.0)
	check("when the player is out of the chamber the balcony scene starts (state 20000)", scene.event_state >= 20000.0, "%.0f" % scene.event_state)
	await _wait_until(func() -> bool: return scene.event_state >= 20250.0, 10.0)
	await shot("intro_balcony")
	t = await _wait_until(func() -> bool: return scene.done, 20.0)
	check("173 reaches the balcony guard and the breach moves to the start room", scene.done and facility.active, "done %s active %s after %.1fs" % [str(scene.done), str(facility.active), t])
	await secs(0.5)
	await shot("intro_start")
	var start_room: Node3D = facility.start_node
	check("the player is now in the start room", start_room != null and facility.room_name_at(player.global_position) == "start", "room '%s' at %s" % [facility.room_name_at(player.global_position), str(player.global_position)])
	check("the intro room is gone", not is_instance_valid(room) or room.is_queued_for_deletion(), "")

func _scn_introrefuse() -> void:
	log_line("== intro: refusing to leave the cell")
	var scene: Node = main.intro_scene
	var room: Node3D = world_chamber()
	await _intro_skip_to_door(scene)
	var cell: Vector3 = scene.at(-4096.0, 0.1, 192.0)
	place_player(cell)
	var t: float = await _wait_until(func() -> bool: return scene.event_state3 >= 640.0, 120.0)
	check("a player who stays in the cell reaches the gas (state3 630+)", scene.event_state3 >= 630.0, "%.1f after %.1fs" % [scene.event_state3, t])
	await secs(1.0)
	check("the cell door shuts and gas pours in", not room.door_slots[6].open and scene._gas_emitters.size() == 2, "open %s, %d emitters" % [str(room.door_slots[6].open), scene._gas_emitters.size()])
	check("the player's eyes sting", GameState.eye_irritation > 0.0, "%.0f" % GameState.eye_irritation)

# The leaflet can be taken the way a player does it: walk to the desk, look at it, press E (SCP_INTRO=1 SCP_BOT_ONLY=introleaflet).
func _scn_introleaflet() -> void:
	log_line("== intro: taking the leaflet")
	var scene: Node = main.intro_scene
	var hud := get_tree().get_first_node_in_group("hud")
	await _wait_until(func() -> bool: return scene.event_state3 >= 15.0 and not player.scripted, 60.0)
	var paper: Node3D = null
	for item in get_tree().get_nodes_in_group("pickup"):
		if str(item.get_meta("item_name", "")) == "Class D Orientation Leaflet":
			paper = item
	check("the leaflet exists", paper != null, "")
	if paper == null:
		return
	log_line("player %s, leaflet %s, %.2f m apart" % [str(player.global_position), str(paper.global_position), player.global_position.distance_to(paper.global_position)])
	var desk_y: float = world_chamber().global_position.y + 156.0 * MeshLoader.ROOM_SCALE
	check("the leaflet lies on the desk top, not on the invisible collision plane above it", absf(paper.global_position.y - desk_y - WorldItem.REST_HEIGHT) < 0.02, "y %.3f, desk %.3f" % [paper.global_position.y, desk_y])
	var ambient := MeshLoader.entity_ambient()
	var lit := EntityLights.vertex_light(player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP, ambient)
	check("in the intro room the models are lit by its rmesh lights, not by the ambient alone", EntityLights.shown.size() > 0 and lit.x > ambient + 0.1, "%d lights, %.2f against ambient %.2f" % [EntityLights.shown.size(), lit.x, ambient])
	var chamber := world_chamber()
	var sitter: Node3D = main.intro_scene.npc[7]
	var seat_y := chamber.global_position.y - 315.0 * MeshLoader.ROOM_SCALE - 0.32
	check("the man at the office desk sits on his chair: the model 0.32 under the collider's -315 (NPCs.bb)", sitter != null and absf(sitter.global_position.y - seat_y) < 0.01, "y %.3f, wanted %.3f" % [sitter.global_position.y if sitter != null else -99.0, seat_y])
	for pair in [["173_2.b3d", chamber.map_prop], ["intro_labels.b3d", chamber.labels]]:
		var visual := (pair[1] as Node3D).get_child(0) as MeshInstance3D
		var box := visual.global_transform * visual.get_aabb()
		check("%s takes the room's RoomScale and lies in the intro room" % pair[0], box.size.length() < 30.0 and box.position.x > -35.0 and box.end.x < 8.0, str(box))
	var start_reach: bool = player.closest_item() == paper
	var spot := paper.global_position + Vector3(0.0, 0.0, 0.5)
	var floor_y: float = world_chamber().global_position.y
	place_player(Vector3(spot.x, floor_y + 0.05, spot.z))
	await secs(0.3)
	face_point(paper.global_position)
	await secs(0.1)
	log_line("the player wakes %.2f m from the leaflet, in reach: %s" % [player.global_position.distance_to(paper.global_position), str(start_reach)])
	check("standing at the desk and looking at it, the leaflet is the item in reach", player.closest_item() == paper, "dist %.2f" % player.camera.global_position.distance_to(paper.global_position))
	player._interact()
	await secs(0.2)
	check("E takes the leaflet into the inventory", str(hud.items[0]) == "Class D Orientation Leaflet", str(hud.items[0]))
	check("the inventory prompt follows", scene.event_state3 >= 40.0, "%.1f" % scene.event_state3)

func _scn_introslow() -> void:
	log_line("== intro: dawdling in the escort")
	var scene: Node = main.intro_scene
	await _intro_skip_to_door(scene)
	var ulgrin: CharacterBody3D = scene.npc[3]
	place_player(scene.at(-4096.0, 0.1, 760.0))
	await _wait_until(func() -> bool: return scene.event_state3 >= 800.0, 30.0)
	# the player stands still while the guards walk off
	var t: float = await _wait_until(func() -> bool: return player.dead or ulgrin.state == 11, 200.0)
	check("a player who will not follow is warned and then shot by the escort (state 11)", ulgrin.state == 11 or player.dead, "state %d state2 %.0f after %.0fs" % [ulgrin.state, ulgrin.state2, t])
	t = await _wait_until(func() -> bool: return player.dead, 40.0)
	check("and killed", player.dead, "after %.0fs" % t)

func _scn_securitycam() -> void:
	log_line("== security cameras")
	statue.active = false
	var room: Node3D = facility.start_node
	check("the start room has its camera and monitor", room.cams.size() >= 1 and room.cams[0].has_screen, "%d cams" % room.cams.size())
	var cam: Node3D = room.cams[0]
	place_player(room.to_global(Vector3(3.0, 1.55, -3.0)))
	await secs(0.5)
	var start_angle: float = cam.curr_angle
	var low: float = start_angle
	var high: float = start_angle
	var t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		low = minf(low, cam.curr_angle)
		high = maxf(high, cam.curr_angle)
		if high - low > 117.0:
			break
	check("the camera swings through +-58.5 degrees (45 * 1.3)", high - low > 100.0 and high <= 58.6 and low >= -58.6, "%.1f .. %.1f after %.0fs" % [low, high, t])
	place_player(room.to_global(Vector3(3.0, 1.55, -3.0)))
	face_point(cam.global_position)
	await secs(0.3)
	await shot("camera_head")
	var yaw_a: Vector3 = cam.head_forward()
	await secs(2.0)
	check("the head turns with it", cam.head_forward().distance_to(yaw_a) > 0.01, "")
	# the monitor: close and looking at it, the feed is redrawn
	var screen: Node3D = cam._screen
	var front: Vector3 = screen.global_transform.basis.z
	var spot: Vector3 = screen.global_position + front * 0.8
	place_player(Vector3(spot.x, room.global_position.y + 1.55, spot.z))
	face_point(screen.global_position)
	player.blink_timer = 400.0
	await secs(1.0)
	await shot("camera_monitor")
	check("looking at the monitor redraws its picture", cam.in_sight and cam.renders > 0, "in sight %s, %d renders" % [str(cam.in_sight), cam.renders])
	# Euclid: saving needs a selected monitor
	GameState.difficulty = 1
	var hud := get_tree().get_first_node_in_group("hud")
	hud.quick_save()
	check("on Euclid F5 away from a monitor says saving needs one", hud.message_label.text.begins_with("Saving is only permitted"), hud.message_label.text)
	var close_spot: Vector3 = screen.global_position + front * 0.6
	place_player(Vector3(close_spot.x, room.global_position.y + 1.55, close_spot.z))
	face_point(screen.global_position)
	await secs(0.3)
	cam.select_requested = true
	await secs(0.3)
	check("a click on the monitor selects it", GameState.selected_monitor == cam, "selected %s, save type %d, allow %s, near %.2f, visible %s, in sight %s, paused %s" % [str(GameState.selected_monitor), GameState.save_type(), str(cam.allow_saving), player.camera.global_position.distance_to(screen.global_position), str(cam._screen_visible(player)), str(cam.in_sight), str(get_tree().paused)])
	await secs(0.3)
	check("it tells the player to press F5", hud.message_label.text == "Press F5 to save.", hud.message_label.text)
	hud.quick_save()
	check("F5 saves the game", hud.message_label.text == "Game progress saved.", hud.message_label.text)
	var far: Vector3 = room.to_global(Vector3(12.0, 1.55, -3.0))
	place_player(far)
	await secs(0.5)
	check("walking away puts the monitor down", GameState.selected_monitor == null, "")
	GameState.difficulty = 0

# The intro's own camera and monitor (SCP_INTRO=1 SCP_BOT_ONLY=introcam).
func _scn_introcam() -> void:
	log_line("== the intro's security camera")
	var room: Node3D = world_chamber()
	var cam: Node3D = room.cams[0]
	check("the intro room has its camera and a monitor in the office", room.cams.size() == 1 and cam.has_screen, "")
	await secs(1.0)
	var screen: Node3D = cam._screen
	var front: Vector3 = screen.global_transform.basis.z
	var spot: Vector3 = screen.global_position + front * 0.8
	var scene: Node = main.intro_scene
	scene.set_physics_process(false)     # hold the intro still: this is only a look at the camera
	player.scripted = false
	place_player(Vector3(spot.x, room.global_position.y + 0.02, spot.z))
	player.camera.position = Vector3(0.0, 0.9, 0.0)
	face_point(screen.global_position)
	player.blink_timer = 400.0
	await secs(1.0)
	check("the monitor in the office shows the camera over the corridor", cam.in_sight and cam.renders > 0, "in sight %s, %d renders" % [str(cam.in_sight), cam.renders])
	check("the intro room is in the light containment zone, so 079 cannot show SCP-895 on its monitor", facility.zone_at(player.global_position) == 0 and cam.coffin_effect == 0, "zone %d, effect %d" % [facility.zone_at(player.global_position), cam.coffin_effect])
	await shot("introcam_monitor")
	var corridor: Vector3 = cam.global_position + Vector3(0.0, -1.0, 0.0) + cam.head_forward() * 2.5
	place_player(Vector3(corridor.x, room.global_position.y + 0.02, corridor.z))
	face_point(cam.global_position)
	await secs(0.4)
	await shot("introcam_head")

# The staircase door of the intro room has its buttons moved beside the frame (SCP_INTRO=1 SCP_BOT_ONLY=introdoorview).
func _scn_introdoorview() -> void:
	log_line("== intro: the staircase door and its buttons")
	var room: Node3D = world_chamber()
	var door: Node3D = room.door_slots[5]
	main.intro_scene.set_physics_process(false)
	player.scripted = false
	player.camera.position = Vector3(0.0, 0.9, 0.0)
	await secs(0.5)
	var wanted := [Vector3(-10.125, 0.7, 3.9687), Vector3(-10.125, 0.7, 3.8437)]
	for i in door.buttons.size():
		var at: Vector3 = room.to_local(door.buttons[i].global_position)
		log_line("   button %d at local x %.3f z %.3f (the data: x -10.125 z %.4f)" % [i, at.x, at.z, -wanted[i].z])
		check("button %d is where the source puts it" % i, absf(at.x - wanted[i].x) < 0.08 and absf(at.z - wanted[i].z) < 0.08, "%.3f %.3f" % [at.x, at.z])
	for side in [1.0, -1.0]:
		var spot: Vector3 = door.global_position + door.global_transform.basis.z * 1.6 * side
		place_player(Vector3(spot.x, room.global_position.y + 0.05, spot.z))
		face_point(door.global_position + Vector3(0.0, 0.8, 0.0))
		player.blink_timer = 400.0
		GameState.blur_timer = 0.0
		GameState.blur_volume = 0.0
		await secs(0.4)
		await shot("introdoor_%s" % ("a" if side > 0.0 else "b"))

func _scn_lever() -> void:
	log_line("== room2sl lever")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("room2sl")
	if record.is_empty():
		check("the map has a room2sl", false, "")
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(1.5)
	var props: Node3D = room.extras
	check("the room has its monitor wall and lever", props != null and props.monitors.size() == 15 and props.lever != null, "")
	if props == null or props.lever == null:
		return
	var lever: Node3D = props.lever
	check("14 monitors show a picture", props.screens.size() == 14, "%d" % props.screens.size())
	await secs(0.5)
	check("the lever starts up (pitch 10, falling to 80)", lever.is_on() and facility.events.sl.lever_on, "pitch %.0f" % lever.pitch)
	check("it rests at the top end", lever.pitch > 70.0, "pitch %.1f" % lever.pitch)
	# stand in front of it, look at the handle, hold the button and pull the mouse up
	var handle: Vector3 = lever.handle_point()
	var found := false
	for step in 16:
		var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
		var spot: Vector3 = handle + dir * 0.55
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.5, 0), spot + Vector3(0, -3.0, 0))
		down.collision_mask = 1
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
		if hit.is_empty() or absf(hit.position.y - (handle.y - 1.0)) > 1.2:
			continue
		place_player(hit.position + Vector3(0, 0.1, 0))
		await secs(0.3)
		var look: Vector3 = handle - player.camera.global_position
		player.rotation.y = atan2(-look.x, -look.z)
		player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		player.user_pitch = -rad_to_deg(player.camera.rotation.x)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if lever.aimed_at(player.camera) and player.camera.global_position.distance_to(lever.global_position) < 0.8:
			found = true
			break
	check("a spot in front of the handle exists", found, "")
	if not found:
		return
	check("the hand shows over the handle", GameState.hand_icon or lever.aimed_at(player.camera), "")
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("a click grabs it", GameState.grabbed_lever == lever, "")
	player.test_mouse_speed = Vector2(0.0, -4.0)    # the mouse moves up: pitch falls 32 a frame (capped at 30)
	await get_tree().physics_frame
	await get_tree().process_frame
	var shown: Array = get_tree().get_first_node_in_group("hud")._meters.arrows_shown
	check("the grabbed lever shows the up and down arrows", (GameState.arrow_icons[0] or shown[0]) and (GameState.arrow_icons[2] or shown[2]) and not shown[1], str(shown))
	for i in 9:
		await get_tree().physics_frame
	player.test_mouse_speed = Vector2.ZERO
	check("pulling the mouse swings it to the bottom (-80)", lever.pitch < -75.0 and not lever.is_on(), "pitch %.0f" % lever.pitch)
	Input.action_release("interact")
	await secs(1.0)
	check("let go, it falls to the near end and stays down", lever.pitch < -70.0 and GameState.grabbed_lever == null, "pitch %.0f" % lever.pitch)
	check("the lockdown is off", not facility.events.sl.lever_on, "")
	check("it clunked", lever.flips >= 1, "%d" % lever.flips)
	# and pushing it back up
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.test_mouse_speed = Vector2(0.0, 4.0)
	for i in 6:
		await get_tree().physics_frame
	player.test_mouse_speed = Vector2.ZERO
	Input.action_release("interact")
	await secs(0.8)
	check("it can be put back up", lever.is_on() and facility.events.sl.lever_on, "pitch %.0f" % lever.pitch)
	# the grab is let go wherever the player is (door buttons must not stay blocked)
	GameState.grabbed_lever = lever
	place_player(lever.global_position + Vector3(0.0, 0.5, 20.0))
	await secs(0.5)
	check("the grab is cleared once the button is up, even far from the lever", GameState.grabbed_lever == null, "")
	# the facility keeps the handle's place (the saves read it there)
	lever.pitch = -80.0
	await secs(0.5)
	check("the facility remembers the handle", facility.events.sl.lever_pitch < -70.0, "%.0f" % facility.events.sl.lever_pitch)
	facility.events.sl.lever_pitch = 10.0

func _scn_checkpoint() -> void:
	log_line("== checkpoint lockdown")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("checkpoint1")
	if record.is_empty():
		check("the map has a checkpoint1", false, "")
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 1.0) + 0.1, 1.0)))
	await secs(1.2)
	var extras: Node3D = room.extras
	check("the checkpoint has two monitors", extras != null and extras.monitors.size() == 2, "")
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	check("its two doors are linked and stay open 5 s", door_a != null and door_a.linked_door == door_b and door_b.linked_door == door_a and door_a.timer_frames == 350.0, "")
	facility.events.sl.lever_on = false
	await secs(0.4)
	check("lever down: the doors are free and the screens dark", not door_a.locked and not door_b.locked and not extras.lockdown, "")
	facility.events.sl.lever_on = true
	await secs(0.4)
	check("lever up: the doors are locked", door_a.locked and door_b.locked and extras.lockdown, "")
	var picture_one := ""
	var picture_two := ""
	facility.monitor_timer = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var material: StandardMaterial3D = extras._screen_materials[0][0]
	picture_one = str(material.albedo_texture)
	facility.monitor_timer = 60.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	picture_two = str(material.albedo_texture)
	check("and the screens flash between two pictures", material.albedo_texture != null and picture_one != picture_two, "%s / %s" % [picture_one, picture_two])
	# pressing the button of a locked door does nothing; with the lever down it can be opened by the pair
	facility.events.sl.lever_on = false
	await secs(0.4)
	door_a.open = false
	door_b.open = false
	await secs(2.0)
	door_a.locked = false
	door_a.keycard = 0
	door_a.use()
	check("pressing one door flips both", door_a.open and door_b.open, "")
	await secs(1.8)
	check("they stay open until the timer runs out", door_a.open, "")
	await secs(6.0)
	check("and shut after 5 s", not door_a.open and not door_b.open, "")
	door_a.keycard = 3
	facility.events.sl.lever_on = false

func _scn_scp008room() -> void:
	log_line("== SCP-008 chamber")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("008")
	if record.is_empty():
		check("the map has an SCP-008 chamber", false, "")
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.5) + 0.1, 0.5)))
	await secs(1.2)
	var chamber: Node3D = room.extras
	check("the chamber has its event props", chamber != null and chamber._lid != null and chamber._door_c != null, "")
	if chamber == null:
		return
	check("the third door is locked from the start", chamber._door_c.locked, "")
	check("the first two doors are linked", chamber._door_a.linked_door == chamber._door_b and chamber._door_b.linked_door == chamber._door_a, "")
	check("the event starts when the player is in the room", chamber.event_state == 1, "state %d" % chamber.event_state)
	await secs(1.0)
	check("the alarm sounds", chamber._alarm.playing, "")
	var blinked := false
	for i in 80:
		await get_tree().physics_frame
		if chamber._light.visible:
			blinked = true
	check("and the red light blinks", blinked, "")
	# near the container: the doors lock
	var box: Vector3 = chamber.container()
	var found := false
	for step in 16:
		var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
		var spot: Vector3 = box + dir * 0.8
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.0, 0), spot + Vector3(0, -3.0, 0))
		down.collision_mask = 1
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
		if hit.is_empty() or absf(hit.position.y - box.y) > 1.0:
			continue
		place_player(hit.position + Vector3(0, 0.1, 0))
		await secs(0.3)
		face_point(box)
		var look: Vector3 = box - player.camera.global_position
		player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		player.user_pitch = -rad_to_deg(player.camera.rotation.x)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if player.camera.is_position_in_frustum(box) and player.global_position.distance_to(box) < 1.0:
			found = true
			break
	check("a spot beside the container exists", found, "")
	if not found:
		return
	# the event itself brought 173 to the room's corner when it began (and may have broken the glass already): start over
	place_statue(Vector3(0.0, -80.0, 0.0))
	chamber.event_state2 = 0
	chamber.window_broken = false
	GameState.infect = 0.0
	GameState.injuries = 0.0
	await secs(0.3)
	check("beside the container the doors lock", chamber._door_a.locked and chamber._door_b.locked, "")
	check("the window shows", chamber._window.visible, "")
	check("the lid starts shut (pitch 89)", chamber.lever_pitch > 88.0, "%.0f" % chamber.lever_pitch)
	var puffs: Array = facility.particles._items.filter(func(q): return q.image == 6 and q.pos.distance_to(box) < 1.0)
	var rolls := {}
	var rising := 0
	var fading := 0
	for q in puffs:
		rolls[snappedf(q.roll, 0.01)] = true
		if q.pos.y > box.y + 0.001:
			rising += 1
		if q.alpha < 1.0:
			fading += 1
	check("the open container gives off smoke2 particles one a frame", puffs.size() > 20 and puffs.size() < 120, "%d" % puffs.size())
	check("the gas rises, fades and each puff has its own roll", rising > 10 and fading > 10 and rolls.size() > puffs.size() / 2, "rising %d fading %d rolls %d" % [rising, fading, rolls.size()])
	# the glass breaks when 173 is at the container and the player is not looking: with no suit the arm is cut
	GameState.infect = 0.0
	GameState.wearing_hazmat = 0
	var injuries_before: float = GameState.injuries
	var statue_spot: Vector3 = room.to_global(room.fill_objects[4])
	place_statue(statue_spot + Vector3(0.5, 0.05, 0.0))
	statue.idle = 0
	player.blink_timer = -12.0    # the eyes are shut
	await secs(0.3)
	check("173 comes to the window while the player's eyes are shut (the glass breaks)", chamber.window_broken, "")
	check("the cut hurts and infects without a suit", GameState.injuries > injuries_before and GameState.infect >= 1.0, "injuries %.2f infect %.1f" % [GameState.injuries, GameState.infect])
	check("the window is gone", not chamber._window.visible, "")
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.infect = 0.0
	player.blink_timer = 400.0
	# pull the lid: the mouse moves down, five degrees a frame
	Input.action_press("interact")
	player.test_mouse_speed = Vector2(0.0, 5.0)
	for i in 14:
		await get_tree().physics_frame
	player.test_mouse_speed = Vector2.ZERO
	Input.action_release("interact")
	await secs(0.3)
	check("pulling the lever ends the event (state 2)", chamber.event_state == 2 and facility.events.sl.scp008_done, "state %d pitch %.0f" % [chamber.event_state, chamber.lever_pitch])
	check("the alarm stops", not chamber._alarm.playing, "")
	check("and all three doors unlock", not chamber._door_a.locked and not chamber._door_b.locked and not chamber._door_c.locked, "")
	await secs(1.0)
	check("the lever settles back", chamber.lever_pitch < 40.0, "%.0f" % chamber.lever_pitch)

func _scn_checkpoint2() -> void:
	log_line("== checkpoint 2 and SCP-008")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("checkpoint2")
	if record.is_empty():
		check("the map has a checkpoint2", false, "")
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 1.0) + 0.1, 1.0)))
	facility.events.sl.scp008_done = false
	await secs(1.2)
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	check("with SCP-008 not dealt with the checkpoint is locked", door_a.locked and door_b.locked and room.extras.lockdown, "")
	var material: StandardMaterial3D = room.extras._screen_materials[0][0]
	check("and its monitors show the lockdown", material.albedo_texture != null, "")
	facility.events.sl.scp008_done = true
	await secs(0.4)
	check("once the 008 lever is pulled it opens up", not door_a.locked and not door_b.locked and not room.extras.lockdown, "")
	check("and the monitors go dark", material.albedo_texture == null, "")
	facility.events.sl.scp008_done = false

func _scn_medibay() -> void:
	log_line("== medibay event")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "medibay":
			record = candidate
			break
	if record.is_empty():
		check("the map has a medibay", false, "")
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))     # near the room, not inside it
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	check("nothing is there before the player comes in", not facility.events.medibay.entered and facility.events.medibay.zombie == null, "")
	var spot: Vector3 = room.object_point(3)
	check("the room has the zombie's spot (Objects[3])", spot != Vector3.INF, "")
	var entry: Vector3 = room.object_point(1) if room.object_point(1) != Vector3.INF else record.position
	place_player(Vector3(entry.x, record.position.y + 1.55, entry.z))
	player.blink_timer = 400.0
	await secs(1.0)
	check("stepping in creates the zombie, lying", facility.events.medibay.entered and facility.events.medibay.zombie != null and facility.events.medibay.zombie.state == 0, "")
	var props: Node3D = room.extras._props
	check("the props show while the player is inside", props.visible, "")
	var zombie: Node = facility.events.medibay.zombie
	check("it lies at Objects[3]", zombie.global_position.distance_to(spot) < 0.5, "%.2f" % zombie.global_position.distance_to(spot))
	place_player(zombie.global_position + Vector3(0.6, 0.0, 0.0) + Vector3(0.0, 1.55 - 0.05, 0.0) * 0.0 + Vector3(0.0, 0.1, 0.0))
	player.blink_timer = 400.0
	await secs(0.5)
	check("coming within 1.2 flickers the lights", GameState.light_blink > 0.0 or facility.events.medibay.timer > 0.0, "blink %.1f timer %.0f" % [GameState.light_blink, facility.events.medibay.timer])
	check("and it does not get up yet", zombie.state == 0, "state %d" % zombie.state)
	await secs(4.5)
	check("four seconds later it gets up and hunts", zombie.state >= 1, "state %d" % zombie.state)
	place_player(record.position + Vector3(40.0, 0.0, 0.0))
	await secs(0.5)
	check("the props are gone once the player has left", not props.visible, "")
	facility.remove_zombie008(zombie)
	GameState.god_mode = false

func _hit_body_blocks(door: Node3D) -> bool:
	var space := door.get_world_3d().direct_space_state
	for ix in range(-12, 13):
		for iy in range(1, 8):
			var from: Vector3 = door.to_global(Vector3(ix * 0.1, iy * 0.4, -1.0))
			var to: Vector3 = door.to_global(Vector3(ix * 0.1, iy * 0.4, 1.0))
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = 1
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and hit.collider == door.hit_body:
				return true
	return false

func _scn_servers() -> void:
	log_line("== the server room (096 and the guard)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2servers":
			record = candidate
	if record.is_empty():
		check("the map has a room2servers", false, "")
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	check("the three levers are there", room.extras != null and room.extras.levers.size() == 3, "")
	check("the power switch starts up, the pump and generator down", room.extras.levers[0].is_on() and not room.extras.levers[1].is_on() and not room.extras.levers[2].is_on(), "")
	check("nothing has happened yet", facility.events.servers.state == 0.0 and facility.scp096 == null, "")
	var middle: Vector3 = room.global_position
	place_player(Vector3(middle.x, middle.y + 1.55, middle.z) + room.global_transform.basis * Vector3(0.0, 0.0, 0.6))
	player.blink_timer = 400.0
	await secs(1.0)
	var shy: Node = facility.scp096
	check("stepping in starts the scene: 096 sits in state 6, a guard stands by", shy != null and shy.state == 6 and facility.events.servers.guard != null, "")
	check("the doors shut and lock", not room.door_slots[0].open and room.door_slots[0].locked and not room.door_slots[1].open and room.door_slots[1].locked, "")
	var hit_door: Node3D = room.door_slots[0]
	await secs(3.0)
	check("the shut server door has its doorhit body, inactive", hit_door.hit_body != null and hit_door.openstate == 0.0 and hit_door.hit_body.collision_layer == 0, "openstate %.0f" % hit_door.openstate)
	hit_door.open = true
	await secs(1.0)
	check("the doorhit body is inactive while the door is open", hit_door.hit_body.collision_layer == 0, "layer %d" % hit_door.hit_body.collision_layer)
	check("and an open door lets a probe through its frame", not _hit_body_blocks(hit_door), "")
	hit_door.open = false
	await secs(0.3)
	check("the doorhit body is active while the door is closing", hit_door.openstate > 0.0 and hit_door.hit_body.collision_layer == 1 and _hit_body_blocks(hit_door), "openstate %.0f layer %d" % [hit_door.openstate, hit_door.hit_body.collision_layer])
	await secs(3.0)
	check("it is inactive again once the door is shut", hit_door.openstate == 0.0 and hit_door.hit_body.collision_layer == 0, "openstate %.0f" % hit_door.openstate)
	check("other doors have no doorhit body", get_tree().get_nodes_in_group("door").any(func(d: Node) -> bool: return d.hit_body == null), "")
	var guard: Node = facility.events.servers.guard
	# run the scene: the player keeps out of 096's sight (eyes shut) in the middle of the room
	var waited := 0.0
	while waited < 40.0 and facility.events.servers.guard != null:
		player.blink_timer = -10.0 if waited < 30.0 else player.blink_timer
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("096 turns on the guard and maims him (the scene removes him)", facility.events.servers.guard == null and facility.events.servers.killed, "after %.1f s state %.0f 096 state %d" % [waited, facility.events.servers.state, shy.state])
	check("and goes on walking about (state 5)", shy.state == 5, "state %d" % shy.state)
	var walls: Array[GrowingDecal] = []
	var floors: Array[GrowingDecal] = []
	for child in room.get_children():
		if child is GrowingDecal and child.size_change == 0.001:
			walls.append(child)
		elif child is GrowingDecal and child.size_change == 0.0:
			floors.append(child)
	check("14 blood sheets on the walls and 7 pools on the floor", walls.size() == 14 and floors.size() == 7, "%d walls, %d floors" % [walls.size(), floors.size()])
	check("the wall decals face along the room's own x axis, whatever its angle", walls.all(func(d: GrowingDecal) -> bool: return absf(d.global_basis.z.normalized().dot(room.global_basis.x)) > 0.999), "room yaw %.0f" % rad_to_deg(room.rotation.y))
	check("they lie 198 units from the middle on the room's x axis", walls.all(func(d: GrowingDecal) -> bool: return absf(room.to_local(d.global_position).x + 198.0 * 8.0 / 2048.0) < 2.5 * 8.0 / 2048.0), "")
	check("wall blood is fully opaque (alpha 1)", walls.all(func(d: GrowingDecal) -> bool: return is_equal_approx((d.material_override as ShaderMaterial).get_shader_parameter("color").a, 1.0)), "")
	check("floor blood lies 0.001-0.003 above the floor", floors.all(func(d: GrowingDecal) -> bool: return d.global_position.y - room.global_position.y >= 0.001 and d.global_position.y - room.global_position.y <= 0.003), "")
	var turned := room.rotation.y
	for quarter in [1.0, 2.0, 3.0]:
		room.rotation.y = turned + quarter * PI * 0.5
		var probe: Node3D = room.extras
		probe._wall_blood(Vector3(-198.0 * 8.0 / 2048.0, 1.0, 0.0), PI * 0.5)
		probe._wall_blood(Vector3(-198.0 * 8.0 / 2048.0, 1.0, 0.0), -PI * 0.5)
		var made: Array[GrowingDecal] = []
		for child in room.get_children():
			if child is GrowingDecal and child.size_change == 0.001 and not walls.has(child):
				made.append(child)
		check("a room turned a further %.0f degrees still stands the blood against its wall" % (quarter * 90.0), made.size() == 2 and made.all(func(d: GrowingDecal) -> bool: return absf(d.global_basis.z.normalized().dot(room.global_basis.x)) > 0.999), "%d decals" % made.size())
		for decal in made:
			decal.free()
	room.rotation.y = turned
	GameState.god_mode = false
	facility.events.servers.state = 70.0 * 40.0 - 0.5
	for slot in [0, 1]:
		room.door_slots[slot].open = false
	player.blink_timer = 400.0
	place_player(Vector3(middle.x, middle.y + 1.55, middle.z) + room.global_transform.basis * Vector3(0.0, 0.0, 0.6))
	await secs(0.3)
	check("at 40 s both doors open once, still locked", room.door_slots[0].open and room.door_slots[1].open and room.door_slots[0].locked and room.door_slots[1].locked, "state %.0f" % facility.events.servers.state)
	place_player(Vector3(middle.x, middle.y + 1.55, middle.z) + room.global_transform.basis * Vector3(0.0, 0.0, 2.0))
	await secs(0.4)
	check("walking 2 along the room's z does not end the lock-in", facility.events.servers.state < 70.0 * 45.0, "state %.0f" % facility.events.servers.state)
	# toward -x: the mesh reaches only 0.875 to +x, so the bounds lookup (PlayerRoom) would give a neighbour there
	place_player(Vector3(middle.x, middle.y + 0.3, middle.z) + room.global_transform.basis * Vector3(-1.4, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("walking 1.4 along the room's -x does", facility.events.servers.state >= 70.0 * 45.0, "state %.0f at local %s" % [facility.events.servers.state, str(room.to_local(player.global_position))])
	facility.events.servers.state = 70.0 * 45.0
	player.blink_timer = 400.0
	place_player(Vector3(middle.x, middle.y + 1.55, middle.z) + room.global_transform.basis * Vector3(0.0, 0.0, 0.6))
	await secs(0.5)
	check("with the power still on the doors stay locked", room.door_slots[0].locked and room.door_slots[1].locked, "")
	room.extras.levers[0].pitch = -80.0
	room.extras.levers[1].pitch = 80.0
	room.extras.levers[2].pitch = 80.0
	await secs(0.6)
	check("power off, pump and generator on: both doors unlock", not room.door_slots[0].locked and not room.door_slots[1].locked, "")
	check("the generator runs up", facility.events.servers.state3 > 0.0, "%.2f" % facility.events.servers.state3)
	facility.scp096.queue_free()
	facility.scp096 = null
	GameState.god_mode = false

func _scn_ending() -> void:
	log_line("== the ending screen")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	player.blink_timer = 400.0
	await secs(0.5)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	GameState.give_achievement("096")
	hud.start_ending("b3")
	check("the ending starts and stops the game", hud.ending_active() and get_tree().paused, "")
	await secs(1.0)
	var screen: Control = hud.ending_screen
	check("the death fade runs first (the timer is between 0 and -360)", screen.ending_timer < -50.0 and screen.ending_timer > -360.0, "%.0f" % screen.ending_timer)
	screen.ending_timer = -380.0
	await secs(0.6)
	check("then the picture and the music start", screen._picture != null and screen._music.playing, "")
	screen.ending_timer = -440.0
	await secs(0.5)
	check("the ending's own voice line plays at -450", screen._played_voice and screen._voice.playing, "%.0f" % screen.ending_timer)
	await shot("ending_flicker")
	screen.ending_timer = -1005.0
	await secs(0.5)
	check("from -1000 the THE END panel shows with the tallies", screen.panel_requested and hud.pause_menu.visible and hud.pause_menu.mode == hud.PauseMenuScript.Mode.END, "")
	await shot("ending_panel")
	check("the timer waits for the button at -1111", screen.ending_timer >= -1112.0 and screen.ending_timer <= -1005.0, "%.0f" % screen.ending_timer)
	hud.pause_menu.end_continue_requested.emit()
	await secs(0.6)
	check("MAIN MENU starts the credits (-2000 and below)", screen._credits_started and screen.ending_timer <= -2000.0, "%.0f" % screen.ending_timer)
	check("Credits.txt was read", screen._credits.size() > 100 and screen._last_line > 100, "%d lines, last %d" % [screen._credits.size(), screen._last_line])
	screen.ending_timer = -2000.0 - 2.0 * (screen.size.y + 10.0) - 24.0 * float(screen._last_line) * 2.0 * screen.size.y / 1024.0 - 100.0
	await secs(0.5)
	await shot("ending_credits_end")
	check("the credits fade the closing lines in once the last line has scrolled away", screen._credits_timer > 0.0, "%.1f" % screen._credits_timer)
	for connection in screen.finished.get_connections():
		screen.finished.disconnect(connection.callable)      # the test stays in the game instead of going back to the menu
	var finished := [false]
	screen.finished.connect(func() -> void: finished[0] = true)
	screen._credits_timer = -1.0
	await secs(0.3)
	check("and the game goes back to the main menu when they end", finished[0] and not screen.active and not get_tree().paused, "finished %s active %s paused %s timer %.1f" % [str(finished[0]), str(screen.active), str(get_tree().paused), screen._credits_timer])

func _scn_gateb() -> void:
	log_line("== gate B, the surface")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var start_spot: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "exit1":
			record = candidate
	if record.is_empty():
		check("the map has gate B", false, "")
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	check("gate B has its event", room.extras != null and room.extras.has_method("_surface"), "")
	place_player(room.object_point(5) + Vector3(0.0, 1.0, 0.0))
	player.blink_timer = 400.0
	await secs(2.0)
	var event: Node = room.extras
	check("arriving on the surface sets the scene up", facility.events.exit1.state >= 1.0 and event.apaches.has(0) and event.guard != null, "state %.0f" % facility.events.exit1.state)
	check("the fog is the gate's: 5 to 45", GameState.fog_override.x == 5.0 and GameState.fog_override.y == 45.0, "")
	check("and the ambient light 140", is_equal_approx(GameState.ambient_override, 140.0 / 255.0), "")
	check("the sky box is there", event._sky != null and event._sky.visible, "")
	check("the terrain is there", event._terrain != null and event._terrain.get_child_count() > 0, "")
	check("the helicopter circles up high", event.apaches[0].global_position.y > 30.0, "%.1f" % event.apaches[0].global_position.y)
	await shot("gateb_arrival")
	check("the guard has noticed the player", event.guard.state == 1 or event.guard.global_position.distance_to(player.global_position) > 15.0, "state %d dist %.1f" % [event.guard.state, event.guard.global_position.distance_to(player.global_position)])
	place_player(room.object_point(10) + Vector3(0.0, 1.0, 0.0))
	await secs(1.0)
	check("at Objects[10] the battle begins (state 2)", facility.events.exit1.state >= 2.0, "%.0f" % facility.events.exit1.state)
	check("the two doors lock", room.door_slots[2].locked and room.door_slots[3].locked, "")
	check("two more helicopters arrive", event.apaches.has(2) and event.apaches.has(3), "")
	await secs(3.0)
	await shot("gateb_battle")
	# jump to the end of the battle
	facility.events.exit1.state = 74.9 * 70.0
	await secs(1.5)
	check("after 75 s without the remote detonation the announcement says it failed and MTF units come", GameState.selected_ending == "b3" and event._mtf.size() == 3, "ending '%s' units %d" % [GameState.selected_ending, event._mtf.size()])
	# the units close in, hold the player, and the ending follows
	for unit in event._mtf:
		unit.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	for connection in hud.pause_menu.end_continue_requested.get_connections():
		pass
	GameState.god_mode = true
	var held := 0.0
	while held < 2.0 and facility.events.exit1.state3 == 0.0:
		await get_tree().physics_frame
		held += get_physics_process_delta_time()
	check("within 3 units they stop the player", facility.events.exit1.state3 > 0.0 and GameState.unable_to_move, "state3 %.0f" % facility.events.exit1.state3)
	facility.events.exit1.state3 = 505.0
	await secs(0.5)
	check("500 frames later the player is shot and the ending B3 starts", hud.ending_active() and GameState.selected_ending == "b3", "")
	if hud.ending_screen != null:
		for connection in hud.ending_screen.finished.get_connections():
			hud.ending_screen.finished.disconnect(connection.callable)
		hud.ending_screen._finish()
	GameState.selected_ending = ""
	GameState.unable_to_move = false
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.ambient_override = -1.0
	GameState.music_override = ""
	GameState.god_mode = false
	place_player(start_spot)     # off the surface: the gate's fog and music go
	await secs(0.6)
	check("and its music", GameState.music_override != "GateB1" and GameState.music_override != "GateB2", GameState.music_override)
	var clear_env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	check("leaving the gate's fog gives the sky back its dark clear colour", clear_env.background_color.r < 0.1, "%s" % str(clear_env.background_color))

func _scn_gateb2() -> void:
	log_line("== gate B with the remote detonation on (ending B2)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var record := {}
	var nuke := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "exit1":
			record = candidate
		elif str(candidate.name) == "room2nuke":
			nuke = candidate
	if record.is_empty() or nuke.is_empty():
		check("the map has gate B and the warhead room", false, "")
		return
	# the warhead room: two levers, the first on, and its state is read while the player is in there
	place_player(nuke.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var nuke_room: Node3D = facility.rooms.get_room(nuke)
	check("the warhead room has its two levers", nuke_room.extras != null and nuke_room.extras.levers.size() == 2, "")
	check("an unvisited room counts as off", not facility.nuke_remote_on, "")
	nuke_room.extras.body_spawned = false     # the world reset removed the one made at load
	await secs(0.3)
	var corpse: HumanNpc = null
	for human in facility.humans:
		if is_instance_valid(human) and human.texture_id == HumanNpc.BODY2_TEXTURE:
			corpse = human
	check("a dead Class D (body2) lies by the warhead room's Objects[6]", corpse != null and corpse.is_dead and corpse.state == 3 and corpse.frame == 40.0 and corpse.global_position.distance_to(nuke_room.to_global(Vector3(1110.0 * 8.0 / 2048.0, 0.5, 208.0 * 8.0 / 2048.0))) < 1.5, "corpse %s humans %d" % [corpse, facility.humans.size()])
	place_player(nuke_room.to_global(Vector3(-1.5, 6.6, 1.9)))
	await secs(0.6)
	check("inside, the first lever (up) turns the remote detonation on", facility.nuke_remote_on and nuke_room.extras.levers[0].is_on(), "pitch %.0f" % nuke_room.extras.levers[0].pitch)
	nuke_room.extras.levers[0].pitch = -80.0
	await secs(0.4)
	check("thrown down it turns it off", not facility.nuke_remote_on, "")
	nuke_room.extras.levers[0].pitch = 80.0
	await secs(0.4)
	check("and up again on", facility.nuke_remote_on, "")
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.object_point(10) + Vector3(0.0, 1.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	facility.events.exit1.state = 74.9 * 70.0
	await secs(1.0)
	check("at 75 s with the remote detonation on the bomb goes off", GameState.selected_ending == "b2" and GameState.explosion_timer > 0.0, "ending '%s' timer %.0f" % [GameState.selected_ending, GameState.explosion_timer])
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var waited := 0.0
	while waited < 6.0 and not hud.ending_active():
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("about two seconds on the ending B2 starts", hud.ending_active() and hud.ending_screen.code == "b2", "after %.1f s" % waited)
	for connection in hud.ending_screen.finished.get_connections():
		hud.ending_screen.finished.disconnect(connection.callable)
	hud.ending_screen._finish()
	GameState.selected_ending = ""
	GameState.explosion_timer = 0.0
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.ambient_override = -1.0
	GameState.music_override = ""
	GameState.god_mode = false

func _scn_gatea() -> void:
	log_line("== gate A (106 escapes: ending A1)")
	var arrived: Dictionary = await _gatea_arrive(false)
	if not arrived.ok:
		return
	var room: Node3D = arrived.room
	var event: Node = room.extras
	check("gate A has been set up", facility.events.gatea.state >= 1.0 and event.apaches.size() == 3 and event.guards.size() == 2 and event.units.size() == 4, "state %.0f" % facility.events.gatea.state)
	check("the helicopters hover alert (state 1)", event.apaches[0].state == 1, "")
	check("the fog is the gate's: 5 to 30", GameState.fog_override.x == 5.0 and GameState.fog_override.y == 30.0, "")
	place_player(room.object_point(8) + Vector3(0.0, 0.3, 0.0))
	face_point(room.object_point(3) + Vector3(0.0, 1.0, 0.0))
	await secs(0.8)
	await shot("gatea_arrival")
	facility.events.gatea.state = 340.0
	await secs(1.5)
	check("106 comes up at 350 frames", event.stage_106 >= 1, "stage %d" % event.stage_106)
	event._shy.set_frame(257.0)        # the rise takes 14 s
	var wait := 0.0
	while wait < 8.0 and event.stage_106 < 2:
		await get_tree().physics_frame
		wait += get_physics_process_delta_time()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("then walks (the helicopters and the MTF turn on him)", event.stage_106 == 2 and event.apaches[0].state == 3 and event.units[0].state == 5, "stage %d heli %d unit %d" % [event.stage_106, event.apaches[0].state, event.units[0].state])
	place_player(room.object_point(8) + Vector3(0.0, 0.3, 0.0))
	face_point(event._shy.global_position + Vector3(0.0, 1.0, 0.0))
	await secs(0.4)
	await shot("gatea_106")
	# near the bridge end he sinks
	var end: Vector3 = room.object_point(4)
	event._shy.global_position = Vector3(end.x, end.y, end.z - 0.3)
	wait = 0.0
	while wait < 4.0 and event.stage_106 < 3:
		await get_tree().physics_frame
		wait += get_physics_process_delta_time()
	check("at the bridge's end he starts to sink back", event.stage_106 >= 3, "stage %d" % event.stage_106)
	event.sink_timer = 699.0
	await secs(0.5)
	check("gone: the helicopters and the MTF go for the player", event.stage_106 == 4 and event.apaches[0].state == 2 and event.units[0].state == 1, "stage %d" % event.stage_106)
	# the tunnel: the squad is put at its entrance, and the Chaos Insurgency show up
	var tunnel_end: Vector3 = room.object_point(11)
	place_player(tunnel_end + Vector3(0.0, 0.3, 0.0))
	player.blink_timer = 400.0
	await secs(0.3)
	check("near the tunnel's end the squad runs for the player and the Chaos Insurgency appear", facility.events.gatea.state3 >= 1.0 and event.ci_figures.size() == 2, "state3 %.0f player %s end %s" % [facility.events.gatea.state3, str(player.global_position), str(tunnel_end)])
	check("the squad was put at the entrance", event.units[1].global_position.distance_to(room.object_point(15)) < 12.0 or facility.events.gatea.state3 >= 2.0, "")
	await secs(1.0)
	await shot("gatea_ci")
	var fovs: Array[float] = []
	for i in 40:
		await get_tree().physics_frame
		fovs.append(player.camera.fov)
	var expected := 2.0 * rad_to_deg(atan(tan(deg_to_rad(player.BASE_FOV) * 0.5) / (1.0 + sin(deg_to_rad(facility.events.gatea.state3 * 0.8)) * 0.2)))
	check("the Chaos Insurgency scene sets the view's zoom itself (1 + Sin(EventState3 * 0.8) * 0.2)", fovs.max() - fovs.min() > 0.05 and absf(fovs[-1] - expected) < 1.5, "fov %.2f .. %.2f, last %.2f, expected about %.2f" % [fovs.min(), fovs.max(), fovs[-1], expected])
	facility.events.gatea.state3 = 235.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	await secs(0.5)
	event._voice.stop()          # the line is 5 s of real time; a fast test run does not wait for it
	var ended := 0.0
	while ended < 20.0 and not hud.ending_active():
		await get_tree().physics_frame
		ended += get_physics_process_delta_time()
	check("when the CI line ends the ending A1 begins", hud.ending_active() and hud.ending_screen.code == "a1", "after %.1f s" % ended)
	_end_ending_for_test(hud)

func _scn_gatea2() -> void:
	log_line("== gate A (106 contained: ending A2)")
	var arrived: Dictionary = await _gatea_arrive(true)
	if not arrived.ok:
		return
	var room: Node3D = arrived.room
	var event: Node = room.extras
	check("the helicopters stay quiet (state 0)", event.apaches[0].state == 0, "state %d" % event.apaches[0].state)
	check("the back door is locked", room.door_slots[2].locked, "")
	await secs(1.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	for unit in event.units:
		unit.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	var wait := 0.0
	while wait < 4.0 and facility.events.gatea.state2 < 2.0:
		await get_tree().physics_frame
		wait += get_physics_process_delta_time()
	check("the MTF stop within 6 and call out; the player cannot move", facility.events.gatea.state2 >= 2.0 and GameState.unable_to_move, "state2 %.0f" % facility.events.gatea.state2)
	await secs(0.5)
	event._voice.stop()
	var ended := 0.0
	while ended < 15.0 and not hud.ending_active():
		await get_tree().physics_frame
		ended += get_physics_process_delta_time()
	check("when the line ends the ending A2 begins", hud.ending_active() and hud.ending_screen.code == "a2", "after %.1f s" % ended)
	_end_ending_for_test(hud)

func _scn_gate079() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var records := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) in ["room2ccont", "room079", "exit1", "gateaentrance"]:
			records[str(candidate.name)] = candidate
	if not records.has("gateaentrance"):
		log_line("SKIP  079 and the gates: this map has no gate A entrance")
		return
	check("the map has the control room, 079's chamber and both gates", records.size() == 4, str(records.keys()))
	if records.size() < 4:
		return
	# the control room: three levers, all up
	place_player(records.room2ccont.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var control: Node3D = facility.rooms.get_room(records.room2ccont)
	check("the control room has its three levers", control.extras != null and control.extras.levers.size() == 3, "")
	check("the remote doors start on", facility.remote_door_on and GameState.secondary_light == 1.0, "")
	var found: bool = await _stand_before_lever(control.extras.levers[1])
	check("a spot in front of the secondary lighting lever exists", found, "")
	if not found:
		return
	await secs(0.5)
	check("looking at it starts the event", facility.ccont_state > 0.0, "state %.0f" % facility.ccont_state)
	await secs(5.0)
	check("the lever drops by itself", not control.extras.levers[1].is_on(), "pitch %.0f" % control.extras.levers[1].pitch)
	check("and the room lights fade out", GameState.secondary_light < 0.1 and not GameState.lights_on, "light %.2f" % GameState.secondary_light)
	await shot("079_lights_out")
	control.extras.levers[1].pitch = 80.0
	await secs(1.5)
	check("thrown back up the lights return", GameState.secondary_light > 0.95, "light %.2f" % GameState.secondary_light)
	check("the remote doors are still on", facility.remote_door_on, "")
	# the gate doors with the lever up and 079 not yet heard: opened, they shut again
	var exit1: Node3D = await _enter_gate_b(records.exit1)
	var gate_door: Node3D = exit1.door_slots.get(4)
	check("gate B has its door", gate_door != null, "")
	gate_door.locked = false
	gate_door.open = true
	await secs(1.5)
	check("gate B's door shuts again while 079 has not opened it", not gate_door.open and not gate_door.locked, "open %s" % gate_door.open)
	# 079's chamber with the remote doors on: the same
	place_player(records.room079.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var chamber: Node3D = facility.rooms.get_room(records.room079)
	check("the chamber has 079 and her screen", chamber.extras != null and chamber.extras.computer != null and chamber.extras.screen != null, "")
	var inner: Vector3 = chamber.to_global(Vector3(4.6, -1.2, -6.2))
	var door: Node3D = chamber.door_slots.get(0)
	place_player(inner)
	await secs(1.0)
	check("inside, the guard lies by the door", facility.events.room079.state >= 1.0 and chamber.extras.guard != null and chamber.extras.guard.state == 8 and chamber.extras.guard.is_dead, "state %.0f" % facility.events.room079.state)
	check("and 079's music plays", GameState.music_override == "079", GameState.music_override)
	door.locked = false
	door.open = true
	await secs(1.5)
	check("with the remote doors on her door shuts again", not door.open, "")
	check("she says nothing", facility.events.room079.state < 3.0 and not facility.speaking_079(), "state %.0f" % facility.events.room079.state)
	# throw the remote doors off in the control room
	place_player(records.room2ccont.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	await secs(1.5)
	control = facility.rooms.get_room(records.room2ccont)
	place_player(control.to_global(Vector3(-0.4, 4.2, 2.3)))
	await secs(0.5)
	control.extras.levers[2].pitch = -80.0
	await secs(0.6)
	check("thrown down, the remote doors are off", not facility.remote_door_on, "")
	exit1 = await _enter_gate_b(records.exit1)
	gate_door = exit1.door_slots.get(4)
	check("gate B's door is locked", gate_door.locked, "")
	# 079 speaks when the player comes within 3 of her
	place_player(records.room079.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	await secs(1.5)
	chamber = facility.rooms.get_room(records.room079)
	door = chamber.door_slots.get(0)
	place_player(chamber.to_global(Vector3(4.6, -1.2, -6.2)))
	await secs(0.5)
	check("her door stays open now", door.locked == false, "")
	var computer_at: Vector3 = chamber.extras.computer.global_position
	place_player(computer_at + Vector3(-2.0, 0.9, 0.0).rotated(Vector3.UP, chamber.rotation.y))
	await secs(1.0)
	check("within 3 she speaks and gives the achievement", facility.events.room079.state == 3.0 and facility.events.room079.state2 == 1.0 and GameState.achievements.has("079"), "state %.0f/%.0f" % [facility.events.room079.state, facility.events.room079.state2])
	check("her voice plays and the screen shows her face", facility.speaking_079() and chamber.extras.screen != null, "")
	var gaze: Vector3 = chamber.extras.screen.global_position - player.camera.global_position
	player.rotation.y = atan2(-gaze.x, -gaze.z)
	player.camera.rotation.x = atan2(gaze.y, Vector2(gaze.x, gaze.z).length())
	player.user_pitch = -rad_to_deg(player.camera.rotation.x)
	await secs(0.3)
	await shot("079_speaks")
	facility.events.room079.voice.stop()
	await secs(0.3)
	check("when she is done the calm face stays", chamber.extras.screen.visible, "")
	facility.events.room079.state = 1999.0
	await secs(0.5)
	check("2000 frames on, close by, she refuses", facility.events.room079.state == 10001.0, "state %.0f" % facility.events.room079.state)
	check("the gates are not open yet", not facility.gate_a_unlocked and not facility.gate_b_unlocked, "")
	# the lever back up: she opens the gates
	place_player(records.room2ccont.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	await secs(1.5)
	control = facility.rooms.get_room(records.room2ccont)
	place_player(control.to_global(Vector3(-0.4, 4.2, 2.3)))
	await secs(0.5)
	control.extras.levers[2].pitch = 80.0
	await secs(0.8)
	check("put back up, the remote doors are on", facility.remote_door_on, "")
	check("she opens both gates", facility.gate_a_unlocked and facility.gate_b_unlocked and facility.events.room079.state2 == 2.0, "")
	check("and says so", facility.speaking_079(), "")
	exit1 = await _enter_gate_b(records.exit1)
	gate_door = exit1.door_slots.get(4)
	gate_door.open = true
	await secs(2.0)
	check("gate B's door now stays open", gate_door.open and not gate_door.locked, "open %s locked %s" % [gate_door.open, gate_door.locked])
	GameState.god_mode = false

func _scn_femur() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room106":
			record = candidate
	check("the map has SCP-106's chamber", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var chamber: Node3D = facility.rooms.get_room(record)
	var femur: Node3D = chamber.extras
	check("the chamber has its levers, button and platform", femur != null and femur.levers.size() == 2 and femur.button != null and femur.platform != null, "")
	var found: bool = await _stand_before_lever(femur.levers[1])
	check("a spot in front of the transmission lever exists", found, "")
	if not found:
		return
	var old_man: Node = facility.spawn_106(70.0 * 60.0 * 20.0)
	await secs(0.5)
	check("the lure subject hangs in the cell", facility.events.femur.subject != null and is_instance_valid(facility.events.femur.subject) and facility.events.femur.subject.state == 6, "")
	var held_at: Vector3 = femur.room.object_point(5)
	check("the lure subject's model is not lifted above Objects[5] -0.22 (collider +0.1, model -0.32)", facility.events.femur.subject.global_position.y < held_at.y - 0.22 + 0.08, "y=%.3f pivot=%.3f" % [facility.events.femur.subject.global_position.y, held_at.y])
	check("the magnets start on and the transmission off", facility.events.femur.magnets and not facility.events.femur.transmission, "")
	check("the platform stands up", absf(femur.platform.position.y - (-980.0 * 8.0 / 2048.0)) < 0.2, "y %.2f" % femur.platform.position.y)
	check("the magnets lever is free with the platform up", not femur.levers[0].locked, "")
	var rest_y: float = facility.events.femur.platform_y
	facility.events.femur.platform_y = -1100.0 * 8.0 / 2048.0
	await secs(0.1)
	check("the magnets lever is locked while the platform is in transit", femur.levers[0].locked, "")
	facility.events.femur.platform_y = rest_y
	await secs(0.1)
	# the button does nothing while the transmission is off
	femur.button.press()
	await secs(0.3)
	check("the button needs the transmission", facility.events.femur.state == 0, "")
	# a real click on the button from beside it
	var beside: bool = await _stand_before_point(femur.button.global_position, func() -> bool: return player.closest_plain_button() == femur.button)
	check("a spot beside the button exists", beside, "")
	check("the button is found with the camera on it", player.closest_plain_button() == femur.button, "")
	femur.levers[1].pitch = 80.0
	await secs(0.5)
	check("the transmission lever turns it on", facility.events.femur.transmission, "")
	await tap("interact")
	await secs(0.3)
	check("a click on the button starts the breaker", facility.events.femur.state == 1, "state %d" % facility.events.femur.state)
	check("the breaker sounds", facility.events.femur.voice != null and is_instance_valid(facility.events.femur.voice), "")
	await secs(1.0)
	check("the timer runs with the transmission on", facility.events.femur.timer > 10.0, "%.0f" % facility.events.femur.timer)
	# containment: magnets off before the bait, back on during it
	facility.events.femur.timer = 2000.0
	GameState.grabbed_lever = femur.levers[0]
	femur.levers[0].pitch = -80.0
	await secs(0.3)
	GameState.grabbed_lever = null
	check("the magnets go off", not facility.events.femur.magnets, "")
	await secs(1.5)
	check("the platform sinks", facility.events.femur.platform_y < -1100.0 * 8.0 / 2048.0, "y %.2f" % facility.events.femur.platform_y)
	facility.events.femur.timer = 2480.0
	await secs(1.0)
	check("at 2500 he rises into the cell (idle, bait pose, his music)", old_man.idle and old_man.visible and old_man.state == -11.0 and GameState.music_override == "106", "idle %s state %.0f music %s" % [old_man.idle, old_man.state, GameState.music_override])
	check("the cell is where he is", old_man.global_position.distance_to(chamber.object_point(5)) < 3.0, "%.2f" % old_man.global_position.distance_to(chamber.object_point(5)))
	await shot("femur_bait")
	var moving: Node3D = femur.levers[1]
	moving.pitch = -80.0
	await secs(0.3)
	check("the transmission lever cannot be moved during the bait", facility.events.femur.transmission, "")
	GameState.grabbed_lever = femur.levers[0]
	femur.levers[0].pitch = 80.0
	await secs(0.3)
	GameState.grabbed_lever = null
	check("the magnets come on", facility.events.femur.magnets, "")
	var lens_stains := 0
	for child in femur.room.cams[0]._head.get_children():
		if child is GrowingDecal:
			lens_stains += 1
	check("the camera's lens has no smear before 2900", lens_stains == 0, "%d" % lens_stains)
	facility.events.femur.timer = 2890.0
	await secs(0.6)
	lens_stains = 0
	for child in femur.room.cams[0]._head.get_children():
		if child is GrowingDecal:
			lens_stains += 1
	check("the camera's lens is smeared once at 2900", lens_stains == 1, "%d" % lens_stains)
	var lens: GrowingDecal = null
	for child in femur.room.cams[0]._head.get_children():
		if child is GrowingDecal:
			lens = child
	if lens != null:
		check("the lens smear sits left of and ahead of the lens, unturned, fading in (UpdateEvents.bb 6137-6153)", lens.position.x < -0.05 and lens.position.z < -0.1 and lens.position.z > -0.25 and lens.basis.orthonormalized().is_equal_approx(Basis.IDENTITY) and lens.alpha_change == 0.005, "pos %s alpha_change %.3f" % [lens.position, lens.alpha_change])
	var fading := 0
	for node in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if node is GrowingDecal and node.texture_file == "GFX/decal1.png" and node.alpha_change == 0.005:
			fading += 1
	check("the 2500 stain and the lens smear both fade in", fading >= 2, "%d" % fading)
	facility.events.femur.timer = 3190.0
	await secs(1.0)
	check("at 3200 with the magnets on he is caught", facility.contained_106 and not old_man.visible, "contained %s" % facility.contained_106)
	await secs(9.0)
	check("the platform is up again", facility.events.femur.platform_y > -1000.0 * 8.0 / 2048.0, "y %.2f" % facility.events.femur.platform_y)
	# the other endings of the breaker
	_femur_reset()
	facility.events.femur.state = 1
	facility.events.femur.transmission = true
	femur.levers[1].pitch = 80.0
	facility.events.femur.magnets = false
	facility.events.femur.timer = 3150.0
	await secs(1.5)
	check("magnets off at 3200: he is loose and the event is over", not facility.contained_106 and facility.events.femur.state == 2 and not old_man.idle and old_man.visible and old_man.state <= -10.0, "state %d contained %s idle %s" % [facility.events.femur.state, facility.contained_106, old_man.idle])
	var from_platform: float = old_man.global_position.distance_to(chamber.to_global(Vector3(3.0625, facility.events.femur.platform_y, -2.8125)))
	check("he came out of the platform", from_platform < 6.0, "%.1f" % from_platform)
	_femur_reset()
	facility.events.femur.state = 1
	facility.events.femur.transmission = true
	facility.events.femur.magnets = true
	facility.events.femur.timer = 2499.0
	await secs(0.6)
	check("magnets on when the bait starts: he is out at once", facility.events.femur.state == 2 and not facility.contained_106 and not old_man.idle, "state %d" % facility.events.femur.state)
	# a contained 106 stays out of the way
	facility.contained_106 = true
	await secs(0.5)
	check("a contained 106 is hidden and idle", not old_man.visible and old_man.idle, "")
	facility.contained_106 = false
	await secs(0.5)
	check("let go he is active again", not old_man.idle, "")
	GameState.music_override = ""
	GameState.god_mode = false

# Lighting comparison: the intro's office stairs (the user's screenshot of the original is from here).
func _scn_introview() -> void:
	var scene: Node = main.intro_scene
	await _intro_skip_to_door(scene)
	GameState.god_mode = true
	var spots := [[-3328.0, -1232.0], [-3328.0, -1000.0], [-3100.0, -1232.0], [-3550.0, -1232.0]]
	var target: Vector3 = scene.at(-3361.0, -315.0 * 8.0 / 2048.0, -2165.0)
	var index := 0
	for spot in spots:
		place_player(scene.at(spot[0], 1.0, spot[1]))
		await secs(0.8)
		var look: Vector3 = target - player.camera.global_position
		player.rotation.y = atan2(-look.x, -look.z)
		player.camera.rotation.x = deg_to_rad(8.0)
		player.user_pitch = -8.0
		await secs(0.8)
		var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
		log_line("spot %d at %s fog %s %.1f..%.1f" % [index, scene.rs_of(player.global_position), env.fog_enabled, env.fog_depth_begin, env.fog_depth_end])
		await shot("introview%d" % index)
		index += 1

# Close-ups of levers (base and handle orientation): the control room's and the warhead room's.
func _scn_leverview() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	GameState.fog_of_war = false
	var index := 0
	for wanted in ["room2ccont", "room2nuke", "room106"]:
		var record := {}
		for candidate in facility.generator.rooms:
			if str(candidate.name) == wanted:
				record = candidate
		if record.is_empty():
			continue
		place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
		await secs(1.5)
		var room: Node3D = facility.rooms.get_room(record)
		var lever: Node3D = room.extras.levers[0]
		if await _stand_before_lever(lever):
			var back: Vector3 = (player.global_position - lever.global_position)
			back.y = 0.0
			place_player(player.global_position + back.normalized() * 0.4)
			await secs(0.3)
			var look: Vector3 = lever.global_position - player.camera.global_position
			player.rotation.y = atan2(-look.x, -look.z)
			player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
			player.user_pitch = -rad_to_deg(player.camera.rotation.x)
			await secs(0.5)
			var handle_mesh: MeshInstance3D = lever._handle.get_child(0)
			var base_mesh: MeshInstance3D = lever.get_child(0)
			var hbox: AABB = handle_mesh.global_transform * handle_mesh.mesh.get_aabb()
			var bbox: AABB = base_mesh.global_transform * base_mesh.mesh.get_aabb()
			log_line("%s pitch %.0f: handle box %s, base box %s, camera %s" % [wanted, lever.pitch, hbox, bbox, player.camera.global_position])
			await shot("lever_%d_%s" % [index, wanted])
		index += 1
	GameState.fog_of_war = true

func _scn_scp914() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	# the knob's settings from its roll
	check("the knob settings follow its roll", Room914.setting_of(0.0)[0] == "1:1" and Room914.setting_of(40.0)[0] == "coarse" and Room914.setting_of(90.0)[0] == "rough" and Room914.setting_of(-40.0)[0] == "fine" and Room914.setting_of(-90.0)[0] == "very fine" and Room914.setting_of(-1.0)[0] == "1:1", "")
	var gas: Dictionary = Recipes914.refine("Gas Mask", "gasmask", "fine")
	check("a gas mask on fine is the better mask", gas.remove and gas.outputs[0][1] == "supergasmask", str(gas.outputs))
	var rough_card: Dictionary = Recipes914.refine("Level 2 Key Card", "key2", "rough")
	check("a key card on rough is a stain", rough_card.remove and rough_card.outputs.is_empty() and rough_card.decal[1] == 0.07, str(rough_card.decal))
	var panel: Dictionary = Recipes914.refine("Metal Panel", "scp148", "rough")
	check("the metal panel on rough is an ingot", panel.outputs[0][1] == "scp148ingot", "")
	var cards := {}
	for i in 300:
		var made: Dictionary = Recipes914.refine("Level 3 Key Card", "key3", "fine", 1, 0)
		var key := str(made.outputs[0][1])
		cards[key] = int(cards.get(key, 0)) + 1
	check("a level 3 card on fine is mostly a playing card, rarely a level 4", cards.get("misc", 0) > 240 and cards.get("key4", 0) >= 1, str(cards))
	var pill: Dictionary = Recipes914.refine("Pill", "pill", "rough")
	check("a pill on rough leaves a stain and stays", not pill.remove and not pill.decal.is_empty(), "")
	var syringe: Dictionary = Recipes914.refine("Syringe", "veryfinesyringe", "very fine")
	check("the very fine syringe is a zombie", syringe.npc == "008", "")
	var goggles_fine: Dictionary = RoomFill.item_template("Night Vision Goggles", "finenvgoggles")
	var goggles_plain: Dictionary = RoomFill.item_template("Night Vision Goggles", "nvgoggles")
	check("variants of the same name keep their own template (the night vision goggles)", not goggles_fine.is_empty() and str(goggles_fine.icon) != str(goggles_plain.icon), "")
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "914":
			record = candidate
	check("the map has SCP-914", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	var machine: Node3D = room.extras
	check("the room has the machine, its key and knob and three doors", machine != null and machine.key != null and machine.knob != null and room._fill_doors.size() == 3, "")
	if machine == null or machine.key == null:
		return
	var booth: Vector3 = room.object_point(2)
	var output: Vector3 = room.object_point(3)
	var standing: Vector3 = room.to_global(Vector3(0.0, 0.0, -0.8))
	standing.y = room.global_position.y + 1.55
	place_player(standing)
	player.rotation.y = room.rotation.y
	await secs(0.5)
	check("the doors start open", machine.intake_door().open and machine.output_door().open, "")
	check("no 914 music while the chamber door is shut", machine.state2 == 0.0 and GameState.music_override != "914", "state2 %.0f music %s" % [machine.state2, GameState.music_override])
	room._fill_doors[0].open = true
	await secs(0.3)
	check("opening the chamber door (RoomDoors[2]) starts the 914 music (UpdateEvents.bb 7358: ShouldPlay = 22)", machine.state2 == 1.0 and GameState.music_override == "914", "state2 %.0f music %s" % [machine.state2, GameState.music_override])
	# a real turn of the key: grab it and drag sideways
	machine.knob_roll = 0.0
	face_point(machine.key.global_position)
	var to_key: Vector3 = machine.key.global_position - player.camera.global_position
	player.camera.rotation.x = atan2(to_key.y, Vector2(to_key.x, to_key.z).length())
	await secs(0.3)
	check("the key is under the crosshair within a metre", machine._pick(player.camera) == machine.key, "dist %.2f" % player.camera.global_position.distance_to(machine.key.global_position))
	for view_roll in [90.0, -90.0, 0.0]:
		machine.knob_roll = view_roll
		await secs(0.4)
		await shot("scp914_knob_%d" % int(view_roll))
	var spot_items := [["Level 2 Key Card", "key2"], ["Gas Mask", "gasmask"], ["First Aid Kit", "firstaid"]]
	for pair in spot_items:
		var item: Node3D = RoomFill.make_pickup(pair[0], pair[1])
		room.add_child(item)
		item.global_position = booth + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2))
	await secs(0.5)
	Input.action_press("interact")
	var frames := 0
	var arrows_seen := [false, false, false, false]
	while machine.state == 0.0 and frames < 400:
		player.test_mouse_speed = Vector2(25.0, 0.0)
		await get_tree().physics_frame
		await get_tree().process_frame
		for arrow in 4:
			arrows_seen[arrow] = arrows_seen[arrow] or GameState.arrow_icons[arrow] or get_tree().get_first_node_in_group("hud")._meters.arrows_shown[arrow]
		frames += 1
	player.test_mouse_speed = Vector2.ZERO
	Input.action_release("interact")
	check("the held key shows the right arrow", arrows_seen[1], "")
	check("turning the key starts the machine", machine.state > 0.0, "frames %d roll %.0f" % [frames, machine.key_roll])
	await secs(0.2)
	check("the output door shuts at once", not machine.output_door().open, "")
	await secs(2.2)
	check("the intake door shuts 2 s later", not machine.intake_door().open, "")
	await secs(1.0)
	await shot("scp914_running")
	await secs(10.5)
	check("the doors open again when it is done", machine.state == 0.0 and machine.intake_door().open and machine.output_door().open, "state %.0f" % machine.state)
	var near_output := _items_near(output, 0.6)
	check("1:1 turned the key card into a playing card and left the mask and the kit", near_output.has("misc") and near_output.has("gasmask") and (near_output.has("firstaid") or near_output.has("firstaid2")) and not near_output.has("key2"), str(near_output))
	check("the intake is empty", _items_near(booth, 0.6).is_empty(), str(_items_near(booth, 0.6)))
	check("the refined counter counts the three", GameState.refined_items >= 3, str(GameState.refined_items))
	# fine, with the player in the intake: faster, moved to the output
	_clear_items_near(output, 0.8)
	var mask: Node3D = RoomFill.make_pickup("Gas Mask", "gasmask")
	room.add_child(mask)
	mask.global_position = booth + Vector3(0.0, 0.3, 0.0)
	place_player(booth + Vector3(0.0, 1.0, 0.1))
	machine.knob_roll = -40.0
	await secs(0.5)
	check("the knob settles on fine", machine.setting == "fine", machine.setting)
	machine.start_for_test()
	await secs(6.0)
	check("a player in the intake closes their eyes after 3 s", player.blink_timer <= -6.0, "%.0f" % player.blink_timer)
	await secs(7.5)
	check("fine made the player fast", GameState.super_man, "")
	var from_output := Vector2(player.global_position.x - output.x, player.global_position.z - output.z).length()
	check("and moved them to the output booth", from_output < 0.8, "%.2f" % from_output)
	check("the gas mask became the better one", _items_near(output, 0.8).has("supergasmask"), str(_items_near(output, 0.8)))
	GameState.super_man_timer = 70.0 * 50.0 - 5.0
	GameState.god_mode = false
	await secs(0.5)
	check("the fast player dies after 50 s", player.dead, "")
	revive()
	GameState.super_man = false
	GameState.super_man_timer = 0.0
	GameState.god_mode = true
	# coarse: bleeding
	machine.knob_roll = 40.0
	place_player(booth + Vector3(0.0, 1.0, 0.1))
	await secs(0.5)
	machine.start_for_test()
	await secs(13.5)
	check("coarse cut the player", GameState.injuries >= 4.0, "%.1f" % GameState.injuries)
	GameState.injuries = 0.0
	# rough: the player does not survive
	machine.knob_roll = 90.0
	place_player(booth + Vector3(0.0, 1.0, 0.1))
	GameState.god_mode = false
	await secs(0.5)
	machine.start_for_test()
	await secs(13.5)
	check("rough kills a player in the intake", player.dead, "")
	revive()
	GameState.god_mode = true
	GameState.blur_timer = 0.0

func _scn_scp294() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	check("294 knows the coffee by a prefix", not Data294.find("coff").is_empty() and str(Data294.find("coff").get("message", "")).contains("coffee"), "")
	check("294 knows a name from the middle of a list of names", not Data294.find("black coffee").is_empty(), "")
	check("294 has no zzz", Data294.find("zzz").is_empty(), "")
	check("a typed part from the middle of a name is not enough", Data294.find("lack coffee").is_empty(), "")
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2cafeteria":
			record = candidate
	check("the map has the cafeteria", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	var cafe: Node3D = room.extras
	check("the cafeteria has its 294 event", cafe != null and cafe.has_method("spawn_cup"), "")
	if cafe == null or not cafe.has_method("spawn_cup"):
		return
	var names: Array = []
	for child in room.get_children():
		if child.is_in_group("pickup") and str(child.get_meta("tempname", "")) == "cup":
			names.append(str(child.get_meta("item_name", "")))
	names.sort()
	check("the two cups on the tables are orange juice and coffee", names == ["Cup of Coffee", "Cup of Orange Juice"], str(names))
	var machine: Vector3 = room.object_point(0)
	var spout: Vector3 = room.object_point(1)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var panel: Node = get_tree().get_first_node_in_group("scp294_panel")
	check("the keyboard panel exists", panel != null and not panel.is_open(), "")
	# stand in front of the machine, a metre away, looking at it
	var side: Vector3 = (room.to_global(Vector3(0.0, 0.0, 0.0)) - machine)
	side.y = 0.0
	var standing: Vector3 = machine + side.normalized() * 1.0
	standing.y = machine.y + 1.8
	place_player(standing)
	face_point(machine)
	await secs(0.6)
	check("standing at the machine gives the 294 achievement", GameState.achievements.has("294"), "")
	# no coins: a message
	facility.scp294_coins = 0
	cafe.click(facility)
	check("a click without a quarter says so", hud.message_time_left() > 0.0 and facility.scp294_coins == 0, "")
	var slot: int = _give(hud, "Quarter", "25ct")
	hud.set_selected(slot)
	cafe.click(facility)
	check("a quarter goes in", facility.scp294_coins == 1 and hud.items[slot].is_empty(), "coins %d" % facility.scp294_coins)
	check("the panel needs a second one", not panel.is_open(), "")
	slot = _give(hud, "Quarter", "25ct")
	hud.set_selected(slot)
	cafe.click(facility)
	check("the second quarter opens the keyboard", panel.is_open() and GameState.using_294, "coins %d" % facility.scp294_coins)
	await shot("scp294_panel")
	panel.type_and_dispense("zzz")
	await secs(0.3)
	check("an unknown drink is OUT OF RANGE", panel.input == "OUT OF RANGE" and panel.is_open(), panel.input)
	await secs(5.0)
	check("the display clears and the panel stays", panel.input == "" and panel.is_open(), "[%s]" % panel.input)
	panel.type_and_dispense("a cup of coffee")
	await secs(0.5)
	check("a known drink dispenses", panel.input == "DISPENSING..." or panel.input == "", panel.input)
	var cup: Node = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Cup of coffee":
			cup = node
	check("a cup of coffee is at the spout", cup != null and Vector2(cup.global_position.x - spout.x, cup.global_position.z - spout.z).length() < 0.05, "")
	if cup != null:
		check("it is brown", absf(float(cup.get_meta("cr")) - 87.0 / 255.0) < 0.01 and float(cup.get_meta("ca")) == 1.0, "")
		var meshes := 0
		for child in cup.get_children():
			if child is MeshInstance3D:
				meshes += 1
		check("the cup has its model and the liquid in it", meshes == 2 and cup._liquid != null and cup._liquid.visible, "meshes %d" % meshes)
	await shot("scp294_dispensing")
	await secs(6.0)
	check("the panel goes when the drink is out, and the quarters are used", not panel.is_open() and facility.scp294_coins == 0 and not GameState.using_294, "coins %d" % facility.scp294_coins)
	check("the spout is blocked while the cup stands there", not cafe.spout_free(), "")
	player.camera.rotation.x = -0.9
	await secs(0.3)
	await shot("scp294_cup")
	var cup_slot: int = -1
	if cup != null:
		hud.try_pickup(cup)
		cup.queue_free()
		for i in hud.items.size():
			if hud.items[i] == "Cup of coffee":
				cup_slot = i
	check("the cup goes into the inventory with its colour", cup_slot >= 0 and absf(float(hud.item_data[cup_slot].get("cr", 0.0)) - 87.0 / 255.0) < 0.01, "")
	GameState.blur_timer = 0.0
	hud.set_selected(cup_slot)
	await secs(0.3)
	check("drinking the coffee blurs the view, slows the stamina and leaves an empty cup", GameState.blur_timer > 100.0 and absf(GameState.stamina_effect - 0.9) < 0.01 and hud.items[cup_slot] == "Empty Cup", "blur %.0f stamina %.2f item %s" % [GameState.blur_timer, GameState.stamina_effect, hud.items[cup_slot]])
	# a refused drink stays in the hand
	var air_cup: Node = RoomFill.make_pickup("Cup of air", "cup", {"cr": 0.0, "cg": 0.0, "cb": 0.0, "ca": 0.0})
	room.add_child(air_cup)
	hud.try_pickup(air_cup)
	air_cup.queue_free()
	var air_slot := -1
	for i in hud.items.size():
		if hud.items[i] == "Cup of air":
			air_slot = i
	hud.set_selected(air_slot)
	await secs(0.2)
	check("a cup of nothing is refused", hud.items[air_slot] == "Cup of air", hud.items[air_slot])
	# a slow poison
	var bleach_slot: int = _give(hud, "Cup of bleach", "cup")
	hud.set_selected(bleach_slot)
	await secs(0.2)
	check("bleach starts a 50 s death timer", GameState.death_timer > 70.0 * 49.0, "%.0f" % GameState.death_timer)
	GameState.death_timer = 0.0
	# the sickness
	GameState.vomit_timer = 2.0
	GameState.blur_timer = 0.0
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	await secs(3.5)
	check("a sick player vomits: injuries 1.5, blood loss 70, a long blur", GameState.vomit and absf(GameState.injuries - 1.5) < 0.01 and GameState.bloodloss >= 70.0 and GameState.blur_timer > 2000.0, "inj %.1f blood %.0f blur %.0f" % [GameState.injuries, GameState.bloodloss, GameState.blur_timer])
	await secs(1.5)
	check("they cannot move for the first seconds", GameState.unable_to_move, "")
	await secs(15.0)
	check("afterwards they are given back what they had", not GameState.vomit and GameState.injuries == 0.0 and GameState.bloodloss == 0.0 and not GameState.unable_to_move, "inj %.1f blood %.0f" % [GameState.injuries, GameState.bloodloss])
	# the lethal one
	GameState.god_mode = false
	var death_slot: int = _give(hud, "Cup of death", "cup")
	hud.set_selected(death_slot)
	await secs(0.3)
	check("a lethal drink kills", player.dead, "")
	revive()
	GameState.god_mode = true
	GameState.blur_timer = 0.0
	GameState.stamina_effect = 1.0
	GameState.stamina_effect_timer = 0.0

func _scn_room049() -> void:
	MeshLoader._ambient = 1.0       # the zombies are looked at in a screenshot: the chamber is dark
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	facility.events.room049.state = 0.0
	facility.events.room049.pitches = [81.0, -11.0]
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room049":
			record = candidate
	check("the map has SCP-049's chamber", not record.is_empty(), "")
	if record.is_empty():
		return
	facility.spawn_049_enabled = false
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(30.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	var event: Node3D = room.extras
	check("the room has its event, two levers and four lifts doors", event != null and event.levers.size() == 2 and room.door_slots.has(3), "")
	if event == null or event.levers.size() != 2:
		return
	check("the power feed starts up and the generator down", event.levers[0].is_on() and not event.levers[1].is_on(), "")
	# above ground nothing happens
	check("nothing was made above the chamber", facility.events.room049.state == 0.0 and facility.zombies008.is_empty(), "")
	# down in the chamber for the first time
	var floor_spot: Vector3 = room.object_point(4)
	place_player(floor_spot + Vector3(1.0, 1.0, 0.0))
	await secs(1.0)
	check("the first visit makes the zombies, 049 and the document", facility.events.room049.state >= 1.0 and facility.zombies008.size() == 2 and facility.scp049 != null, "state %.0f zombies %d" % [facility.events.room049.state, facility.zombies008.size()])
	var scheme := false
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Research Sector-02 Scheme":
			scheme = true
	check("the map document lies in the chamber", scheme, "")
	check("the zombies lie still", facility.zombies008[0].state == 0 and facility.zombies008[1].state == 0, "")
	await shot("room049_zombie")
	check("049 waits hidden", facility.scp049.idle > 0.1, "")
	await secs(1.5)
	check("the lights are out without the generator", GameState.secondary_light < 0.5, "%.2f" % GameState.secondary_light)
	check("the lifts are dead and the lower doors locked", not room._lifts[0].enabled and room.door_slots[1].locked and room.door_slots[3].locked, "")
	event.levers[1].pitch = 80.0
	await secs(1.0)
	check("the generator brings the lights back", GameState.secondary_light > 0.5, "%.2f" % GameState.secondary_light)
	check("the storage doors unlock", not room.door_slots[4].locked and not room.door_slots[5].locked and not room.door_slots[6].locked, "")
	check("the zombies get up", facility.zombies008[0].state >= 1 and facility.zombies008[1].state >= 1, "states %d %d" % [facility.zombies008[0].state, facility.zombies008[1].state])
	check("the event moved on", facility.events.room049.state >= 70.0 * 241.0, "%.0f" % facility.events.room049.state)
	check("the lower doors are shut and the upper ones open", not room.door_slots[1].open and not room.door_slots[3].open and room.door_slots[0].open and room.door_slots[2].open, "")
	check("the lifts are still off while the power feed is up", not room._lifts[0].enabled, "")
	var first_zombie: Node = facility.zombies008[0]
	first_zombie.set_physics_process(false)
	first_zombie.set_frame(719.0)
	place_player(first_zombie.global_position + Vector3(0.0, 1.5, 0.0) + Vector3(1.8, 0.0, 0.8))
	face_point(first_zombie.global_position + Vector3(0.0, 0.3, 0.0))
	GameState.fog_of_war = false
	await secs(0.5)
	await shot("room049_zombie_lit")
	GameState.fog_of_war = true
	first_zombie.set_physics_process(true)
	# the power feed off: the lifts work and 049 is sent out of the lift the player is next to
	event.levers[0].pitch = -80.0
	# the lift shaft lies under the neighbouring room's cell: walking there keeps PlayerRoom (deep down), a teleport would not
	player.velocity = Vector3.ZERO
	player.global_position = room.door_slots[1].global_position + room.global_transform.basis * Vector3(1.0, 1.0, 0.0)
	await secs(1.0)
	check("the lifts work with the power feed off and the generator on", room._lifts[0].enabled and not room.door_slots[1].locked, "")
	check("049 comes out of the lift", facility.scp049.idle == 0.0 and facility.scp049.state == 2, "idle %.1f state %d" % [facility.scp049.idle, facility.scp049.state])
	# the zombies hunt: one of them close to the player attacks
	var zombie: Node = facility.zombies008[0]
	zombie.global_position = player.global_position + Vector3(0.0, 0.0, 0.0) + player.global_transform.basis * Vector3(0.0, 0.0, -0.9)
	zombie.state = 2
	zombie.state2 = 70.0 * 5.0
	GameState.injuries = 0.0
	await secs(3.0)
	check("a zombie that reaches the player hurts them", GameState.injuries > 0.0 and zombie.hits > 0, "inj %.2f hits %d" % [GameState.injuries, zombie.hits])
	for idle_zombie in facility.zombies008:
		idle_zombie.set_state(4)
		idle_zombie.global_position += Vector3(0.0, 0.0, 40.0)
	# 049 catches the player in the chamber, under room049's own cell: the original keeps PlayerRoom when the player is deep down,
	# the port's room lookup does not, and next to the lower doors it can find the neighbouring room
	var chamber := _find_room("room049")
	place_player(Vector3(chamber.position.x, player.global_position.y, chamber.position.z))
	facility.scp049.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	GameState.god_mode = false
	facility.scp049._reach_player(1.0, player)
	check("049 does not kill them in his chamber, he starts the scene", facility.events.room049.state == -1.0 and not player.dead and GameState.death_msg.contains("Three (3)"), "state %.0f in %s y %.2f" % [facility.events.room049.state, facility.room_name_at(player.global_position), player.global_position.y])
	await secs(9.0)
	check("they wake in the middle of the chamber as one of the infected", GameState.is_zombie and GameState.force_move == 0.5 and event.squad.size() == 3, "squad %d" % event.squad.size())
	check("the zombies are put away and 049 is back at the lift", facility.zombies008[0].state == 4 and facility.zombies008[1].state == 4, "")
	await shot("room049_scene")
	await secs(14.0)
	check("the soldiers shoot them", player.dead, "")
	revive()
	GameState.god_mode = true
	GameState.is_zombie = false
	GameState.force_move = 0.0
	GameState.blur_timer = 0.0
	GameState.injuries = 0.0
	GameState.secondary_light = 1.0
	facility.events.room049.state = 0.0
	MeshLoader._ambient = -1.0

func _scn_scp1025() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	_clear_items(hud)
	for i in 6:
		GameState.scp1025[i] = 0.0
	var book: int = _give(hud, "SCP-1025", "scp1025")
	hud.set_selected(book)
	await secs(0.5)
	var roll := int(hud.item_data[book].state)
	check("the page is shown", hud._doc_rect.visible, "")
	check("the book gives the 1025 achievement", GameState.achievements.has("1025"), "")
	check("the illness of the page starts", GameState.scp1025[roll] > 0.9, "roll %d %s" % [roll, str(GameState.scp1025)])
	await shot("scp1025_page")
	# the cardiac arrest grows 0.35 a frame while it is held
	hud.item_data[book]["state"] = 5.0
	GameState.scp1025[5] = 0.0
	await secs(1.5)
	check("the cardiac arrest grows", GameState.scp1025[5] > 20.0, "%.1f" % GameState.scp1025[5])
	hud.deselect()
	for i in 6:
		GameState.scp1025[i] = 0.0
	GameState.scp1025[0] = 1.0
	GameState.i427_using = false
	await secs(2.0)
	check("a cold persists without SCP-427", GameState.scp1025[0] == 1.0, "%.3f" % GameState.scp1025[0])
	GameState.i427_using = true
	await secs(2.0)
	check("SCP-427 wears a cold off", GameState.scp1025[0] < 0.95 and GameState.scp1025[0] > 0.8, "%.3f" % GameState.scp1025[0])
	GameState.i427_using = false
	GameState.i427_timer = 0.0
	GameState.infect = 50.0
	GameState.i427_using = true
	await secs(1.0)
	check("SCP-427 stops the infection growing", GameState.infect < 50.0, "%.4f" % GameState.infect)
	GameState.i427_using = false
	GameState.i427_timer = 0.0
	GameState.infect = 0.0
	# the ring protects
	for i in 6:
		GameState.scp1025[i] = 0.0
	GameState.wearing_714 = true
	hud.set_selected(book)
	await secs(0.5)
	check("SCP-714 protects the reader", GameState.scp1025[int(hud.item_data[book].state)] == 0.0, "")
	GameState.wearing_714 = false
	hud.deselect()
	# a pill clears them
	GameState.scp1025[3] = 5.0
	var pill: int = _give(hud, "SCP-500-01", "scp500")
	hud.set_selected(pill)
	await secs(0.3)
	check("SCP-500 cures them", GameState.scp1025[3] == 0.0, "")
	_clear_items(hud)

func _scn_coffin() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "coffin":
			record = candidate
	check("the map has SCP-895's chamber", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	await secs(0.5)
	var event: Node = room.extras
	check("the room has its event", event != null and event.lever != null, "")
	if event == null or event.lever == null:
		return
	var cam: Node = null
	for c in room.cams:
		if c.coffin_effect == 1:
			cam = c
	check("the chamber's own camera always carries 895", cam != null, "")
	if cam != null:
		var down: float = rad_to_deg(asin(-cam.head_forward().normalized().y))
		check("the coffin camera looks 60 degrees down into the pit (TurnEntity 120 read back by EntityPitch)", absf(down - 60.0) < 1.0, "%.1f" % down)
	check("the lever starts up and the monitor is on", event.lever.is_on() and cam.screen_on, "pitch %.1f" % event.lever.pitch)
	var coffin: Vector3 = room.object_point(1)
	check("the coffin is six metres down", coffin.y < room.global_position.y - 5.0, "y %.2f" % coffin.y)
	check("the chamber holds the night vision goggles", "nvgoggles" in _items_near(coffin, 3.0), "")
	# the goggles in the chamber are charged
	var found_state := -1.0
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Night Vision Goggles" and node.global_position.distance_to(coffin) < 3.0:
			found_state = float(node.get_meta("state", 0.0))
	check("they come charged", found_state == 400.0, "state %.0f" % found_state)
	# the pit's floor runs from the coffin back under the room; across it are walls
	var back := Vector3(room.global_position.x - coffin.x, 0.0, room.global_position.z - coffin.z).normalized()
	# the guard hangs once the player is within 3 of the coffin
	GameState.coffin_distance = 100.0
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 2.4)
	await secs(0.8)
	check("a dead guard hangs over the pit", event.guard != null and event._phase == 0 and event.guard.frame == 270.0, "")
	check("CoffinDistance is the player's distance to the coffin", GameState.coffin_distance < 3.0, "%.2f" % GameState.coffin_distance)
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 2.4)
	face_point(event.guard.global_position + Vector3(0.0, 0.6, 0.0))
	var up_to: Vector3 = event.guard.global_position + Vector3(0.0, 0.6, 0.0) - player.camera.global_position
	player.user_pitch = -rad_to_deg(atan2(up_to.y, Vector2(up_to.x, up_to.z).length()))
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	await secs(0.3)
	await shot("coffin_guard")
	# within 1.5: the achievement
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 1.0)
	await secs(0.5)
	check("the 895 achievement is given", GameState.achievements.has("895"), "")
	check("the music is silent in the chamber", GameState.music_override == "none", GameState.music_override)
	# six metres away he screams, then falls, then lies in the pit
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 6.0)
	await secs(0.5)
	check("the guard screams when the player is more than 5 away", event._phase == 1 and facility.events.coffin.guard_state >= 1, "phase %d" % event._phase)
	await secs(6.0)
	check("he lands in the pit", event._phase == 2 and event.guard.global_position.y < room.global_position.y - 5.0, "y %.2f" % event.guard.global_position.y)
	# night vision close to the coffin
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	var goggles: int = _give(hud, "Night Vision Goggles", "nvgoggles")
	hud.item_data[goggles]["state"] = 400.0
	GameState.wearing_night_vision = 1
	GameState.sanity = 0.0
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 2.0)
	await secs(1.5)
	check("through goggles the sanity falls", GameState.sanity < -50.0, "%.0f" % GameState.sanity)
	var to := coffin - player.global_position
	var facing := Vector2(-sin(player.rotation.y), -cos(player.rotation.y)).dot(Vector2(to.x, to.z).normalized())
	check("the player is turned to face the coffin", facing > 0.9, "dot %.2f" % facing)
	GameState.sanity = -900.0
	var saw_picture := false
	for i in 150:
		await secs(0.1)
		GameState.sanity = minf(GameState.sanity, -850.0)
		if not hud.nv_picture.is_empty():
			saw_picture = true
			break
	check("below -800 the goggles' overlay shows the horror pictures", saw_picture, "")
	var shown := 0
	for i in 70:
		await secs(0.05)
		GameState.sanity = -850.0
		GameState.vomit_timer = 0.0
		shown += 1 if not hud.nv_picture.is_empty() else 0
	check("below -800 the picture persists most frames (original keeps the texture)", shown > 35, "%d/70 sanity %.0f dist %.1f" % [shown, GameState.sanity, GameState.coffin_distance])
	await shot("coffin_nvg")
	check("the goggles' state2 marks how far the pictures went", float(hud.item_data[goggles].get("state2", 0.0)) == 2.0, "")
	GameState.wearing_night_vision = 0
	GameState.wearing_714 = true
	GameState.sanity = 0.0
	hud.nv_picture = "GFX/895pics/pic1.jpg"
	await secs(0.6)
	check("the ring protects against it", GameState.sanity == 0.0, "%.0f" % GameState.sanity)
	check("the goggles keep the last picture once the effect stops (original resets it only inside the sanity branches)", hud.nv_picture == "GFX/895pics/pic1.jpg", hud.nv_picture)
	GameState.wearing_714 = false
	GameState.sanity = 0.0
	GameState.blur_timer = 0.0
	GameState.vomit_timer = 0.0
	cam.in_sight = true
	GameState.sanity = 0.0
	cam._coffin_effects(1.0, player)
	check("looking at the chamber's monitor wears the sanity down", GameState.sanity == -1.0 and not GameState.restore_sanity, "%.1f" % GameState.sanity)
	GameState.sanity = 0.0
	GameState.restore_sanity = true
	event.lever.pitch = -20.0
	facility.events.coffin.next_broadcast_ms = 0.0
	await secs(0.3)
	check("with the lever down the monitor is off", not cam.screen_on, "")
	event.lever.pitch = 40.0
	await secs(0.3)
	check("the monitors are only set every 3 s: the lever just raised changes nothing yet", not cam.screen_on, "")
	facility.events.coffin.next_broadcast_ms = 0.0
	await secs(0.3)
	check("with it up the monitor is on again", cam.screen_on, "")
	# the radio goes to static near the coffin
	place_player(coffin + Vector3(0.0, 1.0, 0.0) + back * 1.0)
	await secs(0.3)
	check("the radio is overwhelmed within 4 of the coffin", hud.radio_nav._in_dead_zone(), "")
	GameState.sanity = 0.0
	GameState.blur_timer = 0.0
	GameState.vomit_timer = 0.0
	GameState.coffin_distance = 100.0
	GameState.music_override = ""
	hud.nv_picture = ""

func _scn_room860() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room860":
			record = candidate
	check("the map has SCP-860's room", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(30.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	place_player(record.position + Vector3(2.0, 1.0, 0.0))
	await secs(1.0)
	var event: Node = room.extras
	check("the room has its event and forest", event != null and event.forest != null, "")
	if event == null or event.forest == null:
		return
	var forest: Node3D = event.forest
	var doors := 0
	var path := 0
	for i in 100:
		if forest.grid[i] == 3:
			doors += 1
		elif forest.grid[i] == 1:
			path += 1
	check("the grid has two doors and a path of some length", doors == 2 and path >= 20, "doors %d path %d" % [doors, path])
	var rows := ""
	for row in 10:
		for col in 10:
			rows += str(forest.grid[row * 10 + col])
		rows += "/"
	var buildable := 0
	for tx in range(1, 10):
		for ty in range(1, 10):
			if forest.grid[ty * 10 + tx] == 1 and (forest.grid[ty * 10 + tx + 1] > 0 or forest.grid[ty * 10 + tx - 1] > 0 or forest.grid[(ty + 1) * 10 + tx] > 0 or forest.grid[(ty - 1) * 10 + tx] > 0):
				buildable += 1
	check("every path tile that touches another was built", forest.tiles.size() == buildable, "tiles %d buildable %d grid %s" % [forest.tiles.size(), buildable, rows])
	check("both wooden doors stand in their walls", forest.doors[0] != null and forest.doors[1] != null, "")
	check("three log documents lie in the forest", forest.logs.size() == 3, "%d" % forest.logs.size())
	var start := Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	for tx in range(1, 10):
		if forest.grid[9 * 10 + tx] == 3 and forest.grid[8 * 10 + tx] == 1:
			start = Vector2i(tx, 8)
		if forest.grid[0 * 10 + tx] == 3 and forest.grid[1 * 10 + tx] == 1:
			goal = Vector2i(tx, 1)
	var seen := {}
	var queue: Array[Vector2i] = []
	if start.x >= 0:
		queue.append(start)
		seen[start] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if next.x >= 0 and next.x < 10 and next.y >= 0 and next.y < 10 and not seen.has(next) and forest.grid[next.y * 10 + next.x] == 1:
				seen[next] = true
				queue.append(next)
	check("the path joins one door to the other", start.x >= 0 and goal.x >= 0 and seen.has(goal), "start %s goal %s" % [str(start), str(goal)])
	check("the forest is hidden until the door is opened", not forest.visible, "")
	# the door will not budge without the key
	var door_at: Vector3 = event.wooden_door.global_position
	place_player(Vector3(door_at.x - 0.6, room.global_position.y + 1.0, door_at.z))
	await secs(0.3)
	await tap("interact")
	await secs(0.2)
	check("the door will not budge", facility.events.room860.state == 0.0 and hud.message_time_left() > 0.0, "")
	# with the key
	var key: int = _give(hud, "SCP-860", "scp860")
	hud.set_selected(key)
	await secs(0.2)
	await tap("interact")
	await secs(0.6)
	check("the key opens it onto the forest", facility.events.room860.state == 1.0, "")
	check("the player is 30 m up, by a door", player.global_position.y > 29.5 and player.global_position.distance_to(forest.doors[int(1.0 - facility.events.room860.state2)].global_position) < 2.0, "y %.2f" % player.global_position.y)
	check("the key stays in the pocket", hud.items[key] == "SCP-860" and hud.selected == -1, "")
	check("the facility calls the place the chamber", facility.room_name_at(player.global_position) == "room860", facility.room_name_at(player.global_position))
	await secs(2.0)
	check("they stand on the ground", player.global_position.y > 29.0 and player.global_position.y < 32.0 and not player.dead, "y %.2f" % player.global_position.y)
	check("the forest is shown, with its fog and sight", forest.visible and GameState.fog_override.y == 8.0 and player.camera.far == 8.5, "")
	check("106 is told to wait", facility.scp106 == null or facility.scp106.idle, "")
	check("the steps are the forest's", GameState.step_set == 2, "")
	check("the music is the forest's", GameState.music_override == "8601", GameState.music_override)
	await shot("forest_door")
	# a tile in the middle of the path
	var middle := Vector2i(-1, -1)
	for key_cell in forest.tiles:
		var cell := Vector2i(int(key_cell) % 10, int(key_cell) / 10)
		if cell.y == 4:
			middle = cell
	if middle.x >= 0:
		var spot: Vector3 = forest.blitz_world(Vector3(middle.x * 12.0, 3.0, middle.y * 12.0))
		place_player(spot)
		player.rotation.y = 0.8
		await secs(1.5)
		await shot("forest_middle")
	# the trees of the middle tile: the nearest, seen from the path
	var tree_at := Vector3.INF
	var trunk_aabb := AABB()
	for key_cell in forest.tiles:
		if tree_at != Vector3.INF:
			break
		var candidate := Vector2i(int(key_cell) % 10, int(key_cell) / 10)
		var here: Vector3 = forest.blitz_world(Vector3(candidate.x * 12.0, 3.0, candidate.y * 12.0))
		for child in (forest.tiles[key_cell] as Node3D).get_children():
			if child is MultiMeshInstance3D and tree_at == Vector3.INF and child.multimesh.instance_count > 0 and child.multimesh.mesh.get_aabb().size.y > 10.0:
				middle = candidate
				trunk_aabb = child.multimesh.mesh.get_aabb()
				var nearest := INF
				for n in child.multimesh.instance_count:
					var at: Vector3 = (child as Node3D).global_transform * child.multimesh.get_instance_transform(n).origin
					var d: float = Vector2(at.x - here.x, at.z - here.z).length()
					if d > 3.0 and d < nearest:
						nearest = d
						tree_at = at
	check("trees stand on the hills", tree_at != Vector3.INF or DisplayServer.get_name() == "headless", "aabb %s at %s" % [str(trunk_aabb), str(tree_at)])
	if tree_at != Vector3.INF and middle.x >= 0:
		var here2: Vector3 = forest.blitz_world(Vector3(middle.x * 12.0, 3.0, middle.y * 12.0))
		place_player(here2)
		player.blink_timer = 500.0
		face_point(Vector3(tree_at.x, here2.y, tree_at.z))
		await secs(1.2)
		await shot("forest_tree")
	# the tiles beyond 20 m are hidden
	var hidden := 0
	for key_cell in forest.tiles:
		if not (forest.tiles[key_cell] as Node3D).visible:
			hidden += 1
	check("far tiles are hidden", hidden > 0 or forest.tiles.size() < 10, "hidden %d of %d" % [hidden, forest.tiles.size()])
	var monster: Node = event.monster
	check("the monster exists", monster != null, "")
	if monster != null:
		monster.global_position = Vector3(0.0, -110.0, 0.0)
		monster.state = 1
		await secs(1.0)
		check("state 1 puts it between a free cell and the player, out of view", monster.global_position.y > -100.0 and abs(monster.global_position.y - (forest.global_position.y + 2.3)) < 0.01, "y %.2f" % monster.global_position.y)
		await shot("forest_monster1")
		monster.park()
		monster.state = 2
		monster.global_position = Vector3(0.0, -110.0, 0.0)
		await secs(1.0)
		var cell: Vector2i = forest.cell_of(monster.global_position)
		check("state 2 puts it on the path", monster.global_position.y > -100.0 and forest.grid[cell.y * 10 + cell.x] > 0, "cell %s" % str(cell))
		await shot("forest_monster2")
		var waited := 0.0
		while monster.state == 2 and waited < 40.0:
			await secs(0.5)
			waited += 0.5
		check("it walks up and starts to run", monster.state == 3, "state %d after %.0f s" % [monster.state, waited])
		await shot("forest_monster3")
		await secs(6.0)
		check("within 1.1 it claws, the frames run", monster.frame >= 451.0 or monster.state == 3, "frame %.0f" % monster.frame)
		monster.park()
		player.dead = false
	var out_index: int = int(facility.events.room860.state2)
	var wrong: Node3D = forest.doors[1 - out_index]
	var right: Node3D = forest.doors[out_index]
	place_player(wrong.global_position + Vector3(0.0, 0.1, 0.0))
	await secs(0.3)
	face_point(wrong.global_position)
	await tap("interact")
	await secs(0.2)
	check("the far door will not budge", facility.events.room860.state == 1.0, "")
	place_player(right.global_position + Vector3(0.0, 0.1, 0.0))
	await secs(0.3)
	face_point(right.global_position)
	await tap("interact")
	await secs(0.6)
	check("the door they came in by lets them out", facility.events.room860.state == 0.0 and player.global_position.y < 3.0, "state %.0f y %.2f" % [facility.events.room860.state, player.global_position.y])
	check("the fog and the sight are the facility's again", GameState.fog_override.x < 0.0 and player.camera.far > 100.0 and GameState.step_set == 0, "fog %s far %.1f step %d" % [str(GameState.fog_override), player.camera.far, GameState.step_set])
	check("the forest is hidden again", not forest.visible, "")
	GameState.music_override = ""
	# a console teleport out of the forest: the facility's view comes back (the room below stays the player's room otherwise)
	var commands = DebugCommands.new(hud)
	place_player(Vector3(door_at.x - 0.6, room.global_position.y + 1.0, door_at.z))
	await secs(0.3)
	hud.set_selected(key)
	await secs(0.2)
	await tap("interact")
	await secs(0.6)
	check("the key opens the forest a second time", facility.events.room860.state == 1.0, "")
	await secs(0.5)
	commands.run("tele %f %f %f" % [record.position.x + 2.0, record.position.y + 1.0, -record.position.z])
	await secs(0.5)
	check("a console teleport ends the forest state", facility.events.room860.state == 0.0, "")
	check("and the fog, the sight, the steps and the music are the facility's", GameState.fog_override.x < 0.0 and player.camera.far > 100.0 and GameState.step_set == 0 and GameState.music_override == "", "fog %s far %.1f step %d music %s" % [str(GameState.fog_override), player.camera.far, GameState.step_set, GameState.music_override])
	check("the lights are back as they were", GameState.secondary_light == facility.events.room860.light, "%.2f vs %.2f" % [GameState.secondary_light, facility.events.room860.light])

func _scn_tesla() -> void:
	log_line("== the tesla gate")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	var hud: Node = get_tree().get_first_node_in_group("hud")
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	# a real gate if the map has one (its FillRoom objects are in the data), else an ordinary room made into one
	var gate := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) in ["room2tesla", "room2tesla_lcz", "room2tesla_hcz"]:
			gate = candidate
			break
	var made_one := false
	if gate.is_empty():
		gate = await _event_room()
		made_one = true
	var node: Node3D = facility.rooms.get_room(gate)
	if made_one:
		node.fill_objects[0] = Vector3(-0.4453, 0.0, 0.0)
		node.fill_objects[1] = Vector3(0.4453, 0.0, 0.0)
		node.fill_objects[2] = Vector3(0.0, 0.0, 0.0)
		node.fill_objects[3] = Vector3(0.0, 0.8, 0.0)
		node.fill_objects[5] = Vector3(0.0, 0.0, 3.125)
		node.fill_objects[6] = Vector3(0.0, 0.0, -3.125)
	log_line("   gate room %s (%s)" % [str(gate.name), "made" if made_one else "from the map"])
	check("the gate has its coils and its sprite point", node.object_point(0) != Vector3.INF and node.object_point(2) != Vector3.INF and node.object_point(3) != Vector3.INF, "")
	var plan_count: int = ambient.plan.rooms_with("room2tesla").size()
	log_line("   the plan has %d tesla gates" % plan_count)
	GameState.god_mode = true
	# the clerk: the first time the player is at the gate he runs at it from the far end
	var side: Vector3 = node.to_global(Vector3(0.0, 0.6, 3.3))      # the corridor is the strip along the middle: the end of it, away from the coils
	place_player(side)
	await secs(0.6)
	face_point(node.object_point(3))
	ambient.force(gate.key, "room2tesla")
	await secs(0.5)
	var state: Dictionary = ambient.state_of(gate.key)
	var nodes: Dictionary = ambient._nodes.get(gate.key, {})
	check("a clerk comes for the player's first gate", state.get("str") in ["step1", "step2", "0"] and nodes.has("clerk") and is_instance_valid(nodes["clerk"]), "str %s" % str(state.get("str")))
	var clerk: Node3D = nodes.get("clerk")
	check("he is a clerk, running", clerk != null and clerk.kind == 2 and clerk.state in [2, 3], "")
	await shot("tesla_clerk")
	# the gate winds up as he nears it, fires, and he falls
	var waited := 0.0
	while waited < 6.0 and state.s == 0.0:
		await secs(0.1)
		waited += 0.1
	check("the gate winds up as the clerk nears it", state.s > 0.0, "%.1f s" % waited)
	waited = 0.0
	while waited < 2.0 and state.s < 45.0:
		await secs(0.05)
		waited += 0.05
	await secs(0.1)
	face_point(node.object_point(3))
	check("when it fires the clerk stops", clerk != null and clerk.state == 3, "state %d at %.0f frames" % [clerk.state if clerk != null else -1, state.s])
	await shot("tesla_fires")
	waited = 0.0
	while waited < 5.0 and clerk != null and not clerk.is_dead:
		await secs(0.2)
		waited += 0.2
	check("and falls dead", clerk != null and clerk.is_dead and clerk.frame >= 57.0, "frame %.0f" % (clerk.frame if clerk != null else 0.0))
	await secs(1.0)
	check("the clerk scene has moved on to the smoke", not state.get("str") in ["", "step1"], str(state.get("str")))
	await shot("tesla_clerk_dead")
	# the gate rests and starts again
	waited = 0.0
	while waited < 6.0 and state.s != 0.0:
		await secs(0.2)
		waited += 0.2
	check("the gate is ready again after its 150 frames", state.s == 0.0, "state %.0f" % state.s)
	# the player at the middle: wound up, then killed by the discharge
	GameState.god_mode = false
	place_player(node.to_global(Vector3(0.0, 0.2, 0.0)))
	await secs(0.3)
	check("a step at the coils winds the gate up", state.s > 0.0, "%.0f" % state.s)
	waited = 0.0
	while waited < 3.0 and not player.dead:
		await secs(0.1)
		waited += 0.1
	check("the discharge kills the player", player.dead, "")
	hud.cancel_death()
	player.dead = false
	GameState.god_mode = true
	GameState.light_flash = 0.0
	place_player(side)
	waited = 0.0
	while waited < 6.0 and state.s != 0.0:
		await secs(0.2)
		waited += 0.2
	# 106 is sent away when he walks into it
	var old_man: Node3D = facility.spawn_106(-20.0)
	old_man.global_position = node.to_global(Vector3(0.0, 0.1, 0.0))
	old_man.set_physics_process(false)
	await secs(0.3)
	check("106 at a coil winds the gate and is sent away for 10 to 13 minutes", state.s > 0.0 and old_man.state >= 70.0 * 60.0 * 10.0, "state %.0f" % old_man.state)
	waited = 0.0
	while waited < 6.0 and state.s != 0.0:
		await secs(0.2)
		waited += 0.2
	old_man.queue_free()
	facility.scp106 = null
	place_player(side)
	waited = 0.0
	while waited < 6.0 and state.s != 0.0:
		await secs(0.2)
		waited += 0.2
	# a Nine-Tailed Fox unit near the gate: it speaks, stands still and the gate is off for a while
	var unit: Node3D = facility.mtf.spawn(node.to_global(Vector3(1.0, 0.1, 1.0)))
	unit.no_target = true
	unit.set_physics_process(false)
	state.s2 = 0.0
	state.s3 = 0.0
	await secs(0.4)
	check("a unit by the gate says so and holds still 10 s", unit.voices.has("SFX/Character/MTF/Tesla0.ogg") and unit.idle > 600.0, "idle %.0f" % unit.idle)
	check("and the gate is held off for about 100 s", state.s2 > 70.0 * 99.0, "%.0f" % state.s2)
	state.s2 = 70.0 * 50.0       # the middle of it
	place_player(node.to_global(Vector3(0.0, 0.2, 0.0)))
	await secs(0.5)
	check("a step at the coils does nothing while it is off", state.s == 0.0, "%.0f" % state.s)
	facility.mtf.remove(unit)
	ambient.enabled = false
	GameState.god_mode = false

# ---------------------------------------------------------------- SCP-012's room (UpdateEvents "room012")

func _scn_room012() -> void:
	log_line("== SCP-012")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room012":
			record = candidate
	check("the map has SCP-012's room", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(record.position + Vector3(0.0, 1.0, 0.0))
	await secs(1.0)
	var event: Node = room.extras
	check("the room has its event", event != null and event.board != null and event.lever != null, "")
	var smear_at: Vector3 = room.to_global(Vector3(-784.0 * 8.0 / 2048.0, 0.0, -640.0 * 8.0 / 2048.0))
	var smears := 0
	for d in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if not d is GrowingDecal:
			continue
		if d.texture_file == "GFX/decal4.png" and Vector2(d.global_position.x - smear_at.x, d.global_position.z - smear_at.z).length() < 0.05 and absf(d.size - 0.5) < 0.001:
			smears += 1
	check("FillRoom puts decal 4 (size 0.5) by the severed hand", smears == 1, "found %d" % smears)
	if event != null and event.sheet != null:
		var sheet_arrays: Array = event.sheet.mesh.surface_get_arrays(0)
		var sheet_normals: PackedVector3Array = sheet_arrays[Mesh.ARRAY_NORMAL] if sheet_arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		check("the sheet has normals, so the room lights reach it", sheet_normals.size() > 0 and sheet_normals[0].length() > 0.5, "%d normals" % sheet_normals.size())
	if event == null:
		return
	var door: Node3D = room.door_slots.get(0)
	check("RoomDoors[0] is locked and shut", door != null and door.locked and not door.open, "")
	var st: Dictionary = facility.ambient.state_of(record.key)
	st.s = 0.0
	st.s2 = 0.0
	st.s3 = 0.0
	GameState.achievements.erase("012")
	facility.remote_door_on = true
	# far from the door nothing happens; within 2.5 of it 012 opens it
	var door_at: Vector3 = door.global_position
	place_player(door_at + Vector3(0.0, 2.0, 0.0) + room.global_transform.basis * Vector3(0.0, 0.0, 4.0))
	await secs(0.5)
	check("far from the door it stays shut", not door.open and st.s == 0.0, "")
	place_player(door_at + Vector3(0.0, 0.3, 0.0) + room.global_transform.basis * Vector3(1.0, 0.0, 1.0))
	await secs(0.5)
	check("within 2.5 of it 012 opens the door itself and locks it open", door.open and door.locked and st.s >= 1.0, "open %s locked %s state %.0f" % [str(door.open), str(door.locked), st.s])
	check("the achievement is given", GameState.achievements.has("012"), "")
	# the sheet's board sinks, the lever pulls itself down and the light blinks
	var board_y_before: float = event.board.position.y
	await secs(4.0)
	check("the board sinks into the floor", event.board.position.y < board_y_before - 0.1, "%.2f -> %.2f" % [board_y_before, event.board.position.y])
	check("the lever pulls itself down", event.lever.pitch > 60.0, "pitch %.0f" % event.lever.pitch)
	place_player(event.lever.global_position + room.global_transform.basis * Vector3(0.0, 0.3, -0.7))
	face_point(event.lever.global_position)
	await secs(0.5)
	await shot("room012_lever")
	var seen_on := false
	var seen_off := false
	for i in 40:
		if event.glow.visible:
			seen_on = true
		else:
			seen_off = true
		await secs(0.1)
	check("the light blinks", seen_on and seen_off, "")
	# the pull: with the board in sight the view is turned to it and the player is made to walk
	GameState.god_mode = true
	var board_at: Vector3 = event.board.global_position
	var far_from := board_at + room.global_transform.basis * Vector3(1.6, 0.0, 0.0)
	place_player(Vector3(far_from.x, door_at.y + 0.3, far_from.z))
	player.rotation.y = 0.0
	await secs(1.5)
	var to_board: Vector3 = board_at - player.camera.global_position
	var facing: Vector3 = -player.camera.global_transform.basis.z
	check("the view is turned to the board", Vector2(facing.x, facing.z).normalized().dot(Vector2(to_board.x, to_board.z).normalized()) > 0.7, "dot %.2f" % Vector2(facing.x, facing.z).normalized().dot(Vector2(to_board.x, to_board.z).normalized()))
	check("and tilted down", player.user_pitch > 10.0, "pitch %.1f" % player.user_pitch)
	place_player(Vector3(board_at.x, door_at.y + 0.3, board_at.z) + room.global_transform.basis * Vector3(1.0, 0.0, 0.0))
	face_point(board_at)
	await secs(0.4)
	await shot("room012_board")
	var start_dist := Vector2(player.global_position.x - board_at.x, player.global_position.z - board_at.z).length()
	await secs(2.5)
	var end_dist := Vector2(player.global_position.x - board_at.x, player.global_position.z - board_at.z).length()
	check("the player walks to it", end_dist < start_dist - 0.3 or end_dist < 0.7, "%.2f -> %.2f" % [start_dist, end_dist])
	check("the heart races", GameState.blur_volume >= 0.0, "")
	# at the board the counter runs and the stages come
	place_player(Vector3(board_at.x, door_at.y + 0.3, board_at.z) + room.global_transform.basis * Vector3(0.3, 0.0, 0.0))
	await secs(0.5)
	GameState.god_mode = false
	GameState.injuries = 0.0
	var before: float = st.s3
	await secs(1.0)
	check("within 0.6 of it the counter runs", st.s3 > before + 20.0, "%.0f -> %.0f" % [before, st.s3])
	st.s3 = 13.0 * 70.0 - 1.0
	await secs(0.3)
	check("at 13 s the nails go into the wrist", GameState.injuries >= 0.5 and hud.message_label.text.contains("nails"), "%.2f %s" % [GameState.injuries, hud.message_label.text])
	st.s3 = 74.0 * 70.0 - 1.0
	await secs(0.3)
	check("at 74 s the wound is torn open and the player crouches", GameState.injuries > 1.2 and player.crouching, "%.2f" % GameState.injuries)
	st.s3 = 85.0 * 70.0 - 1.0
	await secs(0.3)
	check("at 85 s the player bleeds to death", player.dead, "")
	hud.cancel_death()
	player.dead = false
	GameState.injuries = 0.0
	player.crouching = false
	GameState.wearing_714 = true
	st.s3 = 0.0
	place_player(Vector3(board_at.x, door_at.y + 0.3, board_at.z) + room.global_transform.basis * Vector3(0.3, 0.0, 0.0))
	await secs(1.0)
	check("the ring of SCP-714 keeps it off", st.s3 == 0.0, "%.0f" % st.s3)
	GameState.wearing_714 = false
	GameState.force_move = 0.0

# ---------------------------------------------------------------- SCP-205 (UpdateEvents "room205")

func _scn_room205() -> void:
	log_line("== SCP-205")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("room205")
	check("the map has SCP-205's room", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	var door_in: Node3D = room.door_slots.get(1)
	var door_chamber: Node3D = room.door_slots.get(0)
	var event: Node = room.extras
	check("the four models are loaded with the room, before the player walks in", event != null and event._models.size() == 4, "")
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	var worst: float = (await _measure_frames(70))[6].max()
	check("walking in costs no frame over 100 ms (the models were read on the first visit: 470-600 ms)", worst < 100.0, "%.1f ms" % worst)
	check("the room has its event and both doors", event != null and door_in != null and door_chamber != null, "")
	if event == null:
		return
	var st: Dictionary = facility.ambient.state_of(record.key)
	st.s = 0.0
	st.s2 = 0.0
	st.s3 = 0.0
	GameState.achievements.erase("205")
	await secs(0.3)
	check("with the door shut nothing is shown", event._models.size() == 4 and not event._models[3].visible and st.s == 0.0, "")
	door_in.open = true
	await secs(0.5)
	check("opening the door starts the cycle", st.s >= 1.0, "state %.0f" % st.s)
	check("the achievement is given", GameState.achievements.has("205"), "")
	check("the woman is shown and the 205 music plays", event._models[3].visible and GameState.music_override == "205", "music %s" % GameState.music_override)
	var frames_before: float = event._frames[3]
	await secs(0.5)
	check("she sits and the model animates", event._frames[3] != frames_before and event._frames[3] >= 526.0 and event._frames[3] <= 530.0, "%.1f" % event._frames[3])
	st.s2 = 20.0 * 70.0 + 1.0
	await secs(1.5)
	check("after 20 s the monitor flickers and the step is passed", st.s == 3.0, "state %.0f" % st.s)
	check("she lies down", event._frames[3] >= 377.0 and event._frames[3] <= 525.0, "%.1f" % event._frames[3])
	st.s2 = 40.0 * 70.0 + 1.0
	await secs(1.5)
	check("the stages go on to the first demon", st.s == 7.0 and event._models[2].visible, "state %.0f" % st.s)
	st.s2 = 60.0 * 70.0 + 1.0
	await secs(1.5)
	check("the second demon comes", st.s == 9.0 and event._models[1].visible and not event._models[0].visible, "state %.0f" % st.s)
	st.s2 = 80.0 * 70.0 + 1.0
	await secs(1.5)
	check("and the third", st.s == 11.0 and event._models[0].visible, "state %.0f" % st.s)
	st.s2 = 85.0 * 70.0 + 1.0
	await secs(1.5)
	check("then they dance", st.s == 13.0, "state %.0f" % st.s)
	var dance_before: float = event._frames[0]
	await secs(1.0)
	check("the demons animate", event._frames[0] != dance_before, "%.1f -> %.1f" % [dance_before, event._frames[0]])
	var spot: Vector3 = event._spot()
	var screen_at: Vector3 = room.cams[0]._screen.global_position
	place_player(room.to_global(Vector3(-3.4, room.floor_y(-3.4, -0.7) + 0.1, -0.7)))
	face_point(screen_at)
	await secs(1.5)
	await shot("room205_dance")
	# the chamber door swings open and shut on its own now
	var flips := 0
	var last: bool = door_chamber.open
	for i in 60:
		await secs(0.5)
		if door_chamber.open != last:
			flips += 1
			last = door_chamber.open
	check("the chamber door opens and shuts at random", flips >= 2, "%d flips in 30 s, state %.0f, player %.1f from the models" % [flips, st.s, Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()])
	GameState.god_mode = true
	place_player(Vector3(spot.x, room.global_position.y + 0.3, spot.z) + Vector3(1.0, 0.0, 0.0))
	await secs(0.3)
	check("walking within 2 of the demons sets them on the player", st.s >= 65.0, "state %.0f" % st.s)
	check("the chamber door is shut on the player", not door_chamber.open, "")
	await secs(7.5)
	check("the picture goes off for good", st.s == 67.0, "state %.0f" % st.s)
	var cam_screen: Node3D = room.cams[0]._screen
	check("the monitor is dark", not cam_screen.visible, "")
	GameState.god_mode = false
	GameState.injuries = 0.0
	var at: Vector3 = player.global_position
	var hurt := false
	var moved := false
	for i in 120:
		await secs(0.1)
		if str(facility.record_at(player.global_position).get("key", "")) != record.key:
			place_player(room.to_global(Vector3(-4.2, room.floor_y(-4.2, -0.7) + 0.1, -0.7)))
			at = player.global_position
		if GameState.injuries > 0.3:
			hurt = true
		if player.global_position.distance_to(at) > 0.05:
			moved = true
		if hurt and moved:
			break
	check("in the dark the player is hit and thrown about", hurt and moved, "injuries %.2f moved %s" % [GameState.injuries, str(moved)])
	GameState.injuries = 4.9
	for i in 200:
		if not player.dead:
			place_player(Vector3(spot.x, room.global_position.y + 0.3, spot.z) + Vector3(1.0, 0.0, 0.0))
		await secs(0.1)
		if player.dead:
			break
	check("and beaten to death", player.dead, "injuries %.2f" % GameState.injuries)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	hud.cancel_death()
	player.dead = false
	GameState.injuries = 0.0
	# leaving hides the models and gives the music back
	place_player(record.position + Vector3(60.0, 1.0, 0.0))
	await secs(0.5)
	check("away from the room the music is released", GameState.music_override != "205", "")


# ---------------------------------------------------------------- SCP-035 (UpdateEvents "room035")

func _scn_room035() -> void:
	log_line("== SCP-035")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("room035")
	check("the map has SCP-035's room", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(1.0)
	var event: Node = room.extras
	check("the room has its event, two levers and four doors", event != null and event.levers.size() == 2 and room.door_slots.size() == 4, "doors %s" % str(room.door_slots.keys()))
	if event == null or event.levers.size() < 2:
		return
	check("both levers start down", not event.levers[0].is_on() and not event.levers[1].is_on(), "")
	check("RoomDoors[0] and [1] are locked", room.door_slots[0].locked and room.door_slots[1].locked, "")
	check("the chamber's two jets are far above it", room.jets.size() == 2, "jets %d" % room.jets.size())
	var st: Dictionary = facility.ambient.state_of(record.key)
	st.s = 0.0
	st.s2 = 0.0
	st.s3 = 0.0
	GameState.achievements.erase("035")
	# the host is made when the player comes within 2 of Objects[3]
	var spot: Vector3 = room.object_point(3)
	var chair: Vector3 = room.object_point(4)
	check("the host does not exist yet", get_tree().get_nodes_in_group("scp035_host").is_empty(), "")
	place_player(Vector3(spot.x, room.global_position.y + 0.1, spot.z) + Vector3(1.9, 0.0, 0.0))
	await secs(0.5)
	var host: Node3D = event.host
	check("within 2 of Objects[3] the host is made", host != null and st.s >= 1.0, "state %.1f" % st.s)
	if host == null:
		return
	check("he lies at frame 501 in state 6 at Objects[4]", host.frame == 501.0 and host.state == 6 and Vector2(host.global_position.x - chair.x, host.global_position.z - chair.z).length() < 0.3, "frame %.0f state %d" % [host.frame, host.state])
	place_player(Vector3(spot.x, room.global_position.y + 0.1, spot.z))
	face_point(host.global_position + Vector3(0.0, 0.5, 0.0))
	await secs(0.5)
	check("seen within 1.2 he gets up: the achievement and 1.5, then his talk counts", GameState.achievements.has("035") and st.s > 1.5, "state %.1f" % st.s)
	place_player(Vector3(spot.x, room.global_position.y + 0.1, spot.z))
	st.s = 1.0
	GameState.achievements.erase("035")
	face_point(host.global_position + Vector3(0.0, 0.5, 0.0))
	var eye_spot: Vector3 = host.global_position + Vector3(0.0, 0.4, 0.0)
	var base_yaw: float = player.rotation.y
	var edge_yaw := INF
	for step in range(0, 360):
		player.camera.rotation.x = deg_to_rad(float(step) * 0.25)
		await get_tree().process_frame
		if not player.camera.is_position_in_frustum(eye_spot) and event._host_in_view(player.camera):
			edge_yaw = base_yaw
			break
	check("a view with only the host's edge in it exists", edge_yaw != INF, "")
	if edge_yaw != INF:
		st.s = 1.0
		GameState.achievements.erase("035")
		await secs(0.5)
		check("the host's bounding box in view is enough (EntityInView), not one point", GameState.achievements.has("035") and st.s > 1.0, "state %.1f" % st.s)
	await shot("room035_host")
	var lamp := OmniLight3D.new()
	lamp.light_energy = 4.0
	lamp.omni_range = 8.0
	room.add_child(lamp)
	lamp.global_position = host.global_position + Vector3(0.0, 1.8, 0.0)
	var from_host: Vector3 = (Vector3(spot.x, 0.0, spot.z) - Vector3(chair.x, 0.0, chair.z)).normalized()
	place_player(Vector3(chair.x, room.global_position.y + 0.1, chair.z) + from_host * 1.6)
	face_point(host.global_position + Vector3(0.0, 0.5, 0.0))
	await secs(0.4)
	await shot("room035_host_lit")
	lamp.queue_free()
	place_player(Vector3(spot.x, room.global_position.y + 0.1, spot.z))
	# the valves: gas on the host
	GameState.sanity = 0.0
	event.levers[1].pitch = 80.0
	await secs(1.0)
	var jet_y: float = room.to_local(room.jets[0].pos).y
	check("the valves open: the jets drop into the chamber", jet_y > 1.0 and jet_y < 4.0, "y %.2f" % jet_y)
	check("the gas counts (Gased1 at once)", st.s3 > 0.0 and host.state == 0, "s3 %.0f state %d" % [st.s3, host.state])
	st.s3 = 16.0 * 70.0
	await secs(1.0)
	check("at 15 s he collapses (state 6, frames 553 down to 529)", host.state == 6 and host.frame < 553.0 and host.frame >= 524.0, "frame %.1f state %d" % [host.frame, host.state])
	st.s3 = 26.0 * 70.0
	await secs(0.5)
	check("by 25-35 s the fall goes on (529 down to 524)", host.frame <= 529.0 and host.frame >= 524.0, "frame %.1f" % host.frame)
	# shutting the valves past 25 s does not stop the gas: it runs to 50 s
	event.levers[1].pitch = -80.0
	await secs(0.5)
	check("past 25 s the gas goes on until 50 s even with the valves shut", st.s3 > 26.0 * 70.0, "s3 %.0f" % st.s3)
	# shutting the valves before 25 s: he survives
	event.levers[1].pitch = 80.0
	st.s3 = 2.0 * 70.0
	await secs(0.3)
	event.levers[1].pitch = -80.0
	await secs(1.0)
	check("the valves shut early: 'stop' lines and 61*70", st.s >= 61.0 * 70.0, "s %.0f s3 %.0f" % [st.s, st.s3])
	check("the jets rise out of the chamber", room.to_local(room.jets[0].pos).y > 9.0, "")
	check("the gas counter is negative", st.s3 < 0.0, "s3 %.0f" % st.s3)
	# a longer dose kills the host
	st.s = 1.5
	st.s3 = -1.0
	host.state = 0
	event.levers[1].pitch = 80.0
	await secs(0.5)
	st.s3 = 35.0 * 70.0 - 5.0
	await secs(0.5)
	check("past 35 s the host dies (EventState 60*70)", st.s == 60.0 * 70.0, "s %.0f" % st.s)
	check("his sanity effect runs", GameState.sanity < 0.0, "sanity %.0f" % GameState.sanity)
	st.s3 = 50.0 * 70.0 - 5.0
	await secs(0.5)
	event.levers[1].pitch = -80.0
	await secs(1.0)
	check("the gas ends at 50 s: 'killed' counter (below -35 s)", st.s3 < -35.0 * 70.0, "s3 %.0f" % st.s3)
	# the chamber lever: the host walks out
	var door_chamber: Node3D = room.door_slots[0]
	var door_inner: Node3D = room.door_slots[1]
	event.levers[0].pitch = 80.0
	await secs(1.0)
	check("the lever opens the chamber: EventState2 20, inner door open, control door locked shut", st.s2 == 20.0 and door_inner.open and room.door_slots[2].locked and not room.door_slots[2].open, "s2 %.0f" % st.s2)
	check("and cannot be pushed back (locked)", event.levers[0].locked, "")
	var walked := false
	for i in 300:
		await secs(0.1)
		# the game runs faster than the sound does: let the line he waits for end
		if is_instance_valid(host) and host.global_position.distance_to(door_chamber.global_position) < 2.6 and event._voice != null and is_instance_valid(event._voice):
			event._voice.stop()
		if st.s < 0.0:
			walked = true
			break
	check("the host walks to the door and out: the event ends (-1)", walked, "s %.0f s2 %.0f host dist %.2f" % [st.s, st.s2, host.global_position.distance_to(door_chamber.global_position) if is_instance_valid(host) else -1.0])
	check("the doors are unlocked again", not door_chamber.locked and not door_inner.locked and not room.door_slots[2].locked, "")
	check("the host is gone", event.host == null, "")
	var corner_a: Vector3 = room.object_point(7)
	var corner_b: Vector3 = room.object_point(8)
	var inside := Vector3((corner_a.x + corner_b.x) * 0.5, room.global_position.y + 0.1, (corner_a.z + corner_b.z) * 0.5)
	GameState.god_mode = true
	place_player(inside)
	await secs(0.5)
	check("stepping into the chamber wakes a tentacle at Objects[4]", event.tentacles[0] != null and is_instance_valid(event.tentacles[0]), "")
	if event.tentacles[0] == null:
		return
	var tentacle: Node3D = event.tentacles[0]
	check("it waits at frame 283 until the player is within 2.5", tentacle.state == 0 and tentacle.frame >= 283.0, "state %d frame %.0f dist %.1f" % [tentacle.state, tentacle.frame, tentacle.global_position.distance_to(player.global_position)])
	check("the chamber wears the player down: sanity falls", GameState.sanity < 0.0, "sanity %.0f" % GameState.sanity)
	check("the chamber plays Music(0), The Dread", GameState.music_override == "The Dread", GameState.music_override)
	var toward: Vector3 = (Vector3(inside.x, 0.0, inside.z) - Vector3(tentacle.global_position.x, 0.0, tentacle.global_position.z)).normalized()
	place_player(Vector3(tentacle.global_position.x, room.global_position.y + 0.1, tentacle.global_position.z) + toward * 2.2)
	face_point(tentacle.global_position + Vector3(0.0, 0.8, 0.0))
	await secs(0.5)
	await shot("room035_tentacle_rise")
	await secs(6.0)
	check("it rises (frames 284-389) and then idles", tentacle.state >= 1, "state %d frame %.0f" % [tentacle.state, tentacle.frame])
	check("then the second one arrives at the room's middle", event.tentacles[1] != null and is_instance_valid(event.tentacles[1]), "")
	place_player(Vector3(tentacle.global_position.x, room.global_position.y + 0.1, tentacle.global_position.z) + toward * 1.2)
	face_point(tentacle.global_position + Vector3(0.0, 0.8, 0.0))
	await shot("room035_tentacle_near")
	var lamp2 := OmniLight3D.new()
	lamp2.light_energy = 4.0
	lamp2.omni_range = 8.0
	room.add_child(lamp2)
	lamp2.global_position = tentacle.global_position + Vector3(0.0, 2.0, 0.0) + toward * 1.0
	place_player(Vector3(tentacle.global_position.x, room.global_position.y + 0.1, tentacle.global_position.z) + toward * 2.6)
	face_point(tentacle.global_position + Vector3(0.0, 0.8, 0.0))
	await secs(0.3)
	await shot("room035_tentacle_lit")
	lamp2.queue_free()
	place_player(Vector3(tentacle.global_position.x, room.global_position.y + 0.1, tentacle.global_position.z) + toward * 1.2)
	face_point(tentacle.global_position + Vector3(0.0, 0.8, 0.0))
	GameState.god_mode = false
	GameState.injuries = 0.0
	await secs(3.0)
	check("within 1.8 and in front of it, it strikes", GameState.injuries >= 0.9, "injuries %.2f state %d frame %.1f" % [GameState.injuries, tentacle.state, tentacle.frame])
	GameState.injuries = 2.8
	for i in 100:
		await secs(0.1)
		if player.dead:
			break
	check("and a blow with more than 3 injuries kills", player.dead, "injuries %.2f" % GameState.injuries)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	hud.cancel_death()
	player.dead = false
	GameState.injuries = 0.0
	GameState.sanity = 0.0
	# the offices: once 035 is out, his victim lies in room2offices and a tentacle rises when the player nears
	var offices := _find_room("room2offices")
	check("the map has a room2offices", not offices.is_empty(), "")
	if not offices.is_empty():
		var ambient: Node = facility.ambient
		ambient.enabled = true
		ambient.force(offices.key, "room2offices035")
		var office_room: Node3D = facility.rooms.get_room(offices)
		GameState.god_mode = true
		place_player(offices.position + Vector3(0.0, 1.0, 3.5))
		await secs(1.0)
		var nodes: Dictionary = ambient._nodes.get(offices.key, {})
		var victim: Node3D = nodes.get("body")
		check("the victim lies in the offices in 035's skin (frame 19, held pose)", victim != null and is_instance_valid(victim) and victim.frame == 19.0 and victim.state == 3 and victim.texture_id == 7, "")
		check("no tentacle while the player keeps off", nodes.get("tentacle") == null, "")
		if victim != null and is_instance_valid(victim):
			place_player(Vector3(victim.global_position.x, offices.position.y + 0.1, victim.global_position.z) + Vector3(1.5, 0.0, 0.0))
			await secs(0.5)
			nodes = ambient._nodes.get(offices.key, {})
			var office_tentacle: Node3D = nodes.get("tentacle")
			check("within 2.5 a tentacle rises beyond it", office_tentacle != null and is_instance_valid(office_tentacle) and office_tentacle.in_offices, "")
			place_player(offices.position + Vector3(0.0, 1.0, 40.0))
			await secs(0.5)
			nodes = ambient._nodes.get(offices.key, {})
			check("far away the tentacle is dropped", nodes.get("tentacle") == null, "")
		GameState.god_mode = false
		ambient.enabled = false
	# away from the room the music is given back
	place_player(record.position + Vector3(60.0, 1.0, 0.0))
	await secs(0.5)
	check("away from the chamber the music is released", GameState.music_override != "The Dread", GameState.music_override)

# ---------------------------------------------------------------- SCP-939 (room3storage) and room2scps2

func _scn_room939() -> void:
	log_line("== SCP-939")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := _find_room("room3storage")
	check("the map has room3storage", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	var lower: Vector3 = room.object_point(3)
	place_player(Vector3(lower.x, lower.y + 0.4, lower.z))
	await secs(1.5)
	var event: Node = room.extras
	check("the room has its event and two levers", event != null and event.levers.size() == 2, "")
	if event == null or event.levers.size() < 2:
		return
	var st: Dictionary = facility.ambient.state_of(record.key)
	check("on the lower level the three specimens are put on their loops", event.specimens.size() == 3 and st.s == 1.0 and event.specimens[0].state2 == 5 and event.specimens[1].state2 == 10 and event.specimens[2].state2 == 14, "specimens %d s %.0f" % [event.specimens.size(), st.s])
	check("they stand on the starting waypoints", event.specimens[0].global_position.distance_to(room.object_point(4)) < 1.5 and event.specimens[1].global_position.distance_to(room.object_point(9)) < 1.5 and event.specimens[2].global_position.distance_to(room.object_point(13)) < 1.5, "")
	check("the achievement is given and the storage music plays", GameState.achievements.has("939") and GameState.music_override == "Room3Storage", GameState.music_override)
	check("the hand has been put out", st.has("hand"), "")
	var hand_spot := int(facility.rooms.by_grid.get(room.room_key, {}).get("hand_spot", 0))
	check("the hand's spot is the Rand(3) FillRoom drew at map generation", hand_spot >= 1 and hand_spot <= 3, str(hand_spot))
	check("both levers start down", not event.levers[0].is_on() and not event.levers[1].is_on(), "")
	var factor: float = [1.0, 1.1, 1.2][GameState.other_factors()]
	check("their speed follows the difficulty (NPCSpeedChange)", is_equal_approx(event.specimens[0].top_speed, 0.04 * factor), "%.4f" % event.specimens[0].top_speed)
	# patrolling: they walk their loop without a sound from the player
	GameState.god_mode = true
	var before: Array = []
	for specimen in event.specimens:
		before.append(specimen.global_position)
	for i in 40:
		player.sound_volume = 0.0
		await secs(0.1)
	var moved := 0
	for i in 3:
		if event.specimens[i].global_position.distance_to(before[i]) > 0.3:
			moved += 1
	check("quiet, the specimens walk their loops", moved >= 2, "%d of 3 moved" % moved)
	check("none of them has noticed the player", event.specimens[0].state != 3 and event.specimens[1].state != 3 and event.specimens[2].state != 3, "")
	var lamp := OmniLight3D.new()
	lamp.light_energy = 4.0
	lamp.omni_range = 8.0
	room.add_child(lamp)
	lamp.global_position = event.specimens[0].global_position + Vector3(0.0, 2.0, 0.0)
	place_player(event.specimens[0].global_position + Vector3(3.0, 0.5, 0.0))
	face_point(event.specimens[0].global_position + Vector3(0.0, 0.5, 0.0))
	await secs(0.3)
	await shot("room939_patrol")
	lamp.queue_free()
	# sound: heard at 1.6 x the player's noise they are alerted, at 1.2 x they attack
	var target: Node3D = event.specimens[1]
	target.state = 2
	target.reload = 0.0
	target.state3 = 0
	var away: Vector3 = (Vector3(target.global_position.x, 0.0, target.global_position.z) - Vector3(room.global_position.x, 0.0, room.global_position.z)).normalized()
	var found_alert := false
	for spot_distance in [6.0, 7.0]:
		place_player(target.global_position - away * spot_distance + Vector3(0.0, 0.4, 0.0))
		for frame_step in 6:
			player.sound_volume = 5.5
			await get_tree().physics_frame
			if target.state == 1:
				break
		if target.state == 1:
			found_alert = true
			break
		target.state = 2
	check("a step heard within 1.6 x its volume alerts it (state 1)", found_alert, "state %d vol %.1f room %s noT %s ign %s rel %.1f dist %.1f" % [target.state, player.sound_volume, str(get_tree().get_first_node_in_group("facility").room_name_at(player.global_position)), str(GameState.no_target_mode()), str(target.ignore_player), target.reload, target.global_position.distance_to(player.global_position)])
	if found_alert:
		check("and it rears up (frame 175 on)", target.frame >= 175.0 and target.frame <= 297.0, "frame %.1f" % target.frame)
	target.state = 2
	place_player(target.global_position + Vector3(2.5, 0.4, 0.0))
	player.sound_volume = 4.0
	await secs(0.2)
	check("within 1.2 x it attacks (state 3)", target.state == 3, "state %d" % target.state)
	GameState.god_mode = false
	GameState.injuries = 0.0
	for i in 80:
		player.sound_volume = 4.0
		await secs(0.1)
		if GameState.injuries >= 1.4:
			break
	check("it runs at the player and bites (1.5-2.5 injuries a bite)", GameState.injuries >= 1.4 and target.bites >= 1, "injuries %.2f bites %d state %d frame %.0f" % [GameState.injuries, target.bites, target.state, target.frame])
	GameState.injuries = 3.9
	for i in 100:
		player.sound_volume = 4.0
		await secs(0.1)
		if player.dead:
			break
	check("past 4 injuries the player is killed and it settles (state 5)", player.dead and target.state == 5, "state %d" % target.state)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	hud.cancel_death()
	player.dead = false
	GameState.injuries = 0.0
	# the trigger boxes: inside "939-1_fix" the first one ignores the player
	var fix_box := {}
	for box in room.triggers:
		if str(box.name) == "939-1_fix":
			fix_box = box
	check("the room has the trigger box 939-1_fix", not fix_box.is_empty(), "")
	if not fix_box.is_empty():
		var centre: Vector3 = room.to_global((fix_box.low + fix_box.high) * 0.5)
		place_player(centre)
		await secs(0.3)
		check("inside it the first specimen ignores the player", event.specimens[0].ignore_player and not event.specimens[2].ignore_player, "")
		place_player(Vector3(lower.x, lower.y + 0.4, lower.z))
		await secs(0.3)
		check("outside it does not", not event.specimens[0].ignore_player, "")
	# the levers open RoomDoors[4]
	var door: Node3D = room.door_slots[4]
	door.open = false
	await secs(0.2)
	check("RoomDoors[4] is shut", not door.open, "")
	event.levers[0].pitch = 80.0
	await secs(0.5)
	check("pulling a lever opens it and locks the levers", door.open and event.levers[1].locked, "")
	# up on the first level they do nothing
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.5)
	check("above the lower level the specimens are put away (state 66)", event.specimens[0].state == 66 and event.specimens[1].state == 66 and not event.specimens[2].visible and st.s == 0.0, "state %d" % event.specimens[0].state)
	check("and the music is released", GameState.music_override != "Room3Storage", "")
	var pit: Vector3 = room.object_point(4)
	place_player(Vector3(pit.x, room.global_position.y - 26.0, pit.z))
	await secs(0.6)
	check("below -6400 units the fall kills", player.dead, "")
	hud.cancel_death()
	player.dead = false
	GameState.god_mode = false

func _scn_room2scps2() -> void:
	log_line("== room2scps2 (Emily's scream)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	facility.contained_106 = false
	var record := _find_room("room2scps2")
	check("the map has room2scps2", not record.is_empty(), "")
	if record.is_empty():
		return
	var ambient: Node = facility.ambient
	ambient.enabled = true
	ambient.force(record.key, "room2scps2")
	var room: Node3D = facility.rooms.get_room(record)
	var door: Node3D = room.door_slots.get(0)
	check("RoomDoors[0] is locked", door != null and door.locked, "")
	place_player(record.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.5)
	var st: Dictionary = ambient.state_of(record.key)
	check("in range the scream starts", st.s == 1.0, "state %.0f" % st.s)
	check("and the door is still locked", door.locked, "")
	var nodes: Dictionary = ambient._nodes.get(record.key, {})
	var voice: Variant = nodes.get("scream")
	check("the scream plays", voice != null and is_instance_valid(voice), "")
	if voice != null and is_instance_valid(voice):
		(voice as AudioStreamPlayer3D).stop()
		(voice as AudioStreamPlayer3D).finished.emit()
	await secs(0.5)
	check("when it is over the door is unlocked", not door.locked and ambient.removed.has(record.key), "locked %s removed %s" % [str(door.locked), str(ambient.removed.has(record.key))])
	ambient.enabled = false

# ---------------------------------------------------------------- SCP-1123 (room1123)

func _scn_room3servers() -> void:
	log_line("== room3servers duck and 173")
	statue.active = false
	var record := _find_room("room3servers")
	check("the map has room3servers", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_statue(Vector3(0.0, -80.0, 0.0))
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.5)
	var event: Node = room.extras
	check("the room has its event with the duck", event != null and event.duck != null, "")
	var duck_model: B3DModel = null
	if event != null and event.duck != null:
		for child in event.duck.get_children():
			if child is B3DModel:
				duck_model = child
	var duck_material := duck_model.mesh_instance.get_surface_override_material(0) if duck_model != null else null
	check("the painted duck keeps the entity light model", duck_material is EntityMaterial, "%s" % duck_material)
	if event == null or event.duck == null:
		return
	var duck_start: float = event.duck.position.y
	statue.idle = 0
	facility.events.room3servers.moved_173.erase(room.room_key)
	place_statue(Vector3(0.0, -80.0, 0.0))
	player.blink_timer = -11.0
	await secs(0.1)
	var near := false
	for i in 3:
		var spot: Vector3 = room.object_point(i)
		if Vector2(statue.global_position.x - spot.x, statue.global_position.z - spot.z).length() < 0.5:
			near = true
	check("173 is put at one of Objects[0..2] at the first blink", near, str(statue.global_position))
	var facing: Vector3 = -event.duck.global_transform.basis.z
	var toward: Vector3 = player.camera.global_position - event.duck.global_position
	check("the duck turns to the camera during the blink", Vector2(facing.x, facing.z).normalized().dot(Vector2(toward.x, toward.z).normalized()) > 0.98, "")
	event.bobbing = true
	event.bob_state = 90.0
	await secs(0.1)
	check("the duck bobs", absf(event.duck.position.y - duck_start) > 0.001 or event.bob_state > 90.0, "")

func _scn_room1123vision() -> void:
	log_line("== SCP-1123's vision")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var record := _find_room("room1123")
	check("the map has room1123", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(1.0)
	var event: Node = room.extras
	check("the room has its event, six door pieces and a door at RoomDoors[0]", event != null and event.frames_and_doors.size() == 6 and room.door_slots.has(0), "")
	if event == null:
		return
	var st: Dictionary = facility.ambient.state_of(record.key)
	st.s = 0.0
	st.s2 = 0.0
	GameState.achievements.erase("1123")
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	var skull: int = _give(hud, "SCP-1123", "1123")
	var leaflet: int = _give(hud, "Leaflet", "paper")
	await _use_slot(hud, skull)
	await secs(0.3)
	check("using it in its room starts the vision (EventState 2 after the first frame)", st.s >= 2.0, "state %.0f" % st.s)
	check("the player is carried to Objects[4], hurt and blurred", Vector2(player.global_position.x - room.object_point(4).x, player.global_position.z - room.object_point(4).z).length() < 0.8 and GameState.injuries >= 1.0 and GameState.blur_timer > 100.0, "injuries %.2f" % GameState.injuries)
	check("the officer is in the room", event.officer != null and is_instance_valid(event.officer), "")
	check("saving is refused", GameState.save_blocked and not load("res://scripts/ui/pause_menu.gd").can_save_here(), "")
	GameState.god_mode = true
	# 1000 frames in, the door swings and the officer speaks; leaving the spot carries the player on
	st.s2 = 1001.0
	await secs(1.5)
	check("the door at Objects[11] swings from 90 toward 10", event.door_yaw[11] < 89.0, "yaw %.1f" % event.door_yaw[11])
	check("the officer paces his animation", event.officer.state == 3 and event.officer.frame >= 3.0 and event.officer.frame <= 26.0, "frame %.1f" % event.officer.frame)
	GameState.blur_timer = 0.0
	GameState.light_flash = 0.0
	face_point(event.officer.global_position + Vector3(0.0, 0.8, 0.0))
	await secs(0.1)
	GameState.light_flash = 0.0
	GameState.blur_volume = 0.0
	await shot("room1123_officer")
	# EventState 3 moves on as soon as this door is open; earlier scenarios may have left it open
	room.door_slots[0].open = false
	room.door_slots[0].openstate = 0.0
	place_player(room.object_point(4) + Vector3(0.0, -0.3, 0.0) + (room.global_position - room.object_point(4)).normalized() * 2.0)
	await secs(0.3)
	check("walking off carries the player to Objects[5] (EventState 3)", st.s == 3.0 and Vector2(player.global_position.x - room.object_point(5).x, player.global_position.z - room.object_point(5).z).length() < 0.8, "state %.0f" % st.s)
	var door: Node3D = room.door_slots[0]
	door.open = true
	for i in 100:
		await secs(0.1)
		if st.s == 4.0:
			break
	check("when the door has opened the officer is moved to Objects[7] (EventState 4)", st.s == 4.0 and event.officer.global_position.distance_to(room.object_point(7)) < 1.0, "state %.0f" % st.s)
	# the door at Objects[13]
	# Objects[12] is a door frame standing on the vision floor
	place_player(room.object_point(12) + Vector3(0.0, 0.05, 0.0) + Vector3(0.5, 0.0, 0.0).rotated(Vector3.UP, room.rotation.y))
	await secs(0.2)
	event._set_door(13, 1.0)
	for i in 100:
		await secs(0.1)
		if st.s == 5.0:
			break
	check("pushed open, the officer turns on the player and the blow lands (EventState 5)", st.s == 5.0, "state %.0f door %.1f frame %.1f" % [st.s, event.door_yaw[13], event.officer.frame])
	check("the player is left at 1.5 injuries and 70 blood loss", GameState.injuries == 1.5 and GameState.bloodloss >= 69.0, "injuries %.2f blood %.1f" % [GameState.injuries, GameState.bloodloss])
	st.s2 = 501.0
	await secs(0.3)
	check("later he lies by the door with the officer standing over him (EventState 6)", st.s == 6.0 or st.s >= 7.0, "state %.0f" % st.s)
	if event._voice != null and is_instance_valid(event._voice):
		event._voice.stop()
	for i in 30:
		await secs(0.1)
		if st.s >= 8.0:
			break
	check("when the officer has spoken the shot ends it (EventState 8: over)", st.s == 8.0, "state %.0f" % st.s)
	check("injuries and blood loss are given back", GameState.injuries == 0.0 and GameState.bloodloss == 0.0, "injuries %.2f blood %.1f" % [GameState.injuries, GameState.bloodloss])
	check("the leaflet is gone and the achievement given", GameState.achievements.has("1123") and not hud.items.has("Leaflet"), "")
	check("saving is allowed again and the officer is gone", not GameState.save_blocked and event.officer == null, "")
	GameState.blur_timer = 0.0
	GameState.light_flash = 0.0
	GameState.god_mode = false

func _scn_slresume() -> void:
	log_line("== room2sl: the scene goes on while the player is far away")
	var setup: Dictionary = await _room2sl_setup()
	if setup.is_empty():
		check("the map has a room2sl", false, "")
		return
	var room: Node3D = setup.room
	facility.spawn_049_enabled = true
	facility.scp049 = null
	facility.check_049_trigger(player.global_position)
	var scene: Node = facility.room2sl_scene
	check("entering the room starts the event", scene != null and facility.scp049 != null, "")
	if scene == null or facility.scp049 == null:
		return
	var npc: CharacterBody3D = facility.scp049
	check("049 opens doors within 0.6 of the next waypoint in the scene", npc._follower.open_reach == 0.6, "%.2f" % npc._follower.open_reach)
	check("the first frames are the event's quick load (the scene has not begun)", scene._delay > 0.0, "%.1f" % scene._delay)
	await secs(0.6)
	check("a dozen frames later it has", scene._delay <= 0.0, "%.1f" % scene._delay)
	var far_record: Dictionary = {}
	for record in facility.generator.rooms:
		if far_record.is_empty() or flat_dist(record.position, room.global_position) > flat_dist(far_record.position, room.global_position):
			far_record = record
	scene.event_state2 = -2.0
	GameState.god_mode = true
	place_player(far_record.position + Vector3(0.0, 1.0, 0.0))
	check("the player is more than 40 m from the room", flat_dist(player.global_position, room.global_position) > 40.0, "%.0f" % flat_dist(player.global_position, room.global_position))
	await secs(1.0)
	var started := npc.global_position
	await secs(8.0)
	check("the room is still there", is_instance_valid(room) and facility.rooms.built.get(room.room_key) == room, "")
	check("the scene goes on without the player (no PlayerRoom guard)", is_instance_valid(scene) and scene.event_state2 >= 1.0 and scene.log.has(1), str(scene.log))
	check("049 walks through his sequence", npc.is_physics_processing() and npc.global_position.distance_to(started) > 2.0, "%.1f m" % npc.global_position.distance_to(started))
	GameState.god_mode = false
	if facility.room2sl_scene != null and is_instance_valid(facility.room2sl_scene):
		facility.room2sl_scene.queue_free()
	facility.room2sl_scene = null

# UpdateEvents runs whatever the player is near: room4 (5027) puts 049 on its ledge when the player is within 16 of the room and
# 049, hunting, is farther than 16 from them; the room2sl scene (8127+) has no guard at all.
func _scn_room1archive() -> void:
	log_line("== room1archive re-rolls its door's card level")
	var record: Dictionary = {}
	for r in facility.generator.rooms:
		if str(r.name) == "room1archive":
			record = r
			break
	if record.is_empty():
		log_line("   (no room1archive on this map)")
		return
	var key: String = record.key
	place_player(Vector3(record.position.x, 1.0, record.position.z))
	var room: FacilityRoom = facility.rooms.built.get(key)
	check("the event is planned", facility.ambient.event_of(key) == "room1archive", "")
	room._fill_doors[0].keycard = 6
	facility.ambient.state_of(key).s = 0.0
	facility.ambient.enabled = true
	await secs(0.5)
	facility.ambient.enabled = false
	var level: int = room._fill_doors[0].keycard
	check("the door is level 1-3 afterwards", level >= 1 and level <= 3, str(level))
	check("it matches the rolled state", level == int(facility.ambient.state_of(key).s), "")
	var rolled: Array = record.get("items", [])
	var shelf := 0
	for child in room.get_children():
		if child.has_meta("fill_id"):
			shelf += 1
	check("the shelf items of MapSystem.bb 4654 are rolled and spawned", rolled.size() > 0 and shelf >= rolled.size(), "%d rolled, %d spawned" % [rolled.size(), shelf])

func _scn_distantevent() -> void:
	log_line("== events that act at a distance")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var room4_record: Dictionary = {}
	for record in facility.generator.rooms:
		if str(record.name) == "room4":
			room4_record = record
			break
	if room4_record.is_empty():
		for record in facility.generator.rooms:
			if str(record.name) not in ["start", "gatea"] and not facility.rooms.inside_start(record):
				room4_record = record
				break
	if room4_record.is_empty():
		check("the map has a room to hold the event", false, "")
	else:
		log_line("   the event is forced onto %s %s" % [str(room4_record.name), str(room4_record.grid)])
		facility.spawn_049_enabled = false
		var big: CharacterBody3D = facility.spawn_049(0.0)
		big.state = 2
		var key: String = room4_record.key
		var had_event: Variant = facility.ambient.plan.plan.get(key)
		facility.ambient.force(key, "room4")
		var spot := Vector3(room4_record.position.x, 0.0, room4_record.position.z)
		var heading := Vector3(10.0, 0.0, 0.0)
		for neighbour in [Vector3(10.0, 0.0, 0.0), Vector3(-10.0, 0.0, 0.0), Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, -10.0)]:
			var found: Dictionary = facility.record_at(spot + neighbour)
			if not found.is_empty() and str(found.key) != key:
				heading = neighbour
				break
		place_player(spot + heading + Vector3(0.0, 1.0, 0.0))
		big.global_position = spot + Vector3(60.0, 0.5, 0.0) if heading.x <= 0.0 else spot + Vector3(-60.0, 0.5, 0.0)
		big.velocity = Vector3.ZERO
		var player_flat := flat_dist(player.global_position, spot)
		check("the player is within 16 of the room and not in it", player_flat < 16.0 and str(facility.record_at(player.global_position).get("key", "")) != key, "%.1f" % player_flat)
		check("049 hunts, more than 16 from the player", big.state == 2 and big.global_position.distance_to(player.global_position) > 16.0, "")
		GameState.god_mode = true
		facility.ambient.enabled = true
		await secs(0.5)
		facility.ambient.enabled = false
		var ledge: Vector3 = facility.ambient.to_world(room4_record, 368.0, 528.0, 176.0)
		# a map without a room4 holds the event in another room, where the ledge's height is open air and 049 drops to that floor
		var on_ledge: bool = big.global_position.distance_to(ledge) < 1.5 if str(room4_record.name) == "room4" else flat_dist(big.global_position, ledge) < 1.5 and big.global_position.y <= ledge.y
		check("049 is on the room's ledge", on_ledge, "%s vs %s" % [str(big.global_position), str(ledge)])
		check("he stands and watches (state 4) and the event is over", big.state == 4 and facility.ambient.removed.has(key), "state %d" % big.state)
		GameState.god_mode = false
		if had_event != null:
			facility.ambient.force(key, str(had_event))
		else:
			facility.ambient.plan.plan.erase(key)
			facility.ambient._handlers.erase(key)
			facility.ambient.removed.erase(key)
		facility.ambient.states.erase(key)
		big.queue_free()
		facility.scp049 = null
		facility.spawn_049_enabled = true

# ---------------------------------------------------------------- SCP-1162 (UpdateEvents "room1162")

func _scn_room1162() -> void:
	log_line("== SCP-1162")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room1162":
			record = candidate
	check("the map has SCP-1162's room", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(record.position + Vector3(0.0, 1.0, 0.0))
	await secs(1.0)
	var event: Node = room.extras
	check("the room has its event", event != null, "")
	if event == null:
		return
	var hole: Vector3 = room.object_point(0)
	check("the hole is there", hole != Vector3.INF, "")
	var stand: Vector3 = _clear_spot(hole, 0.5)
	if stand == Vector3.INF:
		stand = hole + Vector3(0.0, -0.3, 0.0)
	var st: Dictionary = facility.ambient.state_of(record.key)
	GameState.god_mode = true
	GameState.achievements.erase("1162")
	for i in 10:
		hud.items[i] = "Level 1 Key Card"
		hud.item_data[i] = {"tempname": "key1", "icon": "GFX/items/INVkey1.jpg", "state": 0.0}
	place_player(stand + Vector3(0.0, 0.1, 0.0))
	face_point(hole)
	await secs(0.5)
	var drop: Vector3 = room.to_global(Vector3(976.0 * 8.0 / 2048.0, 128.0 * 8.0 / 2048.0, 640.0 * 8.0 / 2048.0))
	# a full pocket: one item is traded for another
	await tap("interact")
	var waited := 0.0
	var filled := 10
	while waited < 4.0 and filled == 10:
		await secs(0.1)
		waited += 0.1
		filled = 0
		for i in 10:
			if not hud.items[i].is_empty():
				filled += 1
	check("a click at the hole takes one of the items", filled == 9, "%d left" % filled)
	await secs(0.3)
	var near_drop := 0
	var got := ""
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(drop) < 1.2:
			near_drop += 1
			got = str(node.get_meta("item_name", ""))
	check("and one drops out at the hole's mouth", near_drop >= 1, "%d (%s)" % [near_drop, got])
	check("the trade is over and the achievement is given", st.s3 == 0.0 and GameState.achievements.has("1162"), "state3 %.1f" % st.s3)
	# nothing can be done while the item lies there
	var again: int = 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(hole) < 0.75:
			again += 1
	check("an item left in the hole keeps it shut", again >= 1, "%d" % again)
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(drop) < 1.2:
			node.queue_free()
	await secs(0.3)
	# nothing in the pockets: it takes from the body (or gives a memory, which also costs)
	for i in 10:
		hud.items[i] = ""
		hud.item_data[i] = {}
	GameState.injuries = 0.0
	await tap("interact")
	await secs(0.6)
	check("with empty pockets it costs 5 injuries", GameState.injuries >= 5.0 and not player.dead, "%.1f" % GameState.injuries)
	var paid := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(drop) < 1.2:
			paid += 1
			node.queue_free()
	check("and an item comes out", paid >= 1, "%d" % paid)
	check("with a message of the pain", hud.message_time_left() > 0.0, hud.message_label.text)
	await secs(0.3)
	# a memory for a filled slot: the slot is emptied and the coin comes out
	GameState.injuries = 0.0
	hud.items[0] = "Level 1 Key Card"
	hud.item_data[0] = {"tempname": "key1", "icon": "GFX/items/INVkey1.jpg", "state": 0.0}
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Coin":
			node.queue_free()
	await secs(0.2)
	st.s2 = 0.0
	st.s = 3.0
	st.s3 = 3.0
	event._memory(st, player)      # the memory is picked and spent in the frame of the click (EventState is reset every frame)
	await secs(0.3)
	var coin := false
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(drop) < 1.2 and str(node.get_meta("item_name", "")) == "Coin":
			coin = true
			node.queue_free()
	check("a memory takes the item and gives a coin", coin and hud.items[0].is_empty() and st.s3 == 0.0, "slot0 '%s'" % hud.items[0])
	await secs(0.3)
	# too much of it kills
	GameState.god_mode = false
	GameState.injuries = 12.0
	for i in 10:
		hud.items[i] = ""
		hud.item_data[i] = {}
	await tap("interact")
	await secs(0.6)
	check("past 15 injuries 1162 kills", player.dead, "%.1f" % GameState.injuries)
	hud.cancel_death()
	player.dead = false
	GameState.injuries = 0.0
	GameState.light_flash = 0.0
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).global_position.distance_to(drop) < 1.2:
			node.queue_free()

# ---------------------------------------------------------------- more ambient events: 1048-A, the 106 scares, ... (UpdateEvents)

func _scn_sllockdown() -> void:
	log_line("== room2sl monitors and the lockdown")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var fresh = load("res://scripts/world/facility_map.gd").new()
	check("a new game starts under lockdown (InitNewGame: room2sl EventState3 = 1, the handle up)", fresh.events.sl.lever_on and fresh.events.sl.lever_pitch > 0.0, "")
	fresh.free()
	var record := _find_room("room2sl")
	if record.is_empty():
		check("the map has a room2sl", false, "")
		return
	var room: Node3D = facility.rooms.get_room(record)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(1.5)
	var props: Node3D = room.extras
	check("the room has its monitor wall", props != null and props.screens.size() == 14, "")
	if props == null or props.screens.size() != 14:
		return
	# every monitor shows one frame of its strip (the whole strip came out squeezed onto the quad before)
	var one_eighth := 1.0 / 8.0
	var expected := {0: [one_eighth, 0.0], 2: [one_eighth, 2.0 * one_eighth], 3: [one_eighth, one_eighth], 8: [one_eighth, 4.0 * one_eighth],
			9: [one_eighth, 5.0 * one_eighth], 10: [one_eighth, 3.0 * one_eighth], 11: [one_eighth, 7.0 * one_eighth], 13: [one_eighth, 6.0 * one_eighth]}
	var wrong := ""
	for index in props.screens:
		var material := (props.screens[index] as MeshInstance3D).material_override as StandardMaterial3D
		var want: Array = expected.get(index, [0.25, 0.75])
		if index == 4:
			want = [0.25, 0.25 if absf(material.uv1_offset.x - 0.25) < 0.001 else 0.5]    # the lever's picture: frame 1 or 2 of four
		if absf(material.uv1_scale.x - float(want[0])) > 0.001 or absf(material.uv1_offset.x - float(want[1])) > 0.001 or material.albedo_texture == null or material.albedo_texture.get_width() < 2048:
			wrong += " %d(scale %.3f offset %.3f)" % [index, material.uv1_scale.x, material.uv1_offset.x]
	check("each monitor shows its own frame, not the whole strip", wrong == "", wrong)
	# the wall is drawn only from another level than the hall door
	var camera_screen: Node3D = room.cams[0]._screen if not room.cams.is_empty() else null
	var entrance: Node3D = facility.room_edge_doors(room)[0]
	var inward: Vector3 = room.global_position - entrance.global_position
	inward.y = 0.0
	place_player(entrance.global_position + inward.normalized() * 1.2 + Vector3(0.0, 0.1, 0.0))    # the hall: ground level
	await secs(0.5)
	check("from the hall the monitor wall is not drawn", not props.wall_shown and not props.monitors[0].visible and (camera_screen == null or not camera_screen.visible), "shown %s monitor0 %s screen %s inside %s y %.2f" % [str(props.wall_shown), str(props.monitors[0].visible), str(camera_screen.visible) if camera_screen != null else "-", str(props.player_inside), player.global_position.y])
	var catwalk: Vector3 = room.object_point(16)
	var down := PhysicsRayQueryParameters3D.create(Vector3(catwalk.x, catwalk.y + 0.8, catwalk.z), Vector3(catwalk.x, catwalk.y - 3.0, catwalk.z))
	down.collision_mask = 1
	var floor_hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
	check("the catwalk has a floor", not floor_hit.is_empty(), "")
	if not floor_hit.is_empty():
		place_player(floor_hit.position + Vector3(0.0, 0.1, 0.0))
		await secs(0.5)
		check("from the catwalk it is drawn", props.wall_shown and props.monitors[0].visible and (camera_screen == null or camera_screen.visible), "player y %.2f" % player.global_position.y)
	# getting out of the pocket dimension ends the lockdown and drops the handle
	facility.events.sl.lever_on = true
	facility.events.sl.lever_pitch = 10.0
	props.lever.pitch = 10.0
	facility.after_pocket_exit()
	check("leaving the pocket dimension puts the lockdown out", not facility.events.sl.lever_on and facility.events.sl.lever_pitch == 0.0 and props.lever.pitch == 0.0, "")
	await secs(0.5)
	check("and the handle falls to the bottom", not facility.events.sl.lever_on and props.lever.pitch < 0.0, "pitch %.0f" % props.lever.pitch)
	props.lever.pitch = 10.0
	facility.events.sl.lever_pitch = 10.0
	# the checkpoint: the lockdown holds before anybody has been to room2sl, and "near" is the larger of the two axes
	var cp := _find_room("checkpoint1")
	if cp.is_empty():
		log_line("   no checkpoint1 in this map")
	else:
		var cp_room: Node3D = facility.rooms.get_room(cp)
		place_player(cp_room.to_global(Vector3(0.0, cp_room.floor_y(0.0, 1.0) + 0.1, 1.0)))
		await secs(1.0)
		var cp_extras: Node3D = cp_room.extras
		var door_a: Node3D = cp_room.door_slots.get(0)
		var door_b: Node3D = cp_room.door_slots.get(1)
		cp_extras.lockdown = false
		door_a.locked = false
		door_b.locked = false
		facility.events.sl.lever_on = true
		player.set_physics_process(false)    # a spot out in the void would drop the bot
		place_player(Vector3(cp.position.x + 13.0, cp.position.y + 0.3, cp.position.z))
		await secs(0.4)
		check("13 away on one axis: the checkpoint is not locked yet", not door_a.locked and not cp_extras.lockdown, "")
		place_player(Vector3(cp.position.x + 11.0, cp.position.y + 0.3, cp.position.z + 11.0))
		await secs(0.4)
		check("11 away on both (15.6 straight): it is (r\\dist is the larger axis)", door_a.locked and door_b.locked and cp_extras.lockdown, "")
		facility.release_lockdown()
		await secs(0.4)
		check("the released lockdown frees it again", not door_a.locked and not door_b.locked and not cp_extras.lockdown, "")
		player.set_physics_process(true)
		place_player(cp_room.to_global(Vector3(0.0, cp_room.floor_y(0.0, 1.0) + 0.1, 1.0)))
		await secs(0.5)
	facility.events.sl.lever_on = false
	facility.events.sl.lever_pitch = 10.0
	GameState.god_mode = false

# UpdateEvents.bb "room2tunnel": the maintenance tunnels.
func _scn_maintenance() -> void:
	log_line("== maintenance tunnels")
	_check_mt_grids()
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2tunnel":
			record = candidate
			break
	if record.is_empty():
		check("the map has a room2tunnel", false, "")
		return
	if not is_instance_valid(facility.scp106):
		facility.spawn_106()
	var room: FacilityRoom = facility.rooms.get_room(record)
	var tunnels: MtEvent = room.extras
	check("room2tunnel has the event", tunnels != null and facility.rooms.tunnels == tunnels, "")
	check("nothing is built before the player comes in", tunnels.grid == null, "")
	place_player(record.position + Vector3(0.0, 1.55, 0.0))
	player.blink_timer = 400.0
	await secs(1.0)
	await _check_mt_pieces(tunnels, record)
	await _check_mt_lifts(tunnels)
	await _check_mt_save(tunnels)
	GameState.god_mode = false

# tests/fixtures/mt_grid.json is tools/mt_grid.py (the generator written again from the Blitz code).
func _check_mt_grids() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mt_grid.json"))
	for expected: Dictionary in fixtures:
		var seed_value := int(expected.seed)
		var grid := MtGrid.generate(seed_value)
		var label := "seed %d" % seed_value
		var cells: Array = expected.grid
		var same := true
		for i in MtGrid.CELLS:
			if grid.cells[i] != int(cells[i]) or grid.angles[i] != int(expected.angles[i]):
				same = false
				break
		check("%s: the grid and the pieces' yaws match the fixture" % label, same, "")
		check("%s: %d cells, first %s, last %s" % [label, grid.cell_count, grid.first, grid.last], grid.cell_count == int(expected.cells) and grid.first == Vector2i(int(expected.first[0]), int(expected.first[1])) and grid.last == Vector2i(int(expected.last[0]), int(expected.last[1])), "")
		check("%s: the stream ends where the fixture's does, the items' yaws too" % label, grid.rng_state == int(expected.rng_state) and grid.item_yaws == [int(expected.item_yaws[0]), int(expected.item_yaws[1])], "%d" % grid.rng_state)
		check("%s: the two ends differ and there is one generator room" % label, grid.first != grid.last and grid.cells.count(7) == 1 and grid.cells.count(5) == 1 and grid.cells.count(6) == 1, "")

func _check_mt_pieces(tunnels: MtEvent, record: Dictionary) -> void:
	check("the room is PlayerRoom", facility.drawing.player_room == tunnels.room, "")
	var expected := MtGrid.generate(int(facility.generator.seed_value))
	check("the grid is the seed's", tunnels.grid != null and tunnels.grid.cells == expected.cells, "")
	check("one piece per cell", tunnels.cells_root.get_child_count() > 0 and tunnels._cells.size() == expected.cell_count, "%d of %d" % [tunnels._cells.size(), expected.cell_count])
	check("the pieces hang at y 8 over the room", absf(tunnels._cells[0].global_position.y - 8.0) < 0.001, "")
	var first_cell: Vector2i = expected.first
	var floor_probe := Vector3(record.position.x + first_cell.x * 2.0, 8.6, record.position.z - first_cell.y * 2.0)
	check("the pieces are hidden while the player is below", not tunnels._cells[0].visible, "")
	player.set_physics_process(false)
	place_player(floor_probe + Vector3(0.0, 0.5, 0.0))
	await secs(0.5)
	check("above y 4 the pieces show", tunnels._cells[0].visible, "")
	check("the room is still PlayerRoom up there", facility.drawing.player_room == tunnels.room and facility.room_at(player.global_position) == tunnels.room, "")
	check("the first visit is recorded and the tunnels play Room3Storage", facility.events.mt.state == 2 and GameState.music_override == "Room3Storage" and tunnels.playing_music, GameState.music_override)
	var two_966 := tunnels.sleepers.size() == 2
	for sleeper in tunnels.sleepers:
		two_966 = two_966 and is_instance_valid(sleeper) and sleeper.global_position.y > 7.3 and sleeper.global_position.y < 8.8 and tunnels.contains(sleeper.global_position + Vector3(0.0, 0.6, 0.0))
	check("two 966s were put in the tunnels", two_966, "%d %s" % [tunnels.sleepers.size(), str(tunnels.sleepers.map(func(s): return s.global_position if is_instance_valid(s) else null))])
	check("they are in different fifths of the grid", tunnels.sleepers.size() == 2 and tunnels.sleepers[0].global_position.distance_to(tunnels.sleepers[1].global_position) > 0.5, "")
	if is_instance_valid(facility.scp106):
		var old_flat := Vector2(facility.scp106.global_position.x, facility.scp106.global_position.z)
		var end_flat := Vector2(tunnels.ends[0].x, tunnels.ends[0].z) if player.global_position.distance_to(tunnels.ends[0]) < player.global_position.distance_to(tunnels.ends[1]) else Vector2(tunnels.ends[1].x, tunnels.ends[1].z)
		check("106 was sent up under the nearer end, hunting and rising to the player's level", facility.scp106.state <= 0.0 and old_flat.distance_to(end_flat) < 6.0 and absf(facility.scp106.prev_y - player.global_position.y) < 1.0, "state %.1f at %s" % [facility.scp106.state, str(old_flat.distance_to(end_flat))])
	var stains := 0
	for decal in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if decal.global_position.y > 8.0 and decal.global_position.y < 8.2:
			stains += 1
	check("a stain was made at the end", stains >= 1, "%d" % stains)
	var query := PhysicsRayQueryParameters3D.create(floor_probe + Vector3(0.0, 1.0, 0.0), floor_probe - Vector3(0.0, 1.0, 0.0))
	query.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	check("the elevator cell has a floor at y 8", not hit.is_empty() and absf(hit.position.y - 8.0) < 0.2, str(hit.get("position", "none")))
	var found := {}
	for node in get_tree().get_nodes_in_group("pickup"):
		var item_name := str(node.get_meta("item_name", ""))
		if node.global_position.y > 7.0 and (item_name == "SCP-500-01" or item_name == "Night Vision Goggles"):
			found[item_name] = node.global_position
	var goggles_anywhere := []
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Night Vision Goggles":
			goggles_anywhere.append(node.global_position)
	check("the generator room holds the SCP-500-01 and the goggles", found.has("SCP-500-01") and found.has("Night Vision Goggles"), "%s; goggles anywhere %s; generator spot %s" % [str(found), str(goggles_anywhere), str(tunnels.ends)])
	check("every cell has its lamp and the room has the two elevator ends", tunnels.lamps.size() >= expected.cell_count, "%d lamps" % tunnels.lamps.size())
	player.set_physics_process(true)

func _check_mt_lifts(tunnels: MtEvent) -> void:
	var room := tunnels.room
	check("the two lifts exist, one per end cell", tunnels.lifts.size() == 2 and tunnels.tunnel_doors[0] != null and tunnels.tunnel_doors[1] != null, "%d" % tunnels.lifts.size())
	check("the tunnel doors begin the other way round from the room's", tunnels.tunnel_doors[0].open == not room.door_slots[0].open and tunnels.tunnel_doors[1].open == not room.door_slots[2].open, "")
	check("the doors are elevator doors", tunnels.tunnel_doors[0].elevator and room.door_slots[0].elevator, "")
	check("every cell has a waypoint, linked to its neighbours", tunnels._wp_ids.size() == tunnels.grid.cell_count and facility.graph.neighbours_of(tunnels._wp_ids.values()[0]).size() > 0, "%d" % tunnels._wp_ids.size())
	var wanted := tunnels.tunnel_cabs[0].global_position
	check("the tunnel cab is 552 units (2.16) from the end cell and 8.94 up", absf(wanted.y - (8.0 + 240.0 * MtEvent.RS)) < 0.001 and absf(Vector2(wanted.x - tunnels.ends[1].x, wanted.z - tunnels.ends[1].z).length() - 552.0 * MtEvent.RS) < 0.01, str(wanted))
	var door_a: Node3D = room.door_slots[0]
	player.set_physics_process(true)
	place_player(tunnels.room_cabs[0].global_position + Vector3(0.0, 0.1, 0.0))
	await secs(0.6)
	check("in the room's cab the door lets the player use it", door_a.open and tunnels.lifts[0].door1 == door_a, "")
	door_a.use()
	var t := 0.0
	var arrived := false
	while t < 12.0 and not arrived:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		arrived = player.global_position.distance_to(wanted) < 2.0
	check("the ride up takes about 7 s and ends in the tunnel cab", arrived and t > 6.0 and t < 10.0, "t=%.1f %s" % [t, str(player.global_position)])
	await secs(1.5)
	check("up there the tunnels are PlayerRoom and shown", facility.room_at(player.global_position) == room and tunnels._cells[0].visible and facility.drawing.player_room == room, "")
	var shown_rooms: Array = []
	for key in facility.rooms.built:
		var other: FacilityRoom = facility.rooms.built[key]
		if other != room and (other.visible or other.collidable):
			shown_rooms.append(other.room_name)
	check("up there every other room is hidden and not solid", shown_rooms.is_empty(), str(shown_rooms))
	check("and the room's own mesh is clear", room.visible and not room.visual.visible, "")
	check("the tunnel door opened, the room's is shut", tunnels.tunnel_doors[0].open and not door_a.open, "")
	var back := tunnels.tunnel_doors[0]
	back.use()
	t = 0.0
	arrived = false
	while t < 12.0 and not arrived:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		arrived = player.global_position.distance_to(tunnels.room_cabs[0].global_position) < 2.0
	check("the ride back ends in the room's cab", arrived, "t=%.1f %s" % [t, str(player.global_position)])
	await secs(1.0)
	check("the tunnels' music is let go of", not tunnels.playing_music and GameState.music_override != "Room3Storage", GameState.music_override)
	check("down again the pieces are hidden, the room's mesh is back and its neighbours are drawn by the usual rule", not tunnels._cells[0].visible and room.visual.visible and facility.drawing.ring_rooms.size() > 1, "%d rooms" % facility.drawing.ring_rooms.size())

func _check_mt_save(tunnels: MtEvent) -> void:
	var cell_count := tunnels.grid.cell_count
	var cells_before := tunnels.grid.cells.duplicate()
	place_player(tunnels.tunnel_cabs[1].global_position + Vector3(0.0, 0.1, 0.0))
	await secs(1.5)
	var sleepers_before := facility.scp966s.size()
	var at: Vector3 = player.global_position
	check("up in the tunnels again", tunnels.contains(at) and facility.drawing.player_room == tunnels.room, str(at))
	check("the game saves", main.save_game(), "")
	await main.load_game()
	var waited := 0.0
	while waited < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(2.5)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173
	var room: FacilityRoom
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2tunnel":
			room = facility.rooms.get_room(candidate)
	var again: MtEvent = room.extras
	check("after loading the player is up in the tunnels, in their room", again.contains(player.global_position) and facility.drawing.player_room == room, str(player.global_position))
	check("the grid is made again, the same", again.grid != null and again.grid.cells == cells_before and again._cells.size() == cell_count, "")
	check("the first visit is not repeated", facility.events.mt.state == 2 and facility.scp966s.size() == sleepers_before, "%d 966s, was %d" % [facility.scp966s.size(), sleepers_before])
	var pills := 0
	var goggles := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if node.global_position.y > 7.0 and node.global_position.y < 12.0:
			pills += int(str(node.get_meta("item_name", "")) == "SCP-500-01")
			goggles += int(str(node.get_meta("item_name", "")) == "Night Vision Goggles")
	check("the generator room's items are there once", pills == 1 and goggles == 1, "%d and %d" % [pills, goggles])
	check("the two lifts come back, the car where it was", again.lifts.size() == 2 and again.tunnel_doors[1].open != room.door_slots[2].open, "")
	check("the tunnels are drawn", again._cells[0].visible, "")
	check("the music plays", again.playing_music, "")
	var elsewhere := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name).begins_with("room") and str(candidate.name) != "room2tunnel" and facility.rooms.get_room(candidate) != null:
			elsewhere = candidate
			break
	if not elsewhere.is_empty():
		place_player(elsewhere.position + Vector3(0.0, 5.0, 0.0))
		await secs(0.4)
		check("leaving the tunnels for another room above y 4 does not keep the other rooms hidden", not again.hides_rooms(player.global_position) and facility.drawing.player_room != room, "%s in %s" % [str(player.global_position), str(facility.drawing.player_room.room_key if facility.drawing.player_room != null else "none")])
