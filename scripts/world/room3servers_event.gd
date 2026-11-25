extends Node3D
# room3servers (MapSystem.bb FillRoom, UpdateEvents.bb Case "room3servers"): the duck at Objects[3] (`duck_low_res.b3d`, `duck2.png`,
# scale 0.07). While the player is in the room it bobs (EventState cycles 0-360 at 0.5 per frame after a 1-in-800 roll, eases back
# to 0 after a 1-in-1200 roll), and during a blink (BlinkTimer between -12 and -8) it turns to face the camera. The first time
# BlinkTimer drops below -10 with SCP-173 not idle, 173 is put at a random one of Objects[0..2].

const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var duck: Node3D
var bob_state := 0.0
var bobbing := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var spot: Vector3 = room.fill_objects.get(3, Vector3.INF)
	if spot == Vector3.INF:
		return
	duck = Node3D.new()
	room.add_child(duck)
	var model := B3DModel.new()
	model.load_file(ContentPaths.existing_file("GFX/npcs/duck_low_res.b3d"))
	model.scale = Vector3.ONE * 0.07
	duck.add_child(model)
	var picture := MeshLoader._load_texture(ContentPaths.existing_file("GFX/npcs/duck2.png"))
	var mesh: ArrayMesh = model.mesh_instance.mesh
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		var own: Material = material.duplicate() if (material is StandardMaterial3D or material is EntityMaterial) else MeshLoader.entity_material(picture, false)
		own.albedo_texture = picture
		model.mesh_instance.set_surface_override_material(i, own)
	duck.position = spot

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	if str(facility.record_at(player.global_position).get("key", "")) != room.room_key:
		return
	var fps := delta * 70.0
	var statue := GameState.scp173 as Scp173
	var moved: Dictionary = facility.events.room3servers.moved_173     # EventState3, kept for a save
	if not moved.has(room.room_key) and statue != null and statue.idle == 0 and player.blink_timer < -10.0:
		var spot: Vector3 = room.object_point(randi_range(0, 2))
		if spot != Vector3.INF:
			statue.put_at_collider(spot)
		moved[room.room_key] = true
	if duck == null:
		return
	if player.blink_timer < -8.0 and player.blink_timer > -12.0:
		var toward: Vector3 = player.camera.global_position - duck.global_position
		if Vector2(toward.x, toward.z).length() > 0.001:
			duck.rotation.y = atan2(-toward.x, -toward.z) - room.rotation.y
	if not bobbing:
		bob_state += (0.0 - bob_state) * minf(fps / 15.0, 1.0)
		if randi_range(1, 800) == 1:
			bobbing = true
	else:
		bob_state += fps * 0.5
		if bob_state > 360.0:
			bob_state = 0.0
		if randi_range(1, 1200) == 1:
			bobbing = false
	duck.position.y = -608.0 * RS + 0.05 + sin(deg_to_rad(bob_state + 270.0)) * 0.05
