extends Node3D
# SCP-1499's dimension (MapSystem.bb "dimension1499" and the chunk code, UpdateEvents.bb UpdateDimension1499, Main.bb Case "scp1499" and
# UpdateLeave1499). Wearing the mask carries the player to a church room 800 up (outside the grid), in an endless grey land of 40 m
# chunks; taking it off carries them back to where they stood (and the next time they put it on they come back to where they left).
#  - chunks: the 7 x 7 chunks around the player (reach 120). Each is a 40 x 40 platform (1499plane.b3d) with the parts of one of
#    the entries of Data/1499chunks.ini (1499object1-15.b3d); which entry a place gets is fixed by the run's seed (a 64 x 64 table).
#    The four chunks next to the church are bare platforms that never go away.
#  - look: fog 40-80 of colour (96, 97, 104), the camera sees 90, a sky box from GFX/map/sky/1499sky_*.jpg, music "1499"
#    (the church has "HaveMercyOnMe", an attack has "1499Danger")
#  - people: up to 64 inhabitants (16 while the church king is there) appear 40-80 away around the player and are dropped when
#    farther than 120; the first time in a visit 15 are put within 20 of the player, and on the 2nd or 3rd visit (or the 4th) eight
#    surround the player at once, screaming
#  - the church: two front guards, two more, a stairs guard, the king and his guard, and 45 praying inhabitants. 10 s inside the church
#    and the king and his guard speak, 10 s later the king's speech ends and the guards (and the congregation) turn on the player
#    (EventState3 70 * 30). The first time out of the church's reach it is not recreated once done.
# Coordinates below are Blitz ones (z up) of the original converted at the door: Godot z = -z.

const Scp1499 = preload("res://scripts/npc/scp_1499.gd")

const RS := MeshLoader.ROOM_SCALE
const CHUNK := 40.0
const REACH := 120.0
const SPAWN_CHUNKS := [Vector2i(-40, 0), Vector2i(0, 0), Vector2i(-40, -40), Vector2i(0, -40)]

var facility: FacilityMap
var record := {}
var room: Node3D = null
var inside := false
var state := 0                  # EventState: 0 never entered, 1 entered before, 2 inside
var visits := 0                 # EventState2
var church_state := 0.0         # EventState3
var prev_position := Vector3.ZERO
var last_position := Vector3.INF      # NTF_1499X/Y/Z: where they left it
var npcs: Array[Node] = []
var king: Node = null
var king_guard: Node = null
var church_guards: Array[Node] = []
var dummies: Array[Node3D] = []
var chunks: Dictionary = {}

var _next_id := 1
var _chunk_data: Array = []
var _parts: Array = []             # per chunk entry: [{obj, x, z, yaw (degrees, or -1 random)}]
var _object_meshes: Dictionary = {}
var _object_shapes: Dictionary = {}
var _plane_mesh: ArrayMesh = null
var _plane_shape: ConcavePolygonShape3D = null
var _chunk_root: Node3D = null
var _sky: Node3D = null
var _blocker: StaticBody3D = null
var _choir: AudioStreamPlayer3D = null
var _music_on := false
var _rng := RandomNumberGenerator.new()

func setup(facility_node: Node, template: Dictionary) -> void:
	facility = facility_node
	if template.is_empty():
		return
	record = {"name": "dimension1499", "mesh": str(template.mesh), "shape": 1, "zone": 0, "grid": Vector2i(-100, -100), "angle": 0, "position": Vector3(8.0, 800.0, 0.0), "large": false, "key": "dimension1499", "off_grid": true}
	facility.rooms.by_grid["dimension1499"] = record

func contains(pos: Vector3) -> bool:
	return inside and not record.is_empty() and pos.y > float(record.position.y) - 6.0

func _origin() -> Vector3:
	return record.position

# A point of the church given as the original's room-relative units (x, y, z up).
func church_point(x: float, y: float, z: float) -> Vector3:
	return room.global_position + Vector3(x * RS, y * RS, -z * RS)

# Called by the room registry once the church is built.
func prepare() -> void:
	room = facility.rooms.get_room(record)
	_rng.seed = hash("1499%s" % str(facility.generator.seed_value))
	for i in 64:
		var row: Array = []
		for j in 64:
			row.append(_rng.randi_range(0, 4))
		_chunk_data.append(row)
	var ini := IniFile.parse(ContentPaths.existing_file("Data/1499chunks.ini"))
	for index in 5:
		var section := "chunk%d" % index
		var entries: Array = []
		if ini.sections.has(section):
			var count := int(ini.get_value(section, "count", "0"))
			for j in count + 1:
				var yaw_text := ini.get_value(section, "obj%d-yaw" % j, "0")
				entries.append({"obj": int(ini.get_value(section, "obj%d" % j, "1")), "x": ini.get_float(section, "obj%d-x" % j), "z": ini.get_float(section, "obj%d-z" % j), "yaw": -1.0 if yaw_text.to_lower() == "random" else float(yaw_text)})
		_parts.append(entries)
	var plane := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/dimension1499/1499plane.b3d"))
	_make_bright(plane)
	_plane_mesh = plane
	_plane_shape = _shape_of(plane, 1.0)
	for id in range(1, 16):
		var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/dimension1499/1499object%d.b3d" % id))
		_make_bright(mesh)
		_object_meshes[id] = mesh
		_object_shapes[id] = _shape_of(mesh, RS)
	_chunk_root = Node3D.new()
	_chunk_root.top_level = true
	add_child(_chunk_root)
	_build_sky()
	# the invisible barrier of the church (1499object0_cull.b3d, shown while the king is there)
	var cull := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/dimension1499/1499object0_cull.b3d"))
	if cull != null and cull.get_surface_count() > 0:
		_blocker = StaticBody3D.new()
		_blocker.collision_layer = 1
		_blocker.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = _shape_of(cull, RS)
		_blocker.add_child(shape)
		room.add_child(_blocker)
		_blocker.process_mode = Node.PROCESS_MODE_DISABLED
		shape.disabled = true

func _shape_of(mesh: ArrayMesh, scale_value: float) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	if mesh == null or mesh.get_surface_count() == 0:
		return shape
	shape.set_faces(Transform3D(Basis.from_scale(Vector3.ONE * scale_value), Vector3.ZERO) * mesh.get_faces())
	return shape

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
		var picture := MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/sky/1499sky_%s.jpg" % face_name))
		var points := PackedVector3Array()
		for corner in faces[face_name]:
			points.append((corner as Vector3) * 20.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/sky_box.gdshader")
		material.set_shader_parameter("tex", picture)
		material.render_priority = -127
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 16384.0
		_sky.add_child(instance)
	_sky.visible = false

# The mask has just gone on: carry the player over.
func enter(player: CharacterBody3D) -> void:
	if room == null:
		return
	player.blink_timer = -1.0
	prev_position = player.global_position
	if last_position == Vector3.INF:
		player.global_position = church_point(6086.0, 304.0, 2292.5)
		player.rotation.y = deg_to_rad(90.0)
	else:
		player.global_position = last_position + Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	facility.after_teleport()
	last_position = Vector3.INF
	Sfx.play_global(self, "SFX/SCP/1499/Enter.ogg")
	if player.global_position.distance_to(room.global_position) > 8300.0 * RS and visits < 5:
		visits += 1
	inside = true
	_begin_visit(player)

# Loading a game that was saved inside the dimension.
func resume(player: CharacterBody3D) -> void:
	if room == null:
		return
	inside = true
	_begin_visit(player)

func _begin_visit(player: CharacterBody3D) -> void:
	state = 2
	_next_id = 1
	_make_initial_chunks()
	_update_chunks(player, false)
	if church_state < 70.0 * 30.0:
		_make_church()
	# the people of the first minute
	for i in 15:
		var n := _spawn_npc(Vector3(player.global_position.x + randf_range(-20.0, 20.0), float(record.position.y) + 0.1, player.global_position.z + randf_range(-20.0, 20.0)))
		n.angle = randf() * TAU
		n.state2 = 0.0
		if n.global_position.distance_to(player.global_position) < 10.0:
			n.set_state(2)
	var value := randi_range(2, 3)
	if visits == value or visits == 4:
		for i in range(-1, 2):
			for j in range(-1, 2):
				if i == 0 and j == 0:
					continue
				var around := _spawn_npc(player.global_position + Vector3(0.75 * i if i != 0 and j != 0 else float(i), 0.05, -(0.75 * j if i != 0 and j != 0 else float(j))))
				around.rotation.y = atan2(-(player.global_position.x - around.global_position.x), -(player.global_position.z - around.global_position.z))
				around.angle = around.rotation.y
				around.set_state(2)
		visits = 5
	_apply_look(player)
	if _sky != null:
		_sky.visible = true

# UpdateLeave1499: the mask came off.
func leave(player: CharacterBody3D) -> void:
	if not inside:
		return
	last_position = player.global_position
	player.blink_timer = -1.0
	player.global_position = prev_position + Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	# a mask lying in the dimension comes with the player
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pickup) and str(pickup.get_meta("tempname", "")) in ["scp1499", "super1499"] and pickup.global_position.y >= float(record.position.y) - 5.0:
			pickup.global_position = Vector3(prev_position.x, prev_position.y + (pickup.global_position.y - float(record.position.y)), prev_position.z)
			if pickup.has_method("wake"):
				pickup.wake()
	_teardown()
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	player.camera.far = 4000.0
	Sfx.play_global(self, "SFX/SCP/1499/Exit.ogg")
	inside = false
	state = 1
	facility.after_teleport()

func _teardown() -> void:
	if _sky != null:
		_sky.visible = false
	for chunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks.clear()
	for n in npcs.duplicate():
		remove_npc(n)
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	king = null
	king_guard = null
	church_guards.clear()
	if church_state < 70.0 * 30.0:
		church_state = 0.0
	_stop_church_music()
	if _blocker != null:
		_blocker.process_mode = Node.PROCESS_MODE_DISABLED
		(_blocker.get_child(0) as CollisionShape3D).disabled = true
	if GameState.music_override in ["1499", "1499Danger", "HaveMercyOnMe(NoChoir)"]:
		GameState.music_override = ""

func _make_initial_chunks() -> void:
	for key in SPAWN_CHUNKS:
		_make_chunk(key, -1, true)

func _make_chunk(key: Vector2i, entry: int, spawn_chunk: bool = false) -> void:
	if chunks.has(key):
		return
	var pivot := Node3D.new()
	_chunk_root.add_child(pivot)
	pivot.global_position = Vector3(float(key.x) + 20.0, float(record.position.y), -(float(key.y) + 20.0))
	pivot.set_meta("spawn", spawn_chunk)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	pivot.add_child(body)
	var platform := MeshInstance3D.new()
	platform.mesh = _plane_mesh
	pivot.add_child(platform)
	var plane_shape := CollisionShape3D.new()
	plane_shape.shape = _plane_shape
	body.add_child(plane_shape)
	if entry >= 0 and entry < _parts.size():
		for part in _parts[entry]:
			var id := int(part.obj)
			if not _object_meshes.has(id):
				continue
			var yaw: float = _rng.randf() * 360.0 if float(part.yaw) < 0.0 else float(part.yaw)
			var spot := Vector3(float(part.x), 0.0, -float(part.z))
			var visual := MeshInstance3D.new()
			visual.mesh = _object_meshes[id]
			visual.scale = Vector3.ONE * RS
			visual.position = spot
			visual.rotation.y = deg_to_rad(yaw)
			pivot.add_child(visual)
			var shape := CollisionShape3D.new()
			shape.shape = _object_shapes[id]
			shape.position = spot
			shape.rotation.y = deg_to_rad(yaw)
			body.add_child(shape)
	chunks[key] = pivot

# UpdateChunks: the 7 x 7 around the player, the far ones dropped, the inhabitants kept to the limit.
func _update_chunks(player: CharacterBody3D, with_people: bool = true) -> void:
	var blitz_x := player.global_position.x
	var blitz_z := -player.global_position.z
	var cx := int(blitz_x / CHUNK)
	var cz := int(blitz_z / CHUNK)
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var key := Vector2i((cx + ix) * 40, (cz + iz) * 40)
			if not chunks.has(key):
				var a := absi(int((key.x + 32) / 40) % 64)
				var b := absi(int((key.y + 32) / 40) % 64)
				_make_chunk(key, int(_chunk_data[a][b]))
	for key in chunks.keys():
		var pivot: Node3D = chunks[key]
		if bool(pivot.get_meta("spawn", false)):
			continue
		var flat := Vector2(pivot.global_position.x - player.global_position.x, pivot.global_position.z - player.global_position.z).length()
		if flat > REACH:
			pivot.queue_free()
			chunks.erase(key)
	if not with_people:
		return
	var limit := 16 if king != null and is_instance_valid(king) else 64
	if npcs.size() < limit:
		var sector := randi_range(1, 8)
		var offsets := [Vector2(randf_range(40, 80), randf_range(40, 80)), Vector2(randf_range(40, 80), randf_range(-40, 40)), Vector2(randf_range(40, 80), randf_range(-80, -40)), Vector2(randf_range(-40, 40), randf_range(-80, -40)), Vector2(randf_range(-80, -40), randf_range(-80, -40)), Vector2(randf_range(-80, -40), randf_range(-40, 40)), Vector2(randf_range(-80, -40), randf_range(40, 80)), Vector2(randf_range(-40, 40), randf_range(40, 80))]
		var offset: Vector2 = offsets[sector - 1]
		var n := _spawn_npc(Vector3(player.global_position.x + offset.x, float(record.position.y) + 0.5, player.global_position.z - offset.y))
		if randi_range(1, 2) == 1:
			n.state2 = 500.0 * 3.0
		n.angle = randf() * TAU
	else:
		for n in npcs.duplicate():
			if is_instance_valid(n) and n.kind == 0:
				if n.global_position.distance_to(player.global_position) > REACH or n.global_position.y < float(record.position.y) - 5.0:
					remove_npc(n)

func _spawn_npc(pos: Vector3) -> CharacterBody3D:
	var n := CharacterBody3D.new()
	n.set_script(Scp1499)
	n.npc_id = _next_id
	_next_id += 1
	facility.get_parent().add_child(n)
	n.global_position = pos
	npcs.append(n)
	return n

func remove_npc(n: Node) -> void:
	npcs.erase(n)
	church_guards.erase(n)
	if n == king:
		king = null
	if n == king_guard:
		king_guard = null
	if is_instance_valid(n):
		n.queue_free()

func _church_npc(x: float, y: float, z: float, kind: int, yaw_degrees: float) -> CharacterBody3D:
	var n := _spawn_npc(church_point(x, y, z))
	n.kind = kind
	n.rotation.y = deg_to_rad(yaw_degrees)
	n.angle = n.rotation.y
	return n

func _make_church() -> void:
	var a := _church_npc(4055.0, 240.0, 1884.0, 3, 270.0)
	var b := _church_npc(4055.0, 240.0, 2876.0, 3, 270.0)
	a.target = b
	b.target = a
	var c := _church_npc(-1877.0, 192.0, 1071.0, 3, 270.0)
	var d := _church_npc(-1877.0, 192.0, 3503.0, 3, 270.0)
	c.target = d
	d.target = c
	church_guards = [a, b, c, d]
	var stairs := _church_npc(-2761.0, 240.0, 3204.0, 1, 180.0)
	stairs.speed = 0.0
	king = _church_npc(-1917.0, 1904.0, 2308.0, 2, 270.0)
	king.make_king()
	king_guard = _church_npc(-1917.0, 1904.0, 2052.0, 1, 270.0)
	# the congregation: 8 x 3 in the first zone, 7 x 3 in the second
	for x in 8:
		for y in 3:
			_dummy(Vector3(clampf((1887.0 - (2560.0 / 7.0) * x) + randf_range(-0.5, 0.5) / RS * 1.0, -873.0, 1887.0), 0.0, clampf((1796.0 - 384.0 * y) + randf_range(-0.5, 0.5) / RS, 1028.0, 1796.0)))
	for x in 7:
		for y in 3:
			_dummy(Vector3(clampf((1375.0 - (2048.0 / 6.0) * x) + randf_range(-0.5, 0.5) / RS, -873.0, 1375.0), 0.0, clampf((3588.0 - 384.0 * y) + randf_range(-0.5, 0.5) / RS, 2820.0, 3588.0)))
	if _blocker != null:
		_blocker.process_mode = Node.PROCESS_MODE_INHERIT
		(_blocker.get_child(0) as CollisionShape3D).disabled = false

func _dummy(room_units: Vector3) -> void:
	var model := B3DModel.new()
	model.load_file(ContentPaths.existing_file("GFX/npcs/1499-1.b3d"))
	Scp1499.make_bright(model)
	var holder := Node3D.new()
	holder.set_meta("anim", randi_range(0, 1))
	var unit_scale := (0.08 / 4.0) * randf_range(0.8, 1.0)
	model.scale = Vector3.ONE * unit_scale
	model.rotation.y = PI
	holder.add_child(model)
	facility.get_parent().add_child(holder)
	holder.global_position = church_point(room_units.x, 0.0, room_units.z)
	holder.rotation.y = deg_to_rad(270.0)
	holder.set_meta("model", model)
	holder.set_meta("frame", 321.0 if int(holder.get_meta("anim")) == 0 else 413.0)
	dummies.append(holder)

func _update_dummies(player: CharacterBody3D, fps: float) -> void:
	var near: bool = room != null and player.global_position.distance_to(room.global_position) <= 40.0
	for holder in dummies:
		if not is_instance_valid(holder):
			continue
		holder.visible = near
		if not near:
			continue
		var model: Node3D = holder.get_meta("model")
		var frame: float = holder.get_meta("frame")
		var anim: int = holder.get_meta("anim")
		if church_state < 70.0 * 30.0:
			frame = _dummy_pray(frame, anim, fps)
		else:
			frame = _dummy_stand(frame, anim, fps)
			var to_player: Vector3 = player.global_position - holder.global_position
			holder.rotation.y = lerp_angle(holder.rotation.y, atan2(-to_player.x, -to_player.z), minf(fps / 10.0, 1.0))
		holder.set_meta("frame", frame)
		model.set_frame(frame)

# Animate2 steps: a one-shot run over start..end at 0.2 a frame.
func _step(frame: float, start: float, finish: float, fps: float) -> float:
	return maxf(minf(frame + 0.2 * fps, finish), start)

func _dummy_pray(frame: float, anim: int, fps: float) -> float:
	if anim == 0:
		if frame <= 360.5:
			return _step(frame, 321.0, 361.0, fps)
		elif frame > 361.5 and frame <= 401.5:
			return _step(frame, 362.0, 402.0, fps)
		return 321.0 if randi_range(0, 1) == 0 else 362.0
	if frame <= 452.5:
		return _step(frame, 413.0, 453.0, fps)
	elif frame > 453.5 and frame <= 497.5:
		return _step(frame, 454.0, 498.0, fps)
	return 413.0 if randi_range(0, 1) == 0 else 454.0

func _dummy_stand(frame: float, anim: int, fps: float) -> float:
	if anim == 0:
		if frame <= 411.5 and frame > 320.5:
			return _step(frame, 403.0, 412.0, fps)
	else:
		if frame <= 507.5 and frame > 320.5:
			return _step(frame, 499.0, 508.0, fps)
	var next := frame + 0.2 * fps
	return 296.0 if next > 320.0 or frame < 296.0 else next

func _apply_look(player: CharacterBody3D) -> void:
	GameState.fog_override = Vector4(40.0, 80.0, 0.0, 0.0)
	GameState.fog_color = Color(96.0 / 255.0, 97.0 / 255.0, 104.0 / 255.0)
	player.camera.far = 90.0

func _physics_process(delta: float) -> void:
	if not inside:
		return
	var player: CharacterBody3D = GameState.player
	if player == null or not facility.active:
		return
	var fps := delta * 70.0
	if GameState.wearing_1499 == 0:
		leave(player)
		return
	_apply_look(player)
	if _sky != null:
		_sky.global_position = player.camera.global_position
	_update_chunks(player)
	if player.global_position.y < float(record.position.y):
		player.global_position.y = float(record.position.y) + 0.5
		player.velocity = Vector3.ZERO
	_church(player, fps)
	_update_dummies(player, fps)
	if not (GameState.music_override in ["1499Danger", "HaveMercyOnMe(NoChoir)", "none"]):
		GameState.music_override = "1499"

# The church event (EventState3).
func _church(player: CharacterBody3D, fps: float) -> void:
	var local := player.global_position - room.global_position
	var in_church := absf(local.x - (-56.0 * RS)) < 2160.0 * RS and absf(local.z - (-2287.0 * RS)) < 1408.0 * RS
	if church_state < 70.0 * 10.0:
		if in_church:
			church_state += fps
	elif church_state >= 70.0 * 10.0 and church_state < 70.0 * 20.0:
		if king != null and is_instance_valid(king):
			king.reload = 1.0
		if king_guard != null and is_instance_valid(king_guard):
			king_guard.reload = 1.0
		church_state = 70.0 * 20.0
	elif church_state == 70.0 * 20.0:
		if king != null and is_instance_valid(king) and king.frame > 854.5:
			var first := true
			for g in church_guards:
				if is_instance_valid(g):
					if first:
						g._voice_play("SFX/SCP/1499/Triggered.ogg")
						first = false
					g.set_state(1)
					g.set_frame(203.0)
			church_state = 70.0 * 30.0
	if king != null and is_instance_valid(king):
		if church_state < 70.0 * 30.0:
			_church_music()
		else:
			_stop_church_music()
	else:
		_stop_church_music()

func _church_music() -> void:
	GameState.music_override = "HaveMercyOnMe(NoChoir)"
	if _choir == null or not is_instance_valid(_choir):
		var stream := Sfx.stream("SFX/Music/HaveMercyOnMe(Choir).ogg")
		if stream != null:
			_choir = AudioStreamPlayer3D.new()
			_choir.stream = stream
			_choir.max_distance = 10.0
			add_child(_choir)
			_choir.global_position = church_point(205.0, 200.0, 2287.0)
			_choir.play()
	_music_on = true

func _stop_church_music() -> void:
	if _music_on and GameState.music_override == "HaveMercyOnMe(NoChoir)":
		GameState.music_override = "1499Danger" if church_state >= 70.0 * 30.0 else "1499"
	if _choir != null and is_instance_valid(_choir):
		_choir.stop()
		_choir.queue_free()
	_choir = null
	_music_on = false

# The land is not lit like the facility's models (their ambient would leave the ground black): the pictures show at full strength
# and the fog does the rest.
func _make_bright(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material is BaseMaterial3D or material is EntityMaterial:
			var bright = material.duplicate()
			bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bright.vertex_color_use_as_albedo = false
			bright.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(surface, bright)
		elif material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("fullbright", true)

# CreateNPC(NPCtype1499, ...) outside the dimension (SCP-914's "very fine" mask): one inhabitant, kept in the list so it goes when the mask does.
func spawn_loose(pos: Vector3) -> CharacterBody3D:
	return _spawn_npc(pos)

# A game is being loaded (or a test starts over): everything of a visit is dropped, the memory of earlier visits is cleared.
func reset() -> void:
	if inside:
		_teardown()
	inside = false
	state = 0
	visits = 0
	church_state = 0.0
	last_position = Vector3.INF
	GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
