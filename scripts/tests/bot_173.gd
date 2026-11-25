extends "res://scripts/tests/bot_world.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_173() -> void:
	log_line("== SCP-173")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	var spot: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -8.0))
	# 1. watched: eyes open and in view -> frozen
	revive()
	place_player(home)
	player.blink_timer = 450.0
	place_statue(spot)
	check("173's speed follows the difficulty (NPCSpeedChange)", is_equal_approx(statue.speed, 0.38 * 70.0 * GameState.npc_speed_factor()) or statue.speed == 35.0, "%.2f" % statue.speed)
	face_point(spot + Vector3(0, 0.8, 0))
	statue.active = true
	var start := statue.global_position
	await secs(1.2)
	var moved := statue.global_position.distance_to(start)
	check("173 frozen while watched", moved < 0.1 and not player.dead, "moved %.2f dead=%s" % [moved, player.dead])
	# 2. eyes closed -> 173 moves and kills
	player.blink_timer = -8.0
	Input.action_press("blink")
	await secs(1.0)
	Input.action_release("blink")
	check("173 kills when eyes closed", player.dead, "dist %.2f" % player.global_position.distance_to(statue.global_position))
	# 3. looking away
	revive()
	place_player(home)
	player.blink_timer = 450.0
	place_statue(spot)
	face_point(home + (home - spot) * 3.0)
	statue.active = true
	await secs(1.0)
	check("173 kills when not in view", player.dead, "dist %.2f" % player.global_position.distance_to(statue.global_position))
	# 4. touching a watched 173 must not kill
	revive()
	place_player(spot + Vector3(0, 0, 0.5))
	player.blink_timer = 450.0
	place_statue(spot)
	face_point(spot + Vector3(0, 0.8, 0))
	statue.active = true
	await secs(1.0)
	check("watched 173 does not kill on contact", not player.dead, "")
	statue.active = false
	revive()

# A controlled arena (flat floor, one closed door) so this tests 173, not the map around it.
func _scn_173_doors() -> void:
	log_line("== 173 opens doors")
	statue.active = false   # _reset_world wakes it; it must not touch the player before the test starts
	revive()
	var home: Vector3 = player.global_position
	var origin := Vector3(300.0, -400.0, 300.0)
	var arena := Node3D.new()
	arena.position = origin
	get_tree().root.add_child(arena)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_col.shape = floor_box
	floor_col.position.y = -0.5
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)
	var door := Node3D.new()
	door.set_script(load("res://scripts/world/facility_door.gd"))
	arena.add_child(door)
	door.place_in_room(Vector3.ZERO, 0.0, false, false)
	# the wall the room mesh puts either side of a door leaf (the door node itself has no frame collision)
	for side in [-1.0, 1.0]:
		var wall := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(30.0, 3.0, 0.1)
		wall.shape = wall_box
		wall.position = Vector3(side * 15.4, 1.5, 0.0)
		floor_body.add_child(wall)
	# 173 on the +z face near a button, the player behind the door facing away
	place_statue(origin + Vector3(0.15, 0.02, 1.0))
	place_player(origin + Vector3(0.15, 0.05, -3.0))
	await secs(0.5)
	player.rotation.y = 0.0
	player.camera.rotation.x = 0.0
	player.blink_timer = 450.0
	statue.enemy_pos = player.global_position
	statue.has_enemy = true
	statue.active = true
	var opened := false
	var crossed := false
	var t := 0.0
	while t < 8.0 and not player.dead and not crossed:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		opened = opened or door.open
		crossed = statue.global_position.z - origin.z < -0.6
	check("173 opens a closed door", opened, "t=%.1fs dead=%s" % [t, player.dead])
	check("173 then passes through it", crossed or player.dead, "statue z %.2f" % (statue.global_position.z - origin.z))
	statue.active = false
	arena.queue_free()
	revive()
	await _locked_map_door_holds_173(home)

# A closed, locked door of the real map at the fastest difficulty speed (x1.2) with 173 against the leaf's edge: it must not get round or through.
func _locked_map_door_holds_173(home: Vector3) -> void:
	place_player(home)
	await secs(1.5)
	var first := _standard_door_near(home, 25.0)
	check("a standard map door is loaded near the player", first != null, "")
	if first == null:
		return
	var spot := first.global_position + Vector3(0.0, 0.05, 0.0)
	place_player(spot)
	await secs(1.0)
	var door := _standard_door_near(spot, 1.0)
	check("the door is still there after the player moved to it", door != null, "")
	if door == null:
		return
	door.snap_shut()
	door.locked = true
	var saved_speed: float = statue.speed
	statue.speed = 0.38 * 70.0 * 1.2
	var worst := INF
	for offset_x in [0.45, -0.45, 0.15, -0.15, 0.0]:
		place_statue(door.to_global(Vector3(offset_x, 0.0, 1.0)))
		place_player(door.to_global(Vector3(offset_x, 0.05, -3.0)))
		await secs(0.4)
		player.rotation.y = door.global_rotation.y
		player.camera.rotation.x = 0.0
		player.blink_timer = 450.0
		statue.enemy_pos = player.global_position
		statue.has_enemy = true
		statue.active = true
		var t := 0.0
		while t < 3.0 and not player.dead:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			worst = minf(worst, door.to_local(statue.global_position).z)
		statue.active = false
	check("173 cannot get past a locked map door at Keter speed", worst > -0.3 or player.dead, "lowest local z %.2f" % worst)
	statue.speed = saved_speed
	door.locked = false
	revive()

func _standard_door_near(point: Vector3, within: float) -> Node3D:
	for node in get_tree().get_nodes_in_group("door"):
		var door := node as Node3D
		if door != null and not door.big and door.keycard == 0 and door.code.is_empty() and not door.elevator and door.global_position.distance_to(point) < within:
			return door
	return null

func _scn_173_facing() -> void:
	log_line("== 173 facing")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	revive()
	GameState.god_mode = true
	var origin := Vector3(900.0, 200.0, 900.0)
	var arena := _arena(origin)
	place_player(origin + Vector3(0.0, 0.05, 0.0))
	await secs(0.3)
	var worst := 1.0
	for offset in [Vector3(6.0, 0.0, 0.0), Vector3(0.0, 0.0, 6.0), Vector3(-5.0, 0.0, -4.0)]:
		place_statue(origin + offset + Vector3(0, 0.05, 0))
		# looking the other way so it is free to move
		var away: Vector3 = (-offset).normalized() * 3.0
		player.rotation.y = atan2(-away.x, -away.z)
		player.camera.rotation.x = 0.0
		player.blink_timer = 450.0
		statue.active = true
		await secs(0.12)
		var to_player: Vector3 = player.global_position - statue.global_position
		to_player.y = 0.0
		var d := _statue_face_dir().dot(to_player.normalized())
		worst = minf(worst, d)
		log_line("   from %s: facing dot player %.2f (1 = looking at you)" % [str(offset), d])
		statue.active = false
	check("173 faces the player while it comes for them", worst > 0.9, "worst dot %.2f" % worst)
	GameState.god_mode = false
	arena.queue_free()
	place_player(home)
	await secs(2.5)

func _scn_173_rules() -> void:
	log_line("== 173 rules")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	revive()
	var s := GameState
	s.god_mode = false
	# --- cues while watched: the view zooms and shudders when it is close
	var arena := _arena(Vector3(1100.0, 200.0, 1100.0))
	var o := arena.position
	place_player(o + Vector3(0.0, 0.05, 0.0))
	await secs(0.3)
	player.rotation.y = 0.0
	player.camera.rotation.x = 0.0
	player.blink_timer = 450.0
	place_statue(o + Vector3(0.0, 0.05, -2.0))
	statue.active = true
	var zoomed := 0.0
	var blurred := 0.0
	var t := 0.0
	while t < 0.8:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		zoomed = maxf(zoomed, player.camera_zoom)
		blurred = maxf(blurred, s.blur_volume)
	check("watched 173 within 3.5 units pinches the view", zoomed > 5.0 and player.camera.fov < 90.0 and not player.dead, "zoom %.1f fov %.2f" % [zoomed, player.camera.fov])
	check("and blurs it (BlurVolume = Max((4 - dist) / 6, 0.1))", blurred > 0.25 and blurred < 0.45, "volume %.2f" % blurred)
	statue.active = false
	# --- a wall between: no kill without line of sight, and it wanders
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(90.0, 3.0, 0.2)    # wide enough that a wandering 173 (about 26 m/s) cannot run round it within the second
	wcol.shape = wbox
	wall.add_child(wcol)
	arena.add_child(wall)
	wall.position = Vector3(0.0, 1.5, -1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	place_statue(o + Vector3(0.0, 0.05, -1.5))
	statue.rotation.y = 0.0   # facing away from the wall
	player.rotation.y = PI
	statue.has_enemy = false
	statue.active = true
	var start := statue.global_position
	await secs(1.0)
	check("173 behind a wall cannot see or kill, and wanders", not player.dead and statue.global_position.distance_to(start) > 0.1, "dead=%s moved %.1f" % [str(player.dead), statue.global_position.distance_to(start)])
	# --- EntityInView has no occlusion test: facing it through the wall still holds it
	statue.active = false
	place_statue(o + Vector3(0.0, 0.05, -2.5))
	player.rotation.y = 0.0
	player.blink_timer = 450.0
	statue.has_enemy = false
	statue.active = true
	start = statue.global_position
	await secs(0.6)
	var moved := flat_dist(statue.global_position, start)
	check("173 behind a wall the player faces stays put", moved < 0.02, "moved %.2f" % moved)
	wall.position = Vector3(0.0, -50.0, 0.0)
	# --- EntityInView culls the whole bounding box: an edge of it on screen holds it
	statue.active = false
	place_statue(o + Vector3(0.0, 0.05, -3.0))
	await get_tree().physics_frame
	var yaw := 0.0
	while yaw < 90.0 and player.camera.is_position_in_frustum(statue.global_position + Vector3(0.0, 0.8, 0.0)):
		yaw += 0.5
		player.rotation.y = deg_to_rad(yaw)
		player.camera.force_update_transform()
	var edge_in_view: bool = statue.in_view(player.camera)
	player.blink_timer = 450.0
	statue.has_enemy = false
	statue.active = true
	start = statue.global_position
	await secs(0.6)
	moved = flat_dist(statue.global_position, start)
	check("173 with its middle off screen but an edge on it stays put", edge_in_view and not player.dead and moved < 0.02, "yaw %.1f in_view=%s moved %.2f" % [yaw, str(edge_in_view), moved])
	# --- notarget: it moves even while watched
	statue.active = false
	place_statue(o + Vector3(0.0, 0.05, -4.0))
	player.rotation.y = 0.0
	player.blink_timer = 450.0
	s.no_target = true
	statue.active = true
	start = statue.global_position
	await secs(0.6)
	s.no_target = false
	statue.active = false
	wall.position = Vector3(0.0, 1.5, -1.0)
	await get_tree().physics_frame
	check("with notarget a watched 173 still moves and does not kill", not player.dead and statue.global_position.distance_to(start) > 0.1, "moved %.2f" % statue.global_position.distance_to(start))
	# --- it walks to where it last saw you
	statue.active = false
	place_statue(o + Vector3(-6.0, 0.05, -5.0))
	statue.enemy_pos = o + Vector3(-6.0, 0.0, -9.0)
	statue.has_enemy = true
	player.rotation.y = PI   # looking away: 173 is behind the player
	statue.active = true
	var closest := INF
	t = 0.0
	while t < 0.8:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		closest = minf(closest, Vector2(statue.global_position.x - statue.enemy_pos.x, statue.global_position.z - statue.enemy_pos.z).length())
	var gap := closest
	check("173 goes to the last place it saw you, then forgets", gap < 0.8 and not statue.has_enemy, "closest %.2f has_enemy=%s" % [gap, str(statue.has_enemy)])
	statue.active = false
	wall.queue_free()
	arena.queue_free()
	# --- the neck-snap message depends on the room
	place_player(home)
	await secs(0.5)
	place_statue(player.global_position + Vector3(0.0, 0.0, -0.4))
	player.rotation.y = PI
	player.blink_timer = 450.0
	statue.active = true
	t = 0.0
	while t < 1.0 and not player.dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var label_text: String = get_tree().get_first_node_in_group("hud").pause_menu.death_message
	check("kill shows the chamber message", player.dead and label_text.contains("Franklin"), label_text.substr(0, 60))
	var menu: Control = get_tree().get_first_node_in_group("hud").pause_menu
	var waited := 0.0
	while waited < 15.0 and not menu.visible:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await get_tree().process_frame
	var message: Label = null
	for child in menu.get_children():
		if child is Label and child.text == label_text:
			message = child
	var menu_s := UIKit.menu_scale(menu)
	var box_bottom: float = (menu.size.y + 600.0 * menu_s) * 0.5
	var text_bottom: float = message.position.y + message.get_line_count() * (message.get_line_height() + message.get_theme_constant("line_spacing")) if message != null else INF
	# Font1 is a 19 cell (16.8 em): RowText fits it in about 38 characters a line, 20 units apart
	check("the death text fits in the box (Font1's size and RowText's rows)", text_bottom <= box_bottom, "%d lines, text ends %.0f, box ends %.0f" % [message.get_line_count() if message != null else -1, text_bottom, box_bottom])
	statue.active = false
	revive()

# NPCs.bb 768-789 and TeleportCloser 5124-5167: past 50 it jumps to a non-door waypoint 15-25 from the player on both axes, between
# 12 and 50 it hops to the waypoint near itself that is closest to the player.
func _far_pool(points: Array[Vector3], from: Vector3, far: bool) -> Array[Vector3]:
	var pool: Array[Vector3] = []
	for w in points:
		if absf(w.y - from.y) > 2.0:
			continue
		var d := from.distance_to(w)
		if far:
			if d >= 55.0 and d <= 110.0:
				pool.append(w)
		elif absf(from.x - w.x) > 15.0 and absf(from.x - w.x) < 25.0 and absf(from.z - w.z) > 15.0 and absf(from.z - w.z) < 25.0:
			pool.append(w)
	return pool

func _scn_far173() -> void:
	log_line("== 173 far teleports")
	await _reset_world()
	GameState.god_mode = true
	statue.active = false
	var points: Array[Vector3] = facility.waypoints()
	check("every room provides waypoints", points.size() > 100, "%d" % points.size())
	var from_player: Vector3 = player.global_position
	if _far_pool(points, from_player, false).is_empty():
		for q in points:
			if facility.room_name_at(q) in ["exit1", "gatea", "pocketdimension"] or _far_pool(points, q, false).is_empty() or _far_pool(points, q, true).is_empty():
				continue
			place_player(q + Vector3(0.0, 1.2, 0.0))
			await secs(0.5)
			from_player = player.global_position
			break
	var trials := 0
	var good := 0
	var sample := 0
	for w in points:
		var d := from_player.distance_to(w)
		if d < 55.0 or d > 110.0 or absf(w.y - from_player.y) > 2.0:
			continue
		sample += 1
		if sample % 9 != 1 or trials >= 3:
			continue
		trials += 1
		place_statue(w + Vector3(0.0, 0.25, 0.0))
		statue.active = true
		var jump := await _first_173_jump(40.0)
		statue.active = false
		if jump.is_empty():
			log_line("   trial %d: no jump from %s" % [trials, str(w)])
			continue
		var landed: Vector3 = jump.to - Vector3(0.0, 0.25, 0.0)
		var on_waypoint := false
		for p in points:
			if p.distance_to(landed) < 0.01:
				on_waypoint = true
				break
		var dx := absf(from_player.x - landed.x)
		var dz := absf(from_player.z - landed.z)
		if on_waypoint and dx > 15.0 and dx < 25.0 and dz > 15.0 and dz < 25.0:
			good += 1
		else:
			log_line("   trial %d: landed %s, dx %.1f dz %.1f, on a waypoint %s" % [trials, str(landed), dx, dz, str(on_waypoint)])
	check("a 173 past 50 m lands on a waypoint 15-25 m from the player on both axes", trials > 0 and good == trials, "%d of %d trials" % [good, trials])
	var hop_ok := 0
	var hop_trials := 0
	for w in points:
		var d := from_player.distance_to(w)
		if d < 22.0 or d > 45.0 or absf(w.y - from_player.y) > 2.0 or hop_trials >= 3:
			continue
		var expected := _closer_goal(w, from_player)
		if expected == Vector3.INF:
			continue
		hop_trials += 1
		place_statue(w + Vector3(0.0, 0.25, 0.0))
		statue.active = true
		var jump := await _first_173_jump(14.0)
		statue.active = false
		if not jump.is_empty() and (jump.to - Vector3(0.0, 0.15, 0.0)).distance_to(expected) < 0.01:
			hop_ok += 1
	check("between 12 and 50 m it hops to the waypoint near itself that is closest to the player", hop_trials > 0 and hop_ok == hop_trials, "%d of %d" % [hop_ok, hop_trials])
	var far_spot := Vector3.INF
	for w in points:
		if from_player.distance_to(w) > 60.0:
			far_spot = w
			break
	var here := Node3D.new()
	facility.add_child(here)
	for name in ["exit1", "gatea"]:
		var record: Dictionary = facility.gatea_record if name == "gatea" else {}
		if name == "exit1":
			for r in facility.generator.rooms:
				if str(r.name) == "exit1":
					record = r
		if record.is_empty():
			continue
		here.global_position = record.position + Vector3(0.0, 0.3, 0.0)
		check("the dummy stands in %s" % name, facility.room_name_at(here.global_position) == name, facility.room_name_at(here.global_position))
		place_statue(far_spot + Vector3(0.0, 0.25, 0.0))
		var before: Vector3 = statue.global_position
		for i in 400:
			statue._teleport_far(here)
		check("173 never jumps while the player is in %s" % name, statue.global_position == before, "")
	here.global_position = from_player
	var moved := false
	for i in 400:
		statue._teleport_far(here)
		if statue.global_position.distance_to(far_spot) > 1.0:
			moved = true
			break
	check("the same call jumps with the player in an ordinary room", moved, "")
	here.queue_free()
	await _check_closer_in_facility()
	GameState.god_mode = false

func _first_173_jump(limit: float) -> Dictionary:
	var last: Vector3 = statue.global_position
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if statue.global_position.distance_to(last) > 1.0:
			return {"from": last, "to": statue.global_position, "time": t}
	return {}

func _closer_goal(from: Vector3, player_at: Vector3) -> Vector3:
	var goal: Variant = TeleportCloser.pick(from, player_at, NpcGravity.in_facility(from.y))
	return goal if goal != null else Vector3.INF

# CheckForNPCInFacility: only an NPC in the facility proper (not the tunnels, not aggressive) refuses a waypoint above 7 or below -10.
func _check_closer_in_facility() -> void:
	var npc := Node3D.new()
	facility.add_child(npc)
	var out := player.global_position + Vector3(400.0, 0.0, 400.0)
	var fake := out + Vector3(5.0, 9.0, 5.0)
	facility.waypoints().append(fake)
	npc.global_position = out + Vector3(0.0, 1.0, 0.0)
	var stay := npc.global_position
	check("a waypoint above y 7 is refused by an NPC in the facility", not TeleportCloser.run(npc) and npc.global_position == stay, str(npc.global_position))
	npc.global_position = out + Vector3(0.0, -20.0, 0.0)
	check("an NPC in the tunnels takes it", TeleportCloser.run(npc) and npc.global_position.is_equal_approx(fake + Vector3(0.0, 0.15, 0.0)), str(npc.global_position))
	var difficulty := GameState.difficulty
	GameState.difficulty = 2
	npc.global_position = out + Vector3(0.0, 1.0, 0.0)
	check("so does one in the facility when the difficulty is aggressive", TeleportCloser.run(npc), "")
	GameState.difficulty = difficulty
	facility.waypoints().erase(fake)
	var low := out + Vector3(5.0, 5.0, 5.0)
	facility.waypoints().append(low)
	npc.global_position = out + Vector3(0.0, 1.0, 0.0)
	check("a waypoint between -10 and 7 is taken", TeleportCloser.run(npc), "")
	facility.waypoints().erase(low)
	npc.queue_free()
