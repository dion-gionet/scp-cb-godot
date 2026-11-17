extends Node3D
class_name FacilityRoom

const DoorScript = preload("res://scripts/world/facility_door.gd")
const ElevatorScript = preload("res://scripts/world/elevator.gd")

var room_name := ""
var triggers: Array = []   # rmesh trigger boxes: name and local corners
var collision_faces: PackedVector3Array = PackedVector3Array()
var materials: Array[ShaderMaterial] = []
var door_slots: Dictionary = {}
var _waypoints_local: Array[Vector3] = []
var _drawn_start := 0
var _door_points: Array[Vector3] = []
var _drawn_metal := PackedByteArray()
var room_key := ""
var fill_rng := -1      # the generator state FillRoom started from (map_generator.gd), -1 when the room was not made by CreateMap
var _fill_doors: Array[Node3D] = []
var _lifts: Array[Node] = []
var visual: MeshInstance3D       # the rendered mesh (GetChild(r\obj, 2)): UpdateRooms and the room2sl event set its alpha
var shell: StaticBody3D          # the room's walls and floor
var collidable := true

var record_below_empty := true
var generated_items: Array = []   # FillRoom items rolled at map generation (room1archive)

func build(record: Dictionary) -> void:
	room_name = str(record.name)
	room_key = str(record.get("key", ""))
	record_below_empty = bool(record.get("below_empty", true))
	name = "Room_%s_%d_%d" % [room_name, record.grid.x, record.grid.y]
	fill_rng = int(record.get("fill_rng", -1))
	generated_items = record.get("items", [])
	position = record.position
	rotation.y = deg_to_rad(float(record.angle))
	var path := ContentPaths.existing_file(str(record.mesh))
	var loaded: Dictionary = MeshLoader.load_rmesh_cached(path)
	visual = MeshInstance3D.new()
	visual.mesh = loaded.visual
	add_child(visual)
	for surface in visual.mesh.get_surface_count():
		var mat := visual.mesh.surface_get_material(surface)
		if mat is ShaderMaterial:
			materials.append(mat)
			mat.set_shader_parameter("light_energy", GameState.light_energy)
	collision_faces = loaded.collision_faces
	triggers = loaded.get("triggers", [])
	_drawn_start = int(loaded.get("drawn_start", 0))
	_drawn_metal = loaded.get("drawn_metal", PackedByteArray())
	shell = MeshLoader.make_static_body_shared(loaded)
	add_child(shell)
	for entity in loaded.entities:
		if str(entity.get("kind", "")) == "waypoint":
			_waypoints_local.append(entity.position)
	for entity in loaded.entities:
		if str(entity.get("kind", "")) == "soundemitter" and emitters.size() < RoomAmbience.MAX_EMITTERS:
			emitters.append(entity)
	_add_lights(loaded.entities)
	_add_screens(loaded.entities)
	_add_props(loaded.entities)
	_spawn_fill()

# HideEntity also takes an entity out of collisions: a room UpdateRooms hides is not solid either.
func set_collidable(on: bool) -> void:
	if on == collidable:
		return
	collidable = on
	shell.collision_layer = 1 if on else 0
	var bodies: Array = []
	for body: StaticBody3D in find_children("*", "StaticBody3D", true, false):
		if body != shell and not body.is_in_group("pickup"):
			bodies.append(body)
	set_solid(bodies, on)

# Takes the bodies out of collisions and back, keeping the layer each one had.
static func set_solid(bodies: Array, on: bool) -> void:
	for entry in bodies:
		if not is_instance_valid(entry):
			continue
		var body: StaticBody3D = entry
		if on:
			if body.has_meta("solid_layer"):
				body.collision_layer = int(body.get_meta("solid_layer"))
				body.remove_meta("solid_layer")
		elif body.collision_layer != 0:
			body.set_meta("solid_layer", body.collision_layer)
			body.collision_layer = 0

func restore_fill_doors() -> void:
	for door in _fill_doors:
		if is_instance_valid(door):
			door.reset_to(bool(door.get_meta("fill_open")), bool(door.get_meta("fill_locked")))

func floor_y(local_x: float, local_z: float, max_y: float = 2.2) -> float:
	var y := MeshLoader.floor_y(collision_faces, local_x, local_z, max_y)
	return 0.35 if y < -100.0 else y

# RotateEntity(model, pitch, yaw, roll) of LoadRMesh as Euler angles. The sign convention is empirical: yaw and roll carry
# over, pitch is negated (the 914 ROLL_SIGN and the room205 prop checks pin it).
static func prop_rotation(blitz_degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(-blitz_degrees.x), deg_to_rad(blitz_degrees.y), deg_to_rad(blitz_degrees.z))

func _add_props(entities: Array) -> void:
	var props_root := ContentPaths.assets_root.path_join("GFX/map/Props")
	for entity in entities:
		if str(entity.get("kind", "")) != "model" or str(entity.get("file", "")).is_empty():
			continue
		var mesh := MeshLoader.load_x(props_root.path_join(str(entity.file)))
		if mesh.get_surface_count() == 0:
			continue
		var prop := MeshInstance3D.new()
		prop.mesh = mesh
		prop.position = entity.position
		var rot: Vector3 = entity.rotation
		prop.rotation = prop_rotation(rot)
		prop.scale = entity.scale
		add_child(prop)
		_add_prop_sight_body(prop, mesh)

# Props are EntityPickMode 2 in the original, so they block EntityVisible. They stay off the player's layer: only the light
# sprites' sight ray (LightSprites.SIGHT_LAYER) sees them.
func _add_prop_sight_body(prop: MeshInstance3D, mesh: Mesh) -> void:
	var local_faces := mesh.get_faces()
	if local_faces.is_empty():
		return
	var faces := PackedVector3Array()
	faces.resize(local_faces.size())
	var transform := prop.transform
	for i in local_faces.size():
		faces[i] = transform * local_faces[i]
	var body := StaticBody3D.new()
	body.collision_layer = LightSprites.SIGHT_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

# CreateScreen: a click target at each rmesh "screen" entity that shows a picture (GFX/screens).
func _add_screens(entities: Array) -> void:
	for entity in entities:
		if str(entity.get("kind", "")) != "screen" or str(entity.get("image", "")).is_empty():
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 16   # seen by the interact ray only
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.1
		shape.shape = sphere
		body.add_child(shape)
		body.position = entity.position
		body.set_meta("screen_image", "GFX/screens/" + str(entity.image))
		add_child(body)

var lights: Array[Light3D] = []

# The rmesh "light" and "spotlight" entities (AddTempLight / AddLight): Blitz point lights with
# range / 2000, color * min(intensity * 0.8, 1) and attenuation 1 / range, which light the
# entities (doors, items, NPCs) but not the lightmapped room. The facility only shows the lights
# within 8.5 units of the camera, like UpdateRoomLights.
func _add_lights(entities: Array) -> void:
	lights.append_array(add_rmesh_lights(self, entities, room_name.to_lower() in LightSprites.VOLUME_ROOMS))

static func add_rmesh_lights(owner: Node3D, entities: Array, volume: bool) -> Array[Light3D]:
	var made: Array[Light3D] = []
	for entity in entities:
		var kind := str(entity.get("kind", ""))
		if kind != "light" and kind != "spotlight":
			continue
		var at: Vector3 = entity.position
		if at.is_zero_approx():
			continue   # the original skips lights left at the origin
		var unit_range := float(entity.get("range", 1000.0)) / 2000.0
		var channels := str(entity.get("color", "255 255 255")).split(" ", false)
		var strength := minf(float(entity.get("intensity", 1.0)) * 0.8, 1.0)
		var color := Color(1, 1, 1)
		if channels.size() >= 3:
			color = Color(float(channels[0]) / 255.0, float(channels[1]) / 255.0, float(channels[2]) / 255.0)
		# LoadRMesh reads a "spotlight" like a "light": AddTempLight ltype 2, a point light (MapSystem.bb 640)
		var light := OmniLight3D.new()
		light.omni_range = clampf(unit_range * 6.0, 1.0, 12.0)
		light.omni_attenuation = 2.0
		light.light_color = color
		light.light_energy = strength
		# LoadRMesh: r = Int(colour) * intensity; the glow, the cone and the fog of war all use that scaled colour
		var scaled := Color(floorf(color.r * 255.0 * strength) / 255.0, floorf(color.g * 255.0 * strength) / 255.0, floorf(color.b * 255.0 * strength) / 255.0)
		light.shadow_enabled = false
		light.visible = false
		light.position = at
		# what the models are lit with (EntityMaterial): LightRange and LightColor Int(colour) * intensity
		light.set_meta("blitz_range", unit_range)
		light.set_meta("blitz_colour", Color(roundf(color.r * 255.0 * strength) / 255.0, roundf(color.g * 255.0 * strength) / 255.0, roundf(color.b * 255.0 * strength) / 255.0))
		owner.add_child(light)
		made.append(light)
		LightSprites.attach(owner, light, scaled, volume)
	return made

# Elevator pairs per room: [door slot A, door slot B, cab marker A, cab marker B]
# (UpdateEvents calls UpdateElevators with exactly these). The maintenance-tunnel elevators of
# room2tunnel are made by mt_event.gd once the tunnels exist.
const ELEVATORS := {
	"room2nuke": [[0, 1, 4, 5]],
	"room3storage": [[0, 1, 0, 1], [2, 3, 2, 3]],
	"room049": [[0, 1, 0, 1], [2, 3, 2, 3]],
	"exit1": [[0, 1, 8, 9]],
}

# FillRoom: the room's own doors and items (data/room_fill.json), and elevators.
var cams: Array[Node3D] = []
var fill_objects: Dictionary = {}    # FillRoom Objects[n]: the pivots (room-local, z flipped)

# CreateItem turns the item to Rand(360) (Items.bb:391) while the room is still unturned, and FillRoom may turn it after
# (room-relative "yaw"). "draw" is the item's place in its room's FillRoom draws (-1 where an earlier draw is conditional).
func _item_yaw(def: Dictionary) -> float:
	if def.has("yaw"):
		return float(def.yaw)
	var draw := int(def.get("draw", -1))
	if draw < 0 or fill_rng < 0:
		return INF
	var rng := BlitzRng.new()
	rng.state = fill_rng
	for _i in draw:
		rng.rand(0, 1)
	return float(rng.rand(360))

func _spawn_fill() -> void:
	var fill := RoomFill.for_room(room_name)
	if fill.is_empty() and generated_items.is_empty():
		return
	var door_index := 0
	for def in fill.get("doors", []):
		if str(def.code) == "GEAR" and room_name.begins_with("checkpoint") and not bool(record_below_empty):
			continue
		var big := int(def.big)
		var sid := "%s|d%d" % [room_key, door_index]
		door_index += 1
		var saved: Dictionary = GameState.door_states.get(sid, {})
		var door := Node3D.new()
		door.set_script(DoorScript)
		door.code = _resolve_code(str(def.code))
		door.elevator = big == 3
		door.button_move = def.get("button_move", {})
		door.button_push = def.get("button_push", {})
		for freed in def.get("free_buttons", []):
			door.free_buttons.append(int(freed))
		door.booth = int(def.get("dir", 0)) == 4
		door.hit_mesh = bool(def.get("hit_mesh", false))
		add_child(door)
		var local := Vector3(float(def.x), float(def.y), -float(def.z))
		door.place_in_room(local, float(def.yaw), big == 1, bool(saved.get("open", def.open)), big == 2, int(def.keycard), bool(def.buttons))
		if bool(def.get("single", false)):
			door.drop_second_leaf()   # FreeEntity(dobj2): this door has one leaf
		door.locked = bool(saved.get("locked", def.locked))
		door.set_meta("sid", sid)
		door.set_meta("fill_open", bool(def.open))
		door.set_meta("fill_locked", bool(def.locked))
		_fill_doors.append(door)
		if big != 3:
			_door_points.append(door.global_position + Vector3(0.0, 0.18, 0.0))   # CreateWaypoint at the frame
		var slot := int(def.slot)
		if slot >= 0:
			door_slots[slot] = door
		door.room = self
		door.room_name = room_name
		door.reparent(get_parent())    # InitNewGame (Main.bb 8411) un-parents every door: UpdateDoors alone decides if one is drawn
	_configure_door_timers()
	for def in fill.get("cams", []):
		var cam := Node3D.new()
		cam.set_script(SecurityCam)
		add_child(cam)
		cam.setup(self, def)
		cams.append(cam)
	var item_index := 0
	for def in fill.get("items", []) + generated_items:
		var iid := "%s|i%d" % [room_key, item_index]
		item_index += 1
		if GameState.taken_items.has(iid):
			continue   # already in the player's hands (or dropped elsewhere)
		var pickup := RoomFill.make_pickup(str(def.name), str(def.tempname))
		pickup.set_meta("fill_id", iid)
		pickup.set_meta("state", float(def.get("state", 0.0)))   # itstate (goggle batteries)
		add_child(pickup)
		pickup.position = Vector3(float(def.x), float(def.y), -float(def.z))
		var yaw := _item_yaw(def)
		if yaw != INF:
			pickup.rotation.y = deg_to_rad(yaw)
	var wanted: Dictionary = {}
	for pair in ELEVATORS.get(room_name, []):
		wanted[int(pair[2])] = true
		wanted[int(pair[3])] = true
	fill_objects.clear()
	for key in fill.get("objects", {}):
		var spot: Dictionary = fill.objects[key]
		fill_objects[int(key)] = Vector3(float(spot.x), float(spot.y), -float(spot.z))
	var markers: Dictionary = {}
	for key in fill.get("objects", {}):
		if not wanted.has(int(key)):
			continue
		var m: Dictionary = fill.objects[key]
		var marker := Node3D.new()
		marker.position = Vector3(float(m.x), float(m.y), -float(m.z))
		add_child(marker)
		markers[int(key)] = marker
	for pair in ELEVATORS.get(room_name, []):
		if door_slots.has(pair[0]) and door_slots.has(pair[1]) and markers.has(pair[2]) and markers.has(pair[3]):
			var lift := Node.new()
			lift.set_script(ElevatorScript)
			add_child(lift)
			lift.setup(door_slots[pair[0]], door_slots[pair[1]], markers[pair[2]], markers[pair[3]])
			lift.state = float(GameState.elevator_states.get("%s|e%d" % [room_key, _lifts.size()], 0.0))
			lift.slam_096 = room_name == "exit1"
			_lifts.append(lift)

	_build_room_extras()
	_build_emitters()

# Cached: about twenty room scripts ask for it every frame and the loop below visits every collision vertex.
var _bounds_cache := AABB()
var _bounds_transform := Transform3D()

func world_bounds() -> AABB:
	if _bounds_cache.size != Vector3.ZERO and _bounds_transform == global_transform:
		return _bounds_cache
	_bounds_transform = global_transform
	_bounds_cache = _compute_world_bounds()
	return _bounds_cache

func _compute_world_bounds() -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in collision_faces:
		lo = lo.min(v)
		hi = hi.max(v)
	if lo.x == INF:
		return AABB(global_position - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
	return global_transform * AABB(lo, hi - lo)

# A lift whose doors the room makes after it is built (the maintenance tunnels'): its trip counter is saved with the room's others.
func adopt_lift(lift: Node) -> void:
	lift.state = float(GameState.elevator_states.get("%s|e%d" % [room_key, _lifts.size()], 0.0))
	_lifts.append(lift)

func release_lift(lift: Node) -> void:
	_lifts.erase(lift)

# Copies the doors' and lifts' state into GameState, where the save takes it and a loaded game's rooms read it back.
func save_state() -> void:
	for door in _fill_doors:
		if is_instance_valid(door):
			GameState.door_states[str(door.get_meta("sid"))] = {"open": door.open, "locked": door.locked}
	for i in _lifts.size():
		if is_instance_valid(_lifts[i]):
			GameState.elevator_states["%s|e%d" % [room_key, i]] = _lifts[i].state

# "$ACCESS" is the run's AccessCode; "$ACCESS3" is room2tunnel's (AccessCode * 3) mod 10000,
# pushed up to at least 1000 (FillRoom, "room2tunnel").
func _resolve_code(raw: String) -> String:
	match raw:
		"$ACCESS":
			return GameState.access_code
		"$ACCESS3":
			var value := (int(GameState.access_code) * 3) % 10000
			if value < 1000:
				value += 1000
			return str(value)
	return raw

# The rmesh waypoint markers in world space (what the NPCs path along and teleport to).
func waypoint_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _waypoints_local:
		out.append(to_global(p))
	return out

# 0 = ordinary floor, 1 = metal (Data/materials.ini stepsound), under a world position.
func step_type_at(world_pos: Vector3) -> int:
	var local := to_local(world_pos)
	return MeshLoader.step_type_at(collision_faces, _drawn_start, _drawn_metal, local.x, local.z, local.y + 0.4)

# World positions of this room's own door waypoints (elevator doors have none).
func door_waypoint_positions() -> Array[Vector3]:
	return _door_points

# CheckTriggers: the name of the trigger box the point is inside (axis-aligned in the world), or "".
func trigger_at(world_pos: Vector3) -> String:
	for box in triggers:
		var corners: Array[Vector3] = []
		for sx in [box.low.x, box.high.x]:
			for sy in [box.low.y, box.high.y]:
				for sz in [box.low.z, box.high.z]:
					corners.append(to_global(Vector3(sx, sy, sz)))
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for corner in corners:
			low = low.min(corner)
			high = high.max(corner)
		if world_pos.x > low.x and world_pos.x < high.x and world_pos.y > low.y and world_pos.y < high.y and world_pos.z > low.z and world_pos.z < high.z:
			return str(box.name)
	return ""

# Objects[n] of FillRoom in world space, or INF when the room has no such pivot.
func object_point(index: int) -> Vector3:
	if not fill_objects.has(index):
		return Vector3.INF
	return to_global(fill_objects[index])

# FillRoom: the checkpoint doors (RoomDoors[0] and [1], linked, 5 s) and the lock room doors (linked pair, 5 s) stay open for 5 s.
func _configure_door_timers() -> void:
	match room_name:
		"checkpoint1", "checkpoint2":
			var a: Node3D = door_slots.get(0)
			var b: Node3D = door_slots.get(1)
			if a != null and b != null:
				a.timer_frames = 70.0 * 5.0
				b.timer_frames = 70.0 * 5.0
				a.linked_door = b
				b.linked_door = a
		"lockroom", "lockroom3":
			for door in _fill_doors:
				door.timer_frames = 70.0 * 5.0
			_link_first_two_doors()
		"room2doors", "room035":
			_link_first_two_doors()

# FillRoom's d\LinkedDoor = d2 : d2\LinkedDoor = d: the first two doors made open and close together.
func _link_first_two_doors() -> void:
	if _fill_doors.size() >= 2:
		_fill_doors[0].linked_door = _fill_doors[1]
		_fill_doors[1].linked_door = _fill_doors[0]

const Room2slProps = preload("res://scripts/world/room2sl_props.gd")
const CheckpointMonitors = preload("res://scripts/world/checkpoint_monitors.gd")
const Scp008Room = preload("res://scripts/world/scp008_room.gd")
const MedibayEvent = preload("res://scripts/world/medibay_event.gd")
const ServersEvent = preload("res://scripts/world/servers_event.gd")
const Room3ServersEvent = preload("res://scripts/world/room3servers_event.gd")
const Exit1Event = preload("res://scripts/world/exit1_event.gd")
const NukeLevers = preload("res://scripts/world/nuke_levers.gd")
const GateAEvent = preload("res://scripts/world/gatea_event.gd")
const ControlRoom = preload("res://scripts/world/control_room.gd")
const Room079Event = preload("res://scripts/world/room079_event.gd")
const GateEntrance = preload("res://scripts/world/gate_entrance.gd")
const FemurRoom = preload("res://scripts/world/femur_room.gd")
const Scp914Room = preload("res://scripts/world/scp914_room.gd")
const Room049Event = preload("res://scripts/world/room049_event.gd")
const Room966Event = preload("res://scripts/world/room966_event.gd")
const Room895Event = preload("res://scripts/world/room895_event.gd")
const Room860Event = preload("res://scripts/world/room860_event.gd")
const Cafeteria294 = preload("res://scripts/world/cafeteria_294.gd")
const Room012Event = preload("res://scripts/world/room012_event.gd")
const Room1162Event = preload("res://scripts/world/room1162_event.gd")
const Room205Event = preload("res://scripts/world/room205_event.gd")
const Room035Event = preload("res://scripts/world/room035_event.gd")
const Room3StorageEvent = preload("res://scripts/world/room3storage_event.gd")
const Room1123Event = preload("res://scripts/world/room1123_event.gd")
const BrokenLiftButtons = preload("res://scripts/world/broken_lift_buttons.gd")
const Room2StorageEvent = preload("res://scripts/world/room2storage_event.gd")
const MtEventScript = preload("res://scripts/world/mt_event.gd")
var extras: Node3D = null
var emitter_voices: Array[AudioStreamPlayer3D] = []    # the voice RoomAmbience loops for each emitter, by slot
var emitters: Array[Dictionary] = []    # the first 8 rmesh soundemitters (position, id, range), FillRoom's SoundEmitter slots
var jets: Array[Dictionary] = []    # this room's particle emitters, in the order FillRoom made them (room035 moves its two)
var fan: Node3D = null          # room2_2's fan (Objects[0]), turned by the room2fan event

const ROOM_EXTRAS := {
	"room2sl": Room2slProps,
	"008": Scp008Room,
	"gatea": GateAEvent,
	"gateaentrance": GateEntrance,
	"room2ccont": ControlRoom,
	"room079": Room079Event,
	"room106": FemurRoom,
	"room2cafeteria": Cafeteria294,
	"room049": Room049Event,
	"room1162": Room1162Event,
	"room2storage": Room2StorageEvent,
	"room1123": Room1123Event,
	"room3storage": Room3StorageEvent,
	"room035": Room035Event,
	"room205": Room205Event,
	"room012": Room012Event,
	"room860": Room860Event,
	"coffin": Room895Event,
	"room966": Room966Event,
	"914": Scp914Room,
	"room2nuke": NukeLevers,
	"exit1": Exit1Event,
	"room2servers": ServersEvent,
	"room3servers": Room3ServersEvent,
	"medibay": MedibayEvent,
	"room2tunnel": MtEventScript,
}

# Things FillRoom builds in code that are not doors, items or cameras.
func _build_room_extras() -> void:
	if ROOM_EXTRAS.has(room_name):
		_attach_extras(ROOM_EXTRAS[room_name]).build(self)
	match room_name:
		"checkpoint1", "checkpoint2":
			_attach_extras(CheckpointMonitors).build(self, room_name)
		"room2tesla", "room2tesla_lcz", "room2tesla_hcz":
			var sign_mesh := MeshInstance3D.new()
			sign_mesh.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/room2tesla_caution.b3d"))
			sign_mesh.scale = Vector3.ONE * (8.0 / 2048.0)
			add_child(sign_mesh)
		"room2_2":
			fan = Node3D.new()
			var fan_mesh := MeshInstance3D.new()
			fan_mesh.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/fan.b3d"))
			fan_mesh.scale = Vector3.ONE * (8.0 / 2048.0)
			fan.add_child(fan_mesh)
			add_child(fan)
			fan.position = Vector3(-248.0, 528.0, 0.0) * (8.0 / 2048.0)
		"lockroom2":
			_add_lockroom2_blood()
		"room2gw_b":
			_add_gw_b_blood()
		"start":
			_fill_decal("GFX/decal1.png", 272.0, 0.005, 262.0)
			_fill_decal("GFX/decal1.png", 456.0, 0.005, 135.0)
		"room2tunnel":
			_fill_decal("GFX/decal1.png", 64.0, 0.005, 144.0)
		"room2poffices2":
			_fill_decal("GFX/decal1.png", -808.0, 0.005, -72.0)
			_fill_decal("GFX/decal3.png", -808.0, 0.01, -72.0, 0.3)
			_fill_decal("GFX/decal1.png", -432.0, 0.01, 0.0)
		"room2scps":
			for i in ROOM2SCPS_DROPS.size():
				var drop: Vector2 = ROOM2SCPS_DROPS[i]
				_fill_decal("GFX/blooddrop%d.png" % randi_range(1, 2), drop.x, 0.005, drop.y, randf_range(0.2, 0.25) if i > 10 else randf_range(0.1, 0.17))
		"room1lifts":
			_attach_extras(BrokenLiftButtons).build([[96.0, 160.0, 64.0, 0.0], [-96.0, 160.0, 64.0, 0.0]])
		"room2shaft":
			_attach_extras(BrokenLiftButtons).build([[1181.0, 180.0, -512.0, 270.0]])
			_fill_decal("GFX/decal4.png", 1334.0, -796.0 * EMITTER_SCALE + 0.01, -220.0, 0.25)

# FillRoom "lockroom2" (MapSystem.bb:2266): six splats with two blood drops each. The drops' CreateDecal results are not assigned to
# `de`, so the splat is rescaled by their Rnd(0.1,0.6) sizes and ends at the last one, while the drops keep size 1. The offsets are
# added to the room's position unrotated, in world axes, so they are turned back into the room's local frame here.
func _add_lockroom2_blood() -> void:
	var scale := 8.0 / 2048.0
	for i in 6:
		var specs: Array = [
			["GFX/decal%d.png" % randi_range(3, 4), _blitz_offset(randf_range(-392.0, 520.0) * scale, randf_range(-392.0, 520.0) * scale), 0.0],
			["GFX/blooddrop%d.png" % randi_range(1, 2), _blitz_offset(randf_range(-392.0, 520.0) * scale, randf_range(-392.0, 520.0) * scale), 1.0],
			["GFX/blooddrop%d.png" % randi_range(1, 2), _blitz_offset(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)), 1.0],
		]
		var splat_size := randf_range(0.1, 0.6)
		for spec in specs:
			_decal_quad(spec[0], splat_size if spec[2] == 0.0 else 1.0, spec[1] + Vector3(0.0, 3.0 * scale + randf_range(0.0, 0.001), 0.0))

func _blitz_offset(dx: float, dz: float) -> Vector3:
	return transform.basis.inverse() * Vector3(dx, 0.0, -dz)

# FillRoom "room2gw_b" (MapSystem.bb:5061): the blood pool under the dead guard, a size 0.5 decal made at build time in every such room.
func _add_gw_b_blood() -> void:
	_decal_quad("GFX/decal4.png", 0.5, _raw(-156.825, -37.3458, 121.364))

# FillRoom's CreateDecal(id, r\x + x * RoomScale, y, r\z + z * RoomScale, 90, Rand(360), 0), parented to r\obj before CreateMap
# turns the room: x and z are room units in the room's own frame, y is in metres, `size` is de\Size (ScaleSprite).
func _fill_decal(texture_file: String, x: float, y: float, z: float, size: float = 1.0) -> void:
	_decal_quad(texture_file, size, Vector3(x * EMITTER_SCALE, y, -z * EMITTER_SCALE))

# A decal flat on the floor at a random turn: a quad 2 x de\Size across, lit like a model (EntityFX 0).
func _decal_quad(texture_file: String, size: float, local_position: Vector3) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 2.0 * size
	quad.mesh = mesh
	quad.material_override = GammaBlend.decal(MeshLoader._load_texture_intensity_alpha(ContentPaths.existing_image(texture_file)), Color.WHITE)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.add_to_group(&"fill_decals")
	add_child(quad)
	quad.position = local_position
	quad.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)

# FillRoom "room2scps" (MapSystem.bb 4084-4136): the trail of blood drops, Case 0 to 14.
const ROOM2SCPS_DROPS := [
	Vector2(-64.0, -516.0), Vector2(-96.0, -388.0), Vector2(-128.0, -292.0), Vector2(-128.0, -132.0), Vector2(-160.0, -36.0),
	Vector2(-192.0, 28.0), Vector2(-384.0, 28.0), Vector2(-448.0, 92.0), Vector2(-480.0, 124.0), Vector2(-512.0, 156.0),
	Vector2(-544.0, 220.0), Vector2(-544.0, 380.0), Vector2(-544.0, 476.0), Vector2(-544.0, 572.0), Vector2(-544.0, 636.0),
]

func _attach_extras(script: GDScript) -> Node3D:
	extras = Node3D.new()
	extras.set_script(script)
	add_child(extras)
	return extras

# ---- gas and steam jets (FillRoom's CreateEmitter, particles.gd) ---------------------------------------------------------

const EMITTER_SCALE := 8.0 / 2048.0

# Raw numbers of FillRoom (x, y, z) in the room's own scaled space -> room-local here (z flipped).
func _raw(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * EMITTER_SCALE, y * EMITTER_SCALE, -z * EMITTER_SCALE)

func _jet(facility: FacilityMap, local_at: Vector3, local_heading: Vector3, settings: Dictionary) -> Dictionary:
	var emitter: Dictionary = facility.particles.add_emitter(to_global(local_at), global_transform.basis * local_heading, self, room_key, settings)
	jets.append(emitter)
	return emitter

func _build_emitters() -> void:
	var facility := get_tree().get_first_node_in_group("facility") if is_inside_tree() else null
	if facility == null or facility.particles == null:
		return
	match room_name:
		"start":
			# CreateDevilEmitter(r\x + 3384, r\y + 510, r\z + 2400, r, 1, 4): ParticleEffect[1], the rising smoke
			facility.particles.add_devil_smoke(to_global(_raw(3384.0, 510.0, 2400.0)), room_key)
		"lockroom":
			# decontamination jets in the ceiling: they blow down and the gas climbs again
			var gas := {"rand_angle": 20.0, "speed": 0.05, "size_change": 0.007, "a_change": -0.006, "gravity": -0.24}
			_jet(facility, _raw(-175.0, 370.0, 656.0), Vector3.DOWN, gas)
			_jet(facility, _raw(-655.0, 370.0, 240.0), Vector3.DOWN, gas)
		"room2pit":
			# six jets along the sides of the pit, aimed across it and 45 degrees up
			var steam := {"rand_angle": 30.0, "speed": 0.0045, "size_change": 0.007, "a_change": -0.016}
			for side in [-1.0, 1.0]:
				for row in [-1.0, 0.0, 1.0]:
					_jet(facility, _raw(202.0 * side, 8.0, 256.0 * row), Vector3(-side, 1.0, 0.0).normalized(), steam)
		"room035":
			# FillRoom puts these at a height of 10 (no RoomScale), far above the chamber
			var contamination := {"rand_angle": 15.0, "speed": 0.05, "size_change": 0.007, "a_change": -0.006, "gravity": -0.24}
			for i in 2:
				_jet(facility, Vector3(-272.0 * EMITTER_SCALE, 10.0, -(624.0 - i * 512.0) * EMITTER_SCALE), Vector3.DOWN, contamination)
		"room3storage":
			var pipe := {"rand_angle": 15.0, "speed": 0.03, "size_change": 0.01, "a_change": -0.006, "gravity": -0.2}
			_jet(facility, _raw(5218.0, -5584.0, -600.0), Vector3(0.926, -0.342, 0.163).normalized(), pipe)
		"room3pit":
			var vent := {"rand_angle": 55.0, "speed": 0.0005, "a_change": -0.015, "size_change": 0.007}
			_jet(facility, _raw(512.0, -76.0, -688.0), Vector3.UP, vent)
			_jet(facility, _raw(-512.0, -76.0, -688.0), Vector3.UP, vent)
		"room2cpit":
			var cvent := {"rand_angle": 55.0, "speed": 0.0005, "a_change": -0.015, "size_change": 0.007}
			_jet(facility, _raw(512.0, -76.0, -688.0), Vector3.UP, cvent)
