extends Node3D
# Gate A (UpdateEvents.bb UpdateEndings, Case "gatea"): the open ground 500 up, reached by the lift in gateaentrance.
#
# Arriving (EventState 0 -> 1): everything but 106 and 173 is removed; the tunnel mesh, the sky box, the searchlight, three Apaches
# circling (hovering and alert unless 106 is contained), two guards on the towers and four MTF units standing at the bridge,
# all facing the spot where 106 will come up (Objects[3]). If 106 is not contained he escapes at 350 frames:
#   rises at Objects[3] (a corrosion decal under him), walks along the bridge toward its end (Objects[4]); within 15 of it
#   Franklin speaks; within 8.5 the HID turret charges (7.5 s) and fires a beam of light at him with shakes and flashes;
#   he reaches the end (0.4) and sinks back (700 frames), the helicopters and MTF turn on the player (state 2 / 1)
#   Then, with the player within 12 of the tunnel's end (Objects[11]), the MTF squad is put at the tunnel entrance (Objects[15])
#   and runs at the player; within 7 of the end the Chaos Insurgency appear (black figures, a bell, a flash), the player is
#   pulled in, stamina gone, the tunnel's walls swing shut (50-230 frames), "CI" plays and when it ends the player is killed:
#   ending A1.
# If 106 IS contained the helicopters stay quiet; the MTF walk to the player, stop within 6, "STOP RIGHT THERE" is spoken, the
#   player cannot move, and when it ends: ending A2.
# The camera: fog 5 to 30, pale (yellower facing -x), camera range 30, ambient 140.

const ApacheScript = preload("res://scripts/npc/apache.gd")

const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var apaches: Array = []            # NPC[2..4]
var guards: Array = []             # NPC[0..1]
var units: Array = []              # NPC[5..8] (MTF)
var walls: Array[Node3D] = []      # Objects[13], [14]
var light_gun_base: Node3D
var light_gun: Node3D
var ci_figures: Array[Node3D] = []
var stage_106 := 0                 # 0 not yet, 1 rising, 2 walking, 3 sinking, 4 gone
var sink_timer := 0.0              # Curr106\State3
var turret_clock := -1.0           # EventState2 of the original while 106 is within 8.5 (the turret's charge)
var _sky: Node3D
var _voice: AudioStreamPlayer
var _was_inside := false
var _ci_sound_started := false
var _shy: Node3D
var _bounds := AABB()               # the room's collision plus the tunnel mesh (PlayerRoom is gatea in the tunnel too)

func build(room_node: FacilityRoom) -> void:
	room = room_node
	_voice = AudioStreamPlayer.new()
	add_child(_voice)

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
	var inside: bool = room.world_bounds().has_point(player.global_position) or (_bounds.size != Vector3.ZERO and _bounds.has_point(player.global_position))
	if not inside:
		if _was_inside:
			_leave(player)
		_was_inside = false
		return
	_was_inside = true
	if facility.events.gatea.state == 0.0:
		_setup(facility, player)
		return
	_update(fps, player, facility)

func _setup(facility: FacilityMap, player: CharacterBody3D) -> void:
	var contained: bool = facility.contained_106
	apaches.clear()
	guards.clear()
	units.clear()
	walls.clear()
	_collision_mesh("GFX/map/gateatunnel.b3d", true)
	_collision_mesh("GFX/map/gatea_hitbox1.b3d", false)
	for index in [13, 14]:
		var wall := Node3D.new()
		add_child(wall)
		wall.global_position = room.object_point(index)
		var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/gateawall%d.b3d" % (index - 12)))
		if mesh != null and mesh.get_surface_count() > 0:
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.scale = Vector3.ONE * RS
			var dark := StandardMaterial3D.new()
			dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dark.albedo_color = Color8(25, 25, 25)
			visual.material_override = dark
			wall.add_child(visual)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(Transform3D(Basis.from_scale(Vector3.ONE * RS), Vector3.ZERO) * mesh.get_faces())
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			wall.add_child(body)
		walls.append(wall)
	for human in facility.humans.duplicate():
		facility.remove_human(human)
	for unit in facility.mtf.units.duplicate():
		facility.mtf.remove(unit)
	for zombie in facility.zombies008.duplicate():
		facility.remove_zombie008(zombie)
	for stray in [facility.scp049, facility.scp096]:
		if stray != null and is_instance_valid(stray):
			stray.queue_free()
	facility.scp049 = null
	facility.scp096 = null
	facility.spawn_049_enabled = false
	facility.mtf.enabled = false
	var statue: Node3D = GameState.scp173
	if statue != null:
		statue.active = false
		statue.idle = 3
		statue.global_position = Vector3(0.0, -400.0, 0.0)
	GameState.lights_on = true
	var centre: Vector3 = room.object_point(3)
	for i in 3:
		var heli := Node3D.new()
		heli.set_script(ApacheScript)
		heli.name = "Apache%d" % (i + 2)
		heli.state = 0 if contained else 1
		heli.gate_name = "A"
		_world().add_child(heli)
		heli.global_position = Vector3(room.global_position.x, room.global_position.y + 11.0, room.global_position.z)
		apaches.append(heli)
	_build_sky()
	for i in 2:
		var guard: Node = facility.spawn_human(HumanNpc.Kind.GUARD, NpcGravity.feet(room.object_point(5 + i)), -1)
		guard.state = 0
		guard.rotation.y = atan2(-(centre.x - guard.global_position.x), -(centre.z - guard.global_position.z))
		guards.append(guard)
	for i in 4:
		var mark: Vector3 = room.object_point(7 if i % 2 == 0 else 8)
		var spot := mark + (Vector3(0.8, 0.0, -0.8) if i >= 2 else Vector3.ZERO)
		var unit: Node = facility.mtf.spawn(spot)
		unit.state = 5
		unit.prev_state = 1
		unit.enemy = centre
		unit.rotation.y = atan2(-(centre.x - spot.x), -(centre.z - spot.z))
		unit.angle = unit.rotation.y
		units.append(unit)
	if contained:
		var door: Node3D = room.door_slots.get(2)
		if door != null:
			door.locked = true
		var entry: Vector3 = room.object_point(15)
		units[0].global_position = entry + Vector3(0.0, 0.2, 0.0)
	_build_light_gun()
	if not contained:
		Sfx.play_global(self, "SFX/Ending/GateA/106Escape.ogg")
	if facility.scp106 == null or not is_instance_valid(facility.scp106):
		facility.spawn_106(70.0 * 60.0 * 20.0)
		facility.scp106.idle = true
		facility.scp106.global_position = Vector3(0.0, -400.0, 0.0)
	_shy = facility.scp106
	_shy.idle = true
	# RotateEntity Collider, 0, EntityYaw(Collider) + (room angle + 180): out of the lift
	player.rotation.y += PI + room.rotation.y
	facility.events.gatea.state = 1.0

func _collision_mesh(file: String, visible_mesh: bool) -> void:
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file(file))
	if mesh == null or mesh.get_surface_count() == 0:
		return
	if visible_mesh:
		var box := mesh.get_aabb()
		var placed := AABB(room.global_position + box.position * RS, box.size * RS)
		_bounds = room.world_bounds().merge(placed)
		var facility := _facility()
		facility.rooms.set_bounds(room.room_key, _bounds)
	var holder := Node3D.new()
	add_child(holder)
	if visible_mesh:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.scale = Vector3.ONE * RS
		holder.add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(Transform3D(Basis.from_scale(Vector3.ONE * RS), Vector3.ZERO) * mesh.get_faces())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	holder.add_child(body)

func _build_light_gun() -> void:
	var spot: Vector3 = room.object_point(9)
	light_gun_base = Node3D.new()
	add_child(light_gun_base)
	light_gun_base.global_position = Vector3(spot.x, room.global_position.y + 992.0 * RS, spot.z)
	light_gun_base.rotation.y = deg_to_rad(48.0)
	light_gun = Node3D.new()
	light_gun_base.add_child(light_gun)
	light_gun.position = Vector3(0.0, 288.0 * RS, 176.0 * RS)
	light_gun.rotation.x = -deg_to_rad(40.0)
	for pair in [[light_gun_base, "GFX/map/lightgunbase.b3d"], [light_gun, "GFX/map/lightgun.b3d"]]:
		var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file(pair[1]))
		if mesh != null and mesh.get_surface_count() > 0:
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.scale = Vector3.ONE * RS
			(pair[0] as Node3D).add_child(visual)

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
		var points := PackedVector3Array()
		for corner in faces[face_name]:
			points.append((corner as Vector3) * 28.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
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
	_sky.rotation.y = room.rotation.y

func _leave(player: CharacterBody3D) -> void:
	if GameState.music_override in ["GateA", "none"] and GameState.selected_ending.is_empty():
		GameState.music_override = ""
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	GameState.ambient_override = -1.0
	player.camera.far = 4000.0
	if _sky != null:
		_sky.visible = false

func _update(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	s.music_override = "GateA" if s.selected_ending.is_empty() else "none"
	facility.events.gatea.state += fps
	var t: float = facility.events.gatea.state
	if _sky != null:
		_sky.visible = true
		_sky.global_position = player.camera.global_position
	# the look: fog 5-30, clear colour pale (200 + sin(yaw + 90) * 40, 200 + ... * 20, 200), camera range 30, ambient 140
	var angle := maxf(sin(player.rotation.y + PI * 0.5), 0.0)
	s.fog_color = Color((200.0 + angle * 40.0) / 255.0, (200.0 + angle * 20.0) / 255.0, 200.0 / 255.0)
	s.fog_override = Vector4(5.0, 30.0, 0.0, 0.0)
	s.ambient_override = 140.0 / 255.0
	player.camera.far = 30.0
	var centre: Vector3 = room.object_point(3)
	for i in apaches.size():
		var heli: Node3D = apaches[i]
		if is_instance_valid(heli) and heli.state < 2:
			var a: float = t / 10.0 + 120.0 * (i + 2)
			heli.global_position = Vector3(centre.x + cos(deg_to_rad(a)) * 6000.0 * RS, room.global_position.y + 11.0, centre.z - sin(deg_to_rad(a)) * 6000.0 * RS)
			heli.pitch = 7.0
			heli.yaw = a
			heli.roll = 20.0
	if facility.contained_106:
		_contained(fps, player, facility)
	else:
		_escape(fps, t, player, facility)

func _escape(fps: float, t: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	var centre: Vector3 = room.object_point(3)
	var bridge_end: Vector3 = room.object_point(4)
	if t >= 350.0 and stage_106 == 0:
		_shy.idle = true
		_shy.state = -0.1
		_shy.visible = true
		_shy.set_frame(110.0)
		_shy.global_position = Vector3(centre.x, centre.y, centre.z)
		_shy.rotation.y = atan2(-(bridge_end.x - centre.x), -(bridge_end.z - centre.z))
		GrowingDecal.make(room, Vector3(centre.x, centre.y + 0.01, centre.z), "GFX/decal1.png", 0.05, 0.001, 0.8, true)
		Sfx.play_global(self, "SFX/Horror/Horror5.ogg")
		Sfx.play_global(self, "SFX/SCP/106/Decay0.ogg")
		stage_106 = 1
	match stage_106:
		1:
			_shy.animate(110.0, 259.0, 0.15, fps, false)
			if _shy.frame >= 259.0:
				stage_106 = 2
		2:
			_walk_106(fps, player, bridge_end)
		3:
			_sink_106(fps, player, centre)
	if stage_106 == 4 and facility.events.gatea.state3 == 0.0:
		var end: Vector3 = room.object_point(11)
		var flat := Vector2(player.global_position.x - end.x, player.global_position.z - end.z).length()
		if absf(player.global_position.y - end.y) < 1.0 and flat < 12.0:
			_squad_to_tunnel(player, facility)
	elif facility.events.gatea.state3 == 1.0:
		for unit in units:
			if is_instance_valid(unit):
				unit.state = 3 if unit.global_position.distance_to(player.global_position) > 4.0 else 1
		var end2: Vector3 = room.object_point(11)
		var flat2 := Vector2(player.global_position.x - end2.x, player.global_position.z - end2.z).length()
		if absf(player.global_position.y - end2.y) < 1.0 and flat2 < 7.0:
			_chaos_insurgency(player, facility)
	elif facility.events.gatea.state3 >= 2.0:
		_ci_scene(fps, player, facility)

func _walk_106(fps: float, player: CharacterBody3D, bridge_end: Vector3) -> void:
	var to_end := Vector3(bridge_end.x - _shy.global_position.x, 0.0, bridge_end.z - _shy.global_position.z)
	var dist := to_end.length()
	# the helicopters and the MTF turn on him, the searchlight gun follows him
	for heli in apaches:
		if is_instance_valid(heli):
			heli.state = 3
			heli.enemy = _shy.global_position + Vector3(0.0, 5.0, 0.0)
	for unit in units:
		if is_instance_valid(unit):
			unit.state = 5
			unit.enemy = _shy.global_position + Vector3(0.0, 0.4, 0.0)
	_aim_light_gun(fps)
	_shy.rotation.y = lerp_angle(_shy.rotation.y, atan2(-to_end.x, -to_end.z), minf(fps / 10.0, 1.0))
	var speed: float = Scp106.SPEED * clampf(dist / 6.0, 0.05, 1.0)
	_shy.curr_speed = speed
	_shy.animate(284.0, 333.0, speed / 70.0 * 43.0, fps)
	if dist > 0.01:
		_shy.global_position += to_end.normalized() * minf(speed / 70.0 * fps, dist)
	if dist < 15.0 and not _franklin_played:
		_franklin_played = true
		_play(_voice, "SFX/Ending/GateA/Franklin.ogg")
	if dist < 8.5:
		_turret(fps, player, dist)
	if dist < 0.4:
		stage_106 = 3
		sink_timer = 0.0
		_shy.set_frame(259.0)
		Sfx.play_at(_shy, "SFX/Ending/GateA/106Retreat.ogg", 35.0)

var _franklin_played := false
var _decal_clock := 0.0

func _turret(fps: float, player: CharacterBody3D, dist: float) -> void:
	if turret_clock < 0.0:
		turret_clock = 0.0
		Sfx.play_global(self, "SFX/Ending/GateA/HIDTurret.ogg")
		return
	turret_clock += fps
	if turret_clock >= 7.5 * 70.0:
		if turret_clock - fps < 7.5 * 70.0:
			_turret_flares()
		elif turret_clock < 14.3 * 70.0:
			player.camera_shake = 0.5
			var seen := 0.5 if player.camera.is_position_in_frustum(light_gun.global_position) else 0.0
			GameState.light_flash = 0.3 + seen
	if dist >= 0.4:
		_smoke_106(dist)
	_decal_clock += fps
	if _decal_clock >= 100.0:
		_decal_clock = 0.0
		GrowingDecal.make(room, Vector3(_shy.global_position.x, room.object_point(3).y + 0.01, _shy.global_position.z), "GFX/decal1.png", 0.2, 0.004, 0.8, true)

# The beam is charged: a sun.jpg flare on 106 and one in front of the light gun, each 6.7 s long.
func _turret_flares() -> void:
	var particles := _facility().particles
	var on_106 := particles.create(_shy.global_position + Vector3(0.0, 0.4, 0.0), 4, 7.0, 0.0, 6.7 * 70.0)
	if on_106 != null:
		on_106.speed = 0.0
		on_106.follow = _shy
		on_106.follow_offset = Vector3(0.0, 0.4, 0.0)
	var muzzle := Vector3(0.0, 92.0 * RS, -512.0 * RS)
	var on_gun := particles.create(light_gun.to_global(muzzle), 4, 2.0, 0.0, 6.7 * 70.0)
	if on_gun != null:
		on_gun.speed = 0.0
		on_gun.follow = light_gun
		on_gun.follow_offset = muzzle
		on_gun.follow_local = true

# While the turret is on him 106 gives off smoke, fewer the farther along the bridge he is.
func _smoke_106(dist: float) -> void:
	var particles := _facility().particles
	for i in randi_range(2, 2 + 6 * (Particles.AMOUNT - 1)) - int(dist) + 1:
		var wisp := particles.create(_shy.global_position + Vector3(0.0, randf_range(0.4, 0.9), 0.0), 0, 0.006, -0.002, 40.0)
		if wisp != null:
			wisp.speed = 0.005
			wisp.alpha = 0.8
			wisp.a_change = -0.01
			wisp.dir = Particles.heading(-randf_range(70.0, 110.0), randf() * 360.0)

# Bell1 and Bell2: two sun.jpg flashes at the tunnel's end, at eye height, rushing off (the first time the second one at the player).
func _bell_flash(player: CharacterBody3D, at_player: bool) -> void:
	var spot: Vector3 = room.object_point(11)
	var origin := Vector3(spot.x, player.camera.global_position.y, spot.z)
	var particles := _facility().particles
	for speed in [0.15, 0.25]:
		var flash := particles.create(origin, 4, 8.0, 0.0, 50.0)
		if flash != null:
			flash.speed = speed
			flash.alpha = 0.5
			if at_player and speed == 0.25:
				flash.dir = (player.global_position + Vector3(0.0, 0.3, 0.0) - origin).normalized()

func _aim_light_gun(fps: float) -> void:
	if light_gun_base == null:
		return
	var wanted := atan2(-(_shy.global_position.x - light_gun_base.global_position.x), -(_shy.global_position.z - light_gun_base.global_position.z))
	light_gun_base.rotation.y = lerp_angle(light_gun_base.rotation.y, wanted, minf(fps / 150.0, 1.0))
	var to := _shy.global_position - light_gun.global_position
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	light_gun.rotation.x = lerpf(light_gun.rotation.x, pitch, minf(fps / 200.0, 1.0))

func _sink_106(fps: float, player: CharacterBody3D, centre: Vector3) -> void:
	_decal_clock += fps
	if _decal_clock >= 160.0:
		_decal_clock = 0.0
		GrowingDecal.make(room, Vector3(_shy.global_position.x, centre.y + 0.01, _shy.global_position.z), "GFX/decal1.png", 0.05, 0.004, 0.8, true)
	_shy.animate(259.0, 110.0, -0.1, fps, false)
	sink_timer += fps
	_shy.global_position.y = centre.y - sink_timer / 4500.0
	if sink_timer > 700.0:
		stage_106 = 4
		_shy.visible = false
		_shy.global_position = Vector3(0.0, -400.0, 0.0)
		for unit in units:
			if is_instance_valid(unit):
				unit.state = 1
		for heli in apaches:
			if is_instance_valid(heli):
				heli.state = 2

func _squad_to_tunnel(player: CharacterBody3D, facility: FacilityMap) -> void:
	var entry: Vector3 = room.object_point(15)
	for i in units.size():
		var unit: Node = units[i]
		if not is_instance_valid(unit):
			continue
		unit.global_position = Vector3(entry.x + (i - 1) * 0.3, entry.y, entry.z - (i - 1) * 0.3)
		unit.velocity = Vector3.ZERO
		unit.state = 3
		unit._find_path(player.global_position + Vector3(0.0, 0.2, 0.0))
		unit.path_timer = 70.0 * 2.0
		unit.last_seen = 70.0 * 100.0
	if is_instance_valid(units[1]):
		Sfx.play_at(units[1], "SFX/Character/MTF/ThereHeIs1.ogg", 25.0)
	var door: Node3D = room.door_slots.get(2)
	if door != null:
		door.open = true
	for heli in apaches:
		if is_instance_valid(heli):
			heli.queue_free()
	apaches.clear()
	facility.events.gatea.state3 = 1.0

func _chaos_insurgency(player: CharacterBody3D, facility: FacilityMap) -> void:
	var spot: Vector3 = room.object_point(11)
	var figure_mesh := B3DModel.static_mesh(ContentPaths.existing_file("GFX/npcs/s2.b3d"), true)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var first := Node3D.new()
	add_child(first)
	first.global_position = spot
	var base := Node3D.new()
	add_child(base)
	base.global_position = Vector3(room.global_position.x - 3968.0 * RS, spot.y, room.global_position.z + 1920.0 * RS)
	# Objects[12] at the tunnel's end; Objects[17] and its two children (z is flipped here)
	var places := [[first, Vector3.ZERO], [base, Vector3.ZERO], [base, Vector3(-192.0, 0.0, 0.0) * RS], [base, Vector3(-96.0, 0.0, 192.0) * RS]]
	for place in places:
		var figure := MeshInstance3D.new()
		figure.mesh = figure_mesh
		figure.scale = Vector3.ONE * (0.32 / 21.3)
		figure.material_override = black
		(place[0] as Node3D).add_child(figure)
		figure.position = place[1]
	ci_figures.append(first)
	ci_figures.append(base)
	Sfx.play_at(first, "SFX/Ending/GateA/Bell1.ogg", 14.0)
	_bell_flash(player, true)
	player.camera_shake = 1.0
	GameState.light_flash = 1.0
	facility.events.gatea.state3 = 2.0

func _ci_scene(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	facility.events.gatea.state3 += fps
	var es3: float = facility.events.gatea.state3
	var first: Node3D = ci_figures[0]
	first.rotation.y = atan2(-(player.global_position.x - first.global_position.x), -(player.global_position.z - first.global_position.z))
	player.stamina = -5.0
	s.blur_timer = sin(deg_to_rad(es3 * 0.7)) * 1000.0
	if not player.dead:
		player.zoom_override = 1.0 + sin(deg_to_rad(es3 * 0.8)) * 0.2
		var spot: Vector3 = room.object_point(11)
		var dist := player.global_position.distance_to(spot)
		if dist < 6.5:
			var blend := minf(fps / maxf(dist * 80.0, 1.0), 1.0)
			player.global_position.x += (spot.x - player.global_position.x) * blend
			player.global_position.z += (spot.z - player.global_position.z) * blend
	if es3 > 50.0 and es3 < 230.0:
		player.camera_shake = sin(deg_to_rad(es3 - 50.0)) * 3.0
		walls[0].rotation.y += deg_to_rad(sin(deg_to_rad(es3 - 50.0)) * 0.85) * fps
		walls[1].rotation.y -= deg_to_rad(sin(deg_to_rad(es3 - 50.0)) * 0.85) * fps
		var door: Node3D = room.door_slots.get(2)
		for unit in units:
			if is_instance_valid(unit) and door != null:
				unit.global_position.x += (door.global_position.x - unit.global_position.x) * minf(fps / 50.0, 1.0)
	if es3 >= 230.0:
		if not _ci_sound_started:
			_ci_sound_started = true
			_play(_voice, "SFX/Ending/GateA/CI.ogg")
		if not _voice.playing and s.selected_ending.is_empty():
			Sfx.play_global(self, "SFX/Ending/GateA/Bell2.ogg")
			_bell_flash(player, false)
			s.selected_ending = "a1"
			s.god_mode = false
			s.noclip = false
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null:
				hud.start_ending("a1")
		if not s.selected_ending.is_empty():
			player.camera_shake += (2.0 - player.camera_shake) * minf(fps / 10.0, 1.0)
			s.light_flash += (2.0 - s.light_flash) * minf(fps / 8.0, 1.0)

func _contained(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	if facility.events.gatea.state2 == 0.0:
		facility.events.gatea.state2 = 1.0
		for i in units.size():
			var unit: Node = units[i]
			if is_instance_valid(unit):
				unit.state = 3
				unit._find_path(Vector3(room.global_position.x - 1.0 + 2.0 * (i % 2), player.global_position.y + 0.2, room.global_position.z + 2.0 * (i % 2)))
				unit.path_timer = 70.0 * randf_range(15.0, 20.0)
				unit.last_seen = 70.0 * 300.0
		return
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if unit.state == 5:
			unit.enemy = player.global_position
		elif unit.global_position.distance_to(player.global_position) < 6.0:
			unit.state = 5
			unit.curr_speed = 0.0
	if facility.events.gatea.state2 <= 1.0:
		var any_stopped := false
		for unit in units:
			if is_instance_valid(unit) and unit.state == 5:
				any_stopped = true
		if any_stopped:
			for unit in units:
				if is_instance_valid(unit):
					unit.state = 5
					unit.enemy = player.global_position
					unit.path_timer = 70.0 * randf_range(7.0, 10.0)
					unit.reload = 2000.0
			s.unable_to_move = true
			_play(_voice, "SFX/Ending/GateA/STOPRIGHTTHERE.ogg")
			facility.events.gatea.state2 = 2.0
		else:
			for unit in units:
				if is_instance_valid(unit):
					unit.last_seen = 70.0 * 300.0
					unit.reload = 2000.0
					unit.state3 = 70.0 * 145.0
	else:
		s.music_override = "none"
		player.velocity = Vector3.ZERO
		if not _voice.playing and s.selected_ending.is_empty():
			Sfx.play_global(self, "SFX/Room/Intro/Bang3.ogg")
			s.selected_ending = "a2"
			s.god_mode = false
			s.noclip = false
			s.unable_to_move = false
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null:
				hud.start_ending("a2")

func _play(player: AudioStreamPlayer, file: String) -> void:
	var stream := Sfx.stream(file)
	if stream != null:
		player.stream = stream
		player.play()
