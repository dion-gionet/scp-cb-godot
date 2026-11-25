extends CharacterBody3D
class_name Scp106
# SCP-106 (NPCs.bb UpdateNPCs, NPCtypeOldMan). He passes through walls and floors.
#  - state > 0: outside the map, sinking to 30 below the player's floor while the counter runs
#    down (22000-27000 frames; the first appearance is 12-17 minutes into the game)
#  - state <= 0: he comes up under the player (corrosion decal), rising for 149 / 0.15 frames of
#    animation, then hunts: straight at the player when far (> 25), in the pocket dimension, in view or without a route,
#    otherwise along waypoint routes; inside 0.8 he reaches for the player and pulls them down
#    (FallTimer); 250 frames later the player is taken to the pocket dimension
#  - while unseen the counter counts further down; at -3000..-3500 he leaves again when unseen
#  - more than 10 away and out of view, he can reappear 2 behind the player (every 10 s)
# Being taken moves the player into the pocket dimension (pocket_dimension.gd).


const SPEED := 1.2 / 100.0 * 70.0          # NPCs.ini speed 1.2 per frame at 70 fps
var speed := SPEED * GameState.npc_speed_factor()                      # the console's 106speed (per second)
const MODEL_SCALE := 0.25 / 2.2            # NPCs.ini scale / 2.2
const COLLIDER_RISE := 0.15                # the Blitz collider rides this far above the model (the node origin)
const DEATH_POCKET := "Subject D-9341. Body partially decomposed by what is assumed to be SCP-106's \"corrosion\" effect. Body disposed of via incineration."

var state := 0.0
var frame := 110.0
var curr_speed := 0.0
var path_timer := 0.0
var reload := 0.0
var grabs := 0
var steps_played := 0

var prev_y := 0.0
var idle := false          # Idle: the pocket dimension moves him itself
var _was_contained := false
var _visual: Node3D
var _eyes: MeshInstance3D
var _breath: AudioStreamPlayer3D
var _route: Array[Vector3] = []
var _route_index := 0
var _route_status := 0
var _last_seen_ms := -100000.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0          # he walks through everything
	add_to_group("scp106")
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/106_2.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	# the original turns the model with the collider (RotateEntity nobj, 0, EntityYaw(nCollider), 0: no half turn, unlike the guards
	# and 173); its face is Blitz +Z, which is the node's forward (-Z) once z is flipped
	add_child(_visual)
	_visual.set_frame(frame)
	_build_eyes()
	_breath = AudioStreamPlayer3D.new()
	_breath.max_distance = 8.0
	_breath.volume_db = linear_to_db(0.8)
	var stream := Sfx.stream("SFX/SCP/106/Breathing.ogg")
	if stream != null:
		stream = stream.duplicate()
		stream.loop = true
		_breath.stream = stream
	add_child(_breath)

func _build_eyes() -> void:
	var path := ContentPaths.existing_file("GFX/npcs/oldmaneyes.jpg")
	_eyes = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.06
	_eyes.mesh = quad
	var material := GammaBlend.make(_eye_texture(path), Color.WHITE, true, false, false)
	material.set_shader_parameter("single_sided", true)
	_eyes.material_override = material
	_eyes.position = Vector3(0.0, 8.6 * 0.11, -1.5 * 0.11)
	_eyes.rotation.y = PI      # SpriteViewMode 2 with RotateEntity(obj2, 0, yaw - 180, 0): seen from the front of his face only
	_eyes.visible = false
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eyes)

func _eye_texture(path: String) -> Texture2D:
	if path.get_extension() != "dc":
		return MeshLoader._load_texture(path)
	var image := MeshLoader.load_image(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

# NPCs.bb:1226-1244: the eyes glow once he is beyond the fog (CameraFogFar * LightVolume * 0.6)
func _update_eyes(dist: float, player: Node3D, facility: FacilityMap) -> void:
	var name: String = facility.room_name_at(player.global_position)
	var fog_far: float = (30.0 if GameState.wearing_night_vision != 0 else 6.0) * facility.light_fog.light_volume * 0.6
	if name == "pocketdimension" or name == "gatea" or dist < fog_far:
		_eyes.visible = false
		return
	var alpha := minf(dist - fog_far, 1.0)
	(_eyes.material_override as ShaderMaterial).set_shader_parameter("color", Color(alpha, alpha, alpha, alpha))
	_eyes.visible = true

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active or player.dead:
		return
	var fps := delta * 70.0
	if facility.contained_106:
		# Contained106: the femur breaker caught him; he is idle and out of sight until something lets him go
		idle = true
		_was_contained = true
		visible = false
		return
	if _was_contained:
		_was_contained = false
		idle = false
	var dist := global_position.distance_to(player.global_position)
	if idle:
		return     # the pocket dimension positions him (its event drives his animation)
	# SpawnAllowed: not in the 1499 dimension nor in 049's lower chamber (the other cases are not in the port)
	var may_spawn: bool = facility.can_106_spawn(player.global_position)
	if not may_spawn and state <= 0.0:
		state = randf_range(22000.0, 27000.0)
		global_position = Vector3(player.global_position.x, player.global_position.y - 30.0, player.global_position.z)
	if not may_spawn:
		visible = false
		return
	if state <= 0.0:
		visible = true
		_attack(fps, delta, dist, player)
		_update_eyes(dist, player, facility)
	else:
		visible = false
		_outside(fps, player)

func _outside(fps: float, player: Node3D) -> void:
	curr_speed = 0.0
	if _breath.playing:
		_breath.stop()
	global_position.y += ((player.global_position.y - 30.0) - global_position.y) / 200.0 * fps
	_set_frame(110.0)
	var facility := _facility()
	var room_name: String = facility.room_name_at(player.global_position)
	if room_name != "gatea" and not facility.generator.room_disables_decals(room_name):
		state -= fps * (2.0 if GameState.aggressive_npcs() else 1.0)

func _attack(fps: float, delta: float, dist: float, player: CharacterBody3D) -> void:
	if global_position.y < player.global_position.y - 20.0 - 0.55:
		# first frame: he surfaces under the player and leaves a stain
		var surface_room: String = _facility().room_name_at(player.global_position)
		if not _facility().generator.room_disables_decals(surface_room):
			_corrosion_decal(player.global_position)
		prev_y = player.global_position.y
		_set_frame(110.0)
		if surface_room != "coffin":
			global_position = Vector3(player.global_position.x, player.global_position.y - 15.0, player.global_position.z)
		Sfx.play_global(self, "SFX/SCP/106/Decay0.ogg")
	if randi() % int(maxf(500.0 / fps, 1.0)) == 0:
		Sfx.play_at(self, "SFX/SCP/106/Corrosion%d.ogg" % randi_range(1, 3), 10.0)
	if not _breath.playing and _breath.stream != null:
		_breath.play()
	if state > -10.0:
		GameState.request_npc_music("none")
		_rise(fps, player)
		return
	var player_room: String = _facility().room_name_at(player.global_position)
	var in_gate_a := player_room == "gatea"
	var in_pocket := player_room == "pocketdimension"
	if not in_gate_a:
		GameState.request_npc_music("106")
	var visible_now := false
	if dist < 8.0:
		visible_now = _line_to(player)
	if GameState.no_target:
		visible_now = false
	if visible_now:
		if player.camera.is_position_in_frustum(global_position + Vector3(0.0, 0.15, 0.0)):
			GameState.give_achievement("106")
			GameState.blur_volume = maxf(maxf(minf((4.0 - dist) / 6.0, 0.9), 0.1), GameState.blur_volume)
			var pinch: float = (sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * 20.0 * maxf((4.0 - dist) / 4.0, 0.0)
			player.camera_zoom = maxf(player.camera_zoom, pinch)
			if GameState.clock_ms() - _last_seen_ms > 60000:
				player.camera_zoom = 40.0
				Sfx.play_global(self, "SFX/Horror/Horror6.ogg")
				_last_seen_ms = GameState.clock_ms()
		if not in_gate_a:
			path_timer = 0.0
	else:
		state -= fps
	if dist > 0.8:
		if (dist > 25.0 or in_pocket or visible_now or _route_status != 1) and not in_gate_a:
			_direct_chase(fps, dist, player, in_pocket)
		else:
			_follow_route(fps, player)
	elif not in_gate_a and not GameState.no_target:
		_grab(fps, dist, player, in_pocket)
	global_position += -global_transform.basis.z * curr_speed * delta
	if state <= randf_range(-3500.0, -3000.0) and not in_view(player.camera) and dist > 5.0:
		state = randf_range(22000.0, 27000.0)   # he goes back where he came from
		global_position = Vector3(player.global_position.x, player.global_position.y - 30.0, player.global_position.z)
	if player.fall_timer < -250.0:
		_take_player(player)
	reload = maxf(reload - fps, 0.0)
	if reload == 0.0 and dist > 10.0 and state < -5.0 and not in_pocket and not in_gate_a and not in_view(player.camera):
		_reappear_behind(player)

# Frames 110..259 at 0.15: he climbs out of the floor, turning slowly to face the player.
func _rise(fps: float, player: Node3D) -> void:
	if frame < 259.0:
		global_position.y = prev_y
		var wanted := atan2(-(player.global_position.x - global_position.x), -(player.global_position.z - global_position.z))
		rotation.y = lerp_angle(rotation.y, wanted, minf(fps / 100.0, 1.0))
		_animate(110.0, 259.0, 0.15, fps, false)
	else:
		state = -10.0

func _direct_chase(fps: float, dist: float, player: Node3D, in_pocket: bool) -> void:
	if dist > 40.0 or in_pocket:
		global_position.y += (player.global_position.y - global_position.y) / 50.0 * fps   # nearer than 40 he keeps his height
	curr_speed += (speed - curr_speed) * minf(fps / 10.0, 1.0)
	_turn_toward(player.global_position, fps, 10.0)
	_animate(284.0, 333.0, curr_speed / 70.0 * 43.0, fps)
	path_timer = maxf(path_timer - fps, 0.0)
	if path_timer <= 0.0:
		_find_route(player)
		path_timer = 70.0 * 10.0

func _follow_route(fps: float, player: Node3D) -> void:
	if path_timer <= 0.0:
		_find_route(player)
		path_timer = 70.0 * 10.0
		curr_speed = 0.0
		return
	path_timer = maxf(path_timer - fps, 0.0)
	if _route_index >= _route.size():
		_route_status = 0
		curr_speed += (0.0 - curr_speed) * minf(fps / 10.0, 1.0)
		_animate(334.0, 494.0, 0.3, fps)
		return
	var waypoint := _route[_route_index]
	global_position.y += ((waypoint.y - 0.26) - global_position.y) / 50.0 * fps
	# EntityDistance from the collider: it settles 0.11 under the waypoint, so measured from the model the gap never drops
	# below 0.26 and he circles the first waypoint for ever
	var gap := (global_position + Vector3(0.0, COLLIDER_RISE, 0.0)).distance_to(waypoint)
	_turn_toward(waypoint, fps, minf(20.0, gap * 10.0))
	curr_speed += (speed - curr_speed) * minf(fps / 10.0, 1.0)
	_animate(284.0, 333.0, curr_speed / 70.0 * 43.0, fps)
	if gap < 0.2:
		_route_index += 1

func _find_route(player: Node3D) -> void:
	var facility := _facility()
	var result: Dictionary = facility.find_path(global_position, player.global_position)
	_route_status = int(result.status)
	_route.clear()
	_route_index = 0
	var points: Array = result.points
	# FindPath fills n\Path from index 1 (Path[0] stays Null) and holds 20 entries: the last waypoint is never stored and a long
	# route is cut after its 19th, so he follows that stretch and then cuts straight through the walls
	var kept := points.size() if points.size() <= 1 else mini(points.size() - 1, 19)
	for i in kept:
		_route.append(points[i])

# Inside 0.8: he reaches out (frames 105..110) and the touch drops the player.
func _grab(fps: float, dist: float, player: CharacterBody3D, in_pocket: bool) -> void:
	curr_speed += ((speed * 2.5 if dist > 0.5 else 0.0) - curr_speed) * minf(fps / 10.0, 1.0)
	_animate(105.0, 110.0, 0.15, fps, false)
	if player.fall_timer >= 0.0:
		_turn_toward(player.global_position, fps, 10.0)
		if ceilf(frame) == 110.0 and not GameState.god_mode:
			grabs += 1
			Sfx.play_global(self, "SFX/Character/D9341/Damage2.ogg")
			Sfx.play_global(self, "SFX/Horror/Horror5.ogg")
			if in_pocket:
				player.kill(DEATH_POCKET)
				return
			Sfx.play_global(self, "SFX/SCP/106/Laugh.ogg")
			player.start_fall()

# FallTimer < -250: MoveToPocketDimension, and 106 stays away for a while.
func _take_player(player: CharacterBody3D) -> void:
	state = 250.0
	player.fall_timer = 0.0
	_facility().enter_pocket(player)

func animate(start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	_animate(start, quit, speed, fps, loop)

func set_frame(value: float) -> void:
	_set_frame(value)

# More than 10 away and unseen: appear 2 behind the player (EntityPick back 5 units).
func _reappear_behind(player: CharacterBody3D) -> void:
	var back := player.global_transform.basis.z   # behind the player
	var from := player.global_position + Vector3(0.0, 0.3, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + back * 5.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	global_position = hit.position
	global_position.y = _floor_below(hit.position)
	var toward: Vector3 = player.global_position - global_position
	rotation.y = atan2(-toward.x, -toward.z)
	global_position -= toward.normalized() * 2.0   # MoveEntity(0, 0, -2)
	Sfx.play_at(self, "SFX/SCP/106/Laugh.ogg", 10.0)
	Sfx.play_at(self, "SFX/SCP/106/WallDecay%d.ogg" % randi_range(1, 3), 10.0)
	path_timer = 0.0
	reload = 70.0 * 10.0 / float(GameState.other_factors() + 1)

# TeleportEntity: a probe 0.05 above the point looks 2 down; the collider rests 0.22 above that floor, the model 0.15 under it.
func _floor_below(at: Vector3) -> float:
	var from := at + Vector3(0.0, 0.05, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -2.0, 0.0))
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y + 0.07 if not hit.is_empty() else at.y

func _line_to(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 0.4, 0.0)
	var to := player.global_position + Vector3(0.0, 0.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func in_view(camera: Camera3D) -> bool:
	return EntityInView.mesh(camera, _visual.mesh_instance)

func _turn_toward(point: Vector3, fps: float, smooth: float) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(fps / smooth, 1.0))

# CreateDecal(0, x, 0.01, z, 90, Rand(360), 0) with Size 0.05, SizeChange 0.001, alpha 0.8: the stain grows to 2 across over 950 frames.
func _corrosion_decal(at: Vector3) -> void:
	var Decal := load("res://scripts/world/growing_decal.gd")
	Decal.make(get_parent(), Vector3(at.x, at.y + 0.01, at.z), "GFX/decal1.png", 0.05, 0.001, 0.8, true)

# ---- animation (AnimateNPC) -----------------------------------------------------------------

func _animate(start: float, quit: float, speed: float, fps: float, loop: bool = true) -> void:
	var new_time := frame
	if speed > 0.0:
		new_time = maxf(minf(frame + speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		if loop:
			new_time = frame + speed * fps
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = maxf(minf(frame + speed * fps, high), low)
	_set_frame(new_time)

func _set_frame(value: float) -> void:
	if absf(frame - value) < 0.001:
		return
	var before := frame
	frame = value
	_visual.set_frame(frame)
	if curr_speed > 0.005 * 70.0 * 0.05:
		for mark in [286.0, 311.0]:
			if before <= mark and frame > mark:
				steps_played += 1
				Sfx.play_at(self, "SFX/Step/StepPD%d.ogg" % randi_range(1, 3), 6.0, randf_range(0.8, 1.0))
				break
