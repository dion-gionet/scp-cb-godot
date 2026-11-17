extends Node3D
# The medibay (MapSystem.bb FillRoom "medibay", UpdateEvents.bb Case "medibay"):
#  - the props (medibay_props.b3d, collision too) are only there while the player is inside the room
#  - the first time the player is inside, an SCP-008-1 (the surgeon) is created lying at Objects[3], facing the room's angle - 90
#  - when the player comes within 1.2 of it, the lights flicker for 12 (LightBlink) with the light-switch sound, and
#    4 seconds later the zombie gets up (state 2)
# What the event has done is kept on the facility (for the saves).


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var _props: Node3D

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/medibay_props.b3d"))
	_props = Node3D.new()
	add_child(_props)
	if mesh != null and mesh.get_surface_count() > 0:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.scale = Vector3.ONE * RS
		_props.add_child(visual)
		var faces := Transform3D(Basis.from_scale(Vector3.ONE * RS), Vector3.ZERO) * mesh.get_faces()
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_props.add_child(body)
	_props.visible = false
	_props.process_mode = Node.PROCESS_MODE_INHERIT

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null:
		return
	var fps := delta * 70.0
	var inside: bool = room.world_bounds().has_point(player.global_position)
	_props.visible = inside
	for body in _props.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 1 if inside else 0
	if inside:
		if not facility.events.medibay.entered:
			facility.events.medibay.entered = true
			var spot: Vector3 = room.object_point(3)
			if spot != Vector3.INF:
				var zombie: Node = facility.spawn_zombie008(spot + Vector3(0.0, 0.05, 0.0), 0)
				zombie.rotation.y = room.rotation.y - PI * 0.5
				facility.events.medibay.zombie = zombie
		var zombie: Node = facility.events.medibay.zombie
		if zombie != null and is_instance_valid(zombie) and zombie.global_position.distance_to(player.global_position) < 1.2:
			if facility.events.medibay.timer == 0.0:
				GameState.light_blink = 12.0
				Sfx.play_global(self, "SFX/General/LightSwitch.ogg")
				facility.events.medibay.timer = fps
	if facility.events.medibay.timer > 0.0 and facility.events.medibay.timer < 70.0 * 4.0:
		facility.events.medibay.timer += fps
	elif facility.events.medibay.timer >= 70.0 * 4.0:
		var zombie: Node = facility.events.medibay.zombie
		if zombie != null and is_instance_valid(zombie) and zombie.state == 0:
			zombie.set_state(2)
