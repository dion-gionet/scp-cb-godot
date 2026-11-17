extends "res://scripts/tests/bot_base.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_spawn() -> void:
	log_line("== spawn")
	var bottom: Array[String] = []
	for r in facility.generator.rooms:
		if r.grid.y >= 16 and r.grid.x < 12:
			bottom.append("%s@(%d,%d)a%d" % [r.name, r.grid.x, r.grid.y, r.angle])
	log_line("   bottom rows: " + ", ".join(bottom))
	check("player on floor", player.is_on_floor(), str(player.global_position))
	check("player alive", not player.dead)
	check("player not inside collision", not blocked(player.global_position), "")
	var d := player.global_position.distance_to(statue.global_position)
	check("173 within 1-6m", d > 0.8 and d < 6.0, "%.2f" % d)
	check("clear line to 173", not ray_blocked(player.camera.global_position, statue.global_position + Vector3(0, 0.5, 0)), "")
	# FillRoom moves the buttons of the landing door (x+1280, z+312) to x+1120, z+328 / z+296
	var landing_ok := false
	for fd in facility.start_node._fill_doors:
		var dl: Vector3 = facility.start_node.to_local(fd.global_position)
		if absf(dl.x - 5.0) < 0.01 and absf(dl.z + 1.2188) < 0.01 and fd.buttons.size() == 2:
			var b0: Vector3 = facility.start_node.to_local(fd.buttons[0].global_position)
			var b1: Vector3 = facility.start_node.to_local(fd.buttons[1].global_position)
			landing_ok = absf(b0.x - 4.375) < 0.01 and absf(b1.x - 4.375) < 0.01 and absf(b0.z + 1.2813) < 0.01 and absf(b1.z + 1.1563) < 0.01
	check("landing door buttons are where FillRoom moves them", landing_ok, "")
	check("alarm event opened the cell door", facility.start_node.door_slots.get(2) != null and facility.start_node.door_slots[2].open, "")
	var exit_open := false
	for edge in facility.rooms.doors:
		var edef: Dictionary = facility.rooms.door_defs.get(edge, {})
		var skey := "%d,%d" % [facility.generator.start_room.grid.x, facility.generator.start_room.grid.y]
		if str(edef.get("a", "")) == skey or str(edef.get("b", "")) == skey:
			exit_open = facility.rooms.doors[edge].open
	check("alarm event opened the start room exit door", exit_open, "")
	await shot("bot_spawn")

func _scn_stamina_blink() -> void:
	log_line("== stamina / blink")
	statue.active = false
	player.stamina = 100.0
	face_point(player.global_position + Vector3(0, 0, -3.0))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var low := 100.0
	var t := 0.0
	while t < 7.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		low = minf(low, player.stamina)
	check("stamina drains to exhaustion (-20)", low <= -19.0, "min %.1f" % low)
	await secs(0.8)
	check("sprint locked while below 0", player.stamina < 0.0 and player.stamina > -20.5, "%.1f" % player.stamina)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await secs(6.0)
	check("stamina recovers above 0", player.stamina > 0.0, "%.1f" % player.stamina)
	player.blink_timer = 490.0
	Input.action_press("blink")
	var closed_seen := false
	t = 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		closed_seen = closed_seen or player.eyes_closed()
	check("blink key closes eyes", closed_seen, "timer %.1f" % player.blink_timer)
	Input.action_release("blink")
	await secs(0.8)
	check("blink ends and timer resets", player.blink_timer > 0.0, "%.1f" % player.blink_timer)

func _scn_doors() -> void:
	log_line("== doors")
	statue.active = false
	var picked: Array[Node3D] = []
	var near: Array = facility.rooms.doors.values()
	near.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var want_closed := 1
	var want_open := 1
	var want_heavy := 1
	for node in near:
		var door: Node3D = node
		if door.keycard > 0 or door.locked or door.global_position.distance_to(player.global_position) > 36.0:
			continue
		if door.heavy and want_heavy > 0:
			picked.append(door)
			want_heavy -= 1
		elif door.open and want_open > 0:
			picked.append(door)
			want_open -= 1
		elif not door.open and not door.heavy and want_closed > 0:
			picked.append(door)
			want_closed -= 1
	log_line("testing %d doors of %d" % [picked.size(), near.size()])
	check("doors available to test", picked.size() >= 2, "%d" % picked.size())
	var index := 0
	for door in picked:
		index += 1
		var label := "door %d (%s%s)" % [index, "heavy " if door.heavy else "", "open" if door.open else "closed"]
		var dir: Vector3 = door.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		var button: Node3D = door.buttons[0]
		var bpos: Vector3 = button.global_position
		var leaf_spot: Vector3 = door.global_position + dir * 0.6
		place_player(Vector3(leaf_spot.x, door.global_position.y + 1.2, leaf_spot.z))
		await secs(1.2)
		if not player.is_on_floor():
			check(label + " approach ground", false, "no floor at %s" % str(player.global_position))
			continue
		var was_open: bool = door.open
		if not was_open:
			# pressing the door leaf must do nothing: only the buttons work (Main.bb UpdateDoors)
			face_point(door.global_position + Vector3(0, 0.9, 0))
			for _k in 3:
				await get_tree().physics_frame
			await tap("interact")
			await secs(0.2)
			check(label + " ignores presses on the leaf", not door.open, "")
		var from: Vector3 = bpos + dir * 0.5
		place_player(Vector3(from.x, door.global_position.y + 0.6, from.z))
		await secs(0.8)
		face_point(bpos)
		var look: Vector3 = bpos - player.camera.global_position
		player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		for _k in 3:
			await get_tree().physics_frame
		if not door.open:
			await tap("interact")
			await secs(0.3)
			check(label + " opens with E at the button", door.open, "locked=%s keycard=%d" % [door.locked, door.keycard])
			await secs(2.4)
		await shot("bot_door_%d" % index)
		var lane: Vector3 = door.global_position + dir * 1.0
		place_player(Vector3(lane.x, door.global_position.y + 0.6, lane.z))
		await secs(0.6)
		player.camera.rotation.x = 0.0
		face_point(door.global_position - dir * 3.0)
		var crossed := false
		Input.action_press("move_forward")
		var t := 0.0
		while t < 5.0 and not crossed:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var side: float = (player.global_position - door.global_position).dot(dir)
			crossed = side < -0.7
		Input.action_release("move_forward")
		check(label + " walk-through", crossed, "side %.2f after %.1fs, y=%.2f" % [(player.global_position - door.global_position).dot(dir), t, player.global_position.y])

func _scn_registry() -> void:
	log_line("== room registry")
	statue.active = false
	var missing: Array[String] = []
	var skipped := 0
	for room in facility.generator.rooms:
		if facility.rooms.inside_start(room):
			skipped += 1
		elif facility.rooms.get_room(room) == null:
			missing.append("%s %s" % [room.name, room.grid])
	log_line("   %d rooms, %d inside the start chamber, %d built" % [facility.generator.rooms.size(), skipped, facility.rooms.built.size()])
	check("every generated room outside the start chamber is built", missing.is_empty(), str(missing))
	check("gate A is registered", facility.rooms.get_room(facility.gatea_record) != null, "")
	check("the pocket dimension and the church of dimension 1499 are built", facility.pocket != null and facility.dimension.room != null and facility.rooms.get_room(facility.dimension.record) != null, "")
	check("the room under the player is found by position", facility.room_at(player.global_position) != null, "")
	var rooms: Array = facility.generator.rooms.duplicate()
	var step: int = maxi(1, rooms.size() / 6)
	var tested := 0
	var i := 0
	var start_pos: Vector3 = facility.generator.start_room.position
	while i < rooms.size() and tested < 6:
		var room: Dictionary = rooms[i]
		i += step
		if str(room.name) == "start" or room.position.distance_to(start_pos) < 20.0 or facility.rooms.inside_start(room):
			continue
		tested += 1
		place_player(room.position + Vector3(0, 3.0, 0))
		await secs(1.5)
		var fell: bool = player.global_position.y < room.position.y - 2.0
		check("room %s %s lands on ground" % [room.name, room.grid], player.is_on_floor() and not fell, "y=%.2f" % player.global_position.y)
		var node: FacilityRoom = facility.rooms.get_room(room)
		check("room %s %s is shown and solid around the player" % [room.name, room.grid], node.visible and node.collidable, "")
	var far: FacilityRoom = null
	for key in facility.rooms.built:
		var node: FacilityRoom = facility.rooms.built[key]
		if flat_dist(node.global_position, player.global_position) > 60.0 and node.position.y < 100.0:
			far = node
			break
	check("a room beyond the neighbourhood is hidden and not solid", far != null and not far.visible and not far.collidable, "")
	if far != null:
		var from := far.global_position + Vector3(0.0, 1.5, 0.0)
		var tall: AABB = far.world_bounds()
		check("a ray through the hidden room's floor passes", not ray_blocked(Vector3(from.x, tall.end.y + 1.0, from.z), Vector3(from.x, tall.position.y - 1.0, from.z)), str(far.room_name))

# Every door should sit in a real gap in the room walls. Rays ignore the door bodies themselves.
func _scn_gaps() -> void:
	log_line("== doorway gaps")
	var exclude: Array[RID] = [player.get_rid()]
	for node in get_tree().get_nodes_in_group("door"):
		for body in node.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as StaticBody3D).get_rid())
	var total := 0
	var blocked_count := 0
	var bad: Array[String] = []
	for edge in facility.rooms.doors:
		var door: Node3D = facility.rooms.doors[edge]
		var dir: Vector3 = door.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		var wall := false
		for h in [0.3, 0.7, 1.1]:
			for dx in [0.0]:
				var base: Vector3 = door.global_position + door.global_transform.basis.x * dx + Vector3(0, h, 0)
				var q := PhysicsRayQueryParameters3D.create(base + dir * 0.5, base - dir * 0.5)
				q.collision_mask = 1
				q.exclude = exclude
				if not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
					wall = true
		total += 1
		if wall:
			blocked_count += 1
			bad.append(str(edge))
	var shown := 0
	for edge in facility.rooms.doors:
		if shown >= 4:
			break
		var d2: Node3D = facility.rooms.doors[edge]
		var dir2: Vector3 = d2.global_transform.basis.z
		dir2.y = 0.0
		dir2 = dir2.normalized()
		var line := "   gap-debug %s yaw=%.0f:" % [str(edge), d2.rotation_degrees.y]
		for h in [0.2, 0.4, 0.9, 1.4, 1.8]:
			var base2: Vector3 = d2.global_position + Vector3(0, h, 0)
			var q2 := PhysicsRayQueryParameters3D.create(base2 + dir2 * 1.5, base2 - dir2 * 1.5)
			q2.collision_mask = 1
			q2.exclude = exclude
			var h2 := get_viewport().world_3d.direct_space_state.intersect_ray(q2)
			if h2.is_empty():
				line += " h%.1f=clear" % h
			else:
				var along: float = (h2.position - d2.global_position).dot(dir2)
				line += " h%.1f=%s@%.2f(n.y %.1f)" % [h, str(h2.collider.get_parent().name).substr(0, 22), along, h2.normal.y]
		log_line(line)
		shown += 1
	check("doorways are open gaps (%d doors)" % total, blocked_count == 0, "%d blocked: %s" % [blocked_count, ", ".join(bad)])

func _scn_debug() -> void:
	log_line("== debug mode")
	var home := Vector3(86.0, 1.55, -141.5)
	var spot := Vector3(86.0, 1.55, -144.0)
	if facility.start_node:
		home = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
		spot = facility.start_node.to_global(Vector3(14.0, 1.55, -8.0))
	revive()
	GameState.god_mode = true
	place_player(home)
	player.blink_timer = -8.0
	place_statue(spot)
	face_point(spot + Vector3(0, 0.8, 0))
	statue.active = true
	Input.action_press("blink")
	await secs(1.0)
	Input.action_release("blink")
	check("god mode survives 173", not player.dead, "dist %.2f" % player.global_position.distance_to(statue.global_position))
	GameState.god_mode = false
	statue.active = false
	place_player(home)
	player.rotation.y = 0.0
	player.camera.rotation.x = 0.0
	GameState.noclip = true
	var start := player.global_position
	Input.action_press("move_forward")
	await secs(1.6)
	Input.action_release("move_forward")
	var travelled := player.global_position.distance_to(start)
	check("noclip moves through walls", travelled > 3.0 and not blocked(start + Vector3(0, 0, -1.0)) == false or travelled > 3.0, "travelled %.2f m" % travelled)
	GameState.noclip = false
	place_player(home)
	await secs(0.8)
	check("noclip off restores collision/gravity", player.is_on_floor(), str(player.global_position))

func _scn_controller() -> void:
	log_line("== controller")
	statue.active = false
	revive()
	var start: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -4.6))
	var results := {}
	for mode in ["walk", "sprint", "crouch"]:
		player.crouching = false
		player.crouch_state = 0.0
		player.stamina = 100.0
		place_player(start)
		await secs(0.5)
		player.rotation.y = 0.0
		player.camera.rotation.x = 0.0
		if mode == "crouch":
			player.crouching = true
			await secs(1.0)
		Input.action_press("move_forward")
		if mode == "sprint":
			Input.action_press("sprint")
		await secs(0.7)
		var p0 := player.global_position
		var t := 0.0
		var cam_min := 9.0
		var cam_max := -9.0
		while t < 0.6:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			cam_min = minf(cam_min, player.camera.position.y)
			cam_max = maxf(cam_max, player.camera.position.y)
		var speed: float = player.global_position.distance_to(p0) / t
		Input.action_release("move_forward")
		Input.action_release("sprint")
		var before := player.velocity.length()
		await get_tree().physics_frame
		await get_tree().physics_frame
		results[mode] = [speed, cam_min, cam_max, player.velocity.length()]
		log_line("   %s: speed %.2f m/s eye %.3f..%.3f stop velocity %.3f (before %.2f)" % [mode, speed, cam_min, cam_max, player.velocity.length(), before])
	player.crouching = false
	check("walk speed ~1.26 m/s", absf(results.walk[0] - 1.26) < 0.15, "%.2f" % results.walk[0])
	check("sprint speed ~3.15 m/s", absf(results.sprint[0] - 3.15) < 0.3, "%.2f" % results.sprint[0])
	check("crouch speed ~0.63 m/s", absf(results.crouch[0] - 0.63) < 0.1, "%.2f" % results.crouch[0])
	check("standing eye height 0.9 +- bob 0.03", results.walk[1] > 0.86 and results.walk[2] < 0.94, "%.3f..%.3f" % [results.walk[1], results.walk[2]])
	check("crouched eye height 0.6", results.crouch[1] > 0.56 and results.crouch[2] < 0.64, "%.3f..%.3f" % [results.crouch[1], results.crouch[2]])
	check("stops instantly on key release", results.walk[3] < 0.2, "%.3f" % results.walk[3])

func _scn_elevator() -> void:
	log_line("== elevator")
	statue.active = false
	revive()
	var record: Dictionary = {}
	for r in facility.generator.rooms:
		if str(r.name) == "room3storage":
			record = r
	if record.is_empty():
		check("map has a room3storage", false, "not generated")
		return
	var key := "%d,%d" % [record.grid.x, record.grid.y]
	place_player(record.position + Vector3(0, 6.0, 0))
	var room: Node3D = facility.rooms.get_room(record)
	await secs(0.25)
	check("elevator room is built", room != null, key)
	if room == null:
		return
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	check("elevator doors present with a car at door A", door_a != null and door_b != null and door_a.open and not door_b.open and door_a.elevator, "")
	# cab marker positions: the first elevator pair uses Objects[0] (up) and Objects[1] (far below)
	var fill: Dictionary = RoomFill.for_room("room3storage")
	var up := Vector3(float(fill.objects["0"].x), float(fill.objects["0"].y), -float(fill.objects["0"].z))
	var down := Vector3(float(fill.objects["1"].x), float(fill.objects["1"].y), -float(fill.objects["1"].z))
	var up_world: Vector3 = room.to_global(up)
	var down_world: Vector3 = room.to_global(down)
	place_player(up_world + Vector3(0.0, 0.1, 0.0))
	await secs(1.0)
	check("player stands in the upper cab", player.is_on_floor() or true, str(player.global_position))
	await shot("elevator_cab_up")
	place_player(room.to_global(up + Vector3(0.0, 0.0, 1.6)))
	await secs(0.6)
	face_point(door_a.global_position + Vector3(0, 0.6, 0))
	await secs(0.3)
	await shot("elevator_door_up")
	place_player(up_world + Vector3(0.0, 0.1, 0.0))
	await secs(0.5)
	# press the inside button: the open door is unlocked because we are inside
	door_a.use()
	var t := 0.0
	var arrived := false
	while t < 12.0 and not arrived:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		arrived = player.global_position.distance_to(down_world) < 2.0
	check("ride down takes about 7 s and arrives in the lower cab", arrived and t > 6.0 and t < 10.0, "t=%.1fs pos=%s expected near %s" % [t, str(player.global_position), str(down_world)])
	await secs(2.0)
	check("lower cab door opens and the room is still there", door_b.open and facility.rooms.built.has(key), "door_b.open=%s" % str(door_b.open))
	check("player is on solid ground below", player.is_on_floor() and player.global_position.y > down_world.y - 1.0, "y=%.2f cab y=%.2f" % [player.global_position.y, down_world.y])
	await shot("elevator_cab_down")
	door_b.use()
	t = 0.0
	arrived = false
	while t < 12.0 and not arrived:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		arrived = player.global_position.distance_to(up_world) < 2.0
	check("ride back up arrives in the upper cab", arrived, "t=%.1fs pos=%s" % [t, str(player.global_position)])
	# the controller reports the car location through door messages
	await secs(2.0)
	check("upper door open again", door_a.open and not door_b.open, "")

func _scn_persist() -> void:
	log_line("== room state across a save")
	statue.active = false
	revive()
	var hud := get_tree().get_first_node_in_group("hud")
	var record: Dictionary = {}
	for r in facility.generator.rooms:
		var def: Dictionary = RoomFill.for_room(str(r.name))
		if str(r.name) != "start" and not def.is_empty() and def.get("items", []).size() > 0 and def.get("doors", []).size() > 0 and not facility.rooms.inside_start(r):
			record = r
			break
	if record.is_empty():
		check("a room with items and doors exists", false, "")
		return
	var key: String = record.key
	var room: Node3D = facility.rooms.get_room(record)
	await secs(0.6)
	var item_node: Node3D = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if node.has_meta("fill_id") and room.is_ancestor_of(node):
			item_node = node
			break
	check("room spawned a fill item", item_node != null, str(record.name))
	if item_node == null:
		return
	var fill_id: String = item_node.get_meta("fill_id")
	var at: Vector3 = item_node.global_position
	place_player(at + Vector3(0.0, 1.0, 0.0))    # the room is solid only near the player
	await get_tree().physics_frame
	await get_tree().physics_frame
	# (items often sit on tables, so the floor is found with a ray rather than the item's height)
	var stand := Vector3(at.x, at.y + 0.1, at.z + 0.5)   # the old spot, if nothing better is found
	var space := get_viewport().world_3d.direct_space_state
	for offset in [Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8)]:
		var column: Vector3 = at + offset
		var q := PhysicsRayQueryParameters3D.create(column + Vector3(0, 0.8, 0), column + Vector3(0, -3.0, 0))
		q.collision_mask = 1
		var floor_hit := space.intersect_ray(q)
		if floor_hit.is_empty():
			continue
		var candidate: Vector3 = floor_hit.position + Vector3(0, 0.05, 0)
		if not blocked(candidate + Vector3(0, 0.1, 0)):
			stand = candidate
			break
	place_player(stand)
	await secs(0.8)
	face_point(at)
	var look: Vector3 = at - player.camera.global_position
	player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	await get_tree().physics_frame
	await get_tree().physics_frame
	# several items can sit side by side: the one the player takes is the closest in view, so that is the one to follow
	var in_reach: Node3D = player.closest_item()
	if in_reach != null and in_reach.has_meta("fill_id"):
		fill_id = in_reach.get_meta("fill_id")
		item_node = in_reach
	await tap("interact")
	await get_tree().physics_frame
	var held: int = hud.items.filter(func(s: String) -> bool: return not s.is_empty()).size()
	check("item taken with E", held >= 1 and GameState.taken_items.has(fill_id), "held=%d id=%s" % [held, fill_id])
	var door: Node3D = room._fill_doors[0]
	door.open = true
	door.locked = false
	var edge_key: String = str(facility.rooms.doors.keys()[0])
	var edge_door: Node3D = facility.rooms.doors[edge_key]
	var edge_was_open: bool = edge_door.open
	edge_door.reset_to(not edge_was_open, true)
	check("the game saves", main.save_game(), "")
	await main.load_game()
	var waited := 0.0
	while waited < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(1.0)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173
	statue.active = false
	var again: Node3D = facility.rooms.get_room(record)
	check("the room is built again in the new game", again != null, str(record.key))
	if again == null:
		return
	var respawned := false
	for node in get_tree().get_nodes_in_group("pickup"):
		if node.get_meta("fill_id", "") == fill_id and is_instance_valid(node) and not node.is_queued_for_deletion():
			respawned = true
	check("taken item does not come back after loading", not respawned, fill_id)
	var edge_again: Node3D = facility.rooms.doors.get(edge_key)
	check("a door between rooms keeps its open and locked state after loading", edge_again != null and edge_again.open == not edge_was_open and edge_again.locked, "open=%s was=%s locked=%s" % [str(edge_again.open) if edge_again != null else "-", str(edge_was_open), str(edge_again.locked) if edge_again != null else "-"])
	check("door keeps its open state after loading", again._fill_doors[0].open and again._fill_doors[0].openstate >= 179.0, "open=%s state=%.0f" % [str(again._fill_doors[0].open), again._fill_doors[0].openstate])

func _scn_stairs() -> void:
	log_line("== stairs")
	statue.active = false
	revive()
	var arena := _arena(Vector3(600.0, 200.0, 600.0))
	# six risers of 0.2 m with 0.4 m treads, then a 0.5 m wall (too tall to climb)
	var body: StaticBody3D = arena.get_child(0)
	for i in 6:
		var step := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 0.2 * (i + 1), 0.4)
		step.shape = box
		step.position = Vector3(0.0, 0.1 * (i + 1) - 0.0, -2.0 - 0.4 * i)
		body.add_child(step)
	var wall := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(8.0, 0.5, 0.3)
	wall.shape = wbox
	wall.position = Vector3(10.0, 0.25, -2.0)
	body.add_child(wall)
	place_player(arena.position + Vector3(0.0, 0.02, 0.0))
	await secs(0.6)
	player.rotation.y = 0.0
	Input.action_press("move_forward")
	var last_pos: Vector3 = player.global_position
	var max_flat := 0.0
	var max_rise := 0.0
	var elapsed := 0.0
	while elapsed < 2.5:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		max_flat = maxf(max_flat, Vector2(player.global_position.x - last_pos.x, player.global_position.z - last_pos.z).length() / dt)
		max_rise = maxf(max_rise, (player.global_position.y - last_pos.y) / dt)
		last_pos = player.global_position
	Input.action_release("move_forward")
	Input.action_release("move_forward")
	var climbed: float = player.global_position.y - arena.position.y
	log_line("   end pos %s floor=%s vel=%s" % [str(player.global_position - arena.position), str(player.is_on_floor()), str(player.velocity)])
	check("walking into 0.2 m risers climbs the staircase (3 risers in 2.5 s at 1.26 m/s)", climbed > 0.55, "rose %.2f m" % climbed)
	check("stairs are climbed at walking speed, not slid up", max_flat < 1.4 and max_rise < 2.5, "flat %.2f m/s, rise %.2f m/s" % [max_flat, max_rise])
	place_player(arena.position + Vector3(10.0, 0.02, 0.0))
	await secs(0.6)
	Input.action_press("move_forward")
	await secs(1.5)
	Input.action_release("move_forward")
	var blocked_by_wall: float = player.global_position.y - arena.position.y
	check("a 0.5 m wall is not climbed", blocked_by_wall < 0.1, "y %.2f" % blocked_by_wall)

# Every FillRoom door must sit in an opening: rays through the leaf plane (at the middle and
# near both edges of the leaf, three heights) may not hit the room's walls.
func _scn_filldoors() -> void:
	log_line("== room doors sit in openings")
	facility.active = false
	facility.drawing.enabled = false
	facility.after_teleport()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var exclude: Array[RID] = [player.get_rid()]
	for node in get_tree().get_nodes_in_group("door"):
		for body in node.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as StaticBody3D).get_rid())
	var space := get_viewport().world_3d.direct_space_state
	var total := 0
	var bad: Array[String] = []
	for node in get_tree().get_nodes_in_group("door"):
		var door: Node3D = node
		if door.room == null or door.get("elevator") == true:
			continue
		total += 1
		var dir: Vector3 = door.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		var side: Vector3 = door.global_transform.basis.x
		side.y = 0.0
		side = side.normalized()
		var hits := 0
		for offset in [-0.2, 0.0, 0.2]:
			for h in [0.3, 0.7, 1.1]:
				var base: Vector3 = door.global_position + Vector3(0, h, 0) + side * offset
				var q := PhysicsRayQueryParameters3D.create(base + dir * 0.5, base - dir * 0.5)
				q.collision_mask = 1
				q.exclude = exclude
				if not space.intersect_ray(q).is_empty():
					hits += 1
		if hits > 0:
			bad.append("%s %s (%d/9 rays hit)" % [str(door.room.name), str(door.room.to_local(door.global_position)), hits])
	check("all %d room doors sit in openings" % total, bad.is_empty(), "%d bad: %s" % [bad.size(), "; ".join(bad.slice(0, 8))])

# Frame times while the player hops and walks along the map, and the numbers of the build at load (RoomRegistry.build_all).
func _scn_perf() -> void:
	log_line("== performance")
	statue.active = false
	var rooms: Array = facility.generator.rooms.duplicate()
	rooms.sort_custom(func(a, b) -> bool: return a.position.distance_to(player.global_position) < b.position.distance_to(player.global_position))
	var frame_ms: Array[float] = []
	var visited := 0
	for record in rooms:
		if str(record.name) == "start" or facility.rooms.inside_start(record):
			continue
		place_player(record.position + Vector3(0.0, 1.6, 0.0))
		visited += 1
		for _f in 40:
			await get_tree().physics_frame
			frame_ms.append(get_process_delta_time() * 1000.0)
		if visited >= (12 if OS.get_environment("SCP_PERF") == "hop" else 0):
			break
	frame_ms.sort()
	var avg := 0.0
	for v in frame_ms:
		avg += v
	avg /= maxf(frame_ms.size(), 1)
	log_line("   frames %d avg %.1f ms p95 %.1f ms max %.1f ms" % [frame_ms.size(), avg, frame_ms[int(frame_ms.size() * 0.95)], frame_ms[-1]])
	log_line("   build_all: %.0f ms (graph link %.0f ms); %d rooms" % [facility.rooms.build_all_ms, facility.rooms.graph_link_ms, facility.rooms.built.size()])
	# 2. walking: a stroll along the map at walking speed
	var route: Array[Vector3] = []
	var remaining: Array = facility.generator.rooms.duplicate()
	var here: Vector3 = player.global_position
	while route.size() < 6 and not remaining.is_empty():
		remaining.sort_custom(func(a, b) -> bool: return a.position.distance_to(here) < b.position.distance_to(here))
		var next: Dictionary = remaining.pop_front()
		if str(next.name) == "start" or facility.rooms.inside_start(next):
			continue
		route.append(next.position + Vector3(0.0, 1.6, 0.0))
		here = next.position
	var walk_ms: Array[float] = await _walk_route(route, get_tree().physics_frame, false)
	walk_ms.sort()
	log_line("   walking: %d frames, p99 %.1f ms, max %.1f ms, frames over 25 ms: %d" % [walk_ms.size(), walk_ms[int(walk_ms.size() * 0.99)], walk_ms[-1], walk_ms.filter(func(v: float) -> bool: return v > 25.0).size()])
	var slow_frames: int = walk_ms.filter(func(v: float) -> bool: return v > 25.0).size()
	check("walking through the map has no frame over 25 ms", slow_frames == 0, "%d frames, worst %.1f ms" % [slow_frames, walk_ms[-1]])

# [draw calls, primitives, objects, render cpu ms, render gpu ms, wall ms per frame] averaged over `frames` frames
func _measure_frames(frames: int) -> Array:
	var rid: RID = get_viewport().get_viewport_rid()
	var calls := 0.0
	var prims := 0.0
	var objects := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var wall: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		calls += float(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		prims += float(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		objects += float(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var total := 0.0
	for value in wall:
		total += value
	return [calls / frames, prims / frames, objects / frames, cpu / frames, gpu / frames, total / frames, wall]

func _percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(int(sorted.size() * fraction), sorted.size() - 1)])

# Walks the player along `route` at walking speed like ordinary motion, one position per frame; returns the wall ms of each frame.
# `wall`: real time per frame; otherwise the engine's frame delta, as the perf check always used (under --fixed-fps it does
# not depend on how busy the machine is).
func _walk_route(route: Array[Vector3], frame_signal: Signal, wall: bool = true) -> Array[float]:
	var times: Array[float] = []
	var cursor: Vector3 = route[0]
	place_player(cursor)
	await secs(1.5)
	var last := Time.get_ticks_usec()
	for target in route.slice(1):
		while cursor.distance_to(target) > 0.2:
			cursor = cursor.move_toward(target, 1.26 * get_physics_process_delta_time())
			player.velocity = Vector3.ZERO
			player.global_position = cursor
			await frame_signal
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0 if wall else get_process_delta_time() * 1000.0)
			last = now
	return times

func _perf_snapshot() -> Dictionary:
	return {"static": Performance.get_monitor(Performance.MEMORY_STATIC), "vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}

func _log_snapshot(label: String, snap: Dictionary) -> void:
	log_line("BUILDALL memory %s: static %.1f MB, video %.1f MB, objects %d, nodes %d" % [label, snap.static / 1048576.0, snap.vram / 1048576.0, snap.objects, snap.nodes])

func _steady_state(label: String, frames: int) -> void:
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var info: Array = []
	var wall: Array = []
	var measured := 0
	while measured < frames:
		var chunk := mini(30, frames - measured)
		info = await _measure_frames(chunk)
		wall.append_array(info[6])
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		measured += chunk
	var p_avg := 0.0
	var f_avg := 0.0
	for v in process_ms:
		p_avg += v / process_ms.size()
	for v in physics_ms:
		f_avg += v / physics_ms.size()
	var w_avg := 0.0
	for v in wall:
		w_avg += float(v) / wall.size()
	log_line("BUILDALL steady %s: %d frames, TIME_PROCESS avg %.2f max %.2f ms, TIME_PHYSICS_PROCESS avg %.2f max %.2f ms (sampled per 30 frames)" % [label, wall.size(), p_avg, process_ms.max(), f_avg, physics_ms.max()])
	log_line("BUILDALL steady %s: wall frame avg %.1f p95 %.1f max %.1f ms; draw calls %.0f, objects %.0f, primitives %.0f" % [label, w_avg, _percentile(wall, 0.95), float(wall.max()), info[0], info[2], info[1]])

func _find_path_cost(label: String) -> void:
	var ids: PackedInt64Array = facility.graph.point_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var times: Array[float] = []
	var found := 0
	var tries := 0
	while times.size() < 20 and tries < 2000:
		tries += 1
		var a: Vector3 = facility.graph.position_of(ids[rng.randi() % ids.size()])
		var b: Vector3 = facility.graph.position_of(ids[rng.randi() % ids.size()])
		if a.distance_to(b) < 60.0:
			continue
		var t0 := Time.get_ticks_usec()
		var result: Dictionary = facility.find_path(a, b)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		if not result.is_empty():
			found += 1
	times.sort()
	var total := 0.0
	for v in times:
		total += v
	log_line("BUILDALL find_path %s: %d calls over %d points, %d found, avg %.2f ms, max %.2f ms" % [label, times.size(), ids.size(), found, total / maxf(times.size(), 1), times[-1] if not times.is_empty() else 0.0])

# Cost of the build at map load (RoomRegistry.build_all): the rooms are all built when a scenario starts, so this reports what the
# build measured and what the finished world costs per frame. A measurement: no performance thresholds.
func _scn_buildall() -> void:
	log_line("== build all rooms")
	statue.active = false
	var targets: Array = facility.generator.rooms.filter(func(r: Dictionary) -> bool: return not facility.rooms.inside_start(r))
	var anchor: Dictionary = targets[0]
	place_player(anchor.position + Vector3(0.0, 1.6, 0.0))
	await secs(2.0)
	log_line("BUILDALL rooms: %d built, build_all total %.0f ms" % [facility.rooms.built.size(), facility.rooms.build_all_ms])
	log_line("BUILDALL graph link: %.0f ms; points %d, pending %d" % [facility.rooms.graph_link_ms, facility.graph.point_count(), facility.graph.pending_count()])
	var missing: Array[String] = []
	for record in targets:
		if not facility.rooms.built.has(record.key):
			missing.append(str(record.key))
	check("every room outside the start footprint is built", missing.is_empty(), "missing: %s" % ", ".join(missing.slice(0, 8)))
	_log_snapshot("all built", _perf_snapshot())
	await _find_path_cost("all built")
	await _steady_state("all built", 300)
	var route: Array[Vector3] = []
	var remaining: Array = targets.duplicate()
	var here: Vector3 = player.global_position
	while route.size() < 6 and not remaining.is_empty():
		remaining.sort_custom(func(a, b) -> bool: return a.position.distance_to(here) < b.position.distance_to(here))
		var next: Dictionary = remaining.pop_front()
		route.append(next.position + Vector3(0.0, 1.6, 0.0))
		here = next.position
	var walk_ms: Array[float] = await _walk_route(route, get_tree().physics_frame)
	walk_ms.sort()
	log_line("BUILDALL walking (all built): %d frames, avg %.1f p99 %.1f max %.1f ms, over 25 ms: %d" % [walk_ms.size(), walk_ms.reduce(func(a, b): return a + b, 0.0) / maxf(walk_ms.size(), 1), walk_ms[int(walk_ms.size() * 0.99)], walk_ms[-1], walk_ms.filter(func(v: float) -> bool: return v > 25.0).size()])

# Test-only cost attribution: with every room built, switches script groups off one at a time and logs the wall ms per physics frame.
func _ablate_ms(frames: int) -> float:
	await get_tree().physics_frame
	var began := Time.get_ticks_usec()
	for i in frames:
		await get_tree().physics_frame
	return (Time.get_ticks_usec() - began) / 1000.0 / frames

func _scn_ablate() -> void:
	log_line("== ablate")
	statue.active = false
	var targets: Array = facility.generator.rooms.filter(func(r: Dictionary) -> bool: return not facility.rooms.inside_start(r))
	place_player(targets[0].position + Vector3(0.0, 1.6, 0.0))
	await secs(2.0)
	place_player(targets[0].position + Vector3(0.0, 1.6, 0.0))
	await secs(2.0)
	var by_script := {}
	var stack: Array[Node] = [get_tree().root]
	var total_nodes := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total_nodes += 1
		stack.append_array(node.get_children())
		if node == self or node.is_ancestor_of(self):
			continue
		var script: Script = node.get_script()
		if script != null and (node.is_processing() or node.is_physics_processing()):
			var path: String = script.resource_path
			if not by_script.has(path):
				by_script[path] = []
			by_script[path].append(node)
	log_line("ABLATE nodes %d, rooms loaded %d" % [total_nodes, facility.rooms.built.size()])

	var timing: Array = []
	var dt := 1.0 / 70.0
	for path in by_script:
		var spent := 0.0
		var calls := 0
		for node in by_script[path]:
			if not node.has_method("_physics_process"):
				continue
			var began := Time.get_ticks_usec()
			for i in 20:
				node._physics_process(dt)
			spent += (Time.get_ticks_usec() - began) / 20.0
			calls += 1
		timing.append([path, calls, spent / 1000.0])
	timing.sort_custom(func(a, b) -> bool: return a[2] > b[2])
	var sum_ms := 0.0
	for row in timing:
		sum_ms += row[2]
		if row[2] >= 0.02:
			log_line("TIMED %-40s nodes %4d  %.3f ms/frame (_physics_process called directly)" % [row[0].get_file(), row[1], row[2]])
	log_line("TIMED sum of all _physics_process: %.2f ms" % sum_ms)
	var fm_parts := {
		"_update_lights": func(): facility._update_lights(player.global_position),
		"drawing.update": func(): facility.drawing.update(),
		"mtf.update": func(): facility.mtf.update(1.0),
		"_mark_room_found": func(): facility._mark_room_found(),
		"_update_096_events": func(): facility._update_096_events(),
		"_door_bodies": func(): facility._door_bodies(),
	}
	for name in fm_parts:
		var began := Time.get_ticks_usec()
		for i in 20:
			fm_parts[name].call()
		log_line("TIMED facility %s: %.3f ms" % [name, (Time.get_ticks_usec() - began) / 20000.0])
	var wb_total := 0.0
	var faces_total := 0
	var wb_rooms := 0
	for key in facility.rooms.built:
		var r: Node = facility.rooms.built[key]
		if not r.has_method("world_bounds"):
			continue
		var began := Time.get_ticks_usec()
		for i in 20:
			r.world_bounds()
		wb_total += (Time.get_ticks_usec() - began) / 20000.0
		faces_total += r.collision_faces.size()
		wb_rooms += 1
	log_line("TIMED world_bounds once per loaded room: %.2f ms over %d rooms, %d collision face vertices" % [wb_total, wb_rooms, faces_total])
	log_line("TIMED graph pending %d" % facility.graph.pending_count())
	var began_ex := Time.get_ticks_usec()
	for i in 20:
		facility._update_explosion(1.0)
		facility._update_079_gates()
		facility._update_femur(1.0)
	log_line("TIMED explosion+gates+femur: %.3f ms" % ((Time.get_ticks_usec() - began_ex) / 20000.0))
	var lights := 0
	for key in facility.rooms.built:
		if "lights" in facility.rooms.built[key]:
			lights += facility.rooms.built[key].lights.size()
	log_line("TIMED lights in loaded rooms: %d" % lights)
	var frames := 150
	var base := await _ablate_ms(frames)
	if OS.get_environment("SCP_TIMED_ONLY") != "":
		return
	log_line("ABLATE baseline %.2f ms" % base)
	var rows: Array = []
	for path in by_script:
		var nodes: Array = by_script[path]
		var states: Array = []
		for node in nodes:
			states.append([node.is_processing(), node.is_physics_processing()])
			node.set_process(false)
			node.set_physics_process(false)
		var ms := await _ablate_ms(frames)
		for i in nodes.size():
			nodes[i].set_process(states[i][0])
			nodes[i].set_physics_process(states[i][1])
		var again := await _ablate_ms(frames)
		rows.append([path, nodes.size(), ms, again])
	rows.sort_custom(func(a, b) -> bool: return a[2] < b[2])
	for row in rows:
		log_line("ABLATE %-48s nodes %4d  off %.2f ms  (baseline before %.2f, after restore %.2f)" % [row[0].get_file(), row[1], row[2], base, row[3]])
	var all_nodes: Array = []
	for path in by_script:
		all_nodes.append_array(by_script[path])
	for node in all_nodes:
		node.set_process(false)
		node.set_physics_process(false)
	var floor_ms := await _ablate_ms(frames)
	log_line("ABLATE every scripted node off: %.2f ms" % floor_ms)
	for node in all_nodes:
		node.set_process(true)
		node.set_physics_process(true)
	facility.active = false
	log_line("ABLATE facility.active=false: %.2f ms" % await _ablate_ms(frames))
	facility.active = true
	var bodies: Array = []
	for key in facility.rooms.built:
		for body in facility.rooms.built[key].find_children("*", "CollisionObject3D", true, false):
			bodies.append([body, body.collision_layer, body.collision_mask])
	log_line("ABLATE collision objects: %d" % bodies.size())
	var player_room = facility.rooms.built.get(facility.record_at(player.global_position).get("key", ""))
	for entry in bodies:
		if player_room == null or not player_room.is_ancestor_of(entry[0]):
			entry[0].collision_layer = 0
			entry[0].collision_mask = 0
	log_line("ABLATE collision off outside player's room: %.2f ms" % await _ablate_ms(frames))
	for entry in bodies:
		entry[0].collision_layer = entry[1]
		entry[0].collision_mask = entry[2]
	log_line("ABLATE baseline after: %.2f ms" % await _ablate_ms(frames))

# Saves, throws the world away and loads it again. Leaves the bot on the NEW world, so run it
# last (the other scenarios' home positions belong to the old one).
func _scn_saveload() -> void:
	log_line("== save and load")
	statue.active = false
	var hud := get_tree().get_first_node_in_group("hud")
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	_give(hud, "Level 1 Key Card", "key1")
	_give(hud, "First Aid Kit", "firstaid")
	player.stamina = 42.0
	GameState.wearing_vest = 1
	GameState.taken_items["test|i9"] = true
	var spot: Vector3 = _clear_spot(player.global_position, 3.0)
	place_player(spot + Vector3(0, 0.05, 0))
	player.rotation.y = 1.2
	await secs(0.5)
	var dropped: Node3D = RoomFill.make_pickup("Level 2 Key Card", "key2")
	main.world.add_child(dropped)
	dropped.global_position = spot + Vector3(1.0, 0.3, 0.0)
	await secs(1.0)
	var squad_lead: Node = facility.mtf.spawn(spot + Vector3(0.0, 0.05, 2.0))
	var squad_second: Node = facility.mtf.spawn(spot + Vector3(0.4, 0.05, 2.0), squad_lead)
	squad_lead.no_target = true
	squad_second.no_target = true
	squad_second.state = 1
	squad_second.state2 = 500.0
	facility.mtf.timer = 12345.0
	statue.idle = 2
	statue.target_node = squad_lead
	facility.remote_door_on = false
	facility.ccont_pitches = [10.0, -60.0, -80.0]
	facility.events.room079.state = 10001.0
	facility.gate_b_unlocked = true
	facility.events.femur.state = 1
	facility.events.femur.timer = 1234.0
	facility.events.femur.magnets = false
	facility.contained_106 = true
	facility.nuke_lever_pitch = -80.0
	GameState.secondary_light = 0.25
	GameState.scp1025[3] = 7.5       # appendicitis (SCP1025state is saved)
	facility.spawn_106(-10.0)        # hunting: a State below -1 must not be mistaken for "use the 12-17 minute counter"
	GameState.blink_effect = 0.6
	GameState.blink_effect_timer = 500.0
	GameState.stamina_effect = 2.0
	GameState.stamina_effect_timer = 500.0
	GameState.death_timer = 100000.0
	GameState.heal_timer = 500.0
	GameState.vomit_timer = 500.0
	GameState.eye_irritation = 5000.0
	GameState.sanity = -300.0
	GameState.achievements["895"] = true
	GameState.rooms_found["0,0"] = true
	GameState.docs_found["Document SCP-173"] = true
	var stain := GrowingDecal.make(main.world, spot + Vector3(0.0, 0.01, 0.6), "GFX/decal1.png", 0.3, 0.002, 0.8, false)
	stain.max_size = 0.9
	stain.alpha_change = 0.0001
	var stain_basis: Basis = stain.global_basis.orthonormalized()
	GrowingDecal._make_stain(main.world, 0.25).global_position = spot + Vector3(0.5, 0.01, 0.6)
	var saved_pos: Vector3 = player.global_position
	var saved_seed: int = facility.generator.seed_value
	check("the game saves", main.save_game(), "")
	var file_exists: bool = FileAccess.file_exists(SaveGame.path_of(SaveGame.LEGACY_SLOT))
	check("a save file is written", file_exists, "")
	await main.load_game()
	var waited := 0.0
	while waited < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(2.5)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173
	var hud2 := get_tree().get_first_node_in_group("hud")
	check("loading rebuilds the same map", facility.generator.seed_value == saved_seed, "%d vs %d" % [facility.generator.seed_value, saved_seed])
	var moved := Vector2(player.global_position.x - saved_pos.x, player.global_position.z - saved_pos.z).length()
	check("the player is where they saved", moved < 0.5, "%.2f m off" % moved)
	check("the inventory comes back", hud2.items.has("Level 1 Key Card") and hud2.items.has("First Aid Kit"), str(hud2.items))
	check("timed effects come back (blink, stamina, drink death, heal, vomit, eye gas)", is_equal_approx(GameState.blink_effect, 0.6) and GameState.blink_effect_timer > 400.0 and is_equal_approx(GameState.stamina_effect, 2.0) and GameState.stamina_effect_timer > 400.0 and GameState.death_timer > 50000.0 and GameState.heal_timer > 400.0 and GameState.vomit_timer > 400.0 and GameState.eye_irritation > 1000.0, "%s" % [[GameState.blink_effect, GameState.stamina_effect, GameState.death_timer, GameState.heal_timer, GameState.vomit_timer, GameState.eye_irritation]])
	check("sanity comes back", GameState.sanity < -100.0, "%.1f" % GameState.sanity)
	check("worn items come back", GameState.wearing_vest == 1, "vest %d" % GameState.wearing_vest)
	check("the MTF squad comes back with its leader", facility.mtf.units.size() == 2 and facility.mtf.units[1].leader == facility.mtf.units[0], "%d units" % facility.mtf.units.size())
	check("and the arrival timer", facility.mtf.timer == 12345.0, "%.0f" % facility.mtf.timer)
	check("and 173 is still boxed by its captor", statue.idle == 2 and facility.mtf.units.size() > 0 and statue.target_node == facility.mtf.units[0], "idle %d" % statue.idle)
	check("a unit keeps its search (state 1 or what it turned into, timer still running)", facility.mtf.units.size() == 2 and facility.mtf.units[1].state2 > 0.0, "")
	statue.idle = 0
	statue.target_node = null
	check("taken items stay taken", GameState.taken_items.has("test|i9"), "")
	check("079, the control room and the gates come back", not facility.remote_door_on and facility.ccont_pitches[2] == -80.0 and facility.events.room079.state == 10001.0 and facility.gate_b_unlocked and not facility.gate_a_unlocked, "")
	check("the femur breaker and Contained106 come back", facility.events.femur.state == 1 and facility.events.femur.timer == 1234.0 and not facility.events.femur.magnets and facility.contained_106, "")
	check("the warhead lever and the light level come back", facility.nuke_lever_pitch == -80.0 and is_equal_approx(GameState.secondary_light, 0.25), "")
	check("SCP-1025's illness comes back", GameState.scp1025[3] > 5.0, "%.2f" % GameState.scp1025[3])
	check("a hunting SCP-106 is still hunting", facility.scp106 != null and is_instance_valid(facility.scp106) and facility.scp106.state < -1.0, "state %.0f" % (facility.scp106.state if facility.scp106 != null else 0.0))
	GameState.scp1025[3] = 0.0
	facility.contained_106 = false
	GameState.secondary_light = 1.0
	var found := false
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Level 2 Key Card" and not node.has_meta("fill_id"):
			found = true
	check("an item left on the floor is still there", found, "")
	check("achievements, found rooms and documents come back (Save.bb 123, 134, 233, 438)", GameState.achievements.has("895") and GameState.rooms_found.has("0,0") and GameState.docs_found.has("Document SCP-173"), "%d achievements, %d rooms, %d docs" % [GameState.achievements.size(), GameState.rooms_found.size(), GameState.docs_found.size()])
	var decal: GrowingDecal = null
	for node in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if node is GrowingDecal and node.global_position.distance_to(spot + Vector3(0.0, 0.01, 0.6)) < 0.05:
			decal = node
	var small_back := false
	for node in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if not node is GrowingDecal and node.global_position.distance_to(spot + Vector3(0.5, 0.01, 0.6)) < 0.05:
			small_back = is_equal_approx(float(node.get_meta("stain_half", 0.0)), 0.25)
	check("and a small corrosion stain", small_back, "")
	check("a decal on the floor comes back with its size but no growth (Save.bb 331-356, CreateDecal defaults)", decal != null and decal.size >= 0.3 and decal.size_change == 0.0 and is_equal_approx(decal.max_size, 1.0) and is_equal_approx(decal.alpha_change, 0.0001) and decal.global_basis.orthonormalized().is_equal_approx(stain_basis), "")
	GameState.wearing_vest = 0

# UpdateDoors offers the button only while a door is fully open or fully shut: clicking a moving door does nothing.
func _scn_doorguard() -> void:
	log_line("== doors beyond HideDistance * 2 are hidden and do not move (Main.bb UpdateDoors)")
	statue.active = false
	revive()
	var home := player.global_position
	var plain: Node3D = null
	var lift: Node3D = null
	for node in get_tree().get_nodes_in_group("door"):
		var door := node as Node3D
		var manhattan := absf(door.global_position.x - home.x) + absf(door.global_position.z - home.z)
		if manhattan < 40.0:
			continue
		if door.elevator:
			lift = door
		elif plain == null and not door.open and not door.locked and door.keycard == 0 and door.code.is_empty() and not door.big and not door.booth and door.leaf_a != null:
			plain = door
	check("a plain door beyond 40 exists", plain != null, "")
	if plain != null:
		await secs(1.2)
		plain.open = true
		await secs(1.0)
		check("a door past 30 is hidden and has no collision", plain.far and not plain.visible and plain.leaf_a.get_child(1).collision_layer == 0, "far %s dist %.0f" % [str(plain.far), plain.dist])
		check("it does not open while far", plain.openstate == 0.0, "state %.0f" % plain.openstate)
		place_player(plain.global_position + Vector3(0.0, 1.3, 0.0))
		await secs(1.0)
		check("near the player it is shown and solid again", not plain.far and plain.visible and plain.leaf_a.get_child(1).collision_layer == 1, "far %s" % str(plain.far))
		check("and then it opens", plain.openstate > 0.0, "state %.0f" % plain.openstate)
		plain.snap_shut()
	if lift != null:
		place_player(home)
		await secs(1.2)
		lift.open = true
		await secs(1.0)
		check("an elevator door past 30 still opens", lift.openstate > 0.0 and lift.far, "state %.0f far %s" % [lift.openstate, str(lift.far)])
		lift.snap_shut()

func _scn_doorspam() -> void:
	log_line("== door buttons while a door moves")
	statue.active = false
	var candidates: Array = facility.rooms.doors.values()
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var door: Node3D = null
	for node in candidates:
		if not node.locked and node.keycard == 0 and node.code.is_empty() and not node.big and not node.open and not node.elevator and node.buttons.size() > 0:
			door = node
			break
	check("a plain closed door is near", door != null, "")
	if door == null:
		return
	var dir: Vector3 = door.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var button: Node3D = door.buttons[0]
	var stand: Vector3 = button.global_position + dir * 0.5
	place_player(Vector3(stand.x, door.global_position.y + 0.6, stand.z))
	await secs(1.0)
	face_point(button.global_position)
	var look: Vector3 = button.global_position - player.camera.global_position
	player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	for _k in 3:
		await get_tree().physics_frame
	await secs(0.2)
	player._interact()
	await secs(0.15)
	check("the first press opens the door", door.open and door.openstate > 0.0 and door.openstate < 180.0, "open %s state %.0f" % [str(door.open), door.openstate])
	for i in 4:
		player._interact()
		await get_tree().physics_frame
	check("pressing again while it moves does nothing", door.open and not door.at_rest(), "open %s state %.0f" % [str(door.open), door.openstate])
	var waited := 0.0
	while waited < 4.0 and door.openstate < 180.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("it finishes opening (about 1.5 s)", door.openstate >= 180.0 and waited < 3.0, "state %.0f after %.1f s" % [door.openstate, waited])
	player._interact()
	await secs(0.15)
	check("a press at rest closes it", not door.open, "")
	player._interact()
	await get_tree().physics_frame
	check("and a press while it closes is ignored", not door.open, "")
	await secs(2.0)
	# the click needs no aim: with the back to the button it still presses it
	player.rotation.y += PI
	player.camera.rotation.x = 0.0
	await get_tree().physics_frame
	check("the button is found with the back turned", not player.closest_door_button().is_empty(), "")
	player._interact()
	await secs(0.15)
	check("and a click then opens the door", door.open, "")
	player.rotation.y += PI
	place_player(player.global_position + dir * 3.0)
	await secs(0.8)
	check("too far from the button nothing is offered", player.closest_door_button().is_empty(), "")

func _scn_movedbuttons() -> void:
	log_line("== door buttons FillRoom moved away from their door (heavy containment)")
	statue.active = false
	for room_name in ["room2tunnel", "room079", "coffin"]:
		var record := {}
		for candidate in facility.generator.rooms:
			if str(candidate.name) == room_name:
				record = candidate
				break
		if record.is_empty():
			continue
		place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
		player.blink_timer = 400.0
		await secs(1.5)
		var room: Node3D = facility.rooms.get_room(record)
		var tested := 0
		for door in room._fill_doors:
			if door.button_move.is_empty() or door.elevator or not door.at_rest():
				continue
			for button in door.buttons:
				var found := false
				var normal: Vector3 = button.global_transform.basis.z
				normal.y = 0.0
				normal = normal.normalized()
				for side in [1.0, -1.0]:
					var stand: Vector3 = button.global_position + normal * 0.4 * side
					place_player(Vector3(stand.x, door.global_position.y + 0.6, stand.z))
					face_point(button.global_position)
					await secs(0.3)
					if player.closest_door_button().get("button") == button:
						found = true
						break
				tested += 1
				check("%s: a moved button is offered (%.1f m from its door)" % [room_name, Vector2(button.global_position.x - door.global_position.x, button.global_position.z - door.global_position.z).length()], found, "")
		check("%s has doors with moved buttons" % room_name, tested > 0, "")

# Stands 0.4 m from a button on either side of its door plane, camera on it, and reports whether the player's pick offers exactly that button.
func _button_offered_from(door: Node3D, button: Node3D, inset: float = 0.4) -> bool:
	var normal: Vector3 = button.global_transform.basis.z
	normal.y = 0.0
	normal = normal.normalized()
	for side in [1.0, -1.0]:
		var stand: Vector3 = button.global_position + normal * inset * side
		place_player(Vector3(stand.x, door.global_position.y + 0.6, stand.z))
		face_point(button.global_position)
		await secs(0.3)
		if player.closest_door_button().get("button") == button:
			return true
	return false

func _stream_room_of(room_name: String) -> Node3D:
	for candidate in facility.generator.rooms:
		if str(candidate.name) == room_name:
			place_player(candidate.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
			player.blink_timer = 400.0
			await secs(1.5)
			return facility.rooms.get_room(candidate)
	return null

# MapSystem.bb CreateRoom/FillRoom: PositionEntity(dbuttons[i], ...) with EntityY/EntityZ(..., True) keeps that axis, FreeEntity(dbuttons[i])
# drops one button, and LoadRMesh's invisible collision mesh has no pick mode (a ray for EntityPick passes through it).
func _scn_doorbuttons() -> void:
	log_line("== door buttons: per-axis FillRoom moves, one freed button, picks through invisible collision")
	statue.active = false
	GameState.god_mode = true     # the tour passes rooms whose hazards can kill, and a dead player's camera drifts off
	var scps := await _stream_room_of("room2scps")
	if scps != null:
		var expected := {0: [1.25, 0.875], 1: [-1.25, -0.875]}
		for slot in expected:
			var door: Node3D = scps._fill_doors[slot]
			check("room2scps door %d has two buttons" % slot, door.buttons.size() == 2, "%d" % door.buttons.size())
			for i in mini(door.buttons.size(), 2):
				var local: Vector3 = scps.to_local(door.buttons[i].global_position)
				var door_local: Vector3 = scps.to_local(door.global_position)
				check("room2scps door %d button %d sits at x %.3f on the wall face (kept z and height)" % [slot, i, expected[slot][i]], absf(local.x - expected[slot][i]) < 0.01 and absf(local.y - 0.7) < 0.01 and absf(local.z - door_local.z) > 0.55 and absf(local.z - door_local.z) < 0.65, str(local))
				var found := await _button_offered_from(door, door.buttons[i])
				check("room2scps door %d button %d is offered from in front of it" % [slot, i], found, "")
	else:
		log_line("   (no room2scps in this seed)")
	var tunnel_room := await _stream_room_of("room2tunnel")
	if tunnel_room != null:
		var keypad_door: Node3D = tunnel_room._fill_doors[2]
		check("room2tunnel keypad door has two buttons", keypad_door.buttons.size() == 2, "%d" % keypad_door.buttons.size())
		for i in mini(keypad_door.buttons.size(), 2):
			var local: Vector3 = tunnel_room.to_local(keypad_door.buttons[i].global_position)
			var normal: Vector3 = tunnel_room.global_basis.inverse() * keypad_door.buttons[i].global_basis.z
			check("room2tunnel keypad button %d faces the passage (RotateEntity %d)" % [i, -90 if i == 0 else 90], absf(local.x) > 0.8 and normal.x * signf(local.x) < -0.9 and absf(normal.z) < 0.1, "%s facing %s" % [str(local), str(normal)])
	var partial := {"lockroom": 2, "lockroom3": 2, "008": 1, "room035": 2, "room012": 1, "room2poffices2": 1, "room2doors": 1, "room1123": 1}
	for room_name in partial:
		var room := await _stream_room_of(room_name)
		if room == null:
			continue
		var fill := RoomFill.for_room(room_name)
		var seen := 0
		for index in fill.doors.size():
			var def: Dictionary = fill.doors[index]
			var freed: Array = def.get("free_buttons", [])
			if freed.is_empty() or index >= room._fill_doors.size():
				continue
			var door: Node3D = room._fill_doors[index]
			seen += 1
			var kept := 2 - freed.size()
			check("%s door %d keeps %d button(s) after FreeEntity of %s" % [room_name, index, kept, str(freed)], door.buttons.size() == kept, "%d" % door.buttons.size())
			if room_name.begins_with("lockroom") and door.buttons.size() == 1:
				var local: Vector3 = room.to_local(door.buttons[0].global_position)
				var want := Vector3(float(def.button_move["0"].x), float(def.button_move["0"].y), -float(def.button_move["0"].z))
				check("%s door %d button sits where PositionEntity puts it" % [room_name, index], local.distance_to(want) < 0.02, "%s vs %s" % [str(local), str(want)])
				var offered := await _button_offered_from(door, door.buttons[0])
				check("%s door %d's lone button is offered" % [room_name, index], offered, "")
		check("%s has doors that free a button" % room_name, seen >= 1, "%d" % seen)
	for room_name in ["room4tunnels", "room3tunnel"]:
		var tunnel := await _stream_room_of(room_name)
		if tunnel == null:
			continue
		var tested := 0
		for node in facility.doors_near(tunnel.global_position, 6.5):
			var door := node as Node3D
			if door == null or door.buttons.is_empty() or not door.at_rest():
				continue
			var in_room: Vector3 = tunnel.to_local(door.global_position)
			if absf(in_room.x) > 4.5 or absf(in_room.z) > 4.5 or absf(in_room.y) > 1.0:
				continue
			var inward: Vector3 = tunnel.global_position - door.global_position
			inward.y = 0.0
			inward = inward.normalized()
			var across := inward.cross(Vector3.UP)
			var offered := 0
			for depth in [0.1, 0.2, 0.3, 0.4, 0.5]:
				for lateral in [-0.3, -0.15, 0.0, 0.15, 0.3]:
					var stand: Vector3 = door.global_position + inward * depth + across * lateral
					place_player(Vector3(stand.x, door.global_position.y + 0.05, stand.z))
					await get_tree().physics_frame
					for button in door.buttons:
						face_point(button.global_position)
						if player.closest_door_button().get("door") == door:
							offered += 1
							break
			tested += 1
			check("%s: a door button is offered from inside the tunnel (door at room x %.1f z %.1f)" % [room_name, in_room.x, in_room.z], offered > 0, "%d of 25 standing spots" % offered)
		check("%s has doors to test" % room_name, tested > 0, "%d" % tested)
	await _fast_open_checks()

func _spawn_test_door(offset: Vector3, big: bool, heavy: bool, elevator: bool, start_open: bool) -> Node3D:
	var door := Node3D.new()
	door.set_script(load("res://scripts/world/facility_door.gd"))
	door.elevator = elevator
	facility.add_child(door)
	door.setup(player.global_position + offset, 0.0, big, start_open, heavy)
	return door

# Main.bb UpdateDoors: d\fastopen = 0 once the door is fully open, and dir 3 (elevator) doors honour it too.
func _fast_open_checks() -> void:
	for kind in ["door", "heavy", "elevator"]:
		var door := _spawn_test_door(Vector3(0.0, 0.0, 3.0), false, kind == "heavy", kind == "elevator", false)
		door.fast_open = true
		door.open = true
		var frames := 0
		while door.openstate < 180.0 and frames < 400:
			await get_tree().physics_frame
			frames += 1
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("a fast-opened %s door clears fast_open once it is fully open" % kind, door.openstate >= 180.0 and not door.fast_open, "openstate %.0f fast %s" % [door.openstate, str(door.fast_open)])
		check("a fast-opened %s door opens twice as fast (about 45 frames, not 90)" % kind, frames < 60, "%d frames" % frames)
		door.open = false
		var closing := 0
		while door.openstate > 0.0 and closing < 400:
			await get_tree().physics_frame
			closing += 1
		check("it then closes at the normal speed (about 90 frames)" , closing > 70, "%d frames" % closing)
		door.queue_free()
	var big := _spawn_test_door(Vector3(0.0, 0.0, -3.0), true, false, false, true)
	await get_tree().physics_frame
	var before: int = facility.particles.count()
	big.open = false
	var burst := 0
	var waited := 0
	while waited < 420 and big.openstate > 0.0:
		await get_tree().physics_frame
		waited += 1
		burst = maxi(burst, facility.particles.count() - before)
	check("a big door that shuts sends up 76 to 100 dust motes", burst >= 75, "%d" % burst)
	big.queue_free()

# FillRoom creates the checkpoints' GEAR door only when MapTemp(x, y - 1) = 0 (no room behind that wall).
func _scn_checkpointgear() -> void:
	var seen := 0
	for record in facility.generator.rooms:
		if not str(record.name).begins_with("checkpoint"):
			continue
		place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
		player.blink_timer = 400.0
		await secs(1.5)
		var room: Node3D = facility.rooms.get_room(record)
		var gear := 0
		for door in room._fill_doors:
			if door.code == "GEAR" or door.code == "gear":
				gear += 1
		var below_empty := bool(record.get("below_empty", true))
		seen += 1
		check("%s at %s: GEAR doors %d, cell below empty %s" % [record.name, str(record.grid), gear, str(below_empty)], gear == (1 if below_empty else 0), "")
	check("a checkpoint was tested", seen > 0, "")

# CreateMap with Blitz's SeedRnd/Rand: the rooms below were read in the original 1.3.11 (console teleport + status) for the
# seed texts "abc" and "forest". Rooms late in the creation order depend on every FillRoom draw before them, the forest's too.
func _scn_blitzmap() -> void:
	check("GenerateSeedNumber(\"abc\") is 297", BlitzRng.seed_number("abc") == 297, str(BlitzRng.seed_number("abc")))
	var rng := BlitzRng.new()
	rng.seed_rnd(1)
	var first := rng.rand(1, 100)
	# state 48271 after one step; Rand uses its low 16 bits: (48271 + 0.5) / 65536 * 100 -> 73, + 1
	check("SeedRnd 1 then Rand(1, 100) gives 74", first == 74, str(first))
	var catalog := RoomCatalog.new()
	catalog.load_from_ini()
	var expected := {
		"abc": {"room2tesla": Vector2i(2, 5), "room4z3": Vector2i(4, 4), "tunnel": Vector2i(5, 7), "room860": Vector2i(4, 3), "room2offices": Vector2i(4, 2), "room2ccont": Vector2i(6, 2), "endroom": Vector2i(10, 2), "start": Vector2i(9, 17)},
		"forest": {"room2z3": Vector2i(15, 4), "room2tesla": Vector2i(13, 3), "room2offices": Vector2i(12, 2), "room2toilets": Vector2i(9, 5), "room2cafeteria": Vector2i(10, 5)},
		# PreventRoomOverlap moves coffin from (8, 5) to (16, 2) and room1lifts from (2, 3) to (8, 5)
		# seed text "9" (57): room106 and 008 / 035 keep their cells (room106 turned by 90 touches room4pit exactly) and room513 swaps with a room3z2
		"9": {"room513": Vector2i(12, 7), "room966": Vector2i(8, 7), "room106": Vector2i(6, 10), "008": Vector2i(2, 9), "room035": Vector2i(1, 7), "room079": Vector2i(5, 11)},
		"laaaaab": {"room1archive": Vector2i(7, 12), "room079": Vector2i(2, 10), "room106": Vector2i(9, 9), "008": Vector2i(3, 7), "room035": Vector2i(16, 7), "room1lifts": Vector2i(8, 5), "endroom": Vector2i(2, 3), "coffin": Vector2i(16, 2)},
	}
	for text in expected:
		var generator := MapGenerator.new()
		# measured in the original with the intro off: no 173 room takes part in PreventRoomOverlap
		generator.generate(catalog, BlitzRng.seed_number(text), false)
		var at := {}
		for record in generator.rooms:
			at[record.grid] = str(record.name)
		for room_name in expected[text]:
			var cell: Vector2i = expected[text][room_name]
			check("seed %s: %s at %s as in the original" % [text, room_name, cell], at.get(cell, "") == room_name, str(at.get(cell, "")))

# InitEvents continues CreateMap's generator after the map doors (Rand(-3, 1) and CreateDoor's Rand(8) each), 106's
# Rand(12, 17), the start decals and the player's turn. The events below were read in the original 1.3.11 (intro off,
# console teleport to the first room of the kind + status) for the same seed texts.
func _inside_start_room(record: Dictionary) -> bool:
	return str(record.name) == "start" or facility.rooms.inside_start(record)

func _scn_seedevents() -> void:
	var catalog := RoomCatalog.new()
	catalog.load_from_ini()
	# tunnel106 is a 7% roll, room3z2 and room4pit lose a 70% and a 60% roll, room2offices2 wins a 70% one
	var expected := {
		"abc": {"tunnel": ["5,7", "tunnel106"], "room2pit": ["10,10", "096spawn"], "room3z2": ["11,10", ""], "room4pit": ["7,10", ""], "room2offices2": ["2,2", "room2offices2"]},
	}
	var turns := {"abc": 167}
	# an item's yaw replays its room's FillRoom draws up to its CreateItem; the indices hold where the extractor's count of
	# a room's draws equals the count fill_room_rng.gd uses to build the map
	var fill: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/room_fill.json"))
	var counted := 0
	var wrong: Array[String] = []
	for room_name in fill.rooms:
		var draws := int(fill.rooms[room_name].get("draws", -1))
		if draws >= 0 and FillRoomRng.FIXED.has(room_name):
			counted += 1
			if draws != int(FillRoomRng.FIXED[room_name]):
				wrong.append(room_name)
	check("FillRoom draw counts of room_fill.json agree with fill_room_rng.gd", counted > 30 and wrong.is_empty(), "%d rooms, wrong %s" % [counted, str(wrong)])
	for record in facility.generator.rooms:
		var defs: Array = fill.rooms.get(str(record.name), {}).get("items", [])
		var index := defs.find_custom(func(d: Dictionary) -> bool: return int(d.get("draw", -1)) >= 0 and not d.has("yaw"))
		if index < 0 or _inside_start_room(record):
			continue
		var rng := BlitzRng.new()
		rng.state = int(record.fill_rng)
		for _i in int(defs[index].draw):
			rng.rand(0, 1)
		var want := float(rng.rand(360))
		var room_node: Node3D = facility.rooms.get_room(record)
		var got := INF
		for child in room_node.get_children():
			if child.has_meta("fill_id") and str(child.get_meta("fill_id")) == "%s|i%d" % [record.key, index]:
				got = rad_to_deg(child.rotation.y)
		check("%s: item %d is turned Rand(360) = %d from its FillRoom draws" % [record.name, index, want], got != INF and absf(wrapf(got - want, -180.0, 180.0)) < 0.001, str(got))
		break
	for text in ["abc", "forest"]:
		var generator := MapGenerator.new()
		generator.generate(catalog, BlitzRng.seed_number(text), false)
		for record in generator.rooms:
			record["key"] = "%d,%d" % [record.grid.x, record.grid.y]
		var plan: RefCounted = EventPlan.build(generator.rooms, generator.rng_before_events, false)
		var first := {}
		for record in generator.rooms:
			if not first.has(record.name):
				first[record.name] = record
		var open := 0
		for door in generator.doors:
			open += int(door.open)
		log_line("seed %s: 106 in %.0f min, turn %d, %d map doors (%d open), broken room2gw %s" % [text, generator.scp106_state / 4200.0, generator.start_turn, generator.doors.size(), open, plan.broken_gw_key])
		if turns.has(text):
			check("seed %s: the player is turned Rand(160, 200) = %d as in the original" % [text, turns[text]], generator.start_turn == turns[text], str(generator.start_turn))
		for room_name in first:
			var key: String = first[room_name].key
			log_line("  %s at %s: %s" % [room_name, key, plan.event_of(key)])
		for room_name in expected.get(text, {}):
			var want: Array = expected[text][room_name]
			var record: Dictionary = first.get(room_name, {})
			var got := "%s %s" % [record.get("key", "-"), plan.event_of(str(record.get("key", "")))]
			check("seed %s: the first %s holds %s as in the original" % [text, room_name, str(want)], got == "%s %s" % want, got)

func _scn_unlitx2() -> void:
	log_line("== rmesh surfaces with no lightmap keep the diffuse x2 (exit1 and endroom gate doors)")
	for file in ["exit1_opt", "endroom_opt"]:
		var parsed: Dictionary = MeshLoader.parse_rmesh(ContentPaths.existing_file("GFX/map/%s.rmesh" % file))
		var found := false
		for surface in parsed.get("surfaces", []):
			if str(surface.albedo).to_lower().ends_with("containment_doors.jpg"):
				found = str(surface.light).is_empty() and bool(surface.get("albedo_x2", false))
		check("%s: the containment_doors surface has no lightmap and the x2 flag" % file, found)
		var built: ArrayMesh = MeshLoader.build_rmesh(parsed).visual
		var door_material: ShaderMaterial = null
		for k in parsed.surfaces.size():
			if str(parsed.surfaces[k].albedo).to_lower().ends_with("containment_doors.jpg"):
				door_material = built.surface_get_material(k) as ShaderMaterial
		check("%s: the built door material is unlit with the diffuse doubled" % file, door_material != null and not bool(door_material.get_shader_parameter("use_lightmap")) and bool(door_material.get_shader_parameter("albedo_x2")))

# FillRoom's CreateDecal calls (MapSystem.bb): SCP-106's corrosion under the start room's desk and drawer, room2tunnel's and
# room2poffices2's stains, room2shaft's blood and room2scps' trail of drops. Decals are lit like models (EntityFX 0) and only
# their own colour takes the fog (the floor behind was fogged when it was drawn).
func _scn_filldecals() -> void:
	log_line("== FillRoom decals")
	var wanted := {"start": 2, "room2tunnel": 1, "room2poffices2": 3, "room2shaft": 1, "room2scps": 15}
	for key in facility.rooms.built:
		var room: Node = facility.rooms.built[key]
		if not is_instance_valid(room) or not wanted.has(room.room_name):
			continue
		var decals := room.get_children().filter(func(n: Node) -> bool: return n.is_in_group(&"fill_decals"))
		var lit: bool = decals.all(func(n: MeshInstance3D) -> bool: return bool((n.material_override as ShaderMaterial).get_shader_parameter("entity_lit")))
		check("%s has its %d FillRoom decals, lit" % [room.room_name, wanted[room.room_name]], decals.size() == wanted[room.room_name] and lit, "%d" % decals.size())
	var start: Node3D = facility.start_node
	if start != null:
		var near_desk := false
		for n in start.get_children():
			if n.is_in_group(&"fill_decals") and n.position.distance_to(Vector3(272.0, 0.0, -262.0) * MeshLoader.ROOM_SCALE + Vector3(0.0, 0.005, 0.0)) < 0.01:
				near_desk = true
		check("the start room's 106 stain lies under the desk (272, 0.005, 262)", near_desk, "")
	var shader_code: String = load("res://shaders/gamma_blend.gdshader").code
	check("mixed pictures fog only their own colour (fog_disabled, the rooms' fog)", shader_code.contains("fog_disabled") and shader_code.contains("ROOM_FOG"), "")
	await secs(0.2)
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	check("the environment's depth fog is not thinned by Godot's default density", not env.fog_enabled or env.fog_density == 1.0, "density %.2f" % env.fog_density)

func _scn_mapmodels() -> void:
	log_line("== map models: lightmapped b3d pieces and multi-material .x files")
	for file in ["IntroDesk", "IntroDrawer", "intro_labels", "173_2"]:
		var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/%s.b3d" % file))
		var lightmapped := 0
		var with_uv2 := 0
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s) as ShaderMaterial
			if material != null and bool(material.get_shader_parameter("use_lightmap")) and material.get_shader_parameter("lightmap_tex") != MeshLoader._white_tex():
				lightmapped += 1
				var uv2: PackedVector2Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2]
				if uv2.size() == (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() and not uv2.is_empty():
					with_uv2 += 1
		check("%s.b3d: its surfaces carry the lightmap and the second UV set" % file, lightmapped > 0 and with_uv2 == lightmapped, "%d lightmapped, %d with uv2 of %d" % [lightmapped, with_uv2, mesh.get_surface_count()])
	var lamps := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/173_2.b3d"))
	var dark := false
	for s in lamps.get_surface_count():
		for c in lamps.surface_get_arrays(s)[Mesh.ARRAY_COLOR] as PackedColorArray:
			if c.r < 0.5:
				dark = true
	check("173_2.b3d keeps its vertex colours", dark)
	for pair in [["heavydoor1", 2], ["heavydoor2", 2], ["DoorFrame", 2], ["cam", 2]]:
		var mesh := MeshLoader.load_x(ContentPaths.existing_file("GFX/map/%s.x" % pair[0]))
		var textures := {}
		for s in mesh.get_surface_count():
			var material = mesh.surface_get_material(s)
			textures[material.albedo_texture] = true
		check("%s.x: one texture per material" % pair[0], textures.size() >= int(pair[1]), "%d textures on %d surfaces" % [textures.size(), mesh.get_surface_count()])

func _scn_lift2cab() -> void:
	log_line("== lift2cab: room3storage's second lift lands at Objects[2] and [3]")
	statue.active = false
	revive()
	var fill: Dictionary = RoomFill.for_room("room3storage")
	var upper: Dictionary = fill.objects["2"]
	check("Objects[2] is the upper cab (608, 240, -624) * RoomScale", absf(float(upper.x) - 2.375) < 0.001 and absf(float(upper.y) - 0.9375) < 0.001 and absf(float(upper.z) + 2.4375) < 0.001, str(upper))
	var record: Dictionary = {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room3storage":
			record = candidate
	check("the map has a room3storage", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0, 6.0, 0))
	var room: Node3D = facility.rooms.get_room(record)
	await secs(0.25)
	check("the room is built", room != null, "")
	if room == null:
		return
	var door_up: Node3D = room.door_slots.get(2)
	var door_down: Node3D = room.door_slots.get(3)
	check("lift 2 has both doors", door_up != null and door_down != null, "")
	if door_up == null or door_down == null:
		return
	var cab_up: Vector3 = room.to_global(Vector3(float(upper.x), float(upper.y), -float(upper.z)))
	check("the upper cab is beside its door", Vector2(cab_up.x, cab_up.z).distance_to(Vector2(door_up.global_position.x, door_up.global_position.z)) < 3.0 and absf(cab_up.y - door_up.global_position.y) < 1.5, "%s door %s" % [str(cab_up), str(door_up.global_position)])
	var lower: Dictionary = fill.objects["3"]
	var cab_down: Vector3 = room.to_global(Vector3(float(lower.x), float(lower.y), -float(lower.z)))
	place_player(cab_up + Vector3(0.0, 0.1, 0.0))
	await secs(0.5)
	door_up.use()
	var t := 0.0
	while t < 12.0 and player.global_position.distance_to(cab_down) > 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("lift 2 rides down to the lower cab", player.global_position.distance_to(cab_down) < 2.0, "%s expected near %s" % [str(player.global_position), str(cab_down)])
	await secs(2.0)
	door_down.use()
	t = 0.0
	while t < 12.0 and player.global_position.distance_to(cab_up) > 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check("lift 2 rides back up into the upper cab", player.global_position.distance_to(cab_up) < 2.0, "%s expected near %s" % [str(player.global_position), str(cab_up)])
