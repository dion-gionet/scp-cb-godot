extends "res://scripts/tests/bot_systems.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_orbit() -> void:
	log_line("== 173 orbit")
	revive()
	var centre := Vector3(86.0, 1.55, -143.0)
	place_statue(centre)
	statue.active = true
	player.blink_timer = 450.0
	var aabb: AABB = (statue.get_node("MeshInstance3D") as MeshInstance3D).get_aabb()
	log_line("   mesh aabb local y %.2f..%.2f scale %.3f visual_y %.2f" % [aabb.position.y, aabb.end.y, (statue.get_node("MeshInstance3D") as Node3D).scale.y, (statue.get_node("MeshInstance3D") as Node3D).position.y])
	var yaw0 := statue.rotation_degrees.y
	for shot_angle in [0.0, 2.1]:
		place_player(centre + Vector3(cos(shot_angle) * 1.6, 0.0, sin(shot_angle) * 1.6))
		face_point(centre + Vector3(0, 0.7, 0))
		await secs(0.5)
		await shot("orbit_cull%s_a%d" % [OS.get_environment("SCP_173_CULL"), int(shot_angle * 10)])
	var pos0 := statue.global_position
	var t := 0.0
	var angle := 0.0
	var worst_yaw := 0.0
	var worst_move := 0.0
	while t < 6.0 and not player.dead:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		angle += dt * 0.6
		place_player(centre + Vector3(cos(angle) * 2.0, 0.0, sin(angle) * 2.0))
		face_point(centre + Vector3(0, 0.8, 0))
		worst_yaw = maxf(worst_yaw, absf(wrapf(statue.rotation_degrees.y - yaw0, -180.0, 180.0)))
		worst_move = maxf(worst_move, statue.global_position.distance_to(pos0))
	log_line("   after orbit: yaw drift %.1f deg, position drift %.2f m, dead=%s, floor gap: statue y %.3f vs placed %.3f" % [worst_yaw, worst_move, player.dead, statue.global_position.y, centre.y])
	statue.active = false
	revive()

func _scn_strafe() -> void:
	log_line("== 173 strafe with natural blinking")
	GameState.god_mode = OS.get_environment("SCP_GOD") == "1"
	revive()
	var centre := Vector3(86.0, 1.55, -143.0)
	place_statue(centre)
	statue.active = true
	place_player(centre + Vector3(1.8, 0.0, 0.0))
	player.blink_timer = 300.0
	var t := 0.0
	var next_log := 0.0
	Input.action_press("move_right")
	while t < 25.0 and not player.dead:
		if OS.get_environment("SCP_FACE") == "away":
			player.camera.rotation.x = 0.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if OS.get_environment("SCP_FACE") == "away":
			face_point(player.global_position * 2.0 - statue.global_position)
		else:
			face_point(statue.global_position + Vector3(0, 0.8, 0))
		if t >= next_log:
			next_log += 2.0
			log_line("   t=%4.1f statue yaw=%7.1f pos=(%.2f, %.2f, %.2f) player dist=%.2f eyes_closed=%s watched_frustum=%s" % [t, statue.rotation_degrees.y, statue.global_position.x, statue.global_position.y, statue.global_position.z, player.global_position.distance_to(statue.global_position), player.eyes_closed(), player.camera.is_position_in_frustum(statue.global_position + Vector3(0, 0.8, 0))])
	Input.action_release("move_right")
	log_line("   ended t=%.1f dead=%s" % [t, player.dead])
	statue.active = false
	revive()

func _scn_doorview() -> void:
	log_line("== door view")
	statue.active = false
	var target: Node3D = null
	for node in facility.rooms.doors.values():
		var door: Node3D = node
		if not door.open and not door.heavy and door.keycard == 0:
			target = door
			break
	if target == null:
		check("door for view test", false, "none")
		return
	var dir: Vector3 = target.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var cull := OS.get_environment("SCP_DOOR_CULL")
	for side in [1.0, -1.0]:
		var pos: Vector3 = target.global_position + dir * 1.3 * side
		place_player(Vector3(pos.x, target.global_position.y + 1.2, pos.z))
		await secs(1.2)
		face_point(target.global_position + Vector3(0, 0.9, 0))
		await secs(0.4)
		await shot("doorview_cull%s_%s" % [cull, "A" if side > 0.0 else "B"])
	log_line("   door at %s yaw %.0f" % [str(target.global_position), target.rotation_degrees.y])

# Loads every generated room and checks that every planned door sits in a real wall gap.
# This is what distinguishes room rotation signs (straight rooms look the same either way).
func _scn_gaps_all() -> void:
	log_line("== doorway gaps, whole map")
	facility.active = false
	for room in facility.generator.rooms:
		facility.rooms.get_room(room)
	for key in facility.rooms.built.keys():
		facility.rooms.spawn_doors(key)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var exclude: Array[RID] = [player.get_rid()]
	for node in get_tree().get_nodes_in_group("door"):
		for body in node.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as StaticBody3D).get_rid())
	var total := 0
	var blocked_edges: Array[String] = []
	var by_shape := {}
	for edge in facility.rooms.door_defs:
		if not facility.rooms.doors.has(edge):
			continue
		var def: Dictionary = facility.rooms.door_defs[edge]
		var door: Node3D = facility.rooms.doors[edge]
		var dir: Vector3 = door.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		var wall := false
		for h in [0.3, 0.7, 1.1]:
			var base: Vector3 = door.global_position + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(base + dir * 0.5, base - dir * 0.5)
			q.collision_mask = 1
			q.exclude = exclude
			if not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
				wall = true
		total += 1
		if wall:
			var a: Dictionary = facility.rooms.by_grid[str(def.a)]
			var b2: Dictionary = facility.rooms.by_grid[str(def.b)]
			blocked_edges.append("%s[%s a%d] -> %s[%s a%d]" % [edge, a.name, a.angle, str(def.b), b2.name, b2.angle])
	check("all %d doorways open across the whole map" % total, blocked_edges.is_empty(), "%d blocked: %s" % [blocked_edges.size(), "; ".join(blocked_edges.slice(0, 6))])


func _scn_fillview() -> void:
	log_line("== room contents")
	statue.active = false
	facility.active = false
	var shown := 0
	for room in facility.generator.rooms:
		var def: Dictionary = RoomFill.for_room(str(room.name))
		if def.is_empty() or def.get("items", []).is_empty() or str(room.name) == "start":
			continue
		var node: Node3D = facility.rooms.get_room(room)
		await secs(0.5)
		var item: Dictionary = def.items[0]
		var local := Vector3(float(item.x), float(item.y), -float(item.z))
		var back := Vector3(-local.x, 0.0, -local.z)
		back = back.normalized() * 1.2 if back.length() > 0.1 else Vector3(0, 0, 1.2)
		var spot: Vector3 = node.to_global(Vector3(local.x + back.x, 0.0, local.z + back.z))
		place_player(Vector3(spot.x, node.global_position.y + 1.0, spot.z))
		await secs(1.0)
		var target: Vector3 = node.to_global(local)
		face_point(target)
		var look: Vector3 = target - player.camera.global_position
		player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		await secs(0.3)
		log_line("   %s: %d doors %d items; first item %s (%s) at local %s" % [room.name, def.get("doors", []).size(), def.items.size(), item.name, str(item.tempname), str(local)])
		await shot("fill_%s" % room.name)
		shown += 1
		if shown >= 3:
			break
	check("rooms with items shown", shown >= 1, "%d" % shown)

func _scn_startroom() -> void:
	log_line("== start room views")
	statue.active = false
	var start: Node3D = facility.start_node
	log_line("   start room at %s angle %.0f" % [str(start.global_position), start.rotation_degrees.y])
	for node in get_tree().get_nodes_in_group("door"):
		var d: Node3D = node
		if d.global_position.distance_to(start.global_position) < 20.0:
			log_line("   door %s open=%s locked=%s buttons=%d yaw=%.0f big=%s" % [str(d.global_position), str(d.open), str(d.locked), d.buttons.size(), d.rotation_degrees.y, str(d.big)])
	var views := [
		["edge_from_outside", Vector3(0.0, 0.6, 7.5), Vector3(0.0, 0.8, 0.0)],
		["edge_just_inside", Vector3(0.0, 0.6, 3.0), Vector3(0.0, 0.8, -3.0)],
		["toward_edge_from_room", Vector3(0.0, 1.9, -3.0), Vector3(0.0, 0.8, 4.0)],
		["room_center_up", Vector3(0.0, 1.9, 0.0), Vector3(0.0, 2.5, -4.0)],
		["west_side", Vector3(-3.0, 1.9, 0.0), Vector3(3.0, 1.0, 0.0)],
	]
	for v in views:
		place_player(start.to_global(v[1]))
		await secs(1.0)
		face_point(start.to_global(v[2]))
		await secs(0.4)
		await shot("start_" + str(v[0]))

func _scn_startmap() -> void:
	log_line("== start room floor plan (local x right, z down; digit = floor height in 0.5 m, D door, P player spawn)")
	var start: Node3D = facility.start_node
	var space := get_viewport().world_3d.direct_space_state
	var doors := []
	for node in get_tree().get_nodes_in_group("door"):
		var d: Node3D = node
		var l: Vector3 = start.to_local(d.global_position)
		if absf(l.x) < 30.0 and absf(l.z) < 20.0:
			doors.append(Vector2(roundf(l.x * 2.0) / 2.0, roundf(l.z * 2.0) / 2.0))
	for iz in range(-24, 17):
		var z := iz * 0.5
		var line := ""
		for ix in range(-20, 45):
			var x := ix * 0.5
			var mark := " "
			if doors.has(Vector2(x, z)):
				mark = "D"
			else:
				var from := start.to_global(Vector3(x, 6.0, z))
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0)
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					mark = "."
				else:
					var h: float = hit.position.y - start.global_position.y
					mark = str(clampi(int(round(h * 2.0)), 0, 9)) if h > -0.2 else "-"
			line += mark
		log_line("%+5.1f %s" % [z, line])

func _scn_startdoors() -> void:
	log_line("== start room doors and buttons")
	var start: Node3D = facility.start_node
	var space := get_viewport().world_3d.direct_space_state
	for node in get_tree().get_nodes_in_group("door"):
		var d: Node3D = node
		var l: Vector3 = start.to_local(d.global_position)
		if absf(l.x) > 18.0 or absf(l.z) > 12.0:
			continue
		log_line("   door local %s yaw %.0f locked=%s open=%s" % [str(l), d.rotation_degrees.y, str(d.locked), str(d.open)])
		for b in d.buttons:
			var bp: Vector3 = b.global_position
			var inside := false
			# a button is "buried" when the point 0.1 in front of its face is inside geometry
			var forward: Vector3 = b.global_transform.basis.z
			for off in [0.0, 0.1, 0.2]:
				var q := PhysicsRayQueryParameters3D.create(bp + forward * (off + 0.3), bp + forward * off)
				q.collision_mask = 1
				if not space.intersect_ray(q).is_empty():
					inside = true
			log_line("      button local %s buried=%s" % [str(start.to_local(bp)), str(inside)])

func _scn_exitdoor() -> void:
	log_line("== exit doors, lit")
	statue.active = false
	var start: Node3D = facility.start_node
	for mat in start.materials:
		mat.set_shader_parameter("light_energy", 4.0)
	var views := [
		["landing_from_below", Vector3(5.0, 0.8, 2.5), Vector3(5.0, 2.0, -1.2)],
		["landing_from_west", Vector3(1.5, 2.2, -1.2), Vector3(5.0, 1.9, -1.2)],
		["landing_from_east", Vector3(9.0, 2.2, -1.2), Vector3(5.0, 1.9, -1.2)],
		["landing_from_north", Vector3(5.0, 2.2, -4.0), Vector3(5.0, 1.9, -1.2)],
	]
	for v in views:
		place_player(start.to_global(v[1]))
		await secs(0.8)
		face_point(start.to_global(v[2]))
		await secs(0.3)
		await shot("exit_" + str(v[0]))

func _scn_neighbors() -> void:
	log_line("== rooms and doors around the start room")
	var start: Node3D = facility.start_node
	for r in facility.generator.rooms:
		var p: Vector3 = r.position
		if p.distance_to(start.global_position) < 20.0:
			log_line("   room %s grid %s angle %d at %s" % [str(r.name), str(r.grid), int(r.angle), str(p)])
	for node in get_tree().get_nodes_in_group("door"):
		var d: Node3D = node
		if d.global_position.distance_to(start.global_position) < 20.0:
			log_line("   door %s yaw %.0f parent=%s" % [str(d.global_position), d.rotation_degrees.y, str(d.room.name) if d.room != null else "map"])

func _scn_nextroom() -> void:
	log_line("== next room (room4info) door views, lit")
	statue.active = false
	for key in facility.rooms.built:
		for mat in facility.rooms.built[key].materials:
			mat.set_shader_parameter("light_energy", 4.0)
	var c: Vector3 = facility.start_node.global_position + Vector3(0.0, 0.0, 8.0)
	var views := [
		["to_south_edge", Vector3(0.0, 1.2, 1.5), Vector3(0.0, 1.0, -4.0)],
		["to_west", Vector3(2.0, 1.2, 0.0), Vector3(-4.0, 1.0, 0.0)],
		["to_east", Vector3(-2.0, 1.2, 0.0), Vector3(4.0, 1.0, 0.0)],
		["to_north", Vector3(0.0, 1.2, -1.5), Vector3(0.0, 1.0, 4.0)],
	]
	for v in views:
		place_player(c + v[1])
		await secs(0.8)
		face_point(c + v[2])
		await secs(0.3)
		await shot("next_" + str(v[0]))

func _scn_unlit() -> void:
	log_line("== disable lighting")
	var overlay: Node = null
	for node in get_tree().root.find_children("*", "Control", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("debug_overlay.gd"):
			overlay = node
	check("debug overlay exists", overlay != null, "")
	if overlay == null:
		return
	var room: Node3D = facility.start_node
	var room_mat: ShaderMaterial = null
	for mat in room.materials:
		room_mat = mat
		break
	var before: bool = room_mat.get_shader_parameter("fullbright") == true
	overlay._set_unlit(true)
	await secs(0.3)
	check("room shaders go fullbright", before == false and room_mat.get_shader_parameter("fullbright") == true, "")
	place_player(facility.start_node.to_global(Vector3(0.0, 1.2, -1.0)))
	await secs(0.5)
	face_point(facility.start_node.to_global(Vector3(0.0, 1.0, 4.0)))
	await secs(0.3)
	await shot("unlit_start_room")
	var entity_white := false
	var any_standard := 0
	for mesh_node in room.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mesh_node
		if m.mesh != null and m.mesh.get_surface_count() > 0 and (m.mesh.surface_get_material(0) is StandardMaterial3D or m.mesh.surface_get_material(0) is EntityMaterial):
			any_standard += 1
			entity_white = m.mesh.surface_get_material(0).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			break
	check("lit models in the room go flat", any_standard == 0 or entity_white, "%d checked" % any_standard)
	overlay._set_unlit(false)
	await secs(0.3)
	check("lighting returns when switched off", room_mat.get_shader_parameter("fullbright") == false, "")

# Where do the room walls sit relative to a door's plane? A sliding leaf is only hidden when a
# wall face lies in front of it. For each door, 0.9 m to one side of its centre (where the
# open leaf rests) rays go both ways along the door's normal; distances to the first wall face.
func _scn_pockets() -> void:
	log_line("== wall pockets beside doors (d- / d+ = distance to the first wall face each way)")
	facility.active = false
	for room in facility.generator.rooms:
		facility.rooms.get_room(room)
	for key in facility.rooms.built.keys():
		facility.rooms.spawn_doors(key)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var exclude: Array[RID] = [player.get_rid()]
	for node in get_tree().get_nodes_in_group("door"):
		for body in node.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as StaticBody3D).get_rid())
	var space := get_viewport().world_3d.direct_space_state
	var buckets := {}
	for node in get_tree().get_nodes_in_group("door"):
		var door: Node3D = node
		if door.get("heavy") == true or door.get("big") == true or door.get("elevator") == true:
			continue
		var dir: Vector3 = door.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		var side: Vector3 = door.global_transform.basis.x
		side.y = 0.0
		side = side.normalized()
		var tag := ""
		for s in [1.0, -1.0]:
			var base: Vector3 = door.global_position + Vector3(0, 0.7, 0) + side * 0.9 * s
			var d_neg := _ray_dist(space, base, -dir, exclude)
			var d_pos := _ray_dist(space, base, dir, exclude)
			tag += "[%s%.2f/%s%.2f]" % ["-" if d_neg < 0.0 else "", absf(d_neg), "-" if d_pos < 0.0 else "", absf(d_pos)]
		var kind := "map" if door.room == null else str(door.room.room_name)
		var row: Array = buckets.get(tag, [])
		row.append(kind)
		buckets[tag] = row
	var keys := buckets.keys()
	keys.sort_custom(func(a, b) -> bool: return (buckets[a] as Array).size() > (buckets[b] as Array).size())
	for tag in keys:
		var kinds: Array = buckets[tag]
		log_line("   %3d x %s  %s" % [kinds.size(), tag, ", ".join(kinds.slice(0, 5))])

# Unlit views of a world point from several offsets: SCP_VIEW="x,y,z" is the target.
func _scn_viewpoint() -> void:
	log_line("== unlit views of a point")
	statue.active = false
	var parts := OS.get_environment("SCP_VIEW").split(",")
	var target := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	for key in facility.rooms.built:
		for mat in facility.rooms.built[key].materials:
			mat.set_shader_parameter("fullbright", true)
	for door in get_tree().get_nodes_in_group("door"):
		for mesh_node in door.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mesh_node
			for s in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s)
				if mat is StandardMaterial3D or mat is EntityMaterial:
					mat.albedo_color = Color.WHITE
	var offsets := [Vector3(0, 0, 3.0), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5), Vector3(0, 0, -3.0), Vector3(2.5, 0, -2.5)]
	if not OS.get_environment("SCP_FROM").is_empty():
		offsets = []
		for spec in OS.get_environment("SCP_FROM").split(";"):
			var p := spec.split(",")
			offsets.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var i := 0
	for off in offsets:
		place_player(target + off + Vector3(0, 0.6, 0))
		await secs(0.8)
		face_point(target)
		await secs(0.3)
		await shot("view_%d" % i)
		i += 1

# SCP_MODEL="GFX/npcs/scp-049.b3d" SCP_SCALE=1.2: the model in front of the camera, unlit lit.
func _scn_modelview() -> void:
	log_line("== model view")
	statue.active = false
	var path := OS.get_environment("SCP_MODEL")
	var scale_value := float(OS.get_environment("SCP_SCALE")) if not OS.get_environment("SCP_SCALE").is_empty() else 1.0
	var frames: PackedStringArray = OS.get_environment("SCP_FRAMES").split(",", false) if not OS.get_environment("SCP_FRAMES").is_empty() else PackedStringArray()
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * scale_value
	get_tree().root.add_child(holder)
	var model: Node3D = null
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	if frames.size() > 0:
		model = load("res://scripts/io/b3d_model.gd").new()
		holder.add_child(model)
		var ok: bool = model.load_file(ContentPaths.existing_file(path))
		log_line("   skinned model ok=%s bones=%d skinned=%s frames=%d animated=%d" % [str(ok), model.bone_names.size(), str(model.skinned), model.frame_count, model._animated.size()])
		var fmt: int = model.mesh_instance.mesh.surface_get_format(0)
		log_line("   fmt bones=%s weights=%s skin binds=%d skel path=%s" % [str((fmt & Mesh.ARRAY_FORMAT_BONES) != 0), str((fmt & Mesh.ARRAY_FORMAT_WEIGHTS) != 0), model.mesh_instance.skin.get_bind_count(), str(model.mesh_instance.skeleton)])
		for ni in model._nodes.size():
			var nd: Dictionary = model._nodes[ni]
			if nd.meshes.size() > 0 or nd.weights.size() > 0 or ni < 6:
				log_line("     node %d %s parent=%d meshes=%d weights=%d verts=%s" % [ni, str(nd.name), int(nd.parent), nd.meshes.size(), nd.weights.size(), str((nd.meshes[0].positions.size() if nd.meshes.size() > 0 else 0))])
		for ai in model._animated.slice(0, 4):
			var an: Dictionary = model._nodes[ai]
			log_line("     %s pos=%d rot=%d scale=%d first=%s" % [str(an.name), an.pos_keys.size(), an.rot_keys.size(), an.scale_keys.size(), str(an.rot_keys[0][0]) if an.rot_keys.size() > 0 else "-"])
	else:
		var ML = load("res://scripts/io/mesh_loader.gd")
		var mesh: ArrayMesh = ML.load_b3d(ContentPaths.existing_file(path)) if path.ends_with(".b3d") else ML.load_x(ContentPaths.existing_file(path))
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		holder.add_child(inst)
		log_line("   aabb %s scaled size %s" % [str(mesh.get_aabb()), str(mesh.get_aabb().size * scale_value)])
	holder.global_position = home + Vector3(0, 0, -2.5)
	holder.global_position.y = facility.start_node.global_position.y + 1.5
	place_player(home)
	await secs(0.8)
	face_point(holder.global_position + Vector3(0, 0.6, 0))
	await secs(0.3)
	if frames.is_empty():
		await shot("model_front")
		holder.rotation.y = PI * 0.5
		await secs(0.3)
		await shot("model_side")
	else:
		var i := 0
		for f in frames:
			model.set_frame(float(f))
			var probe_bone := 20
			log_line("   frame %s bone20 rot %s global %s" % [f, str(model.skeleton.get_bone_pose_rotation(probe_bone)), str(model.skeleton.get_bone_global_pose(probe_bone).origin)])
			await secs(0.3)
			await shot("model_frame_%d" % i)
			i += 1
# Normal lighting: shots of SCP_VIEW="x,y,z" from SCP_FROM offsets ("dx,dy,dz;...").
func _scn_litview() -> void:
	log_line("== lit views")
	statue.active = false
	var parts := OS.get_environment("SCP_VIEW").split(",")
	var target := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var i := 0
	for spec in OS.get_environment("SCP_FROM").split(";"):
		var p := spec.split(",")
		place_player(target + Vector3(float(p[0]), float(p[1]), float(p[2])))
		await secs(1.0)
		face_point(target)
		await secs(0.3)
		await shot("lit_%d" % i)
		i += 1

# SCP-049 standing 3 m away and turned to face the player: is it the front we see?
func _scn_facing049() -> void:
	log_line("== 049 facing")
	statue.active = false
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	await get_tree().physics_frame
	npc.global_position = _clear_spot(player.global_position, 3.0) + Vector3(0, 0.05, 0)
	npc._turn_toward(player.global_position, 100.0)
	npc.state = 2
	npc.state2 = 140.0
	npc.curr_speed = 0.0
	for mode in ["still", "walking"]:
		if mode == "walking":
			npc._set_frame(361.0)
		face_point(npc.global_position + Vector3(0, 0.4, 0))
		await secs(0.3)
		await shot("facing049_" + mode)
	facility.scp049 = null
	npc.queue_free()

# SCP-106 standing 3 m away turned to face the player: is it the front we see?
func _scn_facing106() -> void:
	log_line("== 106 facing")
	statue.active = false
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var npc: CharacterBody3D = facility.spawn_106(0.0)
	await get_tree().physics_frame
	npc.global_position = _clear_spot(player.global_position, 3.0) + Vector3(0, 0.05, 0)
	npc._turn_toward(player.global_position, 100.0, 1.0)
	npc.state = -10.0
	npc.prev_y = npc.global_position.y
	npc._set_frame(300.0)
	npc.curr_speed = 0.0
	face_point(npc.global_position + Vector3(0, 0.4, 0))
	await secs(0.4)
	await shot("facing106")
	npc.queue_free()
	facility.scp106 = null

# Which way do 106's feet point? (printed: negative z = along the node's forward)
func _scn_feet106() -> void:
	log_line("== 106 feet")
	statue.active = false
	var npc: CharacterBody3D = facility.spawn_106(0.0)
	await get_tree().physics_frame
	npc.state = 5000.0
	var mesh: ArrayMesh = npc._visual.mesh_instance.mesh
	var all := PackedVector3Array()
	for s in mesh.get_surface_count():
		all.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var low := 1e9
	var high := -1e9
	for v in all:
		low = minf(low, v.y)
		high = maxf(high, v.y)
	var feet := PackedVector3Array()
	for v in all:
		if v.y < low + (high - low) * 0.06:
			feet.append(v)
	var sum := Vector3.ZERO
	for v in feet:
		sum += v
	var centre := sum / maxf(feet.size(), 1)
	var extreme := 0.0
	for v in feet:
		if absf(v.z - centre.z) > absf(extreme):
			extreme = v.z - centre.z
	log_line("   height %.2f feet %d vertices, toe offset z %.3f (negative = forward)" % [high - low, feet.size(), extreme])
	npc.queue_free()
	facility.scp106 = null


func _scn_pocketlook() -> void:
	log_line("== pocket look")
	statue.active = false
	GameState.god_mode = true
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	pocket.set_physics_process(false)    # freeze the event: only look around
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	if OS.get_environment("SCP_LOOK_BRIGHT") == "1":
		env.fog_enabled = false
		env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var spots := {
		"look_throne": [Vector3(0, 0.5, 32), Vector3(0, 1.0, 20)],
		"look_trench": [Vector3(0, 11.5, 32), Vector3(0, 11.0, 20)],
		"look_pillars": [Vector3(0, 0.5, 64), Vector3(0, 1.0, 70)],
		"look_exit": [Vector3(-1.5, -0.3, 32), Vector3(2.0, -0.5, 32)],
	}
	for key in spots:
		var spot: Array = spots[key]
		pocket._put(player, pocket.B(spot[0].x, spot[0].y, spot[0].z))
		player.blink_timer = 400.0
		GameState.blur_timer = 0.0
		GameState.blur_volume = 0.0
		face_point(pocket.B(spot[1].x, spot[1].y, spot[1].z))
		await secs(0.6)
		player.blink_timer = 400.0
		await shot(key)

# Main.bb 4651-4676: after 106's eyes, blinking shows kneelmortal.pd and plays the Screech, which loops while the eyes stay shut.
func _scn_pocketkneel() -> void:
	log_line("== pocket kneel blink")
	statue.active = false
	GameState.god_mode = true
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	pocket.set_physics_process(false)
	pocket.event_str = 500.0
	player.blink_timer = -4.0
	pocket._kneel_blink(player)
	check("no image before the eyes are met", pocket._kneel_image == null or not pocket._kneel_image.visible)
	pocket.event_str = 1000.0
	pocket._kneel_blink(player)
	check("the blink image shows at BlinkTimer > -5", pocket._kneel_image.visible and pocket._screech.playing)
	var offsets := {}
	for i in 30:
		pocket._kneel_blink(player)
		offsets[pocket._kneel_image.position] = true
	check("the image jitters every frame", offsets.size() > 1)
	player.blink_timer = -4.5
	pocket._kneel_blink(player)
	player.blink_timer = -2.0
	pocket._kneel_blink(player)
	check("eyes open hide the image and stop the screech", not pocket._kneel_image.visible and not pocket._screech.playing)
	player.blink_timer = -11.0
	pocket._kneel_blink(player)
	check("a blink past -10 loops the screech without the image", not pocket._kneel_image.visible and pocket._screech.playing)
	pocket.set_physics_process(true)
	pocket._exit_to(["room2shaft", "room106"], player)

# A close look at 049's head (the plague mask) from the front, in even light.
func _scn_view049head() -> void:
	log_line("== 049 head")
	statue.active = false
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var npc: CharacterBody3D = facility.spawn_049(0.0)
	await get_tree().physics_frame
	npc.global_position = _clear_spot(player.global_position, 1.3) + Vector3(0, 0.05, 0)
	npc._turn_toward(player.global_position, 100.0)
	npc.state = 2
	npc.state2 = 140.0
	npc.curr_speed = 0.0
	var head := npc.global_position + Vector3(0, 1.62, 0)
	for angle in [0.0, 60.0, -60.0]:
		var away: Vector3 = (player.global_position - npc.global_position)
		away.y = 0.0
		var spot: Vector3 = npc.global_position + away.normalized().rotated(Vector3.UP, deg_to_rad(angle)) * 1.0
		place_player(Vector3(spot.x, player.global_position.y, spot.z))
		face_point(head)
		await secs(0.4)
		await shot("head049_%d" % int(angle))
	facility.scp049 = null
	npc.queue_free()

# TEXS entries are name + 7 numbers (flags, blend, position, scale, rotation): reading one number
# short shifted every later texture, which left 049's mask without its picture.
func _scn_b3dtex() -> void:
	log_line("== b3d texture list")
	var model = load("res://scripts/io/b3d_model.gd").new()
	model.parse_file(ContentPaths.existing_file("GFX/npcs/scp-049.b3d"))
	check("049's file lists its two pictures", model._textures.size() == 2 and not str(model._textures[0]).is_empty() and not str(model._textures[1]).is_empty(), str(model._textures))
	var mapped := true
	for slot in model._brush_tex:
		mapped = mapped and slot >= 0
	check("each of 049's brushes (mask, clothing) has a picture", mapped and model._brush_tex.size() == 2, str(model._brush_tex))
	var mask_texture := ""
	for node in model._nodes:
		for mesh_data in node.meshes:
			for surface in mesh_data.surfaces:
				if int(surface.brush) == 0:
					mask_texture = str(model._textures[model._brush_tex[0]])
	check("the first brush is the mask's picture", mask_texture.contains("mask"), mask_texture)
	model.free()

# The human models (guard, class D, MTF): size, bones, frame count, and a picture of each pose.
func _scn_humanview() -> void:
	log_line("== human models")
	statue.active = false
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var files := {"guard": ["GFX/npcs/guard.b3d", 0.29 / 2.5], "classd": ["GFX/npcs/classd.b3d", 0.5], "mtf": ["GFX/npcs/MTF2.b3d", 0.29 / 2.5]}
	for key in files:
		var model = load("res://scripts/io/b3d_model.gd").new()
		var holder := Node3D.new()
		get_tree().root.add_child(holder)
		holder.add_child(model)
		var ok: bool = model.load_file(ContentPaths.existing_file(files[key][0]))
		var box: AABB = model.mesh_instance.get_aabb() if model.mesh_instance != null else AABB()
		var scale_value: float = files[key][1]
		if key == "classd":
			scale_value = 0.5 / box.size.x
		holder.scale = Vector3.ONE * scale_value
		log_line("   %s ok=%s bones=%d frames=%d aabb %s height %.2f m at scale %.4f" % [key, str(ok), model.bone_names.size(), model.frame_count, str(box), box.size.y * scale_value, scale_value])
		var bone_list := ""
		for name in model.bone_names:
			if str(name).to_lower().contains("chest") or str(name).to_lower().contains("head"):
				bone_list += str(name) + " "
		log_line("   %s chest/head bones: %s" % [key, bone_list])
		holder.global_position = _clear_spot(player.global_position, 3.0) + Vector3(0, 0.05, 0)
		holder.rotation.y = atan2(-(player.global_position.x - holder.global_position.x), -(player.global_position.z - holder.global_position.z)) + PI
		for pose in [1.0, 220.0, 245.0, 310.0, 19.0, 100.0, 302.0, 246.0, 287.0]:
			model.set_frame(pose)
			face_point(holder.global_position + Vector3(0, 0.9, 0))
			await secs(0.25)
			await shot("human_%s_%d" % [key, int(pose)])
		holder.queue_free()

# Pictures of the human NPCs in game: a guard aiming at the player, a scientist and a Class D walking.
func _scn_humanshots() -> void:
	log_line("== human pictures")
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	statue.active = false
	GameState.god_mode = true
	var Human = load("res://scripts/npc/human_npc.gd")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var guard: CharacterBody3D = facility.spawn_human(Human.Kind.GUARD, _clear_spot(player.global_position, 4.0) + Vector3(0, 0.05, 0))
	guard.state = 1
	await secs(1.0)
	face_point(guard.global_position + Vector3(0, 0.9, 0))
	await secs(0.2)
	await shot("guard_aim")
	guard.state = 0
	guard.rotation.y += PI * 0.6
	guard.angle = rad_to_deg(guard.rotation.y)
	await secs(0.3)
	await shot("guard_side")
	facility.remove_human(guard)
	var scientist: CharacterBody3D = facility.spawn_human(Human.Kind.CLASS_D, _clear_spot(player.global_position, 3.0) + Vector3(0, 0.05, 0), 3)
	scientist.state = 1
	await secs(0.8)
	face_point(scientist.global_position + Vector3(0, 0.9, 0))
	await secs(0.2)
	await shot("scientist_walk")
	facility.remove_human(scientist)
	var d: CharacterBody3D = facility.spawn_human(Human.Kind.CLASS_D, _clear_spot(player.global_position, 3.0) + Vector3(0, 0.05, 0), 0)
	d.state = 2
	await secs(0.8)
	face_point(d.global_position + Vector3(0, 0.9, 0))
	await secs(0.2)
	await shot("classd_run")
	facility.remove_human(d)

func _scn_triggers() -> void:
	log_line("== trigger boxes of the start room")
	var room: Node3D = facility.start_node
	for box in room.triggers:
		log_line("   %s low %s high %s" % [box.name, str(box.low), str(box.high)])
	check("the start room has trigger boxes", room.triggers.size() >= 3, "%d" % room.triggers.size())

func _scn_cellfloor() -> void:
	log_line("== cell floor")
	var chamber: Node3D = get_tree().get_first_node_in_group("chamber")
	for spot in [Vector2(-4248.0, 8.0), Vector2(-4072.0, 104.0), Vector2(-4096.0, 192.0), Vector2(-3072.0, 192.0)]:
		for max_y in [0.5, 1.05, 2.2]:
			log_line("   x %.0f z %.0f max %.2f -> floor %.3f" % [spot.x, spot.y, max_y, chamber.floor_height(spot.x * 8.0 / 2048.0, -spot.y * 8.0 / 2048.0, max_y)])

# Every pickup within 40 units of the start room and where it came from.
func _scn_pickupsnear() -> void:
	log_line("== pickups near the start room")
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(1.0)
	for node in get_tree().get_nodes_in_group("pickup"):
		var item := node as Node3D
		if item == null or item.global_position.distance_to(home) > 40.0:
			continue
		var room_name: String = facility.room_name_at(item.global_position)
		log_line("   %s at %s (%.1f from the start spot) room %s fill_id %s" % [str(item.get_meta("item_name", "?")), str(item.global_position), item.global_position.distance_to(home), room_name, str(item.get_meta("fill_id", "-"))])

# Pictures of room2sl's monitor wall and lever, and of a checkpoint with the lockdown on.
func _scn_slview() -> void:
	log_line("== room2sl and checkpoint pictures")
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	for wanted in ["room2sl", "checkpoint1"]:
		var record := _find_room(wanted)
		if record.is_empty():
			continue
		var room: Node3D = facility.rooms.get_room(record)
		if wanted == "room2sl":
			place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
			await secs(1.5)
			var lever: Node3D = room.extras.lever
			var handle: Vector3 = lever.handle_point()
			for step in 16:
				var dir := Vector3(cos(TAU * step / 16.0), 0.0, sin(TAU * step / 16.0))
				var spot: Vector3 = handle + dir * 0.9
				var down := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.5, 0), spot + Vector3(0, -3.0, 0))
				down.collision_mask = 1
				var hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
				if hit.is_empty() or absf(hit.position.y - (handle.y - 1.0)) > 1.2:
					continue
				place_player(hit.position + Vector3(0, 0.1, 0))
				await secs(0.3)
				face_point(handle)
				var look: Vector3 = handle - player.camera.global_position
				player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
				await secs(0.3)
				await shot("sl_lever_up")
				lever.pitch = -80.0
				await secs(0.3)
				await shot("sl_lever_down")
				lever.pitch = 80.0
				break
			var wall: Vector3 = room.extras.monitors[0].global_position
			place_player(room.to_global(Vector3(0.6, room.floor_y(0.6, 0.0) + 0.1, 0.0)))
			await secs(0.5)
			face_point(wall)
			await secs(0.3)
			await shot("sl_wall")
		else:
			facility.events.sl.lever_on = true
			for index in 2:
				var mon: Node3D = room.extras.monitors[index]
				for sign in [1.0, -1.0]:
					var stand: Vector3 = room.to_global(room.to_local(mon.global_position) + Vector3(0.0, 0.0, 1.6 * sign))
					place_player(Vector3(stand.x, room.floor_y(room.to_local(stand).x, room.to_local(stand).z) + room.global_position.y + 0.1, stand.z))
					await secs(0.6)
					face_point(mon.global_position)
					var look3: Vector3 = mon.global_position - player.camera.global_position
					player.camera.rotation.x = atan2(look3.y, Vector2(look3.x, look3.z).length())
					player.user_pitch = -rad_to_deg(player.camera.rotation.x)
					await secs(0.3)
					await shot("checkpoint_m%d_%s" % [index, "a" if sign > 0.0 else "b"])
			facility.events.sl.lever_on = false
	GameState.god_mode = false

# Brush flags and pictures of a few NPC models (is a model fullbright in the original?).
func _scn_brushfx() -> void:
	log_line("== brush FX of NPC models")
	for file in ["GFX/npcs/106_2.b3d", "GFX/npcs/scp-049.b3d", "GFX/npcs/guard.b3d", "GFX/npcs/MTF2.b3d", "GFX/npcs/173_2.b3d"]:
		var model = load("res://scripts/io/b3d_model.gd").new()
		model.parse_file(ContentPaths.existing_file(file))
		log_line("   %s: brush fx %s, textures %s" % [file, str(model._brush_fx), str(model._textures)])
		model.load_file(ContentPaths.existing_file(file))
		if model.mesh_instance != null:
			var with_normals := 0
			var surface_count: int = model.mesh_instance.mesh.get_surface_count()
			for surface in surface_count:
				if (model.mesh_instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_NORMAL) != 0:
					with_normals += 1
			log_line("      %d of %d surfaces carry normals" % [with_normals, surface_count])
		model.free()

# SCP-106 next to a guard in the same light: his brightness and which way he faces.
func _scn_see106() -> void:
	log_line("== 106 and a guard side by side")
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	log_line("   ambient colour %s energy %.2f source %d" % [str(env.ambient_light_color), env.ambient_light_energy, env.ambient_light_source])
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.6)
	var spot: Vector3 = _clear_spot(player.global_position, 3.0)
	var old_man: CharacterBody3D = facility.spawn_106(-1000.0)
	old_man.state = -10.0
	old_man.global_position = spot + Vector3(0.0, 0.05, 0.0)
	old_man.prev_y = spot.y
	old_man.frame = 334.0
	old_man.rotation.y = atan2(-(player.global_position.x - spot.x), -(player.global_position.z - spot.z))
	var Human = load("res://scripts/npc/human_npc.gd")
	var guard: CharacterBody3D = facility.spawn_human(Human.Kind.GUARD, spot + Vector3(1.0, 0.05, 0.0))
	guard.state = 13
	guard.rotation.y = old_man.rotation.y
	await secs(0.5)
	face_point(spot + Vector3(0.5, 0.9, 0.0))
	await secs(0.3)
	await shot("see106_front")
	# the same two under a room light (the lights light the entities, not the lightmapped room)
	var lit_room: Node3D = null
	for key in facility.rooms.built:
		var candidate: Node3D = facility.rooms.built[key]
		if "lights" in candidate and candidate.lights.size() > 0 and candidate != facility.start_node:
			lit_room = candidate
			break
	if lit_room != null:
		var lamp: Light3D = lit_room.lights[0]
		var floor_point := Vector3(lamp.global_position.x + 1.0, lit_room.global_position.y + 0.1, lamp.global_position.z)
		place_player(floor_point + Vector3(3.0, 0.1, 0.0))
		await secs(0.8)
		old_man.global_position = floor_point
		old_man.prev_y = floor_point.y
		guard.global_position = floor_point + Vector3(0.0, 0.0, 1.0)
		old_man.rotation.y = atan2(-(player.global_position.x - floor_point.x), -(player.global_position.z - floor_point.z))
		guard.rotation.y = old_man.rotation.y
		await secs(0.5)
		face_point(floor_point + Vector3(0.0, 0.9, 0.5))
		await secs(0.3)
		log_line("   lamp at %s, visible %s, energy %.2f range %.1f, in %s" % [str(lamp.global_position), str(lamp.visible), lamp.light_energy, lamp.get("omni_range") if lamp is OmniLight3D else 0.0, str(lit_room.name)])
		await shot("see106_lit")
	GameState.god_mode = false

# Which textures the rmeshes draw with alpha (flag 3 in the original, FX 3 = fullbright + vertex colours).
func _scn_alphatex() -> void:
	log_line("== alpha surfaces of the rmeshes")
	var dir := DirAccess.open(ContentPaths.existing_file("GFX/map").get_base_dir() + "/map")
	var seen := {}
	for file in dir.get_files():
		if not file.ends_with(".rmesh"):
			continue
		var parsed := MeshLoader.parse_rmesh(ContentPaths.existing_file("GFX/map/" + file))
		for surface in parsed.surfaces:
			if surface.alpha:
				var colors: PackedColorArray = surface.arrays[Mesh.ARRAY_COLOR]
				var key := "%s  light=%s  vertex colour0=%s" % [str(surface.albedo).get_file(), str(surface.light).get_file(), str(colors[0]) if colors.size() > 0 else "-"]
				seen[key] = str(seen.get(key, "")) + " " + file.get_basename()
	for key in seen:
		log_line("   %s :%s" % [key, str(seen[key]).substr(0, 120)])

# The player in front of the nearest rmesh glass, for comparing its brightness with the original.
func _scn_glassview() -> void:
	log_line("== rmesh glass")
	var best := Vector3.INF
	var best_normal := Vector3.ZERO
	var from: Vector3 = player.global_position
	for key in facility.rooms.built:
		var room: Node3D = facility.rooms.built[key]
		for node in room.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.mesh.surface_get_material(surface) as ShaderMaterial
				if mat == null or mat.shader == null or not mat.shader.resource_path.ends_with("lightmap_alpha.gdshader"):
					continue
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if vertices.size() < 3:
					continue
				var sum := Vector3.ZERO
				for v in vertices:
					sum += mesh_instance.global_transform * v
				var centre := sum / float(vertices.size())
				log_line("   glass surface %d verts at %s (room %s)" % [surface, str(centre), room.name])
				if best == Vector3.INF or centre.distance_to(from) < best.distance_to(from):
					best = centre
					var a := mesh_instance.global_transform * vertices[0]
					var b := mesh_instance.global_transform * vertices[1]
					var c := mesh_instance.global_transform * vertices[2]
					best_normal = (b - a).cross(c - a).normalized()
	if best == Vector3.INF:
		log_line("   no glass in the rooms")
		return
	var flat := Vector3(best_normal.x, 0.0, best_normal.z).normalized()
	var spot := best + flat * 2.5
	spot.y = best.y - 0.3
	place_player(Vector3(spot.x, floorf(best.y) + 1.55, spot.z))
	await secs(1.0)
	face_point(best)
	await secs(0.5)
	await shot("glassview")

# How long the first MTF squad and its announcement take to appear (a hitch there is a dropped frame or ten).
func _scn_mtfhitch() -> void:
	log_line("== MTF spawn cost")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(1.0)
	var spot: Vector3 = facility.start_node.global_position + Vector3(0.0, 1.0, -8.0)
	for round in 2:
		var t0 := Time.get_ticks_usec()
		var leader: Node = null
		for i in 3:
			var t1 := Time.get_ticks_usec()
			var unit: Node = facility.mtf.spawn(spot + Vector3(0.3 * (i - 1), 0.0, 0.0), leader)
			if i == 0:
				leader = unit
			log_line("   round %d unit %d spawn_mtf: %.1f ms" % [round, i, (Time.get_ticks_usec() - t1) / 1000.0])
		var t2 := Time.get_ticks_usec()
		facility.mtf.play_announcement("SFX/Character/MTF/Announc.ogg")
		log_line("   round %d announcement: %.1f ms" % [round, (Time.get_ticks_usec() - t2) / 1000.0])
		var f0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		await get_tree().process_frame
		log_line("   round %d next frame after spawning: %.1f ms (total call %.1f ms)" % [round, (Time.get_ticks_usec() - f0) / 1000.0, (Time.get_ticks_usec() - t0) / 1000.0])
		await secs(1.5)
		for unit in facility.mtf.units.duplicate():
			facility.mtf.remove(unit)

# A volumetric-lighting room (light cones) and a plain one, to look at the cones, glows and fixtures.
func _scn_cones() -> void:
	log_line("== light cones")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) in ["room049", "room513", "room966"]:
			record = candidate
			break
	if record.is_empty():
		log_line("   no volumetric room on this map")
		return
	var room: Node3D = facility.rooms.get_room(record)
	var with_cone := 0
	for light in room.lights:
		if light.get_meta("cone") if light.has_meta("cone") else null != null:
			with_cone += 1
	log_line("   %s: %d lights, %d with cones" % [str(record.name), room.lights.size(), with_cone])
	check("every light of the room has a cone", with_cone == room.lights.size() and with_cone > 0, "%d of %d" % [with_cone, room.lights.size()])
	var lamp: Light3D = room.lights[0]
	place_player(Vector3(lamp.global_position.x + 3.0, lamp.global_position.y - 1.0, lamp.global_position.z))
	await secs(1.5)
	face_point(lamp.global_position + Vector3(0.0, -0.5, 0.0))
	await secs(0.5)
	var cone: MeshInstance3D = lamp.get_meta("cone")
	log_line("   cone aabb %s scale %s visible %s" % [str(cone.mesh.get_aabb()), str(cone.scale), str(cone.visible)])
	await shot("cones")

# How long building gate A takes (it is built with the other rooms at load).
func _scn_gateload() -> void:
	log_line("== gate A build cost")
	facility.rooms.reset_gate_a()
	await get_tree().physics_frame
	for round in 2:
		var t0 := Time.get_ticks_usec()
		var room: Node3D = facility.rooms.get_room(facility.gatea_record)
		log_line("   round %d: %.1f ms" % [round, (Time.get_ticks_usec() - t0) / 1000.0])
		facility.rooms.reset_gate_a()
		await get_tree().physics_frame

# The checkpoint monitors' sizes with a lockdown running (the user saw huge red pictures cutting through areas).
func _scn_monprobe() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.events.sl.lever_on = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "checkpoint1":
			record = candidate
	if record.is_empty():
		log_line("no checkpoint1")
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(6.0, 0.0, 0.0))
	await secs(2.0)
	var room: Node3D = facility.rooms.get_room(record)
	await secs(0.5)
	for monitor in room.extras.monitors:
		var box: AABB = monitor.get_aabb()
		log_line("monitor local aabb %s scale %s at %s" % [box, monitor.scale, monitor.global_position])
		for s in monitor.mesh.get_surface_count():
			var arrays: Array = monitor.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for v in verts:
				lo = lo.min(v)
				hi = hi.max(v)
			log_line("  surface %d %s .. %s" % [s, lo, hi])
	var beside: bool = await _stand_before_point(room.extras.monitors[0].global_position)
	log_line("stood %s" % beside)
	await shot("monprobe")


# Lighting comparison: the cafeteria from a few spots, with the fog on.
func _scn_cafe() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2cafeteria":
			record = candidate
	if record.is_empty():
		log_line("no cafeteria")
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(6.0, 0.0, 0.0))
	await secs(2.0)
	var room: Node3D = facility.rooms.get_room(record)
	await secs(1.0)
	log_line("cafeteria at %s angle %s bounds %s" % [room.global_position, room.rotation.y, room.world_bounds()])
	var bounds: AABB = room.world_bounds()
	var spots := [Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.2), Vector3(0.2, 0.5, 0.5)]
	var index := 0
	for spot in spots:
		var at: Vector3 = bounds.position + bounds.size * spot
		var down := PhysicsRayQueryParameters3D.create(at + Vector3(0, 6, 0), at + Vector3(0, -20, 0))
		down.collision_mask = 1
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
		if hit.is_empty():
			continue
		place_player(hit.position + Vector3(0, 1.0, 0))
		player.rotation.y = PI * 0.5 * index
		await secs(1.5)
		log_line("spot %d light volume %.2f (measured %.2f) fog %.2f..%.2f" % [index, facility.light_fog.light_volume, facility.light_fog.measure(facility, player.global_position), 0.5 * facility.light_fog.light_volume, 6.0 * facility.light_fog.light_volume])
		await shot("cafe%d" % index)
		GameState.fog_of_war = false
		await secs(0.3)
		await shot("cafe%d_nofog" % index)
		GameState.fog_of_war = true
		index += 1

# A ceiling light seen from a few metres, to look at the glow (size, colour, square edges).
func _scn_glowview() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2cafeteria":
			record = candidate
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(6.0, 0.0, 0.0))
	await secs(2.0)
	var room: Node3D = facility.rooms.get_room(record)
	await secs(1.0)
	var light: Light3D = null
	for candidate in room.lights:
		light = candidate
		break
	if light == null:
		log_line("no light near")
		return
	var from: Vector3 = light.global_position + Vector3(3.0, -1.2, 0.0)
	place_player(from)
	await secs(0.5)
	var look: Vector3 = light.global_position - player.camera.global_position
	player.rotation.y = atan2(-look.x, -look.z)
	player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	player.user_pitch = -rad_to_deg(player.camera.rotation.x)
	await secs(1.0)
	log_line("light colour %s energy %s" % [light.light_color, light.light_energy])
	await shot("glowview")

# The cafeteria from above (orthographic, under the ceiling), to find a viewpoint; marks every light.
func _scn_cafetop() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2cafeteria":
			record = candidate
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(6.0, 0.0, 0.0))
	await secs(2.0)
	var room: Node3D = facility.rooms.get_room(record)
	await secs(1.0)
	GameState.fog_of_war = false
	for mat_owner in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mat_owner as MeshInstance3D
		for s in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var mat := mi.get_active_material(s)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.contains("lightmap"):
				(mat as ShaderMaterial).set_shader_parameter("fullbright", true)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.near = 0.05
	cam.far = 20.0
	get_tree().root.add_child(cam)
	cam.global_position = room.global_position + Vector3(0.0, 2.3, 0.0)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.current = true
	log_line("room at %s rot %.2f bounds %s" % [room.global_position, room.rotation.y, room.world_bounds()])
	for light in room.lights:
		log_line("light %s colour %s energy %.2f" % [room.to_local(light.global_position), light.light_color, light.light_energy])
	await secs(0.5)
	await shot("cafetop")
	cam.queue_free()
	GameState.fog_of_war = true

func _scn_nearstart() -> void:
	var start: Vector3 = facility.generator.start_room.position
	for candidate in facility.generator.rooms:
		var d: float = (candidate.position as Vector3).distance_to(start)
		if d < 20.0:
			log_line("room %s at %s dist %.1f angle %s" % [candidate.name, candidate.position, d, candidate.angle])

# The spawn point of the start room in eight directions (to line up with a screenshot of the original).
func _scn_spawnview() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var spot: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	if OS.get_environment("SCP_FOG_OFF") == "1":
		GameState.fog_of_war = false
	var extra := OS.get_environment("SCP_VIEW")
	var yaws := [0, 45, 90, 135, 180, 225, 270, 315]
	var pitch := 10.0
	if not extra.is_empty():
		var parts := extra.split(",")
		spot = facility.start_node.to_global(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		yaws = [float(parts[3])]
		if parts.size() > 5:
			yaws = []
			var step := float(parts[5])
			var a := 0.0
			while a < 360.0:
				yaws.append(a)
				a += step
		pitch = float(parts[4])
	for yaw in yaws:
		place_player(spot)
		player.rotation.y = deg_to_rad(float(yaw))
		player.camera.rotation.x = deg_to_rad(pitch)
		player.user_pitch = -pitch
		await secs(1.2)
		log_line("yaw %s at %s light volume %.2f" % [yaw, facility.start_node.to_local(player.global_position), facility.light_fog.light_volume])
		await shot("spawn_%s" % yaw)

# The start room from above (fullbright, orthographic), with a grid of room-local coordinates every 2 units.
func _scn_starttop() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var room: Node3D = facility.start_node
	await secs(1.0)
	GameState.fog_of_war = false
	for mat_owner in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mat_owner as MeshInstance3D
		for s in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var mat := mi.get_active_material(s)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.contains("lightmap"):
				(mat as ShaderMaterial).set_shader_parameter("fullbright", true)
	var height := float(OS.get_environment("SCP_TOP_Y")) if not OS.get_environment("SCP_TOP_Y").is_empty() else 2.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 18.0
	cam.near = 0.05
	cam.far = 30.0
	get_tree().root.add_child(cam)
	var centre: Vector3 = room.to_local(Vector3(69.375 + 12.06, 0.0, -147.125 + 7.56)) if false else Vector3(10.0, 0.0, -3.5)
	cam.global_position = room.to_global(centre + Vector3(0.0, height, 0.0))
	cam.rotation = Vector3(-PI * 0.5, room.rotation.y, 0.0)
	cam.current = true
	# grid posts every 2 units (red) and the spawn (green)
	for gx in range(-2, 24, 2):
		for gz in range(-14, 8, 2):
			var post := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.12, 0.05, 0.12)
			post.mesh = box
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1, 0, 0) if (gx % 4 == 0 and gz % 4 == 0) else Color(1, 0.6, 0)
			post.material_override = m
			room.add_child(post)
			post.position = Vector3(gx, height - 0.3, gz)
	log_line("start room at %s rot %.2f bounds %s" % [room.global_position, room.rotation.y, room.world_bounds()])
	await secs(0.5)
	await shot("starttop")
	cam.queue_free()
	GameState.fog_of_war = true

# Floor heights of the start room on a 1-unit grid (the highest floor under 4.5 units), as a text map.
func _scn_startfloors() -> void:
	var room: Node3D = facility.start_node
	await secs(1.0)
	var space := get_viewport().world_3d.direct_space_state
	for gz in range(-11, 5):
		var row := "z %3d: " % gz
		for gx in range(-3, 22):
			var top: Vector3 = room.to_global(Vector3(gx, 4.5, gz))
			var q := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -6, 0))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			row += ("  .  " if hit.is_empty() else "%5.1f" % room.to_local(hit.position).y)
		log_line(row)

# The lights the fog of war counts around the spawn (TempLightVolume's terms).
func _scn_lightsum() -> void:
	var at: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.6, -4.0))
	place_player(at)
	await secs(1.5)
	var total := 0.0
	var count := 0
	for key in facility.rooms.built:
		var room: Node = facility.rooms.built[key]
		if not is_instance_valid(room) or not "lights" in room:
			continue
		var in_room := 0
		for light in room.lights:
			var d: float = at.distance_to(light.global_position)
			var c: Color = light.light_color
			var i: float = (c.r + c.g + c.b) / 3.0 * light.light_energy
			if d < 15.0:
				total += i * i * (15.0 - d) / 15.0
				in_room += 1
				count += 1
		log_line("room %s: %d lights, %d within 15" % [room.room_name, room.lights.size(), in_room])
	log_line("lights %d sum %.2f TempLightVolume %.2f" % [count, total, maxf(total / 4.5, 1.0)])

# For every rmesh of the game: how many lit surfaces get the diffuse x2 (type 1), how many have a lightmap but another type.
func _scn_rmeshtypes() -> void:
	var MeshLoaderScript := load("res://scripts/io/mesh_loader.gd")
	var dir_path: String = ContentPaths.existing_file("GFX/map")
	var files: Array[String] = []
	for sub in ["", "dimension1499"]:
		var d := DirAccess.open(dir_path.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.to_lower().ends_with(".rmesh"):
				files.append(dir_path.path_join(sub).path_join(f))
	var total_x2 := 0
	var total_other := 0
	for path in files:
		var parsed: Dictionary = MeshLoaderScript.parse_rmesh(path)
		var x2 := 0
		var other := 0
		var plain := 0
		for s in parsed.get("surfaces", []):
			if str(s.light).is_empty():
				plain += 1
			elif bool(s.get("albedo_x2", false)):
				x2 += 1
			else:
				other += 1
		total_x2 += x2
		total_other += other
		if other > 0 or x2 == 0:
			log_line("%s: x2 %d, lightmap without x2 %d, no lightmap %d" % [path.get_file(), x2, other, plain])
	log_line("rmesh files %d, lit surfaces with x2 %d, without %d" % [files.size(), total_x2, total_other])

# Mean brightness of the views from the middle of ordinary light-containment rooms (four directions each), to compare
# with frames of the original.
func _scn_roomviews() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var names := ["room2", "room2_2", "room2_3", "room2_4", "room2_5", "room3", "room3_2", "room4", "room2closets", "room2doors", "endroom"]
	var done := {}
	var all_sum := 0.0
	var all_n := 0
	for record in facility.generator.rooms:
		var n := str(record.name)
		if not n in names or done.has(n):
			continue
		done[n] = true
		place_player(record.position + Vector3(0.0, 1.55, 0.0))
		await secs(1.5)
		var room: Node3D = facility.rooms.get_room(record)
		var at: Vector3 = room.global_position
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.2, 0), at + Vector3(0, -3, 0))
		q.collision_mask = 1
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var line := "%-14s" % n
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			place_player(hit.position + Vector3(0, 0.1, 0))
			player.rotation.y = deg_to_rad(yaw)
			player.camera.rotation.x = 0.0
			player.user_pitch = 0.0
			await secs(0.6)
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.resize(160, 90)
			var s := 0.0
			var c := 0
			for y in range(5, 76):
				for x in range(12, 148):
					var px := image.get_pixel(x, y)
					s += (0.299 * px.r + 0.587 * px.g + 0.114 * px.b) * 255.0
					c += 1
			line += " %5.1f" % (s / c)
			if n == "room2" and yaw == 90.0:
				log_line("room2 view from %s light volume %.2f fog %s" % [room.to_local(player.global_position), facility.light_fog.light_volume, GameState.fog_of_war])
				await shot("room2_view")
			all_sum += s / c
			all_n += 1
		log_line(line)
	log_line("mean %.1f over %d views" % [all_sum / maxf(all_n, 1), all_n])

# The nearest start-room light seen from the spawn (the original's video has the same view), for the glow's size.
func _scn_glowspawn() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	place_player(facility.start_node.to_global(Vector3(14.0, 1.6, -4.0)))
	await secs(1.5)
	var best: Light3D = null
	for light in facility.start_node.lights:
		if best == null or light.global_position.distance_to(player.camera.global_position) < best.global_position.distance_to(player.camera.global_position):
			best = light
	var look: Vector3 = best.global_position - player.camera.global_position
	player.rotation.y = atan2(-look.x, -look.z)
	player.camera.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	player.user_pitch = -rad_to_deg(player.camera.rotation.x)
	await secs(1.0)
	log_line("light at distance %.2f colour %s energy %.2f" % [look.length(), best.light_color, best.light_energy])
	await shot("glowspawn")

# A look at an SCP-049-2 in the lit start room: lying, standing up, walking, attacking.
func _scn_zombie049view() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	GameState.fog_of_war = false
	MeshLoader._ambient = 1.0
	var ahead: Vector3 = player.global_position + player.global_transform.basis * Vector3(0.0, 0.0, -2.2)
	var zombie: Node = facility.spawn_zombie049(ahead, 0)
	zombie.set_physics_process(false)
	zombie.rotation.y = player.rotation.y + PI
	await secs(0.5)
	for pose in [[719.0, "lying"], [682.0, "up"], [980.0, "walk"], [20.0, "attack"], [140.0, "dead"]]:
		zombie.set_frame(float(pose[0]))
		await secs(0.3)
		await shot("zombie049_%s" % pose[1])
	GameState.fog_of_war = true
	MeshLoader._ambient = -1.0

func _scn_roomprops() -> void:
	log_line("== roomprops: rmesh model entities are drawn, with the .x frame transform baked in")
	var lamp := MeshLoader.load_x(ContentPaths.assets_root.path_join("GFX/map/Props/lamp2.x"))
	check("lamp2.x is moved down by its frame (-96)", lamp.get_aabb().position.y < 1.0, str(lamp.get_aabb()))
	for record in facility.generator.rooms:
		if str(record.name) != "room2sl":
			continue
		var node: Node3D = facility.rooms.get_room(record)
		var meshes := 0
		for child in node.get_children():
			if child is MeshInstance3D and child != node.visual and child.mesh != null and child.mesh.get_surface_count() > 0:
				meshes += 1
		check("room2sl draws its prop models", meshes >= 10, "%d" % meshes)
		break

func _scn_soak() -> void:
	log_line("== soak: visit every room, let it run, look for broken state")
	var kinds := await _visit_room_kinds(func(kind: String, _node: Node3D) -> void:
		await secs(3.0)
		var position := player.global_position
		var sane := is_finite(position.x) and is_finite(position.y) and is_finite(position.z) and position.y > -40.0 and position.y < 40.0
		check("soak %s: player in bounds" % kind, sane, str(position))
		check("soak %s: player alive" % kind, not player.dead)
		for npc in get_tree().get_nodes_in_group("scp106") + get_tree().get_nodes_in_group("scp049") + get_tree().get_nodes_in_group("scp939") + get_tree().get_nodes_in_group("scp966") + get_tree().get_nodes_in_group("human_npc"):
			var at: Vector3 = npc.global_position
			check("soak %s: %s finite" % [kind, npc.name], is_finite(at.x) and is_finite(at.y) and is_finite(at.z)))
	log_line("soak visited %d room kinds" % kinds)

# Puts the player in the middle of the first room of each kind (god mode, 173 parked away) and awaits `per_room(kind, node)`
# there; a death is undone before the next room. Returns the number of kinds visited.
func _visit_room_kinds(per_room: Callable) -> int:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var visited := {}
	for record in facility.generator.rooms:
		var kind := str(record.name)
		if visited.has(kind) or facility.rooms.inside_start(record):
			continue
		visited[kind] = true
		var node: Node3D = facility.rooms.get_room(record)
		place_player(node.to_global(Vector3(0.0, node.floor_y(0.0, 0.0) + 0.1, 0.0)))
		await per_room.call(kind, node)
		if player.dead:
			await _reset_world()
	return visited.size()

func _scn_doormesh() -> void:
	log_line("== door mesh")
	var mesh: ArrayMesh = MeshLoader.load_x(ContentPaths.assets_root.path_join("GFX/map/Door01.x"))
	var verts := 0
	for s in mesh.get_surface_count():
		verts += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	check("Door01.x keeps the leaf body (a Frame named MeshNN is not a Mesh)", verts >= 812, "%d vertices" % verts)
	var size := mesh.get_aabb().size
	check("Door01.x leaf is wider than the logo plates", size.x > 3.0 and size.y > 5.0, str(size))

func _scn_proprotation() -> void:
	log_line("== proprotation: LoadRMesh's RotateEntity(pitch, yaw, roll) as the node's angles, with z flipped")
	var forward := Vector3(0.0, 0.0, -1.0)
	var yawed := Basis.from_euler(FacilityRoom.prop_rotation(Vector3(0.0, 90.0, 0.0))) * forward
	check("Blitz yaw 90 turns the nose to -x (a left turn)", yawed.distance_to(Vector3(-1.0, 0.0, 0.0)) < 0.001, str(yawed))
	var pitched := Basis.from_euler(FacilityRoom.prop_rotation(Vector3(90.0, 0.0, 0.0))) * forward
	check("Blitz pitch 90 points the nose down", pitched.distance_to(Vector3(0.0, -1.0, 0.0)) < 0.001, str(pitched))
	var rolled := Basis.from_euler(FacilityRoom.prop_rotation(Vector3(0.0, 0.0, 90.0))) * Vector3.RIGHT
	check("Blitz roll 90 lifts the right side", rolled.distance_to(Vector3(0.0, 1.0, 0.0)) < 0.001, str(rolled))
	var both := Basis.from_euler(FacilityRoom.prop_rotation(Vector3(-90.0, 90.0, 0.0))) * Vector3.UP
	check("Blitz turns by pitch first and yaw after: pitch -90, yaw 90 sends up to +x", both.distance_to(Vector3(1.0, 0.0, 0.0)) < 0.001, str(both))
	var record := _find_room("room205")
	check("the map has SCP-205's room", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	var data: Dictionary = MeshLoader.parse_rmesh_cached(facility.rooms.mesh_path(record))
	var wanted := 0
	for entity in data.entities:
		if str(entity.get("kind", "")) == "model" and str(entity.get("file", "")) == "205.x":
			wanted += 1
	var found := 0
	for child in room.get_children():
		var prop := child as MeshInstance3D
		if prop == null or prop == room.visual or prop.mesh == null:
			continue
		if prop.mesh.get_aabb().size.distance_to(Vector3(0.715649, 2.548871, 3.653992)) > 0.01:
			continue
		found += 1
		var nose := prop.transform.basis.orthonormalized() * Vector3(0.0, 0.0, 1.0)
		check("205.x (yaw 90) has its long side toward +x, into the chamber", nose.distance_to(Vector3(1.0, 0.0, 0.0)) < 0.001, str(nose))
	check("every 205.x prop of the rmesh is drawn", wanted == 2 and found == 2, "%d of %d" % [found, wanted])

func _scn_storagebuttons() -> void:
	log_line("== storagebuttons: FillRoom MoveEntity pushes the SCP-970 buttons out of the wall")
	var fill: Dictionary = RoomFill.for_room("room2storage")
	var pushed := 0
	for def in fill.doors:
		if def.has("button_push") and absf(float(def.button_push["0"].z) + 8.0) < 0.001:
			pushed += 1
	check("room2storage lists its six pushed doors", pushed == 6, "%d" % pushed)
	var record := _find_room("room2storage")
	check("the map has room2storage", not record.is_empty(), "")
	if record.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(record)
	for slot in 6:
		var door: Node3D = room.door_slots.get(slot)
		if door == null or door.buttons.size() < 2:
			check("door %d has two buttons" % slot, false, "")
			continue
		var a: Vector3 = door.buttons[0].position
		var b: Vector3 = door.buttons[1].position
		check("door %d buttons sit 0.13125 off the door plane" % slot, absf(a.z - 0.13125) < 0.0005 and absf(b.z + 0.13125) < 0.0005, "%s %s" % [str(a), str(b)])
	var exit := _find_room("exit1")
	if not exit.is_empty():
		var exit_room: Node3D = facility.rooms.get_room(exit)
		var lift_door: Node3D = exit_room.door_slots.get(0)
		check("exit1's lift door button moves 22 * RoomScale frame units along its own -z (a third of a millimetre)", lift_door != null and absf(lift_door.buttons[0].position.z - (0.1 - 22.0 * lift_door.ROOM_SCALE * lift_door.ROOM_SCALE)) < 0.00005, str(lift_door.buttons[0].position) if lift_door != null else "")

func _scn_booth914() -> void:
	log_line("== booth914: the two SCP-914 doors are d\\dir = 4 (openstate +1.4 a frame, one leaf)")
	var record := _find_room("914")
	check("the map has SCP-914", not record.is_empty(), "")
	if record.is_empty():
		return
	place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.5)
	var room: Node3D = facility.rooms.get_room(record)
	var standing: Vector3 = room.to_global(Vector3(0.0, 0.0, -0.8))
	standing.y = room.global_position.y + 1.55
	place_player(standing)
	await secs(0.5)
	for slot in 2:
		if not is_instance_valid(room):
			room = facility.rooms.get_room(record)
		var door: Node3D = room.door_slots.get(slot)
		check("914 door %d is a booth door with one leaf" % slot, door != null and door.booth and door.leaf_b == null, "")
		if door == null:
			continue
		door.open = true
		var frames := 0
		while is_instance_valid(door) and door.openstate < 180.0 and frames < 400:
			await get_tree().physics_frame
			frames += 1
		if not is_instance_valid(door):
			check("914 door %d is still there" % slot, false, "")
			continue
		door.open = false
		frames = 0
		while is_instance_valid(door) and door.openstate > 0.0 and frames < 400:
			await get_tree().physics_frame
			frames += 1
		if not is_instance_valid(door):
			check("914 door %d is still there" % slot, false, "")
			continue
		var scale := get_physics_process_delta_time() * 70.0
		check("914 door %d closes in about 129 frames" % slot, absf(frames * scale - 129.0) <= 2.0, "%.1f frames" % (frames * scale))
		var rest: Vector3 = door.leaf_a.position
		door.open = true
		frames = 0
		while door.openstate < 180.0 and frames < 400:
			await get_tree().physics_frame
			frames += 1
		check("914 door %d opens in about 129 frames" % slot, absf(frames * scale - 129.0) <= 2.0, "%.1f frames" % (frames * scale))
		var travel: float = door.leaf_a.position.distance_to(rest)
		var expected: float = door._travel(1.4, 114.0)
		check("914 door %d leaf travels the sum of Sin(openstate) / 114" % slot, absf(travel - expected) < 0.02, "%.3f vs %.3f" % [travel, expected])

# Frame spikes during play: every room kind's first visit (the frames while the player arrives and stays 3 s), then the cost of
# a model or a sound read for the first time. Headless has no GPU, so shader compilation hitches do not show here.
const HITCH_MS := 25.0

func _scn_hitchhunt() -> void:
	log_line("== hitchhunt: frames over %.0f ms during play" % HITCH_MS)
	var logger := HitchLogger.new()
	add_child(logger)
	logger.enabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	var busy := Time.get_ticks_usec()
	while Time.get_ticks_usec() - busy < 60000:
		pass
	await get_tree().process_frame
	var logged := FileAccess.get_file_as_string(HitchLogger.LOG_PATH)
	check("the hitch logger writes a 60 ms frame with its room", logged.contains(" ms  ") and not logged.contains("(no player)"), logged.strip_edges())
	logger.queue_free()
	var spikes: Array = []
	var kinds := await _visit_room_kinds(func(kind: String, _node: Node3D) -> void:
		var elapsed := 0.0
		for ms: float in (await _measure_frames(210))[6]:
			elapsed += ms
			if ms > HITCH_MS:
				spikes.append([ms, kind, elapsed / 1000.0]))
	log_line("   %d room kinds" % kinds)
	_log_slowest(spikes, 30, "room %.1f ms  %s at %.2f s")
	var loads: Array = []
	for dir in ["GFX/npcs", "GFX", "GFX/map"]:
		for file in DirAccess.get_files_at(ContentPaths.assets_root.path_join(dir)):
			var path := ContentPaths.existing_file(dir.path_join(file))
			if not file.to_lower().ends_with(".b3d") or B3DModel._cache.has(path):
				continue
			var t := Time.get_ticks_usec()
			var model := B3DModel.new()
			model.load_file(path)
			model.free()
			loads.append([(Time.get_ticks_usec() - t) / 1000.0, dir.path_join(file)])
	log_line("   models not read by B3DModel at load (map props use MeshLoader and are built with their rooms):")
	_log_slowest(loads, loads.size(), "model %.1f ms  %s")
	var sounds: Array = []
	_collect_oggs("SFX", sounds)
	var timed: Array = []
	for relative in sounds:
		if Sfx._streams.has(relative):
			continue
		var t := Time.get_ticks_usec()
		Sfx.stream(relative)
		timed.append([(Time.get_ticks_usec() - t) / 1000.0, relative])
	log_line("   sounds not read yet, slowest:")
	_log_slowest(timed, 15, "sound %.1f ms  %s")

func _log_slowest(entries: Array, limit: int, line_format: String) -> void:
	entries.sort_custom(func(a, b): return a[0] > b[0])
	log_line("   %d entries" % entries.size())
	for entry in entries.slice(0, limit):
		log_line("   " + line_format % entry)

func _collect_oggs(relative: String, out: Array) -> void:
	var root := ContentPaths.assets_root.path_join(relative)
	for file in DirAccess.get_files_at(root):
		if file.to_lower().ends_with(".ogg"):
			out.append(relative.path_join(file))
	for dir in DirAccess.get_directories_at(root):
		_collect_oggs(relative.path_join(dir), out)
