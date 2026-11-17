extends StaticBody3D
class_name WorldItem
# An item lying in the world (Items.bb CreateItem / UpdateItems): the template model under a
# tiny collider, lit by ambient light only, random yaw. It falls at 0.0004 per frame^2
# (1.96 m/s^2) until it touches the map, never falls if there is no ground within 10 units
# below it, and is removed below y = -35. Past 8 units from the camera it is hidden and still.


const GRAVITY := 0.0004 * 70.0 * 70.0
const REST_HEIGHT := 0.01
const HIDE_DIST := 8.0          # Local HideDist = HideDistance * 0.5 (7.5) is an Int in Blitz
const DIST_INTERVAL_MS := 700.0
const CREATED_POSE := {"clipboard": 17.0, "wallet": 0.0}     # CreateItem's SetAnimTime of a container

var item_name := ""
var tempname := ""
var resting := false
var drop_speed := 0.0
var _ground_checked := false
var dist := 0.0                 # i\dist to the camera, re-measured every 700 ms
var _dist_due_ms := 0.0
var _away := false
var pose := -1.0                # the animation frame the model is held at, -1 for a model with no pose
var _visual: MeshInstance3D
var _model_path := ""

func setup(name_: String, tempname_: String, template: Dictionary) -> void:
	item_name = name_
	tempname = tempname_
	collision_layer = 8
	collision_mask = 0
	add_to_group("pickup")
	set_meta("item_name", item_name)
	set_meta("tempname", tempname)
	set_meta("icon", str(template.get("icon", "GFX/items/INVpaper.png")))
	rotation.y = randf() * TAU
	var scale := float(template.get("scale", 1.0))
	var size := Vector3.ONE * 0.12
	var center := Vector3.ZERO
	pose = float(CREATED_POSE.get(tempname_, -1.0))
	var mesh := _load_model(str(template.get("model", "")))
	if mesh and mesh.get_surface_count() > 0:
		_visual = MeshInstance3D.new()
		_visual.mesh = mesh
		_visual.scale = Vector3.ONE * scale
		var override_path := str(template.get("texture", ""))
		if not override_path.is_empty():
			_visual.material_override = _override_material(override_path)
		add_child(_visual)
		var aabb := mesh.get_aabb()
		size = (aabb.size * scale).max(Vector3.ONE * 0.08)
		center = aabb.get_center() * scale
	else:
		add_child(_fallback_sprite(str(template.get("icon", ""))))
	if tempname_ == "cup":
		call_deferred("_build_liquid", scale)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	add_child(shape)

func _load_model(relative: String) -> ArrayMesh:
	if relative.is_empty():
		return null
	var path := ContentPaths.existing_file(relative)
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() == "b3d":
		_model_path = path
		return MeshLoader.load_b3d_posed(path, pose) if pose >= 0.0 else MeshLoader.load_b3d(path)
	return MeshLoader.load_x(path)

# SetAnimTime on the item's model: a clipboard or wallet keeps the frame it was left at while it lies in the world.
func set_pose(frame: float) -> void:
	pose = frame
	set_meta("pose", frame)
	if _visual != null and not _model_path.is_empty():
		_visual.mesh = MeshLoader.load_b3d_posed(_model_path, frame)

func _override_material(relative: String) -> Material:
	var texture: Texture2D = MeshLoader._load_texture(ContentPaths.existing_image(relative))
	return MeshLoader.entity_material(texture, false)

func _fallback_sprite(icon_relative: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	var path := ContentPaths.existing_image(icon_relative)
	if FileAccess.file_exists(path):
		sprite.texture = _masked_texture(path)
	sprite.pixel_size = 0.0015
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	return sprite

# UpdateItems (Items.bb 487-573): past HideDist the collider is hidden, which takes the item out of the picks and the physics.
func _measure_distance() -> void:
	var now: float = GameState.clock_ms()
	if now < _dist_due_ms:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	dist = camera.global_position.distance_to(global_position)
	_dist_due_ms = now + DIST_INTERVAL_MS
	var away := dist >= HIDE_DIST
	if away != _away:
		_away = away
		visible = not away
		collision_layer = 0 if away else 8

# The facility's 700 ms pass over the items that stopped processing: one that is near again resumes.
func recheck_near() -> void:
	_dist_due_ms = 0.0
	_measure_distance()
	if not _away:
		set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_measure_distance()
	if resting or _away:
		if resting and _away:
			set_physics_process(false)
		return
	if global_position.y < -35.0:
		queue_free()
		return
	var space := get_world_3d().direct_space_state
	if not _ground_checked:
		_ground_checked = true
		var probe := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 10.0)
		probe.collision_mask = 1
		if space.intersect_ray(probe).is_empty():
			resting = true
			return
	drop_speed += GRAVITY * delta
	var step := drop_speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.02, 0.0), global_position + Vector3(0.0, -step - REST_HEIGHT, 0.0))
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position.y -= step
	else:
		global_position.y = hit.position.y + REST_HEIGHT
		resting = true
		drop_speed = 0.0

# Called after something moved the item (elevators): make it check for ground again.
func wake() -> void:
	set_physics_process(true)
	resting = false
	_ground_checked = false
	drop_speed = 0.0

static var _mask_cache: Dictionary = {}

# Inventory icons use pure black as the transparency mask (MaskImage in the original).
static func _masked_texture(path: String) -> Texture2D:
	if _mask_cache.has(path):
		return _mask_cache[path]
	var image := MeshLoader.load_image(path)
	if image == null:
		_mask_cache[path] = null
		return null
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r < 0.04 and c.g < 0.04 and c.b < 0.04:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	_mask_cache[path] = texture
	return texture

# ---- cups (Items.bb CreateItem "cup"): the liquid is the cupliquid.x mesh, tinted and see-through (a negative alpha glows)
const CUP_KEYS := ["cr", "cg", "cb", "ca"]

var _liquid: MeshInstance3D = null

# The colour (0..1), alpha (negative: glowing) and name of what the cup holds.
func set_cup(cup_name: String, color: Color, alpha: float) -> void:
	item_name = cup_name
	set_meta("item_name", cup_name)
	set_meta("cr", color.r)
	set_meta("cg", color.g)
	set_meta("cb", color.b)
	set_meta("ca", alpha)
	_paint_liquid()

func _build_liquid(model_scale: float) -> void:
	if _liquid != null:
		return
	var path := ContentPaths.existing_file("GFX/items/cupliquid.x")
	if not FileAccess.file_exists(path):
		return
	var mesh := MeshLoader.load_x(path)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	_liquid = MeshInstance3D.new()
	_liquid.mesh = mesh
	_liquid.scale = Vector3.ONE * model_scale
	add_child(_liquid)
	_paint_liquid()

func _paint_liquid() -> void:
	if _liquid == null:
		return
	var alpha: float = float(get_meta("ca", 1.0))
	var color := Color(float(get_meta("cr", 1.0)), float(get_meta("cg", 1.0)), float(get_meta("cb", 1.0)))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var light := 1.0 if alpha < 0.0 else MeshLoader.entity_ambient()      # EntityFX 1: fullbright when it glows
	material.albedo_color = Color(color.r * light, color.g * light, color.b * light, absf(alpha))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_liquid.material_override = material
	_liquid.visible = absf(alpha) > 0.0
