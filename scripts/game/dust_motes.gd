extends Node
# Dust in the air near the camera (Main.bb MouseLook, "pölyhiukkasia", only with the particle option at 2, the default):
# about once in 35 frames a speck (dust.jpg, additive, 0.004 across) appears 0.5-1.0 ahead of the camera in a random
# direction and 0.5 up or down, drifts 0.001 a frame along a random heading and shrinks by 0.00001 a frame, for 300 frames.


var motes: Array = []      # {node, direction, size, life}
var _texture: Texture2D
var _mesh: QuadMesh

func _physics_process(delta: float) -> void:
	var facility := get_parent()
	var player: CharacterBody3D = GameState.player
	if player == null or not facility.active or player.dead or get_tree().paused:
		return
	var fps := delta * 70.0
	if _texture == null:
		_texture = MeshLoader._load_texture(ContentPaths.existing_image("GFX/dust.jpg"))
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
	if randf() * 35.0 < fps:
		_spawn(player.camera.global_position)
	for mote in motes.duplicate():
		var node: MeshInstance3D = mote.node
		node.global_position += mote.direction * 0.001 * fps
		mote.size += -0.00001 * fps
		mote.life -= fps
		if mote.life <= 0.0 or mote.size < 0.00001:
			node.queue_free()
			motes.erase(mote)
		else:
			node.scale = Vector3.ONE * mote.size * 2.0

func _spawn(camera_at: Vector3) -> void:
	var yaw := randf() * TAU
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var at := camera_at + forward * randf_range(0.5, 1.0) + Vector3(0.0, randf_range(-0.5, 0.5), 0.0)
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = GammaBlend.make(_texture, Color.WHITE, true, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ONE * 0.004
	get_parent().add_child(node)
	node.global_position = at
	var heading := randf() * TAU
	var pitch := deg_to_rad(randf_range(-20.0, 20.0))
	motes.append({"node": node, "direction": Vector3(-sin(heading) * cos(pitch), sin(pitch), -cos(heading) * cos(pitch)), "size": 0.002, "life": 300.0})
