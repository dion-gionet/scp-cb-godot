class_name CoplanarTrim
extends RefCounted
# Removes the parts of triangles that lie in the same plane, facing the same way, as an earlier triangle of the mesh.
# Such overlaps are drawn at equal depth, so which one shows is decided by rounding and changes from frame to frame
# (z-fighting). The pocket dimension's tunnel (pocketdimension2.b3d) has a floor slab whose sides and ends lie in the
# planes of the tunnel's walls and mouth with another UV mapping: with the tunnels rescaled every frame, a strip along
# the bottom of every wall flashed between the two. The earlier triangle wins, so each spot of a plane is drawn once.

const SAME_NORMAL := 0.9999     # cosine between the normals of one plane
const SAME_DISTANCE := 0.01     # model units between the planes' distances from the origin
const MIN_PIECE := 1e-6         # pieces smaller than this share of their triangle are dropped,
const MIN_AREA := 0.01          # and slivers below this many square model units (clipping noise)

static var _cache: Dictionary = {}

# `unit`: one model unit in the mesh's coordinates (RoomScale for an rmesh, which is in metres), so the tolerances below
# mean the same for both. `prior`: triangles of other meshes, in this mesh's space, counted as drawn first, so the parts
# of this mesh lying on them are trimmed too (the result is not cached).
static func apply(mesh: ArrayMesh, unit := 1.0, prior := PackedVector3Array()) -> ArrayMesh:
	if mesh == null:
		return null
	if not prior.is_empty():
		return _trim(mesh, unit, prior)
	if _cache.has(mesh):
		return _cache[mesh]
	var result := _trim(mesh, unit, prior)
	_cache[mesh] = result
	return result

static func _trim(mesh: ArrayMesh, unit: float, prior: PackedVector3Array) -> ArrayMesh:
	var planes: Dictionary = {}       # roundi(distance) -> Array of {normal, distance, drawn: the 2D triangles already in it}
	for t in range(0, prior.size() - 2, 3):
		var a := prior[t] / unit
		var b := prior[t + 1] / unit
		var c := prior[t + 2] / unit
		var normal := (b - a).cross(c - a)
		if normal.length_squared() >= 1e-12:
			var plane := _plane_of(planes, normal.normalized(), normal.normalized().dot(a))
			plane.drawn.append(_counter_clockwise(_flat(a, b, c, plane.normal)))
	var surfaces: Array = []
	var changed := false
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if indices != null else vertices.size()
		var corners: Array[int] = []      # per output vertex: the three source vertex indices it blends
		var weights: Array[Vector3] = []  # and its weights
		for t in range(0, count, 3):
			var ids: Array[int] = [t, t + 1, t + 2]
			if indices != null:
				ids = [indices[t], indices[t + 1], indices[t + 2]]
			var a := vertices[ids[0]] / unit
			var b := vertices[ids[1]] / unit
			var c := vertices[ids[2]] / unit
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-12:
				_keep_whole(ids, corners, weights)
				continue
			normal = normal.normalized()
			var plane := _plane_of(planes, normal, normal.dot(a))
			var flat := _flat(a, b, c, plane.normal)      # one projection for the whole plane, so its triangles compare
			var pieces: Array = [_counter_clockwise(flat)]
			for other in plane.drawn:
				var next: Array = []
				for piece in pieces:
					next.append_array(_subtract(piece, other))
				pieces = next
				if pieces.is_empty():
					break
			var whole := _area(flat)
			var kept: Array = pieces.filter(func(piece: PackedVector2Array) -> bool: return _area(piece) > maxf(whole * MIN_PIECE, MIN_AREA))
			if kept.size() == 1 and absf(_area(kept[0]) - whole) <= whole * 1e-6:
				_keep_whole(ids, corners, weights)
			else:
				changed = true
				var flip := _signed_area(flat) < 0.0      # the pieces are counter-clockwise; keep the triangle's own winding
				for piece in kept:
					for i in range(1, piece.size() - 1):
						var fan := [piece[0], piece[i + 1], piece[i]] if flip else [piece[0], piece[i], piece[i + 1]]
						if _area(PackedVector2Array(fan)) < 1e-6:
							continue      # clipping repeats a point that lies on a cut line
						for point in fan:
							corners.append_array(ids)
							weights.append(_barycentric(point, flat))
			plane.drawn.append(_counter_clockwise(flat))
		surfaces.append({"arrays": arrays, "corners": corners, "weights": weights})
	if not changed:
		return mesh
	var trimmed := ArrayMesh.new()
	for surface in surfaces.size():
		var entry: Dictionary = surfaces[surface]
		trimmed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _rebuild(entry.arrays, entry.corners, entry.weights))
		trimmed.surface_set_material(surface, mesh.surface_get_material(surface))
	return trimmed

static func _keep_whole(ids: Array[int], corners: Array[int], weights: Array[Vector3]) -> void:
	for k in 3:
		corners.append_array(ids)
		weights.append(Vector3(1.0 if k == 0 else 0.0, 1.0 if k == 1 else 0.0, 1.0 if k == 2 else 0.0))

# Every output corner is a blend of its source triangle's three corners, for each attribute the surface has.
static func _rebuild(arrays: Array, corners: Array[int], weights: Array[Vector3]) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var n := weights.size()
	var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vertices := PackedVector3Array()
	vertices.resize(n)
	for i in n:
		var w := weights[i]
		vertices[i] = source_vertices[corners[i * 3]] * w.x + source_vertices[corners[i * 3 + 1]] * w.y + source_vertices[corners[i * 3 + 2]] * w.z
	out[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var source: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normals := PackedVector3Array()
		normals.resize(n)
		for i in n:
			var w := weights[i]
			normals[i] = (source[corners[i * 3]] * w.x + source[corners[i * 3 + 1]] * w.y + source[corners[i * 3 + 2]] * w.z).normalized()
		out[Mesh.ARRAY_NORMAL] = normals
	for slot in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[slot] != null:
			var source: PackedVector2Array = arrays[slot]
			var uvs := PackedVector2Array()
			uvs.resize(n)
			for i in n:
				var w := weights[i]
				uvs[i] = source[corners[i * 3]] * w.x + source[corners[i * 3 + 1]] * w.y + source[corners[i * 3 + 2]] * w.z
			out[slot] = uvs
	if arrays[Mesh.ARRAY_COLOR] != null:
		var source: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var colors := PackedColorArray()
		colors.resize(n)
		for i in n:
			var w := weights[i]
			colors[i] = source[corners[i * 3]] * w.x + source[corners[i * 3 + 1]] * w.y + source[corners[i * 3 + 2]] * w.z
		out[Mesh.ARRAY_COLOR] = colors
	return out

# Planes are matched with a tolerance: rounding to a key would split a plane whose distance sits on a rounding boundary.
static func _plane_of(planes: Dictionary, normal: Vector3, distance: float) -> Dictionary:
	var bucket := roundi(distance)
	for near in [bucket, bucket - 1, bucket + 1]:
		for plane in planes.get(near, []):
			if plane.normal.dot(normal) > SAME_NORMAL and absf(plane.distance - distance) < SAME_DISTANCE:
				return plane
	var created := {"normal": normal, "distance": distance, "drawn": []}
	if not planes.has(bucket):
		planes[bucket] = []
	planes[bucket].append(created)
	return created

# Drops the normal's largest axis.
static func _flat(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> PackedVector2Array:
	return PackedVector2Array([_project(a, normal), _project(b, normal), _project(c, normal)])

static func _project(v: Vector3, normal: Vector3) -> Vector2:
	var axis := normal.abs()
	if axis.x >= axis.y and axis.x >= axis.z:
		return Vector2(v.y, v.z)
	if axis.y >= axis.z:
		return Vector2(v.x, v.z)
	return Vector2(v.x, v.y)

static func _counter_clockwise(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := polygon.duplicate()
	if _signed_area(result) < 0.0:
		result.reverse()
	return result

static func _signed_area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size():
		sum += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return sum * 0.5

static func _area(polygon: PackedVector2Array) -> float:
	return absf(_signed_area(polygon))

# Convex piece minus a convex (counter-clockwise) triangle, as convex pieces: the part outside edge 0, then the part inside
# edge 0 but outside edge 1, and so on. No holes come out of it, unlike a general polygon difference.
static func _subtract(piece: PackedVector2Array, triangle: PackedVector2Array) -> Array:
	var result: Array = []
	var rest := piece
	for i in triangle.size():
		var a := triangle[i]
		var b := triangle[(i + 1) % triangle.size()]
		var outside := _clip(rest, b, a)
		if outside.size() >= 3 and _area(outside) > 0.0:
			result.append(outside)
		rest = _clip(rest, a, b)
		if rest.size() < 3:
			return result
	return result

# Sutherland-Hodgman: the part of the polygon on the left of the line from a to b.
static func _clip(polygon: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var edge := b - a
	for i in polygon.size():
		var current := polygon[i]
		var previous := polygon[i - 1]
		var side_current := edge.cross(current - a)
		var side_previous := edge.cross(previous - a)
		if side_current >= 0.0:
			if side_previous < 0.0:
				out.append(previous + (current - previous) * (side_previous / (side_previous - side_current)))
			out.append(current)
		elif side_previous >= 0.0:
			out.append(previous + (current - previous) * (side_previous / (side_previous - side_current)))
	return out

static func _barycentric(point: Vector2, triangle: PackedVector2Array) -> Vector3:
	var v0 := triangle[1] - triangle[0]
	var v1 := triangle[2] - triangle[0]
	var v2 := point - triangle[0]
	var denominator := v0.cross(v1)
	var w1 := v2.cross(v1) / denominator
	var w2 := v0.cross(v2) / denominator
	return Vector3(1.0 - w1 - w2, w1, w2)
