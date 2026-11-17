extends Node3D
# Gate B (UpdateEvents.bb UpdateEndings, Case "exit1"): the surface above the lift (the player higher than 1040 room units).
#
# On arriving (EventState 0 -> 1): every monster, guard and MTF unit is removed, the fog and the light level change, the
# terrain (exit1terrain.b3d) and the sky box appear, a helicopter starts circling high above (NPC[0]) and a guard stands at
# Objects[4] (NPC[1]). The guard starts shooting once the player is within 15 or the helicopter sees them, but not from
# below the roof or inside the catwalk.
# EventState 1: the helicopter circles (music GateB1) until the player comes within 320 room units of Objects[10]: then the
#   two doors lock, two more helicopters arrive, all three attack the point at Objects[11] and the 682 battle begins.
# EventState >= 2 (frames): the battle (music GateB2) with its shakes; 26.5 s a giant hand (682) swats the third helicopter
#   down; 35 s the "alpha warheads" announcement; 42 s the helicopters leave; 45-75 s the siren. At 75 s: with the remote
#   detonation on (the nuke room, not in the game yet) the bomb goes off (ending B2); otherwise the announcement says it
#   failed, three MTF units close in and, at 3 units, hold the player still; 500 frames later the player is shot (ending B3).
# The camera there: fog 5 to 45 in a pale colour (more yellow looking along +x), clear colour the same, camera range 60, ambient 140.

const ApacheScript = preload("res://scripts/npc/apache.gd")

const RS := MeshLoader.ROOM_SCALE
const SURFACE_Y := 1040.0 * RS

var room: FacilityRoom
var apaches: Dictionary = {}       # NPC index -> Apache (0, 2, 3)
var guard: Node = null
var arm: Node3D = null
var arm_roll := 180.0
var _terrain: Node3D
var _sky: Node3D
var _siren: AudioStreamPlayer
var _warheads: AudioStreamPlayer
var _mtf: Array = []
var _was_on_surface := false

func build(room_node: FacilityRoom) -> void:
	room = room_node

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _world() -> Node:
	return _facility().get_parent()

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or room == null or not facility.active:
		return
	var fps := delta * 70.0
	RemoteDoors.gate(room.door_slots.get(4), facility, facility.gate_b_unlocked, player)
	var on_surface: bool = room.world_bounds().has_point(player.global_position) and player.global_position.y > SURFACE_Y
	if not on_surface:
		if _was_on_surface:
			_leave()
		_was_on_surface = false
		return
	_was_on_surface = true
	if facility.events.exit1.state == 0.0:
		_setup(facility, player)
		return
	_surface(fps, player, facility)

func _setup(facility: FacilityMap, player: CharacterBody3D) -> void:
	for human in facility.humans.duplicate():
		facility.remove_human(human)
	for unit in facility.mtf.units.duplicate():
		facility.mtf.remove(unit)
	for zombie in facility.zombies008.duplicate():
		facility.remove_zombie008(zombie)
	for stray in [facility.scp049, facility.scp106, facility.scp096]:
		if stray != null and is_instance_valid(stray):
			stray.queue_free()
	facility.scp049 = null
	facility.scp106 = null
	facility.scp096 = null
	facility.spawn_049_enabled = false
	facility.spawn_106_enabled = false
	facility.mtf.enabled = false
	var statue: Node3D = GameState.scp173
	if statue != null:
		statue.active = false
		statue.idle = 3
		statue.global_position = Vector3(0.0, -400.0, 0.0)
	GameState.lights_on = true
	facility.exit1_centre = room.object_point(3)
	var heli := _apache(0, room.global_position + Vector3(0.0, 100.0, 0.0), 1)
	heli.gate_name = "B"
	guard = facility.spawn_human(HumanNpc.Kind.GUARD, room.object_point(4) + Vector3(0.0, 0.2, 0.0), -1)
	guard.state = 0
	guard.state2 = 10.0
	_build_terrain()
	_build_sky()
	facility.events.exit1.state = 1.0

func _apache(index: int, at: Vector3, state: int) -> Node3D:
	var heli := Node3D.new()
	heli.set_script(ApacheScript)
	heli.name = "Apache%d" % index
	heli.state = state
	_world().add_child(heli)
	heli.global_position = at
	apaches[index] = heli
	return heli

func _build_terrain() -> void:
	var mesh := MeshLoader.load_b3d_layered(ContentPaths.existing_file("GFX/map/exit1terrain.b3d"))
	_terrain = Node3D.new()
	_terrain.top_level = true
	add_child(_terrain)
	_terrain.global_position = room.object_point(0)
	_terrain.rotation.y = room.rotation.y
	if mesh != null and mesh.get_surface_count() > 0:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.scale = Vector3.ONE * RS
		_terrain.add_child(visual)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(Transform3D(Basis.from_scale(Vector3.ONE * RS), Vector3.ZERO) * mesh.get_faces())
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_terrain.add_child(body)

# sky_CreateSky("GFX\map\sky\sky"): a unit box of five pictures (back, left, front, right, up) round the camera
func _build_sky() -> void:
	_sky = Node3D.new()
	_sky.top_level = true
	add_child(_sky)
	var faces := {
		"back": [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
		"left": [Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)],
		"front": [Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, -1), Vector3(1, -1, -1)],
		"right": [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1), Vector3(-1, -1, -1)],
		"up": [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	}
	for face_name in faces:
		var picture := MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/sky/sky_%s.jpg" % face_name))
		var corners: Array = faces[face_name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var points := PackedVector3Array()
		for corner in corners:
			points.append((corner as Vector3) * 42.0)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = picture
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_fog = true
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sky.add_child(instance)
	_sky.rotation.y = room.rotation.y - PI * 0.5

func _leave() -> void:
	if GameState.music_override in ["GateB1", "GateB2", "none"] and GameState.selected_ending.is_empty():
		GameState.music_override = ""
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.ambient_override = -1.0
	var player: CharacterBody3D = GameState.player
	if player != null:
		player.camera.far = 4000.0
	if _sky != null:
		_sky.visible = false

func _surface(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	if _sky != null:
		_sky.visible = true
		_sky.global_position = player.camera.global_position
	# the camera's look: fog 5-45, pale, a little yellower facing +x (CameraFogColor 200 + sin(yaw) * 50, 200 + sin * 30, 200)
	var facing := maxf(sin(player.rotation.y), 0.0)
	s.fog_color = Color((200.0 + facing * 50.0) / 255.0, (200.0 + facing * 30.0) / 255.0, 200.0 / 255.0)
	s.fog_override = Vector4(5.0, 45.0, 0.0, 0.0)
	s.ambient_override = 140.0 / 255.0
	player.camera.far = 60.0
	_wind_dust(player, facility)
	var heli0: Node3D = apaches.get(0)
	if heli0 != null and facility.events.exit1.state < 2.0 and s.selected_ending.is_empty():
		if heli0.state == 2:
			s.music_override = "GateB2"
		else:
			facility.events.exit1.state2 = fmod(facility.events.exit1.state2 + fps, 3600.0)
			var a: float = facility.events.exit1.state2 / 10.0
			var centre := room.global_position
			heli0.global_position = Vector3(centre.x + cos(deg_to_rad(a)) * 6000.0 * RS, 14000.0 * RS, centre.z - sin(deg_to_rad(a)) * 6000.0 * RS)
			heli0.pitch = 7.0
			heli0.yaw = a
			heli0.roll = 20.0
			s.music_override = "GateB1"
		if player.global_position.distance_to(room.object_point(10)) < 320.0 * RS:
			_begin_battle(facility)
	else:
		s.music_override = "GateB2" if s.selected_ending.is_empty() else "none"
		facility.events.exit1.state += fps
		_battle(fps, player, facility)
	_guard(player, heli0)

func _begin_battle(facility: FacilityMap) -> void:
	facility.events.exit1.state = 2.0
	for slot in [2, 3]:
		var door: Node3D = room.door_slots.get(slot)
		if door != null:
			door.open = false
			door.locked = true
	var second := _apache(2, room.object_point(9) + Vector3(0.0, 0.5, 0.0), 3)
	second.gate_name = "B"
	var third := _apache(3, room.object_point(7) + Vector3(0.0, -2.0, 0.0), 3)
	third.gate_name = "B"
	apaches[0].state = 3
	facility.mtf.play_announcement("SFX/Ending/GateB/682Battle.ogg")

func _target(index: int, base: float, speed_a: float, speed_b: float, extra: float) -> void:
	var heli: Node3D = apaches.get(index)
	if heli == null or not is_instance_valid(heli):
		return
	var ms := GameState.clock_ms()
	var centre: Vector3 = room.object_point(11)
	heli.enemy = Vector3(centre.x + sin(deg_to_rad(ms / speed_a)) * 3.0, centre.y + cos(deg_to_rad(ms / speed_b)) + extra, centre.z - cos(deg_to_rad(ms / speed_a)) * 3.0)

func _battle(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var t: float = facility.events.exit1.state
	var s := GameState
	if t < 40.0 * 70.0:
		_target(0, 0.0, 25.0, 85.0, 9.0)
		_target(2, 0.0, 23.0, 83.0, 5.0)
		var third: Node3D = apaches.get(3)
		if third != null and is_instance_valid(third) and third.state == 3:
			_target(3, 0.0, 20.0, 80.0, 3.5)
	if t > 0.6 * 70.0 and t < 42.2 * 70.0:
		var shake := 0.0
		if t < 0.7 * 70.0:
			shake = 0.5
		elif t > 3.2 * 70.0 and t < 3.3 * 70.0:
			shake = 0.5
		elif t > 6.1 * 70.0 and t < 6.2 * 70.0:
			shake = 0.5
		elif t < 10.8 * 70.0 and t < 10.9 * 70.0:
			shake = 0.5
		elif t > 12.1 * 70.0 and t < 12.3 * 70.0:
			shake = 1.0
		elif t > 13.3 * 70.0 and t < 13.5 * 70.0:
			shake = 1.5
		elif t > 16.5 * 70.0 and t < 18.5 * 70.0:
			shake = 3.0
		elif t > 21.5 * 70.0 and t < 24.0 * 70.0:
			shake = 2.0
		elif t > 25.5 * 70.0 and t < 27.0 * 70.0:
			shake = 2.0
		elif t > 31.0 * 70.0 and t < 31.5 * 70.0:
			shake = 0.5
		elif t > 35.0 * 70.0 and t < 36.5 * 70.0:
			shake = 1.5
			if t - fps <= 35.0 * 70.0:
				_play(_warheads_player(), "SFX/Ending/GateB/DetonatingAlphaWarheads.ogg")
		elif t > 39.5 * 70.0 and t < 39.8 * 70.0:
			shake = 1.0
		if shake > 0.0:
			player.camera_shake = shake
	if t > 42.0 * 70.0 and t < 42.2 * 70.0 + 1.0:
		player.camera_shake = 0.5
	if t > 42.0 * 70.0:
		# the helicopters leave
		var leave: Vector3 = room.object_point(19)
		if apaches.has(0):
			apaches[0].enemy = leave + Vector3(4.0, 4.0, 4.0)
		if apaches.has(2):
			apaches[2].enemy = leave
	if t >= 45.0 * 70.0:
		if t < 75.0 * 70.0:
			if _siren == null:
				_siren = AudioStreamPlayer.new()
				add_child(_siren)
				_play(_siren, "SFX/Ending/GateB/Siren.ogg")
		else:
			_after_battle(fps, player, facility)
	if t > 26.5 * 70.0:
		_arm(fps, facility)

func _arm(fps: float, facility: FacilityMap) -> void:
	var third: Node3D = apaches.get(3)
	if third == null or not is_instance_valid(third):
		return
	if arm == null:
		arm = Node3D.new()
		arm.top_level = true
		_world().add_child(arm)
		var model := B3DModel.new()
		model.load_file(ContentPaths.existing_file("GFX/NPCs/682arm.b3d"))
		model.scale = Vector3.ONE * 0.15
		arm.add_child(model)
		arm.global_position = Vector3(third.global_position.x, 12192.0 * RS, third.global_position.z)
		arm.rotation = Vector3(0.0, room.rotation.y + deg_to_rad(randf_range(-10.0, 10.0)), deg_to_rad(180.0))
		arm_roll = 180.0
	elif arm.visible:
		if fposmod(arm_roll, 360.0) < 340.0:
			var angle := fposmod(arm_roll, 360.0)
			arm_roll += (5.0 + absf(sin(deg_to_rad(angle))) * 2.0) * fps
			arm.rotation.z = deg_to_rad(arm_roll)
			if angle < 270.0 and fposmod(arm_roll, 360.0) >= 270.0:
				Sfx.play_global(self, "SFX/Character/Apache/Crash1.ogg")
				third.state = 4
				third.state2 = 1.0
				var down: Vector3 = room.object_point(7)
				third.enemy = Vector3(down.x, down.y - 2.5, down.z)
				_crash_smoke(third, facility)
		else:
			arm.visible = false

# Rand(3) = 1 a frame: a speck of dust blows past, 0.9 to 2 above the eyes, along the room's -x (RotateEntity room angle - 90)
func _wind_dust(player: CharacterBody3D, facility: FacilityMap) -> void:
	if randi_range(1, 3) != 1:
		return
	var eye: Vector3 = player.camera.global_position
	var speck := facility.particles.create(eye + Vector3(randf_range(-2.0, 2.0), randf_range(0.9, 2.0), randf_range(-2.0, 2.0)), 2, 0.006, 0.0, 300.0)
	if speck != null:
		speck.speed = randf_range(0.002, 0.003)
		speck.dir = Particles.heading(randf_range(-20.0, 20.0), rad_to_deg(room.rotation.y) - 90.0 + randf_range(-15.0, 15.0))
		speck.size_change = -0.00001

# The third helicopter hits the ground: smoke streams from the wreck for good, and a burst of big puffs and small flecks flies out.
func _crash_smoke(wreck: Node3D, facility: FacilityMap) -> void:
	var particles := facility.particles
	var yaw := rad_to_deg(wreck.rotation.y)
	particles.add_emitter(wreck.global_position, Particles.heading(-80.0, yaw), room, room.room_key, {
		"rand_angle": 45.0, "gravity": -0.18, "lifetime": 400.0, "size_change": randf_range(0.005, 0.007), "a_change": -0.004, "follow": wreck})
	for i in 3 + 4 * (Particles.AMOUNT - 1) + 1:
		var puff := particles.create(wreck.global_position, 0, randf_range(0.5, 1.0), -0.1, 200.0)
		if puff != null:
			puff.dir = Particles.random_heading()
			puff.speed = 0.01
			puff.size_change = 0.01
			puff.a_change = -0.005
			puff.pos += puff.dir * 0.3
	for i in 6 + 6 * (Particles.AMOUNT - 1) + 1:
		var fleck := particles.create(wreck.global_position, 0, 0.02, 0.003, 200.0)
		if fleck != null:
			fleck.dir = Particles.random_heading()
			fleck.speed = 0.04
			fleck.a_change = -0.005

# ---- 75 s: the end ---------------------------------------------------------------------------------------------------

func _after_battle(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	if s.selected_ending.is_empty():
		s.music_override = "none"
		if _siren != null:
			_siren.stop()
		if _warheads != null:
			_warheads.stop()
		if facility.nuke_remote_on:
			s.explosion_timer = maxf(s.explosion_timer, 0.1)
			s.selected_ending = "b2"
			facility.explosion_ending = "b2"
		else:
			facility.mtf.play_announcement("SFX/Ending/GateB/AlphaWarheadsFail.ogg")
			for i in 2:
				var spot: Vector3 = room.object_point(18) + Vector3(0.4 * i, 0.29, -0.4 * i)
				_mtf.append(facility.mtf.spawn(spot))
			var door_a: Node3D = room.door_slots.get(2)
			var door_b: Node3D = room.door_slots.get(3)
			if door_a != null and door_b != null:
				_mtf.append(facility.mtf.spawn((door_a.global_position + door_b.global_position) * 0.5 + Vector3(0.0, 0.29, 0.0)))
			for unit in _mtf:
				unit.last_seen = 70.0 * randf_range(30.0, 35.0)
				unit.state = 3
				unit.state2 = 10.0
				unit.enemy = player.global_position
			facility.events.exit1.state = 85.0 * 70.0
			s.selected_ending = "b3"
		return
	if s.selected_ending != "b3":
		return
	var heli0: Node3D = apaches.get(0)
	var heli2: Node3D = apaches.get(2)
	var ms := GameState.clock_ms()
	var centre: Vector3 = room.object_point(11)
	if heli0 != null:
		heli0.enemy = Vector3(centre.x + sin(deg_to_rad(ms / 25.0)) * 3.0, centre.y + cos(deg_to_rad(ms / 85.0)) + 9.0, centre.z - cos(deg_to_rad(ms / 25.0)) * 3.0)
	if heli2 != null:
		heli2.enemy = Vector3(centre.x + sin(deg_to_rad(ms / 23.0)) * 3.0, centre.y + cos(deg_to_rad(ms / 83.0)) + 5.0, centre.z - cos(deg_to_rad(ms / 23.0)) * 3.0)
	var door5: Node3D = room.door_slots.get(5)
	if door5 != null:
		door5.open = true
	# the MTF units walk to the player again whenever they cannot find them; within 3 they stop and the player is held
	if facility.events.exit1.state3 == 0.0:
		for unit in _mtf:
			if not is_instance_valid(unit):
				continue
			if unit.state == 5:
				unit.state = 3
				unit._find_path(player.global_position)
				unit.path_timer = 70.0 * randf_range(15.0, 20.0)
				unit.last_seen = 70.0 * 300.0
			if unit.global_position.distance_to(player.global_position) < 3.0:
				unit.state = 5
				unit.path_status = 0
				unit.path_timer = 0.0
				unit.curr_speed = 0.0
	for unit in _mtf:
		if is_instance_valid(unit) and unit.state == 5 and unit.global_position.distance_to(player.global_position) < 3.0 and facility.events.exit1.state3 == 0.0:
			Sfx.play_global(self, "SFX/Ending/GateB/PlayerDetect.ogg")
			facility.events.exit1.state3 += fps
			for other in _mtf:
				if is_instance_valid(other):
					other.state = 5
					other.path_status = 0
					other.path_timer = 0.0
					other.curr_speed = 0.0
			break
	if facility.events.exit1.state3 > 0.0 and facility.events.exit1.state3 <= 500.0:
		facility.events.exit1.state3 += fps
		s.unable_to_move = true
		for unit in _mtf:
			if is_instance_valid(unit):
				unit.enemy = player.global_position
	elif facility.events.exit1.state3 > 500.0:
		s.music_override = "none"
		player.velocity = Vector3.ZERO
		Sfx.play_global(self, "SFX/Ending/GateB/Gunshot.ogg")
		s.god_mode = false
		s.noclip = false
		s.unable_to_move = false
		for unit in _mtf.duplicate():
			if is_instance_valid(unit):
				facility.mtf.remove(unit)
		_mtf.clear()
		facility.events.exit1.state3 = 0.0
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null:
			hud.start_ending("b3")

func _guard(player: CharacterBody3D, heli0: Node3D) -> void:
	if guard == null or not is_instance_valid(guard):
		return
	if guard.state != 1:
		var near: bool = guard.global_position.distance_to(player.global_position) < 15.0
		var seen := false
		if heli0 != null:
			var query := PhysicsRayQueryParameters3D.create(heli0.global_position, player.global_position)
			query.collision_mask = 1
			seen = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if near or seen:
			guard.state = 1
			guard.state3 = 1.0
	# below the roof or inside the catwalk the guard cannot be sure of a hit
	if guard.global_position.distance_to(player.global_position) < 8.9 or room.object_point(5).distance_to(player.global_position) < 16.9:
		guard.state3 = 0.0
	else:
		guard.state3 = 1.0

func _warheads_player() -> AudioStreamPlayer:
	if _warheads == null:
		_warheads = AudioStreamPlayer.new()
		add_child(_warheads)
	return _warheads

func _play(player: AudioStreamPlayer, file: String) -> void:
	var stream := Sfx.stream(file)
	if stream != null:
		player.stream = stream
		player.play()
