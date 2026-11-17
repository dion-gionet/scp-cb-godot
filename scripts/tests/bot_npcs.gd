extends "res://scripts/tests/bot_items_ui.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_audio() -> void:
	log_line("== audio")
	statue.active = false
	revive()
	var audio: Node = get_tree().get_first_node_in_group("audio")
	check("audio director exists", audio != null, "")
	if audio == null:
		return
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.5)
	# music follows the zone: LCZ rows >= 12, HCZ rows 6..11, EZ rows < 6
	var lcz_track: String = audio.ZONE_TRACKS[facility.zone_at(home)]
	var t := 0.0
	while t < 12.0 and audio._now_playing != lcz_track:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("start room plays its zone track (%s)" % lcz_track, audio._now_playing == lcz_track and audio._music.playing, "now '%s' should '%s'" % [audio._now_playing, audio._should_play])
	await secs(2.0)   # let the new track fade in
	place_player(Vector3(home.x, 1.5, -8.0 * 8.0))   # row 8 = heavy containment
	t = 0.0
	while t < 14.0 and audio._now_playing != "HeavyContainment":
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("moving to row 8 crossfades to HeavyContainment in ~4 s", audio._now_playing == "HeavyContainment" and t > 2.5 and t < 8.0, "t=%.1fs now '%s'" % [t, audio._now_playing])
	place_player(home)
	await secs(1.0)
	# footsteps: about one per 0.73 s walking, 0.49 s sprinting
	var before: int = audio.steps_played
	face_point(home + Vector3(0, 0, 3.0))
	Input.action_press("move_forward")
	await secs(3.0)
	Input.action_release("move_forward")
	var walked: int = audio.steps_played - before
	check("walking makes about four steps in 3 s", walked >= 3 and walked <= 5, "%d (%s)" % [walked, audio.last_step_file])
	place_player(home)
	await secs(1.0)
	player.stamina = 100.0
	before = audio.steps_played
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await secs(2.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var ran: int = audio.steps_played - before
	check("sprinting steps are faster and use the Run files", ran >= 3 and str(audio.last_step_file).contains("Run"), "%d (%s)" % [ran, audio.last_step_file])
	GameState.mark_pd_step()
	audio._step(player)
	check("CurrStepSFX 1 (pocket dimension, sinkhole) plays the StepPD files", str(audio.last_step_file).contains("StepPD"), audio.last_step_file)
	await secs(0.1)
	audio._step(player)
	check("and the facility's steps are back the next frame", not str(audio.last_step_file).contains("StepPD"), audio.last_step_file)
	# some rooms have metal floors
	var metal_rooms := 0
	for key in facility.rooms.built:
		var room: Node3D = facility.rooms.built[key]
		for flag in room._drawn_metal:
			if flag == 1:
				metal_rooms += 1
				break
	log_line("   %d of %d loaded rooms have metal floor triangles" % [metal_rooms, facility.rooms.built.size()])
	player.stamina = 3.0
	Input.action_press("sprint")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("exhausted sprinting starts the breath loop", audio._breath.playing, "")
	Input.action_release("sprint")
	player.stamina = 100.0
	audio.heartbeat(0.5, 140.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("heartbeat starts and fades", audio._heart.playing or audio._heart_volume > 0.0, "volume %.2f" % audio._heart_volume)
	var children_before := audio.get_child_count()
	audio.play_item_sound("Level 1 Key Card")
	check("picking up plays an item sound", audio.get_child_count() == children_before + 1, "")
	audio._update_ambient(player, 100000.0)
	await get_tree().physics_frame
	var emitters := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer3D:
			emitters += 1
	check("an ambience clip is emitted near the player", emitters >= 1, "%d" % emitters)

# FindPath's own search on a four-point graph: S links to A (a 10-unit detour) and B (1 unit), both link to E. The
# original opens A and B with Fcost = S's Gcost + Hcost = 0, expands A first (the earlier point on the tie), opens E
# from A and stops there, so its route is the detour; a textbook A* takes S-B-E.
func _check_findpath_quirks() -> void:
	var detour: Array = _graph([Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(1, 0, 0), Vector3(2, 0, 0)], [[0, 1], [0, 2], [1, 3], [2, 3]])
	var route: Array = detour[0].search(detour[1][0], detour[1][3])
	check("FindPath keeps the original's scoring: the earlier of two fresh points is expanded first", route == [detour[1][0], detour[1][1], detour[1][3]], str(route))
	# the MTF pays 0.5 per non-door step: with B first in the list and two non-door points tied on Fcost the order decides
	var short: Array = _graph([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1.5, 0, 0), Vector3(2, 0, 0)], [[0, 1], [1, 2], [2, 3], [1, 3]])
	var ids: Array = short[1]
	var plain: Array = short[0].search(ids[0], ids[3])
	var mtf: Array = short[0].search(ids[0], ids[3], true)
	check("FindPath stops when the end point is opened", plain == [ids[0], ids[1], ids[3]] and mtf == plain, "%s / mtf %s" % [plain, mtf])
	check("FindPath reports no route between unlinked points", short[0].search(ids[0], short[0].add_point(Vector3(50, 0, 0), "t", "t", false)).is_empty(), "")

# A fresh waypoint graph of `points` (the last one a door's), linked both ways by index `pairs`: [graph, ids].
func _graph(points: Array, pairs: Array) -> Array:
	var graph: Object = facility.graph.get_script().new()
	var ids: Array = []
	for i in points.size():
		ids.append(graph.add_point(points[i], "t", "t", i == points.size() - 1))
	for pair in pairs:
		graph._connect(ids[pair[0]], ids[pair[1]])
		graph._connect(ids[pair[1]], ids[pair[0]])
	return [graph, ids]

func _scn_pathfind() -> void:
	log_line("== pathfinding")
	_check_findpath_quirks()
	statue.active = false
	revive()
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	var t := 0.0
	while t < 12.0 and facility.graph.pending_count() > 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await secs(1.0)
	var graph: Object = facility.graph
	var points: int = graph.point_count()
	var links := 0
	for id in graph._owner_of:
		links += graph.astar.get_point_connections(id).size()
	check("waypoint graph is built from the rooms", points > 20 and links > points, "%d points, %d link ends, %d pending" % [points, links, graph.pending_count()])
	var pair: Dictionary = _find_walkable_pair()
	var start_id: int = pair.start_id
	var end_id: int = pair.end_id
	var target: Vector3 = pair.target
	check("a reachable waypoint pair 15-32 units apart exists outside the start chamber", start_id >= 0 and end_id >= 0, "start=%d end=%d" % [start_id, end_id])
	if start_id < 0 or end_id < 0:
		return
	var start_pos: Vector3 = graph.astar.get_point_position(start_id)
	var result: Dictionary = facility.find_path(start_pos + Vector3(0, 0.1, 0), target)
	var route: Array = result.points
	var contiguous := route.size() >= 2
	for i in range(1, route.size()):
		if (route[i] as Vector3).distance_to(route[i - 1]) > 7.01:
			contiguous = false
	check("FindPath returns a connected route", int(result.status) == 1 and contiguous and (route.back() as Vector3).distance_to(target) < 1.0, "status %d, %d points" % [int(result.status), route.size()])
	check("asking for the spot you stand on says you are there", int(facility.find_path(target, target).status) == 0, "")
	# an NPC that walks it, opening doors
	var npc := CharacterBody3D.new()
	npc.collision_layer = 4
	npc.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# doorways are 1.22 high: NPC colliders are small ellipsoids like the player's (EntityRadius 0.15, 0.30)
	capsule.radius = 0.15
	capsule.height = 0.6
	shape.shape = capsule
	shape.position.y = 0.3
	npc.add_child(shape)
	var follower := Node.new()
	follower.set_script(load("res://scripts/npc/path_follower.gd"))
	follower.body = npc
	follower.speed = 3.5
	npc.add_child(follower)
	get_tree().root.add_child(npc)
	npc.global_position = start_pos + Vector3(0.0, 0.05, 0.0)
	await get_tree().physics_frame
	var status: int = follower.path_to(target)
	check("the walker gets a route", status == 1, "status %d" % status)
	# the walker does not carry keycards: open the locked doors on its route for this test only
	var relocked: Array = []
	for route_point in follower.points:
		for door_node in facility.doors_near(route_point, 0.5):
			if door_node.locked or door_node.keycard != 0 or not door_node.code.is_empty():
				relocked.append([door_node, door_node.locked, door_node.keycard, door_node.code])
				door_node.locked = false
				door_node.keycard = 0
				door_node.code = ""
	t = 0.0
	while t < 40.0 and not follower.has_arrived():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var left := Vector2(npc.global_position.x - target.x, npc.global_position.z - target.z).length()
	var door_note := ""
	for dn in facility.doors_near(npc.global_position, 2.0):
		door_note += " [door %s open=%s locked=%s key=%d code='%s']" % [str(dn.global_position), str(dn.open), str(dn.locked), dn.keycard, dn.code]
	if not follower.has_arrived():
		log_line("   walker at %s index %d/%d goal %s%s" % [str(npc.global_position), follower.index, follower.points.size(), str(follower.points[mini(follower.index, follower.points.size() - 1)]), door_note])
		var goal_point: Vector3 = follower.points[mini(follower.index, follower.points.size() - 1)]
		var toward: Vector3 = Vector3(goal_point.x - npc.global_position.x, 0.0, goal_point.z - npc.global_position.z).normalized()
		var heights := ""
		var space_h := get_viewport().world_3d.direct_space_state
		for height in [0.02, 0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 1.0]:
			var origin_h := Vector3(npc.global_position.x, npc.global_position.y + height, npc.global_position.z)
			var ray_h := PhysicsRayQueryParameters3D.create(origin_h, origin_h + toward * 0.8)
			ray_h.collision_mask = 1
			var hit_h := space_h.intersect_ray(ray_h)
			heights += " +%.2f:%s" % [height, ("%.2f" % origin_h.distance_to(hit_h.position)) if not hit_h.is_empty() else "-"]
		log_line("   walls ahead by height (distance):" + heights + "   direction " + str(toward))
		var exclude_bodies: Array[RID] = facility._door_bodies()
		for link in range(1, follower.points.size()):
			var a: Vector3 = follower.points[link - 1]
			var b: Vector3 = follower.points[link]
			var clear_low: bool = graph._visible(space_h, a + Vector3(0, 0.1, 0), b + Vector3(0, 0.1, 0), exclude_bodies)
			var clear_mid: bool = graph._visible(space_h, a + Vector3(0, 0.6, 0), b + Vector3(0, 0.6, 0), exclude_bodies)
			log_line("   link %d: %s -> %s clear at 0.1: %s, at 0.6: %s, length %.2f" % [link, str(a), str(b), str(clear_low), str(clear_mid), a.distance_to(b)])
		var rec: Dictionary = facility.record_at(Vector3(npc.global_position.x, 0.5, npc.global_position.z))
		log_line("   cell record %s loaded=%s start_loaded=%s" % [str(rec.get("name", "-")) + str(rec.get("grid", "")), str(facility.rooms.built.has(str(rec.get("key", "")))), str(is_instance_valid(facility.start_node))])
	check("the walker reaches the target through the rooms", follower.has_arrived() and left < 1.5, "t=%.1fs, %.2f from the target, stuck %.1fs" % [t, left, follower.stuck_time])
	for saved_door in relocked:
		saved_door[0].locked = saved_door[1]
		saved_door[0].keycard = saved_door[2]
		saved_door[0].code = saved_door[3]
	npc.queue_free()

func _scn_scp049() -> void:
	log_line("== SCP-049")
	statue.active = false
	if facility.scp049 != null and is_instance_valid(facility.scp049):
		facility.scp049.queue_free()
		await get_tree().physics_frame
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.5)
	var messages: Array = []
	GameState.player_died.connect(func(text: String) -> void: messages.append(text))
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	await get_tree().physics_frame
	check("049's speed follows the difficulty (NPCSpeedChange)", is_equal_approx(npc.top_speed, 1.5 / 100.0 * 70.0 * GameState.npc_speed_factor()), "%.3f" % npc.top_speed)
	# 1. it hunts a visible player and kills inside 0.5
	var spot: Vector3 = _clear_spot(player.global_position, 4.0)
	check("a clear spot 4 m from the player", spot != Vector3.INF, "")
	npc.global_position = spot
	npc._turn_toward(home, 100.0)
	npc.state = 2
	GameState.achievements.erase("049")
	var t := 0.0
	var started := npc.global_position.distance_to(player.global_position)
	await secs(1.0)
	check("being hunted by 049 gives its achievement", GameState.achievements.has("049"), "")
	var closer: float = npc.global_position.distance_to(player.global_position)
	check("049 walks at a visible player", closer < started - 0.5, "%.2f -> %.2f" % [started, closer])
	check("its model is shown", npc.visible, "")
	check("it plays its walk animation", npc._frame > 340.0 and npc._frame < 500.0, "frame %.0f" % npc._frame)
	while t < 12.0 and not player.dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("049 kills the player it reaches", player.dead, "t=%.1fs dist %.2f" % [t, npc.global_position.distance_to(player.global_position)])
	check("kill message is the 049-2 report", messages.size() == 1 and str(messages[0]).begins_with("An active instance of SCP-049-2"), str(messages))
	# 2. senses: facing away and quiet it does not see; loud and visible behind it does
	revive()
	await _reset_world()
	statue.active = false
	player.sound_volume = 0.0
	npc = facility.spawn_049(0.0)
	await get_tree().physics_frame
	npc.state = 2
	npc.idle = 0.0
	npc.state2 = 0.0
	npc.global_position = _clear_spot(player.global_position, 4.0)
	npc._turn_toward(home, 100.0)
	await get_tree().physics_frame
	check("it sees a quiet player in front of it", npc._sees_player(player) == 1, "")
	npc.rotation.y += PI
	check("it does not see a quiet player behind it", npc._sees_player(player) == 0, "")
	player.sound_volume = 4.0
	check("a loud player behind it is noticed", npc._sees_player(player) == 1, "")
	player.sound_volume = 0.0
	npc.global_position = _clear_spot(player.global_position, 9.0) if _clear_spot(player.global_position, 9.0) != Vector3.INF else home + Vector3(0.0, 0.0, -30.0)
	npc._turn_toward(home, 100.0)
	check("beyond 8 units it sees nothing", npc._sees_player(player) == 0, "")
	# 3. idle: it counts down hidden, then appears two rooms from the player
	npc.idle = 70.0
	npc.state2 = 0.0
	await secs(1.8)
	var visible_after := npc.visible
	check("049 appears after its idle time", npc.idle == 0.0 and visible_after, "idle %.1f" % npc.idle)
	var away: float = npc.global_position.distance_to(player.global_position)
	check("it appears a room or two away from the player", away > 6.0 and away < 40.0, "%.1f" % away)
	var order_ok := true
	for record in facility.generator.rooms:
		var last := -1
		for other in facility.adjacent_records(record):
			var index: int = facility.rooms.ADJACENT_ORDER.find(Vector2i(other.grid.x - record.grid.x, other.grid.y - record.grid.y))
			if index < 0:
				continue
			order_ok = order_ok and index >= last
			last = index
	check("adjacent rooms come in Room\\Adjacent order (+x, -z, -x, +z)", order_ok, "")
	var firsts: Array = facility.adjacent_records(facility.record_at(player.global_position))
	if firsts.is_empty():
		log_line("   (no adjacent room to the player's)")
	else:
		var expected: Dictionary = facility.adjacent_records(firsts[0])[0]
		npc.idle = 0.1
		npc.global_position = Vector3(0.0, -500.0, 0.0)
		npc._try_appear(player, facility)
		var centre := Vector2(float(expected.grid.x) * 8.0, -float(expected.grid.y) * 8.0)
		check("at idle 0.1 it appears in the first neighbour of the player's first adjacent room", npc.idle == 0.0 and Vector2(npc.global_position.x, npc.global_position.z).distance_to(centre) < 0.5, "idle %.1f at %s, wanted %s" % [npc.idle, str(npc.global_position), str(centre)])
	# 4. far away: it hops to a waypoint at least 16 from the player or goes idle for a minute
	npc.global_position = player.global_position + Vector3(32.0, 0.0, 0.0)
	var before: Vector3 = npc.global_position
	await secs(0.5)
	check("a far 049 teleports closer or goes idle", npc.idle > 0.1 or npc.global_position.distance_to(before) > 1.0, "idle %.0f moved %.1f" % [npc.idle, npc.global_position.distance_to(before)])
	# 5. out of sight it follows a waypoint route to the player
	await _reset_world()
	statue.active = false
	npc = facility.spawn_049(0.0)
	await get_tree().physics_frame
	var start_point := Vector3.INF
	for w in facility.waypoints():
		var p: Vector3 = w
		var flat := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		if flat > 10.0 and flat < 20.0 and absf(p.y - player.global_position.y) < 1.0 and ray_blocked(player.global_position + Vector3(0, 0.3, 0), p + Vector3(0, 0.3, 0)):
			var route: Dictionary = facility.find_path(p, player.global_position)
			if int(route.status) == 1 and route.points.size() >= 3:
				start_point = p
				break
	check("a waypoint out of sight with a route to the player", start_point != Vector3.INF, "")
	if start_point != Vector3.INF:
		npc.global_position = start_point + Vector3(0, 0.2, 0)
		npc.state = 2
		npc.state2 = 0.0
		npc.path_timer = 70.0 * 5.0 + 1.0
		var begin: float = npc.global_position.distance_to(player.global_position)
		t = 0.0
		var closest := begin
		while t < 30.0 and not player.dead:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			closest = minf(closest, npc.global_position.distance_to(player.global_position))
		check("049 finds its way to the player through the rooms", player.dead or closest < begin - 5.0, "start %.1f closest %.1f dead=%s after %.0fs" % [begin, closest, str(player.dead), t])
	npc.queue_free()
	facility.scp049 = null

func _scn_hazmat049() -> void:
	log_line("== 049 against a hazmat suit")
	statue.active = false
	var hud := get_tree().get_first_node_in_group("hud")
	var slot := _give(hud, "Hazmat Suit", "hazmatsuit")
	GameState.wearing_hazmat = 1
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.5)
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	await get_tree().physics_frame
	npc.global_position = _clear_spot(player.global_position, 0.4) + Vector3(0, 0.05, 0)
	npc._turn_toward(home, 100.0)
	npc.state = 2
	npc.state2 = 140.0
	var t := 0.0
	var peak := 0.0
	while t < 14.0 and not player.dead and int(hud.item_data[slot].get("state2", 0)) < 1:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, GameState.blur_timer)
	check("the contact blurs the view (BlurTimer climbs past 250 and reaches 500 before the suit wears)", peak >= 450.0, "peak %.0f" % peak)
	check("049 wears the hazmat suit down instead of killing at once", not player.dead and int(hud.item_data[slot].get("state2", 0)) == 1, "state2=%d dead=%s after %.1fs" % [int(hud.item_data[slot].get("state2", 0)), str(player.dead), t])
	# on its fourth hit the suit is gone and the next contact kills
	t = 0.0
	while t < 40.0 and not player.dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		npc.state2 = 140.0
	check("the suit is destroyed and then 049 kills", player.dead and GameState.wearing_hazmat == 0 and hud.items[slot].is_empty(), "dead=%s worn=%d" % [str(player.dead), GameState.wearing_hazmat])
	npc.queue_free()
	facility.scp049 = null
	GameState.wearing_hazmat = 0

# The beaked mask is the small surface of the model; its beak is the vertex farthest in front of
# the mask's centre, and that has to be along the node's forward (-Z).
func _scn_facing_049_model() -> void:
	log_line("== 049 model faces its walking direction")
	statue.active = false
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	await get_tree().physics_frame
	var mesh: ArrayMesh = npc._visual.mesh_instance.mesh
	var best_vertices := PackedVector3Array()
	for s in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		if best_vertices.is_empty() or vertices.size() < best_vertices.size():
			best_vertices = vertices
	var sum := Vector3.ZERO
	for v in best_vertices:
		sum += v
	var centre := sum / maxf(best_vertices.size(), 1)
	var extreme := 0.0
	for v in best_vertices:
		var along: float = (npc._visual.global_transform.basis * (v - centre)).z   # world -Z is forward at yaw 0
		if absf(along) > absf(extreme):
			extreme = along
	npc.rotation.y = 0.0
	check("the mask's beak points along the walking direction", extreme < 0.0, "z extreme %.3f" % extreme)
	npc.queue_free()
	facility.scp049 = null

func _scn_scp106() -> void:
	log_line("== SCP-106")
	statue.active = false
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	# outside the map: he sinks under the player's floor and stays hidden while the counter runs
	var npc: CharacterBody3D = facility.spawn_106(2000.0)
	check("106's speed follows the difficulty (NPCSpeedChange)", is_equal_approx(npc.speed, 1.2 / 100.0 * 70.0 * GameState.npc_speed_factor()), "%.3f" % npc.speed)
	await secs(2.0)
	check("106 waits hidden below the map while idle", not npc.visible and npc.global_position.y < player.global_position.y - 3.0, "y %.1f vs %.1f" % [npc.global_position.y, player.global_position.y])
	check("his counter is paused in a disable-decals room (the start chamber)", npc.state == 2000.0, "%.0f" % npc.state)
	var counting_room: FacilityRoom = null
	for key in facility.rooms.built:
		var candidate: FacilityRoom = facility.rooms.built[key]
		if candidate.room_name != "gatea" and not facility.generator.room_disables_decals(candidate.room_name) and facility.room_name_at(candidate.global_position + Vector3(0.0, 1.5, 0.0)) == candidate.room_name:
			counting_room = candidate
			break
	if counting_room != null:
		place_player(counting_room.global_position + Vector3(0.0, 1.5, 0.0))
		await secs(2.0)
		check("his counter runs down in an ordinary room", npc.state < 2000.0, "%.0f in %s" % [npc.state, counting_room.room_name])
		place_player(home)
		await secs(0.6)
	# attacking: he surfaces under the player and climbs out
	npc.state = 0.0
	var t := 0.0
	while t < 4.0 and npc.frame < 125.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var flat := Vector2(npc.global_position.x - player.global_position.x, npc.global_position.z - player.global_position.z).length()
	check("106 comes up under the player", npc.visible and flat < 0.5, "%.2f m away" % flat)
	check("he rises through frames 110-259 slowly", npc.frame > 110.0 and npc.frame < 259.0, "frame %.0f" % npc.frame)
	var player_start := player.global_position
	npc.frame = 255.0
	npc._visual.set_frame(255.0)
	t = 0.0
	while t < 3.0 and npc.state > -10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("once risen he starts hunting (state -10)", npc.state <= -10.0, "state %.1f" % npc.state)
	# he walks away from where he surfaced, then grabs: put him 4 m off, the player stays still
	npc.global_position = _clear_spot(player.global_position, 4.0) + Vector3(0, 0.05, 0)
	npc._turn_toward(player.global_position, 100.0, 1.0)
	var began := npc.global_position.distance_to(player.global_position)
	await secs(2.0)
	var closer: float = npc.global_position.distance_to(player.global_position)
	check("106 walks at the player (about 0.84 m/s)", closer < began - 1.0 and closer > began - 3.5, "%.2f -> %.2f" % [began, closer])
	check("his walk animation plays", npc.frame >= 284.0 and npc.frame <= 333.0, "frame %.0f" % npc.frame)
	t = 0.0
	while t < 12.0 and player.fall_timer >= 0.0 and not player.dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("his touch drops the player (FallTimer)", player.fall_timer < 0.0 or player.dead, "fall %.0f after %.1fs" % [player.fall_timer, t])
	var eye_before: float = player.camera.position.y
	await secs(1.0)
	check("the view sinks toward the floor while falling", player.camera.position.y < eye_before or player.dead, "%.2f -> %.2f" % [eye_before, player.camera.position.y])
	check("while falling the camera rides the Head, turned up to 45 degrees off the view (Main.bb 4441, NPCs.bb 1150)", player.dead or (player._head_view and absf(wrapf(player.head_yaw - player.death_yaw, -180.0, 180.0)) <= 45.0), "head %.0f, view %.0f" % [player.head_yaw, player.death_yaw])
	t = 0.0
	while t < 8.0 and not (facility.pocket != null and facility.pocket.player_inside) and not player.dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("after 250 frames the pocket dimension takes them", facility.pocket != null and facility.pocket.player_inside and not player.dead and player.fall_timer == 0.0, "t=%.1fs" % t)
	npc.queue_free()
	facility.scp106 = null

# 106's toes (the lowest vertices stick out in front of the heel) point along the walking direction.
func _scn_facing_106_model() -> void:
	log_line("== 106 model faces his walking direction")
	statue.active = false
	var npc: CharacterBody3D = facility.spawn_106(5000.0)
	await get_tree().physics_frame
	npc.rotation.y = 0.0
	# NPCs.bb turns his model with the collider and nothing more (RotateEntity nobj, 0, EntityYaw(nCollider), 0): the
	# model's own front is the way he walks, so it takes no extra turn here (the guards and 173 have a -180 there)
	check("106's model takes no half turn (RotateEntity obj, 0, EntityYaw(collider), 0)", absf(npc._visual.rotation.y) < 0.001, "visual yaw %.3f" % npc._visual.rotation.y)
	var eyes: MeshInstance3D = npc._eyes
	var eye_material := eyes.material_override as ShaderMaterial
	check("106's eyes are a free sprite (SpriteViewMode 2), not a camera billboard", not eye_material.get_shader_parameter("billboard"), "")
	check("and single-sided like a Blitz sprite", eye_material.get_shader_parameter("single_sided") == true, "")
	for yaw in [0.0, 1.0, -2.3]:
		npc.rotation.y = yaw
		var face_dir: Vector3 = npc.global_basis * Vector3(0.0, 0.0, -1.0)
		var front: Vector3 = eyes.global_basis * Vector3(0.0, 0.0, 1.0)
		check("the eyes show from the front of his face at yaw %.1f" % yaw, front.dot(face_dir) > 0.999, "dot %.3f" % front.dot(face_dir))
	npc.queue_free()
	facility.scp106 = null

func _route_walkable(route_ids: PackedInt64Array, graph: Object) -> bool:
	var space := get_viewport().world_3d.direct_space_state
	var level: float = graph.astar.get_point_position(route_ids[0]).y
	var previous := Vector3.INF
	for id in route_ids:
		var p: Vector3 = graph.astar.get_point_position(id)
		if absf(p.y - level) > 0.6:
			return false
		var samples: Array[Vector3] = [p]
		if previous != Vector3.INF:
			for k in 1:
				samples.append(previous.lerp(p, 0.5))
			samples.append(previous.lerp(p, 0.25))
			samples.append(previous.lerp(p, 0.75))
		for sample in samples:
			var q := PhysicsRayQueryParameters3D.create(sample + Vector3(0, 0.5, 0), sample + Vector3(0, -1.2, 0))
			q.collision_mask = 1
			if space.intersect_ray(q).is_empty():
				return false
		previous = p
	return true

func _pocket_player_feet() -> float:
	return player.global_position.y

func _scn_pocket() -> void:
	log_line("== pocket dimension")
	statue.active = false
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.5)
	var old_man: CharacterBody3D = facility.spawn_106(5000.0)
	await get_tree().physics_frame
	old_man.state = 250.0     # what taking the player sets: hunting there, his touch would kill (MoveToPocketDimension)
	var models := func() -> int: return facility.pocket.get_children().filter(func(n: Node) -> bool: return n.has_meta("visual")).size()
	var built_parts: int = models.call()
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	await secs(1.5)
	check("entering does not build the dimension again over the one built with the map", models.call() == built_parts, "%d models, %d at load" % [models.call(), built_parts])
	var gap := _pocket_note_gap()
	check("the burnt note has fallen to the floor (CreateItem at 0.5 drops it)", gap < 0.05, "%.2f above the floor" % gap)
	check("106 takes the player into the pocket dimension", pocket.player_inside and facility.room_name_at(player.global_position) == "pocketdimension", "room '%s' at %s" % [facility.room_name_at(player.global_position), str(player.global_position)])
	check("the player stands on the starting room's floor", absf(player.global_position.y) < 0.4 and player.is_on_floor(), "feet y %.2f, on floor %s" % [player.global_position.y, str(player.is_on_floor())])
	check("the dimension adds half an injury", GameState.injuries >= 0.5, "%.2f" % GameState.injuries)
	check("the pocket dimension music takes over", GameState.music_override == "PD", GameState.music_override)
	check("the dimension is not a place NPCs can follow", not facility.reachable_room(player.global_position))
	var room_scale_ok: bool = pocket._room_visual.scale.y != 1.0
	check("the starting room breathes (scale changes)", room_scale_ok, "%.3f" % pocket._room_visual.scale.y)
	var tunnel_overlap := _coplanar_overlap(pocket._hallways[0].mesh.get_faces())
	check("the tunnel model has no faces drawn twice in one plane (its floor slab fought the walls and flashed)", tunnel_overlap < 0.5, "%.3f square model units" % tunnel_overlap)
	# the room's plate under its floor lies at the height of the tunnels' floors, over the diagonal tunnels' mouths
	var room_to_model := Transform3D(Basis.from_scale(Vector3.ONE / MeshLoader.ROOM_SCALE), Vector3.ZERO)
	var tunnel_faces := PackedVector3Array()
	for hall: MeshInstance3D in pocket._hallways:
		var holder := hall.get_parent() as Node3D
		tunnel_faces.append_array(room_to_model * holder.transform * Transform3D(Basis.from_scale(Vector3.ONE * MeshLoader.ROOM_SCALE), Vector3.ZERO) * hall.mesh.get_faces())
	var room_overlap := _coplanar_overlap(room_to_model * pocket._room_visual.mesh.get_faces(), tunnel_faces)
	check("the starting room draws no floor where a tunnel's floor lies (the two stretch at their own rates and fought)", room_overlap < 50.0, "%.1f square model units" % room_overlap)
	var terrain_visual: MeshInstance3D = pocket._terrain.get_meta("visual") if pocket._terrain != null and pocket._terrain.has_meta("visual") else null
	check("the terrain is not run through the coplanar trim (it has no overlap, and the trim cost 35 s of the load)", terrain_visual != null and terrain_visual.mesh == MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/pocketdimensionterrain.b3d")), "")
	log_line("   build_all took %.0f ms" % facility.rooms.build_all_ms)
	old_man.state = 5000.0
	old_man.idle = false
	await secs(1.0)
	# 106 circles the starting room while his counter is positive
	var radius_a := Vector2(old_man.global_position.x - pocket.position.x, old_man.global_position.z - pocket.position.z).length()
	check("106 circles the starting room at 5-7 m", old_man.visible and radius_a > 4.5 and radius_a < 7.5 and old_man.idle, "r %.2f visible %s idle %s" % [radius_a, str(old_man.visible), str(old_man.idle)])
	await shot("pocket_start")
	# stepping out of the starting room past 1700 puts the player somewhere else
	var far: Vector3 = pocket.position + Vector3(1700.0 * 8.0 / 2048.0 + 0.5, 0.0, 0.0)
	pocket._put(player, Vector3(far.x, 0.0, far.z))
	var before: Vector3 = player.global_position
	var moved := false
	var waited := 0.0
	while waited < 2.0 and not moved:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		moved = player.global_position.distance_to(before) > 1.0 or pocket.event_state2 != 0 or not pocket.player_inside
	check("walking out of the starting room sends the player somewhere (state %d)" % pocket.event_state2, moved, "from %s to %s" % [str(before), str(player.global_position)])
	if not pocket.player_inside:
		facility.enter_pocket(player)
	old_man.state = 5000.0    # leaving set his counter to 250: back inside he would surface under the player and kill them
	pocket.event_state2 = 1
	pocket.event_state3 = 0
	pocket._put_collider(player, 0.0, 0.5, 32.0)
	await secs(1.0)
	var pillar_a: Vector3 = pocket._pillars[0].global_position
	await secs(1.0)
	check("the flying pillars move", pocket._pillars[0].global_position.distance_to(pillar_a) > 0.05, "%.3f" % pocket._pillars[0].global_position.distance_to(pillar_a))
	check("the throne room has a floor under the player", player.is_on_floor(), "y %.2f" % player.global_position.y)
	await shot("pocket_throne")
	pocket._eyes.visible = true
	await secs(0.2)
	# 106's eyes: close enough, the sanity drops and the injuries rise
	var eyes: Vector3 = pocket.B(0.0, 1376.0 * 8.0 / 2048.0, 32.0 - 2848.0 * 8.0 / 2048.0)
	var injuries_before := GameState.injuries
	pocket._put(player, Vector3(eyes.x, 0.05, eyes.z - 2.5))
	await secs(1.5)
	check("106's eyes within 3.9 m hurt and build up the stare", GameState.injuries > injuries_before + 0.01 and pocket.event_str > 0.0, "inj %.3f -> %.3f stare %.3f" % [injuries_before, GameState.injuries, pocket.event_str])
	await shot("pocket_eyes")
	# crouching there sinks the player into the trenches
	player.crouching = true
	await secs(0.6)
	check("crouching in front of 106 drops the player into the trenches", pocket._collider_y(player) > 5.0 and not player.crouching, "y %.2f crouching %s" % [pocket._collider_y(player), str(player.crouching)])
	await secs(1.5)
	check("the trench plane flies over", pocket._plane.visible, "")
	check("the trench music plays", GameState.music_override == "PDTrench", GameState.music_override)
	await shot("pocket_trench")
	# falling into the sinkhole lands in the exit room
	pocket._put_collider(player, 0.0, 8.0, 32.0)
	await secs(1.0)
	check("the sinkhole leads to the exit room", pocket._collider_y(player) < 0.5 and pocket.event_state2 == 1, "y %.2f state2 %d" % [pocket._collider_y(player), pocket.event_state2])
	await shot("pocket_exit_room")
	# the swirl in the exit room is the way out
	var swirl: Vector3 = pocket.B(1024.0 * 8.0 / 2048.0, 0.0, 32.0)
	pocket._put(player, Vector3(swirl.x, player.global_position.y, swirl.z))
	var left := false
	waited = 0.0
	while waited < 3.0 and pocket.player_inside:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("the swirl leads back to the facility", not pocket.player_inside and facility.room_name_at(player.global_position) != "pocketdimension", "room '%s' at %s" % [facility.room_name_at(player.global_position), str(player.global_position)])
	check("the exit through room2shaft flickers the lights (LightBlink 5)", GameState.light_blink > 4.0, "%.2f" % GameState.light_blink)
	check("the player lands on a floor", true, "y %.2f" % player.global_position.y)
	await secs(1.0)
	check("they do not fall through the map after the exit", player.global_position.y > -1.0, "y %.2f" % player.global_position.y)
	old_man.queue_free()
	facility.scp106 = null

# A start and a target in ordinary rooms (not the start chamber, which has ledges that line-of-sight
# links hop over), 15-32 units apart and joined by a route a walker can follow.
# Area (square model units) where two of the triangles lie in one plane facing the same way: drawn twice, they z-fight.
# With `against`, only the pairs of one of `faces` and one of `against` count.
func _coplanar_overlap(faces: PackedVector3Array, against := PackedVector3Array()) -> float:
	var tris := _plane_tris(faces)
	var others := _plane_tris(against) if not against.is_empty() else tris
	var total := 0.0
	for x in tris.size():
		for y in (range(x + 1, tris.size()) if against.is_empty() else range(others.size())):
			var p: Array = tris[x]
			var q: Array = others[y]
			if p[3].dot(q[3]) < 0.999 or absf(p[3].dot(q[0] - p[0])) > 0.01:
				continue
			var drop := 0 if absf(p[3].x) >= maxf(absf(p[3].y), absf(p[3].z)) else (1 if absf(p[3].y) >= absf(p[3].z) else 2)
			var flat := func(t: Array) -> PackedVector2Array:
				var out := PackedVector2Array()
				for k in 3:
					var v: Vector3 = t[k]
					out.append(Vector2(v.y, v.z) if drop == 0 else (Vector2(v.x, v.z) if drop == 1 else Vector2(v.x, v.y)))
				if Geometry2D.is_polygon_clockwise(out):
					out.reverse()
				return out
			for piece in Geometry2D.intersect_polygons(flat.call(p), flat.call(q)):
				var area := 0.0
				for k in piece.size():
					area += piece[k].cross(piece[(k + 1) % piece.size()])
				total += absf(area) * 0.5
	return total

# How far the pocket dimension's burnt note is above the floor under it (INF without a note or a floor).
func _pocket_note_gap() -> float:
	for child in facility.pocket.get_children():
		if str(child.get_meta("fill_id", "")) == FacilityMap.PocketDimension.NOTE_ID:
			var under := PhysicsRayQueryParameters3D.create(child.global_position + Vector3.UP * 0.1, child.global_position + Vector3.DOWN * 2.0)
			under.collision_mask = 1
			var hit := player.get_world_3d().direct_space_state.intersect_ray(under)
			return child.global_position.y - hit.position.y if not hit.is_empty() else INF
	return INF

func _plane_tris(faces: PackedVector3Array) -> Array:
	var tris: Array = []
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		if normal.length() > 1e-6:
			tris.append([faces[i], faces[i + 1], faces[i + 2], normal.normalized()])
	return tris

func _find_walkable_pair() -> Dictionary:
	# routes are judged on the floor under them, and hidden rooms have no collision: the walkers get every room solid
	facility.drawing.enabled = false
	facility.drawing.show_all_rooms()
	var graph: Object = facility.graph
	var start_key: String = facility.generator.start_room.key
	var ids: Array = graph._owner_of.keys()
	var start_id := -1
	var end_id := -1
	var best := 0.0
	var target := Vector3.ZERO
	for a in ids:
		if graph._owner_of[a] == start_key or graph._is_door[a]:
			continue
		var pa: Vector3 = graph.astar.get_point_position(a)
		if absf(pa.y) > 2.0:
			continue
		for b2 in ids:
			if graph._owner_of[b2] == start_key or b2 == a:
				continue
			var pb: Vector3 = graph.astar.get_point_position(b2)
			var d: float = Vector2(pb.x - pa.x, pb.z - pa.z).length()
			if d < 15.0 or d > 32.0 or absf(pb.y - pa.y) > 1.5 or d <= best:
				continue
			var route_ids: PackedInt64Array = graph.astar.get_id_path(a, b2)
			if route_ids.is_empty():
				continue
			var through_start := false
			var length := 0.0
			for k in route_ids.size():
				if graph._owner_of[route_ids[k]] == start_key:
					through_start = true
				if k > 0:
					length += graph.astar.get_point_position(route_ids[k]).distance_to(graph.astar.get_point_position(route_ids[k - 1]))
			if length > d * 2.0:
				continue
			if not through_start and _route_walkable(route_ids, graph):
				best = d
				start_id = a
				end_id = b2
				target = pb
	return {"start_id": start_id, "end_id": end_id, "target": target}

func _clear_humans() -> void:
	for human in facility.humans.duplicate():
		facility.remove_human(human)

func _scn_guard() -> void:
	log_line("== guards")
	statue.active = false
	var Human = load("res://scripts/npc/human_npc.gd")
	var Gunfire = load("res://scripts/npc/gunfire.gd")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	# state 1: aims at the player and shoots every 7 frames
	var guard: CharacterBody3D = facility.spawn_human(Human.Kind.GUARD, _clear_spot(player.global_position, 6.0) + Vector3(0, 0.05, 0))
	await get_tree().physics_frame
	guard.state = 1
	GameState.god_mode = true     # count the shots without dying
	await secs(2.2)
	var to_player: Vector3 = player.global_position - guard.global_position
	var facing_error: float = absf(wrapf(guard.rotation.y - atan2(-to_player.x, -to_player.z), -PI, PI))
	check("a guard in state 1 turns to face the player", facing_error < 0.2, "%.2f rad off" % facing_error)
	check("he fires every 7 frames (about 10 a second)", guard.shots_fired >= 12 and guard.shots_fired <= 26, "%d shots in 2.2 s" % guard.shots_fired)
	check("he plays the aim and shoot frames", guard.frame >= 245.0 and guard.frame <= 344.0, "frame %.0f" % guard.frame)
	GameState.god_mode = false
	var rounds := 400
	var hits := 0
	GameState.wearing_vest = 0
	for i in rounds:
		revive()
		GameState.injuries = 0.0
		var before: int = Gunfire.hits
		Gunfire.shoot(guard, guard.global_position + Vector3(0, 1.0, 0), 0.4, "test shot")
		if Gunfire.hits > before:
			hits += 1
	var rate := float(hits) / float(rounds)
	check("a shot with 0.4 accuracy lands about 40 percent of the time", rate > 0.28 and rate < 0.52, "%.3f over %d shots" % [rate, rounds])
	GameState.wearing_vest = 2
	var vest_messages := {}
	for i in 120:
		GameState.injuries = 0.0
		revive()
		Gunfire.shoot(guard, guard.global_position + Vector3(0, 1.0, 0), 1.0, "test shot")
		vest_messages[Gunfire.last_message] = true
	check("with the fine vest a hit is mostly absorbed", vest_messages.has("A bullet hit your chest. The vest absorbed most of the damage."), str(vest_messages.keys()))
	check("a hit never leaves more than 4 injuries", GameState.injuries <= 4.0, "%.2f" % GameState.injuries)
	# Shoot(): the flash is flash.jpg (particle 1), 0.08-0.1, fading 0.15 a frame for 5 frames; TurnEntity Camera only twitches the view
	revive()
	var aim_pitch: float = player.user_pitch
	var aim_yaw: float = player.rotation.y
	var flashes_before: int = facility.particles._items.filter(func(p): return p.image == 1).size()
	Gunfire.shoot(guard, guard.global_position + Vector3(0, 1.0, 0), 1.0, "test shot")
	var flashes: Array = facility.particles._items.filter(func(p): return p.image == 1)
	var flash = null if flashes.size() <= flashes_before else flashes[-1]
	check("a shot's muzzle flash is a fading flash.jpg particle", flash != null and flash.size >= 0.08 and flash.size <= 0.1 and is_equal_approx(flash.a_change, -0.15) and flash.lifetime == 5.0, "" if flash == null else "size %.3f, fade %.2f, life %.0f" % [flash.size, flash.a_change, flash.lifetime])
	check("a hit twitches the view but keeps the aim", player.dead or (player.user_pitch == aim_pitch and player.rotation.y == aim_yaw), "pitch %.2f -> %.2f, yaw %.4f -> %.4f" % [aim_pitch, player.user_pitch, aim_yaw, player.rotation.y])
	GameState.wearing_vest = 0
	revive()
	GameState.injuries = 0.0
	Gunfire.shoot(guard, guard.global_position + Vector3(0, 1.0, 0), 0.0, "Subject D-9341. Gunshot wound to the head.", true)
	check("an insta-kill shot ends the run with its message", player.dead, "")
	revive()
	# state 4 notices the player in front
	guard.state = 4
	# his yaw is picked so that WrapAngle(yaw - DeltaYaw) = 45 (the original's odd rule: 2 * yaw - bearing)
	var bearing := rad_to_deg(atan2(-(player.global_position.x - guard.global_position.x), -(player.global_position.z - guard.global_position.z)))
	guard.rotation.y = deg_to_rad((bearing + 45.0) / 2.0)
	guard.angle = (bearing + 45.0) / 2.0
	# the original notices the player when WrapAngle(yaw - DeltaYaw) < 90 and he is in sight
	var notices: bool = fposmod(rad_to_deg(guard.rotation.y) - rad_to_deg(guard._yaw_to(player.global_position)), 360.0) < 90.0 and guard._sees(player)
	guard.angle = rad_to_deg(guard.rotation.y)
	var waited := 0.0
	while waited < 3.0 and guard.state == 4:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	GameState.god_mode = true
	check("an idle guard (state 4) that faces the player in sight starts shooting when the original's angle rule allows (%s)" % str(notices), guard.state == 1 or not notices, "state %d" % guard.state)
	guard.state = 7
	await secs(0.3)
	check("state 7 plays the idle frames 77-201", guard.frame >= 77.0 and guard.frame <= 201.0, "frame %.0f" % guard.frame)
	guard.state = 13
	await secs(0.3)
	check("state 13 plays the standing frames 202-244", guard.frame >= 202.0 and guard.frame <= 244.0, "frame %.0f" % guard.frame)
	GameState.god_mode = false
	_clear_humans()
	# walking a path (state 14): arrives and stands
	var pair: Dictionary = _find_walkable_pair()
	if pair.start_id < 0:
		check("a route for the guard exists", false, "")
		return
	var graph: Object = facility.graph
	var start_pos: Vector3 = graph.astar.get_point_position(pair.start_id)
	var walker: CharacterBody3D = facility.spawn_human(Human.Kind.GUARD, start_pos + Vector3(0, 0.1, 0))
	await get_tree().physics_frame
	var status: int = walker.find_path_to(pair.target)
	check("a guard finds a route", status == 1, "status %d" % status)
	var relocked: Array = []
	for route_point in walker.path:
		for door_node in facility.doors_near(route_point, 0.5):
			if door_node.locked or door_node.keycard != 0 or not door_node.code.is_empty():
				relocked.append([door_node, door_node.locked, door_node.keycard, door_node.code])
				door_node.locked = false
				door_node.keycard = 0
				door_node.code = ""
	walker.state = 14
	waited = 0.0
	while waited < 70.0 and walker.state == 14:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var left := Vector2(walker.global_position.x - pair.target.x, walker.global_position.z - pair.target.z).length()
	check("a guard following a path (state 14) reaches its end and stands (state 13)", walker.state == 13 and left < 1.5, "state %d, %.2f from the target after %.1fs" % [walker.state, left, waited])
	check("his steps are heard", walker.steps_played >= 4, "%d" % walker.steps_played)
	for saved_door in relocked:
		saved_door[0].locked = saved_door[1]
		saved_door[0].keycard = saved_door[2]
		saved_door[0].code = saved_door[3]
	_clear_humans()

func _scn_classd() -> void:
	log_line("== class D")
	statue.active = false
	var Human = load("res://scripts/npc/human_npc.gd")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var d: CharacterBody3D = facility.spawn_human(Human.Kind.CLASS_D, _clear_spot(player.global_position, 4.0) + Vector3(0, 0.05, 0), 3)
	await get_tree().physics_frame
	await secs(0.4)
	check("a Class D idles with frames 210-235", d.frame >= 210.0 and d.frame <= 235.0, "frame %.0f" % d.frame)
	d.state = 1
	var began: Vector3 = d.global_position
	await secs(2.0)
	check("a walking Class D plays 236-260", d.frame >= 236.0 and d.frame <= 260.0, "frame %.0f" % d.frame)
	var walked := Vector2(d.global_position.x - began.x, d.global_position.z - began.z).length()
	check("he walks at about 0.015 per frame (1 m/s)", walked > 0.4 and walked < 2.6, "%.2f m in 2 s" % walked)
	d.state = 2
	began = d.global_position
	await secs(2.0)
	check("a running Class D plays 301-319", d.frame >= 301.0 and d.frame <= 319.0, "frame %.0f" % d.frame)
	var ran := Vector2(d.global_position.x - began.x, d.global_position.z - began.z).length()
	check("he runs at about 0.03 per frame", ran > 1.0, "%.2f m in 2 s" % ran)
	d.state = 8
	d.set_frame(19.0)
	await secs(0.3)
	check("frame 19 marks him dead", d.is_dead, "")
	check("the scientist picture replaces the Class D skin", d.texture_id == 3, "%d" % d.texture_id)
	_clear_humans()

func _room2sl_setup() -> Dictionary:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2sl":
			record = candidate
	if record.is_empty():
		return {}
	var room: Node3D = facility.rooms.get_room(record)
	var hall := room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0))
	place_player(hall)
	await secs(1.5)
	return {"room": room, "record": record}

# A spot behind the room's nearer edge door, `distance` out: far from the monitor and out of 049's sight.
func _outside_spot(room: Node3D, distance: float) -> Vector3:
	var doors: Array = facility.room_edge_doors(room)
	var cell: Vector3 = room.object_point(7)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(cell) < b.global_position.distance_to(cell))
	var away: Vector3 = doors[0].global_position - room.global_position
	away.y = 0.0
	return doors[0].global_position + away.normalized() * distance + Vector3(0.0, 0.3, 0.0)

func _face_node(node: Node3D, point: Vector3) -> void:
	node.rotation.y = atan2(-(point.x - node.global_position.x), -(point.z - node.global_position.z))

func _scn_mtf() -> void:
	log_line("== MTF units")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))    # parked: only the 173 section brings it back
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var spot: Vector3 = _spot_near(player.global_position, 5.0)
	var leader: CharacterBody3D = facility.mtf.spawn(spot + Vector3(0, 0.05, 0))
	var follower: CharacterBody3D = facility.mtf.spawn(spot + Vector3(0.4, 0.05, 0), leader)
	await get_tree().physics_frame
	check("an MTF unit's initial speed follows the difficulty (NPCSpeedChange)", is_equal_approx(follower.speed, 0.02 * GameState.npc_speed_factor()), "%.4f" % follower.speed)
	_face_node(leader, player.global_position)
	leader.angle = leader.rotation.y
	check("a unit starts in the walking frames (488-522)", leader.frame >= 488.0 and leader.frame <= 522.0, "frame %.0f" % leader.frame)
	# seeing the player in front within 8: state 1 and a shout
	await secs(0.3)
	check("a unit that sees the player starts searching (state 1)", leader.state == 1, "state %d" % leader.state)
	var shouted := false
	for line in leader.voices:
		if line.contains("Stop") or line.contains("ThereHeIs") or line.contains("ClassD"):
			shouted = true
	check("and shouts at him", shouted, str(leader.voices))
	check("the search lasts 15 seconds (45 if over a camera)", leader.state2 > 70.0 * 12.0 and leader.state2 <= 70.0 * 15.0, "%.0f" % leader.state2)
	# within 4 he shoots, every 7 frames, and calls the others
	GameState.god_mode = true
	leader.global_position = _spot_near(player.global_position, 3.0) + Vector3(0, 0.05, 0)
	follower.global_position = leader.global_position + Vector3(0.5, 0, 0)
	follower.state = 0
	leader.state = 1
	leader.state2 = 70.0 * 15.0
	leader.reload = 0.0
	await secs(2.0)
	check("a unit within 4 of the player shoots", leader.shots_fired >= 3, "%d shots in 2 s" % leader.shots_fired)
	check("and calls a neighbour", follower.state == 1, "state %d" % follower.state)
	check("the follower's search timer is the leader's", absf(follower.state2 - leader.state2) < 70.0 * 3.0, "%.0f vs %.0f" % [follower.state2, leader.state2])
	GameState.god_mode = false
	# losing him: after state2 runs out the leader says so and goes back to wandering
	place_player(home + Vector3(0, 0, 0))
	leader.global_position = _spot_near(player.global_position, 7.0) + Vector3(0, 0.05, 0)
	leader.rotation.y += PI    # looking away
	leader.state = 1
	leader.state2 = 20.0
	leader.voices.clear()
	var went_back := false
	for i in 70:
		await get_tree().physics_frame
		if leader.state == 0:
			went_back = true
	check("a lost target sends it back to wandering (state 0)", went_back, "state %d" % leader.state)
	var lost_line := false
	for line in leader.voices:
		if line.contains("argetlost") or line.contains("argetLost"):
			lost_line = true
	check("the leader announces it", lost_line, str(leader.voices))
	# 173 in sight: state 2, the statue is held, and boxed after 15 seconds beside it
	leader.state = 0
	follower.state = 0
	statue.global_position = _spot_near(leader.global_position, 3.0) + Vector3(0, 0.05, 0)
	_face_node(statue, leader.global_position)
	_face_node(leader, statue.global_position)
	follower.global_position = leader.global_position + Vector3(0.5, 0.0, 0.0)
	leader.voices.clear()
	await secs(0.4)
	check("a unit that sees 173 looks at it (state 2)", leader.state == 2, "state %d" % leader.state)
	check("the others join him", follower.state == 2, "state %d" % follower.state)
	check("173 is held while he watches", statue.idle == 1, "idle %d" % statue.idle)
	leader.global_position = statue.global_position + Vector3(0.5, 0.0, 0.0)
	leader.state3 = 70.0 * 15.0 - 20.0
	await secs(1.0)
	check("after 15 seconds beside it 173 is boxed (idle 2)", statue.idle == 2, "idle %d" % statue.idle)
	statue.active = true
	var bob_min := 99.0
	var bob_max := -99.0
	for i in 12:
		await secs(0.1)
		bob_min = minf(bob_min, statue.visual.position.y)
		bob_max = maxf(bob_max, statue.visual.position.y)
	check("boxed 173 floats at 0.35..0.39 and bobs", bob_min >= 0.349 and bob_max <= 0.391 and bob_max - bob_min > 0.005, "%.3f..%.3f idle %d active %s" % [bob_min, bob_max, statue.idle, statue.active])
	check("the box shows only while it is boxed", statue.box.visible, "")
	statue.active = false
	var box_line := false
	for line in leader.voices:
		if line.contains("Box"):
			box_line = true
	check("he says so", box_line, str(leader.voices))
	statue.idle = 0
	statue.target_node = null
	await secs(0.1)
	check("the box hides and the statue settles when released", not statue.box.visible and statue.visual.position.y == 0.0, "")
	place_statue(Vector3(0.0, -80.0, 0.0))
	follower.state = 0
	# 106 or 049 seen: back away from it
	var stand_in := Node3D.new()
	get_tree().root.add_child(stand_in)
	# a spot with room to back away: clear 1.5 ahead and 3 behind in some direction
	var open_dir := Vector3(1.0, 0.0, 0.0)
	var open_from: Vector3 = _spot_near(player.global_position, 3.0)
	for step in 16:
		var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
		if not ray_blocked(open_from + Vector3(0, 0.5, 0), open_from + dir * 1.8 + Vector3(0, 0.5, 0)) and not ray_blocked(open_from + Vector3(0, 0.5, 0), open_from - dir * 3.0 + Vector3(0, 0.5, 0)):
			open_dir = dir
			break
	leader.global_position = open_from + Vector3(0, 0.05, 0)
	leader.velocity = Vector3.ZERO
	stand_in.global_position = open_from + open_dir * 1.5
	leader.state = 4
	leader.target = stand_in
	leader.state2 = 70.0 * 15.0
	leader.state3 = 0.0
	var gap_before: float = leader.global_position.distance_to(stand_in.global_position)
	await secs(1.2)
	var gap_after: float = leader.global_position.distance_to(stand_in.global_position)
	check("a unit near SCP-106 or 049 backs away (state 4)", gap_after > gap_before + 0.15, "%.2f -> %.2f" % [gap_before, gap_after])
	stand_in.queue_free()
	# a unit that appears near a motionless 173 that faces away does not react to it (the first look used to count as movement)
	_clear_mtf()
	var fresh_spot: Vector3 = _spot_near(player.global_position, 3.0)
	statue.global_position = fresh_spot + Vector3(1.5, 0.05, 0.0)
	var newcomer: CharacterBody3D = facility.mtf.spawn(fresh_spot + Vector3(0, 0.05, 0))
	newcomer.no_target = true
	_face_node(statue, statue.global_position + (statue.global_position - newcomer.global_position))
	_face_node(newcomer, newcomer.global_position + (newcomer.global_position - statue.global_position))
	await secs(0.4)
	check("a new unit near a still 173 that does not face it keeps wandering", newcomer.state == 0, "state %d" % newcomer.state)
	place_statue(Vector3(0.0, -80.0, 0.0))
	_clear_mtf()
	# doors on the way open for it and shut after five seconds
	var door: Node3D = null
	for node in facility.doors_near(home, 14.0):
		if not node.big and node.leaf_a != null:
			door = node
			break
	if door != null:
		var was_open: bool = door.open
		door.open = false
		door.npc_open(70.0 * 1.0)
		check("an MTF-opened door opens", door.open, "")
		await secs(3.2)    # about 1.3 s to open, then the 1 s timer
		check("and shuts after its timer", not door.open, "")
		# a timer left over from an MTF opening must not shut a door the player has used since
		door.npc_open(300.0)
		await secs(1.6)
		door.toggle(false)     # closed by hand
		await secs(1.8)
		door.toggle(false)     # opened by hand
		check("a hand-opened door has no leftover timer", door.close_timer == 0.0, "%.0f" % door.close_timer)
		door.open = was_open
		door.close_timer = 0.0
	_clear_mtf()

# A clear floor spot about `distance` from the centre (nearer if the room is tight).
func _spot_near(center: Vector3, distance: float) -> Vector3:
	for shrink in [1.0, 0.8, 0.6, 0.45, 0.3]:
		var spot: Vector3 = _clear_spot(center, distance * shrink)
		if spot != Vector3.INF:
			return spot
	return center + Vector3(1.0, 0.0, 0.0)

func _clear_mtf() -> void:
	for unit in facility.mtf.units.duplicate():
		facility.mtf.remove(unit)

# Pictures of the MTF unit: walking toward the camera, standing, aiming, dead.
func _scn_mtfshots() -> void:
	log_line("== MTF pictures")
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var spot: Vector3 = _spot_near(player.global_position, 3.0)
	var unit: CharacterBody3D = facility.mtf.spawn(spot + Vector3(0, 0.05, 0))
	unit.state = 7
	unit.state2 = rad_to_deg(atan2(-(player.global_position.x - spot.x), -(player.global_position.z - spot.z)))
	await secs(0.6)
	face_point(unit.global_position + Vector3(0, 0.9, 0))
	await secs(0.2)
	await shot("mtf_shooting")
	unit.state = 0
	unit.idle = 70.0 * 20.0
	unit.set_frame(500.0)
	_face_node(unit, player.global_position)
	unit.angle = unit.rotation.y
	await secs(0.3)
	await shot("mtf_front")
	unit.rotation.y += PI * 0.5
	unit.angle = unit.rotation.y
	await secs(0.3)
	await shot("mtf_side")
	unit.rotation.y += PI * 0.5
	unit.angle = unit.rotation.y
	await secs(0.3)
	await shot("mtf_back")
	unit.is_dead = true
	await secs(0.5)
	await shot("mtf_dead")
	_clear_mtf()

# A patrol in the real facility: the leader goes from room to room and the others stay with him.
func _scn_mtfwalk() -> void:
	log_line("== MTF patrol")
	var door_states: Dictionary = {}    # the patrol opens doors that then shut: put them back afterwards
	for node in get_tree().get_nodes_in_group("door"):
		door_states[node] = node.open
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var pair: Dictionary = _find_walkable_pair()
	if pair.start_id < 0:
		check("a route for the patrol exists", false, "")
		return
	var graph: Object = facility.graph
	var start_pos: Vector3 = graph.astar.get_point_position(pair.start_id)
	place_player(start_pos + Vector3(0.0, 0.3, 0.0))   # the units do not see him: no_target
	GameState.god_mode = true
	await secs(0.6)
	var leader: CharacterBody3D = facility.mtf.spawn(start_pos + Vector3(0, 0.1, 0))
	var follower: CharacterBody3D = facility.mtf.spawn(start_pos + Vector3(0.4, 0.1, 0.4), leader)
	leader.no_target = true
	follower.no_target = true
	await get_tree().physics_frame
	# the room goal comes from the whole map now, and an unreachable one (status 2) is re-planned within seconds
	var planning := 0.0
	while planning < 90.0 and leader.path_status != 1:
		await get_tree().physics_frame
		planning += get_physics_process_delta_time()
	var began: Vector3 = leader.global_position
	var travelled := 0.0
	var last: Vector3 = began
	var max_apart := 0.0
	var apart_sum := 0.0
	var apart_frames := 0
	var follower_travelled := 0.0
	var follower_last: Vector3 = follower.global_position
	var waited := 0.0
	var frames_walking := 0
	while waited < 40.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		travelled += Vector2(leader.global_position.x - last.x, leader.global_position.z - last.z).length()
		last = leader.global_position
		max_apart = maxf(max_apart, leader.global_position.distance_to(follower.global_position))
		apart_sum += leader.global_position.distance_to(follower.global_position)
		apart_frames += 1
		follower_travelled += Vector2(follower.global_position.x - follower_last.x, follower.global_position.z - follower_last.z).length()
		follower_last = follower.global_position
		if leader.frame >= 488.0 and leader.frame <= 522.0 and leader.curr_speed > 0.005:
			frames_walking += 1
	log_line("   patrol: walked %.1f m in %.0f s, followers up to %.1f m behind, path status %d" % [travelled, waited, max_apart, leader.path_status])
	check("the leader walks from room to room (at 1 m/s)", travelled > 4.0, "%.1f m in %.0f s" % [travelled, waited])
	check("he plays the walking frames while moving", frames_walking > 100, "%d frames" % frames_walking)
	var mean_apart := apart_sum / maxf(float(apart_frames), 1.0)
	check("the follower walks after him (he re-plans every 6-10 s at the same pace, so he trails but does not lose him)", follower_travelled > 2.0 and mean_apart < 12.0 and max_apart < 30.0, "%.1f m walked against %.1f, %.1f m on average and %.1f at most behind" % [follower_travelled, travelled, mean_apart, max_apart])
	check("their steps are heard", leader.steps_played >= 4, "%d" % leader.steps_played)
	for node in door_states:
		if is_instance_valid(node):
			node.close_timer = 0.0
			node.open = door_states[node]
	GameState.god_mode = false
	_clear_mtf()

# UpdateMTF: the announcements and the arrival of the three units.
# CreateMap can leave gateaentrance unplaced (a forced ROOM2C joins a dead end to the hall, so Room1Amount counts one
# ROOM1 too many and the last name slot is never reached), as in the original; such a map has no gate A.
func _scn_mtfdirector() -> void:
	log_line("== MTF arrival")
	statue.active = false
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	facility.mtf.enabled = true
	facility.mtf.timer = 0.0
	facility.mtf.announcements.clear()
	var entrance := {}
	for record in facility.generator.rooms:
		if str(record.name) == "gateaentrance":
			entrance = record
	if entrance.is_empty():
		log_line("SKIP  MTF arrival: this map has no gate A entrance")
		return
	# far from gate A nothing happens
	for i in 40:
		facility.mtf.update_squad(30.0)
	check("no one arrives while the player is far from gate A", facility.mtf.units.is_empty() and facility.mtf.timer == 0.0, "%d units" % facility.mtf.units.size())
	place_player(Vector3(entrance.position.x, entrance.position.y + 2.0, entrance.position.z + 20.0))
	for i in 6:
		facility.mtf.update_squad(30.0)     # the dice always pass at 30 frames
	check("within 30 of the entrance three units arrive", facility.mtf.units.size() == 3, "%d units" % facility.mtf.units.size())
	if facility.mtf.units.size() == 3:
		check("the second and third follow the first", facility.mtf.units[1].leader == facility.mtf.units[0] and facility.mtf.units[2].leader == facility.mtf.units[0] and facility.mtf.units[0].leader == null, "")
		var behind: float = entrance.position.z - facility.mtf.units[0].global_position.z
		check("they appear 8 behind the entrance", absf(behind - 8.0) < 0.5, "%.2f" % behind)
	check("the timer starts", facility.mtf.timer > 0.0, "%.1f" % facility.mtf.timer)
	_clear_mtf()
	facility.mtf.announcements.clear()
	facility.mtf.timer = 70.0 * 120.0 + 5.0
	facility.mtf.update_squad(1.0)
	facility.mtf.timer = 10000.0 + 70.0 * 120.0 + 5.0
	facility.mtf.update_squad(1.0)
	facility.mtf.timer = 20000.0 + 70.0 * 60.0 + 5.0
	facility.mtf.update_squad(1.0)
	facility.mtf.timer = 25000.0 + 70.0 * 60.0 + 5.0
	facility.mtf.update_squad(1.0)
	var heard := ", ".join(facility.mtf.announcements)
	check("the announcements come in order", heard.contains("AnnouncAfter1") and heard.contains("AnnouncAfter2") and heard.contains("ThreatAnnounc") and heard.contains("ThreatAnnouncFinal"), heard)
	check("and the timer ends at 30000", facility.mtf.timer == 30000.0, "%.0f" % facility.mtf.timer)

func _trigger_centre(room: Node3D, trigger_name: String) -> Vector3:
	for box in room.triggers:
		if str(box.name) == trigger_name:
			var centre: Vector3 = (box.low + box.high) * 0.5
			centre.y = box.low.y + 0.3
			return room.to_global(centre)
	return Vector3.INF

# 049 appears when the player is in room2sl or in room049's lower chamber, not merely because those rooms exist.
func _scn_spawn049() -> void:
	log_line("== 049 spawn trigger")
	statue.active = false
	var records: Array = []
	for record in facility.generator.rooms:
		if str(record.name) in ["room2sl", "room049"]:
			records.append(record)
	log_line("   rooms with the event: %s" % str(records.map(func(r): return str(r.name) + str(r.grid))))
	if records.is_empty():
		log_line("   (this seed has neither room)")
		return
	facility.spawn_049_enabled = true
	facility.scp049 = null
	var target: Dictionary = records[0]
	# loading the room (the player walks up to it) does not wake him
	var room: Node3D = facility.rooms.get_room(target)
	await secs(0.5)
	var far := Vector3(target.position.x, 0.0, target.position.z)
	check("049 is not created just because the room exists", facility.scp049 == null and not facility.in_049_zone(player.global_position), "scp049 %s" % str(facility.scp049))
	var inside := Vector3(target.position.x, 1.0, target.position.z)
	if str(target.name) == "room049":
		inside.y = -2848.0 * 8.0 / 2048.0 - 0.3
	check("a point inside the event zone is recognised", facility.in_049_zone(inside), str(inside))
	place_player(inside)
	await secs(1.0)
	check("he is created once the player is in the zone", facility.scp049 != null, "")
	facility.spawn_049_enabled = false
	if facility.scp049 != null:
		facility.scp049.queue_free()
	facility.scp049 = null

# ---- the intro (SCP_INTRO=1 SCP_BOT_ONLY=intro) -------------------------------------------------------

func _wait_until(condition: Callable, max_seconds: float) -> float:
	var waited := 0.0
	while waited < max_seconds and not condition.call():
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return waited

func world_chamber() -> Node3D:
	return get_tree().get_first_node_in_group("chamber") as Node3D

# The intro when the player stays in the cell (the gas) and when they dawdle in the escort (Ulgrin loses patience).
func _intro_skip_to_door(scene: Node) -> void:
	await secs(0.5)
	scene.event_state3 = 170.0
	scene._wake_started = true
	player.scripted = false
	player.camera.position = Vector3(0.0, 0.9, 0.0)
	player.camera.rotation = Vector3.ZERO
	await _wait_until(func() -> bool: return scene.npc[3].state == 9, 30.0)

func _find_room(room_name: String) -> Dictionary:
	for candidate in facility.generator.rooms:
		if str(candidate.name) == room_name:
			return candidate
	return {}

func _scn_mtfcamera() -> void:
	log_line("== MTF camera check")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(1.0)
	# a fixed camera within reach that has a clear floor spot in front of it
	var cam: Node3D = null
	var spot := Vector3.INF
	var space := get_viewport().world_3d.direct_space_state
	for node in get_tree().get_nodes_in_group("security_cam"):
		if bool(node.data.get("follow", false)) or node._head == null:
			continue
		var forward: Vector3 = node.head_forward()
		forward.y = 0.0
		forward = forward.normalized()
		for distance in [2.0, 3.0, 1.5]:
			var ahead: Vector3 = node._head.global_position + forward * distance
			var down := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3(0, -6.0, 0))
			down.collision_mask = 1
			var hit := space.intersect_ray(down)
			if hit.is_empty() or node._head.global_position.y - hit.position.y > 4.0:
				continue
			var line := PhysicsRayQueryParameters3D.create(node._head.global_position, hit.position + Vector3(0, 1.0, 0))
			line.collision_mask = 1
			if space.intersect_ray(line).is_empty():
				cam = node
				spot = hit.position
				break
		if cam != null:
			break
	check("a camera with a clear view is loaded", cam != null, "")
	if cam == null:
		return
	place_player(spot + Vector3(0, 0.1, 0))
	cam.curr_angle = 0.0
	await secs(0.6)
	facility.mtf.camera_check_timer = 0.0
	facility.mtf.camera_check_detected = false
	await secs(0.4)
	check("a camera reports nothing while no check is running", not facility.mtf.camera_check_detected, "")
	facility.mtf.camera_check_timer = 1.0
	var frames := 0
	while frames < 200 and not facility.mtf.camera_check_detected:
		await get_tree().physics_frame
		frames += 1
	check("during a check the camera that sees the player reports him", facility.mtf.camera_check_detected, "after %d frames" % frames)
	facility.mtf.announcements.clear()
	facility.mtf.camera_check_timer = 70.0 * 90.0 - 1.0
	await secs(0.3)
	var heard := ", ".join(facility.mtf.announcements)
	check("the PA says he was found", heard.contains("AnnouncCameraFound"), heard)
	check("and the units now know where he is (player detected, timer 60 s)", facility.mtf.player_detected and facility.mtf.camera_check_timer > 70.0 * 50.0, "%.0f" % facility.mtf.camera_check_timer)
	# an MTF unit far away starts looking for him (MeNPCSeesPlayer = 3: 45 s)
	var far: Vector3 = player.global_position + Vector3(15.0, 0.0, 0.0)    # beyond the 8 units a unit can see or hear
	var unit: CharacterBody3D = facility.mtf.spawn(far + Vector3(0, 0.05, 0))
	unit.rotation.y += PI
	await secs(0.5)
	check("a unit that does not see him still turns to hunt him (state 1)", unit.state == 1, "state %d" % unit.state)
	check("with the camera's 45 s (3 x 15)", unit.state2 > 70.0 * 40.0 and unit.state2 <= 70.0 * 45.0, "%.0f" % unit.state2)
	_clear_mtf()
	# the detection ends 30 s later
	facility.mtf.camera_check_timer = 70.0 * 90.0 - 1.0
	await secs(0.3)
	check("the check ends and the detection with it", not facility.mtf.player_detected and facility.mtf.camera_check_timer == 0.0, "%.0f" % facility.mtf.camera_check_timer)
	# a check that finds nobody
	facility.mtf.announcements.clear()
	place_player(home)
	await secs(0.6)
	facility.mtf.camera_check_timer = 70.0 * 90.0 - 1.0
	facility.mtf.camera_check_detected = false
	place_player(cam._head.global_position + Vector3(0, 30.0, 0))   # out of every camera's sight
	await get_tree().physics_frame
	facility.mtf.camera_check_detected = false
	await secs(0.3)
	var heard_none := ", ".join(facility.mtf.announcements)
	check("a check that finds nobody says so", heard_none.contains("AnnouncCameraNoFound") or heard_none.contains("AnnouncCameraFound"), heard_none)
	# a lost target can start a check
	facility.mtf.camera_check_timer = 0.0
	facility.mtf.announcements.clear()
	var started := false
	for i in 400:
		facility.mtf.start_camera_check(1.0)
		if facility.mtf.camera_check_timer > 0.0:
			started = true
			break
	check("units that lose their target sometimes call a camera check", started and ", ".join(facility.mtf.announcements).contains("AnnouncCameraCheck"), "")
	facility.mtf.camera_check_timer = 0.0

# ---- SCP-008: the chamber, its lever and the checkpoint it unlocks ----------------------------------------------

# The debug menu's force spawn for SCP-106 (F6 or the button).
func _scn_force106() -> void:
	log_line("== debug: force-spawn SCP-106")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	for key in facility.rooms.built:
		var candidate: FacilityRoom = facility.rooms.built[key]
		if candidate.room_name != "gatea" and not facility.generator.room_disables_decals(candidate.room_name) and facility.room_name_at(candidate.global_position + Vector3(0.0, 1.5, 0.0)) == candidate.room_name:
			place_player(candidate.global_position + Vector3(0.0, 1.5, 0.0))
			break
	await secs(0.6)
	facility.spawn_106_enabled = false
	check("no 106 before the key", facility.scp106 == null, "")
	var key := InputEventKey.new()
	key.keycode = KEY_F6
	key.physical_keycode = KEY_F6
	key.pressed = true
	GameState.console_enabled = false
	Input.parse_input_event(key)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("with the console option off the debug keys do nothing", facility.scp106 == null, "")
	GameState.console_enabled = true
	var release_first := key.duplicate() as InputEventKey
	release_first.pressed = false
	Input.parse_input_event(release_first)
	await get_tree().physics_frame
	Input.parse_input_event(key)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	check("F6 creates SCP-106", facility.scp106 != null and is_instance_valid(facility.scp106), "")
	if facility.scp106 == null:
		return
	check("active at once (state 0 or below), not 12-17 minutes away", facility.scp106.state <= 0.0 or facility.scp106.state > 0.0 and facility.scp106.state < 2000.0, "state %.0f" % facility.scp106.state)
	await secs(1.5)
	check("he rises under the player", facility.scp106.global_position.distance_to(player.global_position) < 6.0, "%.1f from the player" % facility.scp106.global_position.distance_to(player.global_position))
	# the stain he leaves where he comes up grows 0.001 a frame from 0.05 (a sprite scaled to its size is twice that across)
	var stains: Array[Node] = []
	for node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("growing_decal.gd") and node.size_change > 0.0:
			stains.append(node)
	check("he leaves a corrosion stain", stains.size() >= 1, "%d" % stains.size())
	if stains.size() >= 1:
		var stain: MeshInstance3D = stains[0]
		for candidate_stain in stains:     # earlier scenarios leave grown stains behind: follow the newest (smallest)
			if candidate_stain.size < stain.size:
				stain = candidate_stain
		check("it is 2 units across at full size (ScaleSprite 1)", absf((stain.mesh as QuadMesh).size.x - 2.0) < 0.001, "%.2f" % (stain.mesh as QuadMesh).size.x)
		var size_then: float = stain.size
		await secs(3.0)
		check("and grows by 0.001 a frame (about 0.2 in 3 s)", stain.size > size_then + 0.15 and stain.size < size_then + 0.3, "%.3f -> %.3f" % [size_then, stain.size])
		await secs(2.0)
		check("small stains drop inside it", stain.drops >= 1, "%d drops" % stain.drops)
	var release := InputEventKey.new()
	release.keycode = KEY_F6
	release.pressed = false
	Input.parse_input_event(release)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _scn_zombie008() -> void:
	log_line("== SCP-008-1, the infected surgeon")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = false
	var room: Node3D = facility.start_node
	var home: Vector3 = room.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	player.blink_timer = 400.0
	await secs(0.6)
	var zombie: Node = facility.spawn_zombie008(home + room.global_transform.basis * Vector3(4.0, 0.05, -1.0), 0)
	zombie.rotation.y = room.rotation.y + PI * 0.5      # facing away: it has to turn round and come
	await secs(0.5)
	check("a lying zombie is frame 11 and collides with nothing", zombie.state == 0 and is_equal_approx(zombie.frame, 11.0) and zombie.collision_layer == 0, "")
	zombie.set_state(1)
	await secs(3.5)
	check("it gets up and is active", zombie.state >= 2, "state %d frame %.0f" % [zombie.state, zombie.frame])
	check("an active one collides like a person", zombie.collision_layer == 4 or zombie.state == 3, "")
	var start_dist: float = zombie.global_position.distance_to(player.global_position)
	(get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	face_point(zombie.global_position + Vector3(0.0, 0.8, 0.0))
	await get_tree().physics_frame
	await shot("zombie_walk")
	#log_line("   dbg state %d path_status %d path %d timer %.0f frame %.0f pos %s player %s sees %d" % [zombie.state, zombie.path_status, zombie.path.size(), zombie.path_timer, zombie.frame, str(zombie.global_position), str(player.global_position), zombie._sees_player(player)])
	await secs(1.5)
	var infect_before := GameState.infect
	var waited := 0.0
	while waited < 10.0 and GameState.infect <= infect_before:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	#log_line("   dbg2 state %d path_status %d path %d loc %d timer %.0f frame %.0f pos %s speed %.3f" % [zombie.state, zombie.path_status, zombie.path.size(), zombie.path_location, zombie.path_timer, zombie.frame, str(zombie.global_position), zombie.curr_speed])
	check("it closes in on the player", zombie.global_position.distance_to(player.global_position) < start_dist or zombie.state == 3, "%.1f -> %.1f" % [start_dist, zombie.global_position.distance_to(player.global_position)])
	check("its swing infects (infection +1) and hurts", GameState.infect >= infect_before + 1.0 and GameState.injuries > 0.0, "infect %.1f injuries %.2f hits %d" % [GameState.infect, GameState.injuries, zombie.hits])
	check("the death note names the infected", GameState.death_msg.begins_with("Subject D-9341. Cause of death: multiple lacerations"), "")
	face_point(zombie.global_position + Vector3(0.0, 0.8, 0.0))
	await get_tree().physics_frame
	await shot("zombie_attack")
	# the Nine-Tailed Fox shoots it
	GameState.god_mode = true
	GameState.infect = 0.0
	GameState.injuries = 0.0
	player.dead = false
	zombie.hp = 30.0
	zombie.global_position = home + room.global_transform.basis * Vector3(0.0, 0.05, -4.0)
	var unit: Node = facility.mtf.spawn(home + room.global_transform.basis * Vector3(2.0, 0.05, -1.0))
	unit.rotation.y = atan2(-(zombie.global_position.x - unit.global_position.x), -(zombie.global_position.z - unit.global_position.z))
	var shot_by_mtf := 0.0
	while shot_by_mtf < 12.0 and not zombie.is_dead:
		await get_tree().physics_frame
		shot_by_mtf += get_physics_process_delta_time()
	check("an MTF unit takes it for a target (state 9)", unit.shots_fired > 0, "%d shots, state %d" % [unit.shots_fired, unit.state])
	check("and shoots it dead", zombie.is_dead, "hp %.0f after %.1fs" % [zombie.hp, shot_by_mtf])
	await secs(1.0)
	check("then goes back to its patrol", unit.state == 0 or unit.state == 1, "state %d" % unit.state)
	check("the body lies in the death frames", zombie.frame >= 344.0, "frame %.0f" % zombie.frame)
	facility.mtf.remove(unit)
	facility.remove_zombie008(zombie)
	# too far for too long: it is gone, and comes back near the player
	var far_one: Node = facility.spawn_zombie008(home + room.global_transform.basis * Vector3(0.0, 0.05, -6.0), 2)
	far_one.no_target = true
	far_one.state3 = 70.0 * 15.0 - 5.0
	place_player(home + Vector3(30.0, 0.0, 0.0))
	player.blink_timer = 400.0
	var gone_wait := 0.0
	while gone_wait < 4.0 and far_one.state != 4:
		await get_tree().physics_frame
		gone_wait += get_physics_process_delta_time()
	check("far from the player too long it gives up (state 4)", far_one.state == 4 or far_one.global_position.distance_to(player.global_position) > 15.0, "state %d dist %.1f" % [far_one.state, far_one.global_position.distance_to(player.global_position)])
	facility.remove_zombie008(far_one)
	GameState.god_mode = false

func _scn_scp096() -> void:
	log_line("== SCP-096")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = false
	facility.spawn_096_rooms = false
	var room: Node3D = facility.start_node
	var home: Vector3 = room.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	player.blink_timer = 400.0
	await secs(0.6)
	var spot := Vector3.INF
	for offset in [Vector3(4.0, 0.0, -0.5), Vector3(-4.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, -4.0), Vector3(3.0, 0.0, 3.0), Vector3(-3.0, 0.0, -3.0), Vector3(3.0, 0.0, -3.0), Vector3(-3.0, 0.0, 3.0)]:
		var candidate: Vector3 = home + room.global_transform.basis * offset
		var probe := PhysicsRayQueryParameters3D.create(player.camera.global_position, candidate + Vector3(0.0, 0.5, 0.0))
		probe.collision_mask = 1
		if player.get_world_3d().direct_space_state.intersect_ray(probe).is_empty():
			spot = candidate
			break
	check("the start room has a clear line to stand 096 on", spot != Vector3.INF, "")
	if spot == Vector3.INF:
		return
	face_point(home + (home - spot) * 2.0 + Vector3(0.0, 1.0, 0.0))      # looking away from where it will sit
	await get_tree().physics_frame
	var shy: Node = facility.spawn_096(spot, 0, atan2(-(home.x - spot.x), -(home.z - spot.z)))
	check("096's speed follows the difficulty (NPCSpeedChange)", is_equal_approx(shy.top_speed, 0.09 * GameState.npc_speed_factor()), "%.3f" % shy.top_speed)
	await secs(0.8)
	check("looking away does not set it off", shy.state == 0, "state %d" % shy.state)
	# looking at it with the eyes shut: nothing happens
	face_point(spot + Vector3(0.0, 0.5, 0.0))
	player.blink_timer = -10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("looking at it with the eyes shut does not either", shy.state == 0, "state %d blink %.0f" % [shy.state, player.blink_timer])
	player.blink_timer = 400.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("eyes open on its face: it is triggered", shy.state == 1 and shy.triggered_count == 1, "state %d" % shy.state)
	check("the view pinches", player.camera_zoom > 5.0, "%.1f" % player.camera_zoom)
	var rise := 0.0
	while rise < 14.0 and shy.state < 2:
		await get_tree().physics_frame
		rise += get_physics_process_delta_time()
	check("it gets up and screams (state 2 or 3)", shy.state == 2 or shy.state == 3, "state %d frame %.0f after %.1fs" % [shy.state, shy.frame, rise])
	await shot("scp096_angry")
	shy.state = 3
	shy.state2 = 70.0 * 18.0
	var waited := 0.0
	while waited < 3.0 and shy.state != 4:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("after 18 s the chase begins (state 4)", shy.state == 4, "state %d frame %.0f" % [shy.state, shy.frame])
	player.blink_timer = 400.0
	var start_dist: float = shy.global_position.distance_to(player.global_position)
	var closing := 0.0
	while closing < 6.0 and not player.dead:
		await get_tree().physics_frame
		closing += get_physics_process_delta_time()
		if shy.global_position.distance_to(player.global_position) < 3.0 and closing > 0.5:
			await shot("scp096_chase")
			break
	waited = 0.0
	while waited < 8.0 and not player.dead:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("it reaches the player and kills", player.dead and shy.kills >= 1, "dist %.1f dead %s after %.1fs" % [shy.global_position.distance_to(player.global_position), str(player.dead), closing + waited])
	check("with the original death note", GameState.death_msg.begins_with("A large amount of blood found in [DATA REDACTED]"), "")
	check("and blood on the floor", get_tree().get_nodes_in_group("scp096").size() >= 1 and shy.kills == 1, "")
	player.dead = false
	GameState.god_mode = true
	# state 5: the player looking at it from the front triggers it
	shy.state = 5
	shy.frame = 423.0
	shy.set_frame(423.0)
	shy.global_position = spot
	shy.rotation.y = atan2(-(home.x - spot.x), -(home.z - spot.z))
	GameState.god_mode = false
	place_player(home)
	player.blink_timer = 400.0
	face_point(spot + Vector3(0.0, 0.8, 0.0))
	await secs(1.0)
	check("a wandering one is triggered by the look too (state 2)", shy.state == 2, "state %d" % shy.state)
	# an MTF unit that sees it looks away (state 8) and snaps out of it when 096 is out of sight
	shy.state = 6
	shy.set_frame(312.0)
	var unit: Node = facility.mtf.spawn(spot + room.global_transform.basis * Vector3(-2.0, 0.0, 0.0))
	unit.rotation.y = unit.rotation.y
	unit.blink_timer = 70.0 * 12.0
	shy.rotation.y = atan2(-(unit.global_position.x - shy.global_position.x), -(unit.global_position.z - shy.global_position.z))
	var saw := 0.0
	while saw < 3.0 and unit.state != 8:
		unit.rotation.y = atan2(-(shy.global_position.x - unit.global_position.x), -(shy.global_position.z - unit.global_position.z))
		await get_tree().physics_frame
		saw += get_physics_process_delta_time()
	check("an MTF unit that sees 096 reacts (state 8)", unit.state == 8, "state %d" % unit.state)
	shy.global_position = Vector3(0.0, -80.0, 0.0)
	await secs(0.5)
	check("and carries on when it is out of sight", unit.state != 8, "state %d" % unit.state)
	facility.mtf.remove(unit)
	facility.scp096.queue_free()
	facility.scp096 = null
	GameState.god_mode = false

func _scn_slam096() -> void:
	log_line("== SCP-096 at the lift")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room3storage":
			record = candidate
	if record.is_empty():
		check("the map has a room3storage", false, "")
		return
	place_player(record.position + Vector3(0.0, 6.0, 0.0))
	var room: Node3D = null
	var key := "%d,%d" % [record.grid.x, record.grid.y]
	room = facility.rooms.built.get(key)
	if room == null:
		check("the room is built", false, key)
		return
	var lift: Node = room._lifts[0]
	lift.slam_096 = true
	var door: Node3D = room.door_slots.get(0)
	var cab: Vector3 = room.object_point(0)
	door.open = false
	place_player(cab + Vector3(0.0, 0.1, 0.0))
	await secs(1.0)
	var shy: Node = facility.spawn_096(cab + Vector3(0.0, 0.0, 12.0), 5)
	await secs(0.5)
	check("a sitting or wandering 096 leaves the lift alone", lift.slam_state == 0.0, "%.0f" % lift.slam_state)
	shy.state = 3          # angered
	door.open = false
	await secs(0.6)
	check("an angered one takes the lift over: it is put outside in state 6", shy.state == 6 and lift.slam_state > 0.0, "state %d slam %.0f" % [shy.state, lift.slam_state])
	check("and the door is held shut", door.locked and not door.open, "")
	await secs(2.5)
	check("the door keeps shut while it slams", not door.open, "slam %.0f" % lift.slam_state)
	var wait := 0.0
	while wait < 6.0 and not door.open:
		await get_tree().physics_frame
		wait += get_physics_process_delta_time()
	check("after about 7 s it tears the door open", door.open and door.fast_open, "after %.1f s, slam %.0f" % [wait + 3.1, lift.slam_state])
	check("and the chase begins (state 4)", shy.state == 4, "state %d" % shy.state)
	facility.scp096.queue_free()
	facility.scp096 = null
	lift.slam_096 = false
	lift.slam_state = 0.0
	GameState.god_mode = false

func _gatea_arrive(contained: bool) -> Dictionary:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	facility.contained_106 = contained
	var result := {"ok": false}
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "gateaentrance":
			record = candidate
	if record.is_empty():
		log_line("SKIP  gate A: this map has no gate A entrance")
		return result
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(10.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(2.0)
	var entrance: Node3D = facility.rooms.get_room(record)
	check("gate A is built with the entrance and one lift links them", facility.rooms.built.has("gatea") and facility.rooms.gate_a_lift != null, "")
	if facility.rooms.gate_a_lift == null:
		return result
	var lift: Node = facility.rooms.gate_a_lift
	var gatea: Node3D = facility.rooms.built["gatea"]
	check("gate A hangs 500 up", absf(gatea.global_position.y - 500.0) < 1.0, "%.1f" % gatea.global_position.y)
	check("the lift's far door is gate A's (closed), the near one open", lift.door1.open and not lift.door2.open, "")
	var cab: Vector3 = lift.cab1.global_position
	var far_door: Node3D = lift.door2
	place_player(cab + Vector3(0.0, 0.1, 0.0))
	player.blink_timer = 400.0
	await secs(0.5)
	lift.door1.use()
	var waited := 0.0
	while waited < 14.0 and player.global_position.y < 400.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("the ride takes the player up to gate A", player.global_position.y > 400.0, "y %.1f after %.1f s" % [player.global_position.y, waited])
	await secs(1.5)
	check("arriving locks the lift's door for good", far_door.locked and far_door.open, "locked %s open %s" % [str(far_door.locked), str(far_door.open)])
	check("the room is gate A", facility.room_name_at(player.global_position) == "gatea", facility.room_name_at(player.global_position))
	result.ok = true
	result.room = gatea
	return result

func _end_ending_for_test(hud: Node) -> void:
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

# Stands the player 0.55 from a lever's handle on a floor, looking at it; false if no such spot exists.
func _stand_before_lever(lever: Node3D) -> bool:
	var handle: Vector3 = lever.handle_point()
	place_player(handle + Vector3(0.0, 0.3, 0.0))    # the room is solid only near the player
	await get_tree().physics_frame
	await get_tree().physics_frame
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
		if lever.aimed_at(player.camera, 1.5):
			return true
	return false

# Gate B's room built and the player standing two units inside its door (slot 4).
func _enter_gate_b(record: Dictionary) -> Node3D:
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	var door: Node3D = room.door_slots.get(4)
	place_player(door.global_position + Vector3(0.0, 1.0, 0.0) + room.global_transform.basis * Vector3(0.0, 0.0, -2.0))
	await secs(0.4)
	return room

func _femur_reset(contained_before: bool = false) -> void:
	facility.events.femur.state = 0
	facility.events.femur.magnets = true
	facility.events.femur.timer = 0.0
	facility.events.femur.transmission = false
	facility.contained_106 = contained_before

# Stands the player on a floor 0.5 from a point (around it), looking at it; false if no such spot exists.
func _stand_before_point(point: Vector3, accept: Callable = Callable()) -> bool:
	for step in 16:
		var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
		var spot: Vector3 = point + dir * 0.5
		var down := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.5, 0), spot + Vector3(0, -3.0, 0))
		down.collision_mask = 1
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
		if hit.is_empty() or absf(hit.position.y - (point.y - 1.0)) > 1.2:
			continue
		place_player(hit.position + Vector3(0, 0.1, 0))
		await secs(0.3)
		var look: Vector3 = point - player.camera.global_position
		player.rotation.y = atan2(-look.x, -look.z)
		player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		player.user_pitch = -rad_to_deg(player.camera.rotation.x)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if accept.is_valid() and not accept.call():
			continue
		return true
	return false

const Recipes914 = preload("res://scripts/items/scp914_recipes.gd")
const Room914 = preload("res://scripts/world/scp914_room.gd")

func _items_near(point: Vector3, radius: float) -> Array:
	var out: Array = []
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and Vector2(pickup.global_position.x - point.x, pickup.global_position.z - point.z).length() < radius:
			out.append(str(pickup.get_meta("tempname", "")))
	return out

func _clear_items_near(point: Vector3, radius: float) -> void:
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pickup) and Vector2(pickup.global_position.x - point.x, pickup.global_position.z - point.z).length() < radius:
			pickup.remove_from_group("pickup")
			pickup.queue_free()

const Data294 = preload("res://scripts/items/scp294_data.gd")

func _use_slot(hud: Node, slot: int) -> void:
	hud.set_selected(slot)
	await secs(0.2)

func _scn_scp966() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room966":
			record = candidate
	check("the map has SCP-966's room", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(30.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	check("nothing is made before the player is inside", facility.scp966s.is_empty() and facility.events.room966.state == 0, "")
	var spot: Vector3 = room.object_point(3)
	place_player(spot + Vector3(0.0, 1.0, 0.0))
	await secs(1.5)
	check("two Sleep Killers wait in the room", facility.scp966s.size() == 2 and facility.events.room966.state == 2, "n %d state %d" % [facility.scp966s.size(), facility.events.room966.state])
	var first: Node = facility.scp966s[0]
	var second: Node = facility.scp966s[1]
	check("they stand at the room's two spots", first.global_position.distance_to(room.object_point(0)) < 1.0 and second.global_position.distance_to(room.object_point(2)) < 1.0, "")
	await secs(1.0)
	check("without night vision their bodies are hidden", not first._visual.visible, "")
	GameState.wearing_night_vision = 1
	await secs(0.3)
	check("with night vision they are seen", first._visual.visible, "")
	GameState.wearing_night_vision = 0
	var cues_state4 := 0
	var cues_state3 := 0
	var before_frame := 214.0
	for step in 125:
		var f := minf(before_frame + 1.0, 457.0) if step > 0 else 332.0
		cues_state4 += 1 if first.idle_cue(before_frame, f) else 0
		before_frame = f
	before_frame = 257.0
	for step in 80:
		var f := before_frame + 1.0
		cues_state3 += 1 if first.idle_cue(before_frame, f) else 0
		before_frame = f
	check("the stare plays Idle once, not every tick past frame 354", cues_state4 == 1, "%d" % cues_state4)
	check("the turn (state 3) plays Idle at 271 and 301 only once each (two cues)", cues_state3 == 2, "%d" % cues_state3)
	# something breathing next to the player: the line, once
	first.global_position = player.global_position + player.global_transform.basis * Vector3(0.0, 0.0, -0.7)
	first.state = 0
	first.reload = 0.0
	await secs(0.5)
	check("a body next to the player is felt", first.reload > 70.0 * 15.0, "reload %.0f" % first.reload)
	# the echo: blink, stamina and blur
	GameState.wearing_night_vision = 1
	first.state = 1
	first.set_frame(214.0)
	GameState.blink_effect = 1.0
	await secs(1.5)
	check("its echo makes the player blink more and tire faster", GameState.blink_effect >= 1.5 and GameState.stamina_effect >= 2.0, "blink %.1f stamina %.1f" % [GameState.blink_effect, GameState.stamina_effect])
	check("seeing one through night vision is the 966 achievement", GameState.achievements.has("966"), "")
	# being worn out makes them hostile
	for npc in facility.scp966s:
		npc.state = 0
		npc.state3 = 0.0
	player.stamina = 5.0
	await secs(0.5)
	player.stamina = 5.0
	var waited := 0.0
	while first.state3 < 1000.0 and waited < 8.0:
		player.stamina = 5.0
		await secs(0.25)
		waited += 0.25
	check("with the stamina gone for 5 s they all turn on the player", first.state3 >= 1000.0 and second.state3 >= 1000.0 and first.state >= 8, "state3 %.0f state %d" % [first.state3, first.state])
	player.stamina = 100.0
	# they chase and attack; the chase may have pushed the player into a corner
	place_player(spot + Vector3(0.0, 1.0, 0.0))
	await secs(0.3)
	var placed := false
	for reach in [2.5, 1.8, 3.5, 1.3, 4.5, 1.0]:
		for turn in 16:
			var offset := Vector3(reach, 0.0, 0.0).rotated(Vector3.UP, turn * PI / 8.0)
			var at: Vector3 = player.global_position + offset
			if not blocked(at) and not ray_blocked(player.global_position + Vector3(0.0, 0.3, 0.0), at + Vector3(0.0, 0.3, 0.0)):
				first.global_position = at
				placed = true
				break
		if placed:
			break
	check("a clear spot a few metres from the player exists", placed, "player at %s, room-local %s" % [player.global_position, room.to_local(player.global_position)])
	first.state = 8
	second.global_position += Vector3(0.0, -20.0, 0.0)
	GameState.injuries = 0.0
	GameState.wearing_night_vision = 0
	await secs(14.0)
	check("a hostile one reaches the player and cuts them", GameState.injuries > 0.0 and first.hits > 0, "inj %.2f hits %d" % [GameState.injuries, first.hits])
	GameState.injuries = 0.0
	GameState.blink_effect = 1.0
	GameState.stamina_effect = 1.0
	GameState.blur_timer = 0.0
	for npc in facility.scp966s.duplicate():
		facility.remove_scp966(npc)
	facility.events.room966.state = 0

func _scn_scp1499() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var dim: Node = facility.dimension
	check("the facility has the dimension manager", dim != null and not dim.record.is_empty(), "")
	if dim == null or dim.record.is_empty():
		return
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	var home := player.global_position
	var mask: int = _give(hud, "SCP-1499", "scp1499")
	GameState.wearing_hazmat = 1
	hud.set_selected(mask)
	await secs(0.3)
	check("the mask will not go on over a hazmat suit", GameState.wearing_1499 == 0 and hud.message_time_left() > 0.0, "")
	GameState.wearing_hazmat = 0
	hud.deselect()
	hud.set_selected(mask)
	await secs(1.0)
	check("the bar holds the player still while it fills", hud.item_use.locks_movement(), "")
	await secs(2.0)
	check("the mask goes on and the player is carried to the dimension", GameState.wearing_1499 == 1 and dim.inside, "wearing %d inside %s" % [GameState.wearing_1499, str(dim.inside)])
	await secs(1.0)
	check("they stand 800 up, in the church's entrance", player.global_position.y > 799.0 and player.global_position.y < 803.0, "y %.2f" % player.global_position.y)
	check("the facility calls the place dimension1499", facility.room_name_at(player.global_position) == "dimension1499", facility.room_name_at(player.global_position))
	check("the 1499 achievement is given", GameState.achievements.has("1499"), "")
	check("the land is made of chunks around them", dim.chunks.size() >= 25 and dim.chunks.size() <= 49, "chunks %d" % dim.chunks.size())
	check("the fog and the camera are the dimension's", GameState.fog_override.x == 40.0 and GameState.fog_override.y == 80.0 and player.camera.far == 90.0, str(GameState.fog_override))
	check("the sky box is up", dim._sky != null and dim._sky.visible, "")
	check("the music is the dimension's", GameState.music_override in ["1499", "HaveMercyOnMe(NoChoir)", "1499Danger"], GameState.music_override)
	check("the people are there (the church's and the first fifteen)", dim.npcs.size() >= 21, "npcs %d" % dim.npcs.size())
	check("the king and his guard are in the church", dim.king != null and dim.king_guard != null and dim.church_guards.size() == 4, "")
	check("45 pray in the pews", dim.dummies.size() == 45, "%d" % dim.dummies.size())
	hud._gas_overlay.texture = null
	player.rotation.y = deg_to_rad(90.0)
	player.camera.rotation.x = -0.2
	await secs(0.3)
	await shot("scp1499_entrance")
	# the player does not fall through the platforms
	await secs(2.0)
	check("the platforms hold them", player.global_position.y > 799.5, "y %.2f" % player.global_position.y)
	# a walk away from the church makes new chunks
	var before_keys: Array = dim.chunks.keys()
	place_player(player.global_position + Vector3(100.0, 0.5, 0.0))
	await secs(1.5)
	check("far from the church the chunks follow the player", dim.chunks.size() >= 25 and dim.chunks.size() <= 49 and not before_keys.is_empty(), "chunks %d" % dim.chunks.size())
	check("and they stand on the platform", player.global_position.y > 799.5, "y %.2f" % player.global_position.y)
	player.camera.rotation.x = -0.35
	await secs(0.3)
	await shot("scp1499_field")
	player.camera.rotation.x = -1.45
	await secs(0.3)
	await shot("scp1499_down")
	# an inhabitant that sees the player screams and attacks
	var citizen: Node = null
	var other: Node = null
	for n in dim.npcs:
		if is_instance_valid(n) and n.kind == 0:
			other = citizen
			citizen = n
	check("there are ordinary inhabitants", citizen != null, "")
	var parked: Dictionary = {}
	if citizen != null and other != null:
		for n in dim.npcs.duplicate():
			if n != citizen and n != other and is_instance_valid(n):
				parked[n] = n.global_position
				n.global_position += Vector3(0.0, -50.0, 0.0)
		citizen.npc_id = 2
		other.npc_id = 3
		other.state = 0
		other.curr_speed = 0.0
		other.target = null
		var clear_dirs: Array = []
		for turn in 8:
			var dir := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, turn * PI / 4.0)
			var far_at: Vector3 = player.global_position + dir * 8.5
			var open := true
			for probe in [0.2, 0.4, 0.6]:
				if ray_blocked(player.global_position + Vector3(0.0, probe, 0.0), far_at + Vector3(0.0, probe, 0.0)):
					open = false
			if open:
				clear_dirs.append(dir)
		var line: Vector3 = clear_dirs[0] if not clear_dirs.is_empty() else Vector3(1.0, 0.0, 0.0)
		citizen.global_position = player.global_position + Vector3(0.0, 0.2, 0.0) + line * 3.0
		for turn in 8:
			if citizen._clear_to(player):
				break
			line = line.rotated(Vector3.UP, PI / 4.0)
			citizen.global_position = player.global_position + Vector3(0.0, 0.2, 0.0) + line * 3.0
		other.global_position = player.global_position + Vector3(0.0, 0.2, 0.0) + line * 8.0
		citizen.state = 0
		citizen.curr_speed = 0.0
		citizen.target = null
		citizen.reload = 0.0
		GameState.injuries = 0.0
		await secs(22.0)
		check("an inhabitant who sees them comes for them and cuts them", GameState.injuries > 0.0 and citizen.hits + other.hits > 0, "inj %.2f hits %d states %d %d" % [GameState.injuries, other.hits, citizen.state, other.state])
	GameState.injuries = 0.0
	for n in parked:
		if is_instance_valid(n):
			n.global_position = parked[n]      # they fall for good when left 50 m down
			n.velocity = Vector3.ZERO
	for n in dim.npcs.duplicate():
		if is_instance_valid(n) and n.kind == 0:
			dim.remove_npc(n)
	place_player(dim.church_point(-56.0, 240.0, 2287.0) + Vector3(0.0, 0.5, 0.0))
	await secs(11.0)
	check("ten seconds in the church starts the king's speech", dim.church_state >= 70.0 * 10.0, "%.0f" % dim.church_state)
	await secs(30.0)
	check("the guards turn on the player when it ends", dim.church_state >= 70.0 * 30.0 and dim.church_guards.size() > 0 and dim.church_guards[0].state != 0, "state %.0f" % dim.church_state)
	GameState.wearing_1499 = 0
	await secs(0.5)
	check("taking the mask off carries them back", not dim.inside and player.global_position.distance_to(home) < 2.0, "dist %.1f" % player.global_position.distance_to(home))
	check("the land is dropped again", dim.chunks.is_empty() and dim.npcs.is_empty() and dim.dummies.is_empty(), "chunks %d npcs %d" % [dim.chunks.size(), dim.npcs.size()])
	check("the fog is the facility's again", GameState.fog_override.x < 0.0 and player.camera.far > 100.0, "")
	check("the church event is not recreated once it is over", dim.church_state >= 70.0 * 30.0, "")
	# back in: where they left
	hud.deselect()
	hud.set_selected(mask)
	await secs(3.5)
	check("putting it on again carries them back to where they left", dim.inside and player.global_position.distance_to(dim.church_point(-56.0, 240.0, 2287.0)) < 6.0, "")
	check("the church has no king the second time", dim.king == null, "")
	# saved inside the dimension
	check("the game saves inside the dimension", main.save_game(), "")
	await main.load_game()
	var waited_load := 0.0
	while waited_load < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited_load += get_physics_process_delta_time()
	await secs(3.0)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173
	dim = facility.dimension
	check("loading a game saved inside brings the player back inside, mask on", dim.inside and GameState.wearing_1499 == 1 and player.global_position.y > 799.0, "inside %s wearing %d y %.1f" % [str(dim.inside), GameState.wearing_1499, player.global_position.y])
	check("with the land around them", dim.chunks.size() >= 25, "chunks %d" % dim.chunks.size())
	GameState.wearing_1499 = 0
	await secs(0.8)
	check("and the mask still takes them back out", not dim.inside, "")
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.blur_timer = 0.0

func _clear_items(hud: Node) -> void:
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	hud.deselect()

func _console_say(console: Control, line: String) -> String:
	var before: int = console.messages.size()
	console.execute(line)
	var text := ""
	for i in range(before + 1, console.messages.size()):
		text += str(console.messages[i].text) + "\n"
	return text

func _real_key(code: int, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	return event

func _key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

# ---------------------------------------------------------------- the event plan and the ambient events (InitEvents, UpdateEvents)

# A room (not the start chamber) that the test can use: `need_objects` lists the FillRoom Objects[] it must have. The first choice is one with
# open ground round its middle and a clear way up (no mezzanine, pit or furniture where a test stands people), as far as a few rays can tell.
func _event_room(need_objects: Array = [], exclude: Array = []) -> Dictionary:
	var fallback := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) in ["start", "173", "gatea", "exit1"] or exclude.has(candidate.key):
			continue
		var node: Node3D = facility.rooms.get_room(candidate)
		var ok := true
		for index in need_objects:
			if node.object_point(int(index)) == Vector3.INF:
				ok = false
		if not ok:
			continue
		if node.extras != null:      # a room with an event of its own (SCP-012, 1162...) keeps its own state
			continue
		if fallback.is_empty():
			fallback = candidate
		place_player(candidate.position + Vector3(0.0, 1.2, 0.0))      # a room is solid only near the player
		await get_tree().physics_frame
		await get_tree().physics_frame
		var clear := true
		for spot in [Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(-2.0, 0.0), Vector2(0.0, 2.0), Vector2(0.0, -2.0), Vector2(1.5, 1.5), Vector2(-1.5, -1.5)]:
			var top: Vector3 = candidate.position + Vector3(spot.x, 1.2, spot.y)       # where a player would stand
			var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3(0.0, -2.5, 0.0))
			ray.collision_mask = 1
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(ray)
			if hit.is_empty() or absf(hit.position.y - candidate.position.y) > 0.15 or hit.normal.y < 0.8:
				clear = false
				break
			if str(facility.record_at(Vector3(top.x, 0.05, top.z)).get("key", "")) != str(candidate.key):     # and the point is this room's, not a bigger neighbour's
				clear = false
				break
		if clear:
			return candidate
	return fallback

func _scn_smallnpcs() -> void:
	log_line("== SCP-066, SCP-372 and SCP-513-1")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var ambient: Node = facility.ambient
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	# --- the events that make them
	var cafeteria := _find_room("room2cafeteria")
	if not cafeteria.is_empty():
		ambient.force(cafeteria.key, "room2cafeteria")
		await secs(0.3)
		check("the cafeteria event makes SCP-066 at the room's middle", get_tree().get_first_node_in_group("scp066") != null, "")
	var pj := _find_room("roompj")
	if not pj.is_empty():
		ambient.force(pj.key, "pj")
		facility.rooms.get_room(pj)
		place_player(pj.position + Vector3(0.0, 1.0, 0.0))
		await secs(0.6)
		check("walking to the middle of the pj room makes SCP-372 and ends the event", get_tree().get_first_node_in_group("scp372") != null and ambient.removed.has(pj.key), "")
	ambient.enabled = false
	for node in get_tree().get_nodes_in_group("scp066") + get_tree().get_nodes_in_group("scp372"):
		node.queue_free()
	await secs(0.2)
	var no_decals: Array = []
	for candidate in facility.generator.rooms:
		if facility.generator.room_disables_decals(str(candidate.name)):
			no_decals.append(candidate.key)
	var home := await _event_room([], no_decals)
	var room: Node3D = facility.rooms.get_room(home)
	var base := Vector3(home.position.x, home.position.y + 0.1, home.position.z)
	place_player(base)
	await secs(1.0)
	var ball := CharacterBody3D.new()
	ball.set_script(load("res://scripts/npc/scp_066.gd"))
	get_tree().get_first_node_in_group("facility").get_parent().add_child(ball)
	ball.global_position = base + Vector3(25.0, 0.0, 0.0)
	ball.hop_at = 1e12
	await secs(0.5)
	check("far away SCP-066 idles (state 0, frames 451-612)", ball.state == 0 and ball.frame >= 451.0 and ball.frame <= 612.0, "state %d frame %.0f" % [ball.state, ball.frame])
	ball.global_position = base + Vector3(5.0, 0.0, 0.0)
	await secs(0.5)
	check("within 8 it stares at the player (state 1, its face turning)", ball.state == 1 and ball.frame >= 2.0 and ball.frame <= 450.0, "state %d frame %.0f" % [ball.state, ball.frame])
	face_point(ball.global_position + Vector3(0.0, 0.2, 0.0))
	await secs(0.2)
	await shot("npc066")
	var before_frame: float = ball.frame
	player.rotation.y += 1.0
	await secs(1.0)
	check("and the face follows the player round", absf(ball.frame - before_frame) > 5.0, "%.0f -> %.0f" % [before_frame, ball.frame])
	ball.state = 2
	ball.state2 = 0.0
	ball.global_position = base + Vector3(2.5, 0.0, 0.0)
	var closer := false
	var start_dist: float = ball.global_position.distance_to(player.global_position)
	for i in 80:
		await secs(0.1)
		if ball.global_position.distance_to(player.global_position) < start_dist - 0.5 or ball.frame == 683.0:
			closer = true
			break
	check("state 2: it turns its face up and rolls at the player", closer or ball.state == 3, "state %d frame %.0f" % [ball.state, ball.frame])
	# the six things it may do on arrival (tried by hand: the ball itself is held still)
	ball.state = 0
	ball.hop_at = 1e12
	ball.set_physics_process(false)
	var deaf := false
	var dark := false
	var hurt := false
	var doors := 0
	GameState.god_mode = false
	GameState.deaf_timer = 0.0
	for i in 90:
		GameState.injuries = 0.0
		ball.global_position = player.global_position + Vector3(0.5, 0.0, 0.0)
		ball.state3 = 0.0
		ball._arrive(player)
		if GameState.deaf_timer > 0.0:
			deaf = true
		if ball.state3 > 0.0:
			dark = true
		if GameState.injuries > 0.2:
			hurt = true
	check("on arrival it sometimes deafens, darkens and hurts", deaf and dark and hurt, "deaf %s dark %s hurt %s" % [str(deaf), str(dark), str(hurt)])
	GameState.god_mode = true
	GameState.injuries = 0.0
	GameState.deaf_timer = 70.0 * 3.0
	await secs(0.3)
	var sfx_bus := AudioServer.get_bus_index(&"Sfx")
	check("while deaf the effects are muted", sfx_bus >= 0 and AudioServer.get_bus_volume_db(sfx_bus) < -50.0, "%.0f dB" % AudioServer.get_bus_volume_db(sfx_bus))
	check("and the music is not", AudioServer.get_bus_volume_db(0) > -1.0 and get_tree().get_first_node_in_group("audio")._music.bus == &"Master", "master %.1f dB, music bus %s" % [AudioServer.get_bus_volume_db(0), str(get_tree().get_first_node_in_group("audio")._music.bus)])
	GameState.deaf_timer = 1.0
	await secs(0.5)
	check("and comes back", AudioServer.get_bus_volume_db(sfx_bus) > linear_to_db(maxf(GameState.sound_volume, 0.0001)) - 1.0, "%.0f dB" % AudioServer.get_bus_volume_db(sfx_bus))
	var volume := GameState.sound_volume
	GameState.sound_volume = 0.5
	check("the sound volume sets the effects bus", absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.5)) < 0.1, "%.1f dB" % AudioServer.get_bus_volume_db(sfx_bus))
	GameState.sound_volume = volume
	# state 3: it rolls away for 250 frames, then rests
	ball.set_physics_process(true)
	ball.state = 3
	ball.state2 = 0.0
	ball.frame = 600.0
	var far_start: float = ball.global_position.distance_to(player.global_position)
	await secs(2.0)
	check("state 3: it rolls away", ball.global_position.distance_to(player.global_position) > far_start + 0.3 or ball.state == 0, "%.1f -> %.1f" % [far_start, ball.global_position.distance_to(player.global_position)])
	ball.state2 = 249.0
	for i in 100:
		await secs(0.1)
		if ball.state <= 1:
			break
	check("then it settles and, near the player still, stares again (0 or 1)", ball.state <= 1, "state %d" % ball.state)
	ball.queue_free()
	GameState.deaf_timer = 0.0
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	var shape := Node3D.new()
	shape.set_script(load("res://scripts/npc/scp_372.gd"))
	get_tree().get_first_node_in_group("facility").get_parent().add_child(shape)
	shape.global_position = base + Vector3(0.0, 0.0, 3.0)
	await secs(0.3)
	check("a new SCP-372 is soon idle (hidden)", shape.idle and not shape.visible, "idle %s" % str(shape.idle))
	GameState.achievements.erase("372")
	player.blink_timer = -10.0
	var shown := false
	for i in 60:
		player.blink_timer = -10.0
		await secs(0.1)
		if not shape.idle:
			shown = true
			break
	check("with the eyes shut it appears", shown and shape.visible, "")
	if shown:
		var d: float = Vector2(shape.global_position.x - player.global_position.x, shape.global_position.z - player.global_position.z).length()
		check("1.5-2 m from the player", d > 1.3 and d < 2.2, "%.2f" % d)
		player.blink_timer = 100.0
		face_point(shape.global_position + Vector3(0.0, 0.3, 0.0))
		GameState.blur_timer = 0.0
		GameState.blur_volume = 0.0
		await secs(0.2)
		await shot("npc372")
		check("seen on screen it gives the achievement", GameState.achievements.has("372"), "")
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(3.0, 3.0, 0.1)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		get_tree().root.add_child(wall)
		wall.global_position = player.camera.global_position.lerp(shape.global_position, 0.5)
		wall.look_at(shape.global_position)
		await get_tree().physics_frame
		check("the rustle needs a clear line to the camera (EntityVisible): a wall in the way silences it", not shape._in_line_of_sight(player, 0.3), "")
		wall.queue_free()
		shape.state = 1.0
		await secs(0.5)
		check("and vanishes when its time is up", shape.idle, "state %.1f" % shape.state)
	shape.queue_free()
	# --- SCP-513-1: rung with the bell
	# it needs another room's waypoint 3-9 away on both axes, so stand on a waypoint that has one
	var graph = facility.graph
	for id in graph.point_ids():
		var p: Vector3 = graph.position_of(id)
		var fits := false
		for other in graph.point_ids():
			if graph.room_key_of(other) == graph.room_key_of(id):
				continue
			var q: Vector3 = graph.position_of(other)
			var dx := absf(p.x - q.x)
			var dz := absf(p.z - q.z)
			if dx > 3.0 and dx < 9.0 and dz > 3.0 and dz < 9.0:
				fits = true
				break
		if fits and str(facility.record_at(p).get("key", "")) == graph.room_key_of(id):
			place_player(p + Vector3(0.0, 0.1, 0.0))
			await secs(0.5)
			break
	var bell: int = _give(hud, "SCP-513", "scp513")
	await _use_slot(hud, bell)
	await secs(0.3)
	var ghost: Node3D = get_tree().get_first_node_in_group("scp513_1")
	check("ringing SCP-513 makes SCP-513-1 (only one)", ghost != null, "")
	if ghost != null:
		var appeared := false
		# looked at every frame: the timer starts at 15 to 20 s and has run 7 frames down after a 0.1 s wait, past the margin
		for i in 15 * 70:
			await get_tree().process_frame
			if not ghost.idle:
				appeared = true
				break
		check("soon it shows itself on a waypoint in another room", appeared and ghost._body.visible and ghost.state2 >= 15.0 * 70.0 - 5.0, "appeared %s" % str(appeared))
		if appeared:
			var far := Vector2(ghost.global_position.x - player.global_position.x, ghost.global_position.z - player.global_position.z).length()
			check("3 to 9 away on both axes", far > 3.0 and far < 13.0, "%.1f" % far)
			ghost.state = 1
			ghost.prev_state = 0
			face_point(ghost.global_position + Vector3(0.0, 0.8, 0.0))
			GameState.blur_timer = 0.0
			GameState.blur_volume = 0.0
			await secs(0.2)
			await shot("npc5131")
			var start: Vector3 = ghost.global_position
			await secs(2.0)
			check("walking it keeps to its waypoints and animates", ghost.frame >= 125.0 or ghost.state != 1 or ghost.idle, "frame %.0f" % ghost.frame)
			ghost.state2 = 1.0
			var vanished := false
			for i in 40:
				await secs(0.02)
				if ghost.idle:
					vanished = true
					break
			check("when its time runs out it vanishes", vanished, "")
		ghost.idle = false
		ghost.state = 0
		ghost.state2 = 5000.0
		ghost.path = -1
		ghost._show()
		place_player(base)
		ghost.global_position = base + Vector3(2.5, 0.2, 0.0)
		await secs(0.1)
		face_point(ghost.global_position + Vector3(0.0, 0.8, 0.0))
		GameState.blur_timer = 0.0
		GameState.blur_volume = 0.0
		await secs(0.1)
		await shot("npc5131_close")
		await _use_slot(hud, bell)
		await secs(0.3)
		check("ringing it again does not make a second one", get_tree().get_nodes_in_group("scp513_1").size() == 1, "")
		ghost.queue_free()
	GameState.god_mode = false

# ---------------------------------------------------------------- room1lifts, room2shaft, room3pit1048, room2storage (SCP-970)

func camera_reset_shake() -> void:
	player.camera_shake = 0.0

func _scn_049doors() -> void:
	log_line("== 049 closing doors behind him (state 5)")
	var setup: Dictionary = await _room2sl_setup()
	if setup.is_empty():
		check("the map has a room2sl", false, "")
		return
	var room: Node3D = setup.room
	GameState.god_mode = true
	facility.spawn_049_enabled = false
	var doors: Array = facility.room_edge_doors(room)
	var cell: Vector3 = room.object_point(7)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(cell) < b.global_position.distance_to(cell))
	# a path ends at the waypoint nearest its target, so the target is a waypoint well past the door in the room beyond
	var door: Node3D = null
	var inward := Vector3.ZERO
	var to_spot := Vector3.ZERO
	for candidate: Node3D in doors:
		if candidate.keycard != 0 or candidate.locked:
			continue
		var into: Vector3 = room.global_position - candidate.global_position
		into.y = 0.0
		into = into.normalized()
		var beyond: Dictionary = facility.record_at(candidate.global_position - into * 3.0)
		if beyond.is_empty():
			continue
		var beyond_room := facility.rooms.get_room(beyond)
		var best := INF
		for index in facility.waypoints().size():
			if facility.rooms.waypoint_rooms()[index] != beyond_room:
				continue
			var p: Vector3 = facility.waypoints()[index]
			var past: float = (candidate.global_position - p).dot(into)
			var dist: float = p.distance_to(candidate.global_position)
			if past > 2.2 and absf(p.y - candidate.global_position.y) < 1.0 and dist < best:
				best = dist
				door = candidate
				inward = into
				to_spot = p + Vector3(0.0, 0.1, 0.0)
		if door != null:
			break
	check("an ordinary door to walk through, with a waypoint past it", door != null, "")
	if door == null:
		return
	var from_spot: Vector3 = door.global_position + inward * 2.5 + Vector3(0.0, 0.1, 0.0)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(door.global_position) > b.global_position.distance_to(door.global_position))
	var far_door: Node3D = doors[0]
	# the player waits behind the other door, out of 049's sight
	var behind: Vector3 = far_door.global_position - room.global_position
	behind.y = 0.0
	place_player(far_door.global_position + behind.normalized() * 6.0 + Vector3(0.0, 0.3, 0.0))
	await secs(1.0)
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	npc.state = 5
	npc.prev_state = 2
	npc.global_position = from_spot
	npc.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var status: int = npc.route_to(to_spot)
	check("there is a route through the door", status == 1, "status %d" % status)
	var sounds := {}
	var count_sounds := func(node: Node) -> void:
		if node is AudioStreamPlayer3D and node.get_parent() != null and node.get_parent().has_method("npc_open"):
			sounds[node.get_parent()] = int(sounds.get(node.get_parent(), 0)) + 1
	get_tree().node_added.connect(count_sounds)
	var waited := 0.0
	while waited < 40.0 and npc.state == 5 and npc.walking():
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(1.5)
	get_tree().node_added.disconnect(count_sounds)
	var worst := 0
	for node in sounds:
		worst = maxi(worst, int(sounds[node]))
	check("he walked through and out (state 5 kept)", npc.state == 5 and npc.global_position.distance_to(door.global_position) > 1.5, "state %d, %.1f from the door" % [npc.state, npc.global_position.distance_to(door.global_position)])
	check("the door he left behind opens once and shuts once, not with every frame", worst <= 4 and sounds.has(door), "%d sounds from one door at worst; the door itself %d" % [worst, int(sounds.get(door, 0))])
	check("and stays shut behind him", not door.open, "")
	npc.queue_free()
	facility.scp049 = null
	facility.spawn_049_enabled = true
	GameState.god_mode = false

# ---------------------------------------------------------------- UpdateRooms: which rooms and meshes are drawn

# Grid distance through existing rooms (a neighbour is the room one cell away; the start chamber's footprint holds none).
func _ring_of(from_key: String) -> Dictionary:
	var ring := {from_key: 0}
	var queue: Array = [from_key]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		if int(ring[key]) >= 3:
			continue
		for i in 4:
			var other: Dictionary = facility.drawing.neighbour_of(facility.rooms.by_grid[key], i)
			if other.is_empty() or ring.has(other.key):
				continue
			ring[other.key] = int(ring[key]) + 1
			queue.append(other.key)
	return ring

# Loaded rooms the rule is not drawing in full: hidden whole, or without their mesh.
func _hidden_rooms() -> int:
	var count := 0
	for key in facility.rooms.built:
		var room: Node3D = facility.rooms.built[key]
		if is_instance_valid(room) and (not room.visible or (room.visual != null and not room.visual.visible)):
			count += 1
	return count

# ---------------------------------------------------------------- the room-drawing rule: what it costs and what it saves (needs the real renderer: run with -Shots)

# Main.bb Kill(): the head drops, the view blurs and darkens with KillTimer, the panel comes at -360.
func _scn_deathcam() -> void:
	log_line("== death camera")
	GameState.god_mode = false
	var hud := get_tree().get_first_node_in_group("hud")
	var start_y: float = player.camera.global_position.y
	player.kill("test")
	check("KillTimer starts at -1", player.kill_timer <= -1.0, "%.2f" % player.kill_timer)
	await secs(0.5)
	check("the head falls", player.camera.global_position.y < start_y - 0.1, "%.2f -> %.2f" % [start_y, player.camera.global_position.y])
	check("the view blurs", GameState.blur_volume > 0.05, "%.2f" % GameState.blur_volume)
	check("no panel yet", not hud.pause_menu.visible, "timer %.0f" % player.kill_timer)
	await secs(3.0)
	check("still no panel after 3.5 s", not hud.pause_menu.visible, "timer %.0f" % player.kill_timer)
	await secs(4.0)
	check("the panel opens past -360", hud.pause_menu.visible and player.kill_timer < -360.0, "timer %.0f" % player.kill_timer)
	hud.cancel_death()
	player.dead = false
	player.restore_view()
	GameState.god_mode = true

# 106 hunts along waypoints when the player is out of his sight within 25: he reaches each waypoint (inside 0.2 of his collider)
# and gets nearer the player instead of circling one.
func _scn_chase106() -> void:
	log_line("== 106 follows waypoint routes")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var pair: Dictionary = _find_walkable_pair()
	if pair.start_id < 0:
		check("a route for 106 exists", false, "")
		return
	var graph: Object = facility.graph
	var goal: Vector3 = graph.astar.get_point_position(pair.start_id)
	place_player(goal + Vector3(0.0, 0.1, 0.0))
	await secs(4.0)
	var from := Vector3.ZERO
	var found := false
	for id in graph._owner_of:
		var p: Vector3 = graph.astar.get_point_position(id)
		var d := flat_dist(p, goal)
		if d < 10.0 or d > 20.0 or absf(p.y - goal.y) > 1.0 or not ray_blocked(p + Vector3(0, 0.4, 0), player.global_position + Vector3(0, 0.4, 0)):
			continue
		var result: Dictionary = facility.find_path(p, player.global_position)
		if int(result.status) == 1 and result.points.size() >= 4:
			from = p
			found = true
			break
	if not found:
		check("a route for 106 exists", false, "")
		return
	var npc: CharacterBody3D = facility.spawn_106(-10.0)
	npc.frame = 260.0
	npc.global_position = from - Vector3(0.0, 0.26, 0.0)
	npc.path_timer = 0.0
	npc._route_status = 1
	var began := flat_dist(from, player.global_position)
	var reached := 0
	var last_index := 0
	var t := 0.0
	var closest := began
	while t < 60.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		npc.state = minf(npc.state, -10.0)
		npc.reload = 100.0
		if npc._route_index > last_index:
			reached += npc._route_index - last_index
		last_index = npc._route_index
		var flat := flat_dist(npc.global_position, player.global_position)
		closest = minf(closest, flat)
		if flat < 1.0:
			break
	check("106 reaches waypoints on his route", reached >= 2, "%d reached" % reached)
	check("and comes up to the player", closest < 1.5, "%.1f -> %.1f m in %.0f s" % [began, closest, t])
	npc.queue_free()
	facility.scp106 = null
	GameState.god_mode = false

# NPCs.bb:1003 / 1014: 106 rising out of the floor cuts the music (ShouldPlay 66), hunting plays Music(10) = 106.ogg
func _scn_npcmusic() -> void:
	log_line("== 106's music")
	GameState.god_mode = true
	GameState.music_override = ""
	var audio: Node = get_tree().get_first_node_in_group("audio")
	var npc: CharacterBody3D = facility.spawn_106(-5.0)
	npc.frame = 110.0
	await secs(0.3)
	check("while he rises the music is cut", GameState.npc_music() == "none", GameState.npc_music())
	npc.state = -10.0
	npc.frame = 260.0
	await secs(0.3)
	check("hunting plays 106.ogg", GameState.npc_music() == "106", GameState.npc_music())
	check("and the director picks it", audio._should_play == "106", str(audio._should_play))
	GameState.music_override = "PD"
	await secs(0.3)
	check("his music wins over an event's music (UpdateNPCs runs after UpdateEvents)", audio._should_play == "106", str(audio._should_play))
	GameState.music_override = "Custom/x"
	await secs(0.3)
	check("the console's custom track stays above his", audio._should_play == "Custom/x", str(audio._should_play))
	GameState.music_override = ""
	npc.state = 25000.0
	await secs(0.3)
	check("once he is gone the music is the zone's", GameState.npc_music() == "", GameState.npc_music())
	npc.queue_free()
	facility.scp106 = null
	GameState.god_mode = false

# Walked, not teleported: from where crouching before 106's eyes drops the player, along the trenches into the sinkhole
# (the trench floor rises above the collider height 12 that the event pulls the player down to), then to the exit swirl.
func _scn_pocketwalk() -> void:
	log_line("== pocket dimension on foot")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var old_man: CharacterBody3D = facility.spawn_106(5000.0)
	await get_tree().physics_frame
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	await secs(1.0)
	old_man.state = 5000.0
	var rs: float = pocket.RS
	var centre: Vector3 = pocket.B(0.0, 0.0, 32.0)
	var route := _trench_route(centre, pocket.B(-1344.0 * rs, 0.0, 32.0 - 1184.0 * rs))
	check("the trenches lead to a sinkhole", not route.is_empty(), "")
	if route.is_empty():
		return
	pocket.event_state2 = 1
	pocket.event_state3 = 0
	pocket._put_collider(player, -1344.0 * rs, 2944.0 * rs, 32.0 - 1184.0 * rs)
	await secs(0.5)
	var index := 0
	var t := 0.0
	Input.action_press("move_forward")
	while t < 60.0 and pocket._collider_y(player) > 8.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		while index < route.size() - 1 and flat_dist(route[index], player.global_position) < 0.35:
			index += 1
		face_point(route[index])
	await secs(0.3)
	Input.action_release("move_forward")
	check("walking the trenches drops the player into the exit room", player.global_position.y < 0.0 and not player.dead, "y %.2f after %.1f s, waypoint %d/%d" % [player.global_position.y, t, index, route.size()])
	pocket.event_state2 = 1
	pocket.event_state3 = 0
	pocket._put_collider(player, -400.0 * rs, -304.0 * rs, 32.0)
	await secs(1.0)
	var swirl: Vector3 = pocket.B(1024.0 * rs, 0.0, 32.0)
	t = 0.0
	Input.action_press("move_forward")
	while t < 20.0 and pocket.player_inside:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		face_point(swirl)
	Input.action_release("move_forward")
	check("walking to the swirl leads out", not pocket.player_inside, "%.1f s" % t)
	old_man.queue_free()
	facility.scp106 = null

# Flood over floor heights on a 0.25 grid under the trench terrain (rays cast as cells are reached), from `from` with steps up
# to 0.3 and any drop, to the first cell low enough for the sinkhole; returns that route thinned to every third cell, then the
# deepest point next to it.
func _trench_route(centre: Vector3, from: Vector3) -> Array[Vector3]:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var space := get_viewport().world_3d.direct_space_state
	var floor_y := {}
	var floor_at := func(cell: Vector2i) -> float:
		if not floor_y.has(cell):
			query.from = centre + Vector3(cell.x * 0.25, 30.0, cell.y * 0.25)
			query.to = query.from + Vector3(0, -25.0, 0)
			var hit := space.intersect_ray(query)
			floor_y[cell] = hit.position.y if not hit.is_empty() else INF
		return floor_y[cell]
	var start := Vector2i(roundi((from.x - centre.x) / 0.25), roundi((from.z - centre.z) / 0.25))
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	var route: Array[Vector3] = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var height: float = floor_at.call(cell)
		if height == INF:
			continue
		if height + 0.3 < 8.5:
			var cells: Array[Vector2i] = []
			var walk := cell
			while walk != start:
				cells.push_front(walk)
				walk = parent[walk]
			for k in cells.size():
				if k % 3 == 0 or k == cells.size() - 1:
					route.append(centre + Vector3(cells[k].x * 0.25, floor_y[cells[k]], cells[k].y * 0.25))
			var deepest := cell
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					var near := cell + Vector2i(dx, dz)
					if floor_at.call(near) < floor_y[deepest]:
						deepest = near
			route.append(centre + Vector3(deepest.x * 0.25, floor_y[deepest], deepest.y * 0.25))
			return route
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if absi(next.x) <= 120 and absi(next.y) <= 120 and not parent.has(next) and floor_at.call(next) - height <= 0.3:
				parent[next] = cell
				queue.append(next)
	return route

func _scn_npcgravity() -> void:
	log_line("== NPC gravity (NPCs.bb 5003-5096)")
	revive()
	GameState.god_mode = true
	var record: Dictionary = await _event_room()
	place_player(record.position + Vector3(0.0, 1.2, 0.0))
	await secs(0.5)
	var at: Vector3 = player.global_position
	statue.active = true
	statue.idle = 1
	check("InFacility: 1 in the rooms, 2 in the tunnels and above 7, 0 over 100", NpcGravity.in_facility(0.3) == 1 and NpcGravity.in_facility(7.0) == 1 and NpcGravity.in_facility(7.1) == 2 and NpcGravity.in_facility(100.0) == 2 and NpcGravity.in_facility(100.1) == 0 and NpcGravity.in_facility(-10.1) == 2, "")
	place_statue(at + Vector3(20.0, 5.0, 0.0))
	await secs(0.8)
	check("an NPC more than 10.5 away does not move vertically", absf(statue.global_position.y - (at.y + 5.0)) < 0.01, "y %.2f" % statue.global_position.y)
	place_statue(at + Vector3(3.0, 3.0, 0.0))
	await secs(0.8)
	check("inside the visible rooms it falls", statue.global_position.y < at.y + 2.5, "y %.2f" % statue.global_position.y)
	place_statue(at + Vector3(3.0, 20.0, 0.0))
	await secs(0.8)
	check("with another InFacility than the player's it does not fall", absf(statue.global_position.y - (at.y + 20.0)) < 0.01, "y %.2f" % statue.global_position.y)
	place_statue(at + Vector3(3.0, 3.0, 0.0))
	var ring: Array = facility.drawing.ring_rooms
	facility.drawing.ring_rooms = []
	check("outside the visible rooms it holds its height", NpcGravity.mode(statue, facility) == NpcGravity.HOLD, "")
	check("unless FallingPickDistance is 0", NpcGravity.mode(statue, facility, 0.0) == NpcGravity.FALL, "")
	facility.events.room860.state = 1.0
	check("or the player is in the forest", NpcGravity.mode(statue, facility) == NpcGravity.FALL, "")
	facility.events.room860.state = 0.0
	place_statue(at + Vector3(20.0, 3.0, 0.0))
	check("an SCP-1499-1 is exempt from the distance", NpcGravity.mode(statue, facility, 10.0, true) == NpcGravity.HOLD and NpcGravity.mode(statue, facility) == NpcGravity.NO_MOVE, "")
	facility.drawing.ring_rooms = ring
	statue.idle = 0
	statue.active = false

# UpdateMTFUnit state 0 (NPCs.bb 5338-5427): the leader picks a room anywhere on the map and FindPath covers the whole graph, so a
# unit far from the player walks through rooms that are hidden and without collision, and keeps its height there (NPCs.bb 5003-5096).
func _scn_mtfcross() -> void:
	log_line("== MTF leader across hidden rooms")
	await _reset_world()
	GameState.god_mode = true
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(1.0)
	var goals: Array[Vector3] = []
	for record in facility.generator.rooms:
		goals.append(Vector3(record.position.x, 0.1, record.position.z))
		if goals.size() >= 6:
			break
	var candidates: Array[Vector3] = []
	var index := 0
	for w in facility.waypoints():
		var d := home.distance_to(w)
		index += 1
		if d > 50.0 and d < 90.0 and absf(w.y - home.y) < 1.5 and index % 5 == 0:
			for goal in goals:
				var route: Dictionary = facility.find_path(w, goal)
				if int(route.status) == 1 and route.points.size() >= 8:
					candidates.append(w)
					break
			if candidates.size() >= 4:
				break
	check("a waypoint 50-90 m from the player with a long route to one of the first rooms", not candidates.is_empty(), "")
	var planned := false
	var leader: CharacterBody3D = null
	var route: Array[Vector3] = []
	for spot in candidates:
		_clear_mtf()
		leader = facility.mtf.spawn(spot + Vector3(0.0, 0.1, 0.0))
		leader.no_target = true
		var waited := 0.0
		while waited < 14.0 and not (leader.path_status == 1 and leader.path.size() >= 3):
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
		if leader.path_status == 1 and leader.path.size() >= 3:
			planned = true
			route = leader.path.duplicate()
			break
	check("the far leader plans a route across the map", planned, "")
	if not planned:
		_clear_mtf()
		GameState.god_mode = false
		return
	leader.path_timer = 70.0 * 600.0
	var hidden_nodes := 0
	for p in route:
		var room: Node3D = facility.room_at(p)
		if room != null and not facility.drawing.ring_rooms.has(room):
			hidden_nodes += 1
	check("the route runs through hidden rooms", hidden_nodes >= 2, "%d of %d nodes" % [hidden_nodes, route.size()])
	var low := INF
	var high := -INF
	for p in route:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var min_y := INF
	var max_y := -INF
	var max_jump := 0.0
	var min_player := INF
	var hidden_frames := 0
	var last: Vector3 = leader.global_position
	var waited := 0.0
	while waited < 200.0 and leader.path_status == 1:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		var at: Vector3 = leader.global_position
		min_y = minf(min_y, at.y)
		max_y = maxf(max_y, at.y)
		max_jump = maxf(max_jump, at.distance_to(last))
		last = at
		min_player = minf(min_player, at.distance_to(player.global_position))
		var inside: Node3D = facility.room_at(at)
		if inside != null and not facility.drawing.ring_rooms.has(inside):
			hidden_frames += 1
	var end: Vector3 = route.back()
	var gap := flat_dist(leader.global_position, end)
	log_line("   walked %d nodes in %.0f s, %d frames in hidden rooms, y %.2f..%.2f, nearest the player %.1f m" % [route.size(), waited, hidden_frames, min_y, max_y, min_player])
	check("the leader finishes the route", leader.path_status != 1, "status %d after %.0f s" % [leader.path_status, waited])
	check("he ends within a few metres of the route's last node", gap < 3.0, "%.1f m" % gap)
	check("he walked in hidden rooms", hidden_frames > 70, "%d frames" % hidden_frames)
	check("he keeps his height (NpcGravity)", min_y > low - 1.0 and max_y < high + 1.0, "y %.2f..%.2f, route %.2f..%.2f" % [min_y, max_y, low, high])
	check("he never teleports", max_jump < 0.5, "%.2f m in one frame" % max_jump)
	_clear_mtf()
	GameState.god_mode = false

func _scn_pocketface() -> void:
	log_line("== 106face flash on a blink in the pocket dimension")
	statue.active = false
	GameState.god_mode = true
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	pocket.event_state2 = 1
	pocket.event_state = 700.0
	pocket.event_str = 0.0
	player.blink_timer = -4.0
	var shown := false
	for i in 600:
		player.blink_timer = -4.0
		await get_tree().physics_frame
		if pocket._face != null and pocket._face.visible:
			shown = true
			break
	check("the face shows during a blink after 600 frames", shown, "")
	pocket.event_str = 1000.0
	player.blink_timer = -4.0
	await get_tree().physics_frame
	check("it is hidden once the eyes were met", pocket._face != null and not pocket._face.visible, "")
	pocket.event_str = 0.0
	player.blink_timer = 300.0
	await get_tree().physics_frame
	check("it is hidden when the blink ends", pocket._face != null and not pocket._face.visible, "")
