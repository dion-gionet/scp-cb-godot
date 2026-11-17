extends Node3D
class_name Forest
# The forest behind SCP-860's door (MapSystem.bb GenForestGrid / PlaceForest / load_terrain / UpdateForest).
# A 10 x 10 grid of 12 m tiles hangs 30 m above the room: the path (1) runs from one wooden door (3) in the bottom row to
# the other in the top row, wandering at most 3 tiles from the middle, with short dead-end branches. Each path tile is one
# of five terrain meshes made from a 30 x 30 heightmap (red = height * 0.03, scaled by 12 / 29), a ground picture, and a path
# picture laid over it where the mask is opaque; trees (four crossed planes on a trunk) and rocks stand where the heightmap
# is bright; tiles more than 20 m from the player are hidden.
# The node sits at the room's position (room x, y + 30, room z) with Blitz z flipped; positions inside are Godot ones.

const RS := 8.0 / 2048.0
const GRID := 10
const TILE := 12.0
const DEVIATION_CHANCE := 40
const BRANCH_CHANCE := 65
const BRANCH_MAX_LIFE := 4
const BRANCH_DIE_CHANCE := 18
const MAX_DEVIATION := 3
const RETURN_CHANCE := 27
const CENTER := 5
const HMAP := 30
const R1 := 1
const R2 := 2
const R2C := 3
const R3 := 4
const R4 := 5
const FILES := {R1: "forest1h", R2: "forest2h", R2C: "forest2Ch", R3: "forest3h", R4: "forest4h"}

var grid: PackedInt32Array = PackedInt32Array()
var tiles: Dictionary = {}              # grid index -> Node3D (the tile root)
var doors: Array[Node3D] = [null, null]
var walls: Array[Node3D] = [null, null]
var logs: Array = []                    # [{name, pos}] the three log documents (world positions)
var terrain_scale := 0.0

static var _tile_meshes: Dictionary = {}
static var _images: Dictionary = {}
static var _details: Dictionary = {}

static func _chance(rng: BlitzRng, percent: int) -> bool:
	return rng.randi_range(0, 100) <= percent

static func _forward_x(dir: int, path_x: int) -> int:
	return path_x if dir == 1 else path_x - 1 + dir

static func _forward_y(dir: int, path_y: int) -> int:
	return path_y + 1 if dir == 1 else path_y

static func _turn(dir: int, path_x: int) -> int:
	var deviation := CENTER - path_x
	if (dir == 0 and deviation >= MAX_DEVIATION) or (dir == 2 and deviation <= -MAX_DEVIATION):
		return (dir + 2) % 4
	return dir

static func _deviated(dir: int, path_x: int) -> bool:
	var deviation := CENTER - path_x
	return (dir == 0 and deviation >= MAX_DEVIATION) or (dir == 2 and deviation <= -MAX_DEVIATION)

static func _at(g: PackedInt32Array, index: int) -> int:
	return g[index] if index >= 0 and index < g.size() else 0

static func _put(g: PackedInt32Array, index: int, value: int) -> void:
	if index >= 0 and index < g.size():
		g[index] = value

# GenForestGrid: 1 path, 3 door, 0 nothing.
static func generate_grid(rng: BlitzRng) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(GRID * GRID + 11)
	var door1 := rng.randi_range(3, 7)
	var door2 := rng.randi_range(3, 7)
	g[door1] = 3
	g[(GRID - 1) * GRID + door2] = 3
	var path_x := door2
	var path_y := 1
	var dir := 1
	_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
	while path_y < GRID - 4:
		if dir == 1:
			if _chance(rng, DEVIATION_CHANCE):
				dir = 2 * rng.randi_range(0, 1)
				dir = _turn(dir, path_x)
				var deviated := _deviated(dir, path_x)
				if deviated:
					_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
				path_x = _forward_x(dir, path_x)
				path_y = _forward_y(dir, path_y)
		else:
			dir = _turn(dir, path_x)
			var deviated2 := _deviated(dir, path_x)
			# Blitz evaluates both sides of Or, so the chance is drawn even when the path has to turn back anyway
			var back := _chance(rng, RETURN_CHANCE)
			if deviated2 or back:
				dir = 1
			path_x = _forward_x(dir, path_x)
			path_y = _forward_y(dir, path_y)
			if dir == 1:
				_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
				path_x = _forward_x(dir, path_x)
				path_y = _forward_y(dir, path_y)
		_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
	dir = 1
	while path_y < GRID - 2:
		path_x = _forward_x(dir, path_x)
		path_y = _forward_y(dir, path_y)
		_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
	if path_x != door1:
		dir = 0
		if door1 > path_x:
			dir = 2
		while path_x != door1:
			path_x = _forward_x(dir, path_x)
			path_y = _forward_y(dir, path_y)
			_put(g, (GRID - 1 - path_y) * GRID + path_x, 1)
	# branches, every fourth row; written as -1 / -2 so they cannot be mistaken for the path
	var new_y := -3
	while new_y < GRID - 6:
		new_y += 4
		var temp_y := new_y
		var new_x := 0
		if _chance(rng, BRANCH_CHANCE):
			var branch_type := -1
			if _chance(rng, 0):          # cobble_chance is never declared in the original: 0
				branch_type = -2
			var branch_pos := 2 * rng.randi_range(0, 1)
			var leftmost := GRID
			var rightmost := 0
			for i in range(0, GRID + 1):
				if _at(g, (GRID - 1 - new_y) * GRID + i) == 1:
					if i < leftmost:
						leftmost = i
					if i > rightmost:
						rightmost = i
			new_x = leftmost - 1 if branch_pos == 0 else rightmost + 1
			if (temp_y != 0 and _at(g, (GRID - 1 - temp_y + 1) * GRID + new_x) == 1) or _at(g, (GRID - 1 - temp_y - 1) * GRID + new_x) == 1:
				break
			_put(g, (GRID - 1 - temp_y) * GRID + new_x, branch_type)
			new_x = leftmost - 2 if branch_pos == 0 else rightmost + 2
			_put(g, (GRID - 1 - temp_y) * GRID + new_x, branch_type)
			var life := 2
			while life < BRANCH_MAX_LIFE:
				life += 1
				if _chance(rng, BRANCH_DIE_CHANCE):
					break
				if rng.randi_range(0, 3) == 0:
					new_x += -1 if branch_pos == 0 else 1
				else:
					temp_y += 1
				var n := (GRID - 1 - temp_y + 1) * GRID + new_x
				if n < GRID - 1:
					if temp_y != 0 and _at(g, n) == 1:
						break
				n = (GRID - 1 - temp_y - 1) * GRID + new_x
				if n > 0:
					if _at(g, n) == 1:
						break
				_put(g, (GRID - 1 - temp_y) * GRID + new_x, branch_type)
				if temp_y >= GRID - 2:
					break
	for i in range(0, GRID):
		for j in range(0, GRID):
			if g[i * GRID + j] == -1 or g[i * GRID + j] == -2:
				g[i * GRID + j] = 1
	return g

static func _image(relative: String) -> Image:
	if _images.has(relative):
		return _images[relative]
	var image := MeshLoader.load_image(ContentPaths.existing_image(relative))
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
	_images[relative] = image
	return image

# load_terrain: two surfaces, the ground and (0.01 higher) the path with the mask's alpha in its vertex colours.
static func _terrain(kind: int) -> Array:
	if _tile_meshes.has(kind):
		return _tile_meshes[kind]
	var height_map := _image("GFX/map/forest/%s.png" % FILES[kind])
	var mask := _image("GFX/map/forest/%s_mask.png" % FILES[kind])
	var x := height_map.get_width() - 1
	var y := height_map.get_height() - 1
	var yscale := 0.03
	var uv_div := float(x / 4)
	var ground := PackedVector3Array()
	var path_verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for ly in range(0, y + 1):
		for lx in range(0, x + 1):
			var pixel := height_map.get_pixel(mini(lx, x - 1), y - mini(ly, y - 1))
			var red := int(round(pixel.r * 255.0))
			var mask_x := minf(lx * float(mask.get_width()) / float(height_map.get_width()), mask.get_width() - 1)
			var mask_y := mask.get_height() - minf(ly * float(mask.get_height()) / float(height_map.get_height()), mask.get_height() - 1)
			var alpha := _mask_alpha(mask, maxf(mask_x - 5.0, 5.0), maxf(mask_y - 5.0, 5.0))
			alpha += _mask_alpha(mask, minf(mask_x + 5.0, mask.get_width() - 5.0), minf(mask_y + 5.0, mask.get_height() - 5.0))
			alpha += _mask_alpha(mask, maxf(mask_x - 5.0, 5.0), minf(mask_y + 5.0, mask.get_height() - 5.0))
			alpha += _mask_alpha(mask, minf(mask_x + 5.0, mask.get_width() - 5.0), maxf(mask_y - 5.0, 5.0))
			alpha = sqrt(alpha * 0.25)
			var h := red * yscale
			ground.append(Vector3(lx - x / 2.0, h, -(ly - y / 2.0)))
			path_verts.append(Vector3(lx - x / 2.0, h + 0.01, -(ly - y / 2.0)))
			uvs.append(Vector2(lx / uv_div, ly / uv_div))
			colors.append(Color(1.0, 1.0, 1.0, alpha))
	var indices := PackedInt32Array()
	for ly in range(0, y):
		for lx in range(0, x):
			var a := lx + (x + 1) * ly
			var b := a + (x + 1)
			var c := (lx + 1) + (x + 1) * ly
			var d := c + (x + 1)
			# the original's (a, b, c) and (c, b, d), reversed for the flipped z
			indices.append_array([a, c, b, c, d, b])
	var meshes: Array = []
	for pass_index in 2:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ground if pass_index == 0 else path_verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		if pass_index == 1:
			arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes.append(mesh)
	_tile_meshes[kind] = meshes
	return meshes

# (alpha byte / 255) in integer arithmetic: 1 only for a fully opaque pixel
static func _mask_alpha(mask: Image, px: float, py: float) -> float:
	var pixel := mask.get_pixel(clampi(int(px), 0, mask.get_width() - 1), clampi(int(py), 0, mask.get_height() - 1))
	return 1.0 if pixel.a >= 0.999 else 0.0

static func _unshaded(mesh: Mesh) -> Mesh:
	var copy: ArrayMesh = (mesh as ArrayMesh).duplicate()
	for i in copy.get_surface_count():
		var material := copy.surface_get_material(i)
		if material is StandardMaterial3D or material is EntityMaterial:
			var own = material.duplicate()
			own.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			copy.surface_set_material(i, own)
	return copy

static func _detail_mesh(relative: String) -> Mesh:
	if not _details.has(relative):
		_details[relative] = _unshaded(MeshLoader.load_b3d_world(ContentPaths.existing_file(relative)))
	return _details[relative]

func _ground_material(texture_file: String, path: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = MeshLoader._load_texture(ContentPaths.existing_file(texture_file))
	material.texture_repeat = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if path:
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.render_priority = 1
	return material

# PlaceForest. `origin` is the pivot in the world; the door and frame meshes are the room's wooden door.
func build(grid_in: PackedInt32Array, rng: BlitzRng) -> void:
	grid = grid_in
	var ground_material := _ground_material("GFX/map/forest/forestfloor.jpg", false)
	var path_material := _ground_material("GFX/map/forest/forestpath.jpg", true)
	terrain_scale = TILE / 29.0
	var trunk := _detail_mesh("GFX/map/forest/detail/treetest4.b3d")
	var crown := _detail_mesh("GFX/map/forest/detail/treetest5.b3d")
	var rock := _detail_mesh("GFX/map/forest/detail/rock.b3d")
	var log_placed := [false, false, false, false]
	for tx in range(1, GRID):
		for ty in range(1, GRID):
			var tile := tile_kind(grid, tx, ty)
			var kind := tile.x
			var angle := tile.y
			if kind == 0:
				continue
			var root := Node3D.new()
			root.position = Vector3(tx * TILE, 0.0, -(ty * TILE))
			add_child(root)
			var terrain := Node3D.new()
			terrain.rotation.y = deg_to_rad(angle)
			terrain.scale = Vector3.ONE * terrain_scale
			root.add_child(terrain)
			var meshes: Array = _terrain(kind)
			var ground := MeshInstance3D.new()
			ground.mesh = meshes[0]
			ground.material_override = ground_material
			terrain.add_child(ground)
			var path_layer := MeshInstance3D.new()
			path_layer.mesh = meshes[1]
			path_layer.material_override = path_material
			terrain.add_child(path_layer)
			# the body is not scaled (physics ignores a body's scale): its shape is made from the scaled, turned faces
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var shape := CollisionShape3D.new()
			shape.shape = _scaled_shape(meshes[0], kind)
			body.add_child(shape)
			body.rotation.y = deg_to_rad(angle)
			root.add_child(body)
			tiles[tx + ty * GRID] = root
			if _log_here(log_placed, ty, rng):
				logs.append({"name": "Log #%d" % (ty / 3 + 1), "pos": to_global(Vector3(tx * TILE, 0.5 * terrain_scale, -(ty * TILE)))})
			_place_details(root, kind, angle, trunk, crown, rock, rng)
	_place_walls()

# PlaceForest's Select on the number of path neighbours: Vector2i(R1..R4 or 0, angle).
static func tile_kind(g: PackedInt32Array, tx: int, ty: int) -> Vector2i:
	if _at(g, ty * GRID + tx) != 1:
		return Vector2i.ZERO
	var tile_type := 0
	if tx + 1 < GRID:
		tile_type = 1 if _at(g, ty * GRID + tx + 1) > 0 else 0
	if tx - 1 >= 0:
		tile_type += 1 if _at(g, ty * GRID + tx - 1) > 0 else 0
	if ty + 1 < GRID:
		tile_type += 1 if _at(g, (ty + 1) * GRID + tx) > 0 else 0
	if ty - 1 >= 0:
		tile_type += 1 if _at(g, (ty - 1) * GRID + tx) > 0 else 0
	match tile_type:
		1:
			if _at(g, (ty + 1) * GRID + tx) > 0:
				return Vector2i(R1, 180)
			elif _at(g, ty * GRID + tx - 1) > 0:
				return Vector2i(R1, 270)
			elif _at(g, ty * GRID + tx + 1) > 0:
				return Vector2i(R1, 90)
			return Vector2i(R1, 0)
		2:
			if _at(g, (ty - 1) * GRID + tx) > 0 and _at(g, (ty + 1) * GRID + tx) > 0:
				return Vector2i(R2, 0)
			elif _at(g, ty * GRID + tx + 1) > 0 and _at(g, ty * GRID + tx - 1) > 0:
				return Vector2i(R2, 90)
			elif _at(g, ty * GRID + tx - 1) > 0 and _at(g, (ty + 1) * GRID + tx) > 0:
				return Vector2i(R2C, 180)
			elif _at(g, ty * GRID + tx + 1) > 0 and _at(g, (ty - 1) * GRID + tx) > 0:
				return Vector2i(R2C, 0)
			elif _at(g, ty * GRID + tx - 1) > 0 and _at(g, (ty - 1) * GRID + tx) > 0:
				return Vector2i(R2C, 270)
			return Vector2i(R2C, 90)
		3:
			if _at(g, (ty - 1) * GRID + tx) == 0:
				return Vector2i(R3, 180)
			elif _at(g, ty * GRID + tx - 1) == 0:
				return Vector2i(R3, 90)
			elif _at(g, ty * GRID + tx + 1) == 0:
				return Vector2i(R3, 270)
			return Vector2i(R3, 0)
		4:
			return Vector2i(R4, 0)
	return Vector2i.ZERO

# The log documents lie on the first path tile PlaceForest reaches (column by column) in each of rows 2, 5 and 8; CreateItem
# draws Rand(360) for each. (Measured against the original: Blitz does not clear the `Local itemPlaced[4]` declared inside the loop.)
static func _log_here(placed: Array, ty: int, rng: BlitzRng) -> bool:
	if ty % 3 != 2 or placed[ty / 3]:
		return false
	placed[ty / 3] = true
	rng.rand(360)
	return true

# PlaceForest's draws without building anything: CreateMap runs it inside FillRoom, so the rooms made after it depend on the count.
static func consume_place(g: PackedInt32Array, rng: BlitzRng) -> void:
	var log_placed := [false, false, false, false]
	for tx in range(1, GRID):
		for ty in range(1, GRID):
			var kind := tile_kind(g, tx, ty).x
			if kind == 0:
				continue
			_log_here(log_placed, ty, rng)
			_detail_rolls(kind, rng)

# The trees and rocks of one tile in PlaceForest's draw order: [lx, ly, red, scale, the four crown yaw offsets (empty for a
# rock), sink, pitch, yaw].
static func _detail_rolls(kind: int, rng: BlitzRng) -> Array:
	var height_map := _image("GFX/map/forest/%s.png" % FILES[kind])
	var width := height_map.get_width()
	var rolls: Array = []
	for lx in range(3, width - 1):
		for ly in range(3, width - 1):
			var red := int(round(height_map.get_pixel(lx, width - ly).r * 255.0))
			if red <= rng.rand(100, 260):
				continue
			if rng.rand(0, 7) <= 6:
				var s: float = rng.rnd(0.25, 0.4)
				var yaws: Array[float] = []
				for i in 4:
					yaws.append(rng.rnd(-20.0, 20.0))
				var sink: float = rng.rnd(3.0, 3.2)
				var pitch: float = rng.rnd(-5.0, 5.0)
				var yaw: float = rng.rnd(360.0)
				rolls.append([lx, ly, red, s, yaws, sink, pitch, yaw])
			else:
				var s2: float = rng.rnd(0.01, 0.012)
				rolls.append([lx, ly, red, s2, [], 0.0, 0.0, rng.rnd(360.0)])
	return rolls

func _place_details(root: Node3D, kind: int, angle: int, trunk: Mesh, crown: Mesh, rock: Mesh, rng: BlitzRng) -> void:
	var width := _image("GFX/map/forest/%s.png" % FILES[kind]).get_width()
	var mesh_width := 29.0
	var step := mesh_width / float(width)
	var turn := Basis(Vector3.UP, deg_to_rad(angle))
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	for roll in _detail_rolls(kind, rng):
		var local_x: float = roll[0] * step - mesh_width / 2.0
		var local_z: float = roll[1] * step - mesh_width / 2.0
		var red: int = roll[2]
		var s: float = roll[3]
		var yaws: Array = roll[4]
		if not yaws.is_empty():
			var offset := turn * (Vector3(local_x, red * 0.03 - float(roll[5]), -local_z) * terrain_scale)
			var tilt := Basis.from_euler(Vector3(-deg_to_rad(float(roll[6])), deg_to_rad(float(roll[7])), 0.0), EULER_ORDER_YXZ)
			var scale_basis := Basis.from_scale(Vector3(s * 1.1, s, s * 1.1))
			trunks.append(Transform3D(tilt * scale_basis, offset))
			for i in 4:
				var yaw := Basis(Vector3.UP, deg_to_rad(90.0 * i + float(yaws[i])))
				crowns.append(Transform3D(tilt * scale_basis * yaw, offset))
		else:
			var offset2 := turn * (Vector3(local_x, red * 0.03 - 1.3, -local_z) * terrain_scale)
			rocks.append(Transform3D(Basis(Vector3.UP, deg_to_rad(float(roll[7]))) * Basis.from_scale(Vector3.ONE * s), offset2))
	_multi(root, trunk, trunks)
	_multi(root, crown, crowns)
	_multi(root, rock, rocks)

func _multi(root: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

# The two wooden doors in a wall each: row 0 (door 0) and the top row (door 1).
func _place_walls() -> void:
	var wall_mesh: Mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/forest/wall.b3d"))
	var door_mesh: Mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/forest/door.b3d"))
	var frame_mesh: Mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/forest/door_frame.b3d"))
	for i in 2:
		var ty := (GRID - 1) * i
		for tx in range(1, GRID):
			if _at(grid, ty * GRID + tx) != 3:
				continue
			var wall := Node3D.new()
			wall.position = Vector3(tx * TILE, 0.0, -(ty * TILE + TILE * 0.5 - TILE * i))
			wall.rotation.y = deg_to_rad(180.0 * i)
			add_child(wall)
			var wall_visual := MeshInstance3D.new()
			wall_visual.mesh = wall_mesh
			wall_visual.scale = Vector3.ONE * RS
			wall.add_child(wall_visual)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var shape := CollisionShape3D.new()
			shape.shape = (wall_mesh as ArrayMesh).create_trimesh_shape()
			shape.scale = Vector3.ONE * RS
			body.add_child(shape)
			wall.add_child(body)
			var door := Node3D.new()
			door.position = Vector3(72.0 * RS, 32.0 * RS, 0.0)
			door.rotation.y = PI
			var door_visual := MeshInstance3D.new()
			door_visual.mesh = door_mesh
			door_visual.scale = Vector3(48.0, 45.0, 48.0) * RS
			door.add_child(door_visual)
			wall.add_child(door)
			var frame := MeshInstance3D.new()
			frame.mesh = frame_mesh
			frame.position = Vector3(0.0, 32.0 * RS, 0.0)
			frame.scale = Vector3(48.0, 45.0, 48.0) * RS
			wall.add_child(frame)
			doors[i] = door
			walls[i] = wall

# The forest is hidden (HideEntity, which also takes it out of collisions) except while the player is in it (UpdateEvents.bb 6557, 6604).
var _solid := true
var _bodies: Array[StaticBody3D] = []

func set_shown(on: bool) -> void:
	visible = on
	if on == _solid:
		return
	_solid = on
	if _bodies.is_empty():
		_bodies.assign(find_children("*", "StaticBody3D", true, false))
	FacilityRoom.set_solid(_bodies, on)

# UpdateForest: only the tiles within 20 m of the player (in x and z) are shown, and only while the player is within 12 m of
# the forest's height.
func update_visible(player_position: Vector3) -> void:
	if absf(player_position.y - global_position.y) >= 12.0:
		return
	for key in tiles:
		var root: Node3D = tiles[key]
		root.visible = absf(player_position.x - root.global_position.x) < 20.0 and absf(player_position.z - root.global_position.z) < 20.0

# TFormPoint(world -> forest) in Blitz coordinates: x right, z forward as the original had it (Godot z negated).
func blitz_local(world: Vector3) -> Vector3:
	var local := to_local(world)
	return Vector3(local.x, local.y, -local.z)

func blitz_world(blitz: Vector3) -> Vector3:
	return to_global(Vector3(blitz.x, blitz.y, -blitz.z))

# The grid cell holding the point (Floor((x + 6) / 12)).
func cell_of(world: Vector3) -> Vector2i:
	var l := blitz_local(world)
	return Vector2i(int(floor((l.x + 6.0) / TILE)), int(floor((l.z + 6.0) / TILE)))

static var _shapes: Dictionary = {}

# The ground of a tile as a collision shape, already scaled to 12 m (a body's own scale is not used by physics).
func _scaled_shape(mesh: ArrayMesh, kind: int) -> ConcavePolygonShape3D:
	if not _shapes.has(kind):
		var faces := mesh.get_faces()
		var scaled := PackedVector3Array()
		scaled.resize(faces.size())
		for i in faces.size():
			scaled[i] = faces[i] * terrain_scale
		var made := ConcavePolygonShape3D.new()
		made.set_faces(scaled)
		made.backface_collision = true
		_shapes[kind] = made
	return _shapes[kind]
