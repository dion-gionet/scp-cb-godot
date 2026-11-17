class_name MeshLoader
extends RefCounted

const Inflate = preload("res://scripts/io/inflate.gd")
const ROOM_SCALE := 8.0 / 2048.0

# Room meshes are parsed on worker threads ahead of time (facility_map prefetch), so the shared
# caches below are guarded; Mutex is recursive.
static var _lock := Mutex.new()
static var _rmesh_cache: Dictionary = {}
static var _textures: Dictionary = {}
static var _white: Texture2D
static var _opaque_shader: Shader
static var _alpha_shader: Shader

static func blitz_to_godot(x: float, y: float, z: float, scale: float = 1.0) -> Vector3:
	return Vector3(x * scale, y * scale, -z * scale)


# Parses the file into plain data (arrays, texture file names, decoded images). Touches no
# rendering resource, so it can run on a worker thread; build_rmesh turns it into a mesh.
static func parse_rmesh(path: String) -> Dictionary:
	var reader := _Reader.new(path)
	var result := {
		"surfaces": [],
		"images": {},
		"collision_faces": PackedVector3Array(),
		"entities": [],
		"drawn_meshes": 0,
		"vertices": 0,
		"triangles": 0,
	}
	if reader.data.is_empty():
		push_error("RMesh missing: %s" % path)
		return result
	var directory := path.get_base_dir()
	var magic := reader.blitz_string()
	if magic != "RoomMesh" and magic != "RoomMesh.HasTriggerBox":
		push_error("Not an RMesh (%s): %s" % [magic, path])
		return result
	var faces_drawn := PackedVector3Array()
	var drawn_metal := PackedByteArray()   # one byte per drawn triangle: 1 = a metal floor texture
	var drawn := reader.i32()
	result.drawn_meshes = drawn
	for _i in drawn:
		var slots: Array = []
		var alpha := false
		for _slot in 2:
			var flag := reader.u8()
			if flag == 0:
				slots.append({"flag": 0, "path": ""})
			else:
				var tex_path := reader.blitz_string().replace("\\", "/")
				slots.append({"flag": flag, "path": tex_path})
				if flag == 3:
					alpha = true
		var vert_count := reader.i32()
		var positions := PackedVector3Array()
		var uv0 := PackedVector2Array()
		var uv1 := PackedVector2Array()
		var colors := PackedColorArray()
		positions.resize(vert_count)
		uv0.resize(vert_count)
		uv1.resize(vert_count)
		colors.resize(vert_count)
		# position (3 floats), two UV pairs (4 floats) and a colour (3 bytes) per vertex
		var data := reader.data
		var p := reader.pos
		for v in vert_count:
			positions[v] = Vector3(data.decode_float(p) * ROOM_SCALE, data.decode_float(p + 4) * ROOM_SCALE, -data.decode_float(p + 8) * ROOM_SCALE)
			uv0[v] = Vector2(data.decode_float(p + 12), data.decode_float(p + 16))
			uv1[v] = Vector2(data.decode_float(p + 20), data.decode_float(p + 24))
			colors[v] = Color(data[p + 28] / 255.0, data[p + 29] / 255.0, data[p + 30] / 255.0)
			p += 31
		reader.pos = p
		var tri_count := reader.i32()
		var indices: PackedInt32Array = reader.data.slice(reader.pos, reader.pos + tri_count * 12).to_int32_array()
		reader.pos += tri_count * 12
		result.vertices += vert_count
		result.triangles += tri_count
		var metal := 0
		for slot_info in slots:
			if is_metal_texture(str(slot_info.path)):
				metal = 1
		if not alpha:
			var base := faces_drawn.size()
			faces_drawn.resize(base + tri_count * 3)
			var metal_base := drawn_metal.size()
			drawn_metal.resize(metal_base + tri_count)
			for t in tri_count:
				faces_drawn[base + t * 3] = positions[indices[t * 3]]
				faces_drawn[base + t * 3 + 1] = positions[indices[t * 3 + 1]]
				faces_drawn[base + t * 3 + 2] = positions[indices[t * 3 + 2]]
				drawn_metal[metal_base + t] = metal
		var albedo_slot := -1
		var light_slot := -1
		for s in slots.size():
			var slot: Dictionary = slots[s]
			if str(slot.path).is_empty():
				continue
			if str(slot.path).to_lower().contains("_lm"):
				light_slot = s
			elif albedo_slot < 0:
				albedo_slot = s
		var albedo_uv := uv0
		var light_uv := uv1
		if albedo_slot == 0:
			albedo_uv = uv1
		elif albedo_slot == 1:
			albedo_uv = uv0
		if light_slot == 0:
			light_uv = uv1
		elif light_slot == 1:
			light_uv = uv0
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = albedo_uv
		arrays[Mesh.ARRAY_TEX_UV2] = light_uv
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var albedo_path := directory.path_join(str(slots[albedo_slot].path)) if albedo_slot >= 0 else ""
		var light_path := directory.path_join(str(slots[light_slot].path)) if light_slot >= 0 else ""
		# LoadRMesh: a texture of type 1 gets TextureBlend 5 (multiply x2); the "_lm" lightmap is added onto a black first stage
		var albedo_x2: bool = albedo_slot >= 0 and int(slots[albedo_slot].flag) == 1
		result.surfaces.append({"arrays": arrays, "alpha": alpha, "albedo": albedo_path, "light": light_path, "albedo_x2": albedo_x2})
		_decode_image(result.images, albedo_path)
		_decode_image(result.images, light_path)
	var hidden := reader.i32()
	var faces := PackedVector3Array()
	for _h in hidden:
		var hv := reader.i32()
		var hpos := PackedVector3Array()
		hpos.resize(hv)
		for v in hv:
			hpos[v] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
		var ht := reader.i32()
		for _t in ht:
			var a := reader.i32()
			var b := reader.i32()
			var c := reader.i32()
			if a < 0 or b < 0 or c < 0 or a >= hv or b >= hv or c >= hv:
				continue
			faces.append(hpos[a])
			faces.append(hpos[c])
			faces.append(hpos[b])
			faces.append(hpos[a])
			faces.append(hpos[b])
			faces.append(hpos[c])
	result["drawn_start"] = faces.size()
	result["drawn_metal"] = drawn_metal
	faces.append_array(faces_drawn)
	result.collision_faces = faces
	if magic == "RoomMesh.HasTriggerBox":
		var trigger_count := reader.i32()
		var triggers: Array = []
		for _tb in trigger_count:
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			var mesh_count := reader.i32()
			for _m in mesh_count:
				var vc := reader.i32()
				for _v in vc:
					var corner := blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
					low = low.min(corner)
					high = high.max(corner)
				var tc := reader.i32()
				reader.pos += tc * 12
			var trigger_name := reader.blitz_string()
			if low.x != INF:
				triggers.append({"name": trigger_name, "low": low, "high": high})
		result["triggers"] = triggers
	var points := reader.i32()
	var entities: Array = result.entities
	for _p in points:
		var kind := reader.blitz_string()
		var entity := {"kind": kind}
		match kind:
			"screen":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
				entity["image"] = reader.blitz_string()
			"waypoint":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
			"light":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
				entity["range"] = reader.f32()
				entity["color"] = reader.blitz_string()
				entity["intensity"] = reader.f32()
			"spotlight":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
				entity["range"] = reader.f32()
				entity["color"] = reader.blitz_string()
				entity["intensity"] = reader.f32()
				entity["angles"] = reader.blitz_string()
				entity["inner"] = reader.i32()
				entity["outer"] = reader.i32()
			"soundemitter":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
				entity["id"] = reader.i32()
				entity["range"] = reader.f32()
			"playerstart":
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), 1.0)
				entity["angles"] = reader.blitz_string()
			"model":
				entity["file"] = reader.blitz_string()
				entity["position"] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32(), ROOM_SCALE)
				if not str(entity.file).is_empty():
					entity["rotation"] = Vector3(reader.f32(), reader.f32(), reader.f32())
					entity["scale"] = Vector3(reader.f32(), reader.f32(), reader.f32()) * ROOM_SCALE
			_:
				push_warning("Unknown RMesh entity %s" % kind)
				break
		entities.append(entity)
	return result


static var _b3d_cache: Dictionary = {}
static var _b3d_world_cache: Dictionary = {}

# A b3d with every node's transform baked in (map pieces; Blitz LoadMesh flattens the hierarchy).
static func load_b3d_world(path: String) -> ArrayMesh:
	if not _b3d_world_cache.has(path):
		_b3d_world_cache[path] = load("res://scripts/io/b3d_model.gd").static_mesh(path, true)
	return _b3d_world_cache[path]

static var _b3d_layered_cache: Dictionary = {}

static func load_b3d_layered(path: String) -> ArrayMesh:
	if not _b3d_layered_cache.has(path):
		_b3d_layered_cache[path] = load("res://scripts/io/b3d_model.gd").static_mesh(path, true, true)
	return _b3d_layered_cache[path]

static var _b3d_posed_cache: Dictionary = {}

# The model as SetAnimTime(frame) leaves it, baked static.
static func load_b3d_posed(path: String, frame: float) -> ArrayMesh:
	var key := "%s@%s" % [path, frame]
	if not _b3d_posed_cache.has(key):
		_b3d_posed_cache[key] = load("res://scripts/io/b3d_model.gd").static_mesh(path, false, false, frame)
	return _b3d_posed_cache[key]

static func load_b3d(path: String) -> ArrayMesh:
	if _b3d_cache.has(path):
		return _b3d_cache[path]
	var mesh := _load_b3d_uncached(path)
	_b3d_cache[path] = mesh
	return mesh


static func _load_b3d_uncached(path: String) -> ArrayMesh:
	# loaded lazily: b3d_model.gd itself preloads this script
	return load("res://scripts/io/b3d_model.gd").static_mesh(path)



static var _x_cache: Dictionary = {}

# Parsed models are shared between users (doors reuse the same few files); callers must not
# edit the returned mesh or its materials in place.
static func load_x(path: String) -> ArrayMesh:
	path = ContentPaths.match_case_absolute(path)
	if _x_cache.has(path):
		return _x_cache[path]
	var header := FileAccess.get_file_as_bytes(path).slice(0, 16).get_string_from_ascii()
	var mesh: ArrayMesh
	if header.contains("bin") or header.contains("zip"):
		mesh = _load_x_binary(path)
	else:
		mesh = _load_x_text(path)
	_x_cache[path] = mesh
	return mesh


static func floor_y(faces: PackedVector3Array, x: float, z: float, max_y: float = 2.95) -> float:
	var best := -999.0
	var i := 0
	while i + 2 < faces.size():
		var hit := _ray_down(x, z, faces[i], faces[i + 1], faces[i + 2])
		if hit < max_y and hit > best:
			best = hit
		i += 3
	return best


static func _ray_down(x: float, z: float, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var n := ab.cross(ac)
	if n.y < 0.2:
		return -999.0
	var t := (n.dot(a) - n.x * x - n.z * z) / n.y
	if t > 6.0 or t < -4.0:
		return -999.0
	var p := Vector3(x, t, z)
	if ab.cross(p - a).dot(n) < 0.0:
		return -999.0
	if (c - b).cross(p - b).dot(n) < 0.0:
		return -999.0
	if (a - c).cross(p - c).dot(n) < 0.0:
		return -999.0
	return t


# Rooms of one template share a single trimesh shape (built once on the main thread). The invisible collision faces
# (LoadRMesh's hiddenMesh: EntityType HIT_MAP and no pick mode) sit in a child body on the same layer, so rays that
# stand for EntityPick can skip it ("invisible_collision") while the player still collides with it.
static func make_static_body_shared(rmesh: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var faces: PackedVector3Array = rmesh.collision_faces
	if faces.is_empty():
		return body
	var split := clampi(int(rmesh.get("drawn_start", 0)), 0, faces.size())
	if not rmesh.has("shape"):
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces.slice(split))
		rmesh["shape"] = shape
		if split > 0:
			var hidden_shape := ConcavePolygonShape3D.new()
			hidden_shape.set_faces(faces.slice(0, split))
			rmesh["hidden_shape"] = hidden_shape
	var col := CollisionShape3D.new()
	col.shape = rmesh["shape"]
	body.add_child(col)
	if rmesh.has("hidden_shape"):
		var hidden := StaticBody3D.new()
		hidden.collision_layer = 1
		hidden.collision_mask = 0
		hidden.set_meta("invisible_collision", true)
		var hidden_col := CollisionShape3D.new()
		hidden_col.shape = rmesh["hidden_shape"]
		hidden.add_child(hidden_col)
		body.add_child(hidden)
	return body

# EntityPick: the first pickable hit on `mask`. The invisible collision faces take part in collisions only, so the ray passes them.
static func pick_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: RID, mask: int = 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	var skipped: Array[RID] = [exclude]
	for _i in 16:
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not hit.collider.has_meta("invisible_collision"):
			return hit
		skipped.append(hit.rid)
	return {}


static func make_static_body(faces: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if faces.is_empty():
		return body
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body


# "bzip" .x files: the binary format with MSZIP chunks after the 16 byte header. Each chunk is
# u16 inflated size, u16 compressed size (including the "CK" marker), then raw deflate data.
# Each chunk is inflated with the last 32 KB of the output so far as its dictionary.
static func _inflate_mszip(bytes: PackedByteArray) -> PackedByteArray:
	var out := bytes.slice(0, 16)
	out[8] = ord("b")
	out[9] = ord("i")
	out[10] = ord("n")
	out[11] = ord(" ")
	var pos := 20   # header + total inflated size
	while pos + 6 <= bytes.size():
		var inflated := bytes.decode_u16(pos)
		var packed := bytes.decode_u16(pos + 2)
		var chunk: PackedByteArray = Inflate.inflate(bytes.slice(pos + 6, pos + 4 + packed), out.slice(maxi(out.size() - 32768, 16)))
		out.append_array(chunk)
		pos += 4 + packed
	return out


static func _load_x_binary(path: String) -> ArrayMesh:
	var reader := _Reader.new(path)
	var mesh := ArrayMesh.new()
	if reader.data.slice(8, 12).get_string_from_ascii().ends_with("zip"):
		reader.data = _inflate_mszip(reader.data)
	reader.pos = 16
	var names: PackedStringArray = []
	var pending: PackedStringArray = []
	var texture_name := ""
	while reader.pos + 2 <= reader.data.size():
		var token := reader.u16()
		if token == 1:
			pending.append(reader.x_name())
		elif token == 10:
			# "Mesh Bone {" names an instance: the first name is the object's type
			var type_name := pending[0] if not pending.is_empty() else ""
			pending.clear()
			names.append(type_name)
			if type_name == "Mesh":
				_read_binary_mesh(reader, mesh)
		elif token == 11:
			if not names.is_empty():
				names.remove_at(names.size() - 1)
		elif token == 2:
			var text := reader.x_string()
			if texture_name.is_empty() and _is_image(text):
				texture_name = text.replace("\\", "/").get_file()
		elif token == 3:
			reader.i32()
		elif token == 5:
			reader.pos += 16
		elif token == 6:
			var n := reader.u32()
			reader.pos += n * 4
		elif token == 7:
			var n := reader.u32()
			reader.pos += n * 4
		elif token >= 10 and token <= 60:
			pass
		else:
			push_warning("Binary .x stopped at token %s in %s" % [token, path.get_file()])
			break
	if mesh.get_surface_count() > 0:
		var tex := _load_texture(path.get_base_dir().path_join(texture_name)) if not texture_name.is_empty() else _white_tex()
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, entity_material(tex, false))
	return mesh


static func _read_binary_mesh(reader: _Reader, mesh: ArrayMesh) -> void:
	if reader.u16() != 6:
		return
	var ncount := reader.u32()
	if ncount < 1:
		return
	var vert_count := reader.u32()
	reader.pos += (ncount - 1) * 4
	if reader.u16() != 7:
		return
	var floats := reader.u32()
	var positions := PackedVector3Array()
	positions.resize(vert_count)
	for v in vert_count:
		if v * 3 + 2 >= floats:
			break
		positions[v] = blitz_to_godot(reader.f32(), reader.f32(), reader.f32())
	reader.pos += maxi(0, floats - vert_count * 3) * 4
	if reader.u16() != 6:
		return
	var face_ints := reader.u32()
	var face_start := reader.pos
	if face_ints < 1:
		return
	var face_count := reader.u32()
	var indices := PackedInt32Array()
	var consumed := 1
	for _f in face_count:
		if consumed >= face_ints:
			break
		var nidx := reader.u32()
		consumed += 1
		var face: Array[int] = []
		for i in nidx:
			if consumed >= face_ints:
				break
			face.append(reader.u32())
			consumed += 1
		for t in maxi(0, face.size() - 2):
			indices.append(face[0])
			indices.append(face[t + 1])
			indices.append(face[t + 2])
	reader.pos = face_start + face_ints * 4
	var uvs := PackedVector2Array()
	uvs.resize(positions.size())
	var look := reader.pos
	var found_uv := false
	while look + 2 < reader.data.size() and look < reader.pos + positions.size() * 40 + 256:
		if reader.data.decode_u16(look) == 1:
			var save := reader.pos
			reader.pos = look + 2
			var name := reader.x_name()
			if name == "MeshTextureCoords" and reader.pos + 2 <= reader.data.size() and reader.u16() == 10:
				if reader.u16() == 6:
					var nc := reader.u32()
					if nc >= 1:
						var ncoords := reader.u32()
						reader.pos += (nc - 1) * 4
						if reader.u16() == 7:
							var nf := reader.u32()
							for v in mini(ncoords, positions.size()):
								if v * 2 + 1 >= nf:
									break
								uvs[v] = Vector2(reader.f32(), reader.f32())
							found_uv = true
			reader.pos = save
			if found_uv:
				break
		look += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _load_x_text(path: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Text .x missing: %s" % path)
		return mesh
	var materials := _x_materials(text)
	var default_texture := _x_texture_name(text)
	var groups := {}
	var order: PackedStringArray = []
	var search := 0
	while true:
		var at := text.find("Mesh", search)
		if at < 0:
			break
		var before_ok := at == 0 or not text.unicode_at(at - 1) >= 65
		if at >= 9 and text.substr(at - 9, 9) == "template ":
			search = at + 4
			continue
		var after := at + 4
		var next_char := text.unicode_at(after) if after < text.length() else 0
		if not before_ok or (next_char >= 48 and next_char <= 57) or (next_char >= 65 and next_char <= 90) or (next_char >= 97 and next_char <= 122):
			search = at + 4
			continue
		var brace := text.find("{", after)
		if brace < 0 or brace - after > 80:
			search = at + 4
			continue
		var block := _brace_block(text, brace)
		_add_text_mesh_block(groups, order, block, _frame_transform(text, at), materials, default_texture)
		search = brace + block.length()
	for texture_name in order:
		var group: Dictionary = groups[texture_name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.positions
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_TEX_UV] = group.uvs
		arrays[Mesh.ARRAY_INDEX] = group.indices
		var surface := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if texture_name.begins_with("#"):
			var face_color := Color.html(texture_name)
			var colored := entity_material(null, face_color.a < 1.0)
			colored.albedo_color = face_color
			mesh.surface_set_material(surface, colored)
			continue
		var tex := _load_texture(path.get_base_dir().path_join(texture_name)) if not texture_name.is_empty() else _white_tex()
		mesh.surface_set_material(surface, entity_material(tex, false))
	return mesh


# A Material block's surface: its texture file, or "#rrggbbaa" of its faceColor when it names no texture (Blitz shows
# such faces in that colour).
static func _x_surface_key(block: String) -> String:
	var texture_name := _x_texture_name(block)
	if not texture_name.is_empty():
		return texture_name
	var numbers := _numbers(block)
	if numbers.size() < 4:
		return ""
	return "#" + Color(numbers[0], numbers[1], numbers[2], numbers[3]).to_html()


static func _x_texture_name(text: String) -> String:
	var tex_at := text.find("TextureFilename")
	if tex_at < 0:
		return ""
	var q1 := text.find("\"", tex_at)
	var q2 := text.find("\"", q1 + 1)
	if q1 >= 0 and q2 > q1:
		return text.substr(q1 + 1, q2 - q1 - 1).get_file()
	return ""


# The named top-level "Material name { ... TextureFilename { "x.jpg"; } }" blocks: name -> texture file.
static func _x_materials(text: String) -> Dictionary:
	var result := {}
	var search := 0
	while true:
		var at := text.find("Material", search)
		if at < 0:
			break
		search = at + 8
		var brace := text.find("{", search)
		if brace < 0:
			break
		var between := text.substr(search, brace - search).strip_edges()
		var preceded := at == 0 or text.unicode_at(at - 1) <= 32
		if not preceded or between.is_empty() or between.contains(";") or between.contains("\n") or between.contains(" "):
			continue
		result[between] = _x_surface_key(_brace_block(text, brace))
	return result


# MeshMaterialList: per-face material slots, each a {name} reference or an inline Material block.
# Returns the texture file of every face; an empty array when the block has no list.
static func _x_face_textures(block: String, face_count: int, materials: Dictionary, default_texture: String) -> PackedStringArray:
	var result := PackedStringArray()
	var list_at := block.find("MeshMaterialList")
	if list_at < 0:
		return result
	var open := block.find("{", list_at)
	if open < 0:
		return result
	var body := _brace_block(block, open)
	var first_brace := body.find("{")
	var head := body if first_brace < 0 else body.substr(0, first_brace)
	var head_end := head.rfind("Material")
	if head_end >= 0:
		head = head.substr(0, head_end)
	var numbers := _numbers(head)
	if numbers.size() < 2:
		return result
	var slots: PackedStringArray = []
	var cursor := head.length()
	while true:
		var brace := body.find("{", cursor)
		if brace < 0:
			break
		var label := body.substr(cursor, brace - cursor).strip_edges()
		var inner := _brace_block(body, brace)
		if label.begins_with("Material") or label.ends_with("Material"):
			slots.append(_x_surface_key(inner))
		else:
			slots.append(str(materials.get(inner.strip_edges(), default_texture)))
		cursor = brace + inner.length() + 2
	var index_count := int(numbers[1])
	for f in face_count:
		var slot := -1
		if index_count > 0 and numbers.size() > 2:
			slot = int(numbers[2 + mini(f, mini(index_count, numbers.size() - 2) - 1)])
		result.append(slots[slot] if slot >= 0 and slot < slots.size() else default_texture)
	return result


# Blitz LoadMesh bakes the frame hierarchy into the mesh: the product of the FrameTransformMatrix of
# every Frame block that encloses the Mesh at `mesh_at` (row-vector matrices, translation in the last row).
static func _flip_z(v: Vector3) -> Vector3:
	return blitz_to_godot(v.x, v.y, v.z)


static func _frame_transform(text: String, mesh_at: int) -> Transform3D:
	var result := Transform3D.IDENTITY
	var search := 0
	while true:
		var m_at := text.find("FrameTransformMatrix", search)
		if m_at < 0 or m_at > mesh_at:
			break
		search = m_at + 20
		var m_open := text.find("{", m_at)
		var m_values := _numbers(_brace_block(text, m_open))
		if m_values.size() < 16:
			continue
		var depth := 0
		var i := m_at - 1
		var parent := -1
		while i >= 0:
			var c := text.unicode_at(i)
			if c == 125:
				depth += 1
			elif c == 123:
				if depth == 0:
					parent = i
					break
				depth -= 1
			i -= 1
		if parent < 0 or parent + _brace_block(text, parent).length() + 1 < mesh_at:
			continue
		var basis := Basis(
			Vector3(m_values[0], m_values[1], m_values[2]),
			Vector3(m_values[4], m_values[5], m_values[6]),
			Vector3(m_values[8], m_values[9], m_values[10]))
		result = result * Transform3D(basis, Vector3(m_values[12], m_values[13], m_values[14]))
	return result


static func _add_text_mesh_block(groups: Dictionary, order: PackedStringArray, block: String, frame: Transform3D, materials: Dictionary, default_texture: String) -> void:
	var geom := block
	for marker in ["MeshNormals", "MeshTextureCoords", "MeshMaterialList"]:
		var cut := geom.find(marker)
		if cut >= 0:
			geom = geom.substr(0, cut)
	var numbers := _numbers(geom)
	if numbers.size() < 4:
		return
	var cursor := 0
	var vert_count := int(numbers[cursor])
	cursor += 1
	if numbers.size() < cursor + vert_count * 3 + 1:
		return
	var positions := PackedVector3Array()
	positions.resize(vert_count)
	for v in vert_count:
		positions[v] = _flip_z(frame * Vector3(numbers[cursor], numbers[cursor + 1], numbers[cursor + 2]))
		cursor += 3
	var face_count := int(numbers[cursor])
	cursor += 1
	var triangles: Array[PackedInt32Array] = []
	for _f in face_count:
		if cursor >= numbers.size():
			break
		var nidx := int(numbers[cursor])
		cursor += 1
		var face: Array[int] = []
		for _i in nidx:
			if cursor >= numbers.size():
				break
			face.append(int(numbers[cursor]))
			cursor += 1
		var face_indices := PackedInt32Array()
		for t in maxi(0, face.size() - 2):
			face_indices.append(face[0])
			face_indices.append(face[t + 1])
			face_indices.append(face[t + 2])
		triangles.append(face_indices)
	var uvs := PackedVector2Array()
	uvs.resize(vert_count)
	var uv_at := block.find("MeshTextureCoords")
	if uv_at >= 0:
		var uv_numbers := _numbers(block.substr(uv_at))
		if uv_numbers.size() >= 1 + int(uv_numbers[0]) * 2:
			var ncoords := int(uv_numbers[0])
			for v in mini(ncoords, vert_count):
				uvs[v] = Vector2(uv_numbers[1 + v * 2], uv_numbers[2 + v * 2])
	var remaps := {}
	var face_textures := _x_face_textures(block, triangles.size(), materials, default_texture)
	var normals := _x_normals(block, frame, positions, triangles, face_textures, default_texture)
	for f in triangles.size():
		var texture_name := face_textures[f] if not face_textures.is_empty() else default_texture
		if not groups.has(texture_name):
			groups[texture_name] = {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
			order.append(texture_name)
		var group: Dictionary = groups[texture_name]
		var group_positions: PackedVector3Array = group.positions
		var group_normals: PackedVector3Array = group.normals
		var group_uvs: PackedVector2Array = group.uvs
		var group_indices: PackedInt32Array = group.indices
		var remap: Dictionary = remaps.get_or_add(texture_name, {})
		var corners: PackedInt32Array = triangles[f]
		for c in corners.size():
			var old := corners[c]
			if not remap.has(old):
				remap[old] = group_positions.size()
				group_positions.append(positions[old])
				group_normals.append((normals[f] as PackedVector3Array)[c])
				group_uvs.append(uvs[old])
			group_indices.append(remap[old])
		group.positions = group_positions
		group.normals = group_normals
		group.uvs = group_uvs
		group.indices = group_indices


# The vertex normals Blitz3D gives a .x mesh (loader_x.cpp): the file's MeshNormals when there is one per vertex,
# else Surface::updateNormals, the sum of the unit normals of the faces at the same position on the same surface.
# Returned per face and corner. Worked out in Blitz space (z not yet flipped), where the faces wind clockwise.
static func _x_normals(block: String, frame: Transform3D, positions: PackedVector3Array, triangles: Array[PackedInt32Array], face_textures: PackedStringArray, default_texture: String) -> Array[PackedVector3Array]:
	var per_vertex := PackedVector3Array()
	var normals_at := block.find("MeshNormals")
	if normals_at >= 0:
		var numbers := _numbers(block.substr(normals_at + 11))
		if numbers.size() >= 1 and int(numbers[0]) == positions.size() and numbers.size() >= 1 + positions.size() * 3:
			var turn := frame.basis.inverse().transposed()
			for v in positions.size():
				per_vertex.append(_flip_z(turn * Vector3(numbers[1 + v * 3], numbers[2 + v * 3], numbers[3 + v * 3])).normalized())
	var smooth := {}
	if per_vertex.is_empty():
		for f in triangles.size():
			var texture_name := face_textures[f] if not face_textures.is_empty() else default_texture
			var sums: Dictionary = smooth.get_or_add(texture_name, {})
			var corners: PackedInt32Array = triangles[f]
			for t in range(0, corners.size() - 2, 3):
				var a := _flip_z(positions[corners[t]])
				var n := (_flip_z(positions[corners[t + 1]]) - a).cross(_flip_z(positions[corners[t + 2]]) - a)
				if n.length() <= 0.000001:
					continue
				n = n.normalized()
				for k in 3:
					var at := positions[corners[t + k]]
					sums[at] = sums.get(at, Vector3.ZERO) + n
	var out: Array[PackedVector3Array] = []
	for f in triangles.size():
		var corners: PackedInt32Array = triangles[f]
		var texture_name := face_textures[f] if not face_textures.is_empty() else default_texture
		var face := PackedVector3Array()
		for old in corners:
			if not per_vertex.is_empty():
				face.append(per_vertex[old])
			else:
				face.append(_flip_z((smooth[texture_name] as Dictionary).get(positions[old], Vector3.ZERO)).normalized())
		out.append(face)
	return out


static func _numbers(text: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var i := 0
	while i < text.length():
		var c := text.unicode_at(i)
		if c == 45 or (c >= 48 and c <= 57):
			var j := i + 1
			while j < text.length():
				var d := text.unicode_at(j)
				if (d >= 48 and d <= 57) or d == 46 or d == 101 or d == 69 or d == 43 or d == 45:
					j += 1
				else:
					break
			out.append(float(text.substr(i, j - i)))
			i = j
		else:
			i += 1
	return out


static func _brace_block(text: String, open_brace: int) -> String:
	var depth := 0
	var i := open_brace
	while i < text.length():
		var c := text.unicode_at(i)
		if c == 123:
			depth += 1
		elif c == 125:
			depth -= 1
			if depth == 0:
				return text.substr(open_brace + 1, i - open_brace - 1)
		i += 1
	return text.substr(open_brace + 1)


static func _room_material(albedo: Texture2D, lightmap: Texture2D, alpha: bool, albedo_x2: bool = false) -> ShaderMaterial:
	_lock.lock()
	if _opaque_shader == null:
		_opaque_shader = load("res://shaders/lightmap.gdshader")
		_alpha_shader = load("res://shaders/lightmap_alpha.gdshader")
	_lock.unlock()
	var mat := ShaderMaterial.new()
	mat.shader = _alpha_shader if alpha else _opaque_shader
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("lightmap_tex", lightmap if lightmap != null else _white_tex())
	mat.set_shader_parameter("use_lightmap", lightmap != null)
	mat.set_shader_parameter("light_energy", 1.0)
	mat.set_shader_parameter("albedo_x2", albedo_x2)
	if alpha:
		mat.render_priority = 5       # panes after the decals and sprites behind them
	return mat


# Blitz entities have no lights of their own: AmbientLight Brightness (options.ini, /255) is
# the only light they get, so models are albedo * ambient.
static var _ambient := -1.0

static func entity_ambient() -> float:
	if _ambient < 0.0:
		var forced := OS.get_environment("SCP_ENTITY_AMBIENT")
		if not forced.is_empty():
			_ambient = float(forced)
			return _ambient
		var ini := IniFile.parse(ContentPaths.existing_file("options.ini"))
		_ambient = clampf(float(ini.get_value("options", "brightness", "50")) / 255.0, 0.05, 1.0)
	return _ambient


# Blitz multiplies the ambient with the texture in gamma space, Godot in linear space, which leaves dark textures
# (fuse box, key card) at about a fifth of the original's brightness. The square root lifts the ambient colour so
# that they come out as bright as in the original at the default brightness 50 (measured in room106).
static func ambient_colour(blitz_ambient: float) -> Color:
	var v := sqrt(blitz_ambient)
	return Color(v, v, v)

# AmbientLight: the models (EntityMaterial) take the Blitz value itself; the environment's lifted colour is left for
# the few standard materials that are still lit by Godot.
static func set_ambient(env: Environment, blitz_ambient: float) -> void:
	env.ambient_light_color = ambient_colour(blitz_ambient)
	RenderingServer.global_shader_parameter_set(&"entity_ambient", Vector3.ONE * blitz_ambient)


# Models are lit like Blitz3D's fixed pipeline: ambient (options.ini brightness) plus the shown room lights,
# diffuse only and per vertex (EntityMaterial).
static func entity_material(albedo: Texture2D, alpha: bool, cutout: bool = false) -> EntityMaterial:
	var mat := EntityMaterial.new()
	mat.albedo_texture = albedo if albedo != null else _white_tex()
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	elif cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return mat


static func _load_texture(path: String) -> Texture2D:
	_lock.lock()
	var texture := _load_texture_locked(path)
	_lock.unlock()
	return texture


static var _intensity_alpha: Dictionary = {}


# The materials sample with mipmaps, but an image loaded from a file has none and ImageTexture does not make them: without
# them every textured surface shimmers when the camera moves or rolls (the pocket dimension's dirt, table tops, tile floors).
static func _mipped_texture(image: Image) -> ImageTexture:
	_prepare_image(image)
	return ImageTexture.create_from_image(image)


# Every texture goes through here once, on whichever thread read it.
static func _prepare_image(image: Image) -> void:
	if image.is_compressed() or image.has_mipmaps():
		return
	_fill_clear_texels(image)
	image.generate_mipmaps()


# A straight-alpha picture keeps whatever colour lies under its clear texels (white round the black smoke, pale grey round
# every blood decal). Linear filtering mixes that colour into the outline, and each mipmap level mixes more of it in, until
# the far levels are the hidden colour at a low alpha over the whole quad: a pale outline up close and a pale square from
# afar. The clear texels take the picture's average visible colour, and those next to the picture the colour beside them.
static func _fill_clear_texels(image: Image) -> void:
	if image.detect_alpha() == Image.ALPHA_NONE:
		return
	image.convert(Image.FORMAT_RGBA8)
	var average := image.duplicate() as Image
	average.premultiply_alpha()
	while average.get_width() > 1 or average.get_height() > 1:
		average.resize(maxi(average.get_width() / 2, 1), maxi(average.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	var mean := average.get_pixel(0, 0)
	if mean.a <= 0.0:
		return
	var filled := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	filled.fill(Color(mean.r / mean.a, mean.g / mean.a, mean.b / mean.a, 0.0))
	filled.blit_rect_mask(image, image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	filled.fix_alpha_edges()
	image.copy_from(filled)


static func _has_blended_alpha(texture: Texture2D) -> bool:
	var image := _plain_image(texture)
	return image != null and image.detect_alpha() == Image.ALPHA_BLEND


static func _plain_image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	return image

static var _masked: Dictionary = {}

# Blitz LoadTexture flag 4: pure black is clear. Models use it for fences, grates and the like.
static func _load_texture_masked(path: String) -> Texture2D:
	var source := _load_texture(path)
	if _masked.has(source):
		return _masked[source]
	var image := _plain_image(source)
	if image == null or image.is_empty():
		_masked[source] = source
		return source
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		if data[i] + data[i + 1] + data[i + 2] <= 6:
			data[i + 3] = 0
	var result := _mipped_texture(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data))
	_masked[source] = result
	return result


# Blitz LoadTexture flag 2 on a picture without an alpha channel (every JPG) takes the alpha from the colour: black is clear.
static func _load_texture_intensity_alpha(path: String) -> Texture2D:
	var source := _load_texture(path)
	if _intensity_alpha.has(source):
		return _intensity_alpha[source]
	var image := _plain_image(source)
	if image == null or image.is_empty() or image.detect_alpha() != Image.ALPHA_NONE:
		_intensity_alpha[source] = source
		return source
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		data[i + 3] = maxi(data[i], maxi(data[i + 1], data[i + 2]))
	var result := _mipped_texture(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data))
	_intensity_alpha[source] = result
	return result


static func _load_texture_locked(path: String) -> Texture2D:
	if path.is_empty():
		return _white_tex()
	if _textures.has(path):
		return _textures[path]
	var resolved := ContentPaths.match_case_absolute(path)
	if not FileAccess.file_exists(resolved):
		for ext in [".jpg", ".jpeg", ".png", ".JPG", ".PNG"]:
			var alt: String = path.get_basename() + ext
			if FileAccess.file_exists(alt):
				resolved = alt
				break
	if not FileAccess.file_exists(resolved):
		# the original's material cache is keyed by the stripped name, so a texture first loaded from another folder is
		# reused; looking in a fixed list of folders gives that without depending on what happens to be cached
		if MISSING_IN_RELEASE.has(path.get_file().to_lower()):
			_textures[path] = _white_tex()
			return _white_tex()
		var same_name := _find_by_name(path)
		if not same_name.is_empty():
			var shared := _load_texture_locked(same_name)
			_textures[path] = shared
			return shared
		push_warning("Missing texture %s" % path)
		_textures[path] = _white_tex()
		return _white_tex()
	var image := load_image(resolved)
	if image == null or image.is_empty():
		_textures[path] = _white_tex()
		return _white_tex()
	var tex := _mipped_texture(image)
	_textures[path] = tex
	return tex


# Named by meshes but absent from the 1.3.11 release too (1048_1.jpg is repainted in code, scp-012_diffuse.png stays untextured there as well)
const MISSING_IN_RELEASE := ["1048_1.jpg", "scp-012_diffuse.png"]


const SAME_NAME_FOLDERS := ["", "/Props", "/forest", "/dimension1499", "/sky"]


static func _find_by_name(path: String) -> String:
	var map_end := path.find("/GFX/map")
	var folders: Array[String] = [path.get_base_dir()]
	if map_end >= 0:
		for sub: String in SAME_NAME_FOLDERS:
			var folder := path.substr(0, map_end + 8) + sub
			if not folders.has(folder):
				folders.append(folder)
	var name := path.get_file()
	for folder in folders:
		for candidate in [folder + "/" + name, folder + "/" + name.get_basename() + ".jpg", folder + "/" + name.get_basename() + ".png"]:
			if candidate != path and FileAccess.file_exists(candidate):
				return candidate
	return ""


static func _white_tex() -> Texture2D:
	_lock.lock()
	var texture := _white_tex_locked()
	_lock.unlock()
	return texture


static func _white_tex_locked() -> Texture2D:
	if _white != null:
		return _white
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	return _white


static func _is_image(text: String) -> bool:
	var lower := text.to_lower()
	return lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".png")


class _Reader:
	extends RefCounted
	var data: PackedByteArray = PackedByteArray()
	var pos: int = 0

	func _init(path: String) -> void:
		if FileAccess.file_exists(path):
			data = FileAccess.get_file_as_bytes(path)

	func i32() -> int:
		var v := data.decode_s32(pos)
		pos += 4
		return v

	func u32() -> int:
		var v := data.decode_u32(pos)
		pos += 4
		return v

	func u16() -> int:
		var v := data.decode_u16(pos)
		pos += 2
		return v

	func f32() -> float:
		var v := data.decode_float(pos)
		pos += 4
		return v

	func u8() -> int:
		var v := data[pos]
		pos += 1
		return v

	func tag() -> String:
		var s := data.slice(pos, pos + 4).get_string_from_ascii()
		pos += 4
		return s

	func blitz_string() -> String:
		var n := i32()
		if n <= 0:
			return ""
		var bytes := data.slice(pos, pos + n)
		pos += n
		var end := bytes.find(0)      # a terminating NUL is not part of the text
		if end >= 0:
			bytes = bytes.slice(0, end)
		return bytes.get_string_from_utf8()

	func cstr() -> String:
		var start := pos
		while pos < data.size() and data[pos] != 0:
			pos += 1
		var s := data.slice(start, pos).get_string_from_utf8()
		pos += 1
		return s

	func x_name() -> String:
		var n := u32()
		var s := data.slice(pos, pos + n).get_string_from_ascii()
		pos += n
		return s

	func x_string() -> String:
		var n := u32()
		var s := data.slice(pos, pos + n).get_string_from_ascii()
		pos += n
		if pos + 1 < data.size():
			pos += 2
		return s

# ---- floor materials (Data/materials.ini "stepsound") -------------------------------

static var _metal_textures: Dictionary = {}
static var _metal_loaded := false

static func is_metal_texture(texture_path: String) -> bool:
	if texture_path.is_empty():
		return false
	_lock.lock()
	if not _metal_loaded:
		_metal_loaded = true
		var ini: RefCounted = IniFile.parse(ContentPaths.existing_file("Data/materials.ini"))
		for section in ini.sections.keys():
			if int(ini.get_value(section, "stepsound", "0")) > 0:
				_metal_textures[section] = true
	var metal := _metal_textures.has(texture_path.get_file().to_lower())
	_lock.unlock()
	return metal

# 1 when the drawn triangle highest under (x, z) below max_y is a metal texture, else 0.
static func step_type_at(faces: PackedVector3Array, drawn_start: int, drawn_metal: PackedByteArray, x: float, z: float, max_y: float) -> int:
	var best := -999.0
	var kind := 0
	var i := drawn_start
	var tri := 0
	while i + 2 < faces.size() and tri < drawn_metal.size():
		var hit := _ray_down(x, z, faces[i], faces[i + 1], faces[i + 2])
		if hit < max_y and hit > best:
			best = hit
			kind = drawn_metal[tri]
		i += 3
		tri += 1
	return kind

# ---- room mesh: parse (any thread) and build (main thread) ------------------------------

static var _parsed_cache: Dictionary = {}

# Decodes a texture file into `images` unless the texture already exists (image decoding does
# not touch the rendering server).
static func _decode_image(images: Dictionary, path: String) -> void:
	if path.is_empty() or images.has(path):
		return
	_lock.lock()
	var known := _textures.has(path)
	_lock.unlock()
	if known:
		return
	var resolved := path
	if not FileAccess.file_exists(resolved):
		for ext in [".jpg", ".jpeg", ".png", ".JPG", ".PNG"]:
			var alt: String = path.get_basename() + ext
			if FileAccess.file_exists(alt):
				resolved = alt
				break
	if not FileAccess.file_exists(resolved):
		return
	var image := load_image(resolved)
	if image != null and not image.is_empty():
		_prepare_image(image)
		images[path] = image

static func _texture_from(parsed: Dictionary, path: String) -> Texture2D:
	if path.is_empty():
		return _white_tex()
	_lock.lock()
	var known: Texture2D = _textures.get(path)
	_lock.unlock()
	if known != null:
		return known
	if parsed.images.has(path):
		var texture := _mipped_texture(parsed.images[path])
		_lock.lock()
		_textures[path] = texture
		_lock.unlock()
		return texture
	return _load_texture(path)

# Mesh, materials and textures from parse_rmesh output. Main thread only.
static func build_rmesh(parsed: Dictionary) -> Dictionary:
	var mesh := ArrayMesh.new()
	for surface_data in parsed.surfaces:
		var index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_data.arrays)
		var albedo := _texture_from(parsed, str(surface_data.albedo))
		var lightmap: Texture2D = null
		if not str(surface_data.light).is_empty():
			lightmap = _texture_from(parsed, str(surface_data.light))
		mesh.surface_set_material(index, _room_material(albedo, lightmap, bool(surface_data.alpha), bool(surface_data.get("albedo_x2", false))))
	var result := parsed.duplicate()
	result.erase("surfaces")
	result.erase("images")
	result["visual"] = mesh
	return result

static func load_rmesh(path: String) -> Dictionary:
	return build_rmesh(parse_rmesh(path))

static func parse_rmesh_cached(path: String) -> Dictionary:
	_lock.lock()
	if _parsed_cache.has(path):
		var hit: Dictionary = _parsed_cache[path]
		_lock.unlock()
		return hit
	_lock.unlock()
	var parsed := parse_rmesh(path)
	_lock.lock()
	_parsed_cache[path] = parsed
	_lock.unlock()
	return parsed

# True once the file has been parsed (so a build needs no disk work).
static func has_cached_rmesh(path: String) -> bool:
	_lock.lock()
	var found := _parsed_cache.has(path) or _rmesh_cache.has(path)
	_lock.unlock()
	return found

# The built room mesh of a template; rooms of one template share it. Main thread only.
static func load_rmesh_cached(path: String) -> Dictionary:
	if _rmesh_cache.has(path):
		return _rmesh_cache[path]
	var built := build_rmesh(parse_rmesh_cached(path))
	_rmesh_cache[path] = built
	# the parsed arrays now live in the built mesh; keep only one copy
	_lock.lock()
	_parsed_cache.erase(path)
	_lock.unlock()
	return built

# Image.load_from_file picks the decoder from the extension, and some .jpg files are PNGs (INVwallet.jpg, LockdownScreen3):
# the image is read by what the bytes are, and by the extension only when they are not a format it knows.
static func load_image(path: String) -> Image:
	var image := _load_by_content(path)
	return image if image != null and not image.is_empty() else Image.load_from_file(path)

static func _load_by_content(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 4:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4D:
		error = image.load_bmp_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49:
		error = image.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x44 and bytes[1] == 0x44:
		error = image.load_dds_from_buffer(bytes)
	return image if error == OK else null
