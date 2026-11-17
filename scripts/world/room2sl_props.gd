extends Node3D
# The things MapSystem.bb FillRoom "room2sl" builds in code: a wall of 14 monitors with animated pictures
# (Objects[0..14] except 7), and the lever (Objects[18], [19]) whose position is the checkpoint lockdown:
# lever up (pitch > 0) = lockdown on, the checkpoint monitors flash and the doors are locked; down = off
# (UpdateEvents.bb room2sl: EventState3 = UpdateLever(Levers[0])). The lever is only read while the player is in
# the room, so the lockdown begins when it is first visited (the handle starts at pitch 10: up).
# Monitor 4's picture follows the lever (Objects[20]) and monitor 13's follows SCP-008 (Objects[21]); SCP-008 is
# not in the game yet, so it shows its idle picture.


const RS := MeshLoader.ROOM_SCALE
const SCALE := RS * 4.5 * 0.4

var room: FacilityRoom
var lever: Node3D
var monitors: Array[Node3D] = []
var screens: Dictionary = {}       # monitor index -> the picture quad
var player_inside := false
var wall_shown := true            # the monitors are drawn (the player is not at the hall level)

var _atlas0: Texture2D    # SL_monitors_checkpoint.jpg: 4 frames of 512
var _atlas1: Texture2D    # Sl_monitors.jpg: 8 frames of 256
var _bounds := AABB()

func build(room_node: FacilityRoom) -> void:
	room = room_node
	_atlas0 = MeshLoader._load_texture(ContentPaths.existing_image("GFX/SL_monitors_checkpoint.jpg"))
	_atlas1 = MeshLoader._load_texture(ContentPaths.existing_image("GFX/Sl_monitors.jpg"))
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/monitor.b3d"))
	var box := mesh.get_aabb()
	var size := Vector2(box.size.x, box.size.y) * SCALE * 0.95
	for i in 15:
		if i == 7:
			monitors.append(null)
			continue
		var at := _monitor_place(i)
		var holder := Node3D.new()
		var spot: Vector3 = at[0]
		holder.position = Vector3(spot.x * RS, spot.y * RS, -spot.z * RS)
		holder.rotation.y = deg_to_rad(float(at[1]))
		var model := MeshInstance3D.new()
		model.mesh = mesh
		model.scale = Vector3.ONE * SCALE
		holder.add_child(model)
		var picture := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = size
		picture.mesh = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var shows: Array = [_atlas1, 256, 6] if i == 13 else _frame_for(i)
		_set_picture(material, shows[0], shows[1], shows[2])
		picture.material_override = material
		picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(picture)
		add_child(holder)
		monitors.append(holder)
		screens[i] = picture
	lever = Node3D.new()
	lever.set_script(Lever)
	add_child(lever)
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	lever.add_to_group("sl_lever")
	lever.setup(Vector3(-49.0 * RS, 689.0 * RS, -912.0 * RS), -180.0, facility.events.sl.lever_pitch if facility != null else 10.0)

# [position in RoomScale units (x, y, z), yaw] of monitor i
func _monitor_place(i: int) -> Array:
	if i <= 2:
		return [Vector3(-207.94, 648.0 + 112.0 * i, -60.0686), 105.0]
	if i <= 5:
		return [Vector3(-231.489, 648.0 + 112.0 * (i - 3), 95.7443), 90.0]
	if i <= 8:
		return [Vector3(-231.489, 648.0 + 112.0 * (i - 6), 255.744), 90.0]
	if i <= 11:
		return [Vector3(-231.489, 648.0 + 112.0 * (i - 9), 415.744), 90.0]
	return [Vector3(-208.138, 648.0 + 112.0 * (i - 12), 571.583), 75.0]

# Which picture each monitor shows (the Select in FillRoom) as [atlas, frame size, frame number]; the unlisted ones
# show the lockdown atlas's frame 3.
func _frame_for(i: int) -> Array:
	match i:
		0:
			return [_atlas1, 256, 0]
		2:
			return [_atlas1, 256, 2]
		3:
			return [_atlas1, 256, 1]
		8:
			return [_atlas1, 256, 4]
		9:
			return [_atlas1, 256, 5]
		10:
			return [_atlas1, 256, 3]
		11:
			return [_atlas1, 256, 7]
		4:
			return [_atlas0, 512, 2]
	return [_atlas0, 512, 3]

# LoadAnimTexture: the frames run left to right, top to bottom. An AtlasTexture's region is ignored when it is a 3D
# material's texture (the whole strip comes out squeezed onto the quad), so the frame is picked with the UVs.
func _set_picture(material: StandardMaterial3D, atlas: Texture2D, cell: int, index: int) -> void:
	if atlas == null:
		return
	var columns := maxi(int(atlas.get_width() / cell), 1)
	var rows := maxi(int(atlas.get_height() / cell), 1)
	material.albedo_texture = atlas
	material.texture_repeat = false
	material.uv1_scale = Vector3(1.0 / columns, 1.0 / rows, 1.0)
	material.uv1_offset = Vector3(float(index % columns) / columns, float(index / columns) / rows, 0.0)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null:
		return
	if _bounds.size == Vector3.ZERO and room.has_method("world_bounds"):
		_bounds = room.world_bounds()
	player_inside = _bounds.has_point(player.global_position)
	facility.events.sl.lever_pitch = lever.pitch
	if not player_inside:
		return
	# EventState3 = UpdateLever(Levers[0]); the lever's own update runs in its _physics_process
	facility.events.sl.lever_on = lever.is_on()
	var eight: MeshInstance3D = screens.get(13)
	if eight != null:
		# monitor 13 (Objects[21]): the checkpoint atlas once SCP-008 is dealt with, its own picture before
		var shows: Array = [_atlas0, 512, 3] if facility.events.sl.scp008_done else [_atlas1, 256, 6]
		_set_picture(eight.material_override as StandardMaterial3D, shows[0], shows[1], shows[2])
	var picture: MeshInstance3D = screens.get(4)
	if picture != null:
		var frame := 0
		if lever.is_on():
			frame = 1 if facility.monitor_timer < 50.0 else 2
		_set_picture(picture.material_override as StandardMaterial3D, _atlas0, 512, frame)
	_show_wall(player)

# The monitors and the room's own camera screen are only drawn while the player is on another level than the hall
# door (Abs(EntityY(RoomDoors[0]\frameobj) - EntityY(Collider)) > 1.0): from the hall they would show through the
# floor of the catwalk they stand on.
func _show_wall(player: CharacterBody3D) -> void:
	var hall: Node3D = room.door_slots.get(0)
	if hall == null or not is_instance_valid(hall):
		return
	var wanted := absf(hall.global_position.y - player.global_position.y) > 1.0
	wall_shown = wanted
	for monitor in monitors:
		if monitor != null:
			monitor.visible = wanted
	for camera in room.cams:
		var screen: Node3D = camera._screen
		if screen != null and is_instance_valid(screen):
			screen.visible = wanted
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		# the event's say comes after UpdateRooms': off the hall level the neighbours' meshes are not drawn
		if wanted:
			facility.drawing.neighbours_hidden_by = room
		elif facility.drawing.neighbours_hidden_by == room:
			facility.drawing.neighbours_hidden_by = null
