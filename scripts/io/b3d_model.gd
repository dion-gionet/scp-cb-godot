extends Node3D
class_name B3DModel
# A Blitz3D .b3d model with its skeleton: every NODE becomes a bone, the BONE chunks become
# vertex weights (up to four per vertex), and the KEYS chunks are sampled by frame number like
# SetAnimTime does. Frame numbers are the file's own (the NPC code addresses animations as
# frame ranges such as 346..393).
#   var model := B3DModel.new(); model.load_file(path); model.set_frame(361.0)
# Coordinates follow the rest of the port: Blitz z is flipped.


var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var frame_count := 0
var skinned := false
var bone_names: PackedStringArray = []

var _nodes: Array[Dictionary] = []
var _world: Array[Transform3D] = []
var _animated: Array[int] = []        # node indices that have keys
var _textures: PackedStringArray = []
var _brush_tex: PackedInt32Array = PackedInt32Array()
var _brush_fx: PackedInt32Array = PackedInt32Array()
var _brush_color: PackedColorArray = PackedColorArray()
var _brush_light: PackedInt32Array = PackedInt32Array()   # lightmap texture of a brush that also has a diffuse one, else -1
var _tex_blend: PackedInt32Array = PackedInt32Array()
var _tex_flags: PackedInt32Array = PackedInt32Array()
var _directory := ""

# Parsing and meshing a model takes a few hundred milliseconds (the MTF2 body: 250), so what a file yields is kept and
# every later copy of it shares the parsed data, the mesh and the skin; only the skeleton is made again.
static var _cache: Dictionary = {}
var _source_path := ""

func load_file(path: String) -> bool:
	_source_path = path
	if _cache.has(path):
		var cached: Dictionary = _cache[path]
		_nodes = cached.nodes
		_textures = cached.textures
		_brush_tex = cached.brush_tex
		_brush_fx = cached.brush_fx
		_brush_color = cached.brush_color
		_brush_light = cached.brush_light
		_tex_blend = cached.tex_blend
		_tex_flags = cached.tex_flags
		_directory = cached.directory
		frame_count = cached.frame_count
	elif not parse_file(path):
		return false
	_build()
	return mesh_instance != null

# Reads the file into nodes, meshes, weights and keys without creating any scene objects.
func parse_file(path: String) -> bool:
	var reader = MeshLoader._Reader.new(path)
	if reader.data.size() < 12:
		return false
	_directory = path.get_base_dir()
	reader.pos = 0
	reader.tag()    # "BB3D"
	reader.i32()    # size
	reader.i32()    # version
	while reader.pos + 8 <= reader.data.size():
		var chunk: String = reader.tag()
		var size: int = reader.i32()
		var chunk_end: int = reader.pos + size
		match chunk:
			"TEXS":
				while reader.pos < chunk_end:
					var name: String = reader.cstr()
					_tex_flags.append(reader.i32())    # bit 16 (65536): texture coordinates from the second set
					_tex_blend.append(reader.i32())
					reader.f32(); reader.f32(); reader.f32(); reader.f32(); reader.f32()   # position, scale, rotation
					_textures.append(name.replace("\\", "/").get_file())
			"BRUS":
				var n_texs: int = reader.i32()
				while reader.pos < chunk_end:
					reader.cstr()
					_brush_color.append(Color(reader.f32(), reader.f32(), reader.f32()))
					reader.f32()
					reader.f32()
					reader.i32()
					_brush_fx.append(reader.i32())   # FX flags: bit 0 = fullbright
					var first := -1
					var lightmap := -1
					for _t in n_texs:
						var tex_id: int = reader.i32()
						# the first slot that names a picture (some files list blank placeholders first); a lightmap
						# (a name with "_lm") is only the choice when the brush has nothing else
						if tex_id >= 0 and tex_id < _textures.size() and not _textures[tex_id].is_empty():
							if _textures[tex_id].to_lower().contains("_lm"):
								if lightmap < 0:
									lightmap = tex_id
							elif first < 0:
								first = tex_id
					_brush_tex.append(first if first >= 0 else lightmap)
					_brush_light.append(lightmap if first >= 0 else -1)
			"NODE":
				_read_node(reader, chunk_end, -1)
		reader.pos = chunk_end
	_share_zero_weights()
	return not _nodes.is_empty()

# 372.b3d gives every vertex its bone with a weight of 0, and the vertex still follows that bone in the original: a vertex whose
# weights add up to 0 is shared evenly between its bones, so the skinning below needs no special case.
func _share_zero_weights() -> void:
	var owners := _bone_mesh_owners()
	var totals := {}
	for bone in owners:
		for pair in _nodes[bone].weights:
			var key := Vector2i(int(owners[bone]), int(pair[0]))
			totals[key] = float(totals.get(key, 0.0)) + float(pair[1])
	for bone in owners:
		for pair in _nodes[bone].weights:
			if float(totals[Vector2i(int(owners[bone]), int(pair[0]))]) <= 0.0:
				pair[1] = 1.0

func _read_node(reader, end: int, parent: int) -> void:
	var index := _nodes.size()
	var node := {"name": reader.cstr(), "parent": parent, "meshes": [], "weights": [], "pos_keys": [], "scale_keys": [], "rot_keys": []}
	var px: float = reader.f32()
	var py: float = reader.f32()
	var pz: float = reader.f32()
	node.pos = Vector3(px, py, -pz)
	node.scale = Vector3(reader.f32(), reader.f32(), reader.f32())
	var qw: float = reader.f32()
	var qx: float = reader.f32()
	var qy: float = reader.f32()
	var qz: float = reader.f32()
	node.rot = convert_quat(qw, qx, qy, qz)
	_nodes.append(node)
	while reader.pos + 8 <= end:
		var chunk: String = reader.tag()
		var size: int = reader.i32()
		var chunk_end: int = reader.pos + size
		match chunk:
			"NODE":
				_read_node(reader, chunk_end, index)
			"MESH":
				var mesh_brush: int = reader.i32()
				_read_mesh(reader, chunk_end, index, mesh_brush)
			"BONE":
				while reader.pos + 8 <= chunk_end:
					var vertex: int = reader.i32()
					var weight: float = reader.f32()
					(node.weights as Array).append([vertex, weight])
			"KEYS":
				var flags: int = reader.i32()
				while reader.pos + 4 <= chunk_end:
					var frame: int = reader.i32()
					if flags & 1:
						var x: float = reader.f32()
						var y: float = reader.f32()
						var z: float = reader.f32()
						(node.pos_keys as Array).append([frame, Vector3(x, y, -z)])
					if flags & 2:
						(node.scale_keys as Array).append([frame, Vector3(reader.f32(), reader.f32(), reader.f32())])
					if flags & 4:
						var w: float = reader.f32()
						var rx: float = reader.f32()
						var ry: float = reader.f32()
						var rz: float = reader.f32()
						(node.rot_keys as Array).append([frame, convert_quat(w, rx, ry, rz)])
			"ANIM":
				reader.i32()
				frame_count = maxi(frame_count, reader.i32())
		reader.pos = chunk_end

func _read_mesh(reader, end: int, node_index: int, mesh_brush: int) -> void:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var colors := PackedColorArray()
	var surfaces: Array = []
	while reader.pos + 8 <= end:
		var chunk: String = reader.tag()
		var size: int = reader.i32()
		var chunk_end: int = reader.pos + size
		if chunk == "VRTS":
			var flags: int = reader.i32()
			var tc_sets: int = reader.i32()
			var tc_size: int = reader.i32()
			var stride := 3
			if flags & 1:
				stride += 3
			if flags & 2:
				stride += 4
			stride += tc_sets * tc_size
			var count := int((chunk_end - reader.pos) / (stride * 4))
			positions.resize(count)
			uvs.resize(count)
			uvs2.resize(count)
			colors.resize(count)
			if flags & 1:
				normals.resize(count)
			for v in count:
				var x: float = reader.f32()
				var y: float = reader.f32()
				var z: float = reader.f32()
				positions[v] = Vector3(x, y, -z)
				if flags & 1:
					var nx: float = reader.f32()
					var ny: float = reader.f32()
					var nz: float = reader.f32()
					normals[v] = Vector3(nx, ny, -nz)
				var color := Color.WHITE
				if flags & 2:
					color = Color(reader.f32(), reader.f32(), reader.f32(), reader.f32())
				colors[v] = color
				var u := 0.0
				var vv := 0.0
				if tc_sets > 0 and tc_size > 0:
					u = reader.f32()
					vv = reader.f32() if tc_size > 1 else 0.0
					for _extra in (tc_size - 2):
						reader.f32()
					for set_index in (tc_sets - 1):
						var u2: float = reader.f32()
						var v2: float = reader.f32() if tc_size > 1 else 0.0
						for _c in (tc_size - 2):
							reader.f32()
						if set_index == 0:
							uvs2[v] = Vector2(u2, v2)
				uvs[v] = Vector2(u, vv)
		elif chunk == "TRIS":
			var brush: int = reader.i32()
			var tri_count := int((chunk_end - reader.pos) / 12)
			var indices := PackedInt32Array()
			indices.resize(tri_count * 3)
			for t in tri_count:
				indices[t * 3] = reader.i32()
				indices[t * 3 + 1] = reader.i32()
				indices[t * 3 + 2] = reader.i32()
			surfaces.append({"brush": brush if brush >= 0 else mesh_brush, "indices": indices})
		reader.pos = chunk_end
	(_nodes[node_index].meshes as Array).append({"positions": positions, "normals": normals, "uvs": uvs, "uvs2": uvs2, "colors": colors, "surfaces": surfaces})

func _build() -> void:
	_world.resize(_nodes.size())
	var any_weights := false
	for i in _nodes.size():
		var node: Dictionary = _nodes[i]
		var local := Transform3D(Basis(node.rot) * Basis.from_scale(node.scale), node.pos)
		var parent: int = node.parent
		_world[i] = local if parent < 0 else _world[parent] * local
		if not (node.weights as Array).is_empty():
			any_weights = true
		if not (node.pos_keys as Array).is_empty() or not (node.scale_keys as Array).is_empty() or not (node.rot_keys as Array).is_empty():
			_animated.append(i)
	skinned = any_weights
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for i in _nodes.size():
		var node: Dictionary = _nodes[i]
		var unique := "%s_%d" % [str(node.name), i]
		skeleton.add_bone(unique)
		bone_names.append(unique)
		if int(node.parent) >= 0:
			skeleton.set_bone_parent(i, int(node.parent))
		skeleton.set_bone_rest(i, Transform3D(Basis(node.rot) * Basis.from_scale(node.scale), node.pos))
	skeleton.reset_bone_poses()
	var mesh: ArrayMesh = null
	var skin: Skin = null
	var shared: Dictionary = _cache.get(_source_path, {})
	if not shared.is_empty():
		mesh = shared.mesh
		skin = shared.skin
	else:
		var owner_of_bone := _bone_mesh_owners()
		mesh = ArrayMesh.new()
		for i in _nodes.size():
			for mesh_data in _nodes[i].meshes:
				_add_surfaces(mesh, i, mesh_data, owner_of_bone)
		if skinned:
			skin = Skin.new()
			for i in _nodes.size():
				skin.add_bind(i, _world[i].affine_inverse())
		if mesh.get_surface_count() > 0 and not _source_path.is_empty():
			_cache[_source_path] = {"nodes": _nodes, "textures": _textures, "brush_tex": _brush_tex, "brush_fx": _brush_fx, "brush_color": _brush_color, "brush_light": _brush_light, "tex_blend": _tex_blend, "tex_flags": _tex_flags, "directory": _directory, "frame_count": frame_count, "mesh": mesh, "skin": skin}
	if mesh.get_surface_count() == 0:
		return
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	if skin != null:
		mesh_instance.skin = skin
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")

# BONE chunks name vertices of the mesh that owns the bone: the nearest ancestor that has a mesh,
# else the first mesh in the file.
func _bone_mesh_owners() -> Dictionary:
	var first_mesh := -1
	for i in _nodes.size():
		if not (_nodes[i].meshes as Array).is_empty():
			first_mesh = i
			break
	var owners := {}
	for i in _nodes.size():
		if (_nodes[i].weights as Array).is_empty():
			continue
		var current: int = i
		var found := -1
		while current >= 0:
			if not (_nodes[current].meshes as Array).is_empty():
				found = current
				break
			current = int(_nodes[current].parent)
		owners[i] = found if found >= 0 else first_mesh
	return owners

func _add_surfaces(mesh: ArrayMesh, node_index: int, mesh_data: Dictionary, owners: Dictionary) -> void:
	var local_positions: PackedVector3Array = mesh_data.positions
	var count := local_positions.size()
	if count == 0:
		return
	var world_transform: Transform3D = _world[node_index]
	var positions := PackedVector3Array()
	positions.resize(count)
	for v in count:
		positions[v] = world_transform * local_positions[v]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	if skinned:
		var influences: Array = []
		influences.resize(count)
		for v in count:
			influences[v] = []
		for bone in owners:
			if int(owners[bone]) != node_index:
				continue
			for pair in _nodes[bone].weights:
				var vertex := int(pair[0])
				if vertex >= 0 and vertex < count:
					(influences[vertex] as Array).append([int(bone), float(pair[1])])
		bones.resize(count * 4)
		weights.resize(count * 4)
		for v in count:
			var list: Array = influences[v]
			if list.is_empty():
				list = [[node_index, 1.0]]   # rigid part: follows its own node
			list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
			var total := 0.0
			for k in mini(list.size(), 4):
				total += float(list[k][1])
			for k in 4:
				if k < list.size() and total > 0.0:
					bones[v * 4 + k] = int(list[k][0])
					weights[v * 4 + k] = float(list[k][1]) / total
				else:
					bones[v * 4 + k] = 0
					weights[v * 4 + k] = 0.0
	var normals := PackedVector3Array()
	var local_normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	if local_normals.size() == count:
		normals.resize(count)
		var normal_basis := world_transform.basis.inverse().transposed()
		for v in count:
			normals[v] = (normal_basis * local_normals[v]).normalized()
	for surface_data in mesh_data.surfaces:
		_emit_surface(mesh, positions, mesh_data.uvs, surface_data, bones, weights, false, normals)

# One TRIS block as a surface with its brush's texture.
func _emit_surface(mesh: ArrayMesh, positions: PackedVector3Array, uvs: PackedVector2Array, surface_data: Dictionary, bones: PackedInt32Array, weights: PackedFloat32Array, brush_is_texture: bool = false, normals: PackedVector3Array = PackedVector3Array()) -> void:
	# a b3d shares one vertex buffer between all its surfaces; a static surface keeps only the
	# vertices it uses (otherwise every one of hundreds of surfaces carries the whole buffer)
	if bones.is_empty() and positions.size() > 64:
		var source_indices: PackedInt32Array = surface_data.indices
		var remap := {}
		var small_positions := PackedVector3Array()
		var small_normals := PackedVector3Array()
		var small_uvs := PackedVector2Array()
		var small_indices := PackedInt32Array()
		small_indices.resize(source_indices.size())
		for i in source_indices.size():
			var old: int = source_indices[i]
			if not remap.has(old):
				remap[old] = small_positions.size()
				small_positions.append(positions[old])
				small_uvs.append(uvs[old])
				if normals.size() == positions.size():
					small_normals.append(normals[old])
			small_indices[i] = remap[old]
		positions = small_positions
		uvs = small_uvs
		if not small_normals.is_empty():
			normals = small_normals
		else:
			normals = PackedVector3Array()
		surface_data = surface_data.duplicate()
		surface_data["indices"] = small_indices
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	if normals.size() == positions.size():
		arrays[Mesh.ARRAY_NORMAL] = normals     # lit by the rooms' lights like Blitz' vertex lighting
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = surface_data.indices
	if not bones.is_empty():
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var surface := mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var brush: int = surface_data.brush
	var texture_index := brush
	if not brush_is_texture and not _brush_tex.is_empty() and brush >= 0 and brush < _brush_tex.size():
		texture_index = _brush_tex[brush]
	var texture: Texture2D = MeshLoader._white_tex()
	var flags := 0
	if texture_index >= 0 and texture_index < _textures.size() and not _textures[texture_index].is_empty():
		var texture_path := _directory.path_join(_textures[texture_index])
		flags = _tex_flags[texture_index] if texture_index < _tex_flags.size() else 0
		texture = MeshLoader._load_texture_masked(texture_path) if flags & 4 else MeshLoader._load_texture(texture_path)
	var has_alpha := flags & 2 != 0 and MeshLoader._has_blended_alpha(texture)
	var surface_material := MeshLoader.entity_material(texture, has_alpha, flags & 4 != 0)
	var fullbright: bool = surface_data.get("fullbright", false)
	if fullbright:
		surface_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# the brush colour is the Direct3D material's diffuse and ambient colour: it scales the lighting (gxScene::setRenderState)
	if not fullbright:
		var color_brush: int = brush if not brush_is_texture else int(surface_data.get("color_brush", -1))
		if color_brush >= 0 and color_brush < _brush_color.size():
			surface_material.albedo_color = _brush_color[color_brush]
	mesh.surface_set_material(surface, surface_material)

func _uses_second_uv_set(texture_index: int) -> bool:
	return texture_index >= 0 and texture_index < _tex_flags.size() and (_tex_flags[texture_index] & 65536) != 0

func _has_lightmap() -> bool:
	for light in _brush_light:
		if light >= 0:
			return true
	return false

# A map piece the way LoadRMesh brushes a wall: vertex colour times the "_lm" lightmap (second UV set) times the diffuse
# texture, times two for TextureBlend 5. Surfaces of the same file without a lightmap keep their vertex colours.
func _emit_lit_surface(mesh: ArrayMesh, group: Dictionary, layered: bool = false) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = group.positions
	arrays[Mesh.ARRAY_TEX_UV] = group.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = group.uvs2
	arrays[Mesh.ARRAY_COLOR] = group.colors
	arrays[Mesh.ARRAY_INDEX] = group.indices
	var surface := mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var texture: Texture2D = _texture_at(group.texture)
	var lightmap: Texture2D = null
	if int(group.light) >= 0:
		lightmap = _texture_at(group.light)
	var diffuse_x2 := int(group.texture) >= 0 and int(group.texture) < _tex_blend.size() and _tex_blend[group.texture] == 5
	var material := MeshLoader._room_material(texture, lightmap, layered and group.alpha_blended, diffuse_x2)
	material.set_shader_parameter("entity_brush", true)
	mesh.surface_set_material(surface, material)

func _texture_at(index: int) -> Texture2D:
	if index >= 0 and index < _textures.size() and not _textures[index].is_empty():
		return MeshLoader._load_texture(_directory.path_join(_textures[index]))
	return MeshLoader._white_tex()

# layered: a brush with FX 32 (force alpha blending) is drawn over the one before it by vertex alpha (exit1terrain.b3d: the gravel over
# grass2, both fullbright with vertex colours and TextureBlend 5).
# Every mesh of the file as one static ArrayMesh, vertices as stored (no node transforms): what
# props, doors and items use. MeshLoader.load_b3d caches it.
# frame >= 0: the weighted vertices are skinned to that frame's pose (what SetAnimTime leaves a still model in), from the nodes' world positions.
static func static_mesh(path: String, apply_nodes: bool = false, layered: bool = false, frame: float = -1.0) -> ArrayMesh:
	var model := new()
	var mesh := ArrayMesh.new()
	if model.parse_file(path):
		# Surfaces sharing a texture become one surface: a b3d such as the pocket dimension's
		# throne room has hundreds of tiny quads, and adding that many surfaces one by one is
		# very slow (Godot rebuilds the mesh each time).
		# apply_nodes: bake each node's world transform in (what Blitz' LoadMesh does for maps)
		var world: Array[Transform3D] = []
		world.resize(model._nodes.size())
		for n in model._nodes.size():
			var node_data: Dictionary = model._nodes[n]
			var local := Transform3D(Basis(node_data.rot) * Basis.from_scale(node_data.scale), node_data.pos)
			world[n] = local if int(node_data.parent) < 0 else world[int(node_data.parent)] * local
		var lit := layered or model._has_lightmap()
		var pose_matrices: Array[Transform3D] = []
		if frame >= 0.0:
			pose_matrices = model._pose_matrices(world, frame)
		var bone_owners: Dictionary = model._bone_mesh_owners() if frame >= 0.0 else {}
		var groups: Dictionary = {}   # (texture, lightmap, fullbright) -> {positions, uvs, indices, ...}
		var order: Array = []
		for node_index in model._nodes.size():
			var node: Dictionary = model._nodes[node_index]
			for mesh_data in node.meshes:
				var positions: PackedVector3Array = mesh_data.positions
				if apply_nodes or frame >= 0.0:
					positions = world[node_index] * positions
				if frame >= 0.0:
					positions = model._skin_positions(node_index, positions, pose_matrices, bone_owners)
				var uvs: PackedVector2Array = mesh_data.uvs
				var uvs2: PackedVector2Array = mesh_data.get("uvs2", PackedVector2Array())
				var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
				var source_normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
				if (apply_nodes or frame >= 0.0) and source_normals.size() == positions.size():
					var normal_basis := world[node_index].basis.inverse().transposed()
					var turned := PackedVector3Array()
					turned.resize(source_normals.size())
					for n_index in source_normals.size():
						turned[n_index] = (normal_basis * source_normals[n_index]).normalized()
					source_normals = turned
				for surface_data in mesh_data.surfaces:
					var brush: int = surface_data.brush
					var texture_index := brush
					if not model._brush_tex.is_empty() and brush >= 0 and brush < model._brush_tex.size():
						texture_index = model._brush_tex[brush]
					var fullbright := brush >= 0 and brush < model._brush_fx.size() and (model._brush_fx[brush] & 1) != 0
					var light_index := -1
					if lit and brush >= 0 and brush < model._brush_light.size():
						light_index = model._brush_light[brush]
					var vertex_colors := brush >= 0 and brush < model._brush_fx.size() and (model._brush_fx[brush] & 2) != 0
					var group_key := ((texture_index * 1000 + light_index) * 4 + (1 if fullbright else 0) + (2 if vertex_colors else 0)) * 4096 + brush + 1
					if not groups.has(group_key):
						groups[group_key] = {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(), "uvs2": PackedVector2Array(), "colors": PackedColorArray(), "indices": PackedInt32Array(), "texture": texture_index, "light": light_index, "fullbright": fullbright, "vertex_colors": vertex_colors, "brush": brush, "alpha_blended": brush >= 0 and brush < model._brush_fx.size() and (model._brush_fx[brush] & 32) != 0}
						order.append(group_key)
					var group: Dictionary = groups[group_key]
					var group_positions: PackedVector3Array = group.positions
					var group_uvs: PackedVector2Array = group.uvs
					var group_normals: PackedVector3Array = group.normals
					var group_uvs2: PackedVector2Array = group.uvs2
					var group_colors: PackedColorArray = group.colors
					var group_indices: PackedInt32Array = group.indices
					var remap := {}
					for old in surface_data.indices:
						if not remap.has(old):
							remap[old] = group_positions.size()
							group_positions.append(positions[old])
							var second := uvs2[old] if uvs2.size() == positions.size() else Vector2.ZERO
							group_uvs.append(second if model._uses_second_uv_set(texture_index) else uvs[old])
							if lit:
								group_uvs2.append(second if model._uses_second_uv_set(light_index) else uvs[old])
								group_colors.append(colors[old] if vertex_colors and colors.size() == positions.size() else Color.WHITE)
							if source_normals.size() == positions.size():
								group_normals.append(source_normals[old])
						group_indices.append(remap[old])
					group.positions = group_positions
					group.uvs = group_uvs
					group.normals = group_normals
					group.uvs2 = group_uvs2
					group.colors = group_colors
					group.indices = group_indices
		for group_key in order:
			var group: Dictionary = groups[group_key]
			if lit and (group.fullbright or int(group.light) >= 0):
				model._emit_lit_surface(mesh, group, layered)
				continue
			model._emit_surface(mesh, group.positions, group.uvs, {"brush": group.texture, "color_brush": group.brush, "indices": group.indices, "fullbright": group.fullbright}, PackedInt32Array(), PackedFloat32Array(), true, group.normals)
	else:
		push_error("Not a B3D: %s" % path)
	model.free()
	return mesh

# Each node's pose-to-rest matrix at `frame`: world pose * inverse rest world.
func _pose_matrices(rest_world: Array[Transform3D], frame: float) -> Array[Transform3D]:
	var posed: Array[Transform3D] = []
	var matrices: Array[Transform3D] = []
	posed.resize(_nodes.size())
	matrices.resize(_nodes.size())
	for i in _nodes.size():
		var node: Dictionary = _nodes[i]
		var position: Vector3 = _sample_vec(node.pos_keys, frame) if not (node.pos_keys as Array).is_empty() else node.pos
		var scale: Vector3 = _sample_vec(node.scale_keys, frame) if not (node.scale_keys as Array).is_empty() else node.scale
		var rotation: Quaternion = _sample_rot(node.rot_keys, frame) if not (node.rot_keys as Array).is_empty() else node.rot
		var local := Transform3D(Basis(rotation) * Basis.from_scale(scale), position)
		posed[i] = local if int(node.parent) < 0 else posed[int(node.parent)] * local
		matrices[i] = posed[i] * rest_world[i].affine_inverse()
	return matrices

func _skin_positions(node_index: int, positions: PackedVector3Array, matrices: Array[Transform3D], owners: Dictionary) -> PackedVector3Array:
	var blended := PackedVector3Array()
	blended.resize(positions.size())
	var sums := PackedFloat32Array()
	sums.resize(positions.size())
	for bone in owners:
		if int(owners[bone]) != node_index:
			continue
		for pair in _nodes[bone].weights:
			var vertex := int(pair[0])
			if vertex < 0 or vertex >= positions.size():
				continue
			var weight := float(pair[1])
			blended[vertex] += weight * (matrices[bone] * positions[vertex])
			sums[vertex] += weight
	var skinned := positions.duplicate()
	for v in positions.size():
		if sums[v] > 0.0:
			skinned[v] = blended[v] / sums[v]
	return skinned

# SetAnimTime: pose every animated bone at the (fractional) frame.
func set_frame(frame: float) -> void:
	for i in _animated:
		var node: Dictionary = _nodes[i]
		if not (node.pos_keys as Array).is_empty():
			skeleton.set_bone_pose_position(i, _sample_vec(node.pos_keys, frame))
		if not (node.scale_keys as Array).is_empty():
			skeleton.set_bone_pose_scale(i, _sample_vec(node.scale_keys, frame))
		if not (node.rot_keys as Array).is_empty():
			skeleton.set_bone_pose_rotation(i, _sample_rot(node.rot_keys, frame))

func _bracket(keys: Array, frame: float) -> Array:
	# returns [index_before, index_after, t]
	if frame <= float(keys[0][0]):
		return [0, 0, 0.0]
	var last := keys.size() - 1
	if frame >= float(keys[last][0]):
		return [last, last, 0.0]
	var low := 0
	var high := last
	while high - low > 1:
		var mid := (low + high) / 2
		if float(keys[mid][0]) <= frame:
			low = mid
		else:
			high = mid
	var span := float(keys[high][0]) - float(keys[low][0])
	return [low, high, (frame - float(keys[low][0])) / span if span > 0.0 else 0.0]

func _sample_vec(keys: Array, frame: float) -> Vector3:
	var b := _bracket(keys, frame)
	var a: Vector3 = keys[b[0]][1]
	var c: Vector3 = keys[b[1]][1]
	return a.lerp(c, float(b[2]))

func _sample_rot(keys: Array, frame: float) -> Quaternion:
	var b := _bracket(keys, frame)
	var a: Quaternion = keys[b[0]][1]
	var c: Quaternion = keys[b[1]][1]
	return a.slerp(c, float(b[2]))

# Blitz quaternion (w, x, y, z) to Godot with z mirrored. Found by comparing poses: this variant
# (the mirror of the rotation about z, i.e. z negated) is the one that keeps the walk cycle of
# SCP-049 upright; the textbook (-x, -y) mirror twists the body.
static func convert_quat(w: float, x: float, y: float, z: float) -> Quaternion:
	return Quaternion(x, y, -z, w).normalized()
