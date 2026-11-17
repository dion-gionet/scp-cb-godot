extends Node3D


const ROOM_SCALE := 8.0 / 2048.0

static var _streams: Dictionary = {}

var locked := false
var open := false
var big := false
var heavy := false
var keycard := 0
var code := ""
var elevator := false
var elevator_state := 0   # Doors.IsElevatorDoor: 1 callable, 2 moving, 3 car is here
var call_pressed := false
var openstate := 0.0
var _hit_shown := false
var fast_open := false      # d\fastopen: SCP-096 tore it open; the leaves move twice as fast until it is shut again
var leaf_a: Node3D
var leaf_b: Node3D
var buttons: Array[Node3D] = []
# FillRoom PositionEntity(dbuttons[i], ...): the room-local Blitz x / y / z a button was moved to (an axis left out stays the door's
# default) and "yaw" when it was turned to a global heading
var button_move: Dictionary = {}
var free_buttons: Array[int] = []    # FillRoom FreeEntity(dbuttons[i]): the indexes of the buttons this door never gets
# FillRoom MoveEntity(dbuttons[i], x, y, z): raw Blitz offsets along each button's own axes, in the frame's units
var button_push: Dictionary = {}
var hit_mesh := false    # CreateDoor useCollisionMesh: GFX\doorhit.b3d as a HIT_MAP body that exists only while the door is not shut
var hit_body: StaticBody3D
static var _hit_shape: Shape3D
var booth := false    # d\dir = 4, set for the two SCP-914 doors: slower, one leaf
var close_timer := 0.0    # door\timerstate for MTF units: frames until it shuts again (0 = stays)
var timer_frames := 0.0    # door	imer: how long it stays open after a press (checkpoints and lock rooms: 5 s), 0 = until closed
var linked_door: Node3D = null    # doorLinkedDoor: pressing one flips both
var room: Node3D = null    # the room whose FillRoom made it (null for the doors between rooms); doors are not its children
var auto_close := false    # d\AutoClose: slams shut once when the player comes near
var dist := 0.0            # d\dist: |dx| + |dz| to the player, refreshed every 30 ticks
var far := false           # past HideDistance * 2: hidden, no collision, no movement

const HIDE_DISTANCE := NpcGravity.HIDE_DISTANCE
const DIST_REFRESH := 30.0
# MapSystem.bb ValidRoom2slCamRoom (8472): the rooms the room2sl cameras look into
const ROOM2SL_CAM_ROOMS := ["room2closets", "room1archive", "room3z3", "room1lifts", "checkpoint1", "room2nuke", "008", "room1162", "room966", "room2ccont"]
var _dist_timer := 0.0     # UpdateDoorsTimer
var _phased := false
var room_name := "":       # d\room's template name
	set(value):
		room_name = value
		cam_room = value in ROOM2SL_CAM_ROOMS
var cam_room := false      # ValidRoom2slCamRoom(d\room)
var _bodies: Array[StaticBody3D] = []
var _solid := true

func setup(world_pos: Vector3, yaw_degrees: float, is_big: bool, start_open: bool, is_heavy: bool = false, key_level: int = 0) -> void:
	global_position = world_pos
	# Blitz yaw and Godot rotation.y turn the same way once z is flipped (proven on room angles).
	rotation.y = deg_to_rad(yaw_degrees)
	_build(is_big, start_open, is_heavy, key_level, true)

# For a door made as a child of its room (position and yaw are room-local); FacilityRoom un-parents it once it is placed.
func place_in_room(local_pos: Vector3, yaw_degrees: float, is_big: bool, start_open: bool, is_heavy: bool = false, key_level: int = 0, with_buttons: bool = true) -> void:
	position = local_pos
	rotation.y = deg_to_rad(yaw_degrees)
	_build(is_big, start_open, is_heavy, key_level, with_buttons)

func _build(is_big: bool, start_open: bool, is_heavy: bool, key_level: int, with_buttons: bool) -> void:
	add_to_group("door")
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		facility.rooms.mark_doors_dirty()
	big = is_big
	heavy = is_heavy
	keycard = key_level
	open = start_open
	var assets := ContentPaths.assets_root
	if big:
		leaf_a = _leaf(assets.path_join("GFX/map/ContDoorLeft.x"), Vector3.ONE * 55.0 * ROOM_SCALE)
		leaf_b = _leaf(assets.path_join("GFX/map/ContDoorRight.x"), Vector3.ONE * 55.0 * ROOM_SCALE)
		_add_frame(assets.path_join("GFX/map/DoorColl.x"), Vector3.ONE * ROOM_SCALE, false)
	elif elevator:
		leaf_a = _leaf(assets.path_join("GFX/map/elevatordoor.b3d"), Vector3.ONE * ROOM_SCALE)
		leaf_b = _leaf(assets.path_join("GFX/map/elevatordoor.b3d"), Vector3.ONE * ROOM_SCALE)
		leaf_b.rotation.y = PI
		_add_frame(assets.path_join("GFX/map/DoorFrame.x"), Vector3.ONE * ROOM_SCALE, true)
	elif heavy:
		leaf_a = _leaf(assets.path_join("GFX/map/heavydoor1.x"), Vector3.ONE * ROOM_SCALE)
		leaf_b = _leaf(assets.path_join("GFX/map/heavydoor2.x"), Vector3.ONE * ROOM_SCALE)
		leaf_b.rotation.y = PI
		_add_frame(assets.path_join("GFX/map/DoorFrame.x"), Vector3.ONE * ROOM_SCALE, true)
	else:
		var door_mesh := MeshLoader.load_x(assets.path_join("GFX/map/Door01.x"))
		var size := door_mesh.get_aabb().size
		var scale := Vector3(
			(204.0 * ROOM_SCALE) / maxf(size.x, 0.001),
			(312.0 * ROOM_SCALE) / maxf(size.y, 0.001),
			(16.0 * ROOM_SCALE) / maxf(size.z, 0.001)
		)
		leaf_a = _leaf_from_mesh(door_mesh, scale)
		leaf_b = _leaf_from_mesh(door_mesh, scale)
		leaf_b.rotation.y = PI
		# CreateDoor/UpdateDoors: each leaf sits 8 units off the frame centre on its own side.
		leaf_a.position.z = -8.0 * ROOM_SCALE
		leaf_b.position.z = 8.0 * ROOM_SCALE
		_add_frame(assets.path_join("GFX/map/DoorFrame.x"), Vector3.ONE * ROOM_SCALE, true)
	if hit_mesh:
		_add_hit_body()
	if with_buttons:
		_add_buttons()
	_closed_a = leaf_a.position if leaf_a != null else Vector3.ZERO
	_closed_b = leaf_b.position if leaf_b != null else Vector3.ZERO
	if start_open:
		openstate = 180.0
		_slide_to_open()

var _closed_a := Vector3.ZERO     # the leaves' own positions with the door shut
var _closed_b := Vector3.ZERO

# `d\open = False : d\openstate = 0` (UpdateEvents): the door is shut at once, with no closing movement or sound.
func snap_shut() -> void:
	open = false
	openstate = 0.0
	close_timer = 0.0
	fast_open = false
	if leaf_a != null:
		leaf_a.position = _closed_a
	if leaf_b != null:
		leaf_b.position = _closed_b

func reset_to(start_open: bool, start_locked: bool) -> void:
	locked = start_locked
	call_pressed = false
	snap_shut()
	if start_open:
		open = true
		openstate = 180.0
		_slide_to_open()

# UpdateDoors only offers a button while the door is fully open or fully shut: a moving door cannot be used.
func at_rest() -> bool:
	return openstate <= 0.0 or openstate >= 180.0

func npc_open(close_after: float = 0.0) -> void:
	if not open:
		_sound("SFX/Door/DoorOpen173.ogg")
	open = true
	if close_after > 0.0:
		close_timer = close_after

func use(button: Node3D = null) -> void:
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	_sound("SFX/Interact/Button.ogg")
	if elevator:
		call_pressed = true
		if locked:
			# UseDoor: a locked elevator door explains itself instead of opening
			match elevator_state:
				1:
					_say(hud, "You called the elevator.")
				3:
					_say(hud, "The elevator is already on this floor.")
				0:
					_say(hud, "The elevator appears to be broken.")
				_:
					_say(hud, "You already called the elevator.")
			return
	if not code.is_empty():
		var pad := get_tree().get_first_node_in_group("keypad") if is_inside_tree() else null
		if pad:
			pad.open(self, button if button != null else (buttons[0] if not buttons.is_empty() else null))
		else:
			_say(hud, "A keypad is required to operate this door.")
		return
	if keycard < 0:
		# Hand scanners (Main.bb UseDoor): -1 needs the "hand" item, -2 needs "hand2".
		var palm: String = hud.selected_tempname() if hud and hud.has_method("selected_tempname") else ""
		if hud:
			hud.deselect()
		if (keycard == -1 and palm == "hand") or (keycard == -2 and palm == "hand2"):
			_sound("SFX/Interact/ScannerUse1.ogg")
			_say(hud, "You place the palm of the hand onto the scanner. The scanner reads: \"DNA verified. Access granted.\"", 10.0)
		else:
			_sound("SFX/Interact/ScannerUse2.ogg")
			_say(hud, "You placed your palm onto the scanner. The scanner reads: \"DNA does not match known sample. Access denied.\"", 10.0)
			return
	if keycard > 0:
		var held: String = hud.selected_tempname() if hud and hud.has_method("selected_tempname") else ""
		var level := _key_level(held)
		if level < 0:
			_say(hud, "A keycard is required to operate this door.")
			return
		hud.deselect()
		if level < keycard:
			_sound("SFX/Interact/KeycardUse2.ogg")
			if locked:
				_say(hud, "The keycard was inserted into the slot but nothing happened.")
			else:
				_say(hud, "A keycard with security clearance %d or higher is required to operate this door." % keycard)
			return
		if locked:
			_sound("SFX/Interact/KeycardUse2.ogg")
			_say(hud, "The keycard was inserted into the slot but nothing happened.")
			return
		_sound("SFX/Interact/KeycardUse1.ogg")
		_say(hud, "The keycard was inserted into the slot.")
	elif locked:
		_sound("SFX/Interact/Button2.ogg")
		_say(hud, "You pushed the button but nothing happened." if open else "The door appears to be locked.")
		return
	_flip(true)

func _key_level(tempname: String) -> int:
	if tempname.length() == 4 and tempname.begins_with("key") and tempname[3].is_valid_int():
		return int(tempname[3])
	return -1

func _say(hud: Node, text: String, seconds: float = 5.0) -> void:
	if hud and hud.has_method("message"):
		hud.message(text, seconds)

# UpdateDoors (Main.bb 2041-2076): the distance is measured every 30 ticks; past HideDistance * 2 the door and its buttons are
# hidden (HideEntity, which also takes them out of collisions). While the player is in room2sl the doors of the rooms its
# cameras see stay shown.
func _refresh_distance(fps: float) -> void:
	if _dist_timer > 0.0:
		_dist_timer = maxf(_dist_timer - fps, 0.0)
		return
	var player: Node3D = GameState.player
	if player == null:
		return
	dist = absf(player.global_position.x - global_position.x) + absf(player.global_position.z - global_position.z)
	far = dist > HIDE_DISTANCE * 2.0
	var shown := not far
	if far and is_inside_tree():
		var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
		var player_room := facility.drawing.player_room if facility != null else null
		if player_room is FacilityRoom and (player_room as FacilityRoom).room_name == "room2sl":
			shown = cam_room
	_set_shown(shown)
	_dist_timer = DIST_REFRESH
	if not _phased:
		_phased = true
		_dist_timer = fposmod(global_position.x * 7.0 + global_position.z * 13.0, DIST_REFRESH)

func _set_shown(shown: bool) -> void:
	visible = shown
	if shown == _solid:
		return
	_solid = shown
	if _bodies.is_empty():
		_bodies.assign(find_children("*", "StaticBody3D", true, false).filter(func(body: Node) -> bool: return body != hit_body))
	FacilityRoom.set_solid(_bodies, shown)
	_sync_hit_body()

func _add_hit_body() -> void:
	if _hit_shape == null:
		var mesh := MeshLoader.load_b3d(ContentPaths.existing_file("GFX/doorhit.b3d"))
		if mesh.get_surface_count() == 0:
			return
		_hit_shape = mesh.create_trimesh_shape()
	hit_body = StaticBody3D.new()
	hit_body.collision_layer = 0
	hit_body.scale = Vector3.ONE * ROOM_SCALE
	var shape := CollisionShape3D.new()
	shape.shape = _hit_shape
	hit_body.add_child(shape)
	add_child(hit_body)

# UpdateDoors: ShowEntity(DoorHitOBJ) only on frames the door is shutting (not open, openstate > 0), HideEntity once it is
# shut at 0. Opening never hides it, so a door reopened mid-close keeps it until it next shuts.
func _sync_hit_body() -> void:
	if hit_body == null:
		return
	if not open:
		_hit_shown = openstate > 0.0
	var layer := 1 if _hit_shown and _solid else 0
	if hit_body.collision_layer != layer:
		hit_body.collision_layer = layer

func _physics_process(delta: float) -> void:
	if leaf_a == null:
		return
	var fps := delta * 70.0
	_refresh_distance(fps)
	_sync_hit_body()
	if far and not elevator:
		return
	if close_timer > 0.0 and open and openstate >= 180.0:
		var before := close_timer
		close_timer -= fps
		if before > 110.0 and close_timer <= 110.0:
			_sound("SFX/Room/LockroomSiren.ogg")      # CautionSFX: the last 1.5 s
		if close_timer <= 0.0:
			close_timer = 0.0
			open = false
			_play_door_sound(false)
	if auto_close and open and openstate >= 180.0:
		_check_auto_close()
	if open and openstate < 180.0:
		_advance(fps, true)
	elif not open and openstate > 0.0:
		_advance(fps, false)
		_push_player_out(fps)
		if openstate <= 0.0:
			fast_open = false
			leaf_a.position = _closed_a
			if leaf_b != null:
				leaf_b.position = _closed_b
	elif open:
		fast_open = false

# UpdateDoors (Main.bb:2152): with the remote doors on, an AutoClose door shuts when the camera is within 2.1 of it, with
# HorrorSFX(7) unless SCP-714 is worn.
func _check_auto_close() -> void:
	var camera := get_viewport().get_camera_3d()
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if camera == null or facility == null or not facility.remote_door_on:
		return
	if camera.global_position.distance_to(leaf_a.global_position) >= 2.1:
		return
	if not GameState.wearing_714:
		Sfx.play_global(self, "SFX/Horror/Horror7.ogg")
	open = false
	_play_door_sound(false)
	auto_close = false

# UpdateDoors: a door closing on the player slides them off its plane (CurveValue, smooth 5)
# to 0.15 from the frame, within 0.7 * (dir * 2 + 1) along it.
func _push_player_out(fps: float) -> void:
	var player: Node3D = GameState.player
	if player == null or elevator:
		return
	var kind := 4 if booth else (1 if big else (2 if heavy else 0))
	var half_width := 0.7 * (kind * 2 + 1)
	var yaw := fposmod(rotation_degrees.y, 360.0)
	var along_x := is_equal_approx(yaw, 0.0) or is_equal_approx(yaw, 180.0) or is_equal_approx(yaw, 360.0)
	var frame := global_position
	var blend := minf(fps / 5.0, 1.0)
	if along_x:
		if absf(frame.z - player.global_position.z) < 0.15 and absf(frame.x - player.global_position.x) < half_width:
			var target := frame.z + 0.15 * signf(player.global_position.z - frame.z)
			player.global_position.z += (target - player.global_position.z) * blend
	else:
		if absf(frame.x - player.global_position.x) < 0.15 and absf(frame.z - player.global_position.z) < half_width:
			var target := frame.x + 0.15 * signf(player.global_position.x - frame.x)
			player.global_position.x += (target - player.global_position.x) * blend
func _advance(fps: float, opening: bool) -> void:
	var sign_ := 1.0 if opening else -1.0
	if booth:
		openstate = minf(openstate + sign_ * fps * 1.4, 180.0)
		_move_leaf(leaf_a, sign_ * sin(deg_to_rad(openstate)) * fps / 114.0)
	elif big:
		openstate = clampf(openstate + sign_ * fps * 0.8, 0.0, 180.0)
		var step := sin(deg_to_rad(openstate)) * fps / 180.0
		_move_leaf(leaf_a, sign_ * step)
		_move_leaf(leaf_b, -sign_ * step)
		if not opening and openstate < 15.0 and openstate + fps >= 15.0:
			_dust_burst()
	elif elevator:
		var fast := 2.0 if fast_open else 1.0
		openstate = clampf(openstate + sign_ * fps * 2.0 * fast, 0.0, 180.0)
		var lift_step := sin(deg_to_rad(openstate)) * fps * (fast * 2.0 - 1.0 if opening else fast) / 162.0
		_move_leaf(leaf_a, sign_ * lift_step)
		_move_leaf(leaf_b, sign_ * lift_step)
	elif heavy:
		var quick := 2.0 if fast_open else 1.0
		openstate = clampf(openstate + sign_ * fps * 2.0 * quick, 0.0, 180.0)
		var s := sin(deg_to_rad(openstate))
		_move_leaf(leaf_a, sign_ * s * fps * quick / 85.0)
		_move_leaf(leaf_b, sign_ * s * fps * ((quick * 2.0 - 1.0) if opening else quick) / 120.0)
	else:
		var quick_step := 2.0 if fast_open else 1.0
		openstate = clampf(openstate + sign_ * fps * 2.0 * quick_step, 0.0, 180.0)
		var step := sin(deg_to_rad(openstate)) * fps * quick_step / 80.0
		_move_leaf(leaf_a, sign_ * step * ((quick_step * 2.0 - 1.0) / quick_step if opening else 1.0))
		_move_leaf(leaf_b, sign_ * step)

# UpdateDoors (Main.bb:2171) for a big door (dir 1) that is almost shut: 75 to 100 dust motes fall around its frame, with the
# ParticleAmount at FULL.
func _dust_burst() -> void:
	if GameState.particle_amount != 2:
		return
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or facility.particles == null:
		return
	for _i in randi_range(75, 99) + 1:
		var at := global_position + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 1.2), randf_range(-0.2, 0.2))
		var mote = facility.particles.create(at, 2, 0.01, 0.0, 300.0)
		if mote == null:
			return
		mote.speed = 0.005
		mote.dir = Particles.heading(randf_range(-20.0, 20.0), randf() * 360.0)
		mote.size_change = -0.00001
		mote.a_change = -0.01

func _move_leaf(leaf: Node3D, amount: float) -> void:
	if leaf == null:
		return
	var axis := leaf.global_transform.basis.x.normalized()
	leaf.global_position += axis * amount

# The leaves end an opening displaced by the sum of the original's per-frame steps
# (Sin(openstate) / divisor while openstate climbs by `increment` to 180).
static var _travel_cache: Dictionary = {}

static func _travel(increment: float, divisor: float) -> float:
	var key := Vector2(increment, divisor)
	if _travel_cache.has(key):
		return _travel_cache[key]
	var total := 0.0
	var state := 0.0
	while state < 180.0:
		state = minf(state + increment, 180.0)
		total += sin(deg_to_rad(state)) / divisor
	_travel_cache[key] = total
	return total

func _slide_to_open() -> void:
	if booth:
		_move_leaf(leaf_a, _travel(1.4, 114.0))
	elif big:
		var t := _travel(0.8, 180.0)
		_move_leaf(leaf_a, t)
		_move_leaf(leaf_b, -t)
	elif elevator:
		var t := _travel(2.0, 162.0)
		_move_leaf(leaf_a, t)
		_move_leaf(leaf_b, t)
	elif heavy:
		_move_leaf(leaf_a, _travel(2.0, 85.0))
		_move_leaf(leaf_b, _travel(2.0, 120.0))
	else:
		var t := _travel(2.0, 80.0)
		_move_leaf(leaf_a, t)
		_move_leaf(leaf_b, t)

func _leaf(path: String, scale: Vector3) -> Node3D:
	var mesh: ArrayMesh = MeshLoader.load_b3d(path) if path.get_extension().to_lower() == "b3d" else MeshLoader.load_x(path)
	return _leaf_from_mesh(mesh, scale)

func _leaf_from_mesh(mesh: ArrayMesh, scale: Vector3) -> Node3D:
	var leaf := Node3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = scale
	leaf.add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := mesh.get_aabb()
	box.size = Vector3(maxf(aabb.size.x * scale.x, 0.05), maxf(aabb.size.y * scale.y, 0.05), maxf(aabb.size.z * scale.z, 0.05))
	col.shape = box
	col.position = aabb.get_center() * scale
	body.add_child(col)
	leaf.add_child(body)
	add_child(leaf)
	return leaf

# The frame is visual only: the room mesh already has the wall opening, and in the original
# only the leaves have collision (a solid frame box would block the open doorway).
func _add_frame(path: String, scale: Vector3, visible: bool) -> void:
	var mesh := MeshLoader.load_x(path)
	if mesh.get_surface_count() == 0:
		return
	var frame := MeshInstance3D.new()
	frame.mesh = mesh
	frame.scale = scale
	frame.visible = visible
	add_child(frame)
	if visible:
		_add_frame_sight_body(frame, mesh)

# The frame is EntityPickMode 2 (Main.bb 1921, 1992), so it blocks EntityVisible; only the light sprites' sight ray sees this body.
func _add_frame_sight_body(frame: MeshInstance3D, mesh: Mesh) -> void:
	var local_faces := mesh.get_faces()
	if local_faces.is_empty():
		return
	var faces := PackedVector3Array()
	faces.resize(local_faces.size())
	for i in local_faces.size():
		faces[i] = frame.transform * local_faces[i]
	var body := StaticBody3D.new()
	body.collision_layer = LightSprites.SIGHT_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

# CreateDoor: two buttons 0.7 up, 0.6 either side of the frame, 0.1 in front/behind (big doors: 432 / 192 units).
func _add_buttons() -> void:
	var file := "GFX/map/Button.x"
	if not code.is_empty():
		file = "GFX/map/ButtonCode.x"
	elif keycard > 0:
		file = "GFX/map/ButtonKeycard.x"
	elif keycard < 0:
		file = "GFX/map/ButtonScanner.x"
	var mesh := MeshLoader.load_x(ContentPaths.assets_root.path_join(file))
	if mesh.get_surface_count() == 0:
		return
	var slots := [
		[Vector3(0.6, 0.7, 0.1), 0.0],
		[Vector3(-0.6, 0.7, -0.1), PI],
	]
	if big:
		slots = [
			[Vector3(-432.0 * ROOM_SCALE, 0.7, -192.0 * ROOM_SCALE), deg_to_rad(90.0)],
			[Vector3(432.0 * ROOM_SCALE, 0.7, 192.0 * ROOM_SCALE), deg_to_rad(270.0)],
		]
	for index in slots.size():
		if free_buttons.has(index):
			continue
		var slot: Array = slots[index]
		var button := Node3D.new()
		button.position = slot[0]
		button.rotation.y = slot[1]
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.scale = Vector3.ONE * 0.03
		visual.material_override = _button_material(mesh)
		button.add_child(visual)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		body.set_meta("button", true)
		box.size = Vector3(0.12, 0.12, 0.12)
		col.shape = box
		body.add_child(col)
		button.add_child(body)
		add_child(button)
		if button_move.has(str(index)):
			_move_button(button, button_move[str(index)])
		if button_push.has(str(index)):
			var push: Dictionary = button_push[str(index)]
			button.position += button.transform.basis * Vector3(float(push.x), float(push.y), -float(push.z)) * ROOM_SCALE
		buttons.append(button)

# PositionEntity(dbuttons[i], x, y, z, True): the axes FillRoom gives are room-relative, the others stay where CreateDoor put the button.
func _move_button(button: Node3D, spot: Dictionary) -> void:
	var room_node := get_parent() as Node3D
	if room_node == null:
		return
	var local := room_node.to_local(button.global_position)
	if spot.has("x"):
		local.x = float(spot.x)
	if spot.has("y"):
		local.y = float(spot.y)
	if spot.has("z"):
		local.z = -float(spot.z)
	button.global_position = room_node.to_global(local)
	if spot.has("yaw"):
		button.global_basis = room_node.global_basis * Basis(Vector3.UP, deg_to_rad(float(spot.yaw)))

func _play_door_sound(opening: bool) -> void:
	var variant := randi_range(0, 2)
	var verb := "Open" if opening else "Close"
	var file := "Door%s%d" % [verb, variant + 1]
	if big:
		file = "BigDoor%s%d" % [verb, randi_range(0, 1) + 1]
	elif elevator:
		file = "Elevator%s%d" % [verb, variant + 1]
	elif heavy:
		file = "Door2%s%d" % [verb, variant + 1]
	_sound("SFX/Door/%s.ogg" % file)

func _sound(relative: String) -> void:
	if not is_inside_tree():
		return
	var path := ContentPaths.existing_file(relative)
	if not _streams.has(path):
		_streams[path] = AudioStreamOggVorbis.load_from_file(path) if FileAccess.file_exists(path) else null
	var stream: AudioStream = _streams[path]
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.max_distance = 12.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

# Buttons use the same material as every other .x model (winding fixed in the loader).
func _button_material(mesh: ArrayMesh) -> Material:
	var source := mesh.surface_get_material(0)
	var mat := source.duplicate() if source else StandardMaterial3D.new()
	if mat is BaseMaterial3D or mat is EntityMaterial:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		if not code.is_empty():
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

# UseDoor(d, False, playsfx): flips the door without any message.
func toggle(play_sound: bool = true) -> void:
	_flip(play_sound)

# The right code was typed: SelectedDoor\locked = 0 and UseDoor(door).
func keypad_open() -> void:
	locked = false
	_flip(true)

# EntityTexture d\obj, tex: only the first leaf takes the new skin.
func set_leaf_texture(texture: Texture2D) -> void:
	if texture == null or leaf_a == null:
		return
	for child in leaf_a.get_children():
		var visual := child as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		for surface in visual.mesh.get_surface_count():
			var material = visual.mesh.surface_get_material(surface)
			if not (material is BaseMaterial3D or material is EntityMaterial):
				continue
			material = material.duplicate()
			material.albedo_texture = texture
			visual.set_surface_override_material(surface, material)

# Original FillRoom frees d\obj2 on a few doors, leaving a single leaf.
func drop_second_leaf() -> void:
	if leaf_b != null:
		leaf_b.queue_free()
		leaf_b = null

# UseDoor: flip the door and its linked partner; a door that opens starts its close timer (none for an
# ordinary door), one that closes forgets it, so an old timer never shuts a door the player has since opened.
func _flip(play_sound: bool) -> void:
	open = not open
	_apply_timer()
	if linked_door != null and is_instance_valid(linked_door):
		linked_door.open = not linked_door.open
		linked_door._apply_timer()
	if play_sound:
		_play_door_sound(open)

func _apply_timer() -> void:
	close_timer = timer_frames if open else 0.0
