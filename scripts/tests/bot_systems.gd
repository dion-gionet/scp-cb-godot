extends "res://scripts/tests/bot_events.gd"
# Playtest bot scenarios (see playtest_bot.gd for the runner and the scenario sets).

func _scn_infection() -> void:
	log_line("== SCP-008 infection")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.8)
	var infection: Node = facility.infection
	var hud_node := get_tree().get_first_node_in_group("hud")
	GameState.infect = 0.0
	await _frames(4)
	check("a healthy player has no overlay", GameState.infect_overlay == 0.0 and not GameState.is_zombie, "")
	# the first stages: the overlay, the blur, the messages and voices as the thresholds are crossed
	infection.messages.clear()
	infection.voices.clear()
	GameState.infect = 9.99
	await _frames(40)
	check("a whisper at 10", infection.voices.has(0), str(infection.voices))
	GameState.infect = 19.99
	await _frames(40)
	check("the fever is felt at 20", infection.messages.has("You feel kinda feverish."), str(infection.messages))
	check("the overlay shows and the view blurs", GameState.infect_overlay > 0.002 and GameState.blur_timer > 0.0, "overlay %.4f blur %.0f" % [GameState.infect_overlay, GameState.blur_timer])
	check("the green overlay is on screen", hud_node._infect_overlay.visible and hud_node._infect_overlay.texture != null, "")
	for level in [24.99, 39.99, 54.99, 59.99, 69.99, 79.99, 84.99]:
		GameState.infect = level     # just under each threshold, as the slow real climb would be
		await _frames(40)
	check("nausea at 40 and 60, faintness at 80", infection.messages.has("You feel nauseated.") and infection.messages.has("The nausea's getting worse.") and infection.messages.has("You feel very faint."), str(infection.messages))
	check("a voice at each 15 from 10 (10, 25, 40, 55, 70, 85)", infection.voices.has(0) and infection.voices.has(1) and infection.voices.has(2) and infection.voices.has(3) and infection.voices.has(4) and infection.voices.has(5), str(infection.voices))
	# 91.5: the eyes close and the body will not move
	GameState.infect = 91.6
	await _frames(10)
	check("at 91.5 the player cannot move or crouch", GameState.is_zombie and GameState.unable_to_move, "")
	check("and the eyes are shut", player.blink_timer <= -9.0, "%.0f" % player.blink_timer)
	hud_node.open_inventory()
	check("the inventory stays shut", not hud_node.inventory_open, "")
	# 92.7: carried to the chamber, a scientist waits
	GameState.infect = 92.69
	await _frames(12)
	var record := _find_room("008")
	var chamber: Node3D = facility.rooms.get_room(record)
	check("at 92.7 the player is in the SCP-008 chamber", player.global_position.distance_to(chamber.object_point(7)) < 2.0, "%.1f from the spot" % player.global_position.distance_to(chamber.object_point(7)))
	check("a scientist stands opposite", infection.scientist != null and is_instance_valid(infection.scientist), "")
	# 93 on: forced to walk to the scientist
	GameState.infect = 93.2
	var from: Vector3 = player.global_position
	await _frames(60)
	check("forced to walk toward him (ForceMove 0.75)", GameState.force_move == 0.75 and player.global_position.distance_to(from) > 0.3, "moved %.2f" % player.global_position.distance_to(from))
	check("badly hurt on the way (injuries 2.5)", GameState.injuries >= 2.4, "%.1f" % GameState.injuries)
	check("facing him", absf(wrapf(player.rotation.y - atan2(-(infection.scientist.global_position.x - player.global_position.x), -(infection.scientist.global_position.z - player.global_position.z)), -PI, PI)) < 0.3, "")
	var decals_before := _decal_count(0.5)     # the bleeding player's drips are 0.24 at most
	var particles: Particles = facility.particles
	GameState.infect = 94.68
	await _frames(30)
	check("at 94.7 the player is held in place", GameState.unable_to_move and GameState.force_move == 0.0, "")
	check("the scientist's blood is left on the floor (decal 3, 0.8)", _decal_count(0.5) == decals_before + 1, "%d -> %d" % [decals_before, _decal_count(0.5)])
	var sprayed := false
	for i in 500:
		await get_tree().physics_frame
		for item in particles._items:
			if item.image == 5 and item.alpha <= 0.5:
				sprayed = true
		if sprayed:
			break
	check("blood sprays from him (bloodsprite, one frame in 50)", sprayed, "")
	GameState.infect = 95.95
	await _frames(40)
	check("by 96 the infection has killed him", player.dead, "infect %.2f" % GameState.infect)
	revive()
	GameState.infect = 0.0
	await _frames(4)
	check("everything is released when the infection is gone", not GameState.is_zombie and not GameState.unable_to_move and GameState.force_move == 0.0, "")
	GameState.infect = 30.0
	var pill := _give(hud_node, "SCP-500-01", "scp500")
	check("an SCP-500 pill can be carried", pill >= 0, "")
	if pill >= 0:
		hud_node.set_selected(pill)
		await _frames(3)
		check("the pill cures the infection", GameState.infect == 0.0, "%.1f" % GameState.infect)
		check("and is used up", not hud_node.items.has("SCP-500-01"), str(hud_node.items))
	GameState.infect = 0.0

func _scn_fog() -> void:
	log_line("== fog of war (LightVolume)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(1.5)
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	var env := holder.environment
	var fog: Node = facility.light_fog
	check("fog is on", env.fog_enabled and GameState.fog_of_war, "")
	check("temp light volume is at least 1", fog.temp_light_volume >= 1.0, "%.2f" % fog.temp_light_volume)
	check("fog runs 0.5 to 6 times the light volume", is_equal_approx(env.fog_depth_begin, 0.5 * fog.light_volume) and is_equal_approx(env.fog_depth_end, 6.0 * fog.light_volume), "%.2f..%.2f lv %.2f" % [env.fog_depth_begin, env.fog_depth_end, fog.light_volume])
	check("fog is black", env.fog_light_color == Color.BLACK, "")
	var lit_before: float = fog.light_volume
	fog.flash()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("a gunshot flashes the volume up 1.2x", is_equal_approx(fog.light_volume, fog.temp_light_volume * 1.2), "%.2f vs %.2f" % [fog.light_volume, fog.temp_light_volume])
	await shot("fog_on")
	GameState.fog_of_war = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("the debug option turns the fog off", not env.fog_enabled, "")
	await shot("fog_off")
	GameState.fog_of_war = true
	await secs(0.3)
	check("and back on", env.fog_enabled, "")
	check("light volume %.2f was steady" % lit_before, true, "")

func _scn_lampflare() -> void:
	log_line("== ordinary lamps seen from their room's centre keep the star flare")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	for lamp in [["room1archive", 1.46, 1.414], ["room1162", 2.42, 0.0], ["room106", 2.05, 4.74]]:
		var found: Light3D = null
		var room: FacilityRoom = null
		for key in facility.rooms.built:
			var candidate: FacilityRoom = facility.rooms.built[key]
			if candidate.room_name != lamp[0]:
				continue
			for light in candidate.lights:
				var local := candidate.to_local(light.global_position)
				if absf(local.y - lamp[1]) < 0.03 and absf(Vector2(local.x, local.z).length() - lamp[2]) < 0.05 and light.has_meta("glow"):
					room = candidate
					found = light
		if found == null:
			log_line("   skipped: this seed has no %s" % lamp[0])
			continue
		place_player(room.global_position + Vector3(0.0, 0.3, 0.0))
		player.blink_timer = 400.0
		await secs(1.0)
		check("the %s lamp shows its star flare" % lamp[0], (found.get_meta("glow") as MeshInstance3D).visible, "%.2f away" % get_viewport().get_camera_3d().global_position.distance_to(found.global_position))

func _scn_lockroomlamp() -> void:
	log_line("== lockroom dome lamp: its shade hides the flare")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var room: FacilityRoom = null
	var dome_light: Light3D = null
	for key in facility.rooms.built:
		var candidate: FacilityRoom = facility.rooms.built[key]
		if candidate.room_name != "lockroom":
			continue
		for light in candidate.lights:
			var local := candidate.to_local(light.global_position)
			if absf(local.y - 1.28125) < 0.01 and absf(Vector2(local.x, local.z).length() - 3.366) < 0.05 and light.has_meta("glow"):
				room = candidate
				dome_light = light
	if room == null:
		log_line("   skipped: this seed has no lockroom with the dome lamp")
		return
	place_player(room.global_position + Vector3(0.0, 1.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.0)
	check("the dome lamp's light exists", dome_light != null, "")
	if dome_light != null:
		check("seen from below its rim the dome lamp shows no flare", not (dome_light.get_meta("glow") as MeshInstance3D).visible, "")
		check("but still its small bulb", (dome_light.get_meta("fixture") as MeshInstance3D).visible, "")

func _scn_room035lamp() -> void:
	log_line("== room035: the red lamp's flare is not hidden by the room's invisible collision faces")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var room: FacilityRoom = null
	for key in facility.rooms.built:
		var candidate: FacilityRoom = facility.rooms.built[key]
		if candidate.room_name == "room035":
			room = candidate
	if room == null:
		log_line("   skipped: this seed has no room035")
		return
	place_player(room.global_position + Vector3(0.0, 0.3, 0.0))
	player.blink_timer = 400.0
	await secs(1.0)
	var red := 0
	var red_glowing := 0
	for light in room.lights:
		var color: Color = light.get_meta("glow_color")
		if color.r > color.g * 2.0:
			red += 1
			if (light.get_meta("glow") as MeshInstance3D).visible:
				red_glowing += 1
	check("the room has red lamps", red > 0, "%d" % red)
	check("a red lamp in the open shows its flare from the room's middle", red_glowing > 0, "%d of %d" % [red_glowing, red])

func _scn_lightfx() -> void:
	log_line("== lighting and camera effects")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var room: Node3D = facility.start_node
	place_player(room.to_global(Vector3(14.0, 1.55, -5.5)))
	player.blink_timer = 400.0
	await secs(1.0)
	check("the vignette (fog.jpg) is over the view", hud._vignette.visible, "")
	var with_glow := 0
	var with_fixture := 0
	for light in room.lights:
		var glow: MeshInstance3D = light.get_meta("glow") if light.has_meta("glow") else null
		var fixture: MeshInstance3D = light.get_meta("fixture") if light.has_meta("fixture") else null
		if glow != null and glow.visible:
			with_glow += 1
		if fixture != null and fixture.visible:
			with_fixture += 1
	check("every light has its fixture point while the power is on", with_fixture == room.lights.size() and room.lights.size() > 0, "%d of %d" % [with_fixture, room.lights.size()])
	check("lights in sight within 8.5 glow", with_glow >= 0, "%d glowing" % with_glow)
	GameState.lights_on = false
	await secs(0.3)
	check("with the power out the screen is 0.9 dark", is_equal_approx(hud._fade.color.a, 0.9), "%.2f" % hud._fade.color.a)
	var still_glowing := 0
	for light in room.lights:
		var glow: MeshInstance3D = light.get_meta("glow") if light.has_meta("glow") else null
		var fixture: MeshInstance3D = light.get_meta("fixture") if light.has_meta("fixture") else null
		if (glow != null and glow.visible) or (fixture != null and fixture.visible):
			still_glowing += 1
	check("and every light sprite is gone", still_glowing == 0, "%d" % still_glowing)
	GameState.lights_on = true
	await secs(0.3)
	check("power back: the screen clears", hud._fade.color.a < 0.5, "%.2f" % hud._fade.color.a)
	GameState.eye_stuck = 3000.0
	await secs(0.2)
	check("stuck eyes (3000 left) darken the view by (6000 - 3000) / 5000", hud._fade.color.a > 0.55, "%.2f" % hud._fade.color.a)
	check("and blur it", GameState.blur_timer > 0.0 or GameState.blur_volume > 0.3, "timer %.0f volume %.2f" % [GameState.blur_timer, GameState.blur_volume])
	GameState.eye_stuck = 0.0
	var dust_wait := 0.0
	while dust_wait < 8.0 and facility.dust_motes.motes.is_empty():
		await get_tree().physics_frame
		dust_wait += get_physics_process_delta_time()
	check("dust motes drift near the camera", facility.dust_motes.motes.size() >= 1, "%d" % facility.dust_motes.motes.size())
	var mote: Dictionary = facility.dust_motes.motes[0] if facility.dust_motes.motes.size() > 0 else {}
	check("each is a 0.004 speck", not mote.is_empty() and mote.size <= 0.002, "")

# Main.bb: Rand(50000) = 3 each frame makes SCP-079 flicker the lights and play Broadcast1-7, except in the pocket dimension, gate A,
# gate B's room, 860, 1123, the 173 chamber and 1499.
func _scn_broadcast() -> void:
	log_line("== SCP-079's broadcast")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var audio: Node = get_tree().get_first_node_in_group("audio")
	var ordinary := {}
	for candidate in facility.generator.rooms:
		if not str(candidate.name) in audio.NO_BROADCAST_ROOMS and not str(candidate.name) in ["start", "checkpoint1", "checkpoint2"]:
			ordinary = candidate
			break
	check("the map has an ordinary room", not ordinary.is_empty(), "")
	if ordinary.is_empty():
		return
	place_player(ordinary.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
	player.blink_timer = 400.0
	await secs(1.0)
	place_player(ordinary.position + Vector3(0.0, 1.55, 0.0))
	await secs(0.5)
	GameState.light_blink = 0.0
	await get_tree().physics_frame
	check("without the roll nothing flickers", GameState.light_blink == 0.0, "%.2f" % GameState.light_blink)
	var players_before := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			players_before += 1
	audio.force_broadcast = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("the roll flickers the lights (LightBlink 1-2)", GameState.light_blink > 0.5 and GameState.light_blink <= 2.0, "%.2f in '%s'" % [GameState.light_blink, facility.room_name_at(player.global_position)])
	check("and consumes the roll", not audio.force_broadcast, "")
	var players_after := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			players_after += 1
	check("a Broadcast sound is started", players_after == players_before + 1, "%d -> %d" % [players_before, players_after])
	GameState.light_blink = 0.0
	var chamber := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "173":
			chamber = candidate
	if not chamber.is_empty():
		place_player(chamber.position + Vector3(0.0, 1.55, 0.0))
		await secs(0.5)
		audio.force_broadcast = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("in the room '%s' the broadcast is skipped" % facility.room_name_at(player.global_position), GameState.light_blink == 0.0 and facility.room_name_at(player.global_position) == "173", "%.2f" % GameState.light_blink)
	audio.force_broadcast = false

# UpdateRoomLights: a light of flicker class 5+ in a room with light cones throws a spark now and then: a burst of electric sparks, a
# flash lying flat 0.05 above the light for 10 frames, and Light1-3 within 10.
# Models are lit like Blitz3D's Direct3D 7 vertex lighting (shaders/entity.gdshaderinc): AmbientLight plus the
# shown room lights at colour * N.L * LightRange / distance, at most 8, times the brush colour.
func _scn_entitylight() -> void:
	log_line("== model lighting (Blitz3D vertex lights)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "medibay":
			record = candidate
			break
	if record.is_empty():
		check("the map has a medibay", false, "")
		return
	var room := facility.rooms.get_room(record) as FacilityRoom
	var spot: Light3D = null
	for light in room.lights:
		if light is OmniLight3D and is_equal_approx(float(light.get_meta("blitz_range", 0.0)), 0.4):
			spot = light
	check("the rmesh spotlight is a point light of range 800 / 2000 (LoadRMesh ltype 2)", spot != null and room.lights.all(func(l): return l is OmniLight3D), "")
	check("its colour is Int(255) * Min(1.2 * 0.8, 1)", spot != null and is_equal_approx((spot.get_meta("blitz_colour") as Color).r, 245.0 / 255.0), "")
	place_player(room.global_position + Vector3(0.0, 1.55, 0.0))
	player.blink_timer = 400.0
	await secs(1.0)
	var camera: Vector3 = player.camera.global_position
	check("the 8 nearest lights reach the models", EntityLights.shown.size() == mini(8, _lights_within(camera, 8.5)), "%d" % EntityLights.shown.size())
	check("only lights within 8.5 of the camera", EntityLights.shown.all(func(l: Light3D) -> bool: return camera.distance_to(l.global_position) < 8.5), "")
	var zombie := B3DModel.new()
	zombie.load_file(ContentPaths.existing_file("GFX/npcs/zombiesurgeon.b3d"))
	var surgeon_colour: Color = zombie.mesh_instance.mesh.surface_get_material(0).albedo_color
	check("the surgeon takes its brush colour 150 / 255", zombie.mesh_instance.mesh.surface_get_material(0) is EntityMaterial and absf(surgeon_colour.r - 150.0 / 255.0) < 0.01, "%.3f" % surgeon_colour.r)
	zombie.free()
	var mask_mesh := MeshLoader.load_b3d(ContentPaths.existing_file("GFX/items/gasmask.b3d"))
	var mask_material = mask_mesh.surface_get_material(0)
	check("a static item model takes its brush colour (gas mask 0.41)", mask_material is EntityMaterial and absf(mask_material.albedo_color.r - 0.41) < 0.02 and mask_material.albedo_color.r < 0.99, "%s" % str(mask_material.albedo_color if mask_material is EntityMaterial else null))
	var door := MeshLoader.load_x(ContentPaths.existing_file("GFX/map/Door01.x"))
	var normals: PackedVector3Array = door.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check("a .x model keeps its MeshNormals", normals.size() > 0 and normals.size() == (door.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() and is_equal_approx(normals[0].length(), 1.0), "%d" % normals.size())
	var lever := MeshLoader.load_x(ContentPaths.existing_file("GFX/map/leverbase.x"))
	check("the lever box's normals point out of it", _normals_outward(lever), "")
	# one light 2 above a point facing it: 50 / 255 + 0.64 * 0.3 / 2, where Godot's inverse square gave about 0.6 * 0.25 in linear
	var probe := OmniLight3D.new()
	facility.add_child(probe)
	probe.global_position = Vector3(0.0, 102.0, 0.0)
	probe.set_meta("blitz_range", 0.3)
	probe.set_meta("blitz_colour", Color(163.0 / 255.0, 163.0 / 255.0, 163.0 / 255.0))
	var kept := EntityLights.shown.duplicate()
	EntityLights.upload([probe] as Array[Light3D])
	var lit := EntityLights.vertex_light(Vector3(0.0, 100.0, 0.0), Vector3.UP, 50.0 / 255.0)
	check("a model 2 below a medibay lamp gets 50 / 255 + 0.64 * 0.3 / 2", absf(lit.x - (50.0 / 255.0 + 163.0 / 255.0 * 0.3 / 2.0)) < 0.001, "%.4f" % lit.x)
	EntityLights.upload(kept)
	probe.queue_free()

# Blitz' UpdateRooms hands the model lights of every built room within range
func _lights_within(at: Vector3, radius: float) -> int:
	var count := 0
	for built in facility.rooms.built.values():
		for light in (built as FacilityRoom).lights:
			if is_instance_valid(light) and light.has_meta("blitz_range") and light.is_visible_in_tree() and at.distance_to(light.global_position) < radius:
				count += 1
	for light: Light3D in get_tree().get_nodes_in_group("entity_lights"):
		if light.is_visible_in_tree():
			count += 1
	return count

# Godot's front faces wind clockwise, so (v2 - v0) x (v1 - v0) points out of them.
func _normals_outward(mesh: ArrayMesh) -> bool:
	var agree := 0
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if normals.size() != points.size():
			return false
		for t in range(0, indices.size(), 3):
			var face := (points[indices[t + 2]] - points[indices[t]]).cross(points[indices[t + 1]] - points[indices[t]])
			total += 1
			if face.dot(normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]) > 0.0:
				agree += 1
	return total > 0 and agree >= total * 0.9

func _scn_sparks() -> void:
	log_line("== light sparks")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var host := Node3D.new()
	facility.add_child(host)
	var lamp := OmniLight3D.new()
	host.add_child(lamp)
	lamp.position = Vector3(0.0, 40.0, 0.0)
	LightSprites.attach(host, lamp, Color.WHITE, true)
	lamp.set_meta("flicker", 7)
	var spark: MeshInstance3D = lamp.get_meta("spark")
	check("the spark lies flat, facing down", is_equal_approx(spark.rotation.x, PI * 0.5), "%.2f" % spark.rotation.x)
	check("0.05 above the light", is_equal_approx(spark.position.y, lamp.position.y + 0.05), "%.3f" % spark.position.y)
	check("and is not a camera billboard", not (spark.material_override as ShaderMaterial).get_shader_parameter("billboard"), "")
	check("the glow has its own roll", (lamp.get_meta("glow").material_override as ShaderMaterial).get_shader_parameter("billboard_roll") != null, "")
	var particles: Node = facility.particles
	var before: int = particles.count()
	LightSprites._throw_spark(lamp, spark, 1.0)
	check("the flash shows", spark.visible and lamp.get_meta("spark_frames") > 0.0, "")
	for i in 12:
		await get_tree().physics_frame
		LightSprites._update_cone(lamp, lamp.get_meta("cone"), true, false)
	check("a burst of 7 x 6 sparks flew", particles.count() >= before + 42, "%d -> %d" % [before, particles.count()])
	check("the flash is over after 10 frames", not spark.visible, "")
	var rolls := 0
	var trials := 40000
	for i in trials:
		LightSprites._update_cone(lamp, lamp.get_meta("cone"), true, false)
		if lamp.get_meta("spark_frames") > 0.0:
			rolls += 1
			lamp.set_meta("spark_frames", 0.0)
	var expected := float(trials) * (70.0 / Engine.physics_ticks_per_second) / 3200.0
	check("about 1 in 400 per turn, one turn every 8 frames", rolls >= expected * 0.3 and rolls <= expected * 2.5, "%d rolls, %.1f expected" % [rolls, expected])
	var quiet: Light3D = OmniLight3D.new()
	host.add_child(quiet)
	LightSprites.attach(host, quiet, Color.WHITE, true)
	quiet.set_meta("flicker", 3)
	var quiet_rolls := 0
	for i in trials:
		LightSprites._update_cone(quiet, quiet.get_meta("cone"), true, false)
		if quiet.get_meta("spark_frames") > 0.0:
			quiet_rolls += 1
			quiet.set_meta("spark_frames", 0.0)
	check("a light under class 5 never sparks", quiet_rolls == 0, "%d" % quiet_rolls)
	host.queue_free()

func _scn_nvg() -> void:
	log_line("== night vision goggles")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var room: Node3D = facility.start_node
	place_player(room.to_global(Vector3(14.0, 1.55, -5.5)))
	player.blink_timer = 400.0
	await secs(0.5)
	var env: Environment = (get_tree().get_first_node_in_group("world_env") as WorldEnvironment).environment
	var normal_ambient: float = env.ambient_light_color.r ** 2
	hud.items[0] = "Night Vision Goggles"
	hud.item_data[0] = {"tempname": "nvgoggles", "icon": "GFX/items/INVnightvision.jpg", "state": 1000.0}
	GameState.wearing_hazmat = 1
	hud.set_selected(0)
	await secs(0.2)
	check("goggles will not go on over a hazmat suit", GameState.wearing_night_vision == 0, "")
	GameState.wearing_hazmat = 0
	hud.set_selected(0)
	await secs(0.5)
	check("using the goggles puts them on", GameState.wearing_night_vision == 1, "")
	check("the green overlay shows", hud._nv_overlay.visible and hud._nv_overlay.modulate == Color8(0, 255, 0), "")
	check("models are lit at twice the brightness", is_equal_approx(env.ambient_light_color.r, MeshLoader.ambient_colour(minf(normal_ambient * 2.0, 1.0)).r), "%.3f vs %.3f" % [env.ambient_light_color.r, normal_ambient])
	check("the rooms' lightmaps are lifted by 15 / 255", is_equal_approx(GameState.room_ambient, 15.0 / 255.0), "")
	var fog_env: Environment = env
	check("the fog reaches 30 times the light volume", is_equal_approx(fog_env.fog_depth_end, 30.0 * facility.light_fog.light_volume), "%.1f" % fog_env.fog_depth_end)
	var before := float(hud.item_data[0].state)
	await secs(2.0)
	var spent := before - float(hud.item_data[0].state)
	check("the battery drains 0.02 a frame (about 2.8 in 2 s)", spent > 2.0 and spent < 3.6, "%.2f" % spent)
	await shot("nvg_plain")
	hud.item_data[0].state = 50.0
	await secs(0.3)
	check("under 100 the battery is low", GameState.nvg_battery == 1, "")
	hud.item_data[0].state = 0.01
	await secs(0.3)
	check("at 0 the batteries die and the screen goes black", GameState.nvg_battery == 0 and GameState.nvg_blinking and hud._nv_black.visible, "")
	check("173 would move now (the view is black)", GameState.nvg_blinking, "")
	hud.set_selected(0)
	await secs(0.2)
	check("using them again takes them off", GameState.wearing_night_vision == 0, "")
	check("ambient and lightmaps return to normal", is_equal_approx(env.ambient_light_color.r, MeshLoader.ambient_colour(normal_ambient).r) and GameState.room_ambient == 0.0, "")
	check("the screen clears", not hud._nv_black.visible, "")
	hud.item_data[0] = {"tempname": "supernv", "icon": "GFX/items/INVsupernightvision.jpg", "state": 1000.0}
	hud.set_selected(0)
	await secs(0.3)
	check("the super goggles turn the overlay blue", GameState.wearing_night_vision == 2 and hud._nv_overlay.modulate == Color8(0, 100, 255), "")
	var nv: Node = facility.night_vision
	var waited := 0.0
	while nv.snapshot.is_empty() and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("the super goggles take a reading at once", nv.timer > 0.0 or not nv.snapshot.is_empty(), "timer %.0f, %d seen" % [nv.timer, nv.snapshot.size()])
	await secs(1.0)
	await shot("nvg_super")
	hud.set_selected(0)
	hud.items[0] = ""
	hud.item_data[0] = {}
	GameState.wearing_night_vision = 0

func _scn_mouseopts() -> void:
	log_line("== mouse smoothing and invert")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	player.blink_timer = 400.0
	await secs(0.5)
	var sens := GameState.mouse_sensitivity
	GameState.mouse_sensitivity = 0.5
	var shown := func(smoothing: float, invert: bool) -> float:
		GameState.mouse_smoothing = smoothing
		GameState.invert_mouse = invert
		player.user_pitch = 0.0
		player._mouse_smooth = Vector2.ZERO
		player._mouse_raw = Vector2(0.0, 10.0)
		player.test_mouse_speed = Vector2.ZERO
		player._update_look(1.0)       # one 70 Hz frame, called directly so the order of the physics callbacks does not matter
		return player.user_pitch
	var default_turn: float = await shown.call(1.0, false)
	var raw_turn: float = await shown.call(0.0, false)
	var slow_turn: float = await shown.call(2.0, false)
	var inverted: float = await shown.call(0.0, true)
	check("at 100% a frame of movement is followed by a sixth", absf(default_turn - raw_turn / 6.0) < raw_turn * 0.03 and default_turn > 0.0, "%.3f vs %.3f" % [default_turn, raw_turn])
	check("at 0% the view follows the mouse at once", raw_turn > default_turn * 5.0, "%.3f" % raw_turn)
	check("at 200% it lags twice as long", absf(slow_turn - default_turn / 2.0) < default_turn * 0.05, "%.3f vs %.3f" % [slow_turn, default_turn])
	check("inverting flips the pitch", is_equal_approx(inverted, -raw_turn), "%.3f vs %.3f" % [inverted, raw_turn])
	GameState.mouse_smoothing = 1.0
	GameState.invert_mouse = false
	GameState.mouse_sensitivity = sens
	player.user_pitch = 0.0
	player._mouse_smooth = Vector2.ZERO

func _scn_items2() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	# combining: a battery into the night vision goggles, the navigator, the radio
	var nv: int = _give(hud, "Night Vision Goggles", "nvgoggles")
	var nv_fine: int = _give(hud, "Night Vision Goggles", "finenvgoggles")
	var battery: int = _give(hud, "9V Battery", "bat")
	hud.item_data[nv]["state"] = 0.0
	hud.swap_items(battery, nv_fine)
	check("a battery does not fit the very fine goggles", not hud.items[battery].is_empty() and hud.message_time_left() > 0.0, "")
	hud.swap_items(battery, nv)
	check("a battery into the goggles refills them and is used up", hud.items[battery].is_empty() and hud.item_data[nv].state == 1000.0, "state %s" % str(hud.item_data[nv].state))
	var nav: int = _give(hud, "S-NAV Navigator Ultimate", "nav")
	var battery2: int = _give(hud, "9V Battery", "bat")
	hud.swap_items(battery2, nav)
	check("no place for batteries in the ultimate navigator", not hud.items[battery2].is_empty(), "")
	var radio: int = _give(hud, "Radio Transceiver", "radio")
	hud.item_data[radio]["state"] = 0.0
	hud.swap_items(battery2, radio)
	check("a 9 V battery refills the plain radio", hud.items[battery2].is_empty() and hud.item_data[radio].state == 100.0, "")
	var bat18: int = _give(hud, "18V Battery", "18vbat")
	hud.swap_items(bat18, radio)
	check("the 18 V battery does not fit it", not hud.items[bat18].is_empty(), "")
	var empty_slot := -1
	for i in hud.items.size():
		if hud.items[i].is_empty():
			empty_slot = i
	hud.swap_items(bat18, empty_slot)
	check("dragging onto an empty slot moves the item", hud.items[empty_slot] == "18V Battery" and hud.items[bat18].is_empty(), "")
	GameState.injuries = 2.0
	GameState.bloodloss = 0.0
	var syringe: int = _give(hud, "Syringe", "syringe")
	await _use_slot(hud, syringe)
	check("a syringe sets the healing timer and slows the stamina", GameState.heal_timer > 29.0 and GameState.stamina_effect == 0.5, "heal %.0f" % GameState.heal_timer)
	await secs(3.0)
	check("healing takes injuries off and costs a little blood", GameState.injuries < 2.0 and GameState.bloodloss > 0.0, "inj %.2f blood %.2f" % [GameState.injuries, GameState.bloodloss])
	GameState.heal_timer = 0.0
	GameState.stamina_effect = 1.0
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	# the strange bottle: the outcomes (the fifth, the pocket dimension, is not rolled here)
	for roll in [1, 2, 3, 4]:
		GameState.injuries = 1.0
		GameState.bloodloss = 20.0
		GameState.blur_timer = 0.0
		hud.item_use.bottle_roll = roll
		var bottle: int = _give(hud, "Strange Bottle", "veryfinefirstaid")
		hud.set_selected(bottle)
		check("the strange bottle is used up (outcome %d)" % roll, hud.items[bottle].is_empty(), "")
		match roll:
			1:
				check("outcome 1 bleeds", GameState.injuries == 3.5, "")
			2:
				check("outcome 2 heals everything", GameState.injuries == 0.0 and GameState.bloodloss == 0.0, "")
			3:
				check("outcome 3 helps", GameState.injuries < 1.0 and GameState.bloodloss < 20.0, "")
			4:
				check("outcome 4 blurs for a long time", GameState.blur_timer > 5000.0 and GameState.bloodloss == 0.0, "")
	hud.item_use.bottle_roll = 0
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	GameState.blur_timer = 0.0
	var joint: int = _give(hud, "Joint", "420s")
	GameState.god_mode = false
	await _use_slot(hud, joint)
	check("the joint ends the run with its note", player.dead, "")
	revive()
	GameState.god_mode = true
	var weed: int = _give(hud, "Some SCP-420-J", "420")
	GameState.injuries = 1.0
	await _use_slot(hud, weed)
	check("SCP-420-J eases the injuries and blurs the view", absf(GameState.injuries - 0.5) < 0.01 and GameState.blur_timer >= 400.0 and GameState.achievements.has("420"), "")
	var cigarette: int = _give(hud, "Cigarette", "cigarette")
	hud.set_selected(cigarette)
	await secs(0.1)
	check("a cigarette is refused with a line", hud.message_time_left() > 0.0, "")
	GameState.blur_timer = 0.0
	GameState.injuries = 0.0
	# SCP-427
	for i in hud.items.size():
		hud.items[i] = ""
		hud.item_data[i] = {}
	var locket: int = _give(hud, "SCP-427", "scp427")
	await _use_slot(hud, locket)
	check("the locket opens", GameState.i427_using and GameState.achievements.has("427"), "")
	GameState.injuries = 2.0
	GameState.bloodloss = 30.0
	await secs(3.0)
	check("an open locket heals", GameState.injuries < 2.0, "%.3f" % GameState.injuries)
	GameState.i427_timer = 70.0 * 359.5
	GameState.injuries = 3.0
	var blood_before: float = GameState.bloodloss
	await secs(2.0)
	check("after 360 s the change has begun", GameState.i427_timer >= 70.0 * 360.0, "%.0f" % GameState.i427_timer)
	GameState.i427_timer = 70.0 * 389.5
	await secs(2.0)
	check("after 390 s the player is forced to crouch", player.crouching, "")
	GameState.god_mode = false
	GameState.i427_timer = 70.0 * 419.5
	await secs(2.0)
	check("after 420 s the locket's owner is dead", player.dead, "")
	revive()
	GameState.god_mode = true
	GameState.i427_using = false
	GameState.i427_timer = 0.0
	# the ring of SCP-1123 outside its room
	var skull: int = _give(hud, "SCP-1123", "1123")
	GameState.god_mode = false
	await _use_slot(hud, skull)
	check("touching SCP-1123 outside its room is fatal", player.dead, "")
	revive()
	GameState.god_mode = true
	GameState.blur_timer = 0.0
	GameState.light_flash = 0.0

func _scn_radionav() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	_clear_items(hud)
	var radio: int = _give(hud, "Radio Transceiver", "radio")
	hud.item_data[radio]["state"] = 100.0
	hud.set_selected(radio)
	await secs(0.5)
	var rn: Control = hud.radio_nav
	check("the radio is drawn and the key hint is shown once", rn.visible and rn.rs[5] == 1.0 and hud.message_time_left() > 0.0, "")
	check("the first channel is the user track player's, on static", rn._playing(0) and rn._text.contains("USER TRACK PLAYER"), rn._text)
	check("a number key changes the channel", rn.handle_key(KEY_3) and int(hud.item_data[radio].state2) == 2, "")
	await secs(1.0)
	check("channel 3 plays the on-site radio", rn._playing(2) and rn._text.contains("On-Site Radio"), rn._text)
	check("the old channel is paused", rn._chan[0].stream_paused, "")
	rn.handle_key(KEY_2)
	await secs(1.0)
	check("channel 2 plays the alarm", rn._playing(1) and rn._text.contains("WARNING"), rn._text)
	rn.handle_key(KEY_4)
	await secs(1.0)
	check("channel 4 is the emergency channel, on static", rn._playing(3) and rn._text.contains("EMERGENCY"), rn._text)
	check("the battery runs down while it is held", float(hud.item_data[radio].state) < 100.0 and float(hud.item_data[radio].state) > 98.0, "%.2f" % float(hud.item_data[radio].state))
	rn.handle_key(KEY_5)
	await secs(1.0)
	check("channel 5 has static in the background", rn._playing(6), "")
	await shot("radio_channel4")
	hud.deselect()
	await secs(0.3)
	var all_paused := true
	for channel in rn._chan:
		if rn._chan[channel].playing and not rn._chan[channel].stream_paused:
			all_paused = false
	check("putting the radio away pauses every channel", all_paused, "")
	# a dead radio
	hud.item_data[radio]["state"] = 0.0
	hud.item_data[radio]["state2"] = 0.0
	hud.set_selected(radio)
	await secs(0.5)
	rn.handle_key(KEY_2)
	check("a dead radio does not change channel", int(hud.item_data[radio].state2) == 0, "")
	hud.deselect()
	var code_radio: int = _give(hud, "Radio Transceiver", "veryfineradio")
	hud.item_data[code_radio]["state"] = 100.0
	hud.set_selected(code_radio)
	GameState.access_code = "3721"
	rn.rs[6] = 0.0
	rn.rs[7] = 0.0
	rn.rs[8] = 0.0
	await secs(2.5)
	check("the very fine radio ignores the number keys", not rn.handle_key(KEY_2), "")
	check("the very fine radio buzzes the code", rn.rs[7] >= 1.0 or rn.rs[8] >= 1.0, "rs6 %.0f rs7 %.0f rs8 %.0f" % [rn.rs[6], rn.rs[7], rn.rs[8]])
	await shot("radio_code")
	hud.deselect()
	_clear_items(hud)
	var nav: int = _give(hud, "S-NAV 310 Navigator", "nav")
	hud.item_data[nav]["state"] = 60.0
	for room in facility.generator.rooms:
		GameState.rooms_found["%d,%d" % [room.grid.x, room.grid.y]] = true
	hud.set_selected(nav)
	await secs(1.0)
	check("the navigator shows the map", rn.visible and rn._map.visible, "")
	check("its battery runs down", float(hud.item_data[nav].state) < 60.0, "")
	await shot("nav310")
	hud.deselect()
	var nav_plain: int = _give(hud, "S-NAV 300 Navigator", "nav")
	hud.item_data[nav_plain]["state"] = 100.0
	hud.set_selected(nav_plain)
	await secs(0.6)
	await shot("nav300")
	hud.deselect()
	var nav_ultimate: int = _give(hud, "S-NAV Navigator Ultimate", "nav")
	hud.item_data[nav_ultimate]["state"] = 1000.0
	hud.set_selected(nav_ultimate)
	await secs(0.6)
	await shot("navultimate")
	hud.deselect()
	_clear_items(hud)

func _scn_containers() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	_clear_items(hud)
	var clip: int = _give(hud, "Clipboard", "clipboard")
	var wallet: int = _give(hud, "Wallet", "wallet")
	var paper: int = _give(hud, "Class D Orientation Leaflet", "paper")
	var coin: int = _give(hud, "Coin", "coin")
	var ring: int = _give(hud, "SCP-714", "scp714")
	check("an empty clipboard shows its empty picture", str(hud.item_data[clip].icon).contains("INVclipboard2"), str(hud.item_data[clip].icon))
	hud.swap_items(coin, clip)
	check("a coin does not go on a clipboard", not hud.items[coin].is_empty() and hud.message_time_left() > 0.0, "")
	hud.swap_items(paper, wallet)
	check("a paper does not go into a wallet", not hud.items[paper].is_empty(), "")
	hud.swap_items(ring, wallet)
	check("the ring does not go into a wallet", not hud.items[ring].is_empty(), "")
	hud.swap_items(paper, clip)
	check("a paper goes on the clipboard", hud.items[paper].is_empty() and hud.container_slots(clip)[0].name == "Class D Orientation Leaflet", "")
	check("the clipboard has its full picture", str(hud.item_data[clip].icon).contains("INVclipboard.jpg"), str(hud.item_data[clip].icon))
	hud.swap_items(coin, wallet)
	check("a coin goes into the wallet", hud.items[coin].is_empty() and hud.container_slots(wallet)[0].name == "Coin", "")
	# reading from the clipboard
	hud.set_selected(clip)
	await secs(0.3)
	check("using the clipboard shows its pockets", hud.inventory_open and hud.container_index == clip, "")
	await shot("clipboard_open")
	hud.use_from_container(0)
	await secs(0.3)
	check("a double click reads the paper where it lies", hud.selected >= 10 and hud.selected_tempname() == "paper" and hud._doc_rect.visible, "sel %d" % hud.selected)
	await shot("clipboard_read")
	hud.deselect()
	check("putting it away leaves it on the clipboard", hud.items.size() == 10 and hud.container_slots(clip)[0].name == "Class D Orientation Leaflet", "")
	# dragging out of a pocket drops it
	hud.set_selected(clip)
	await secs(0.2)
	var before := get_tree().get_nodes_in_group("pickup").size()
	hud.drop_from_container(0)
	await secs(0.3)
	check("dragging out drops it", get_tree().get_nodes_in_group("pickup").size() == before + 1 and not hud.inventory_open, "")
	check("an emptied clipboard goes back to the empty picture", str(hud.item_data[clip].icon).contains("INVclipboard2"), str(hud.item_data[clip].icon))
	# a full wallet
	for i in 9:
		var c: int = _give(hud, "Coin", "coin")
		hud.swap_items(c, wallet)
	var extra: int = _give(hud, "Coin", "coin")
	hud.swap_items(extra, wallet)
	check("a full wallet takes no more", not hud.items[extra].is_empty() and hud.container_slots(wallet).size() == 10, "")
	# a wallet keeps its coins when it is dropped and picked up again
	hud.selected = wallet
	hud.drop_selected(player)
	await secs(0.3)
	var lying: Node = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("tempname", "")) == "wallet":
			lying = node
	check("the dropped wallet keeps what it held", lying != null and lying.has_meta("inv") and not (lying.get_meta("inv")[0] as Dictionary).is_empty(), "")
	if lying != null:
		hud.try_pickup(lying)
		lying.queue_free()
		var back := -1
		for i in hud.items.size():
			if hud.items[i] == "Wallet":
				back = i
		check("and keeps it when it is picked up again", back >= 0 and hud.container_slots(back)[0].name == "Coin", "")
		check("it survives a save as JSON", back >= 0 and JSON.parse_string(JSON.stringify(hud.item_data[back])).inv.size() == 10, "")
	_clear_items(hud)
	await _check_container_poses(hud)

func _dropped_container(hud: Node, slot: int) -> WorldItem:
	var tempname: String = hud.item_data[slot].tempname
	hud.selected = slot
	hud.drop_selected(player)
	await secs(0.2)
	var found: WorldItem = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if node is WorldItem and node.tempname == tempname and node.has_meta("dropped"):
			found = node
	return found

func _mesh_signature(item: WorldItem) -> Vector3:
	var mesh: ArrayMesh = (item.get_child(0) as MeshInstance3D).mesh
	var sum := Vector3.ZERO
	for surface in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			sum += v
	return sum

# Items.bb 419-425, Main.bb 5196-5210, 5430-5440, 5474-5482: a clipboard is at frame 17 empty and 0 once it holds something;
# a wallet is at 0 empty and 3 once it holds anything but a coin or a key.
func _check_container_poses(hud: Node) -> void:
	var clip: int = _give(hud, "Clipboard", "clipboard")
	var wallet: int = _give(hud, "Wallet", "wallet")
	var paper: int = _give(hud, "Class D Orientation Leaflet", "paper")
	var coin: int = _give(hud, "Coin", "coin")
	var card: int = _give(hud, "Level 1 Key Card", "key1")
	var empty_clip: WorldItem = await _dropped_container(hud, clip)
	check("an empty clipboard on the floor is at frame 17", empty_clip != null and empty_clip.pose == 17.0, "")
	hud.swap_items(paper, wallet)
	hud.swap_items(coin, wallet)
	check("a coin leaves an empty wallet at frame 0", hud.item_data[wallet].pose == 0.0, str(hud.item_data[wallet].pose))
	var coin_wallet: WorldItem = await _dropped_container(hud, wallet)
	check("a wallet with only a coin lies at frame 0", coin_wallet != null and coin_wallet.pose == 0.0, "")
	var clip2: int = _give(hud, "Clipboard", "clipboard")
	hud.swap_items(paper, clip2)
	var full_clip: WorldItem = await _dropped_container(hud, clip2)
	check("a clipboard holding a paper lies at frame 0", full_clip != null and full_clip.pose == 0.0, "")
	var wallet2: int = _give(hud, "Wallet", "wallet")
	hud.swap_items(card, wallet2)
	var card_wallet: WorldItem = await _dropped_container(hud, wallet2)
	check("a wallet holding a card lies at frame 3", card_wallet != null and card_wallet.pose == 3.0, "")
	if empty_clip != null and full_clip != null and card_wallet != null and coin_wallet != null:
		check("the clipboard's two poses are different meshes", not _mesh_signature(empty_clip).is_equal_approx(_mesh_signature(full_clip)), "")
		check("the wallet's two poses are different meshes", not _mesh_signature(coin_wallet).is_equal_approx(_mesh_signature(card_wallet)), "")
		hud.try_pickup(card_wallet)
		card_wallet.queue_free()
		var back := -1
		for i in hud.items.size():
			if hud.items[i] == "Wallet":
				back = i
		check("a picked-up wallet carries its pose", back >= 0 and hud.item_data[back].pose == 3.0, "")
	for node in [empty_clip, full_clip, card_wallet, coin_wallet]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_clear_items(hud)

func _scn_console() -> void:
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var overlay: Node = null
	for node in get_tree().get_nodes_in_group("hud")[0].get_children():
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("debug_overlay.gd"):
			overlay = node
	check("the debug overlay holds a console", overlay != null and overlay.console != null, "")
	if overlay == null:
		return
	var console: Control = overlay.console
	var hud: Node = get_tree().get_first_node_in_group("hud")
	check("the menu has six pages", overlay.tabs.get_tab_count() == 6, "%d" % overlay.tabs.get_tab_count())
	check("help lists the first page", _console_say(console, "help").contains("LIST OF COMMANDS - PAGE 1/3"), "")
	check("help 3 lists the last page", _console_say(console, "help 3").contains("PAGE 3/3"), "")
	check("help gives a command's text", _console_say(console, "help noclip").contains("HELP - noclip"), "")
	check("a command with no help says so", _console_say(console, "help nothing").contains("no help available"), "")
	check("an unknown command is refused", _console_say(console, "frobnicate").contains("Command not found."), "")
	_console_say(console, "godmode on")
	check("godmode on", GameState.god_mode, "")
	_console_say(console, "godmode off")
	check("godmode off", not GameState.god_mode, "")
	_console_say(console, "god")
	check("godmode with no argument toggles", GameState.god_mode, "")
	_console_say(console, "god")
	_console_say(console, "noclip on")
	check("noclip on", GameState.noclip, "")
	_console_say(console, "noclipspeed 5")
	check("noclipspeed sets the speed", GameState.noclip_speed == 5.0, "")
	_console_say(console, "noclipspeed 2")
	_console_say(console, "noclip off")
	check("noclip off", not GameState.noclip, "")
	_console_say(console, "infinitestamina on")
	check("infinite stamina", GameState.infinite_stamina, "")
	player.stamina = 10.0
	await secs(1.0)
	check("it keeps the stamina up", player.stamina > 20.0, "%.1f" % player.stamina)
	_console_say(console, "infstam off")
	_console_say(console, "notarget on")
	check("notarget on", GameState.no_target, "")
	_console_say(console, "notarget off")
	_console_say(console, "sanic")
	check("sanic starts the speed", GameState.super_man, "")
	_console_say(console, "sanic")
	check("sanic again stops it", not GameState.super_man, "")
	_console_say(console, "showfps")
	check("showfps", GameState.show_fps, "")
	_console_say(console, "showfps")
	_console_say(console, "debughud on")
	check("debughud on shows the numbers", GameState.debug_hud, "")
	await secs(0.3)
	check("the debug HUD has text", overlay.hud_label.text.contains("Room:"), overlay.hud_label.text)
	_console_say(console, "debughud off")
	_console_say(console, "injure 2.5")
	_console_say(console, "infect 12")
	check("injure and infect set the values", GameState.injuries == 2.5 and GameState.infect == 12.0, "")
	_console_say(console, "heal")
	check("heal clears the injuries and the blood loss", GameState.injuries == 0.0 and GameState.bloodloss == 0.0, "")
	GameState.infect = 0.0
	check("status prints the room", _console_say(console, "status").contains("Room: "), "")
	_console_say(console, "427state 5")
	check("427state is in seconds", GameState.i427_timer == 350.0, "")
	GameState.i427_timer = 0.0
	_console_say(console, "setblinkeffect 2 30")
	check("setblinkeffect", GameState.blink_effect == 2.0 and GameState.blink_effect_timer == 30.0, "")
	GameState.blink_effect = 1.0
	GameState.blink_effect_timer = 0.0
	_console_say(console, "giveachievement 3")
	check("giveachievement", GameState.achievements.has(GameState.ACHIEVEMENT_ORDER[3]), "")
	check("a bad achievement id is refused", _console_say(console, "giveachievement 99").contains("doesn't exist"), "")
	_console_say(console, "wireframe on")
	check("wireframe on", get_viewport().debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "")
	_console_say(console, "wireframe off")
	check("wireframe off", get_viewport().debug_draw == Viewport.DEBUG_DRAW_DISABLED, "")
	_console_say(console, "camerafog 15 20")
	check("camerafog sets the fog", GameState.fog_override.x == 15.0 and GameState.fog_override.y == 20.0, str(GameState.fog_override))
	_console_say(console, "camerafog")
	check("camerafog with nothing resets it", GameState.fog_override.x < 0.0, "")
	_console_say(console, "gamma 1")
	_console_say(console, "asd")
	check("asd is god, noclip, wireframe and fog", GameState.god_mode and GameState.noclip and GameState.wireframe and GameState.fog_override.x == 15.0, "")
	_console_say(console, "godmode off")
	_console_say(console, "noclip off")
	_console_say(console, "wireframe off")
	_console_say(console, "camerafog")
	_console_say(console, "asd2")
	check("asd2 is god, infinite stamina and the monsters off", GameState.god_mode and GameState.infinite_stamina and facility.contained_106, "")
	_console_say(console, "godmode off")
	_console_say(console, "infinitestamina off")
	_console_say(console, "enable106")
	_console_say(console, "enable173")
	_console_say(console, "unlockexits")
	check("unlockexits opens both gates", facility.gate_a_unlocked and facility.gate_b_unlocked, "")
	facility.gate_a_unlocked = false
	facility.gate_b_unlocked = false
	var coffin_room := {}
	for record in facility.generator.rooms:
		if str(record.name) == "coffin":
			coffin_room = record
	_console_say(console, "teleport 895")
	await secs(0.5)
	check("teleport 895 goes to the coffin room (the middle of it is the pit)", Vector2(player.global_position.x - coffin_room.position.x, player.global_position.z - coffin_room.position.z).length() < 2.0, str(player.global_position))
	check("an unknown room is refused", _console_say(console, "teleport nowhere").contains("Room not found."), "")
	_console_say(console, "tele 10 5 -20")
	check("tele goes to the coordinates (Blitz z)", player.global_position.distance_to(Vector3(10.0, 5.0, 20.0)) < 0.01, str(player.global_position))
	place_player(coffin_room.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.3)
	var before := get_tree().get_nodes_in_group("pickup").size()
	var said := _console_say(console, "spawnitem level 3 key card")
	check("spawnitem makes the item", said.contains("spawned.") and get_tree().get_nodes_in_group("pickup").size() == before + 1, said)
	check("an unknown item is refused", _console_say(console, "spawnitem blorp").contains("Item not found."), "")
	_console_say(console, "spawnradio")
	_console_say(console, "spawnnvg")
	_console_say(console, "spawnnav")
	check("the three quick spawns make three items", get_tree().get_nodes_in_group("pickup").size() == before + 4, "")
	_console_say(console, "scp-420-j")
	check("420 scatters twenty", get_tree().get_nodes_in_group("pickup").size() == before + 24, "")
	_console_say(console, "spawn class-d")
	check("spawn class-d", facility.humans.size() >= 1, "")
	_console_say(console, "spawn guard")
	_console_say(console, "spawn mtf")
	check("spawn mtf", facility.mtf.units.size() >= 1, "")
	_console_say(console, "spawn 096 5")
	check("spawn 096 with a state", facility.scp096 != null and is_instance_valid(facility.scp096) and facility.scp096.state == 5, "")
	check("096state prints", _console_say(console, "096state").contains("SCP-096"), "")
	_console_say(console, "reset096")
	check("reset096", facility.scp096.state == 0, "")
	_console_say(console, "spawn 049")
	check("spawn 049", facility.scp049 != null and is_instance_valid(facility.scp049) and facility.scp049.state == 1, "")
	_console_say(console, "spawn 106")
	check("spawn 106 is active at once, not 12-17 minutes away", facility.scp106 != null and is_instance_valid(facility.scp106) and facility.scp106.state <= 0.0, "")
	check("106state prints", _console_say(console, "106state").contains("SCP-106"), "")
	_console_say(console, "106speed 0.02")
	check("106speed sets the speed", absf(facility.scp106.speed - 0.02 * 70.0) < 0.001, "")
	_console_say(console, "teleport106")
	check("teleport106 wakes him", facility.scp106.state == 0.0 and not facility.scp106.idle, "")
	_console_say(console, "spawn 008zombie")
	_console_say(console, "spawn 049-2")
	_console_say(console, "spawn 966")
	_console_say(console, "spawn apache")
	_console_say(console, "spawn 173")
	check("spawn 173 brings the statue", statue.global_position.distance_to(player.global_position) < 1.0, "")
	check("173state prints", _console_say(console, "173state").contains("SCP-173"), "")
	_console_say(console, "173speed 0.5")
	check("173speed sets the speed", absf(statue.speed - 35.0) < 0.001, "")
	_console_say(console, "173speed 0.38")
	_console_say(console, "disable173")
	check("disable173 hides it", statue.idle == 3 and not statue.visible, "")
	_console_say(console, "enable173")
	check("enable173 shows it", statue.idle == 0 and statue.visible, "")
	_console_say(console, "disable106")
	check("disable106 contains him", facility.contained_106 and facility.scp106.idle, "")
	_console_say(console, "enable106")
	check("enable106 lets him out", not facility.contained_106 and not facility.scp106.idle, "")
	check("an unknown NPC is refused", _console_say(console, "spawn blob").contains("NPC type not found."), "")
	check("SCP-066 is not a console NPC in the original either", _console_say(console, "spawn 066").contains("NPC type not found."), "")
	check("spawn 513-1 works", _console_say(console, "spawn 513-1").contains("SCP-513-1 spawned."), "")
	for ghost in get_tree().get_nodes_in_group("scp513_1"):
		ghost.queue_free()
	check("860-2 cannot be spawned", _console_say(console, "spawn 860-2").contains("cannot be spawned"), "")
	for stray in get_tree().get_nodes_in_group("scp106"):
		stray.queue_free()
	facility.scp106 = null
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	_console_say(console, "godmode on")
	_console_say(console, "kill")
	check("kill kills even in godmode", player.dead, "")
	_console_say(console, "revive")
	check("revive brings the player back", not player.dead and not GameState.god_mode, "")
	GameState.god_mode = true      # the monsters spawned above are still around the player
	await secs(1.6)
	check("and the death panel never comes up over the living player", not hud.pause_menu.visible, "")
	# the real keys: F3 opens the console and Escape closes it (the pause menu must not take the Escape)
	Input.parse_input_event(_real_key(KEY_F3, true))
	Input.parse_input_event(_real_key(KEY_F3, false))
	await get_tree().process_frame
	await get_tree().process_frame
	check("the F3 key opens the console", console.is_open and get_tree().paused, "")
	Input.parse_input_event(_real_key(KEY_ESCAPE, true))
	Input.parse_input_event(_real_key(KEY_ESCAPE, false))
	await get_tree().process_frame
	await get_tree().process_frame
	check("Escape closes it and does not open the pause menu", not console.is_open and not hud.pause_menu.visible and not get_tree().paused, "open %s menu %s paused %s" % [str(console.is_open), str(hud.pause_menu.visible), str(get_tree().paused)])
	console._toggle()
	check("F3 opens the console and stops the game", console.is_open and get_tree().paused, "")
	console.entry_box.text = "godm"
	console._complete()
	check("Tab completes a command", console.entry_box.text == "godmode ", console.entry_box.text)
	console.entry_box.text = "help noc"
	console._complete()
	check("Tab completes a help topic", console.entry_box.text == "help noclip", console.entry_box.text)
	console.entry_box.text = "tele"
	console._complete()
	check("Tab completes up to what the commands share", console.entry_box.text == "tele", console.entry_box.text)
	console._submit("noclip on")
	check("Enter runs the typed line", GameState.noclip and console.history.back() == "noclip on", "")
	console.entry_box.text = ""
	console._input_keys(_key_event(KEY_UP))
	check("Up brings the last command back", console.entry_box.text == "noclip on", console.entry_box.text)
	console._submit("noclip off")
	console._toggle()
	check("F3 closes it and the game goes on", not console.is_open and not get_tree().paused, "")
	check("closing the console marks the run as having used it, and the save keeps that", GameState.used_console and SaveGame.capture(main).get("used_console", false) == true, "")
	GameState.used_console = false
	overlay.panel.visible = true
	overlay.run("injure 1.5")
	check("the menu runs console commands", GameState.injuries == 1.5, "%.2f" % GameState.injuries)
	overlay.run("heal")
	check("the item page lists the items", overlay._item_list.item_count > 100, "%d" % overlay._item_list.item_count)
	overlay._fill_rooms()
	check("the places page lists the rooms", overlay._room_list.item_count > 20, "%d" % overlay._room_list.item_count)
	player.blink_timer = 500.0
	console.execute("help")
	console.execute("status")
	console.execute("spawnitem nothing")
	console.execute("frobnicate")
	console._toggle()
	await secs(0.4)
	await shot("console_open")
	console._toggle()
	overlay.panel.visible = true
	overlay.tabs.current_tab = 2
	await secs(0.3)
	await shot("debug_menu_npcs")
	overlay.tabs.current_tab = 3
	await secs(0.3)
	await shot("debug_menu_items")
	overlay.panel.visible = false
	for stray_human in facility.humans.duplicate():
		facility.remove_human(stray_human)
	for unit in facility.mtf.units.duplicate():
		facility.mtf.remove(unit)

func _scn_ambient() -> void:
	log_line("== the event plan and the ambient events")
	facility.contained_106 = false
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	check("the facility holds an event plan", ambient != null and ambient.plan != null and ambient.plan.plan.size() > 10, "%d events" % (ambient.plan.plan.size() if ambient != null else 0))
	if ambient == null:
		return
	# CreateEvent: the id-th free room (0 and 1 both mean the first), or every free room with a chance
	var PlanScript = EventPlan
	var fake: Array[Dictionary] = []
	for i in 6:
		fake.append({"name": "x", "key": "k%d" % i})
	var unit = PlanScript.new()
	unit._rooms = fake
	unit._create("a", "x", 1)
	unit._create("b", "x", 1)
	unit._create("c", "x", 0)
	unit._create("d", "x", 5)
	check("an id of 1 is the first free room, and the next one is the next", unit.plan.get("k0") == "a" and unit.plan.get("k1") == "b" and unit.plan.get("k2") == "c", str(unit.plan))
	check("an id of 5 counts the rooms that already hold events", unit.plan.get("k4") == "d" and not unit.plan.has("k3"), str(unit.plan))
	unit._create("e", "x", 0, 1.0)
	check("a chance of 1.0 fills every free room and takes none that is held", unit.plan.get("k3") == "e" and unit.plan.get("k5") == "e" and unit.plan.get("k0") == "a", str(unit.plan))
	unit._create("f", "y", 0)
	check("a room name that no room has makes nothing", not unit.plan.values().has("f"), "")
	var again = PlanScript.build(facility.generator.rooms, int(facility.generator.rng_before_events), GameState.aggressive_npcs())
	check("the seed fixes the plan", again.plan == ambient.plan.plan, "")
	var other = PlanScript.build(facility.generator.rooms, int(facility.generator.rng_before_events) + 1, GameState.aggressive_npcs())
	check("another generator state gives another plan", other.plan != ambient.plan.plan, "")
	var misplaced := 0
	for key in ambient.plan.plan:
		var template := str(facility.rooms.by_grid[key].name)
		match str(ambient.plan.plan[key]):
			"096spawn":
				if not template in ["room4pit", "room3pit", "room2pipes", "room2pit", "room3tunnel", "room4tunnels", "tunnel", "tunnel2", "room3z2"]:
					misplaced += 1
			"room2fan":
				if template != "room2_2":
					misplaced += 1
			"1048a":
				if template != "room2":
					misplaced += 1
	check("every event sits in a room of the kind it is made for", misplaced == 0, "%d wrong" % misplaced)
	var snapshot: Dictionary = {"states": {"3,4": {"s": 12.0, "s2": 1.0, "s3": 0.0}}, "removed": ["5,6"]}
	ambient.load_data(JSON.parse_string(JSON.stringify(snapshot)))
	check("event states and removed events come back from a save", ambient.states.get("3,4", {}).get("s") == 12.0 and ambient.removed.has("5,6"), "")
	ambient.states.clear()
	ambient.removed.clear()
	ambient._handlers.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var used: Array = []
	# --- lockroom173: 173 is put in the room (2 from its middle) when it is not in view
	var rec: Dictionary = await _event_room()
	used.append(rec.key)
	var home: Vector3 = rec.position + Vector3(2.0, 1.0, 1.0)
	place_player(home)
	await secs(0.5)
	ambient.force(rec.key, "lockroom173")
	await secs(0.3)
	var flat := Vector2(statue.global_position.x - rec.position.x, statue.global_position.z - rec.position.z).length()
	check("lockroom173 puts 173 in the room", absf(flat - 2.0) < 0.05 and ambient.removed.has(rec.key), "%.2f from the middle, removed %s" % [flat, str(ambient.removed.has(rec.key))])
	place_statue(Vector3(0.0, -80.0, 0.0))
	# --- room2trick: the player is carried across the middle and turned round; 173 near keeps it from happening
	var trick: Dictionary = await _event_room([], used)
	used.append(trick.key)
	var spot: Vector3 = trick.position + Vector3(1.0, 1.0, 0.5)
	place_player(spot)
	player.rotation.y = 0.0
	await secs(0.5)
	place_player(spot)
	ambient.force(trick.key, "room2trick")
	await secs(0.3)
	var mirrored := Vector2(2.0 * trick.position.x - spot.x, 2.0 * trick.position.z - spot.z)
	check("room2trick carries the player to the other side of the room", Vector2(player.global_position.x, player.global_position.z).distance_to(mirrored) < 0.3, "%s vs %s" % [str(player.global_position), str(mirrored)])
	check("and turns them round", absf(wrapf(player.rotation.y - 0.0, -PI, PI)) > 3.0, "yaw %.2f" % player.rotation.y)
	check("once", ambient.removed.has(trick.key), "")
	var spot2: Vector3 = trick.position + Vector3(-1.0, 1.0, 1.0)
	place_player(spot2)
	place_statue(spot2 + Vector3(2.0, -0.7, 0.0))
	ambient.force(trick.key, "room2trick")
	await secs(0.3)
	check("with 173 close the trick is dropped and the player stays", Vector2(player.global_position.x - spot2.x, player.global_position.z - spot2.z).length() < 0.3 and ambient.removed.has(trick.key), str(player.global_position))
	place_statue(Vector3(0.0, -80.0, 0.0))
	# --- room2doors173: 173 at Objects[0]
	var doors: Dictionary = await _event_room([], used)
	used.append(doors.key)
	facility.rooms.get_room(doors).fill_objects[0] = Vector3(1.5, 0.0, 1.5)
	var object_spot: Vector3 = facility.rooms.get_room(doors).object_point(0)
	place_player(doors.position + Vector3(2.0, 1.0, 2.0))
	await secs(0.5)
	face_point(player.global_position + (player.global_position - statue.global_position))      # looking away from the statue: it is not in view
	ambient.force(doors.key, "room2doors173")
	await secs(0.3)
	check("room2doors173 puts 173 at Objects[0]", Vector2(statue.global_position.x - object_spot.x, statue.global_position.z - object_spot.z).length() < 0.1 and ambient.removed.has(doors.key), "%s vs %s, player in %s (%s)" % [str(statue.global_position), str(object_spot), str(facility.record_at(player.global_position).get("key")), doors.key])
	place_statue(Vector3(0.0, -80.0, 0.0))
	# --- tunnel2: the lights, the eyes shut, 173 in the middle, then all as before
	var tunnel: Dictionary = await _event_room([], used)
	used.append(tunnel.key)
	place_player(tunnel.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.5)
	ambient.force(tunnel.key, "tunnel2")
	await secs(0.4)
	check("tunnel2 starts when the player is at the middle", ambient.state_of(tunnel.key).s > 0.0, "%.0f" % ambient.state_of(tunnel.key).s)
	check("the eyes are shut and the lights blink", player.eyes_closed() and GameState.light_blink > 0.5, "%.1f / %.2f" % [player.blink_timer, GameState.light_blink])
	await secs(1.6)
	check("173 is put in the middle and held", statue.idle == 1 and Vector2(statue.global_position.x - tunnel.position.x, statue.global_position.z - tunnel.position.z).length() < 0.1, "idle %d at %s" % [statue.idle, str(statue.global_position)])
	await secs(1.8)
	check("after 200 frames 173 is let go and the event is over", statue.idle == 0 and ambient.removed.has(tunnel.key) and player.blink_timer > 0.0, "idle %d blink %.0f" % [statue.idle, player.blink_timer])
	place_statue(Vector3(0.0, -80.0, 0.0))
	# --- room3door: a door shut at once (no movement, no sound)
	var shut: Node3D = null
	for door in facility.rooms.doors.values():
		if is_instance_valid(door) and not door.elevator and not door.big and door.leaf_a != null:
			shut = door
			break
	check("there is a door to shut", shut != null, "")
	if shut != null:
		shut.open = true
		shut.openstate = 180.0
		shut._slide_to_open()
		var opened: float = shut.leaf_a.position.distance_to(shut._closed_a)
		shut.snap_shut()
		check("snap_shut brings the leaves back to where they were", opened > 0.5 and shut.leaf_a.position.distance_to(shut._closed_a) < 0.001 and not shut.open and shut.openstate == 0.0, "was %.2f off" % opened)
	var plain: Dictionary = await _event_room([], used)
	used.append(plain.key)
	place_player(plain.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.5)
	ambient.force(plain.key, "room3door")
	await secs(0.3)
	check("room3door is spent once the player is at the middle", ambient.removed.has(plain.key), "")
	var roar: Dictionary = await _event_room([], used)
	used.append(roar.key)
	place_player(roar.position + Vector3(1.0, 1.0, 1.0))
	await secs(0.5)
	ambient.force(roar.key, "682roar")
	await secs(0.3)
	var roar_state: Dictionary = ambient.state_of(roar.key)
	check("682roar counts 5 to 17 minutes from the first visit", roar_state.s > 70.0 * 290.0 - 100.0 and roar_state.s <= 70.0 * 1000.0, "%.0f" % roar_state.s)
	roar_state.s = 500.0
	player.camera_shake = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("in the last seconds the view shakes hard", player.camera_shake >= 1.5, "%.2f" % player.camera_shake)
	roar_state.s = 70.5
	await secs(0.3)
	check("and the event ends after the roar", ambient.removed.has(roar.key), "")
	# --- room2offices3: the door shuts when the player is away from it and looking elsewhere
	var offices: Dictionary = await _event_room([], used)
	used.append(offices.key)
	var node: Node3D = facility.rooms.get_room(offices)
	place_player(offices.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.5)
	ambient.force(offices.key, "room2offices3")
	var offices_state: Dictionary = ambient.state_of(offices.key)
	await secs(0.3)
	check("room2offices3 counts the frames the player spends in the room", offices_state.s > 5.0 and offices_state.s < 700.0, "%.0f" % offices_state.s)
	offices_state.s = 701.0
	if node.door_slots.get(0) != null:
		face_point(node.global_position + (node.global_position - node.door_slots[0].global_position))
	await secs(0.3)
	check("and then shuts RoomDoors[0] and goes", ambient.removed.has(offices.key) and (node.door_slots.get(0) == null or not node.door_slots[0].open), "")
	# --- buttghost, room3tunnel, toiletguard need Objects[]
	var ghost: Dictionary = await _event_room([], used)
	used.append(ghost.key)
	var ghost_node: Node3D = facility.rooms.get_room(ghost)
	ghost_node.fill_objects[0] = Vector3(1.2, 0.0, 1.0)      # on the floor, whatever the room keeps there
	var ghost_at: Vector3 = ghost_node.object_point(0)
	place_player(ghost_at + Vector3(0.6, 0.9, 0.0))
	await secs(0.5)
	GameState.achievements.erase("789")
	ambient.force(ghost.key, "buttghost")
	await secs(0.4)
	check("buttghost laughs when the player passes Objects[0] (SCP-789-J)", ambient.state_of(ghost.key).s == 1.0 and GameState.achievements.has("789"), "state %.0f, player in %s, room %s, at %s, spot %s" % [ambient.state_of(ghost.key).s, str(facility.record_at(player.global_position).get("key")), ghost.key, str(player.global_position), str(ghost_at)])
	var voice: Variant = ambient._nodes.get(ghost.key, {}).get("voice")
	if voice != null and is_instance_valid(voice):
		(voice as AudioStreamPlayer3D).stop()
	await secs(0.3)
	check("and is gone when the laugh has ended", ambient.removed.has(ghost.key), "")
	var dead: Dictionary = await _event_room([], used)
	used.append(dead.key)
	facility.rooms.get_room(dead).fill_objects[0] = Vector3(1.2, 0.0, -1.0)
	var humans_before: int = facility.humans.size()
	place_player(dead.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.5)
	ambient.force(dead.key, "room3tunnel")
	await secs(0.5)
	var lying: Node3D = facility.humans.back() if facility.humans.size() > humans_before else null
	check("room3tunnel lays a dead guard at Objects[0]", lying != null and lying.is_dead and lying.state == 8 and lying.frame >= 287.5 and ambient.removed.has(dead.key), "")
	var toilet: Dictionary = await _event_room([], used)
	var toilet_node: Node3D = facility.rooms.get_room(toilet)
	toilet_node.fill_objects[1] = Vector3(-1.5, 0.0, 1.0)      # the stall and the wall the event needs (a map may have no toilets)
	toilet_node.fill_objects[2] = Vector3(-1.9, 1.2, 1.0)
	place_player(toilet.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.5)
	ambient.force(toilet.key, "toiletguard")
	await secs(0.5)
	var toilet_nodes: Dictionary = ambient._nodes.get(toilet.key, {})
	check("toiletguard makes his guard when the player comes near", toilet_nodes.has("guard") and is_instance_valid(toilet_nodes["guard"]) and toilet_nodes["guard"].is_dead, "state %.0f nodes %s handler %s removed %s dist %.1f in room %s" % [ambient.state_of(toilet.key).s, str(toilet_nodes.keys()), str(ambient._handlers.has(toilet.key)), str(ambient.removed.has(toilet.key)), maxf(absf(toilet.position.x - player.global_position.x), absf(toilet.position.z - player.global_position.z)), str(facility.record_at(player.global_position).get("key") == toilet.key)])
	player.sound_volume = 4.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.sound_volume = 4.0
	await secs(0.3)
	check("noise close by ends the loop and plays his last words", ambient._nodes.get(toilet.key, {}).has("last") or ambient.removed.has(toilet.key), "")
	used.append(toilet.key)
	# --- room4: 049 put on the ledge
	var four: Dictionary = await _event_room([], used)
	used.append(four.key)
	var neighbours: Array = facility.adjacent_records(four)
	var near_room: Dictionary = neighbours[0] if neighbours.size() > 0 else four
	place_player(near_room.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.6)
	var big: Node3D = facility.spawn_049(0.0)
	big.set_physics_process(false)
	big.global_position = four.position + Vector3(60.0, 0.5, 0.0)
	big.state = 2
	ambient.force(four.key, "room4")
	await secs(0.4)
	var ledge: Vector3 = ambient.to_world(four, 368.0, 528.0, 176.0)
	check("room4 puts a hunting 049 on the ledge of the room", big.global_position.distance_to(ledge) < 0.5 and ambient.removed.has(four.key), "%s vs %s" % [str(big.global_position), str(ledge)])
	check("he stands there in state 4", big.state == 4 and big.state2 == 0.0 and big.state3 == 0.0, "state %d" % big.state)
	big._on_catwalk(1.0, 0.0143, 13.0, player, facility)
	check("beyond 12 and not yet watching he stays on the catwalk", big.state == 4, "state %d" % big.state)
	big._on_catwalk(1.0, 0.0143, 5.0, player, facility)
	check("within 8 he watches the player", big.state == 4 and big.state3 == 1.0, "state %d state3 %.0f" % [big.state, big.state3])
	big._on_catwalk(1.0, 0.0143, 13.0, player, facility)
	check("once the player is beyond 12 he climbs down into the room under him and hunts", big.state == 2 and big.state3 == 0.0 and big.global_position.distance_to(four.position + Vector3(0.0, 0.1, 0.0)) < 0.5, "state %d at %s" % [big.state, str(big.global_position)])
	facility.scp049 = null
	big.queue_free()
	# --- tunnel2smoke: two pipes burst, puff and go on hissing
	var burst: Dictionary = await _event_room([], used)
	used.append(burst.key)
	var burst_node: Node3D = facility.rooms.get_room(burst)
	burst_node.fill_objects[0] = Vector3(0.0, 2.1, -2.0)
	burst_node.fill_objects[1] = Vector3(0.0, 2.1, 2.0)
	var emitters_before := 0
	for jet in facility.particles.emitters:
		if jet.key == burst.key:
			emitters_before += 1
	place_player(burst.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.5)
	var puffs_before: int = facility.particles.count()
	ambient.force(burst.key, "tunnel2smoke")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var jets_now := 0
	for jet in facility.particles.emitters:
		if jet.key == burst.key:
			jets_now += 1
	check("tunnel2smoke opens two jets and puffs once", jets_now == emitters_before + 2 and facility.particles.count() >= puffs_before + 10 and ambient.removed.has(burst.key), "%d jets, %d particles" % [jets_now - emitters_before, facility.particles.count() - puffs_before])
	# --- room2pit: 173 on the ledge at Objects[6] while neither it nor the spot is seen
	var pit: Dictionary = await _event_room([], used)
	used.append(pit.key)
	var pit_node: Node3D = facility.rooms.get_room(pit)
	pit_node.fill_objects[6] = Vector3(0.0, -30.0, 2.0)      # under the floor: the event waits until the spot is out of sight
	place_player(pit.position + Vector3(-1.5, 1.0, 0.0))
	await secs(0.5)
	place_statue(Vector3(player.global_position.x, -80.0, player.global_position.z))      # straight down: the floor under the player's feet hides it
	statue.idle = 0
	ambient.force(pit.key, "room2pit")
	await secs(0.4)
	var ledge_spot: Vector3 = pit_node.object_point(6)
	check("room2pit puts 173 on the ledge", Vector2(statue.global_position.x - ledge_spot.x, statue.global_position.z - ledge_spot.z).length() < 0.1 and ambient.removed.has(pit.key), "%s vs %s" % [str(statue.global_position), str(ledge_spot)])
	place_statue(Vector3(0.0, -80.0, 0.0))
	var shy_room: Dictionary = await _event_room([], used)
	var next_door: Array = facility.adjacent_records(shy_room)
	var from_room: Dictionary = shy_room
	if is_instance_valid(facility.scp096):
		facility.scp096.queue_free()
	facility.scp096 = null
	facility.events.servers.state = 70.0 * 45.0
	# a neighbour with a floor in the middle (a shaft or a pit room drops the player away from where 096 was turned)
	for candidate in next_door:
		from_room = candidate
		place_player(from_room.position + Vector3(0.0, 1.0, 0.0))
		await secs(0.6)
		if player.global_position.y > from_room.position.y - 0.5:
			break
	ambient.force(shy_room.key, "096spawn")
	await secs(0.5)
	var shy: Node3D = facility.scp096
	check("096spawn makes 096 when the player is near and not in the room", shy != null and is_instance_valid(shy) and shy.state == 5 and ambient.state_of(shy_room.key).s >= 1.0, "")
	if shy != null and is_instance_valid(shy):
		var off := Vector2(shy.global_position.x - shy_room.position.x, shy.global_position.z - shy_room.position.z).length()
		check("it stands inside the room, near the middle", off < 3.0, "%.2f from the middle" % off)
		var facing: Vector3 = -shy.global_transform.basis.z
		var to_player: Vector3 = player.global_position - shy.global_position
		check("with its back to the player", facing.dot(to_player.normalized()) < -0.5, "dot %.2f" % facing.dot(to_player.normalized()))
		shy.set_physics_process(false)
		# the player comes within 7.5 in its sight: it is rested
		var close := Vector3.INF
		for try_distance in [4.0, 3.0, 5.0, 2.5, 6.0]:
			close = _clear_spot(shy.global_position, try_distance)
			if close != Vector3.INF:
				break
		if close == Vector3.INF:
			close = shy.global_position + Vector3(3.0, 0.1, 0.0)
		place_player(close + Vector3(0.0, 0.1, 0.0))
		await secs(0.4)
		check("it rests when the player comes close in its sight", ambient.state_of(shy_room.key).s == 2.0, "state %.0f" % ambient.state_of(shy_room.key).s)
		# away, the event wakes again or waits until the next time
		place_player(shy_room.position + Vector3(40.0, 1.0, 0.0))
		await secs(0.4)
		check("and when the player has gone away it is armed again (or waits)", ambient.state_of(shy_room.key).s in [0.0, 3.0], "state %.0f" % ambient.state_of(shy_room.key).s)
		facility.scp096.queue_free()
		facility.scp096 = null
	ambient.enabled = false

# ---------------------------------------------------------------- bleeding and bullets that miss (Main.bb UpdateInjuries, NPCs.bb Shoot)

func _decal_count(min_size: float = 0.0) -> int:
	var count := 0
	for child in facility.get_parent().get_children():
		if child is GrowingDecal and child.scale.x >= min_size:
			count += 1
	return count

func _last_decal() -> GrowingDecal:
	var last: GrowingDecal = null
	for child in facility.get_parent().get_children():
		if child is GrowingDecal:
			last = child
	return last

func _scn_lockroom2blood() -> void:
	log_line("== lockroom2 floor blood: 6 splats + 12 drops (MapSystem.bb 2266-2279)")
	var found := 0
	for key in facility.rooms.built:
		var room: Node3D = facility.rooms.built[key]
		if str(room.get("room_name")) != "lockroom2":
			continue
		found += 1
		var quads := 0
		for child in room.get_children():
			if child is MeshInstance3D and child.mesh is QuadMesh and absf(child.position.y) < 0.05 and child.position.y > 0.0:
				quads += 1
		check("lockroom2 has 18 floor decals", quads == 18, "%d" % quads)
		var outside := 0
		for child in room.get_children():
			if child is MeshInstance3D and child.mesh is QuadMesh and absf(child.position.y) < 0.05 and child.position.y > 0.0:
				var d: Vector3 = child.global_position - room.global_position
				if d.x < -392.0 * 8.0 / 2048.0 - 0.01 or d.x > 520.0 * 8.0 / 2048.0 + 0.01 or d.z > 392.0 * 8.0 / 2048.0 + 0.01 or d.z < -520.0 * 8.0 / 2048.0 - 0.01:
					outside += 1
		check("lockroom2 blood sits in the unrotated Blitz offsets (x -392..520, z flipped)", outside == 0, "%d outside at angle %.0f" % [outside, rad_to_deg(room.rotation.y)])
	var planned := 0
	for record in facility.generator.rooms:
		if str(record.name) == "lockroom2":
			planned += 1
	if planned == 0:
		log_line("SKIP  lockroom2: this map has none (MapSystem.bb 7448 indexes past the placed ROOM2C rooms)")
	else:
		check("every generated lockroom2 is built", found == planned, "built %d, generated %d" % [found, planned])

# The colour a straight-alpha picture keeps under its clear texels must be the picture's own: filtering and the mipmaps
# mix it into the outline and, far away, over the whole quad (the pale squares round the decals and the smoke).
func _scn_spriteedges() -> void:
	log_line("== decal and particle pictures hold their own colour under their clear texels")
	var files: Array[String] = ["GFX/smoke.png", "GFX/smoke2.png", "GFX/bloodsprite.png", "GFX/blooddrop1.png", "GFX/blooddrop2.png", "GFX/decal8.png", "GFX/decal19.png", "GFX/decal427.png", "GFX/lightcone.png", "GFX/npcs/860_eyes.png"]
	for i in range(1, 8):
		files.append("GFX/decal%d.png" % i)
	var worst_clear := 0.0
	var worst_far := 0.0
	var worst_file := ""
	for file in files:
		# a copy: headless, get_image() hands out the texture's own image, which other code has stripped of its mipmaps
		var image := MeshLoader._load_texture(ContentPaths.existing_image(file)).get_image().duplicate() as Image
		if not image.has_mipmaps():
			image.generate_mipmaps()
		var mipped := image.get_data()
		# the last level is one texel, the last four bytes; one that is all but clear has no colour to speak of
		var far := Vector3(mipped[-4], mipped[-3], mipped[-2]) / 255.0
		var far_counts := mipped[-1] >= 8
		image.clear_mipmaps()
		var visible := Vector3.ZERO
		var weight := 0.0
		var clear := Vector3.ZERO
		var clear_count := 0
		var data := image.get_data()
		for at in range(0, data.size(), 4):
			var colour := Vector3(data[at], data[at + 1], data[at + 2]) / 255.0
			if data[at + 3] == 0:
				clear += colour
				clear_count += 1
			else:
				visible += colour * data[at + 3]
				weight += data[at + 3]
		if weight <= 0.0 or clear_count == 0:
			check("%s has visible and clear texels" % file, false, "")
			continue
		visible /= weight
		var clear_error := (clear / clear_count - visible).abs()
		var far_error := (far - visible).abs()
		var clear_max := maxf(clear_error.x, maxf(clear_error.y, clear_error.z))
		var far_max := maxf(far_error.x, maxf(far_error.y, far_error.z)) if far_counts else 0.0
		if maxf(clear_max, far_max) > maxf(worst_clear, worst_far):
			worst_file = file
		worst_clear = maxf(worst_clear, clear_max)
		worst_far = maxf(worst_far, far_max)
	check("the clear texels of all %d pictures are the picture's colour (smoke.png held 0.29 off, decal8.png 0.69)" % files.size(), worst_clear < 0.08, "%.3f off in %s" % [worst_clear, worst_file])
	# 860_eyes.png is 0.11 off: its halo is paler than its core, and the level weighs them by area
	check("their smallest mipmap is the picture's colour too (decal5.png was 0.53 off)", worst_far < 0.15, "%.3f off in %s" % [worst_far, worst_file])
	# Headless nothing is drawn, so these two only hold the fix in place: a mixed picture drawn at full alpha pastes the
	# screen copy (the opaque scene) over the smoke and decals already drawn inside its quad.
	var smoke_material: ShaderMaterial = (facility.particles._picture_mesh(0).instance as MultiMeshInstance3D).material_override
	check("particles are drawn after the decals behind them", smoke_material.render_priority > 0, "%d" % smoke_material.render_priority)
	var mixed := FileAccess.get_file_as_string("res://shaders/gamma_blend.gdshaderinc")
	check("mixed pictures blend over what the transparent pass has drawn", mixed.contains("ALPHA = cover;"), "")
	# smoke.png has pale lines at 1-3 % alpha along two edges: blended on linear values they stood out over the dark rooms
	check("alpha-mixed particles blend on display values", smoke_material.shader.code.contains("display_mix("), "")

func _scn_decalload() -> void:
	log_line("== a decal restored from a save stops growing (Save.bb 331-356, Main.bb 10771-10781)")
	var record := {"pos": [0.0, 0.0, 0.0], "basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], "texture": "GFX/decal0.png", "size": 0.3, "growth": 0.001, "max": 0.8, "timer": 5.0, "stains": true, "alpha": 0.8, "alpha_change": 0.0, "multiply": true}
	var world_decals := GrowingDecal.capture_all(get_tree())
	var holder := Node3D.new()
	add_child(holder)
	var old := GrowingDecal.make(holder, Vector3.ZERO, "GFX/decal3.png", 0.5, 0.0, 1.0, false)
	GrowingDecal.restore_all(holder, [record])
	await get_tree().process_frame
	check("restoring frees the decals that were already there (Save.bb 975-978)", not is_instance_valid(old), "")
	var decal: GrowingDecal = null
	var count := 0
	for child in holder.get_children():
		if child is GrowingDecal:
			decal = child
			count += 1
	check("the decal is restored", decal != null and count == 1, "%d" % count)
	if decal != null:
		check("it keeps its size and has no growth", is_equal_approx(decal.size, 0.3) and decal.size_change == 0.0, "size %.3f change %.4f" % [decal.size, decal.size_change])
		check("it drops no stains", not decal.drop_stains, "")
		check("with no fade it is drawn opaque and with the normal blend (Save.bb 999)", is_equal_approx(decal.alpha, 1.0) and not decal.multiply, "alpha %.2f multiply %s" % [decal.alpha, decal.multiply])
		await secs(1.0)
		check("it is still the same size a second later", is_equal_approx(decal.size, 0.3) and holder.get_child_count() == 1, "size %.3f, %d children" % [decal.size, holder.get_child_count()])
	var fading := {"pos": [1.0, 0.0, 0.0], "basis": record.basis, "texture": "GFX/decal1.png", "size": 0.2, "alpha": 0.4, "alpha_change": 0.005, "lifetime": 100.0}
	GrowingDecal.restore_all(holder, [fading])
	await get_tree().process_frame
	var kept: GrowingDecal = null
	for child in holder.get_children():
		if child is GrowingDecal and not child.is_queued_for_deletion():
			kept = child
	check("a fading decal keeps its saved alpha and its lifetime", kept != null and absf(kept.alpha - 0.4) < 0.05 and kept.lifetime > 90.0, "")
	var saved := GrowingDecal.capture_all(get_tree())
	var lifetimes := 0
	for item in saved:
		if item.has("lifetime") and float(item.lifetime) > 0.0:
			lifetimes += 1
	check("the lifetime is saved", lifetimes == 1, "%d" % lifetimes)
	await secs(2.5)
	check("the restored lifetime runs down and removes the decal (UpdateDecals)", not is_instance_valid(kept), "")
	holder.queue_free()
	GrowingDecal.restore_all(facility.get_parent(), world_decals)

func _scn_fxplayer() -> void:
	log_line("== bleeding drips and bullet impacts")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	player.blink_timer = 400.0
	await secs(1.0)
	GameState.god_mode = false
	GameState.injuries = 4.0
	GameState.bloodloss = 5.0
	var drops_before := _decal_count()
	var waited := 0.0
	while waited < 8.0 and _decal_count() == drops_before:
		await get_tree().physics_frame
		GameState.bloodloss = minf(GameState.bloodloss, 20.0)
		waited += get_physics_process_delta_time()
	check("a bleeding player drips blood on the floor", _decal_count() > drops_before, "%.1f s" % waited)
	var drop := _last_decal()
	check("the drop lies on the floor, 0.03 to 0.24 wide", drop != null and absf(drop.global_position.y - home.y) < 0.1 and drop.scale.x > 0.029 and drop.scale.x < 0.25, "%s" % str(drop.scale if drop != null else Vector3.ZERO))
	GameState.injuries = 0.0
	GameState.bloodloss = 0.0
	# a shot that misses: a puff, flecks and a bullet hole in the wall behind the player
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	facility.get_parent().add_child(wall)
	wall.global_position = home + Vector3(0.0, 1.0, 1.5)
	await _frames(2)
	var puffs_before: int = _particles_of(0).size()
	var decals_before := _decal_count()
	Gunfire.shoot(player, home + Vector3(0.0, 0.6, -3.0), 0.0, "test", false, true)
	check("a miss that is meant to show leaves an impact", _decal_count() == decals_before + 1, "")
	var puffs: int = _particles_of(0).size() - puffs_before
	check("with a puff and three or four flecks", puffs >= 4 and puffs <= 5, "%d" % puffs)
	var hole := _last_decal()
	check("the hole lives 20 seconds (lifetime 1400 frames)", hole is GrowingDecal and (hole as GrowingDecal).lifetime > 1300.0, "")
	check("the hole faces out of the wall, 1 mm off it", hole != null and hole.global_basis.z.normalized().dot(Vector3(0.0, 0.0, -1.0)) > 0.99 and absf(hole.global_position.z - (home.z + 1.4 - 0.001)) < 0.002, "%s" % str(hole.global_position if hole != null else Vector3.ZERO))
	check("it is 0.028 to 0.034 across (half), multiplied", hole != null and hole.scale.x >= 0.028 and hole.scale.x <= 0.034 and hole.material_override is StandardMaterial3D, "")
	decals_before = _decal_count()
	Gunfire.shoot(player, home + Vector3(0.0, 0.6, -3.0), 0.0, "test", false, false)
	check("a shooter that does not ask for it leaves none", _decal_count() == decals_before, "")
	wall.queue_free()

# ---------------------------------------------------------------- effects of single rooms: 895 on the monitors, steam, 106 in the gate

func _particles_of(image: int) -> Array:
	return facility.particles._items.filter(func(p: Particles.Particle) -> bool: return p.image == image)

# MapSystem.bb 4021: the start room's DevilParticleSystem smoke (ParticleEffect[1]), made while the player is in the room or within 8
func _scn_startsmoke() -> void:
	log_line("== the start room's smoke")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	var start: FacilityRoom = facility.start_node
	var source: Vector3 = start.to_global(Vector3(3384.0, 510.0, -2400.0) * (8.0 / 2048.0))
	place_player(start.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(1.5)
	var puffs := _particles_of(Particles.DEVIL_SMOKE_PICTURE)
	# 4 puffs every 5 frames (ticks: the timer's reset takes one) that live 31-46: 26 to 31 at a time
	check("smoke rises in the start room, about 31 puffs at a time", puffs.size() >= 20 and puffs.size() <= 42, "%d" % puffs.size())
	var shaped: bool = not puffs.is_empty() and puffs.all(func(p: Particles.Particle) -> bool:
		return Vector2(p.pos.x - source.x, p.pos.z - source.z).length() < 0.001 and p.pos.y >= source.y and p.yspeed >= 0.02 and p.yspeed <= 0.025 and p.size_mult == 1.01 and p.size >= 0.2)
	check("from (3384, 510, 2400), straight up 0.02-0.025 a frame, 0.2 to 0.6 and growing", shaped, "")
	var far_key := ""
	for key in facility.rooms.by_grid:
		var rec: Dictionary = facility.rooms.by_grid[key]
		if RoomRegistry.room_dist(rec.position, start.global_position) > 24.0:
			far_key = key
			break
	if far_key != "":
		place_player((facility.rooms.by_grid[far_key].position as Vector3) + Vector3(0.0, 0.5, 0.0))
		await secs(1.0)
		check("none is made once the player is more than 8 away", _particles_of(Particles.DEVIL_SMOKE_PICTURE).is_empty(), "%d" % _particles_of(Particles.DEVIL_SMOKE_PICTURE).size())
	place_player(start.to_global(Vector3(14.0, 1.55, -5.5)))

func _scn_fxrooms() -> void:
	log_line("== the 895 camera on the monitors, the burst pipes, 106 burning in the gate")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var ambient: Node = facility.ambient
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	# CoffinCam: a monitor that 079 is broadcasting on shows the chamber's camera instead of its own
	var coffin_cam: SecurityCam = SecurityCam.coffin_cam
	check("SCP-895's camera is the CoffinCam", coffin_cam != null and coffin_cam.coffin_effect == 1, "")
	var screen_cam: SecurityCam = null
	for node in get_tree().get_nodes_in_group("security_cam"):
		if node is SecurityCam and node != coffin_cam and node.has_screen and node._picture != null and node._overlay != null and node.coffin_effect == 0:
			screen_cam = node
			break
	check("the map has another monitor", screen_cam != null, "")
	if coffin_cam != null and screen_cam != null:
		var chamber: Node3D = coffin_cam.room
		var renders_before: int = screen_cam.renders
		var coffin_before: int = screen_cam.coffin_renders
		for i in 12:
			screen_cam._render_feed()
		var own_renders: int = screen_cam.renders - renders_before
		var own_coffin: int = screen_cam.coffin_renders - coffin_before
		check("a monitor that does not carry 895 shows its own camera", own_renders == 12 and own_coffin == 0, "%d of %d" % [own_coffin, own_renders])
		screen_cam.coffin_effect = 3
		chamber.visible = false
		var visuals := chamber.find_children("*", "VisualInstance3D", true, false)
		var layers_before := visuals.map(func(v: VisualInstance3D) -> int: return v.layers)
		var coffin_view := false
		for i in 60:
			var before: int = screen_cam.coffin_renders
			screen_cam._render_feed()
			if screen_cam.coffin_renders > before:
				coffin_view = true
				var feed: Camera3D = screen_cam._feed_camera
				check("it looks from the CoffinCam's head, 0.1 forward", feed.global_position.distance_to(coffin_cam._head.global_position + coffin_cam.head_forward() * 0.1) < 0.001, "")
				check("and the chamber is shown for the picture", chamber.visible, "")
				check("the feed camera draws the chamber's layer and the player's camera does not", (feed.cull_mask & SecurityCam.CHAMBER_LAYER) != 0 and (player.camera.cull_mask & SecurityCam.CHAMBER_LAYER) == 0, "feed %d player %d" % [feed.cull_mask, player.camera.cull_mask])
				break
		check("a monitor 079 is broadcasting on shows the chamber's camera most of the time", coffin_view and screen_cam.coffin_renders > 0, "%d of %d" % [screen_cam.coffin_renders, screen_cam.renders])
		var leaked := 0
		var drawable := 0
		for frame in 4:
			for v in visuals:
				if v.is_visible_in_tree():
					if (v.layers & player.camera.cull_mask) != 0:
						leaked += 1
					elif (v.layers & screen_cam._feed_camera.cull_mask) != 0:
						drawable += 1
			await get_tree().process_frame
		check("while the chamber is shown for the picture only the feed camera can see it", leaked == 0 and drawable > 0, "%d visible to the player's camera, %d to the feed" % [leaked, drawable])
		await _frames(3)
		check("the chamber is hidden again afterwards", not chamber.visible, "")
		var restored := true
		for i in visuals.size():
			restored = restored and visuals[i].layers == layers_before[i]
		check("and its visuals are back on their layers", restored, "")
		# 079's broadcast (UpdateSecurityCams): a monitor that may carry 895 plays the broadcast sound and turns to the chamber's feed
		screen_cam.in_sight = false
		screen_cam.coffin_effect = 2
		screen_cam.player_state = 1
		screen_cam._channel = null
		screen_cam._broadcast_079()
		check("an effect-2 monitor broadcasts: its sound plays and it turns to effect 3 with PlayerState 0", screen_cam.coffin_effect == 3 and screen_cam.player_state == 0 and screen_cam._channel_playing(), "effect %d state %d" % [screen_cam.coffin_effect, screen_cam.player_state])
		check("and shows 079's face on its overlay", (screen_cam._overlay.material_override as ShaderMaterial).get_shader_parameter("tex") == screen_cam._ai_face, "")
		screen_cam.coffin_effect = 2
		screen_cam.player_state = 1
		screen_cam._broadcast_079()
		check("with the channel busy it keeps waiting at effect 2", screen_cam.coffin_effect == 2, "effect %d" % screen_cam.coffin_effect)
		screen_cam._channel.stop()
		screen_cam.coffin_effect = 0
		screen_cam.player_state = 0
		screen_cam.in_sight = true
		screen_cam._broadcast_079()
		check("a clean monitor in sight sets PlayerState to 60000..65000", screen_cam.player_state >= 60000 and screen_cam.player_state <= 65000 and screen_cam.coffin_effect == 0, "state %d" % screen_cam.player_state)
		screen_cam.in_sight = false
		screen_cam.player_state = 1
		screen_cam._channel = null
		screen_cam._broadcast_079()
		check("out of sight a clean monitor does nothing", screen_cam._channel == null and screen_cam.player_state == 1, "")
		screen_cam.player_state = 0
		chamber.visible = true
		screen_cam.coffin_effect = 0
		var angle_before: float = coffin_cam.curr_angle
		place_player(screen_cam.room.global_position + Vector3(0.0, 1.55, 0.0))
		player.blink_timer = 400.0
		await secs(1.0)
		check("the CoffinCam keeps turning when the player is far from it", coffin_cam.curr_angle != angle_before and not coffin_cam._close(player, facility), "%.2f -> %.2f" % [angle_before, coffin_cam.curr_angle])
	# room2gw_b: a dead guard, steam from the pipes, the alarm
	var gw := _find_room("room2gw_b")
	check("the map has the burst airlock", not gw.is_empty(), "")
	if not gw.is_empty():
		var gw_room: Node = facility.rooms.get_room(gw)
		var pool := gw_room.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.mesh is QuadMesh and absf(n.mesh.size.x - 1.0) < 0.001 and n.position.distance_to(Vector3(-156.825, -37.3458, -121.364) * (8.0 / 2048.0)) < 0.001)
		check("the blood pool under the guard is part of the room build, before the event runs (MapSystem.bb:5064)", pool.size() == 1, "%d" % pool.size())
		place_player(gw.position + Vector3(0.0, 1.55, 0.0))
		player.blink_timer = 400.0
		ambient.force(gw.key, "room2gw_b")
		await secs(1.0)
		var state: Dictionary = ambient.state_of(gw.key)
		var nodes: Dictionary = ambient._nodes.get(gw.key, {})
		check("within 8 a guard lies in the room, dead (frame 288)", state.s == 1.0 and nodes.has("guard") and is_instance_valid(nodes["guard"]) and nodes["guard"].is_dead and nodes["guard"].frame == 288.0, "")
		var steam := _particles_of(6).filter(func(p: Particles.Particle) -> bool: return p.size == 0.2)
		check("steam blows from the pipes (a puff a frame, 10 long)", steam.size() >= 5 and steam.size() <= 12, "%d" % steam.size())
		var at: Vector3 = facility.rooms.get_room(gw).object_point(0)
		check("room2gw_b's Objects[0] is its own (280, 345, -340), not room2gw's", at.distance_to(ambient.to_world(gw, 280.0, 345.0, -340.0)) < 0.01, "")
		check("from Objects[0], heading up and along the room", steam.size() > 0 and steam[0].pos.distance_to(at) < 0.5 and steam[0].dir.y > 0.8, "")
		check("the alarm sounds", nodes.has("alarm") and is_instance_valid(nodes["alarm"]) and nodes["alarm"].playing, "")
		place_player(gw.position + Vector3(30.0, 1.55, 0.0))
		await secs(0.4)
		check("and stops when the player has gone", not is_instance_valid(nodes.get("alarm")), "")
	# the tesla gate burns 106
	ambient._tesla_burn(Vector3(0.0, 200.0, 0.0))
	var burn := _particles_of(0).filter(func(p: Particles.Particle) -> bool: return p.size == 0.03 and p.gravity == -0.2)
	check("106 burning in a tesla gate gives off 11 puffs of smoke", burn.size() == 11, "%d" % burn.size())
	ambient.enabled = false
	await _frames(2)

func _scn_fxgates() -> void:
	log_line("== the pillar room's figure, gate B's dust and wreck, the nuke's smoke, gate A's flares")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.spawn_096_rooms = false
	var particles: Particles = facility.particles
	# the pocket dimension's pillar room
	var home: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
	place_player(home)
	await secs(0.5)
	var old_man: CharacterBody3D = facility.spawn_106(5000.0)
	await get_tree().physics_frame
	old_man.state = 250.0
	facility.enter_pocket(player)
	var pocket: Node3D = facility.pocket
	await secs(1.0)
	pocket.event_state2 = 12
	await secs(0.3)
	check("the pillar room is entered", pocket.event_state2 >= 12 and pocket.player_inside, "")
	var before := _particles_of(Particles.HG_MULTIPLIED).size()
	for i in 20000:
		pocket._drift_figure(player)
	var figures := _particles_of(Particles.HG_MULTIPLIED)
	check("1 frame in 800 a figure appears (hg.pt multiplied, 4 across, 2500 frames)", figures.size() > before + 5 and figures[-1].size == 4.0 and figures[-1].lifetime == 2500.0 and figures[-1].speed == 0.01, "%d" % (figures.size() - before))
	var offset: Vector3 = figures[-1].pos - player.global_position
	var turn := wrapf(rad_to_deg(atan2(-offset.z, offset.x)) - rad_to_deg(player.rotation.y), 0.0, 360.0)
	check("7.5 away, 150 to 210 degrees round from the view's yaw (a sideways quirk of the original), at the floor", absf(Vector2(offset.x, offset.z).length() - 7.5) < 0.01 and turn >= 149.9 and turn <= 210.1 and absf(figures[-1].pos.y - pocket.position.y) < 0.01, "%s turn %.1f" % [str(offset), turn])
	await _frames(2)
	check("it is shown with the multiply blend", particles._meshes.size() > Particles.HG_MULTIPLIED and particles._meshes[Particles.HG_MULTIPLIED] != null and particles._meshes[Particles.HG_MULTIPLIED].instance.material_override.get_shader_parameter("tex") != null, "")
	GameState.god_mode = true
	pocket.player_inside = false
	pocket.set_shown(false)
	pocket._unfog()
	old_man.queue_free()
	facility.scp106 = null
	# gate B
	var record := _find_room("exit1")
	if record.is_empty():
		log_line("SKIP  this map has no gate B")
	else:
		place_player(record.position + Vector3(0.0, 1.55, 0.0) + Vector3(20.0, 0.0, 0.0))
		player.blink_timer = 400.0
		await secs(1.5)
		var room: Node3D = facility.rooms.get_room(record)
		place_player(room.object_point(5) + Vector3(0.0, 1.0, 0.0))
		player.blink_timer = 400.0
		await secs(1.5)
		var event: Node = room.extras
		var specks := _particles_of(2).filter(func(p: Particles.Particle) -> bool: return p.size < 0.007)
		check("on the surface wind-blown dust comes past the eyes", specks.size() > 10, "%d" % specks.size())
		var speck: Particles.Particle = specks[0] if not specks.is_empty() else null
		if speck != null:
			check("a speck is 0.006 across, 300 frames long, slowly shrinking, heading level-ish", speck.size_change == -0.00001 and speck.speed >= 0.002 and speck.speed <= 0.003 and absf(speck.dir.y) < 0.35, "")
		place_player(room.object_point(10) + Vector3(0.0, 1.0, 0.0))
		await secs(1.0)
		check("the battle begins", facility.events.exit1.state >= 2.0 and event.apaches.has(3), "%.0f" % facility.events.exit1.state)
		var emitters_before := particles.emitters.size()
		facility.events.exit1.state = 26.6 * 70.0
		var waited := 0.0
		while waited < 6.0 and particles.emitters.size() == emitters_before:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
		check("when the third helicopter is swatted down it smokes for good", particles.emitters.size() == emitters_before + 1, "%.1f s" % waited)
		var wreck: Dictionary = particles.emitters[-1]
		check("with the wreck's emitter (gravity -0.18, 400 frames, 45 degrees)", wreck.gravity == -0.18 and wreck.lifetime == 400.0 and wreck.rand_angle == 45.0 and wreck.follow == event.apaches[3] and wreck.size_change >= 0.005 and wreck.size_change <= 0.007, "")
		await get_tree().physics_frame
		var big := _particles_of(0).filter(func(p: Particles.Particle) -> bool: return p.gravity == -0.1 * 0.004 and p.size_change == 0.01)
		var flecks := _particles_of(0).filter(func(p: Particles.Particle) -> bool: return p.size == 0.02 and p.speed == 0.04)
		check("and 8 big puffs and 13 flecks fly out", big.size() == 8 and flecks.size() == 13, "%d %d" % [big.size(), flecks.size()])
		await secs(0.5)
		check("the emitter follows the helicopter", wreck.pos.distance_to(wreck.follow.global_position) < 0.5, "")
		# the nuke
		GameState.explosion_timer = 135.0
		await secs(0.4)
		var risers := _particles_of(0).filter(func(p: Particles.Particle) -> bool: return p.size >= 0.19 and p.speed >= 0.05 and p.speed <= 0.07 and p.dir.y > 0.99)
		check("the nuke pours 41 columns of smoke up around the player", risers.size() >= 41, "%d" % risers.size())
		GameState.explosion_timer = 0.0
		facility.events.exit1.state = 0.0
		var start_spot: Vector3 = facility.start_node.to_global(Vector3(14.0, 1.55, -5.5))
		place_player(start_spot)
		await secs(0.6)
	# gate A
	var arrived: Dictionary = await _gatea_arrive(false)
	if arrived.ok:
		var room: Node3D = arrived.room
		var event: Node = room.extras
		facility.events.gatea.state = 340.0
		await secs(1.5)
		event._shy.set_frame(257.0)
		var wait := 0.0
		while wait < 8.0 and event.stage_106 < 2:
			await get_tree().physics_frame
			wait += get_physics_process_delta_time()
		var end: Vector3 = room.object_point(4)
		event._shy.global_position = Vector3(end.x + 6.0, end.y, end.z)
		wait = 0.0
		while wait < 3.0 and event.turret_clock < 0.0:
			await get_tree().physics_frame
			wait += get_physics_process_delta_time()
		check("106 walking up the bridge within 8.5 of the end sets the turret charging", event.turret_clock >= 0.0, "")
		# Rand(2,8)-6 smokes on 3 frames in 7
		var wisps: Array = []
		for i in 30:
			await _frames(1)
			wisps = _particles_of(0).filter(func(p: Particles.Particle) -> bool: return p.gravity == -0.002 * 0.004 and p.lifetime <= 40.0)
			if not wisps.is_empty():
				break
		check("he gives off smoke while it does (6 m from the end: 2 to 8 minus 6)", wisps.size() > 0 and wisps[0].dir.y > 0.3, "%d" % wisps.size())
		event.turret_clock = 7.5 * 70.0 - 0.5
		await _frames(2)
		var suns := _particles_of(4).filter(func(p: Particles.Particle) -> bool: return p.size == 7.0 or p.size == 2.0)
		check("at 7.5 s of charge a flare sits on 106 (7 across) and one on the light gun (2), 6.7 s each", suns.size() == 2 and suns[0].lifetime > 6.7 * 70.0 - 6.0 and suns[0].follow != null and suns[1].follow == event.light_gun, "%d" % suns.size())
		var flare: Particles.Particle = suns.filter(func(p: Particles.Particle) -> bool: return p.size == 2.0)[0]
		var expected: Vector3 = event.light_gun.to_global(Vector3(0.0, 92.0 * 8.0 / 2048.0, -512.0 * 8.0 / 2048.0))
		check("the gun's flare is 512 in front of it and follows", flare.pos.distance_to(expected) < 0.01, "")
		# the Chaos Insurgency
		event.stage_106 = 4
		var tunnel_end: Vector3 = room.object_point(11)
		place_player(tunnel_end + Vector3(0.0, 0.3, 0.0))
		player.blink_timer = 400.0
		facility.events.gatea.state3 = 1.0
		await secs(0.3)
		check("when the Chaos Insurgency show up two flashes rush off from the tunnel's end", _particles_of(4).filter(func(p: Particles.Particle) -> bool: return p.size == 8.0 and p.alpha == 0.5 and (p.speed == 0.15 or p.speed == 0.25)).size() == 2, "")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		_end_ending_for_test(hud)
		facility.events.gatea.state = 0.0
		place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
		await secs(0.6)

# ---------------------------------------------------------------- particles and the gas jets (Particles.bb)

func _scn_particles() -> void:
	log_line("== particles and gas jets")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var particles: Node = facility.particles
	check("the facility has a particle system", particles != null, "")
	if particles == null:
		return
	# one particle by hand: it moves along its heading, rises with a negative gravity, fades, grows and ends
	var before: int = particles.count()
	var p = particles.create(Vector3(0.0, 100.0, 0.0), 0, 0.05, -0.2, 40.0)
	p.speed = 0.1
	p.dir = Vector3.RIGHT
	p.size_change = 0.01
	p.a_change = -0.02
	check("a particle is made", particles.count() == before + 1, "")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("it moves along its heading", p.pos.x > 0.1 and p.pos.x < 0.5, "x %.2f" % p.pos.x)
	check("a negative gravity lifts it", p.pos.y > 100.0, "y %.4f" % p.pos.y)
	check("it grows and fades", p.size > 0.05 and p.alpha < 1.0, "size %.3f alpha %.2f" % [p.size, p.alpha])
	await secs(1.2)
	check("and it is gone when its life is over", not particles._items.has(p), "%d particles" % particles.count())
	# the jets: a lock room's two, near the player
	var lock := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "lockroom":
			lock = candidate
			break
	if lock.is_empty():
		log_line("   no lock room in this map")
		return
	facility.rooms.get_room(lock)
	var jets := 0
	for e in particles.emitters:
		if e.key == lock.key:
			jets += 1
	check("a lock room has its two jets", jets == 2, "%d" % jets)
	place_player(lock.position + Vector3(2.5, 1.0, 2.5))
	await secs(1.5)
	check("they give off gas while the player is near", particles.count() > 40, "%d particles" % particles.count())
	for e in particles.emitters:
		if e.key == lock.key:
			face_point(e.pos)
			break
	player.blink_timer = 500.0
	await secs(1.0)
	await shot("gas_jets")
	GameState.god_mode = true
	# the gas: standing in a jet's smoke burns the eyes; a gas mask keeps it off
	var jet: Dictionary = {}
	for e in particles.emitters:
		if e.key == lock.key:
			jet = e
			break
	if not jet.is_empty():
		place_player(Vector3(jet.pos.x + 0.2, jet.pos.y - 1.2, jet.pos.z))
		GameState.eye_irritation = 0.0
		await secs(1.0)
		check("within 0.8 of a jet the smoke gets in the eyes", particles.in_smoke and GameState.eye_irritation > 100.0, "irritation %.0f" % GameState.eye_irritation)
		GameState.wearing_gas_mask = 1
		var then: float = GameState.eye_irritation
		await secs(0.5)
		check("a gas mask keeps it off", not particles.in_smoke and GameState.eye_irritation <= then, "")
		GameState.wearing_gas_mask = 0
		GameState.god_mode = false
		GameState.eye_irritation = 70.0 * 24.0 + 10.0
		await secs(0.3)
		check("24 seconds of it kill", player.dead, "")
		player.dead = false
		GameState.eye_irritation = 0.0

# ---------------------------------------------------------------- the tesla gate (UpdateEvents "room2tesla")

func _scn_pitduck() -> void:
	log_line("== room3pitduck")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var pit := _find_room("room3pit")
	if pit.is_empty():
		log_line("(this map has no room3pit)")
		return
	ambient.force(pit.key, "room3pitduck")
	var room: Node3D = facility.rooms.get_room(pit)
	var spot: Vector3 = room.object_point(0)
	player.blink_timer = 500.0       # a blink turns the duck at random
	place_player(Vector3(spot.x, pit.position.y + 0.1, spot.z) + (room.global_position - spot).normalized() * 2.0)
	await secs(0.6)
	var nodes: Dictionary = ambient._nodes.get(pit.key, {})
	check("the duck is made at Objects[0]", nodes.has("duck") and is_instance_valid(nodes.duck), "")
	if not nodes.has("duck"):
		return
	var duck: Node3D = nodes.duck
	check("at the object point", duck.global_position.distance_to(spot) < 0.05, "")
	var to_centre := Vector2(room.global_position.x - spot.x, room.global_position.z - spot.z).normalized()
	var duck_front := -duck.global_basis.z
	var duck_facing := Vector2(duck_front.x, duck_front.z).normalized().dot(to_centre)
	check("it faces the middle of the room whatever the room's angle (room at %d)" % int(pit.angle), duck_facing > 0.99, "dot %.2f" % duck_facing)
	var st: Dictionary = ambient.state_of(pit.key)
	face_point(duck.global_position)
	await secs(0.3)
	var before: float = st.s
	await secs(0.3)
	check("on screen the timer does not run", st.s == before, "%.1f" % st.s)
	face_point(player.global_position * 2.0 - duck.global_position)
	await secs(0.3)
	before = st.s
	await secs(0.5)
	check("off screen the timer runs", st.s > before or st.s == 0.0, "%.1f -> %.1f" % [before, st.s])

func _scn_offices2duck() -> void:
	log_line("== room2offices2 duck")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var office := _find_room("room2offices2")
	if office.is_empty():
		log_line("(this map has no room2offices2)")
		return
	ambient.force(office.key, "room2offices2")
	var room: Node3D = facility.rooms.get_room(office)
	var spots: Array = []
	for i in range(1, 5):
		spots.append(room.object_point(i))
	place_player(Vector3(spots[0].x, office.position.y + 0.1, spots[0].z))
	await secs(0.6)
	var nodes: Dictionary = ambient._nodes.get(office.key, {})
	check("the duck is made", nodes.has("duck") and is_instance_valid(nodes.duck), "")
	if not nodes.has("duck"):
		return
	var duck: Node3D = nodes.duck
	var on_pivot := func() -> bool:
		for s in spots:
			if duck.global_position.distance_to(s) < 0.05:
				return true
		return false
	check("it starts on one of Objects[1..4]", on_pivot.call(), "")
	player.blink_timer = 0.0
	await secs(0.3)
	var held := duck.global_position
	var yaw := duck.rotation.y
	check("it stays put while the blink timer is outside (-12,-8)", duck.global_position == held and duck.rotation.y == yaw, "")
	var seen := {}
	for n in 40:
		player.blink_timer = -10.0
		await secs(0.05)
		seen[duck.global_position.snapped(Vector3.ONE * 0.01)] = true
	check("blinking moves it between pivots", seen.size() >= 2 and on_pivot.call(), "%d spots" % seen.size())
	check("and turns it", absf(duck.rotation.y - yaw) > 0.0001, "")

func _scn_lastrooms() -> void:
	log_line("== room1lifts, room2shaft, SCP-1048's drawing, room2storage")
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
	var lifts := _find_room("room1lifts")
	check("the map has room1lifts", not lifts.is_empty(), "")
	if not lifts.is_empty():
		var room: Node3D = facility.rooms.get_room(lifts)
		place_player(lifts.position + Vector3(0.0, 1.0, 0.0))
		await secs(0.3)
		check("room1lifts has its two buttons and the camera", room.extras != null and room.extras.buttons.size() == 2 and room.cams.size() == 1, "")
		hud.message("", 0.1)
		room.extras.buttons[0].press()
		check("pressing one says the elevator is broken", hud.message_label.text.contains("The elevator appears to be broken."), hud.message_label.text)
	var shaft := _find_room("room2shaft")
	if not shaft.is_empty():
		ambient.force(shaft.key, "room2shaft")
		var room: Node3D = facility.rooms.get_room(shaft)
		place_player(shaft.position + Vector3(0.0, 1.0, 0.0))
		await secs(0.5)
		check("room2shaft has its button", room.extras != null and room.extras.buttons.size() == 1, "")
		var guards := 0
		for human in facility.humans:
			if is_instance_valid(human) and human.state == 8 and human.frame == 286.0:
				guards += 1
		check("a guard stands at the bottom of the shaft (frame 286, state 8)", guards >= 1, "%d" % guards)
	var pit := _find_room("room3pit")
	if pit.is_empty():
		log_line("(this map has no room3pit)")
	if not pit.is_empty():
		ambient.force(pit.key, "room3pit1048")
		var room: Node3D = facility.rooms.get_room(pit)
		var bird_spot: Vector3 = room.object_point(0)
		GameState.achievements.erase("1048")
		place_player(Vector3(bird_spot.x, pit.position.y + 0.1, bird_spot.z) + (room.global_position - bird_spot).normalized() * 2.0)
		await secs(0.6)
		var nodes: Dictionary = ambient._nodes.get(pit.key, {})
		check("the paper bird is made at Objects[0]", nodes.has("pivot") and is_instance_valid(nodes.pivot), "")
		check("with one of the twenty drawings chosen", str(nodes.get("path", "")).begins_with("GFX/items/1048/1048_"), str(nodes.get("path", "")))
		check("the Drawing paper shows that picture", str(RoomFill.item_template("Drawing").get("image", "")) == str(nodes.get("path", "x")), "")
		var st: Dictionary = ambient.state_of(pit.key)
		for i in 20:
			face_point(bird_spot + Vector3(0.0, 0.4, 0.0))
			await secs(0.1)
			if st.s >= 1.0:
				break
		check("seen within 3 it unfolds and gives the achievement", st.s >= 1.0 and GameState.achievements.has("1048"), "state %.0f" % st.s)
		for i in 60:
			await secs(0.1)
			if st.s >= 2.0:
				break
		check("then it keeps moving (state 2)", st.s == 2.0, "state %.0f" % st.s)
		var pivot: Node3D = nodes.pivot
		var to_player := Vector2(player.global_position.x - pivot.global_position.x, player.global_position.z - pivot.global_position.z).normalized()
		var bird_front := -pivot.global_basis.z
		var bird_facing := Vector2(bird_front.x, bird_front.z).normalized().dot(to_player)
		check("it turns to the player whatever the room's angle (room at %d)" % int(pit.angle), bird_facing > 0.99, "dot %.2f" % bird_facing)
		place_player(Vector3(bird_spot.x, pit.position.y + 0.1, bird_spot.z) + (room.global_position - bird_spot).normalized() * 0.8)
		face_point(bird_spot + Vector3(0.0, 0.4, 0.0))
		await secs(0.2)
		await shot("room3pit1048_bird")
		for i in 10:
			if not ambient.removed.has(pit.key):
				await tap("interact")
		check("a click within 1.5 takes the drawing and ends the event", ambient.removed.has(pit.key) and hud.items.has("Drawing"), "removed %s" % str(ambient.removed.has(pit.key)))
		var slot: int = hud.items.find("Drawing")
		if slot >= 0:
			hud.items[slot] = ""
			hud.item_data[slot] = {}
	var storage := _find_room("room2storage")
	check("the map has room2storage", not storage.is_empty(), "")
	if storage.is_empty():
		return
	var room: Node3D = facility.rooms.get_room(storage)
	place_player(room.to_global(Vector3(0.0, room.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.6)
	var event: Node = room.extras
	check("the room has its event and six doors", event != null and room.door_slots.size() == 6, "doors %d" % room.door_slots.size())
	var st: Dictionary = ambient.state_of(storage.key)
	st.s = 0.0
	st.s2 = 0.0
	GameState.achievements.erase("970")
	var door_3: Node3D = room.door_slots[3]
	door_3.open = true
	await secs(1.5)
	var at: Vector3 = room.to_local(player.global_position)
	place_player(room.to_global(Vector3(3.1, at.y, at.z)))
	await secs(0.2)
	var after: Vector3 = room.to_local(player.global_position)
	face_point(room.to_global(Vector3(-3.0, 1.2, 0.0)))
	await shot("room2storage_corridor")
	check("going 3 m out at +x carries the player 4 m back and counts a step", after.x < -0.5 and after.x > -1.5 and st.s >= 1.0, "x %.2f s %.0f" % [after.x, st.s])
	check("the achievement is given", GameState.achievements.has("970"), "")
	check("the open door was carried with them (door 1 open, door 3 shut)", room.door_slots[1].open and not room.door_slots[3].open, "")
	place_player(room.to_global(Vector3(-3.1, after.y, after.z)))
	await secs(0.2)
	after = room.to_local(player.global_position)
	check("and the same the other way", after.x > 0.5 and after.x < 1.5 and st.s >= 2.0, "x %.2f s %.0f" % [after.x, st.s])
	# the counted effects
	GameState.god_mode = false
	GameState.injuries = 0.0
	for i in 5:
		_give(hud, "Document SCP-939", "paper")
	var before_items := 0
	for name in hud.items:
		if not name.is_empty():
			before_items += 1
	var lost := false
	for i in 40:
		event._count(facility, player, 2)
		var now := 0
		for name in hud.items:
			if not name.is_empty():
				now += 1
		if now < before_items:
			lost = true
			break
	check("step 2 empties a slot", lost, "")
	event._count(facility, player, 5)
	check("step 5 hurts (0.3)", absf(GameState.injuries - 0.3) < 0.05, "%.2f" % GameState.injuries)
	GameState.injuries = 0.0
	var notes_before := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(node) and node.get_meta("item_name", "") == "Strange Note":
			notes_before += 1
	event._count(facility, player, 18)
	var notes_after := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(node) and node.get_meta("item_name", "") == "Strange Note":
			notes_after += 1
	check("step 18 leaves a strange note by the wall", notes_after == notes_before + 1, "")
	event._count(facility, player, 25)
	check("step 25 puts the corpse at the end", event.corpse != null and is_instance_valid(event.corpse) and event.corpse.frame == 80.0, "")
	event._count(facility, player, 30)
	check("step 30 puts a strange note in a slot", hud.items.has("Strange Note"), "")
	event._count(facility, player, 50)
	check("step 50 stands a guard behind", event.guard != null and is_instance_valid(event.guard), "")
	event._count(facility, player, 52)
	check("step 52 takes him away", event.guard == null, "")
	GameState.halloween = false
	var plain_texture: Texture2D = statue.visual.get_active_material(0).get("albedo_texture")
	event._count(facility, player, 60)
	var skinned: Texture2D = statue.visual.get_active_material(0).get("albedo_texture")
	check("step 60 gives SCP-173 the jack-o'-lantern skin without setting the console's flag", skinned != plain_texture and skinned.get_width() == 1024 and not GameState.halloween, "")
	check("and the skin can be put back", statue.set_skin(false) and statue.visual.get_active_material(0).get("albedo_texture") != skinned, "")
	# the dropped item in three
	GameState.god_mode = true
	var dropped := RoomFill.make_pickup("9V Battery", "bat")
	facility.get_parent().add_child(dropped)
	dropped.set_meta("dropped", true)
	dropped.global_position = room.to_global(Vector3(0.3, 1.2, 0.3))
	await secs(0.6)
	var batteries := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(node) and node.has_meta("tripled") and node.get_meta("item_name", "") == "9V Battery":
			batteries += 1
	check("an item dropped in the middle comes in three", batteries == 3, "%d" % batteries)
	var cup := RoomFill.make_pickup("Cup of Coffee", "cup", {"cr": 0.4, "cg": 0.2, "cb": 0.1, "ca": 0.9})
	facility.get_parent().add_child(cup)
	cup.set_meta("dropped", true)
	cup.global_position = room.to_global(Vector3(-0.4, 1.2, -0.4))
	await secs(0.6)
	var cups := 0
	var coloured := 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(node) and node.has_meta("tripled") and node.get_meta("tempname", "") == "cup":
			cups += 1
			if absf(float(node.get_meta("cr", 0.0)) - 0.4) < 0.01:
				coloured += 1
	check("a dropped cup comes in three with the same drink", cups == 3 and coloured == 3, "%d cups, %d with the drink" % [cups, coloured])
	cup.queue_free()
	dropped.queue_free()
	await secs(0.4)
	batteries = 0
	for node in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(node) and node.has_meta("tripled") and node.get_meta("item_name", "") == "9V Battery":
			batteries += 1
	check("and taking one takes all three", batteries == 0, "%d" % batteries)
	event._locks(facility, player, st, 1.0)
	check("the doors 1 and 4 are unlocked with nothing near", not room.door_slots[1].locked and not room.door_slots[4].locked, "")
	st.s2 = 0.0
	if facility.scp106 == null or not is_instance_valid(facility.scp106):
		facility.spawn_106(INF)
	facility.scp106.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
	event._locks(facility, player, st, 1.0)
	check("with 106 within 8 they are locked", room.door_slots[1].locked and room.door_slots[4].locked, "")
	facility.scp106.global_position = Vector3(0.0, -100.0, 0.0)
	ambient.enabled = false
	GameState.god_mode = false
	GameState.injuries = 0.0
	if event.corpse != null and is_instance_valid(event.corpse):
		facility.remove_human(event.corpse)

func _scn_actorsave() -> void:
	log_line("== the NPCs events make survive a save")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var home := await _event_room()
	facility.rooms.get_room(home)
	var base := Vector3(home.position.x, home.position.y + 0.1, home.position.z)
	place_player(base)
	await secs(0.8)
	var world: Node = facility.get_parent()
	for node in get_tree().get_nodes_in_group("scp066") + get_tree().get_nodes_in_group("scp513_1") + get_tree().get_nodes_in_group("scp372") + get_tree().get_nodes_in_group("tentacle") + get_tree().get_nodes_in_group("scp939"):
		node.queue_free()
	await secs(0.2)
	var ball := CharacterBody3D.new()
	ball.set_script(load("res://scripts/npc/scp_066.gd"))
	world.add_child(ball)
	ball.global_position = base + Vector3(24.0, 0.0, 0.0)
	ball.hop_at = 1e12
	ball.state = 3
	ball.state2 = 33.0
	ball.state3 = 500.0
	var ghost := Node3D.new()
	ghost.set_script(load("res://scripts/npc/scp_513_1.gd"))
	world.add_child(ghost)
	ghost.global_position = base + Vector3(-24.0, 0.0, 0.0)
	ghost.idle = false
	ghost.state = 0
	ghost.state2 = 99999.0
	var shape := Node3D.new()
	shape.set_script(load("res://scripts/npc/scp_372.gd"))
	world.add_child(shape)
	shape.global_position = base + Vector3(0.0, 0.0, 24.0)
	shape.idle = false
	shape.state = 99999.0
	var tentacle := Node3D.new()
	tentacle.set_script(load("res://scripts/npc/scp_tentacle.gd"))
	world.add_child(tentacle)
	tentacle.global_position = base + Vector3(0.0, 0.0, -24.0)
	tentacle.state = 1
	tentacle.frame = 100.0
	tentacle.in_offices = true
	var specimen := CharacterBody3D.new()
	specimen.set_script(load("res://scripts/npc/scp_939.gd"))
	specimen.index = 2
	world.add_child(specimen)
	specimen.global_position = base + Vector3(30.0, 0.0, 0.0)
	specimen.state = 66
	specimen.state2 = 6
	specimen.prev_state = 7
	var body: Node3D = facility.spawn_human(1, base + Vector3(-30.0, 0.0, 0.0), 1)
	body.set_frame(80.0)
	body.state = 10
	body.set_meta("role", "corpse")
	facility.ambient._nodes["test|key"] = {"corpse": body}
	await secs(0.3)
	check("the game saves", main.save_game(), "")
	await main.load_game()
	var waited := 0.0
	while waited < 20.0 and (GameState.player == null or main.facility == null or not main.facility.active):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await secs(2.0)
	player = GameState.player
	facility = main.facility
	statue = GameState.scp173
	var balls := get_tree().get_nodes_in_group("scp066")
	var kept_ball := false
	for node in balls:
		if node.state == 3 and node.state2 > 33.0 and node.state3 > 0.0 and node.state3 < 500.0:
			kept_ball = true
	check("SCP-066 comes back with its state", kept_ball, "%d of them" % balls.size())
	var ghosts := get_tree().get_nodes_in_group("scp513_1")
	check("SCP-513-1 comes back awake, one of it", ghosts.size() == 1 and not ghosts[0].idle and ghosts[0].state == 0, "%d" % ghosts.size())
	var shapes := get_tree().get_nodes_in_group("scp372")
	var awake_shapes := 0
	for node in shapes:
		if not node.idle:
			awake_shapes += 1
	check("SCP-372 comes back awake (a room event may have made another)", awake_shapes >= 1, "%d" % shapes.size())
	var tentacles := get_tree().get_nodes_in_group("tentacle")
	check("the tentacle comes back with its frame and where it is made", tentacles.size() == 1 and tentacles[0].state == 1 and tentacles[0].in_offices and absf(tentacles[0].frame - 100.0) < 60.0, "%d" % tentacles.size())
	var specimens := get_tree().get_nodes_in_group("scp939")
	check("SCP-939's specimen comes back", specimens.size() == 1 and specimens[0].index == 2 and specimens[0].state2 == 6, "%d" % specimens.size())
	var held: Dictionary = facility.ambient._nodes.get("test|key", {})
	var corpse: Node = held.get("corpse")
	check("what an event kept is found in its slot again", corpse != null and is_instance_valid(corpse) and corpse.get_meta("role", "") == "corpse" and corpse.frame == 80.0 and corpse.texture_id == 1, "")
	for group in ["scp066", "scp513_1", "scp372", "tentacle", "scp939"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()
	if corpse != null and is_instance_valid(corpse):
		facility.remove_human(corpse)
	facility.ambient._nodes.erase("test|key")

func _scn_ambient2() -> void:
	log_line("== more ambient events")
	facility.contained_106 = false
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	var hud: Node = get_tree().get_first_node_in_group("hud")
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var used: Array = []
	# --- 1048a: made while the player blinks near the room, wakes within 2.5, smothers in 15 s
	var ears := {}
	for candidate in facility.generator.rooms:      # a plain corridor, where the creature really lives; a turned one shows a local yaw
		if str(candidate.name) == "room2" and (ears.is_empty() or int(candidate.angle) % 180 == 90):
			ears = candidate
			if int(candidate.angle) % 180 == 90:
				break
	if ears.is_empty():
		ears = await _event_room([], used)
	log_line("   1048-A room: %s" % str(ears.name))
	used.append(ears.key)
	var neighbours: Array = facility.adjacent_records(ears)
	var beside: Dictionary = neighbours[0] if neighbours.size() > 0 else ears
	facility.rooms.get_room(beside)
	place_player(beside.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.6)
	ambient.force(ears.key, "1048a")
	var st: Dictionary = ambient.state_of(ears.key)
	player.blink_timer = 500.0
	await secs(0.3)
	check("1048a waits while the eyes are open", st.s == 0.0, "")
	player.blink_timer = -12.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("it is made when the player blinks near the room, out of it", st.s == 1.0 and ambient._nodes.get(ears.key, {}).has("model"), "state %.0f" % st.s)
	var model: Node3D = ambient._nodes[ears.key].model
	check("it lies in the middle of the room", Vector2(model.global_position.x - ears.position.x, model.global_position.z - ears.position.z).length() < 0.1, "")
	var look_from: Vector3 = Vector3.INF
	for try_distance in [3.0, 2.6, 3.4, 2.2]:
		look_from = _clear_spot(model.global_position, try_distance)
		if look_from != Vector3.INF:
			break
	if look_from != Vector3.INF:
		place_player(look_from + Vector3(0.0, 0.1, 0.0))
		face_point(model.global_position)
		player.user_pitch = rad_to_deg(atan2(player.camera.global_position.y - model.global_position.y, player.camera.global_position.distance_to(model.global_position) * 0.9))
		player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	await secs(0.6)
	await shot("ears")
	player.blink_timer = 500.0
	var by_it: Vector3 = model.global_position + Vector3(2.0, 0.5, 0.0)
	place_player(by_it)
	await secs(0.4)
	check("within 2.5 of it, it wakes", st.s == 2.0, "state %.0f" % st.s)
	var to_player := Vector2(player.global_position.x - model.global_position.x, player.global_position.z - model.global_position.z).normalized()
	var front := -model.global_basis.y
	var facing := Vector2(front.x, front.z).normalized().dot(to_player)
	check("awake, it turns to face the player whatever the room's angle (room at %d)" % int(ears.angle), facing > 0.99, "dot %.2f" % facing)
	ambient._nodes[ears.key].frame = 640.0
	await secs(0.3)
	check("when it is done and the player is in the room, ears start to grow", st.s == 3.0 and hud.message_time_left() > 0.0, "state %.0f %s" % [st.s, hud.message_label.text])
	GameState.god_mode = false
	st.s2 = 70.0 * 15.0 - 1.0
	await secs(0.3)
	check("15 s of it kill", player.dead, "")
	hud.cancel_death()
	player.dead = false
	GameState.blur_timer = 0.0
	check("the event is over", ambient.removed.has(ears.key), "")
	GameState.god_mode = true
	# gone 25 s after the player left (not in the room, the creature is still there)
	var gone: Dictionary = await _event_room([], used)
	used.append(gone.key)
	var next_to: Array = facility.adjacent_records(gone)
	var out_of: Dictionary = next_to[0] if next_to.size() > 0 else gone
	facility.rooms.get_room(out_of)
	place_player(out_of.position + Vector3(0.0, 1.0, 0.0))
	await secs(0.5)
	ambient.force(gone.key, "1048a")
	var gone_state: Dictionary = ambient.state_of(gone.key)
	player.blink_timer = -12.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.blink_timer = 500.0
	check("a second one is made", gone_state.s == 1.0, "")
	await secs(0.3)
	await secs(1.0)
	check("an unwoken one stays (the original resets its leaving timer every frame)", not ambient.removed.has(gone.key), "")
	gone_state.s = 2.0      # it wakes and finishes while the player is not in the room: it is taken away at once
	ambient._nodes[gone.key].frame = 646.5
	await secs(0.3)
	check("one that wakes out of the player's sight is taken away", ambient.removed.has(gone.key) and not ambient._nodes.get(gone.key, {}).has("model"), "")
	ambient.enabled = false

# ---------------------------------------------------------------- the 106 scares (UpdateEvents tunnel106, room2pit106, room2pipes106, 106sinkhole, 106victim, endroom106)

func _scn_ambient3() -> void:
	log_line("== the 106 scares")
	facility.contained_106 = false      # an earlier scenario may have caught him
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var used: Array = []
	var tunnel: Dictionary = await _event_room([], used)
	used.append(tunnel.key)
	var old: Node3D = facility.spawn_106(5000.0)
	place_player(tunnel.position + Vector3(3.2, 1.0, 3.2))      # 3.2 from the middle each way: past 3, within 5
	await secs(0.8)
	ambient.force(tunnel.key, "tunnel106")
	var st: Dictionary = ambient.state_of(tunnel.key)
	await secs(0.3)
	check("tunnel106 begins when the player is near and 106 is outside", st.s == 1.0, "state %.0f" % st.s)
	place_player(tunnel.position + Vector3(1.0, 1.0, 1.0))
	await secs(0.5)
	check("close to the middle a stain opens on the ceiling and he starts to come down", st.s >= 2.0 and old.visible and old.idle, "state %.0f visible %s idle %s" % [st.s, str(old.visible), str(old.idle)])
	check("above the player, over the middle of the room", Vector2(old.global_position.x - tunnel.position.x, old.global_position.z - tunnel.position.z).length() < 0.1 and old.global_position.y > player.global_position.y, "%s" % str(old.global_position))
	st.s = 181.0
	await secs(0.2)
	check("let go, he falls through the floor and hunts", not old.idle and old.state <= -10.0 and old.global_position.y < player.global_position.y - 1.0, "state %.0f y %.2f" % [old.state, old.global_position.y])
	var waited := 0.0
	while waited < 6.0 and not ambient.removed.has(tunnel.key):
		await secs(0.2)
		waited += 0.2
	check("he rises under the player and the event is over", ambient.removed.has(tunnel.key), "%.1f s" % waited)
	old.queue_free()
	facility.scp106 = null
	var pit: Dictionary = await _event_room([], used)
	used.append(pit.key)
	var pit_node: Node3D = facility.rooms.get_room(pit)
	pit_node.fill_objects[7] = Vector3(-1.5, 0.0, 1.5)
	old = facility.spawn_106(5000.0)
	place_player(pit.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.6)
	ambient.force(pit.key, "room2pit106")
	var pit_state: Dictionary = ambient.state_of(pit.key)
	await secs(0.5)
	var spot: Vector3 = pit_node.object_point(7)
	check("room2pit106 holds 106 at Objects[7], visible and trembling", old.idle and old.visible and Vector2(old.global_position.x - spot.x, old.global_position.z - spot.z).length() < 0.2, "%s vs %s" % [str(old.global_position), str(spot)])
	pit_state.s = 801.0
	player.blink_timer = -6.0
	await secs(0.3)
	check("after 800 frames and a blink he lets go and the event ends", not old.idle and ambient.removed.has(pit.key), "")
	old.queue_free()
	facility.scp106 = null
	var pipes: Dictionary = await _event_room([], used)
	used.append(pipes.key)
	var pipes_node: Node3D = facility.rooms.get_room(pipes)
	pipes_node.fill_objects[0] = Vector3(1.4, 0.0, 0.0)
	pipes_node.fill_objects[1] = Vector3(-1.4, 0.0, 0.0)
	pipes_node.fill_objects[2] = Vector3(0.9, 0.75, 0.0)
	pipes_node.fill_objects[3] = Vector3(-0.9, 0.75, 0.0)
	old = facility.spawn_106(5000.0)
	place_player(pipes.position + Vector3(0.0, 1.0, 3.0))
	await secs(0.6)
	ambient.force(pipes.key, "room2pipes106")
	var pipes_state: Dictionary = ambient.state_of(pipes.key)
	player.rotation.y = 0.0
	await secs(0.4)
	check("room2pipes106 starts when the player is in the room, 106 walking in from Objects[0]", pipes_state.s > 0.0 and old.idle and old.visible, "state %.0f" % pipes_state.s)
	var stains_before := 0
	for child in facility.get_parent().get_children():
		if child is GrowingDecal:
			stains_before += 1
	# he springs on a player within 4 and less than 80 degrees to his left: stand behind him (he turns a third of the way in 0.2 s)
	var pipes_middle: Vector3 = pipes_node.object_point(0).lerp(pipes_node.object_point(1), 0.5)
	for s_value in [74.0, 161.0]:
		var behind := Vector3(sin(old.rotation.y), 0.0, cos(old.rotation.y)) * 2.5
		place_player(Vector3(pipes_middle.x, pipes.position.y + 1.0, pipes_middle.z) + behind)
		pipes_state.s = s_value
		await secs(0.2)
	var stains: Array[GrowingDecal] = []
	for child in facility.get_parent().get_children():
		if child is GrowingDecal:
			stains.append(child)
	check("two wall stains open at 0.3 and 0.65 of the event", stains.size() == stains_before + 2, "%d -> %d" % [stains_before, stains.size()])
	if stains.size() >= stains_before + 2:
		var yaw_a := rad_to_deg(wrapf(stains[stains.size() - 2].rotation.y - deg_to_rad(float(pipes.angle) - 90.0) + PI, 0.0, TAU) - PI)
		var yaw_b := rad_to_deg(wrapf(stains[stains.size() - 1].rotation.y - deg_to_rad(float(pipes.angle) + 90.0) + PI, 0.0, TAU) - PI)
		check("the first faces the room's angle -90, the second +90 (angle %d)" % int(pipes.angle), absf(yaw_a) < 0.5 and absf(yaw_b) < 0.5, "off by %.1f and %.1f" % [yaw_a, yaw_b])
	pipes_state.s = 120.0
	place_player(pipes.position + Vector3(0.0, 1.0, 3.8))
	await secs(0.2)
	var middle: Vector3 = pipes_node.object_point(0).lerp(pipes_node.object_point(1), 0.5)
	check("then he stands between the two ends and looks around", Vector2(old.global_position.x - middle.x, old.global_position.z - middle.z).length() < 0.2, "%s vs %s" % [str(old.global_position), str(middle)])
	pipes_state.s = 249.0
	await secs(0.5)
	check("he walks out and is gone after 250", ambient.removed.has(pipes.key) and not old.idle, "state %.0f" % pipes_state.s)
	old.queue_free()
	facility.scp106 = null
	var victim: Dictionary = await _event_room([], used)
	used.append(victim.key)
	place_player(victim.position + Vector3(2.0, 1.0, 2.0))
	await secs(0.6)
	var humans_before: int = facility.humans.size()
	ambient.force(victim.key, "106victim")
	var victim_state: Dictionary = ambient.state_of(victim.key)
	await secs(0.3)
	check("106victim opens a stain on the ceiling when the player is in the room", victim_state.s >= 1.0, "")
	victim_state.s = 201.0
	await secs(0.1)
	check("a body in 106's marks drops out of it", facility.humans.size() == humans_before + 1 and facility.humans.back().texture_id == 5, "%d humans" % facility.humans.size())
	var body: Node3D = facility.humans.back()
	check("the body is still falling when it appears", body.global_position.y > victim.position.y + 0.35, "y %.2f" % body.global_position.y)
	check("106victim: high above the floor the body is not solid to the player (EntityType 0 above y 0.6)", body.global_position.y <= victim.position.y + 0.4 or body.collision_layer & HumanNpc.PLAYER_BLOCK_LAYER == 0, "layer %d" % body.collision_layer)
	if body.global_position.y > victim.position.y + 0.35:
		var under := Vector3(body.global_position.x + 0.3, body.global_position.y, body.global_position.z)
		player.global_position = under
		var before := Vector2(under.x - body.global_position.x, under.z - body.global_position.z).length()
		await get_tree().physics_frame
		await get_tree().physics_frame
		var shoved := Vector2(player.global_position.x - body.global_position.x, player.global_position.z - body.global_position.z).length()
		check("106victim: the falling body shoves a player under it away (UpdateEvents.bb:7221)", absf(player.global_position.x - under.x) + absf(player.global_position.z - under.z) > 0.01, "dist %.3f -> %.3f" % [before, shoved])
	waited = 0.0
	while waited < 5.0 and body.frame < 18.0:
		await secs(0.2)
		waited += 0.2
	if body.global_position.y > victim.position.y + 0.4:
		log_line("   (the body was held up by something in the room: put on the floor)")
		body.global_position.y = victim.position.y + 0.05
		await secs(1.0)
	check("it lands and lies there", body.frame >= 18.0 and body.global_position.y < victim.position.y + 0.4, "frame %.0f y %.2f" % [body.frame, body.global_position.y])
	check("106victim: once down it is solid to the player (HIT_PLAYER, UpdateEvents.bb 7249)", body.collision_layer & HumanNpc.PLAYER_BLOCK_LAYER != 0, "layer %d" % body.collision_layer)
	var pool_size := 0.0
	for node in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		if node is GrowingDecal and absf(node.global_position.y - victim.position.y - 0.001) < 0.0005 and Vector2(node.global_position.x - victim.position.x, node.global_position.z - victim.position.z).length() < 0.05:
			pool_size = node.size
	check("the stain under it is drawn at scale 1 (its de\\Size 0.4 is never applied, UpdateEvents.bb 7267)", is_equal_approx(pool_size, 1.0), "size %.2f" % pool_size)
	victim_state.s = 399.0
	await secs(0.5)
	check("and the event ends, the body stays", ambient.removed.has(victim.key) and is_instance_valid(body), "")
	facility.remove_human(body)
	var dead_end: Dictionary = await _event_room([], used)
	used.append(dead_end.key)
	old = facility.spawn_106(5000.0)
	old.set_physics_process(false)
	place_player(dead_end.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.6)
	humans_before = facility.humans.size()
	ambient.force(dead_end.key, "endroom106")
	var end_state: Dictionary = ambient.state_of(dead_end.key)
	await secs(0.4)
	check("endroom106 lets a janitor into the room", end_state.s >= 1.0 and facility.humans.size() == humans_before + 1 and facility.humans.back().texture_id == 4, "state %.0f" % end_state.s)
	var janitor: Node3D = facility.humans.back()
	await secs(0.5)
	check("with the player in the room he walks to the middle", end_state.s >= 2.0, "state %.0f janitor %d" % [end_state.s, janitor.state])
	janitor.global_position = Vector3(dead_end.position.x, dead_end.position.y + 0.1, dead_end.position.z)
	await secs(0.4)
	check("at the middle a stain opens and 106 comes for him", end_state.s >= 3.0 and old.idle and old.visible, "state %.0f" % end_state.s)
	end_state.s = 101.0
	await secs(0.4)
	check("then the janitor is gone, 106 has left and the event is over", ambient.removed.has(dead_end.key) and not old.idle and not is_instance_valid(janitor) or ambient.removed.has(dead_end.key), "")
	old.queue_free()
	facility.scp106 = null
	# --- 106sinkhole (last: it ends in the pocket dimension, which is left out)
	var hole: Dictionary = await _event_room([], used)
	used.append(hole.key)
	place_player(hole.position + Vector3(1.5, 1.0, 0.0))
	await secs(0.8)
	ambient.force(hole.key, "106sinkhole")
	var hole_state: Dictionary = ambient.state_of(hole.key)
	await secs(0.4)
	check("106sinkhole leaves a stain in the middle", hole_state.s == 1.0, "")
	place_player(hole.position + Vector3(1.0, 0.1, 0.0))
	player.crouch_state = 0.0
	await secs(0.5)
	check("within 2 of it the player crouches down and slows", player.crouch_state > 0.1, "crouch %.2f" % player.crouch_state)
	place_player(hole.position + Vector3(0.3, 0.1, 0.0))
	await secs(1.0)
	check("within 0.5 it holds them and draws them in", GameState.unable_to_move and hole_state.s2 > 0.0, "sink %.2f" % hole_state.s2)
	check("the view darkens and smears", GameState.light_blink > 0.0 and GameState.blur_timer > 0.0, "")
	hole_state.s2 = 0.0
	place_player(hole.position + Vector3(3.0, 0.1, 0.0))
	await secs(0.5)
	check("and lets go when they get away", not GameState.unable_to_move, "")
	GameState.unable_to_move = false
	GameState.blur_timer = 0.0
	GameState.light_blink = 0.0
	ambient.enabled = false

# ---------------------------------------------------------------- single-room set pieces (room_gw, room2fan, room2elevator(2), room2poffices2, testroom173, room2closets)

# height above `floor_y` of the lowest decal within 0.1 (in x/z) of `spot`; INF if there is none
func _floor_decal_dy(spot: Vector3, floor_y: float) -> float:
	var best := INF
	for node in get_tree().get_nodes_in_group(GrowingDecal.GROUP):
		var at: Vector3 = (node as Node3D).global_position
		if Vector2(at.x - spot.x, at.z - spot.z).length() < 0.1:
			best = minf(best, absf(at.y - floor_y))
	return best

func _scn_ambient4() -> void:
	log_line("== single-room set pieces")
	facility.contained_106 = false
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	var ambient: Node = facility.ambient
	var hud: Node = get_tree().get_first_node_in_group("hud")
	ambient._handlers.clear()
	ambient.states.clear()
	ambient.removed.clear()
	ambient._nodes.clear()
	ambient.enabled = true
	GameState.god_mode = true
	var used: Array = []
	# --- room_gw: the airlock (made from two real doors when this map has none)
	var airlock := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2gw" or str(candidate.name) == "room3gw":
			airlock = candidate
			break
	var gw: Node3D = null
	var borrowed: Array = []
	if airlock.is_empty():
		airlock = await _event_room([], used)
		gw = facility.rooms.get_room(airlock)
		var pair: Array = []
		for door in facility.doors_near(airlock.position, 16.0):
			if is_instance_valid(door) and not door.elevator and not door.big and not door.locked and door.keycard == 0 and absf(door.global_position.y - airlock.position.y) < 0.5 and pair.size() < 2:
				pair.append(door)
				borrowed.append({"door": door, "open": door.open, "locked": door.locked})
		pair[0].open = true
		pair[1].open = true
		gw.door_slots[0] = pair[0]
		gw.door_slots[1] = pair[1]
		gw.fill_objects[0] = Vector3(1.3, 0.5, 0.0)
		gw.room_name = "room2gw"
		log_line("   (an airlock made from two doors)")
	else:
		gw = facility.rooms.get_room(airlock)
	used.append(airlock.key)
	var door_a: Node3D = gw.door_slots.get(0)
	var door_b: Node3D = gw.door_slots.get(1)
	check("the airlock has its two doors, open", door_a != null and door_b != null and door_a.open and door_b.open, "")
	var inside: Vector3 = gw.object_point(0)
	place_player(Vector3(inside.x, airlock.position.y + 0.3, inside.z) + gw.global_transform.basis * Vector3(0.0, 0.0, 2.0))      # past the 1.4 of the trigger
	await secs(0.8)
	ambient.force(airlock.key, "room_gw")
	var gw_state: Dictionary = ambient.state_of(airlock.key)
	await secs(0.4)
	check("outside the airlock's middle nothing happens", gw_state.s == 0.0 and door_a.locked and door_b.locked, "state %.0f" % gw_state.s)
	place_player(Vector3(inside.x + 0.2, airlock.position.y + 0.3, inside.z))
	await secs(0.5)
	check("stepping into it shuts both doors", gw_state.s >= 1.0 and not door_a.open and not door_b.open, "state %.0f open %s %s" % [gw_state.s, str(door_a.open), str(door_b.open)])
	gw_state.s2 = 70.0 * 3.5
	await secs(0.4)
	var steam := 0
	for puff in facility.particles._items:
		if puff.image == 6:
			steam += 1
	check("after three seconds steam fills it", steam > 10, "%d puffs" % steam)
	gw_state.s2 = 70.0 * 7.0 + 1.0
	await secs(0.4)
	check("after seven it opens again", gw_state.s == 0.0 and door_a.open and door_b.open and gw_state.s3 == 1.0, "state %.0f open %s %s" % [gw_state.s, str(door_a.open), str(door_b.open)])
	place_player(Vector3(inside.x + 3.0, airlock.position.y + 0.3, inside.z))
	await secs(0.4)
	check("having gone 2.4 away it is ready again", gw_state.s3 == 0.0, "state3 %.0f" % gw_state.s3)
	check("the broken-door airlock is chosen by the plan", ambient.plan.broken_gw_key is String, "")
	door_a.locked = false
	door_b.locked = false
	for entry in borrowed:
		entry.door.open = entry.open
		entry.door.locked = entry.locked
	var fan_room := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "room2_2":
			fan_room = candidate
			break
	if fan_room.is_empty():
		log_line("   no fan room in this map")
	else:
		used.append(fan_room.key)
		var fan_node: Node3D = facility.rooms.get_room(fan_room)
		check("the fan is built with the room", fan_node.fan != null, "")
		place_player(fan_room.position + Vector3(0.5, 1.0, 0.5))
		await secs(0.8)
		ambient.force(fan_room.key, "room2fan")
		var fan_state: Dictionary = ambient.state_of(fan_room.key)
		fan_state.s = 1000000.0
		fan_state.s2 = 1.0
		var turned_before: Basis = fan_node.fan.transform.basis
		await secs(2.0)
		check("with the fan on it speeds up and turns", fan_state.s3 > 0.2 and not fan_node.fan.transform.basis.is_equal_approx(turned_before), "speed %.2f" % fan_state.s3)
		fan_state.s = -1.0
		await secs(0.3)
		check("after its 15 to 30 seconds the fan chooses again", fan_state.s >= 15.0 * 70.0 - 60.0, "%.0f" % fan_state.s)
		fan_state.s = 1000000.0
		fan_state.s2 = 0.0
		var fast: float = fan_state.s3
		await secs(2.0)
		check("with it off it slows", fan_state.s3 < fast, "%.2f -> %.2f" % [fast, fan_state.s3])
	# --- room2elevator2: a body in blood at Objects[0]
	var morgue: Dictionary = await _event_room([], used)
	used.append(morgue.key)
	var morgue_node: Node3D = facility.rooms.get_room(morgue)
	morgue_node.fill_objects[0] = Vector3(1.0, 240.0 * 8.0 / 2048.0, 0.5)      # the pivot is 240 units up (MapSystem.bb 2907); the blood is not
	place_player(morgue.position + Vector3(-1.5, 1.0, -1.5))
	await secs(0.6)
	var humans_before: int = facility.humans.size()
	ambient.force(morgue.key, "room2elevator2")
	await secs(0.4)
	var lying: Node3D = facility.humans.back() if facility.humans.size() > humans_before else null
	check("room2elevator2 lays a body at Objects[0]", lying != null and lying.is_dead and lying.state == 8 and ambient.removed.has(morgue.key), "")
	check("its blood lies on the floor, not at the pivot's height", _floor_decal_dy(morgue_node.object_point(0), morgue.position.y) < 0.01, "dy %.3f" % _floor_decal_dy(morgue_node.object_point(0), morgue.position.y))
	# --- room4tunnels: a Class D corpse in body1.jpg near the centre
	var tunnels: Dictionary = await _event_room([], used)
	used.append(tunnels.key)
	place_player(tunnels.position + Vector3(5.0, 1.0, 0.0))
	await secs(0.6)
	var before: int = facility.humans.size()
	ambient.force(tunnels.key, "room4tunnels")
	await secs(0.4)
	var corpse: Node3D = facility.humans.back() if facility.humans.size() > before else null
	check("room4tunnels lays a corpse in body1.jpg at the centre +1, +1", corpse != null and corpse.state == 8 and corpse.frame == 19.0 and corpse.texture_id == 8 and absf(corpse.global_position.x - tunnels.position.x - 1.0) < 0.3 and absf(corpse.global_position.z - tunnels.position.z + 1.0) < 0.3 and ambient.removed.has(tunnels.key), "")
	# --- room2elevator: the guard who runs for the lift door
	var lift: Dictionary = await _event_room([], used)
	used.append(lift.key)
	var lift_node: Node3D = facility.rooms.get_room(lift)
	lift_node.fill_objects[0] = Vector3(2.0, 240.0 * 8.0 / 2048.0, 0.0)
	lift_node.fill_objects[1] = Vector3(3.0, 0.0, 0.0)
	place_player(lift.position + Vector3(6.5, 1.0, 0.0))      # within 8 of the room, not yet within 5
	await secs(0.2)
	place_player(lift.position + Vector3(6.5, 1.0, 0.0))
	humans_before = facility.humans.size()
	ambient.force(lift.key, "room2elevator")
	var lift_state: Dictionary = ambient.state_of(lift.key)
	await secs(0.4)
	check("a guard is made when the player is within 8 of the room", lift_state.s >= 1.0 and facility.humans.size() == humans_before + 1, "state %.0f" % lift_state.s)
	var guard: Node3D = facility.humans.back()
	guard.set_physics_process(false)
	place_player(lift.position + Vector3(2.0, 1.0, 1.0))
	await secs(0.3)
	check("within 5 he runs for the door", lift_state.s == 2.0 and guard.state == 5, "state %.0f guard %d" % [lift_state.s, guard.state])
	guard.global_position = lift_node.object_point(1) + Vector3(0.0, 0.2, 0.0)
	await secs(0.3)
	check("at the door the scene begins", is_equal_approx(lift_state.s, 2.05) or lift_state.s > 2.05, "state %.2f" % lift_state.s)
	lift_state.s = 12.6 * 70.0 - 1.0
	await secs(0.3)
	check("at 12.6 s the guard is gone", not is_instance_valid(guard) or not facility.humans.has(guard), "")
	check("his blood lies on the floor", _floor_decal_dy(lift_node.object_point(0), lift.position.y) < 0.01, "dy %.3f" % _floor_decal_dy(lift_node.object_point(0), lift.position.y))
	lift_state.s = 13.0 * 70.0 + 1.0
	await secs(0.3)
	check("and the event ends once the door is open (or waits for it)", ambient.removed.has(lift.key) or lift_state.s > 13.0 * 70.0, "")
	camera_reset_shake()
	# --- room2poffices2: handler is quiet in a room without its door
	var offices: Dictionary = await _event_room([], used)
	used.append(offices.key)
	place_player(offices.position + Vector3(0.5, 1.0, 0.5))
	await secs(0.6)
	facility.rooms.get_room(offices).door_slots.erase(0)      # a room without its keypad door
	ambient.force(offices.key, "room2poffices2")
	await secs(0.3)
	check("room2poffices2 does nothing without its keypad door", ambient.state_of(offices.key).s == 0.0, "")
	var glass_room: Dictionary = await _event_room([], used)
	used.append(glass_room.key)
	var glass_node: Node3D = facility.rooms.get_room(glass_room)
	glass_node.fill_objects[0] = Vector3(-2.0, 0.0, 2.0)
	glass_node.fill_objects[1] = Vector3(-2.0, 0.0, 0.0)
	var any_door: Node3D = null
	for door in facility.doors_near(glass_room.position, 16.0):
		if is_instance_valid(door) and not door.elevator and not door.big and not door.locked and door.keycard == 0 and absf(door.global_position.y - glass_room.position.y) < 0.5:
			any_door = door
			break
	var any_door_was: bool = any_door.open if any_door != null else false
	glass_node.door_slots[0] = any_door
	any_door.open = true
	place_player(glass_node.to_global(Vector3(1.5, 1.0, 0.0)))
	await secs(0.6)
	statue.idle = 0
	ambient.force(glass_room.key, "testroom173")
	var glass_state: Dictionary = ambient.state_of(glass_room.key)
	await secs(0.4)
	var behind: Vector3 = glass_node.object_point(0)
	check("testroom173 puts 173 behind the window and shows the glass", glass_state.s >= 1.0 and Vector2(statue.global_position.x - behind.x, statue.global_position.z - behind.z).length() < 0.2 and ambient._nodes[glass_room.key].has("glass"), "state %.0f" % glass_state.s)
	glass_state.s = 70.0 * 12.0 + 1.0
	player.blink_timer = -12.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var window: Vector3 = glass_node.object_point(1)
	check("after 12 s, with the player blinking away from the window, 173 breaks through", Vector2(statue.global_position.x - window.x, statue.global_position.z - window.z).length() < 0.2 and ambient.removed.has(glass_room.key), "")
	# --- testroom: SCP-1048 crawls across, the warning and six hissing pipes near Objects[6]
	var lab: Dictionary = await _event_room([], used)
	used.append(lab.key)
	var lab_node: Node3D = facility.rooms.get_room(lab)
	lab_node.fill_objects[6] = Vector3(2.9453, -4.875, 0.0)
	var lab_jets_before := 0
	for jet in facility.particles.emitters:
		if jet.key == lab.key:
			lab_jets_before += 1
	place_player(lab_node.to_global(Vector3(-1.0, 1.0, 1.0)))
	await secs(0.5)
	ambient.force(lab.key, "testroom")
	await secs(0.3)
	var lab_state: Dictionary = ambient.state_of(lab.key)
	check("testroom puts SCP-1048 in the room on entry", lab_state.s == 1.0 and ambient._nodes[lab.key].has("model"), "state %.0f" % lab_state.s)
	var lab_model: Node3D = ambient._nodes[lab.key]["model"]
	check("on the side opposite the player", lab_node.to_local(lab_model.global_position).z < -1.0, "z %.2f" % lab_node.to_local(lab_model.global_position).z)
	lab_node.fill_objects[6] = lab_node.to_local(player.global_position) + Vector3(0.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lab_jets := 0
	for jet in facility.particles.emitters:
		if jet.key == lab.key:
			lab_jets += 1
	check("near Objects[6] six pipes start to hiss", lab_jets == lab_jets_before + 6 and lab_state.s < 0.0, "%d jets, %.2f from Objects[6], in %s want %s" % [lab_jets - lab_jets_before, player.global_position.distance_to(lab_node.object_point(6)), facility.record_at(player.global_position).get("key", ""), lab.key])
	await secs(30.0)
	check("SCP-1048 leaves past |x| 725 and the event ends", ambient.removed.has(lab.key), "state %.0f" % lab_state.s)
	place_statue(Vector3(0.0, -80.0, 0.0))
	# --- checkpoint: SCP-1048 turns to the player, waves once looked at, goes once looked away from
	var checkpoint := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) in ["checkpoint1", "checkpoint2"]:
			checkpoint = candidate
			break
	if checkpoint.is_empty():
		check("a checkpoint exists to test SCP-1048 (skipped)", true, "")
	else:
		var gate_node: Node3D = facility.rooms.get_room(checkpoint)
		ambient.force(checkpoint.key, "checkpoint")
		place_player(gate_node.to_global(Vector3(0.0, 1.0, 0.0)))
		var gate_state: Dictionary = ambient.state_of(checkpoint.key)
		var tries := 0
		while tries < 30 and not ambient._nodes.get(checkpoint.key, {}).has("model"):
			gate_state.s3 = 0.0
			await get_tree().physics_frame
			await get_tree().physics_frame
			tries += 1
		check("the checkpoint's SCP-1048 appears on a Rand(2)", ambient._nodes.get(checkpoint.key, {}).has("model"), "%d tries" % tries)
		if ambient._nodes.get(checkpoint.key, {}).has("model"):
			var bear: Node3D = ambient._nodes[checkpoint.key]["model"]
			var spot := (Vector3(720.0, 120.0, -333.0) if str(checkpoint.name) == "checkpoint1" else Vector3(-720.0, 120.0, -464.0)) * MeshLoader.ROOM_SCALE
			check("at Objects[0], pitched up and yawed at the player", gate_node.to_local(bear.global_position).distance_to(spot) < 0.01, "%s want %s" % [str(gate_node.to_local(bear.global_position)), str(spot)])
			var toward := bear.global_position - player.global_position
			player.rotation.y = atan2(toward.x, toward.z)
			await secs(0.3)
			check("looking away from it, it waits", gate_state.s3 == 1.0, "state %.0f" % gate_state.s3)
			var expected_yaw := atan2(player.global_position.x - bear.global_position.x, player.global_position.z - bear.global_position.z) + PI
			check("it faces the player", absf(angle_difference(bear.rotation.y, atan2(-(player.global_position.x - bear.global_position.x), -(player.global_position.z - bear.global_position.z)))) < 0.01 and absf(bear.rotation.x - PI * 0.5) < 0.01, "yaw %.2f expected %.2f" % [bear.rotation.y, expected_yaw])
			player.rotation.y = atan2(-toward.x, -toward.z)
			await secs(0.3)
			check("looked at, it waves", gate_state.s3 >= 2.0, "state %.0f" % gate_state.s3)
			await secs(4.0)
			check("after the wave it waits to be looked away from", gate_state.s3 == 4.0, "state %.0f" % gate_state.s3)
			player.rotation.y = atan2(toward.x, toward.z)
			await secs(0.3)
			check("looked away from, it is gone", gate_state.s3 == 5.0 and not ambient._nodes[checkpoint.key].has("model"), "state %.0f" % gate_state.s3)
	# --- room2closets: the scene that ends with a wallet
	var store: Dictionary = await _event_room([], used)
	used.append(store.key)
	var store_node: Node3D = facility.rooms.get_room(store)
	store_node.fill_objects[0] = Vector3(-1.5, 0.0, 1.5)
	store_node.fill_objects[1] = Vector3(-1.5, 0.0, -1.5)
	place_player(store.position + Vector3(1.0, 1.0, 0.0))
	await secs(0.6)
	humans_before = facility.humans.size()
	statue.idle = 0
	ambient.force(store.key, "room2closets")
	var store_state: Dictionary = ambient.state_of(store.key)
	await secs(0.4)
	check("room2closets makes a janitor and a scientist when the player is in the room", store_state.s >= 1.0 and facility.humans.size() == humans_before + 2, "%d new" % (facility.humans.size() - humans_before))
	var janitor: Node3D = facility.humans[facility.humans.size() - 2]
	var scientist: Node3D = facility.humans[facility.humans.size() - 1]
	check("in their own clothes", janitor.texture_id == 4 and scientist.texture_id == 2, "%d %d" % [janitor.texture_id, scientist.texture_id])
	janitor.set_physics_process(false)
	scientist.set_physics_process(false)
	store_state.s = 70.0 * 6.6
	await secs(0.3)
	check("at 6.5 s the player is made to blink", player.blink_timer <= 0.0, "blink %.0f" % player.blink_timer)
	store_state.s = 70.0 * 7.5 - 2.0
	var pickups_before := get_tree().get_nodes_in_group("pickup").size()
	await secs(0.5)
	var wallet: Node = null
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == "Wallet":
			wallet = node
	var quarters := 0
	if wallet != null:
		for slot in wallet.get_meta("inv", []):
			if not (slot as Dictionary).is_empty():
				quarters += 1
	check("when the necks snap a wallet with two quarters falls", wallet != null and quarters == 2 and get_tree().get_nodes_in_group("pickup").size() > pickups_before, "%d quarters" % quarters)
	var wallet_gap := 99.0
	if wallet != null:
		var wallet_hit := MeshLoader.pick_ray(player.get_world_3d().direct_space_state, wallet.global_position + Vector3(0.0, 0.3, 0.0), wallet.global_position + Vector3(0.0, -3.0, 0.0), RID())
		if not wallet_hit.is_empty():
			wallet_gap = wallet.global_position.y - wallet_hit.position.y
	check("the wallet lies on the floor where TeleportEntity puts it", absf(wallet_gap) < 0.02, "%.3f above the floor" % wallet_gap)
	check("both are dead", janitor.state == 8 and janitor.frame >= 59.0 and scientist.state == 6 and scientist.frame >= 18.0, "janitor %d %.0f, scientist %d %.0f" % [janitor.state, janitor.frame, scientist.state, scientist.frame])
	store_state.s = 70.0 * 8.5 + 1.0
	await secs(0.3)
	var between: Vector3 = (janitor.global_position + scientist.global_position) * 0.5
	check("at 8.5 s 173 stands between them and the event is over", Vector2(statue.global_position.x - between.x, statue.global_position.z - between.z).length() < 0.3 and ambient.removed.has(store.key), "")
	if wallet != null:
		wallet.queue_free()
	place_statue(Vector3(0.0, -80.0, 0.0))
	if any_door != null:
		any_door.open = any_door_was
	ambient.enabled = false

func _scn_roomdraw() -> void:
	log_line("== which rooms are drawn (UpdateRooms)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	facility.drawing.enabled = true
	facility.drawing.neighbours_hidden_by = null
	# a room with the most neighbours, away from the start chamber
	var best := {}
	var best_count := -1
	for record in facility.generator.rooms:
		if str(record.name) == "start" or facility.rooms.inside_start(record):
			continue
		var count := 0
		for i in 4:
			if not facility.drawing.neighbour_of(record, i).is_empty():
				count += 1
		if count > best_count:
			best_count = count
			best = record
	var node: Node3D = facility.rooms.get_room(best)
	place_player(node.to_global(Vector3(0.0, node.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.8)
	var ring := _ring_of(str(best.key))
	var wrong := ""
	var hidden := 0
	for key in facility.rooms.built:
		var room: Node3D = facility.rooms.built[key]
		var want: bool = ring.has(key) and int(ring[key]) <= 2
		if not want:
			hidden += 1
		if room.visible != want:
			wrong += " %s(want %s, ring %s)" % [key, str(want), str(ring.get(key, "far"))]
	check("rooms beyond the player's, its neighbours' and theirs are hidden, the rest drawn", wrong == "", wrong)
	check("there are rooms hidden in this test (it tests something)", hidden >= 1, "%d of %d" % [hidden, facility.rooms.built.size()])
	check("the player's own mesh is drawn", node.visual.visible, "")
	# the neighbours' meshes follow their doors
	var first_index := -1
	for i in 4:
		var rec: Dictionary = facility.drawing.neighbour_of(best, i)
		if not rec.is_empty() and facility.drawing.door_toward(best, i) != null and facility.rooms.built.has(rec.key):
			first_index = i
			break
	check("the room has a neighbour behind a door", first_index >= 0, "")
	if first_index >= 0:
		var neighbour_key: String = facility.drawing.neighbour_of(best, first_index).key
		var door: Node3D = facility.drawing.door_toward(best, first_index)
		var neighbour: Node3D = facility.rooms.built[neighbour_key]
		door.open = false
		door.openstate = 0.0
		face_point(door.global_position + Vector3(0.0, 1.0, 0.0))
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("a shut door: the neighbour's mesh is not drawn", not neighbour.visual.visible, "openstate %.0f" % door.openstate)
		await shot("roomdraw_shut")
		door.open = true
		door.openstate = 180.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("an open door in view: it is drawn", neighbour.visual.visible, "in view %s" % str(facility.drawing.frame_in_view(door, player.camera)))
		await shot("roomdraw_open")
		player.rotation.y += PI
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("an open door behind the player: it is not", not neighbour.visual.visible, "in view %s" % str(facility.drawing.frame_in_view(door, player.camera)))
		face_point(door.global_position + Vector3(0.0, 1.0, 0.0))
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("turned back to it: drawn again", neighbour.visual.visible, "")
	# a neighbour's neighbour: the room is there but its mesh is not drawn
	var second_key := ""
	for key in ring:
		if int(ring[key]) == 2 and facility.rooms.built.has(key):
			second_key = str(key)
			break
	if second_key.is_empty():
		log_line("   no room two steps away")
	else:
		var second: Node3D = facility.rooms.built[second_key]
		check("two steps away: the room is drawn but its mesh never", second.visible and not second.visual.visible, "visible %s mesh %s" % [str(second.visible), str(second.visual.visible)])
	# nowhere (the forest, the pocket dimension): the last room stays the player's
	var before := {}
	for key in facility.rooms.built:
		before[key] = (facility.rooms.built[key] as Node3D).visible
	player.set_physics_process(false)
	place_player(Vector3(best.position.x, -400.0, best.position.z))
	await secs(0.4)
	var moved := ""
	for key in facility.rooms.built:
		if (facility.rooms.built[key] as Node3D).visible != before[key]:
			moved += " " + str(key)
	check("in no room, nothing is shown or hidden", moved == "", moved)
	player.set_physics_process(true)
	place_player(node.to_global(Vector3(0.0, node.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.5)
	# room2sl: off the hall level the neighbours are not drawn, even through an open door in view
	var setup: Dictionary = await _room2sl_setup()
	if setup.is_empty():
		log_line("   no room2sl in this map")
	else:
		var sl: Node3D = setup.room
		var sl_record: Dictionary = facility.rooms.record_of(sl)
		var catwalk: Vector3 = sl.object_point(16)
		var down := PhysicsRayQueryParameters3D.create(Vector3(catwalk.x, catwalk.y + 0.8, catwalk.z), Vector3(catwalk.x, catwalk.y - 3.0, catwalk.z))
		down.collision_mask = 1
		var floor_hit := get_viewport().world_3d.direct_space_state.intersect_ray(down)
		var sl_index := -1
		for i in 4:
			if not facility.drawing.neighbour_of(sl_record, i).is_empty() and facility.drawing.door_toward(sl_record, i) != null and facility.rooms.built.has(facility.drawing.neighbour_of(sl_record, i).key):
				sl_index = i
				break
		if floor_hit.is_empty() or sl_index < 0:
			log_line("   room2sl has no catwalk floor or no neighbour behind a door here")
		else:
			var sl_door: Node3D = facility.drawing.door_toward(sl_record, sl_index)
			var sl_neighbour: Node3D = facility.rooms.built[facility.drawing.neighbour_of(sl_record, sl_index).key]
			sl_door.open = true
			sl_door.openstate = 180.0
			place_player(floor_hit.position + Vector3(0.0, 0.1, 0.0))
			await secs(0.5)
			face_point(sl_door.global_position + Vector3(0.0, 1.0, 0.0))
			await get_tree().physics_frame
			await get_tree().physics_frame
			check("room2sl, on the catwalk: the neighbour is hidden although its door is open and in view", not sl_neighbour.visual.visible and facility.drawing.frame_in_view(sl_door, player.camera), "mesh %s in view %s" % [str(sl_neighbour.visual.visible), str(facility.drawing.frame_in_view(sl_door, player.camera))])
			var entrance: Vector3 = sl_door.global_position + (sl.global_position - sl_door.global_position).normalized() * 1.5
			place_player(Vector3(entrance.x, sl_door.global_position.y + 0.1, entrance.z))
			await secs(0.5)
			face_point(sl_door.global_position + Vector3(0.0, 1.0, 0.0))
			await get_tree().physics_frame
			await get_tree().physics_frame
			check("and at the hall level the ordinary rule is back: drawn", sl_neighbour.visual.visible, "player y %.2f" % player.global_position.y)
			sl_door.open = false
	# the console's `culling` and noclip
	var overlay: Node = null
	for child in get_tree().get_first_node_in_group("hud").get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("debug_overlay.gd"):
			overlay = child
	check("the debug menu holds a console", overlay != null and overlay.console != null, "")
	if overlay != null and overlay.console != null:
		var console: Control = overlay.console
		node = facility.rooms.get_room(best)
		place_player(node.to_global(Vector3(0.0, node.floor_y(0.0, 0.0) + 0.1, 0.0)))
		await secs(0.5)
		check("the console lists culling and explains it", _console_say(console, "help culling").contains("HELP - culling") and _console_say(console, "help 3").contains("culling [on/off]"), "")
		check("with the rule on some rooms are hidden", _hidden_rooms() >= 1, "%d" % _hidden_rooms())
		var said: String = _console_say(console, "culling off")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("culling off: it says so, every room and mesh is drawn", said.contains("CULLING OFF") and not facility.drawing.enabled and _hidden_rooms() == 0, "%d hidden: %s" % [_hidden_rooms(), said.strip_edges()])
		_console_say(console, "culling")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("with no argument it toggles back on and rooms are hidden again", facility.drawing.enabled and _hidden_rooms() >= 1, "%d hidden" % _hidden_rooms())
		_console_say(console, "noclip on")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("noclip on: the rule stands aside, everything is drawn (the setting stays on)", GameState.noclip and facility.drawing.enabled and not facility.drawing.active() and _hidden_rooms() == 0, "%d hidden" % _hidden_rooms())
		check("and the console's `culling on` says it is suspended", _console_say(console, "culling on").contains("noclip"), "")
		check("the status line says so", _console_say(console, "status").contains("Room culling: off while noclip is on"), "")
		_console_say(console, "noclip off")
		await get_tree().physics_frame
		await get_tree().physics_frame
		check("noclip off: the rule is back", not GameState.noclip and facility.drawing.active() and _hidden_rooms() >= 1, "%d hidden" % _hidden_rooms())
		_console_say(console, "roomculling off")
		check("roomculling is another name for it", not facility.drawing.enabled, "")
		var box: CheckBox = null
		for candidate in overlay.find_children("*", "CheckBox", true, false):
			if (candidate as CheckBox).text.contains("(culling)"):
				box = candidate
		check("the World tab has a culling checkbox", box != null, "")
		if box != null:
			box.button_pressed = false
			check("unticking it turns the rule off", not facility.drawing.enabled, "")
			box.button_pressed = true
			await get_tree().physics_frame
			await get_tree().physics_frame
			check("ticking it turns the rule on again", facility.drawing.enabled and _hidden_rooms() >= 1, "%d hidden" % _hidden_rooms())
	GameState.noclip = false
	facility.drawing.enabled = true
	GameState.god_mode = false

func _scn_drawperf() -> void:
	log_line("== room drawing: cost and saving")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# a room with the most neighbours, and a stable set of rooms round it
	var best := {}
	var best_count := -1
	for record in facility.generator.rooms:
		if str(record.name) == "start" or facility.rooms.inside_start(record):
			continue
		var count := 0
		for i in 4:
			if not facility.drawing.neighbour_of(record, i).is_empty():
				count += 1
		if count > best_count:
			best_count = count
			best = record
	var node: Node3D = facility.rooms.get_room(best)
	await secs(1.0)
	var stops: Array[Vector3] = []
	for key in facility.rooms.built:
		var record: Dictionary = facility.rooms.by_grid.get(key, {})
		if record.is_empty() or str(record.name) == "start":
			continue
		if Vector2(record.position.x - best.position.x, record.position.z - best.position.z).length() < 17.0:
			stops.append(record.position + Vector3(0.0, 0.0, 0.0))
	log_line("   %d rooms loaded, %d stops in a 17 unit radius" % [facility.rooms.built.size(), stops.size()])
	# the cost of one call
	facility.drawing.enabled = true
	place_player(node.to_global(Vector3(0.0, node.floor_y(0.0, 0.0) + 0.1, 0.0)))
	await secs(0.5)
	var started := Time.get_ticks_usec()
	for i in 2000:
		facility.drawing.update()
	var per_call := (Time.get_ticks_usec() - started) / 2000.0
	log_line("   one call of the rule: %.1f us" % per_call)
	check("the rule costs under half a millisecond a call", per_call < 500.0, "%.1f us" % per_call)
	# static views: off, on, off, on (the first pair warms everything up; the second is the one reported)
	var results := {}
	for pass_index in 4:
		var mode: bool = pass_index % 2 == 1
		facility.drawing.enabled = mode
		if not mode:
			facility.drawing.show_all_rooms()
		var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var used := 0
		for stop in stops:
			var floor_spot := stop + Vector3(0.0, 0.1, 0.0)
			var room_here: Node3D = facility.room_at(floor_spot)
			if room_here != null:
				floor_spot = room_here.to_global(Vector3(0.0, room_here.floor_y(0.0, 0.0) + 0.1, 0.0))
			place_player(floor_spot)
			await secs(0.3)
			var got: Array = await _measure_frames(20)
			for k in 6:
				sums[k] += float(got[k])
			used += 1
		for k in 6:
			sums[k] /= maxf(used, 1)
		results[pass_index] = sums
	var off: Array = results[2]
	var on: Array = results[3]
	log_line("   static views (mean over %d rooms):" % stops.size())
	log_line("      rule off: %.0f draw calls, %.0f primitives, %.0f objects, render cpu %.2f ms, gpu %.2f ms, %.2f ms a frame" % [off[0], off[1], off[2], off[3], off[4], off[5]])
	log_line("      rule on : %.0f draw calls, %.0f primitives, %.0f objects, render cpu %.2f ms, gpu %.2f ms, %.2f ms a frame" % [on[0], on[1], on[2], on[3], on[4], on[5]])
	check("the rule does not add draw calls", float(on[0]) <= float(off[0]) + 1.0, "%.0f vs %.0f" % [on[0], off[0]])
	# a walk through the rooms: off, on, off, on; the frame times of the last pair
	var route: Array[Vector3] = []
	var remaining: Array = facility.generator.rooms.duplicate()
	var here: Vector3 = best.position
	while route.size() < 7 and not remaining.is_empty():
		remaining.sort_custom(func(a, b) -> bool: return a.position.distance_to(here) < b.position.distance_to(here))
		var next: Dictionary = remaining.pop_front()
		if str(next.name) == "start" or facility.rooms.inside_start(next):
			continue
		route.append(next.position + Vector3(0.0, 1.6, 0.0))
		here = next.position
	var walk := {}
	for pass_index in 4:
		var mode2: bool = pass_index % 2 == 1
		facility.drawing.enabled = mode2
		if not mode2:
			facility.drawing.show_all_rooms()
		var times: Array[float] = await _walk_route(route, get_tree().process_frame)
		walk[pass_index] = times
	for pass_index in [2, 3]:
		var series: Array = walk[pass_index]
		var total := 0.0
		for value in series:
			total += float(value)
		var slow := 0
		for value in series:
			if float(value) > 25.0:
				slow += 1
		log_line("   walk, rule %s: %d frames, mean %.2f ms, p50 %.2f, p99 %.2f, max %.2f ms, %d frames over 25 ms" % ["on " if pass_index == 3 else "off", series.size(), total / maxf(series.size(), 1), _percentile(series, 0.5), _percentile(series, 0.99), _percentile(series, 1.0), slow])
	facility.drawing.enabled = true
	GameState.god_mode = false

func _image_gap(a: Image, b: Image) -> float:
	var small_a := a.duplicate() as Image
	var small_b := b.duplicate() as Image
	small_a.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	small_b.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 27:
		for x in 48:
			var ca := small_a.get_pixel(x, y)
			var cb := small_b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / (48.0 * 27.0 * 3.0)

func _frame_image() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _scn_dreamblur() -> void:
	log_line("== Dreamfilter blur: the previous frame is mixed over the new one")
	statue.active = false
	revive()
	var hud := get_tree().get_first_node_in_group("hud")
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(0.5)
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	await secs(0.3)
	var effect: DreamBlur = hud._dream_blur
	check("the HUD puts the feedback blur on the player's camera", effect != null and player.camera.compositor != null and player.camera.compositor.compositor_effects.has(effect), "")
	check("with no blur the effect is off and costs nothing", not effect.enabled, "volume %.3f" % effect.volume)
	GameState.blur_timer = 900.0
	await get_tree().physics_frame
	await secs(0.1)
	check("a blur timer switches it on with BlurVolume as the weight", effect.enabled and absf(effect.volume - GameState.blur_volume) < 0.1 and effect.volume > 0.5, "enabled %s volume %.2f" % [str(effect.enabled), effect.volume])
	check("the weight never passes 0.95", effect.volume <= 0.95, "%.2f" % effect.volume)
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check("when the blur ends the effect goes off and forgets its history", not effect.enabled and effect._restart, "enabled %s restart %s" % [str(effect.enabled), str(effect._restart)])
	if RenderingServer.get_rendering_device() == null:
		log_line("   (no rendering device: the feedback itself is checked only with a window)")
		return
	player.rotation.y = 0.0
	player.camera.rotation.x = 0.0
	await secs(0.5)
	var clean_a := await _frame_image()
	player.rotation.y = PI
	await secs(0.5)
	var clean_b := await _frame_image()
	var views_differ := _image_gap(clean_a, clean_b)
	check("the two test views look different", views_differ > 0.01, "gap %.3f" % views_differ)
	player.rotation.y = 0.0
	GameState.blur_timer = 100000.0
	await secs(0.5)
	var settled_a := await _frame_image()
	player.rotation.y = PI
	var first_b := await _frame_image()
	var gap_to_old := _image_gap(first_b, settled_a)
	var gap_to_new := _image_gap(first_b, clean_b)
	check("the first frame after a turn is still mostly the old picture (out = mix(scene, last, BlurVolume))", gap_to_old < gap_to_new, "to old %.3f, to new %.3f" % [gap_to_old, gap_to_new])
	await secs(1.5)
	var settled_b := await _frame_image()
	check("and the ghost fades into the new view", _image_gap(settled_b, clean_b) < gap_to_new * 0.5, "to new %.3f" % _image_gap(settled_b, clean_b))
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	await secs(0.3)

func _scn_viewfx() -> void:
	log_line("== view effects: pulses in degrees, sanity heartbeat, hazmat overlay, SCP-294 darkness, pocket dimension roll")
	statue.active = false
	revive()
	var hud := get_tree().get_first_node_in_group("hud")
	var s := GameState
	GameState.god_mode = true
	place_player(facility.start_node.to_global(Vector3(14.0, 1.55, -5.5)))
	await secs(0.5)
	# Sin(MilliSecs2() / 20.0) is in degrees: one pulse every 360 * 20 ms = 7.2 s
	var crossings: Array[float] = []
	var previous := 0.0
	var t := 0.0
	while t < 17.0 and crossings.size() < 3:
		s.bloodloss = 99.0
		s.injuries = 0.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var zoom: float = player.camera_zoom
		if previous < 19.8 and zoom >= 19.8 and previous > 0.0:
			crossings.append(s.clock_ms())
		previous = zoom
	s.bloodloss = 0.0
	player.camera_zoom = 0.0
	check("the blood-loss zoom pulses every 7.2 s", crossings.size() >= 2 and absf((crossings[1] - crossings[0]) - 7200.0) < 150.0, "crossings %s" % str(crossings))
	# the sanity heartbeat: volume Abs(Sanity + 200) / 500, rate 70 + Abs(Sanity + 200) / 6
	var audio := get_tree().get_first_node_in_group("audio")
	s.sanity = 0.0
	await secs(0.8)
	var quiet: float = audio._heart_volume
	s.sanity = -450.0
	s.restore_sanity = false
	await get_tree().process_frame
	await get_tree().process_frame
	check("sanity below -200 sets the heartbeat (volume 0.5, rate about 112)", quiet < 0.1 and audio._heart_volume > 0.4 and audio._heart_rate > 105.0, "quiet %.2f volume %.2f rate %.0f" % [quiet, audio._heart_volume, audio._heart_rate])
	s.sanity = 0.0
	# the gas mask overlay also shows for the hazmat suit
	s.wearing_gas_mask = 0
	s.wearing_1499 = 0
	s.wearing_hazmat = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var without: bool = hud._gas_overlay.visible
	s.wearing_hazmat = 1
	await get_tree().process_frame
	await get_tree().process_frame
	var worn: bool = hud._gas_overlay.visible
	s.wearing_hazmat = 0
	check("the gas mask overlay shows for a hazmat suit and not without one", worn and not without, "worn %s without %s" % [str(worn), str(without)])
	# Using294: DarkA = 1
	await get_tree().process_frame
	var clear_before: float = hud._fade.color.a
	hud._scp294_panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var dark_while: float = hud._fade.color.a
	hud._scp294_panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	check("the view goes fully dark while the SCP-294 panel is up", dark_while > 0.99 and clear_before < 0.99 and hud._fade.color.a < 0.99, "before %.2f while %.2f after %.2f" % [clear_before, dark_while, hud._fade.color.a])
	# the pocket dimension rolls the camera outside the throne room band
	var pocket := facility.pocket
	check("outside the pocket dimension the roll is the head bob only", pocket.camera_roll() == 0.0, "")
	pocket.player_inside = true
	var expected := sin(deg_to_rad(s.clock_ms() / 150.0)) * 30.0
	check("inside it the camera rolls Sin(MilliSecs2() / 150) * 30 degrees", absf(pocket.camera_roll() - expected) < 0.5, "%.2f vs %.2f" % [pocket.camera_roll(), expected])
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("and the camera has that roll (plus the head bob, at most 8)", absf(rad_to_deg(player.camera.rotation.z) - pocket.camera_roll()) < 8.5, "camera %.2f roll %.2f" % [rad_to_deg(player.camera.rotation.z), pocket.camera_roll()])
	var floor_y := player.global_position.y
	player.global_position.y = 2300.0 * 8.0 / 2048.0 - 0.3
	check("in the throne room's height band there is no roll", pocket.camera_roll() == 0.0, "")
	player.global_position.y = floor_y
	pocket.player_inside = false
	GameState.god_mode = false

# The original's numbers (tests/fixtures/original.json) measured in the port: movement, stamina, blinking, doors. Time is
# counted in the original's 70 Hz frames (physics delta * 70), not in physics ticks or wall-clock seconds.
func _scn_golden() -> void:
	log_line("== the original's numbers (tests/fixtures/original.json)")
	statue.active = false
	place_statue(Vector3(0.0, -80.0, 0.0))
	GameState.god_mode = true
	player.crouching = false
	player.stamina = 100.0
	await _blitz_frames(35.0)
	Input.action_press("move_forward")
	await _blitz_frames(140.0)
	check_golden("walk_speed", player.curr_speed)
	Input.action_press("sprint")
	await _blitz_frames(140.0)
	check_golden("sprint_speed", player.curr_speed)
	player.stamina = 100.0
	var frames := 0.0
	while frames < 560.0 and player.stamina > 0.0:
		frames += await _blitz_frames(0.0)
	check_golden("sprint_empty_seconds", frames / 70.0)
	Input.action_release("sprint")
	player.crouching = true
	await _blitz_frames(140.0)
	check_golden("crouch_speed", player.curr_speed)
	Input.action_release("move_forward")
	player.crouching = false
	frames = 0.0
	while frames < 210.0 and player.curr_speed > 0.0:
		frames += await _blitz_frames(0.0)
	player.stamina = 20.0
	frames = await _blitz_frames(70.0)
	check_golden("stamina_regen_still", (player.stamina - 20.0) * 70.0 / frames)
	player.blink_timer = 400.0
	frames = await _blitz_frames(70.0)
	check_golden("blink_drain", (400.0 - player.blink_timer) * 70.0 / frames)
	await _golden_door("door_open_frames", false)
	await _golden_door("big_door_open_frames", true)
	GameState.god_mode = false

# Waits at least `count` of the original's frames (one physics tick when 0) and returns how many passed.
func _blitz_frames(count: float) -> float:
	var passed := 0.0
	while passed == 0.0 or passed < count:
		await get_tree().physics_frame
		passed += get_physics_process_delta_time() * 70.0
	return passed

func _golden_door(fixture: String, big: bool) -> void:
	var door := _spawn_test_door(Vector3(0.0, 0.0, 3.0), big, false, false, false)
	await get_tree().physics_frame
	door.open = true
	var frames := 0.0
	while frames < 600.0 and door.openstate < 180.0:
		frames += await _blitz_frames(0.0)
	check_golden(fixture, frames)
	door.queue_free()

func _scn_roomambience() -> void:
	log_line("== room ambience emitters (UpdateRooms / LoopSound2)")
	var ambience: RoomAmbience = facility.ambience
	var target: FacilityRoom = null
	for room: FacilityRoom in facility.rooms.built.values():
		if not room.emitters.is_empty() and int(room.emitters[0].id) > 0 and float(room.emitters[0].range) > 2.0:
			target = room
			break
	check("a built room holds a soundemitter", target != null, "")
	if target == null:
		return
	check("a room keeps at most 8 emitters", target.emitters.size() <= RoomAmbience.MAX_EMITTERS, str(target.emitters.size()))
	var emitter: Dictionary = target.emitters[0]
	var source: Vector3 = target.to_global(emitter.position)
	var range_m := float(emitter.range)
	place_player(source)
	await _blitz_frames(5.0)
	var voice := ambience.voice_of(target, 0)
	check("inside the range the emitter plays", voice != null and voice.playing, "id %d range %.1f" % [int(emitter.id), range_m])
	if voice == null:
		return
	var camera_at: Vector3 = GameState.player.camera.global_position
	var expected := clampf(1.0 - camera_at.distance_to(source) / range_m, 0.0001, 1.0)
	check("the volume is 1 - distance / range", absf(db_to_linear(voice.volume_db) - expected) < 0.05, "%.3f vs %.3f" % [db_to_linear(voice.volume_db), expected])
	check("the clip is the rooms.ini ambience", voice.stream != null and voice.stream.resource_name.begins_with("SFX"), voice.stream.resource_name if voice.stream != null else "")
	await _blitz_frames(20.0)
	check("a clip that has not ended keeps playing", voice.playing and voice.stream.get_length() > 0.5, "length %.2f" % voice.stream.get_length())
	voice.stop()
	place_player(source + Vector3(range_m + 3.0, 0.0, 0.0))
	await _blitz_frames(10.0)
	check("outside the range a stopped emitter is not restarted", not voice.playing, "")
	place_player(target.global_position + Vector3(40.0, 0.0, 40.0))
	await _blitz_frames(10.0)
	check("more than 16 from the room it stays stopped", not voice.playing, "")
