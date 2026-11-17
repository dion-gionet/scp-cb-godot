extends Node3D
# The intro room (rooms.ini [173]; MapSystem.bb FillRoom "173"): the Class D cells, the corridors,
# the office, the concrete tunnel and SCP-173's chamber, all in one mesh. The room sits at the
# world origin. Positions below are written in the original's units (x and z in RoomScale units,
# y in metres) and turned into Godot ones by P() (z flips).


const RS := MeshLoader.ROOM_SCALE

var materials: Array[ShaderMaterial] = []
var containment_door: Node      # RoomDoors[1]: the big door of SCP-173's chamber
var side_door: Node             # the door to the staircase in the office room
var collision_faces: PackedVector3Array = PackedVector3Array()
var door_slots: Dictionary = {}     # RoomDoors[n]
var doors: Array[Node] = []
var objects: Array[Vector3] = []    # Objects[0..5] pivots (world positions)
var waypoints: Array[Vector3] = []  # the rmesh waypoints
var door_waypoints: Array[Vector3] = []   # 0.18 above the frame of every door that has one
var map_prop: Node3D            # Objects[9]
var labels: Node3D              # Objects[10]
var decals: Array[Node3D] = []
var light_points: Array = []        # [world position, LightIntensity] of every rmesh light (the fog of war counts them)
var lights: Array[Light3D] = []     # the rmesh lights the models are lit with (FacilityMap._update_lights)

# x, z in RoomScale units, y in metres; yaw; open; big; locked; buttons; waypoint; slot
const DOOR_DEFS := [
	# the containment door of the chamber (RoomDoors[1]); the original opens it for the scene
	{"x": 288.0, "y": 0.0, "z": 384.0, "yaw": 90.0, "open": false, "big": true, "locked": false, "buttons": false, "wp": true, "slot": 1},
	{"x": -1008.0, "y": 0.0, "z": -688.0, "yaw": 90.0, "open": false, "big": false, "locked": true, "buttons": false, "wp": true, "slot": 2},
	{"x": -2320.0, "y": 0.0, "z": -1248.0, "yaw": 90.0, "open": true, "big": false, "locked": true, "buttons": true, "wp": true, "slot": 3},
	{"x": -4352.0, "y": 0.0, "z": -1248.0, "yaw": 90.0, "open": true, "big": false, "locked": true, "buttons": true, "wp": true, "slot": 4},
	# the door in the office below the walkway
	{"x": -3712.0, "y": -1.5039, "z": -128.0, "yaw": 0.0, "open": true, "big": false, "locked": false, "buttons": true, "wp": true, "slot": 7},
	{"x": -3712.0, "y": -1.5039, "z": -2336.0, "yaw": 0.0, "open": false, "big": false, "locked": true, "buttons": true, "wp": false, "slot": -1},
	# from the concrete tunnel to the large hall
	{"x": -6864.0, "y": 0.0, "z": -1248.0, "yaw": 90.0, "open": true, "big": false, "locked": true, "buttons": true, "wp": true, "slot": -1},
	# the locked door to the lower level of the hall
	{"x": -5856.0, "y": 0.0, "z": -1504.0, "yaw": 0.0, "open": false, "big": false, "locked": true, "buttons": true, "wp": false, "slot": -1},
	# the door to the staircase in the office room
	{"x": -2432.0, "y": 0.0, "z": -1000.0, "yaw": 0.0, "open": false, "big": false, "locked": true, "buttons": true, "wp": false, "slot": 5,
		"button_move": {"0": {"x": -10.125, "z": -3.9687}, "1": {"x": -10.125, "z": -3.8437}}},   # PositionEntity(dbuttons[0], x - 2592 RoomScale, ..., z - 1016 RoomScale): the buttons sit beside the frame
]

func build() -> void:
	add_to_group("chamber")
	var path := ContentPaths.existing_file("GFX/map/173bright_opt.rmesh")
	var room: Dictionary = MeshLoader.load_rmesh(path)
	var visual := MeshInstance3D.new()
	visual.mesh = room.visual
	add_child(visual)
	for surface in visual.mesh.get_surface_count():
		var mat := visual.mesh.surface_get_material(surface)
		if mat is ShaderMaterial:
			materials.append(mat)
	collision_faces = room.collision_faces
	add_child(MeshLoader.make_static_body_shared(room))
	_add_props(room.entities)
	lights = FacilityRoom.add_rmesh_lights(self, room.entities, false)
	for entity in room.entities:
		if str(entity.get("kind", "")) == "waypoint":
			waypoints.append(to_global(entity.position))
		var kind := str(entity.get("kind", ""))
		if (kind == "light" or kind == "spotlight") and not (entity.position as Vector3).is_zero_approx():
			# LoadRMesh: r = Int(colour) * Min(intensity * 0.8, 1); LightIntensity = (r + g + b) / 255 / 3
			var strength := minf(float(entity.get("intensity", 1.0)) * 0.8, 1.0)
			var channels := str(entity.get("color", "255 255 255")).split(" ", false)
			var sum := 0.0
			for c in channels.slice(0, 3):
				sum += floorf(float(c) * strength)
			light_points.append([to_global(entity.position), sum / 255.0 / 3.0])
	_add_pivots()
	_add_doors()
	_add_paper(Vector3(-(2914.0 + 1024.0) * RS, 170.0 * RS, -40.0 * RS))
	map_prop = _prop("GFX/map/173_2.b3d", true)
	labels = _prop("GFX/map/intro_labels.b3d", false)
	_add_decals()
	_add_cams()
	containment_door = door_slots[1]
	side_door = door_slots[5]

func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * RS, y, -z * RS)

func floor_height(x: float, z: float, max_y: float = 2.2) -> float:
	var y := MeshLoader.floor_y(collision_faces, x, z, max_y)
	return 0.0 if y < -100.0 else y

func set_light_energy(energy: float) -> void:
	GameState.light_energy = energy
	for mat in materials:
		mat.set_shader_parameter("light_energy", energy)

# Objects[0..5]: where the scripted people and 173 stand (EntityParent r\obj).
func _add_pivots() -> void:
	var spots := [
		Vector3(40.0, 460.0 * RS, 1072.0), Vector3(-80.0, 100.0 * RS, 526.0), Vector3(-128.0, 100.0 * RS, 320.0),
		Vector3(660.0, 100.0 * RS, 526.0), Vector3(700.0, 100.0 * RS, 320.0), Vector3(1472.0, 100.0 * RS, 912.0),
	]
	for spot in spots:
		objects.append(to_global(P(spot.x, spot.y, spot.z)))

func _add_doors() -> void:
	for def in DOOR_DEFS:
		_make_door(def)
	var cell_texture := MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/Door02.jpg"))
	for zt in 2:
		_make_door({"x": -5760.0, "y": 0.0, "z": 320.0 + 896.0 * zt, "yaw": 0.0, "open": false, "big": false, "locked": true, "buttons": true, "wp": false, "slot": -1})
		_make_door({"x": -8288.0, "y": 0.0, "z": 320.0 + 896.0 * zt, "yaw": 0.0, "open": zt == 0, "big": false, "locked": true, "buttons": true, "wp": zt == 0, "slot": -1})
		var cell_yaw := 180.0 if zt == 0 else 0.0
		for xt in 3:
			var cell := _make_door({"x": -(7424.0 - 512.0 * xt), "y": 0.0, "z": 1008.0 - 480.0 * zt, "yaw": cell_yaw, "open": false, "big": false, "locked": true, "buttons": false, "wp": false, "slot": -1})
			cell.set_leaf_texture(cell_texture)
			cell.drop_second_leaf()
		for xt in 5:
			var slot := 6 if (xt == 2 and zt == 1) else -1
			var cell := _make_door({"x": -(5120.0 - 512.0 * xt), "y": 0.0, "z": 1008.0 - 480.0 * zt, "yaw": cell_yaw, "open": false, "big": false, "locked": true, "buttons": false, "wp": false, "slot": slot})
			cell.set_leaf_texture(cell_texture)
			cell.drop_second_leaf()

func _make_door(def: Dictionary) -> Node:
	var door := Node3D.new()
	door.set_script(load("res://scripts/world/facility_door.gd"))
	door.button_move = def.get("button_move", {})
	add_child(door)
	door.place_in_room(P(def.x, def.y, def.z), float(def.yaw), bool(def.big), bool(def.open), false, 0, bool(def.buttons))
	door.locked = bool(def.locked)
	doors.append(door)
	if bool(def.wp):
		door_waypoints.append(door.global_position + Vector3(0.0, 0.18, 0.0))
	var slot := int(def.slot)
	if slot >= 0:
		door_slots[slot] = door
	return door

func _add_props(entities: Array) -> void:
	var props_root := ContentPaths.assets_root.path_join("GFX/map/Props")
	for entity in entities:
		if str(entity.get("kind", "")) != "model":
			continue
		var file := str(entity.get("file", ""))
		if file.is_empty():
			continue
		var mesh := MeshLoader.load_x(props_root.path_join(file))
		if mesh.get_surface_count() == 0:
			continue
		var prop := MeshInstance3D.new()
		prop.mesh = mesh
		prop.position = entity.position
		var rot: Vector3 = entity.rotation
		prop.rotation = FacilityRoom.prop_rotation(rot)
		prop.scale = entity.scale
		add_child(prop)

# LoadMesh_Strict("GFX\map\...", r\obj): a map piece with its node transforms, in raw room units like the rmesh, so
# it takes r\obj's ScaleEntity RoomScale. `solid`: EntityType HIT_MAP.
func _prop(relative: String, solid: bool) -> Node3D:
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file(relative))
	var holder := Node3D.new()
	add_child(holder)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3.ONE * RS
	holder.add_child(visual)
	if solid:
		var faces := mesh.get_faces()
		for i in faces.size():
			faces[i] *= RS
		holder.add_child(MeshLoader.make_static_body(faces))
	return holder

# Blood on the floor: one at Objects[5], and four around the entrance of the chamber.
func _add_decals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_decal(rng.randi_range(5, 6), P(1472.0, 0.002, 912.0), 1.2, 1.0)
	for xt in 2:
		for zt in 2:
			var at := P(700.0 + xt * 700.0, rng.randf_range(0.001, 0.0018), 600.0 * zt) + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
			_decal(rng.randi_range(5, 7), at, rng.randf_range(0.5, 0.8), rng.randf_range(0.8, 1.0))

# GFX/decal<n>.png on the floor; `size` is the sprite scale (a 2 x 2 quad at 1).
func _decal(index: int, at: Vector3, size: float, alpha: float) -> void:
	var file := "GFX/decal%d.png" % index
	var texture: Texture2D = MeshLoader._load_texture(ContentPaths.existing_file(file))
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size * 2.0
	quad.mesh = mesh
	quad.material_override = GammaBlend.decal(texture, Color(1, 1, 1, alpha))
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	quad.position = at + Vector3(0.0, 0.01, 0.0)
	quad.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	decals.append(quad)

func _add_paper(pos: Vector3) -> void:
	var paper := RoomFill.make_pickup("Class D Orientation Leaflet", "paper")
	add_child(paper)
	# CreateItem's 170 units are under the room's invisible collision plane over the desk (0.72) and above the desk top
	# (156 units): left there, it falls onto the desk like a Blitz item
	paper.position = pos

# The camera over the corridor and the monitor in the office (CreateSecurityCam in FillRoom "173").
var cams: Array[Node3D] = []

func _add_cams() -> void:
	for def in RoomFill.for_room("173").get("cams", []):
		var cam := Node3D.new()
		cam.set_script(SecurityCam)
		add_child(cam)
		cam.setup(self, def)
		cams.append(cam)
