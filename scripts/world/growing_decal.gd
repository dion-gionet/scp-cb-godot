extends MeshInstance3D
class_name GrowingDecal
# `single_sided`: CreateDecal's sprite has no EntityFX 16, so it is seen from its front only; the wall decals that come in
# pairs facing opposite ways (the 096 server room's windows) need it, or each side shows both.
# A decal that grows (Main.bb CreateDecal / UpdateDecals): a flat sprite on the floor whose `size` (half the side, as
# ScaleSprite takes it) climbs by `size_change` a frame up to `max_size`. The corrosion stain (decal id 0, from
# SCP-106 coming out of the floor) also drops small stains (id 1, 0.1 to 0.5 across) inside itself every 50-100
# frames, each with a decay sound.


var size := 0.05
var size_change := 0.001
var max_size := 1.0
var timer := 0.0
var alpha := 0.8
var alpha_change := 0.0       # per 70 Hz frame, up to 1
var drops := 0                 # small stains left so far (tests)
var drop_stains := true
var texture_file := ""
var multiply := false
var lifetime := 0.0            # 70 Hz frames; a bullet hole is removed once it runs down to 5 (UpdateDecals)

# Every decal made while the game runs; the save keeps them (Save.bb 331-356). Decals built with a room are made again by the rebuild.
const GROUP := &"run_decals"

static func make(parent: Node, at: Vector3, texture_file: String, start_size: float, growth: float, alpha: float = 0.8, stains: bool = true, orientation: Vector3 = Vector3.INF, multiply: bool = false, single_sided: bool = false) -> MeshInstance3D:
	var decal := GrowingDecal.new()
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 2.0)          # a sprite scaled to `size` is 2 * size across
	decal.mesh = _quad
	var path := ContentPaths.existing_image(texture_file)
	if multiply:
		decal.material_override = _multiplied(MeshLoader._load_texture(path))
	else:
		decal.material_override = GammaBlend.decal(MeshLoader._load_texture_intensity_alpha(path), Color(1, 1, 1, alpha))
		if single_sided:
			(decal.material_override as ShaderMaterial).shader = load("res://shaders/gamma_blend_front.gdshader")
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.alpha = alpha
	decal.size = start_size
	decal.size_change = growth
	decal.drop_stains = stains
	decal.texture_file = texture_file
	decal.multiply = multiply
	decal.add_to_group(GROUP)
	parent.add_child(decal)
	decal.global_position = at
	# a floor decal by default (random turn); `orientation` stands it up on a wall instead
	decal.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0) if orientation == Vector3.INF else orientation
	decal.scale = Vector3.ONE * start_size
	return decal

static var _quad: QuadMesh = null
static var _multiplied_by_texture: Dictionary = {}

# EntityBlend 2: the picture darkens what is behind it (the bullet holes, whose paper is white). One material per picture.
static func _multiplied(texture: Texture2D) -> StandardMaterial3D:
	if _multiplied_by_texture.has(texture):
		return _multiplied_by_texture[texture]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	_multiplied_by_texture[texture] = material
	return material

# A drop of blood on the floor under the player (EntityPick 0.3 down from the collider, a decal 0.005 above what it hits) with
# one of the three BloodDrip sounds at a random volume and pitch: bleeding (Main.bb 4310) and SCP-427 (Main.bb 10293).
static func drip(player: CharacterBody3D, texture_file: String, size: float) -> void:
	var from := player.global_position + Vector3(randf_range(-0.05, 0.05), 0.25, randf_range(-0.05, 0.05))
	var hit := MeshLoader.pick_ray(player.get_world_3d().direct_space_state, from, from + Vector3(0.0, -0.3, 0.0), player.get_rid())
	if not hit.is_empty():
		make(player.get_parent(), hit.position + Vector3(0.0, 0.005, 0.0), texture_file, size, 0.0, 1.0, false)
	var voice := Sfx.play_global(player, "SFX/Character/D9341/BloodDrip%d.ogg" % randi_range(0, 2), randf_range(0.0, 0.8))
	if voice != null:
		voice.pitch_scale = randf_range(20000.0, 30000.0) / 44100.0

func _physics_process(delta: float) -> void:
	var fps := delta * 70.0
	if alpha_change != 0.0 and alpha < 1.0:
		alpha = minf(alpha + alpha_change * fps, 1.0)
		(material_override as ShaderMaterial).set_shader_parameter("color", Color(1, 1, 1, alpha))
	if lifetime > 0.0:
		lifetime = maxf(lifetime - fps, 5.0)
		if lifetime == 5.0:
			queue_free()
			return
	if size_change == 0.0:
		return
	size = minf(size + size_change * fps, max_size)
	scale = Vector3.ONE * size
	if drop_stains:
		if timer <= 0.0:
			_drop_stain()
			timer = randf_range(50.0, 100.0)
		else:
			timer -= fps
	if size >= max_size:
		size_change = 0.0

func _drop_stain() -> void:
	var angle := randf() * TAU
	var offset := randf() * size
	var small := _make_stain(get_parent(), randf_range(0.1, 0.5))
	small.global_position = global_position + Vector3(cos(angle) * offset, -0.0005, sin(angle) * offset)
	small.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	drops += 1
	Sfx.play_at(small, "SFX/SCP/106/Decay%d.ogg" % randi_range(1, 3), 10.0, randf_range(0.1, 0.5))

static func _make_stain(parent: Node, half: float) -> MeshInstance3D:
	var small := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0) * half
	small.mesh = quad
	small.material_override = GammaBlend.decal(MeshLoader._load_texture(ContentPaths.existing_image("GFX/decal2.png")))
	small.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	small.set_meta("stain_half", half)
	small.add_to_group(GROUP)
	parent.add_child(small)
	return small

static func _basis_array(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]

static func capture_all(tree: SceneTree) -> Array:
	var out: Array = []
	for node in tree.get_nodes_in_group(GROUP):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.is_queued_for_deletion() or not mesh.is_inside_tree():
			continue
		var at := mesh.global_position
		var record := {"pos": [at.x, at.y, at.z], "basis": _basis_array(mesh.global_basis)}
		if mesh is GrowingDecal:
			var decal := mesh as GrowingDecal
			record.merge({"texture": decal.texture_file, "size": decal.size, "growth": decal.size_change, "max": decal.max_size, "timer": decal.timer, "stains": decal.drop_stains, "alpha": decal.alpha, "alpha_change": decal.alpha_change, "multiply": decal.multiply, "lifetime": decal.lifetime})
		else:
			record["stain"] = float(mesh.get_meta("stain_half", 0.1))
		out.append(record)
	return out

# Only the game's own pictures are loaded back (the save is a file the player can edit). Save.bb writes neither SizeChange nor
# MaxSize, so CreateDecal's defaults (0 and 1.0, Main.bb 10771-10781) apply: a decal saved mid-growth stops where it was, and
# the corrosion stain no longer drops small stains.
static func restore_all(parent: Node, records: Array) -> void:
	for old in parent.get_tree().get_nodes_in_group(GROUP):
		if not old.is_queued_for_deletion():
			old.queue_free()
	for record in records:
		if not record is Dictionary or not record.has("pos") or not record.has("basis") or record.basis.size() != 9:
			continue
		var b: Array = record.basis
		var xform := Transform3D(Basis(Vector3(float(b[0]), float(b[1]), float(b[2])), Vector3(float(b[3]), float(b[4]), float(b[5])), Vector3(float(b[6]), float(b[7]), float(b[8]))), Vector3(float(record.pos[0]), float(record.pos[1]), float(record.pos[2])))
		if record.has("stain"):
			_make_stain(parent, float(record.stain)).global_transform = xform
			continue
		var texture := str(record.get("texture", ""))
		if not texture.begins_with("GFX/") or texture.contains(".."):
			continue
		var size := float(record.get("size", 0.05))
		var alpha_change := float(record.get("alpha_change", 0.0))
		var saved_alpha := float(record.get("alpha", 1.0)) if alpha_change != 0.0 else 1.0
		var decal := make(parent, xform.origin, texture, size, 0.0, saved_alpha, false, Vector3.ZERO, false)
		decal.global_transform = xform
		decal.timer = float(record.get("timer", 0.0))
		decal.alpha_change = alpha_change
		decal.lifetime = float(record.get("lifetime", 0.0))
