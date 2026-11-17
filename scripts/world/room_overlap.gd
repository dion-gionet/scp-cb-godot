extends RefCounted
# PreventRoomOverlap (MapSystem.bb:8597), which CreateMap runs for every room once the map is built (MapSystem.bb:7586):
# a room whose extents overlap another room's is turned 180 degrees if it is a ROOM2, else swapped with rooms of the same
# template shape and zone. Quirks kept from the original:
# - CreateRoom computes the extents before CreateMap turns the room, so they stay unrotated until the room is turned or
#   swapped here (CalculateRoomExtents recomputes them with the real angle).
# - The swap loop does not stop at the first swap that works: it goes on swapping with every later candidate that also fits.
# - The 0.05 shrink is applied before the min/max swap, so a turned axis grows by it instead.
# - y is not offset by the room's height, so dimension1499 (y = 800) is checked as if it were on the floor.
# Extents use Blitz world units: x = grid x * 8, z = grid y * 8. Floats are 32-bit as in Blitz.


const ROOM_SCALE := 8.0 / 2048.0
const SHRINK := 0.05
const NO_SWAP := ["checkpoint1", "checkpoint2", "start"]

static var _mesh_extents: Dictionary = {}

# rooms: {name, shape (template shape), zone, x, z, angle, disabled, mesh_min, mesh_max}; x, z and angle are updated.
static func resolve(rooms: Array) -> void:
	for room in rooms:
		_calc(room, 0)
	for room in rooms:
		_prevent(room, rooms)

static func _prevent(r: Dictionary, rooms: Array) -> void:
	if bool(r.disabled) or NO_SWAP.has(str(r.name)):
		return
	if not _hits_any(r, rooms):
		return
	if int(r.shape) == 2:
		r.angle = int(r.angle) + 180
		_calc(r, int(r.angle))
		if not _hits_any(r, rooms):
			return
		r.angle = int(r.angle) - 180
		_calc(r, int(r.angle))
	for r2 in rooms:
		if is_same(r2, r) or bool(r2.disabled):
			continue
		if int(r2.shape) != int(r.shape) or int(r2.zone) != int(r.zone) or NO_SWAP.has(str(r2.name)):
			continue
		var x := _grid(float(r.x))
		var y := _grid(float(r.z))
		var rot := int(r.angle)
		var x2 := _grid(float(r2.x))
		var y2 := _grid(float(r2.z))
		var rot2 := int(r2.angle)
		_place(r, x2, y2, rot2)
		_place(r2, x, y, rot)
		var hit := false
		for r3 in rooms:
			if bool(r3.disabled):
				continue
			if not is_same(r3, r) and _overlap(r, r3):
				hit = true
				break
			if not is_same(r3, r2) and _overlap(r2, r3):
				hit = true
				break
		if hit:
			_place(r, x, y, rot)
			_place(r2, x2, y2, rot2)

static func _hits_any(r: Dictionary, rooms: Array) -> bool:
	for r2 in rooms:
		if not is_same(r2, r) and not bool(r2.disabled) and _overlap(r, r2):
			return true
	return false

static func _place(r: Dictionary, gx: int, gy: int, angle: int) -> void:
	r.x = float(gx) * 8.0
	r.z = float(gy) * 8.0
	r.angle = angle
	_calc(r, angle)

# Local x% = r\x / 8.0 rounds to the nearest int.
static func _grid(value: float) -> int:
	return int(round(value / 8.0))

static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3 = a.ext_min
	var amax: Vector3 = a.ext_max
	var bmin: Vector3 = b.ext_min
	var bmax: Vector3 = b.ext_max
	if amax.x <= bmin.x or amax.y <= bmin.y or amax.z <= bmin.z:
		return false
	if amin.x >= bmax.x or amin.y >= bmax.y or amin.z >= bmax.z:
		return false
	return true

# CalculateRoomExtents (MapSystem.bb:8558): TFormVector of the template's mesh extents through the room's scale and yaw.
static func _calc(r: Dictionary, angle: int) -> void:
	if bool(r.disabled):
		r.ext_min = Vector3.ZERO
		r.ext_max = Vector3.ZERO
		return
	var lo := _tform(r.mesh_min, angle)
	var hi := _tform(r.mesh_max, angle)
	var x := float(r.x)
	var z := float(r.z)
	var mn := Vector3(_f(_f(lo.x + SHRINK) + x), _f(lo.y + SHRINK), _f(_f(lo.z + SHRINK) + z))
	var mx := Vector3(_f(_f(hi.x - SHRINK) + x), _f(hi.y - SHRINK), _f(_f(hi.z - SHRINK) + z))
	if mn.x > mx.x:
		var t := mx.x
		mx.x = mn.x
		mn.x = t
	if mn.z > mx.z:
		var t := mx.z
		mx.z = mn.z
		mn.z = t
	r.ext_min = mn
	r.ext_max = mx

# Blitz3D's RotateEntity and TFormVector in 32-bit floats (DirectX 7 leaves the FPU in single precision): the yaw
# quaternion (cos(y / -2), sin(y / -2)), normalised, becomes a matrix whose 90/270-degree terms are 1.0000001 (2*w*qy)
# and -1.19e-7 (1-2*qy^2) (not 1.0 and 5.96e-8) and whose 180-degree cross terms are 8.7e-8. That overshoot carries room106's
# turned edge (20.0500011) past room4pit's (20.0499992) at seed 57; the unnormalised 0.99999994 gives no overlap. Do not snap
# the terms to 1.0. The extents of rooms that touch exactly depend on that rounding.
# A yaw of +90 turns local +z to world -x and local +x to world +z.
const DTOR := 0.0174532925199432957692369076848

static func _tform(v: Vector3, angle: int) -> Vector3:
	var half := _f(_f(float(angle) * _f(DTOR)) / -2.0)
	var w := _f(cos(half))
	var qy := _f(sin(half))
	var length := _f(sqrt(_f(_f(w * w) + _f(qy * qy))))
	w = _f(w / length)
	qy = _f(qy / length)
	var yy := _f(qy * qy)
	var wy := _f(w * qy)
	var diag := _f(1.0 - _f(2.0 * yy))
	var ix := _f(diag * ROOM_SCALE)
	var iz := _f(_f(2.0 * _f(-wy)) * ROOM_SCALE)
	var kx := _f(_f(2.0 * wy) * ROOM_SCALE)
	var kz := ix
	var y := _f(v.y * ROOM_SCALE)
	return Vector3(_f(_f(ix * v.x) + _f(kx * v.z)), y, _f(_f(iz * v.x) + _f(kz * v.z)))

static func _f(value: float) -> float:
	return BlitzRng._f32(value)

# GetMeshExtents of the room mesh's drawn surfaces (LoadRMesh child 2: opaque and alpha meshes), in rmesh units.
static func mesh_extents(path: String) -> Array:
	if _mesh_extents.has(path):
		return _mesh_extents[path]
	var result := [Vector3.ZERO, Vector3.ZERO]
	var f := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if f != null:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		_string(f)
		var drawn := f.get_32()
		for _i in drawn:
			for _slot in 2:
				if f.get_8() != 0:
					_string(f)
			var verts := f.get_32()
			for _v in verts:
				var p := Vector3(f.get_float(), f.get_float(), f.get_float())
				lo = lo.min(p)
				hi = hi.max(p)
				f.seek(f.get_position() + 19)
			var tris := f.get_32()
			f.seek(f.get_position() + tris * 12)
		if drawn > 0:
			result = [lo, hi]
	_mesh_extents[path] = result
	return result

static func _string(f: FileAccess) -> String:
	var n := f.get_32()
	return f.get_buffer(n).get_string_from_ascii()
