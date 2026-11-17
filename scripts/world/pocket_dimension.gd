extends Node3D
# SCP-106's pocket dimension (MapSystem.bb FillRoom "pocketdimension", UpdateEvents.bb event
# "pocketdimension"). The original places it as a room of the map; here it is one node built far
# from the facility the first time 106 takes the player. Blitz coordinates are written as in the
# source and turned into Godot ones by B() (z flips). Collider heights become feet heights (-0.3).
#
# event_state  frames spent inside; drives the squirming of the tunnels
# state2       0 = the starting room, 1 = the throne room and what lies below it,
#              12-15 = the pillar room (106 hops between the pillars while it counts down)
# state3       1 = the "trick room" above the throne room, 2 = after its door was opened
# event_str    how long the player has looked 106 in the eyes (1000 = that has happened)

const DoorScript = preload("res://scripts/world/facility_door.gd")

const RS := MeshLoader.ROOM_SCALE
const NOTE_ID := "pocket|burnt_note"
const COLLIDER_CENTRE := 0.3
const PILLAR_KILL_RADIUS := 100.0 * RS

var player_inside := false
var event_state := 0.0
var event_state2 := 0
var event_state3 := 0
var event_str := 0.0

var _room_visual: MeshInstance3D
var _hallways: Array[MeshInstance3D] = []
var _throne: Node3D
var _pillars: Array[Node3D] = []        # Objects[9], Objects[10]
var _pillar_visuals: Array[MeshInstance3D] = []
var _pillar_room: Node3D
var _pillar_spots: Array[Vector3] = []  # Objects[12..16]
var _terrain: Node3D
var _doors: Array[Node3D] = []
var _eyes: MeshInstance3D
var _plane: MeshInstance3D
var _plane_textures: Array[Texture2D] = []
var _rumble: Array[AudioStreamPlayer3D] = []
var _voices: AudioStreamPlayer3D
var _plane_voices: AudioStreamPlayer
var _screech: AudioStreamPlayer
var _kneel_layer: CanvasLayer
var _kneel_image: TextureRect
var _plane_rumble: AudioStreamPlayer3D
var _saved_background := Color.BLACK
var _solid := true
var _bodies: Array[StaticBody3D] = []
var steps_played := 0
var _face_layer: CanvasLayer
var _face: TextureRect

# Blitz offset from the room origin (x, y, z) to a world point.
func B(x: float, y: float, z: float) -> Vector3:
	return position + Vector3(x, y, -z)

func _throne_origin() -> Vector3:
	return B(0.0, 0.0, 32.0)

func contains(pos: Vector3) -> bool:
	return absf(pos.x - position.x) < 70.0 and pos.z < position.z + 40.0 and pos.z > position.z - 110.0 and pos.y > -30.0 and pos.y < 40.0

# Built once, with the map (RoomRegistry.build_all).
func build() -> void:
	name = "PocketDimension"
	position = Vector3(0.0, 0.0, 400.0)
	var loaded := MeshLoader.load_rmesh_cached(ContentPaths.existing_file("GFX/map/pocketdimension1_opt.rmesh"))
	_room_visual = MeshInstance3D.new()
	_room_visual.mesh = loaded.visual
	add_child(_room_visual)
	for surface in _room_visual.mesh.get_surface_count():
		var material := _room_visual.mesh.surface_get_material(surface)
		if material is ShaderMaterial:
			material.set_shader_parameter("light_energy", GameState.light_energy)
	add_child(MeshLoader.make_static_body_shared(loaded))
	# the eight tunnels of the starting room (Objects[0..7]) around a ring of radius 512
	var tunnel_floors := PackedVector3Array()
	for i in 8:
		var angle := float(i) * 45.0
		var hall := _b3d("GFX/map/pocketdimension2.b3d", true)
		hall.position = B(cos(deg_to_rad(angle)) * 512.0 * RS, 0.0, sin(deg_to_rad(angle)) * 512.0 * RS) - position
		hall.rotation.y = deg_to_rad(angle - 90.0)
		var hall_visual: MeshInstance3D = hall.get_meta("visual")
		_hallways.append(hall_visual)
		var faces: PackedVector3Array = hall.transform * hall_visual.transform * hall_visual.mesh.get_faces()
		for t in range(0, faces.size(), 3):
			if absf((faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).normalized().y) > 0.99:     # level faces: only floors can lie on the plate
				tunnel_floors.append_array([faces[t], faces[t + 1], faces[t + 2]])
		if i < 5:
			_decal("GFX/decalpd%d.jpg" % (i + 1), Vector3(cos(deg_to_rad(angle)) * 512.0 * RS * 3.0, 0.02, sin(deg_to_rad(angle)) * 512.0 * RS * 3.0), angle - 90.0, 0.5)
	# The room has a 4 x 4 m plate 0.125 under its floor, at the height of the tunnels' floors: the diagonal tunnels' mouths
	# lie over its corners, and the room and each tunnel stretch upright at their own rate, so the two floors kept crossing
	# and fought. The plate is trimmed where a tunnel covers it (the tunnels only ever get wider).
	_room_visual.mesh = CoplanarTrim.apply(loaded.visual, RS, tunnel_floors)
	# the throne room (Objects[8]), the two flying pillars (9, 10), the pillar room (11), the trenches
	_throne = _b3d("GFX/map/pocketdimension3.b3d", true)
	_throne.position = B(0.0, 0.0, 32.0) - position
	# both are HIT_MAP (MapSystem.bb 4903-4905): the player bumps into them
	for i in 2:
		var pillar := _b3d("GFX/map/pocketdimension4.b3d", true, true, Vector3(1.5, 2.0, 1.5) if i == 1 else Vector3.ONE)
		_pillars.append(pillar)
		_pillar_visuals.append(pillar.get_meta("visual"))
	_pillar_room = _b3d("GFX/map/pocketdimension5.b3d", true)
	_pillar_room.position = B(0.0, 0.0, 64.0) - position
	_terrain = _b3d("GFX/map/pocketdimensionterrain.b3d", true, false)
	_terrain.position = B(0.0, 2944.0 * RS, 32.0) - position
	# Objects[12..16]: where 106 stands in the pillar room, and the way out at the bottom
	for spot in [Vector3(0, 200, 0), Vector3(390, 200, 272), Vector3(838, 200, -551), Vector3(-139, 200, 1201), Vector3(-1238, -1664, 381)]:
		_pillar_spots.append(B(spot.x * RS, spot.y * RS, 64.0 + spot.z * RS))
	# the doors of the trick room (RoomDoors[0], [1])
	for door_def in [[B(0.0, 2048.0 * RS, 32.0 - 1024.0 * RS), 0.0], [B(0.0, 2048.0 * RS, 32.0 + 1024.0 * RS), 180.0]]:
		var door := Node3D.new()
		door.set_script(DoorScript)
		add_child(door)
		door.setup(door_def[0], door_def[1], false, false)
		_doors.append(door)
	_decal("GFX/decalpd6.dc", Vector3(-1536.0 * RS, 0.02, 608.0 * RS + 32.0), 90.0, 0.8)
	if not GameState.taken_items.has(NOTE_ID):
		var note := RoomFill.make_pickup("Burnt Note", "paper")
		note.set_meta("fill_id", NOTE_ID)    # built with the map, so a save must not also keep it as a dropped item
		add_child(note)
		note.position = B(0.0, 0.5, 3.5) - position
	_build_sprites()
	_build_sounds()

# A b3d model scaled like the original (RoomScale) with a trimesh collider baked at world scale. Faces that lie on an earlier
# face of the model are trimmed (CoplanarTrim): the tunnel's floor slab fought the tunnel walls and flashed.
# `trim` false: the terrain has no faces drawn twice, and its 5193 triangles in one plane made the trim take 35 s of the load.
# Returns the holder node; its visual (the part that squirms) is in meta "visual".
func _b3d(relative: String, collide: bool, trim: bool = true, size := Vector3.ONE) -> Node3D:
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file(relative))
	if trim:
		mesh = CoplanarTrim.apply(mesh)
	var holder := Node3D.new()
	add_child(holder)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = size * RS
	holder.add_child(visual)
	holder.set_meta("visual", visual)
	if collide and mesh != null and mesh.get_surface_count() > 0:
		var faces := Transform3D(Basis.from_scale(size * RS), Vector3.ZERO) * mesh.get_faces()
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		holder.add_child(body)
	return holder

func _texture(relative: String) -> Texture2D:
	var path := ContentPaths.existing_file(relative)
	if path.get_extension() == "dc":
		# a renamed picture; read it by content
		var image := MeshLoader.load_image(path)
		if image == null:
			return null
		return MeshLoader._mipped_texture(image)
	return MeshLoader._load_texture(path)

# CreateDecal with blendmode 2 (multiply) and fullbright: a picture on the floor.
func _decal(relative: String, local_blitz: Vector3, yaw: float, size: float) -> void:
	var texture := _texture(relative)
	if texture == null:
		return
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size * 2.0
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.albedo_texture = texture
	material.disable_fog = true
	quad.material_override = material
	add_child(quad)
	quad.position = Vector3(local_blitz.x, local_blitz.y, -local_blitz.z)
	quad.rotation = Vector3(-PI * 0.5, deg_to_rad(yaw), 0.0)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_sprites() -> void:
	# 106's eyes: a small additive picture that always faces the player
	_eyes = MeshInstance3D.new()
	var eye_mesh := QuadMesh.new()
	eye_mesh.size = Vector2.ONE * 0.06
	_eyes.mesh = eye_mesh
	_eyes.material_override = GammaBlend.make(_texture("GFX/npcs/oldmaneyes.jpg"), Color.WHITE, true, true, false)
	_eyes.visible = false
	add_child(_eyes)
	# the plane that hunts the player in the trenches: a big picture overhead
	for file in ["GFX/npcs/pdplane.png", "GFX/npcs/pdplaneeye.png"]:
		_plane_textures.append(_texture(file))
	_plane = MeshInstance3D.new()
	var plane_mesh := QuadMesh.new()
	plane_mesh.size = Vector2.ONE * 16.0
	_plane.mesh = plane_mesh
	var plane_material := GammaBlend.make(_plane_textures[0], Color.WHITE, false, false, false, true)
	plane_material.set_shader_parameter("multiply", true)
	plane_material.render_priority = 100
	_plane.material_override = plane_material
	_plane.visible = false
	add_child(_plane)

func _loop(relative: String, max_distance: float, parent: Node3D, volume: float = 1.0) -> AudioStreamPlayer3D:
	var source := Sfx.stream(relative)
	var audio := AudioStreamPlayer3D.new()
	if source != null:
		source = source.duplicate()
		source.loop = true
		audio.stream = source
	audio.max_distance = max_distance
	audio.volume_db = linear_to_db(maxf(volume, 0.0001))
	parent.add_child(audio)
	return audio

func _build_sounds() -> void:
	for pillar in _pillars:
		_rumble.append(_loop("SFX/Room/PocketDimension/Rumble.ogg", 6.0, pillar))
	var spot := Node3D.new()
	add_child(spot)
	spot.position = B(-1536.0 * RS, 500.0 * RS, 32.0 + 608.0 * RS) - position
	_voices = _loop("SFX/Room/PocketDimension/PrisonVoices.ogg", 3.0, spot)
	_plane_rumble = _loop("SFX/Room/PocketDimension/Rumble.ogg", 8.0, _plane)

# The dimension shows itself only while the player is in it (UpdateEvents.bb 1970, 2513); HideEntity takes its walls out of collisions too.
func set_shown(on: bool) -> void:
	visible = on
	if on == _solid:
		return
	_solid = on
	if _bodies.is_empty():
		for body: StaticBody3D in find_children("*", "StaticBody3D", true, false):
			if not body.is_in_group("pickup") and not _in_door(body):
				_bodies.append(body)
	FacilityRoom.set_solid(_bodies, on)
	if on:
		# an item that looked for the floor while the dimension had no collision (the note, made with the map) settled in the air
		for item in get_children():
			if item is WorldItem:
				item.wake()

func _in_door(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent.is_in_group("door"):
			return true
		parent = parent.get_parent()
	return false

# MoveToPocketDimension: the player appears in the middle of the starting room.
func enter(player: CharacterBody3D) -> void:
	if not player_inside:
		var env := _environment()
		if env != null:
			_saved_background = env.background_color
	player_inside = true
	set_shown(true)
	player.fall_timer = 0.0
	player.camera.position.y = 0.9
	_put(player, B(0.0, 0.8 - COLLIDER_CENTRE, 0.0))
	player.blink_timer = -10.0
	GameState.injuries += 0.5
	Sfx.play_global(self, "SFX/Room/PocketDimension/Enter.ogg")
	_fog(Color.BLACK)

func _put(player: CharacterBody3D, feet: Vector3) -> void:
	player.global_position = feet
	player.velocity = Vector3.ZERO

# Standing at collider height cy (Blitz) at Blitz x/z of the throne room or the room centre.
func _put_collider(player: CharacterBody3D, x: float, collider_y: float, z: float) -> void:
	_put(player, B(x, collider_y - COLLIDER_CENTRE, z))

func _collider_y(player: Node3D) -> float:
	return player.global_position.y + COLLIDER_CENTRE

# MouseLook: outside the throne room's height band the camera rolls Sin(MilliSecs2() / 150) * 30 degrees.
func camera_roll() -> float:
	if not player_inside or GameState.player == null:
		return 0.0
	var y_collider := _collider_y(GameState.player)
	if y_collider < 2000.0 * RS or y_collider > 2608.0 * RS:
		return sin(deg_to_rad(GameState.clock_ms() / 150.0)) * 30.0
	return 0.0

func _environment() -> Environment:
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	return holder.environment if holder != null else null

# CameraFogColor / CameraClsColor: black, or green in the trenches. Fog runs 0.5 to 6.
func _fog(color: Color) -> void:
	var env := _environment()
	if env == null:
		return
	env.background_color = color
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = color
	env.fog_depth_begin = 0.5
	env.fog_depth_end = 6.0
	env.fog_depth_curve = 1.0
	# the rooms' own shader fogs itself (lightmap.gdshader): the dimension's rmesh needs the same range and colour
	RenderingServer.global_shader_parameter_set(&"room_fog_range", Vector2(0.5, 6.0))
	RenderingServer.global_shader_parameter_set(&"room_fog_color", Vector3(color.r, color.g, color.b))

func _unfog() -> void:
	var env := _environment()
	if env == null:
		return
	env.background_color = _saved_background
	env.fog_enabled = false
	RenderingServer.global_shader_parameter_set(&"room_fog_range", Vector2(100000.0, 200000.0))
	RenderingServer.global_shader_parameter_set(&"room_fog_color", Vector3.ZERO)

# Out through the exit rooms: back to a room of the facility.
func _exit_to(kinds: Array, player: CharacterBody3D, sound: bool = false) -> void:
	var facility := get_parent()
	var target: Vector3 = facility.pocket_exit(kinds)
	GameState.give_achievement("pd")
	event_state = 0.0
	event_state2 = 0
	event_state3 = 0
	event_str = 0.0
	player_inside = false
	set_shown(false)
	_unfog()
	GameState.music_override = ""
	GameState.blur_timer = 1500.0
	player.blink_timer = -10.0
	_put(player, target)
	for rumble in _rumble:
		rumble.stop()
	_voices.stop()
	_plane_rumble.stop()
	_stop_kneel_blink()
	if sound:
		Sfx.play_global(self, "SFX/Room/PocketDimension/Exit.ogg")
	var old_man: Node = facility.scp106
	if old_man != null and is_instance_valid(old_man):
		old_man.idle = false
		old_man.state = 10000.0 if "room106" in kinds or "room2shaft" in kinds else 250.0
		old_man.global_position = Vector3(target.x, target.y - 30.0, target.z)
	facility.after_pocket_exit()

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if not player_inside or player == null or player.dead:
		_hide_face()
		return
	var fps := delta * 70.0
	_blink_face(player)
	var facility := get_parent()
	var old_man: Node = facility.scp106 if facility.scp106 != null and is_instance_valid(facility.scp106) else null
	GameState.injuries += fps * 0.00005
	var y_collider := _collider_y(player)
	if y_collider < 2000.0 * RS or event_state3 == 0 or y_collider > 2608.0 * RS:
		GameState.music_override = "PD"
	else:
		GameState.music_override = ""
	if y_collider < 2000.0 * RS or y_collider > 2608.0 * RS:
		GameState.mark_pd_step()
	_squirm()
	event_state += fps
	if event_state2 == 0:
		_start_room(fps, player, old_man)
	if old_man != null and old_man.global_position.distance_to(player.global_position) < 0.3:
		old_man.idle = false
		old_man.state = -10.0   # 106 attacks if close enough to the player
	if event_state2 == 1:
		_throne_room(fps, player, old_man)
	elif event_state2 == 0:
		_wander_away(player)
	else:
		_pillar_room_step(fps, player, old_man)
	_kneel_blink(player)

# DrawGUI (Main.bb 4651-4676): once 106's eyes have been met, each blink flashes kneelmortal.pd with a jitter and plays the screech, which loops while the eyes stay shut.
func _kneel_blink(player: CharacterBody3D) -> void:
	if _screech == null:
		_screech = AudioStreamPlayer.new()
		_screech.stream = Sfx.stream("SFX/Room/PocketDimension/Screech.ogg")
		add_child(_screech)
		_kneel_layer = CanvasLayer.new()
		_kneel_layer.layer = 5
		_kneel_image = TextureRect.new()
		_kneel_image.texture = _texture("GFX/kneelmortal.pd")
		_kneel_image.stretch_mode = TextureRect.STRETCH_KEEP
		_kneel_image.visible = false
		_kneel_layer.add_child(_kneel_image)
		add_child(_kneel_layer)
	var blinking: bool = player.blink_timer < -3.0 and player.blink_timer > -10.0
	if event_str < 1000.0:
		_kneel_image.visible = false
		return
	if blinking:
		if not _kneel_image.visible:
			if player.blink_timer > -5.0:
				_kneel_image.visible = true
				_screech.play()
		else:
			var half := get_viewport().get_visible_rect().size * 0.5
			var s := UIKit.pixel_scale(_kneel_image)
			_kneel_image.scale = Vector2(s, s)
			_kneel_image.position = half - Vector2(randi_range(310, 390), randi_range(290, 310)) * s
	else:
		_kneel_image.visible = false
		if player.blink_timer < -3.0:
			if not _screech.playing:
				_screech.play()
		elif _screech.playing:
			_screech.stop()

func _stop_kneel_blink() -> void:
	if _screech != null:
		_screech.stop()
		_kneel_image.visible = false

# Main.bb DrawGUI 4629-4650: 106's face flashes on screen during a blink once the event has run
# 600 frames. It is drawn at a jittering offset from the screen centre until the blink ends.
func _blink_face(player: CharacterBody3D) -> void:
	var blinking: bool = event_str < 1000.0 and event_state > 600.0 and player.blink_timer < -3.0 and player.blink_timer > -10.0
	if not blinking:
		_hide_face()
		return
	if _face == null or not _face.visible:
		if player.blink_timer > -5.0 and randi_range(1, 30) == 1:
			Sfx.play_global(self, "SFX/Character/D9341/BloodDrip0.ogg")
			_show_face()
		return
	var size := get_viewport().get_visible_rect().size
	var s := UIKit.pixel_scale(_face)
	_face.scale = Vector2(s, s)
	_face.position = size * 0.5 - Vector2(randi_range(310, 390), randi_range(290, 310)) * s

func _show_face() -> void:
	if _face == null:
		_face_layer = CanvasLayer.new()
		_face_layer.layer = 50
		add_child(_face_layer)
		_face = TextureRect.new()
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.texture = _texture("GFX/npcs/106face.jpg")
		_face_layer.add_child(_face)
		_face.size = _face.texture.get_size() if _face.texture != null else Vector2.ZERO
	_face.visible = true

func _hide_face() -> void:
	if _face != null:
		_face.visible = false

# ScaleEntity every frame: the tunnels and the room breathe.
func _squirm() -> void:
	_room_visual.scale.y = 1.0 + sin(deg_to_rad(event_state / 14.0)) * 0.2
	for i in 8:
		_hallways[i].scale = Vector3(
			RS * (1.0 + absf(sin(deg_to_rad(event_state / 21.0 + i * 45.0)) * 0.1)),
			RS * (1.0 + sin(deg_to_rad(event_state / 14.0 + i * 20.0)) * 0.1),
			RS)
	_pillar_visuals[0].scale = Vector3(
		RS * (1.5 + absf(sin(deg_to_rad(event_state / 21.0 + 8.0 * 45.0)) * 0.1)),
		RS * (1.0 + sin(deg_to_rad(event_state / 14.0 + 8.0 * 20.0)) * 0.1),
		RS)

func _start_room(fps: float, player: CharacterBody3D, old_man: Node) -> void:
	_doors[0].open = false
	_doors[1].open = false
	if old_man == null or old_man.state <= 0.0:
		return
	# 106 circles around the starting room
	var angle := fmod(event_state / 10.0, 360.0)
	var radius := 6.0 - sin(deg_to_rad(event_state / 10.0))
	var height := 0.2 + 0.35 + sin(deg_to_rad(event_state / 14.0 + 8.0 * 20.0)) * 0.4
	old_man.idle = true
	old_man.visible = true
	old_man.global_position = position + Vector3(-sin(deg_to_rad(angle)) * radius, height - 0.15, -cos(deg_to_rad(angle)) * radius)
	old_man.rotation.y = deg_to_rad(angle + 90.0)
	old_man.animate(55.0, 104.0, 0.5, fps)
	old_man.prev_y = old_man.global_position.y
	if event_state > 65.0 * 70.0 and randi() % int(maxf(800.0 / fps, 1.0)) == 0:
		Sfx.play_global(self, "SFX/Horror/Horror8.ogg")
		old_man.state = -0.1
		old_man.idle = false
		event_state = 601.0

# Further than 1700 from the middle of the starting room, the walls spit the player somewhere.
func _wander_away(player: CharacterBody3D) -> void:
	var from_centre := Vector3(player.global_position.x - position.x, 0.0, player.global_position.z - position.z)
	var dist := from_centre.length()
	if dist <= 1700.0 * RS:
		return
	player.blink_timer = -10.0
	var roll := randi_range(1, 25)
	if roll <= 4:
		Sfx.play_global(self, "SFX/SCP/106/Laugh.ogg")
		# through the middle to the far side (MoveEntity dist * 1.9 toward the centre)
		var toward := -from_centre.normalized()
		var landing := player.global_position + toward * dist * 1.9
		_put(player, Vector3(landing.x, player.global_position.y, landing.z))
		var ahead := landing + toward * 0.8
		_pillars[1].position = Vector3(ahead.x, 0.0, ahead.z) - position
		_pillars[1].rotation.y = atan2(-toward.x, -toward.z)
	elif roll <= 10:
		event_state2 = 1
		Sfx.play_global(self, "SFX/SCP/106/Laugh.ogg")
		_put_collider(player, 0.0, 0.5, 32.0)
	elif roll <= 12:
		GameState.blur_timer = 500.0
		_put_collider(player, 0.0, 0.5, 0.0)
	elif roll <= 15:
		GameState.blur_timer = 1500.0
		event_state2 = 1
		_put_collider(player, -400.0 * RS, -304.0 * RS, 32.0)
	elif roll <= 19:
		GameState.blur_timer = 1500.0
		_exit_to(["tunnel", "tunnel2"], player)
	elif roll <= 22:
		event_state2 = 15
		_put(player, Vector3(_pillar_spots[0].x, 0.6 - COLLIDER_CENTRE, _pillar_spots[0].z))
	else:
		GameState.blur_timer = 1500.0
		event_state2 = 1
		event_state3 = 1
		Sfx.play_global(self, "SFX/SCP/106/Laugh.ogg")
		_put_collider(player, 0.0, 2288.0 * RS, 32.0)

# ---- state2 == 1: the throne room, the trenches and the way down -------------------------------

func _throne_room(fps: float, player: CharacterBody3D, old_man: Node) -> void:
	var centre := _throne_origin()
	var t := event_state
	_pillars[0].position = Vector3(centre.x + 3384.0 * RS + cos(deg_to_rad(t * 0.8)) * 5.0, 0.0, centre.z - sin(deg_to_rad(t * 1.6)) * 4.0) - position
	_pillars[0].rotation.y = deg_to_rad(t * 2.0)
	_pillars[1].position = Vector3(centre.x + sin(deg_to_rad(t * 1.6)) * 4.0, 0.0, centre.z - 3384.0 * RS - cos(deg_to_rad(t * 0.8)) * 5.0) - position
	_pillars[1].rotation.y = deg_to_rad(t * 2.0)
	var y_collider := _collider_y(player)
	if event_state3 == 1 or event_state3 == 2:
		# the "trick room"
		if event_state3 == 1 and (_doors[0].openstate > 150.0 or _doors[1].openstate > 150.0):
			Sfx.play_global(self, "SFX/Horror/Horror16.ogg")
			GameState.blur_timer = 800.0
			event_state3 = 2
		if y_collider < 5.0:
			event_state3 = 0
	elif y_collider > 6.0:
		_trenches(fps, player)
	else:
		event_state3 = 0
		_throne_hall(fps, player)
	# below -1600 the player is out of the dimension, or falling forever
	if _collider_y(player) < -1600.0 * RS:
		if player.global_position.distance_to(centre) > 4750.0 * RS:
			_exit_to(["room106", "room2shaft"], player)
			return
		if not player.dead:
			Sfx.play_global(self, "SFX/Horror/Horror8.ogg")
			player.kill("In addition to the decomposed appearance typical of the victims of SCP-106, the subject seems to have suffered multiple heavy fractures to both of his legs.")
			GameState.blur_timer = 3000.0

# The trenches: a plane flies over and the player is pulled toward the sinkhole.
func _trenches(fps: float, player: CharacterBody3D) -> void:
	var centre := _throne_origin()
	GameState.music_override = "PDTrench"
	var color := Color8(38, 55, 47)
	_fog(color)
	if not _plane.visible or _plane.global_position.x < centre.x - 4000.0 * RS:
		_plane.visible = true
		if _plane_voices == null:
			_plane_voices = AudioStreamPlayer.new()
			add_child(_plane_voices)
			var voices := Sfx.stream("SFX/Room/PocketDimension/TrenchPlane.ogg")
			if voices != null:
				voices = voices.duplicate()
				voices.loop = true
				_plane_voices.stream = voices
		if not _plane_voices.playing:
			_plane_voices.play()
		_plane.global_position = Vector3(player.global_position.x + 4000.0 * RS, 12.0, player.global_position.z)
	var cy := _collider_y(player)
	if cy > 12.0:
		# MoveEntity with the player's collisions: the trench floor rises above 12 in places and stops the pull there
		player.move_and_collide(Vector3(0.0, (12.0 - cy) * minf(fps, 1.0), 0.0))
	_plane.global_position.x -= fps * RS * 4.0
	_plane.global_position.y = 17.0 - absf(player.global_position.x - _plane.global_position.x) * 0.5
	_plane.global_position.z = player.global_position.z
	var offset_x := player.global_position.x - _plane.global_position.x
	_plane.rotation = Vector3(PI * 0.5, 0.0, deg_to_rad(offset_x * 1.5))
	# is the player under one of the three safe spots (where the plane cannot see)?
	var safe := false
	for spot in [Vector2(-1452.0, -37.0), Vector2(-121.0, 188.0), Vector2(1223.0, -196.0)]:
		var world := B(spot.x * RS, 0.0, 32.0 + spot.y * RS)
		if Vector2(player.global_position.x - world.x, player.global_position.z - world.z).length() < 200.0 * RS:
			safe = true
			break
	var dist := player.global_position.distance_to(_plane.global_position)
	(_plane.material_override as ShaderMaterial).set_shader_parameter("tex", _plane_textures[0 if safe else (1 if dist < 8.0 else 0)])
	if _plane_voices.playing:
		_plane_voices.volume_db = linear_to_db(0.3 + (0.0 if safe else 0.6))
	if not safe and dist < 8.0:
		if not _plane_rumble.playing:
			_plane_rumble.play()
		GameState.injuries += (8.0 - dist) * fps * 0.0003
		if dist < 7.0:
			var to_plane: Vector3 = _plane.global_position - player.camera.global_position
			var flat := Vector2(to_plane.x, to_plane.z).length()
			var wanted_pitch := clampf(-rad_to_deg(atan2(to_plane.y, flat)), -70.0, 70.0)
			player.user_pitch = lerpf(player.user_pitch, wanted_pitch, minf(fps / 10.0, 1.0))
			player.camera.rotation.x = -deg_to_rad(player.user_pitch)
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-to_plane.x, -to_plane.z), minf(fps / 10.0, 1.0))
	else:
		_plane_rumble.stop()
	player.camera_shake = maxf(4.0 + (0.0 if safe else 4.0) - dist, 0.0)
	# the sinkhole
	if _collider_y(player) < 8.5:
		_plane.visible = false
		_plane_voices.stop()
		_plane_rumble.stop()
		GameState.blur_timer = 1500.0
		event_state2 = 1
		player.blink_timer = -10.0
		_put_collider(player, -400.0 * RS, -304.0 * RS, 32.0)
		_fog(Color.BLACK)

# The throne room proper: the pillars crush, 106's eyes watch, and a pit leads to the exit room.
func _throne_hall(fps: float, player: CharacterBody3D) -> void:
	var centre := _throne_origin()
	if _plane.visible:
		_plane.visible = false
	for i in 2:
		var pillar := _pillars[i]
		var to_player := Vector2(player.global_position.x - pillar.global_position.x, player.global_position.z - pillar.global_position.z)
		var dist := to_player.length()
		if dist < PILLAR_KILL_RADIUS:
			# pushed out along the nearest axis; whoever stood there is crushed
			var axis := roundf(atan2(to_player.y, to_player.x) / (PI * 0.5)) * (PI * 0.5)
			player.global_position.x = pillar.global_position.x + cos(axis) * 100.0 * RS
			player.global_position.z = pillar.global_position.z + sin(axis) * 100.0 * RS
			if not player.dead:
				Sfx.play_global(self, "SFX/Room/PocketDimension/Impact.ogg")
				player.kill("In addition to the decomposed appearance typical of SCP-106's victims, the body exhibits injuries that have not been observed before: massive skull fracture, three broken ribs, fractured shoulder and multiple heavy lacerations.")
				return
		var audible := dist < 6.0 and event_str < 1000.0
		if audible and not _rumble[i].playing:
			_rumble[i].play()
		elif not audible and _rumble[i].playing:
			_rumble[i].stop()
	var voices_spot := B(-1536.0 * RS, 500.0 * RS, 32.0 + 608.0 * RS)
	if player.camera.global_position.distance_to(voices_spot) < 5.0:
		if not _voices.playing:
			_voices.play()
	elif _voices.playing:
		_voices.stop()
	_eyes.visible = true
	_eyes.global_position = B(0.0, 1376.0 * RS, 32.0 - 2848.0 * RS)
	var eye_dist: float = player.camera.global_position.distance_to(_eyes.global_position)
	if eye_dist < 2000.0 * RS:
		GameState.injuries += fps / 4000.0
		event_str += fps / 1000.0
		if event_str > 1.0 and event_str < 1000.0:
			Sfx.play_global(self, "SFX/Room/PocketDimension/Kneel.ogg")
			event_str = 1000.0
		GameState.sanity = maxf(GameState.sanity - fps / eye_dist / 8.0, -1000.0)
		player.camera_zoom = maxf(player.camera_zoom, (sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * 15.0 * maxf((6.0 - eye_dist) / 6.0, 0.0))
		var smooth := minf(maxf(15000.0 / maxf(-GameState.sanity, 0.001), 15.0), 500.0)
		var to_eyes: Vector3 = _eyes.global_position - player.camera.global_position
		var flat := Vector2(to_eyes.x, to_eyes.z).length()
		player.user_pitch = lerpf(player.user_pitch, clampf(-rad_to_deg(atan2(to_eyes.y, flat)), -70.0, 70.0), minf(fps / smooth, 1.0))
		player.camera.rotation.x = -deg_to_rad(player.user_pitch)
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-to_eyes.x, -to_eyes.z), minf(fps / smooth, 1.0))
		if player.crouching:
			# crouching in front of 106 drops the player into the trenches
			player.blink_timer = -10.0
			_put_collider(player, -1344.0 * RS, 2944.0 * RS, 32.0 - 1184.0 * RS)
			player.crouching = false
			Sfx.play_global(self, "SFX/Room/PocketDimension/Explosion.ogg")
			_plane.global_position = Vector3(centre.x - 1000.0, 0.0, 0.0)
			event_str = 0.0
	elif _collider_y(player) < -180.0 * RS:
		# the exit room: a swirl in the floor at +1024 leads out
		var swirl := B(1024.0 * RS, 0.0, 32.0)
		var temp := Vector2(player.global_position.x - swirl.x, player.global_position.z - swirl.z).length()
		if temp < 640.0 * RS:
			GameState.blur_timer = (640.0 * RS - temp) * 3000.0
			player.curr_speed += (0.0 - player.curr_speed) * minf(fps / (temp * 10.0 + 0.001), 1.0)
			if temp < 130.0 * RS:
				Sfx.play_global(self, "SFX/Room/PocketDimension/Exit.ogg")
				_exit_to(["room2shaft", "room106"], player)
				GameState.light_blink = 5.0
				return

# ---- state2 >= 12: the pillar room ------------------------------------------------------------

# 1 frame in 800 a huge pale figure (hg.pt, multiplied, 4 across, lasting 2500 frames) appears 7.5 away at floor level, 150 to
# 210 degrees round from the player's yaw taken as a plain angle (so to the side, not behind), and drifts past them: pointed at the
# camera, turned 145 degrees about the vertical and tilted 10 to 20 degrees about x.
func _drift_figure(player: CharacterBody3D) -> void:
	if randi_range(1, 800) != 1:
		return
	var facility := get_parent() as FacilityMap
	var angle := player.rotation.y + deg_to_rad(randf_range(150.0, 210.0))
	var at := Vector3(player.global_position.x + cos(angle) * 7.5, position.y, player.global_position.z - sin(angle) * 7.5)
	var figure := facility.particles.create(at, Particles.HG_MULTIPLIED, 4.0, 0.0, 2500.0)
	if figure != null:
		var turned: Vector3 = Basis(Vector3.UP, deg_to_rad(145.0)) * (player.camera.global_position - at).normalized()
		figure.dir = Basis(Vector3.RIGHT, -deg_to_rad(randf_range(10.0, 20.0))) * turned
		figure.speed = 0.01

func _pillar_room_step(fps: float, player: CharacterBody3D, old_man: Node) -> void:
	_drift_figure(player)
	_fog(Color(38.0 * 0.5 / 255.0, 55.0 * 0.5 / 255.0, 47.0 * 0.5 / 255.0))
	if old_man != null:
		if event_state2 > 12:
			var spot := _pillar_spots[event_state2 - 12]
			old_man.idle = true
			old_man.visible = true
			var toward: Vector3 = player.camera.global_position - Vector3(spot.x, 0.27, spot.z)
			var yaw := atan2(-toward.x, -toward.z) + deg_to_rad(sin(deg_to_rad(GameState.clock_ms() / 20.0)) * 6.0)
			old_man.rotation.y = yaw
			old_man.global_position = Vector3(spot.x, 0.27 - 0.15, spot.z) + Vector3(sin(yaw), 0.0, cos(yaw)) * sin(deg_to_rad(GameState.clock_ms() / 15.0)) * 0.06
			old_man.prev_y = old_man.global_position.y
			if randi() % int(maxf(750.0 / fps, 1.0)) == 0:
				player.blink_timer = -10.0
				event_state2 -= 1
				Sfx.play_global(self, "SFX/Horror/Horror8.ogg")
			if event_state2 == 12:
				player.camera_shake = 1.0
				old_man.global_position = Vector3(_pillar_spots[0].x, -1.0, _pillar_spots[0].z)
				old_man.state = -10.0
		else:
			old_man.state = -10.0
			old_man.idle = false
	if _collider_y(player) < -1600.0 * RS:
		var exit_spot := _pillar_spots[4]
		if Vector2(exit_spot.x - player.global_position.x, exit_spot.z - player.global_position.z).length() < 144.0 * RS:
			_unfog()
			_fog(Color.BLACK)
			GameState.blur_timer = 500.0
			event_state2 = 0
			_put_collider(player, 0.0, 0.5, 0.0)
		elif not player.dead:
			Sfx.play_global(self, "SFX/Horror/Horror8.ogg")
			player.kill("In addition to the decomposed appearance typical of the victims of SCP-106, the subject seems to have suffered multiple heavy fractures to both of his legs.")
			GameState.blur_timer = 3000.0

func capture() -> Dictionary:
	return {"state": event_state, "state2": event_state2, "state3": event_state3, "str": event_str}

func restore(data: Dictionary, player: CharacterBody3D) -> void:
	player_inside = true
	set_shown(true)
	event_state = float(data.state)
	event_state2 = int(data.state2)
	event_state3 = int(data.state3)
	event_str = float(data.str)
	var env := _environment()
	if env != null:
		_saved_background = env.background_color
	_fog(Color.BLACK)
