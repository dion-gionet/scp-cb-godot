extends Node3D
# SCP-079's chamber (MapSystem.bb FillRoom "room079", UpdateEvents.bb Case "room079"): the old computer (079.b3d, 1.3 times
# scaled, turned round) with its face on a small screen (Objects[1], hidden until she speaks), and a dead guard slumped by the
# door (Objects[2], placed the first time the player is inside). While the player is inside the music is 079's.
#  - RemoteDoorOn (the control room's lever, up at the start): the chamber door (RoomDoors[0]) shuts again with the error click
#    as soon as it is opened enough to pass, so the lever has to be thrown down first.
#  - Lever down: state 1 -> 2 at once; within 3 of the computer she speaks (Speech.ogg, the achievement, EventState2 = 1) and the
#    screen flickers between her angry face and static while she does; afterwards the screen shows the calm face and 2000
#    frames later, if the player is within 2.5, she refuses (Refuse.ogg, state 10001).
#  - EventState2 = 1 and the lever put back up (facility_map._update_079_gates): GateB.ogg, and both gates' doors are free.


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var computer: Node3D
var screen: MeshInstance3D
var guard: Node = null
var _face_angry: Texture2D
var _face_calm: Texture2D

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var model := B3DModel.new()
	model.load_file(ContentPaths.existing_file("GFX/map/079.b3d"))
	computer = model
	computer.scale = Vector3.ONE * 1.3
	computer.position = room.fill_objects.get(0, Vector3.ZERO)
	computer.rotation.y = PI
	add_child(computer)
	var pool_at: Vector3 = room.object_point(2)
	if pool_at != Vector3.INF:
		_place_pool.call_deferred(pool_at + Vector3(0.0, 0.01, 0.0))
	_face_angry = MeshLoader._load_texture(ContentPaths.existing_image("GFX/AIface.jpg"))
	_face_calm = MeshLoader._load_texture(ContentPaths.existing_image("GFX/AIface2.jpg"))
	# CreateSprite(Objects[0]), SpriteViewMode 2 (fixed), ScaleSprite(0.09, 0.0725), turned 13 degrees and moved 0.022 off the screen
	screen = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.145)
	screen.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _face_angry
	screen.material_override = material
	screen.rotation.y = deg_to_rad(13.0)
	var spot: Vector3 = room.fill_objects.get(1, Vector3(0.082, 0.119, -0.01))
	screen.position = spot + Basis(Vector3.UP, deg_to_rad(13.0)) * Vector3(0.0, 0.0, 0.022)
	screen.visible = false
	computer.add_child(screen)

func _place_pool(at: Vector3) -> void:
	GrowingDecal.make(room, at, "GFX/decal4.png", 0.5, 0.0, 1.0, false)

func _show_face(angry: bool) -> void:
	(screen.material_override as StandardMaterial3D).albedo_texture = _face_angry if angry else _face_calm
	screen.visible = true

# Her voice is playing: the angry face flickers (1 in 3 frames shown, else 1 in 10 hidden).
func _flicker() -> void:
	if randi_range(1, 3) == 1:
		_show_face(true)
	elif randi_range(1, 10) == 1:
		screen.visible = false

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	var fps := delta * 70.0
	var door: Node3D = room.door_slots.get(0)
	if not room.world_bounds().has_point(player.global_position):
		if GameState.music_override == "079":
			GameState.music_override = ""
		return
	if facility.events.room079.state == 0.0:
		_place_guard(facility)
		facility.events.room079.state = 1.0
	if GameState.music_override.is_empty():
		GameState.music_override = "079"
	if facility.remote_door_on:
		RemoteDoors.slam(door, player)
		return
	var state: float = facility.events.room079.state
	var near: float = computer.global_position.distance_to(player.global_position)
	if state < 10000.0:
		if state == 1.0:
			facility.events.room079.state = 2.0
		elif state == 2.0:
			if near < 3.0:
				GameState.give_achievement("079")
				facility.events.room079.state = 3.0
				facility.events.room079.state2 = 1.0
				facility.speak_079("SFX/SCP/079/Speech.ogg")
		elif state < 2000.0:
			if facility.speaking_079():
				_flicker()
			else:
				_show_face(false)
				facility.events.room079.state += fps
		elif near < 2.5:
			facility.events.room079.state = 10001.0
			facility.speak_079("SFX/SCP/079/Refuse.ogg")
	elif facility.events.room079.voice != null and is_instance_valid(facility.events.room079.voice):
		if facility.speaking_079():
			_flicker()
		else:
			_show_face(false)

# NPC[0] = CreateNPC(NPCtypeGuard) at Objects[2] + 0.5, turned to face the room's origin, state 8 at frame 288 (slumped dead)
func _place_guard(facility: FacilityMap) -> void:
	var at: Vector3 = room.object_point(2)
	if at == Vector3.INF:
		return
	guard = facility.spawn_human(HumanNpc.Kind.GUARD, at + Vector3(0.0, 0.5, 0.0), -1)
	var to_room: Vector3 = room.global_position - guard.global_position
	guard.rotation.y = atan2(-to_room.x, -to_room.z)
	guard.state = 8
	guard.set_frame(288.0)
