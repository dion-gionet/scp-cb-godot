extends Node3D
# The checkpoint rooms (checkpoint1: light to heavy containment, checkpoint2: heavy to entrance zone). Two
# monitors (monitor_checkpoint.b3d, Objects[2] and [3]) show the lockdown pictures while the checkpoint is shut
# down; otherwise they are black (UpdateCheckpointMonitors / TurnCheckpointMonitorsOff).
#  - checkpoint1 follows the lever of room2sl: lever up and the player within 12 of the room = monitors flash
#    LockdownScreen2 / 3 (every 50 frames) and both doors are locked; lever down = dark and unlocked.
#  - checkpoint2 is tied to the SCP-008 event: locked and flashing until the lever of the 008 container is pulled
#    (scp008_room.gd), then free and dark.
# Also: the door clunk when the pair opens or closes, and the "ToZone" ambience when the player walks through.

const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var name_of_room := ""
var monitors: Array[MeshInstance3D] = []
var lockdown := false
var passed := false

var _screen_materials: Array = []      # per monitor: the materials that carry the picture
var _picture_a: Texture2D
var _picture_b: Texture2D
var _last_open := false

func build(room_node: FacilityRoom, room_name: String) -> void:
	room = room_node
	name_of_room = room_name
	var base := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/monitor_checkpoint.b3d"))
	_picture_a = MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/LockdownScreen2.jpg"))
	_picture_b = MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/LockdownScreen3.jpg" if room_name == "checkpoint1" else "GFX/map/LockdownScreen.jpg"))
	for index in [2, 3]:
		if not room.fill_objects.has(index):
			continue
		var monitor := MeshInstance3D.new()
		var mesh: ArrayMesh = base.duplicate()
		monitor.mesh = mesh
		monitor.scale = Vector3.ONE * 2.0 * RS      # ScaleEntity 2 under the room entity, which is scaled by RoomScale
		monitor.position = room.fill_objects[index]
		monitor.rotation.y = PI if index == 2 else 0.0
		add_child(monitor)
		monitors.append(monitor)
		# every surface but the first carries a picture, unless it is the monitor's own base texture
		var mats: Array = []
		for surface in mesh.get_surface_count():
			if surface == 0:
				continue
			var old := mesh.surface_get_material(surface)
			if (old is StandardMaterial3D or old is EntityMaterial) and old.albedo_texture != null and old.albedo_texture.resource_path.to_lower().contains("monitortexture"):
				continue
			var screen := StandardMaterial3D.new()
			screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			screen.albedo_color = Color.BLACK
			mesh.surface_set_material(surface, screen)
			mats.append(screen)
		_screen_materials.append(mats)
	var door: Node3D = room.door_slots.get(0)
	_last_open = door != null and door.open

func _show(on: bool, timer: float) -> void:
	for mats in _screen_materials:
		for screen in mats:
			var material := screen as StandardMaterial3D
			if not on:
				material.albedo_texture = null
				material.albedo_color = Color.BLACK
			else:
				material.albedo_color = Color.WHITE
				material.albedo_texture = _picture_a if timer < 50.0 else _picture_b

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null:
		return
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	if door_a == null or door_b == null:
		return
	# checkpoint1 follows the lever of room2sl, checkpoint2 the SCP-008 event (locked until its lever is pulled)
	var wanted_lockdown: bool = facility.events.sl.lever_on if name_of_room == "checkpoint1" else not facility.events.sl.scp008_done
	# r\dist: the larger of the x and z distances to the room's middle (UpdateRooms)
	var reach := RoomRegistry.room_dist(room.global_position, player.global_position)
	if reach < 12.0:
		lockdown = wanted_lockdown
		_show(lockdown, facility.monitor_timer)
		door_a.locked = lockdown
		door_b.locked = lockdown
	elif lockdown:
		_show(true, facility.monitor_timer)    # the picture keeps flashing in the shut-down room while it is far off
	if door_a.open != _last_open:
		Sfx.play_at(door_a, "SFX/Door/DoorCheckpoint.ogg", 14.0)
		Sfx.play_at(door_b, "SFX/Door/DoorCheckpoint.ogg", 14.0)
	_last_open = door_a.open
	if not passed and facility.room_at(player.global_position) == room and player.global_position.z > room.global_position.z:
		passed = true
		Sfx.play_global(self, "SFX/Ambient/ToZone2.ogg" if facility.zone_at(player.global_position) == 1 else "SFX/Ambient/ToZone3.ogg")
