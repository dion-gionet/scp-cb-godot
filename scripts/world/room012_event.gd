extends Node3D
# SCP-012's room (UpdateEvents.bb Case "room012", MapSystem.bb FillRoom "room012"). The way down is RoomDoors[0], locked: when the
# player comes within 2.5 of it while the remote door control is on (079's), 012 opens it itself (a horror sting, the lever). From then on:
#  - the music box 012Golgotha plays at the sheet, the board it hangs on sinks into the floor (EventState 0 to 90), a lever by the
#    door pulls itself down over 200 frames and a small light by it blinks (50 frames on, 50 off)
#  - without the ring of SCP-714, a very fine gas mask or a very fine hazmat suit, a player who can see the board is pulled to it: the
#    view turns toward it and tilts 25 degrees down, the heart races, the view smears and pinches; facing within 40 degrees makes the
#    player walk at it; within 0.6 of it EventState3 counts up to 86 s and the player (with his speech, Speech1-7) pushes nails into his
#    wrist (13 s), tears it open and writes on the sheet in blood (31 s, picture 1), ... (63 s, picture 2), (74 s, picture 3, crouching)
#    and bleeds to death at 85 s
#  - a player who cannot see the board but is down in the room near the door is turned toward the door and walks out
# EventState / EventState2 / EventState3 are kept by facility.ambient (they outlive the room). Positions are raw numbers in the room's
# scaled space (z flipped here).

const RS := 8.0 / 2048.0

const DEATH := "Subject D-9341 found in a pool of blood next to SCP-012. Subject seems to have ripped open his wrists and written three extra lines to the composition before dying of blood loss."

var room: FacilityRoom
var lever: Node3D
var board: Node3D           # Objects[2]: the mesh that sinks
var sheet: MeshInstance3D   # Objects[4]: the composition, written on in blood
var glow: MeshInstance3D    # Objects[3]
var _golgotha: AudioStreamPlayer3D
var _music: AudioStreamPlayer3D
var _pushing := false       # this event holds ForceMove

func build(room_node: FacilityRoom) -> void:
	room = room_node
	lever = Node3D.new()
	lever.set_script(Lever)
	add_child(lever)
	lever.setup(_raw(240.0, -512.0, -364.0), 180.0, 10.0, 0.04)
	lever.set_physics_process(false)         # nobody pulls it but 012
	board = Node3D.new()
	add_child(board)
	board.position = _raw(-360.0, -130.0, 456.0)
	var board_mesh := MeshInstance3D.new()
	board_mesh.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/room012_2.b3d"))
	board_mesh.scale = Vector3.ONE * RS
	board.add_child(board_mesh)
	sheet = MeshInstance3D.new()
	sheet.mesh = _with_normals(MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/room012_3.b3d")))
	sheet.scale = Vector3.ONE * RS
	board.add_child(sheet)
	_paint_sheet(0)
	glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	glow.mesh = quad
	glow.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/light2.jpg")), Color.WHITE, true, true)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.scale = Vector3.ONE * 0.015
	glow.visible = false
	add_child(glow)
	glow.position = _raw(-43.5, -574.0, -362.0)
	var smear := GrowingDecal.make(room, room.to_global(_raw(-784.0, 0.0, 640.0)), "GFX/decal4.png", 0.5, 0.0, 1.0, false)
	smear.global_position.y = room.global_position.y - 768.0 * RS + 0.01

func _exit_tree() -> void:
	_release_push()

func _raw(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * RS, y * RS, -z * RS)

# The b3d carries no normals; Blitz3D's loader computes them (Surface::updateNormals), so the sheet is lit like the board.
static func _with_normals(source: ArrayMesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for i in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(source, i)
		tool.generate_normals()
		tool.commit(result)
		result.surface_set_material(i, source.surface_get_material(i))
	return result

# EntityTexture(Objects[4], picture, 0, 1): the model's second picture (scp-012_diffuse, which the game never ships) is the
# composition; the stages of the writing replace it.
func _paint_sheet(stage: int) -> void:
	var texture := MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/scp-012_%d.jpg" % stage))
	var mesh: ArrayMesh = sheet.mesh
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if (material is StandardMaterial3D or material is EntityMaterial) and material.albedo_texture != null and material.albedo_texture.get_width() <= 4:
			var own = material.duplicate()
			own.albedo_texture = texture
			sheet.set_surface_override_material(i, own)
			return
		if material is ShaderMaterial:
			var held: Variant = (material as ShaderMaterial).get_shader_parameter("albedo_texture")
			if held is Texture2D and (held as Texture2D).get_width() <= 4:
				var own_shader: ShaderMaterial = material.duplicate()
				own_shader.set_shader_parameter("albedo_texture", texture)
				sheet.set_surface_override_material(i, own_shader)
				return

# CurveValue / CurveAngle
func _curve(target: float, current: float, smooth: float, fps: float) -> float:
	return current + (target - current) / maxf(smooth, 1.0) * fps

func _curve_angle(target: float, current: float, smooth: float, fps: float) -> float:
	return current + wrapf(target - current, -PI, PI) / maxf(smooth, 1.0) * fps

func _release_push() -> void:
	if _pushing:
		GameState.force_move = 0.0
		_pushing = false

func _clear_between(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _stop_voices() -> void:
	for voice in [_golgotha, _music]:
		if voice != null and is_instance_valid(voice):
			(voice as AudioStreamPlayer3D).stop()

func _start_voice(relative: String, range_m: float) -> AudioStreamPlayer3D:
	var stream := Sfx.stream(relative)
	if stream == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.max_distance = range_m
	add_child(voice)
	voice.global_position = glow.global_position
	voice.finished.connect(func() -> void: if is_instance_valid(voice): voice.play())
	voice.play()
	return voice

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active:
		return
	var fps := delta * 70.0
	var in_room: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if not in_room:
		_release_push()
		_stop_voices()
		return
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	var door: Node3D = room.door_slots.get(0)
	if st.s == 0.0:
		if door != null and player.global_position.distance_to(door.global_position) < 2.5 and facility.remote_door_on:
			GameState.give_achievement("012")
			Sfx.play_global(self, "SFX/Horror/Horror7.ogg")
			Sfx.play_at(door, "SFX/Interact/LeverFlip.ogg", 10.0)
			st.s = 1.0
			door.locked = false
			door.toggle(false)
			door.locked = true
		return
	if _golgotha == null or not is_instance_valid(_golgotha) or not _golgotha.playing:
		_golgotha = _start_voice("SFX/Music/012Golgotha.ogg", 5.0)
	if _music == null or not is_instance_valid(_music):
		_music = _start_voice("SFX/Music/012.ogg", 10.0)
		if _music != null:
			_music.volume_db = -80.0
	if st.s < 90.0:
		st.s = _curve(90.0, st.s, 500.0, fps)
	board.position.y = (-130.0 - 448.0 * sin(deg_to_rad(st.s))) * RS
	if st.s2 > 0.0 and st.s2 < 200.0:
		st.s2 += fps
		lever.pitch = _curve(85.0, lever.pitch, 5.0, fps)
		lever._handle.rotation.x = -deg_to_rad(lever.pitch)
	else:
		st.s2 += fps
		if st.s2 < 250.0:
			glow.visible = true
		else:
			glow.visible = false
			if st.s2 > 300.0:
				st.s2 = 200.0
	if not GameState.wearing_714 and GameState.wearing_gas_mask < 3 and GameState.wearing_hazmat < 3:
		if _clear_between(player.camera.global_position, board.global_position):
			_compel(player, st, fps)
		else:
			_walk_out(player, door, fps)
			if door == null:
				_release_push()
	else:
		_release_push()

# the view is taken, and the player drawn to the sheet
func _compel(player: CharacterBody3D, st: Dictionary, fps: float) -> void:
	var s := GameState
	var eye: Vector3 = player.camera.global_position
	var target := Vector3(board.global_position.x, board.global_position.y, board.global_position.z)
	if _music != null and is_instance_valid(_music):
		_music.volume_db = linear_to_db(maxf(st.s3 / (86.0 * 70.0), 0.0001))
	var smooth: float = 80.0 - st.s3 / 200.0
	var yaw_to := atan2(-(target.x - eye.x), -(target.z - eye.z))
	player.rotation.y = _curve_angle(yaw_to, player.rotation.y, smooth, fps)
	var eye_dist := Vector2(eye.x - target.x, eye.z - target.z).length()
	var pivot_pitch := -rad_to_deg(atan2(0.05, eye_dist))
	player.user_pitch = _curve(25.0 + pivot_pitch, player.user_pitch, smooth, fps)
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	var dist := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	var audio := get_tree().get_first_node_in_group("audio")
	if audio != null:
		audio.heartbeat(maxf(3.0 - dist, 0.0) / 3.0, 150.0)
		audio.stop_breath()
	var wave := sin(deg_to_rad(s.clock_ms() / 20.0 + 1.0))
	s.blur_volume = maxf(maxf((2.0 - dist) * (st.s3 / 800.0) * wave, 0.0), s.blur_volume)
	player.add_camera_zoom((sin(deg_to_rad(s.clock_ms() / 20.0)) + 1.0) * 8.0 * maxf(3.0 - dist, 0.0))
	if dist < 0.6:
		_release_push()
		var before: float = st.s3
		st.s3 = minf(st.s3 + fps, 86.0 * 70.0)
		_stage(player, before, st.s3)
		var wobble: float = sin(deg_to_rad(st.s3 * (st.s3 / 2000.0))) * (st.s3 / 300.0)
		player.rotation.y = _curve_angle(player.rotation.y + deg_to_rad(wobble), player.rotation.y, 80.0, fps)
	else:
		var angle := fposmod(rad_to_deg(yaw_to - player.rotation.y), 360.0)
		if angle < 40.0:
			s.force_move = (40.0 - angle) * 0.02
			_pushing = true
		elif angle > 310.0:
			s.force_move = (40.0 - absf(360.0 - angle)) * 0.02
			_pushing = true
		else:
			_release_push()

func _crossed(before: float, after: float, seconds: float) -> bool:
	return after > seconds * 70.0 and before <= seconds * 70.0

func _stage(player: CharacterBody3D, before: float, after: float) -> void:
	var s := GameState
	var hud := get_tree().get_first_node_in_group("hud")
	if _crossed(before, after, 1.0):
		Sfx.play_global(self, "SFX/SCP/012/Speech1.ogg")
	elif _crossed(before, after, 13.0):
		hud.message("You start pushing your nails into your wrist, drawing blood.", 7.0)
		s.injuries += 0.5
		Sfx.play_global(self, "SFX/SCP/012/Speech2.ogg")
	elif _crossed(before, after, 31.0):
		_paint_sheet(1)
		hud.message("You tear open your left wrist and start writing on the composition with your blood.", 7.0)
		s.injuries = maxf(s.injuries, 1.5)
		Sfx.play_global(self, "SFX/SCP/012/Speech%d.ogg" % randi_range(3, 4))
	elif _crossed(before, after, 49.0):
		hud.message("You push your fingers deeper into the wound.", 8.0)
		s.injuries += 0.3
		Sfx.play_global(self, "SFX/SCP/012/Speech5.ogg")
	elif _crossed(before, after, 63.0):
		_paint_sheet(2)
		s.injuries += 0.5
		Sfx.play_global(self, "SFX/SCP/012/Speech6.ogg")
	elif _crossed(before, after, 74.0):
		_paint_sheet(3)
		hud.message("You rip the wound wide open. Grabbing scoops of blood pouring out.", 7.0)
		s.injuries += 0.8
		Sfx.play_global(self, "SFX/SCP/012/Speech7.ogg")
		player.crouching = true
		var pool := GrowingDecal.make(get_parent(), Vector3(player.global_position.x, room.global_position.y - 768.0 * RS + 0.01, player.global_position.z), "GFX/decal8.png", 0.1, 0.0002, 0.8, false)
		pool.max_size = 0.45
	elif _crossed(before, after, 85.0):
		player.kill(DEATH)

# the board is out of sight: down in the room by the door, the player is turned to the door and walks out
func _walk_out(player: CharacterBody3D, door: Node3D, fps: float) -> void:
	if door == null:
		return
	var s := GameState
	var flat := Vector2(player.global_position.x - door.global_position.x, player.global_position.z - door.global_position.z).length()
	if flat < 4.5 and player.global_position.y < room.global_position.y - 2.5:
		var eye: Vector3 = player.camera.global_position
		var yaw_to := atan2(-(door.global_position.x - eye.x), -(door.global_position.z - eye.z))
		player.user_pitch = _curve(0.0, player.user_pitch, 100.0, fps)
		player.camera.rotation.x = -deg_to_rad(player.user_pitch)
		player.rotation.y = _curve_angle(yaw_to, player.rotation.y, 150.0, fps)
		var angle := fposmod(rad_to_deg(yaw_to - player.rotation.y), 360.0)
		if angle < 40.0:
			s.force_move = (40.0 - angle) * 0.008
			_pushing = true
		elif angle > 310.0:
			s.force_move = (40.0 - absf(360.0 - angle)) * 0.008
			_pushing = true
		else:
			_release_push()
	else:
		_release_push()
