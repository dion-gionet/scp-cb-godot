extends CharacterBody3D
class_name HumanNpc
# The human NPCs of NPCs.bb: guards (NPCtypeGuard) and Class D / scientists / janitors (NPCtypeD).
# Events set `state` (and `state2`, `state3`, `angle`, ...); the rules below run every frame.
#
# Guard states (UpdateNPCs, NPCtypeGuard):
#   0 idle, looking about      1 aims and shoots at the player   2 shoots (cutscene)
#   3 follows a path           4 idle, scans for the player      5 follows a target (enemy_x/z)
#   7 idle animation           8 nothing (pose held)             9 idle, head follows the player
#   10 walks straight ahead    11 hunts the player on foot       12 aims (at the player if state2 = 1)
#   13 standing guard          14 follows a path, then stands (13)
# Class D states: 0 idle, 1 walking (state2 = 1: at guard pace), 2 running, 3 and 8 hold a pose.
# Speeds are per 70 Hz frame like the original; the body moves by speed * 70 m/s.


enum Kind { GUARD, CLASS_D, CLERK }      # the clerk (NPCtypeClerk) is a Class D with its own model: the same states and frames

# DTextures[1..8] (ChangeNPCTextureID(n, id) uses id + 1): the Class D body skins.
const D_TEXTURES := {
	0: "gonzales.jpg", 1: "corpse.jpg", 2: "scientist.jpg", 3: "scientist2.jpg", 4: "janitor.jpg",
	5: "106victim.jpg", 6: "classd2.jpg", 7: "035victim.jpg", 8: "body1.jpg", 9: "body2.jpg",
}
const BODY2_TEXTURE := 9

const PLAYER_BLOCK_LAYER := 64      # HIT_PLAYER against the player (Main.bb 2698): a body on it stops the player; NPCs are not on it by default

const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0

var kind: int = Kind.GUARD
var state := 0
var state2 := 0.0
var state3 := 0.0
var prev_state := 0
var angle := 0.0                 # n\Angle, degrees
var speed := 0.0                 # per frame
var curr_speed := 0.0
var reload := 0.0
var frame := 1.0
var is_dead := false
var enemy := Vector3.ZERO        # EnemyX / EnemyZ
var texture_id := -1             # -1: the model's own skin
var model_override := ""         # another body for a Class D (SCP-035's host: GFX/npcs/035.b3d)
var no_target := false
var scene_move := 0.0           # forward distance a scripted scene adds this frame (negative = backwards)

var path: Array[Vector3] = []
var path_status := 0
var path_location := 0
var path_timer := 0.0

var steps_played := 0
var shots_fired := 0
var last_shot_hit := false

var _visual: Node3D
var _aim_pitch := 0.0
var _voice: AudioStreamPlayer3D

func setup(new_kind: int, texture: int = -1, model: String = "") -> void:
	kind = new_kind
	texture_id = texture
	model_override = model

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("human_npc")
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	# Class D use EntityRadius 0.32, which exactly fills a doorway (0.64 wide); Godot's collision margin
	# stops a sphere that tight, so they get a hair less
	shape.radius = 0.2 if kind == Kind.GUARD else 0.3
	body.shape = shape
	body.position.y = shape.radius
	add_child(body)
	_visual = B3DModel.new()
	var path_name := "GFX/npcs/guard.b3d" if kind == Kind.GUARD else ("GFX/npcs/clerk.b3d" if kind == Kind.CLERK else "GFX/npcs/classd.b3d")
	if not model_override.is_empty():
		path_name = model_override
	_visual.load_file(ContentPaths.existing_file(path_name))
	var scale_value := 0.29 / 2.5 / 1.0
	if kind == Kind.GUARD:
		speed = 2.0 / 100.0
	else:
		speed = 2.0 / 100.0
		var width: float = _visual.mesh_instance.get_aabb().size.x
		scale_value = 0.5 / maxf(width, 0.001)
		_apply_texture(texture_id)
	_visual.scale = Vector3.ONE * scale_value
	_visual.rotation.y = PI    # RotateEntity n\obj, 0, EntityYaw(n\Collider) + 180
	add_child(_visual)
	frame = 1.0 if kind == Kind.GUARD else 210.0
	_visual.set_frame(frame)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 20.0
	add_child(_voice)

# The part of an actor a save keeps (save_game.gd); the kind, skin and model are what spawn_human is asked for.
func save_state() -> Dictionary:
	return {
		"kind": kind, "texture": texture_id, "model": model_override, "state": state, "state2": state2, "state3": state3,
		"prev_state": prev_state, "angle": angle, "curr_speed": curr_speed, "reload": reload, "frame": frame, "dead": is_dead,
		"role": str(get_meta("role", "")),
	}

func load_state(data: Dictionary) -> void:
	state = int(data.state)
	state2 = float(data.state2)
	state3 = float(data.state3)
	prev_state = int(data.prev_state)
	angle = float(data.angle)
	curr_speed = float(data.curr_speed)
	reload = float(data.reload)
	is_dead = bool(data.dead)
	if str(data.get("role", "")) != "":
		set_meta("role", str(data.role))
	set_frame(float(data.frame))

# ChangeNPCTextureID: the whole body takes one picture.
func change_texture(id: int) -> void:
	texture_id = id
	_apply_texture(id)

func _apply_texture(id: int) -> void:
	var file: String = D_TEXTURES.get(id, "")
	if file.is_empty() or _visual == null or _visual.mesh_instance == null:
		return
	var texture := MeshLoader._load_texture(ContentPaths.existing_file("GFX/npcs/" + file))
	var mesh: ArrayMesh = _visual.mesh_instance.mesh     # shared by every copy of the model: paint this one's own materials
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if material is StandardMaterial3D or material is EntityMaterial:
			var own = material.duplicate()
			own.albedo_texture = texture
			_visual.mesh_instance.set_surface_override_material(i, own)

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null:
		return
	var fps := delta * 70.0
	var before := frame
	var move := 0.0    # forward distance this frame (Blitz MoveEntity n\Collider, 0, 0, n\CurrSpeed * FPSfactor)
	if kind == Kind.GUARD:
		move = _guard(fps, delta, player, before)
	else:
		move = _class_d(fps, delta, player, before)
	if kind == Kind.GUARD and curr_speed > 0.01:
		if before < 5.0 and frame >= 5.0:
			_step()
		elif before < 23.0 and frame >= 23.0:
			_step()
	if kind == Kind.GUARD and frame > 286.5 and frame < 288.5:
		is_dead = true
	reload = maxf(reload - fps, 0.0)
	move += scene_move
	scene_move = 0.0
	var forward := -global_transform.basis.z
	_gravity_step(delta, forward * move / maxf(delta, 0.0001))

func _guard(fps: float, delta: float, player: CharacterBody3D, before: float) -> float:
	var move := 0.0
	match state:
		1:
			_raise_gun_if_needed(fps)
			if player.dead:
				state = 0
			else:
				_aim_and_shoot(fps, player)
		2:
			animate(245.0, 248.0, 0.35, fps)
			if reload == 0.0:
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 20.0)
				shots_fired += 1
				Gunfire.flash(self, _muzzle(), 0.2, false)
				reload = 7.0
		3:
			move = _follow_path(fps, player, 4, false, before)
		4:
			animate(77.0, 201.0, 0.2, fps)
			if randi() % int(maxf(400.0 / fps, 1.0)) == 0:
				angle = randf_range(-180.0, 180.0)
			var wobble := sin(deg_to_rad(GameState.clock_ms() / 50.0)) * 2.0
			rotation.y = _curve_angle(deg_to_rad(angle + wobble), rotation.y, 150.0, fps)
			var dist := global_position.distance_to(player.global_position)
			if dist < 15.0:
				var delta_yaw := rad_to_deg(_yaw_to(player.global_position))
				if fposmod(rad_to_deg(rotation.y) - delta_yaw, 360.0) < 90.0:
					if _sees(player):
						state = 1
		5:
			var to_enemy := Vector3(enemy.x - global_position.x, 0.0, enemy.z - global_position.z)
			rotation.y = _curve_angle(atan2(-to_enemy.x, -to_enemy.z) + deg_to_rad(angle), rotation.y, 20.0, fps)
			var gap := to_enemy.length()
			animate(1.0, 38.0, curr_speed * 40.0, fps)
			if gap > 2.0 or gap < 1.0:
				curr_speed = _curve_value(speed * signf(gap - 1.5) * 0.75, curr_speed, 10.0, fps)
			else:
				curr_speed = _curve_value(0.0, curr_speed, 10.0, fps)
			move = curr_speed * fps
		7:
			animate(77.0, 201.0, 0.2, fps)
		8:
			pass
		9:
			animate(77.0, 201.0, 0.2, fps)
			angle = rad_to_deg(rotation.y)
		10:
			animate(1.0, 38.0, curr_speed * 40.0, fps)
			curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
			move = curr_speed * fps
		11:
			move = _search_and_shoot(fps, player, before)
		12:
			_raise_gun_if_needed(fps)
			if frame < 345.0:
				animate(302.0, 344.0, 0.35, fps)
			if state2 == 1.0:
				var to_player := player.global_position - global_position
				rotation.y = _curve_angle(atan2(-to_player.x, -to_player.z), rotation.y, 10.0, fps)
			else:
				rotation.y = _curve_angle(deg_to_rad(angle), rotation.y, 10.0, fps)
		13:
			animate(202.0, 244.0, 0.35, fps)
		14:
			move = _follow_path(fps, player, 13, true, before)
		_:
			if randi() % int(maxf(400.0 / fps, 1.0)) == 0:
				prev_state = int(randf_range(-30.0, 30.0))
			path_status = 0
			animate(77.0, 201.0, 0.2, fps)
			var sway := sin(deg_to_rad(GameState.clock_ms() / 50.0)) * 2.0
			rotation.y = _curve_angle(deg_to_rad(angle + float(prev_state) + sway), rotation.y, 50.0, fps)
	return move

# Frames below 39, 77-244, 249-301 and above 344 raise the weapon first (345..357, then the aim loop).
func _raise_gun_if_needed(fps: float) -> void:
	if frame < 39.0 or (frame > 76.0 and frame < 245.0) or (frame > 248.0 and frame < 302.0) or frame > 344.0:
		animate(345.0, 357.0, 0.2, fps, false)
		if frame >= 356.0:
			set_frame(302.0)

# State 1: turn to the player and fire every 7 frames. The shot lands with 0.4 accuracy (0.9 on
# the aggressive difficulties); at gate B he sees farther but is less sure.
func _aim_and_shoot(fps: float, player: CharacterBody3D) -> void:
	var dist := global_position.distance_to(player.global_position)
	var accuracy := 0.4 + 0.5 * float(GameState.aggressive_npcs())
	var detect := 11.0
	var facility := _facility()
	var room_name: String = facility.room_name_at(player.global_position)
	if room_name == "exit1":
		detect = 21.0
		accuracy = 0.0
		if randi_range(1, 8 - int(GameState.aggressive_npcs()) * 4) < 2:
			accuracy = 0.03
		accuracy += 0.5 - player.curr_speed / 70.0 * 20.0
	if dist < detect:
		var to_player := player.global_position - global_position
		rotation.y = _curve_angle(atan2(-to_player.x, -to_player.z), rotation.y, 10.0, fps)
		_aim_pitch = _curve_value(minf(rad_to_deg(atan2(player.global_position.y + 0.5 - global_position.y - 1.0, Vector2(to_player.x, to_player.z).length())), 20.0), _aim_pitch, 10.0, fps)
		if reload == 0.0:
			if state3 == 1.0 or _hits_player(player, dist):
				var insta := false
				var message := ""
				if room_name == "start":
					message = "Subject D-9341. Cause of death: Gunshot wound to the head. The surveillance tapes confirm that the subject was terminated by Agent Ulgrin shortly after the site lockdown was initiated."
					insta = true
				elif room_name == "exit1":
					message = "\"Agent G. to control. Eliminated a Class D escapee in Gate B's courtyard.\""
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 35.0)
				shots_fired += 1
				Gunfire.shoot(self, _muzzle(), accuracy, message, insta)
				reload = 7.0
			else:
				curr_speed = speed
		if reload > 0.0 and reload <= 7.0:
			animate(245.0, 248.0, 0.35, fps)
		elif frame < 302.0:
			animate(302.0, 344.0, 0.35, fps)
	else:
		animate(302.0, 344.0, 0.35, fps)

# State 11: shoots when the player is in sight within 11, otherwise walks a path to them.
func _search_and_shoot(fps: float, player: CharacterBody3D, before: float) -> float:
	var move := 0.0
	_raise_gun_if_needed(fps)
	if player.dead:
		state = 0
		return 0.0
	var dist := global_position.distance_to(player.global_position)
	var search := dist < 11.0 and _sees(player)
	if search:
		var to_player := player.global_position - global_position
		rotation.y = _curve_angle(atan2(-to_player.x, -to_player.z), rotation.y, 10.0, fps)
		if reload == 0.0:
			if state3 == 1.0 or _hits_player(player, dist):
				Sfx.play_at(self, "SFX/General/Gunshot.ogg", 35.0)
				shots_fired += 1
				Gunfire.shoot(self, _muzzle(), 1.0, "", false)
				reload = 7.0
			else:
				curr_speed = speed
		if reload > 0.0 and reload <= 7.0:
			animate(245.0, 248.0, 0.35, fps)
		elif frame < 302.0:
			animate(302.0, 344.0, 0.35, fps)
		return 0.0
	if path_status == 1:
		if path_location >= path.size():
			path_location = 0
			path_status = 0
		else:
			animate(39.0, 76.0, curr_speed * 40.0, fps)
			curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
			var waypoint := path[path_location]
			var to_point := waypoint - global_position
			rotation.y = _curve_angle(atan2(-to_point.x, -to_point.z), rotation.y, 20.0, fps)
			move = curr_speed * fps
			if Vector2(to_point.x, to_point.z).length() < 0.2:
				path_location += 1
			_open_doors()
	else:
		path_timer = maxf(path_timer - fps, 0.0)
		if path_timer <= 0.0:
			_find_path(player.global_position)
			path_timer = 70.0 * 5.0
		curr_speed = _curve_value(0.0, curr_speed, 10.0, fps)
	if before < 43.0 and frame >= 43.0:
		_step()
	elif before < 61.0 and frame >= 61.0:
		_step()
	return move

# States 3 and 14: follow the route; when it ends (or there is none) go to `end_state`.
func _follow_path(fps: float, player: Node3D, end_state: int, anim39: bool, before: float) -> float:
	var move := 0.0
	if path_status == 2:
		state = end_state
		curr_speed = 0.0
	elif path_status == 1:
		if path_location >= path.size():
			path_location = 0
			path_status = 0
		else:
			var waypoint := path[path_location]
			var to_point := waypoint - global_position
			rotation.y = _curve_angle(atan2(-to_point.x, -to_point.z), rotation.y, 20.0, fps)
			animate(39.0 if anim39 else 1.0, 76.0 if anim39 else 38.0, curr_speed * 40.0, fps)
			curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
			move = curr_speed * fps
			if Vector2(to_point.x, to_point.z).length() < 0.2:
				path_location += 1
			_open_doors()
	else:
		curr_speed = 0.0
		state = end_state
	if anim39:
		if before < 43.0 and frame >= 43.0:
			_step()
		elif before < 61.0 and frame >= 61.0:
			_step()
	return move

func _class_d(fps: float, delta: float, player: CharacterBody3D, before: float) -> float:
	match state:
		0:
			curr_speed = _curve_value(0.0, curr_speed, 5.0, fps)
			animate(210.0, 235.0, 0.1, fps)
		1:
			if state2 == 1.0:
				curr_speed = _curve_value(speed * 0.7, curr_speed, 20.0, fps)
			else:
				curr_speed = _curve_value(0.015, curr_speed, 5.0, fps)
			animate(236.0, 260.0, curr_speed * 18.0, fps)
		2:
			curr_speed = _curve_value(0.03, curr_speed, 5.0, fps)
			animate(301.0, 319.0, curr_speed * 18.0, fps)
	if state2 != 2.0:
		if state == 1 and curr_speed > 0.01:
			if before < 244.0 and frame >= 244.0:
				_step()
			elif before < 256.0 and frame >= 256.0:
				_step()
		elif state == 2 and curr_speed > 0.01:
			if before < 309.0 and frame >= 309.0:
				_step(true)
			elif before <= 319.0 and frame <= 301.0:
				_step(true)
	if frame == 19.0 or frame == 60.0:
		is_dead = true
	return curr_speed * fps

# EntityVisible between the NPC and the player: nothing of the map in the way.
func _sees(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 0.3, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# EntityPick from chest height toward the player: is the player the first thing hit?
func _hits_player(player: CharacterBody3D, dist: float) -> bool:
	var from := global_position + Vector3(0.0, 1.0, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 0.3, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + (to - from).normalized() * (dist + 0.5))
	query.collision_mask = 3
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player

# MoveEntity (pvt, 0.8 * 0.079, 10.75 * 0.079, 6.9 * 0.079) from the model: right, up, forward.
func _muzzle() -> Vector3:
	var basis_yaw := Basis(Vector3.UP, rotation.y)
	return global_position + basis_yaw * Vector3(0.8 * 0.079, 10.75 * 0.079, -6.9 * 0.079)

func _gravity_step(delta: float, flat_velocity: Vector3) -> void:
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

# FindPath: waypoints from the facility's graph.
func find_path_to(target: Vector3) -> int:
	return _find_path(target)

func _find_path(target: Vector3) -> int:
	var facility := _facility()
	path.clear()
	path_location = 0
	if facility == null:
		path_status = 2
		return path_status
	var result: Dictionary = facility.find_path(global_position, target)
	path_status = int(result.status)
	for point in result.points:
		path.append(point)
	return path_status

# Closed, unlocked doors close ahead are opened.
func _open_doors() -> void:
	var facility := _facility()
	if facility == null:
		return
	for node in facility.doors_near(global_position, 1.6):
		var door := node as Node3D
		if door == null or door.open or door.locked or door.keycard != 0 or not door.code.is_empty():
			continue
		if door.openstate > 0.0 and door.openstate < 180.0:
			continue
		var flat := Vector2(door.global_position.x - global_position.x, door.global_position.z - global_position.z)
		if flat.length() < 1.6 and absf(door.global_position.y - global_position.y) < 2.0:
			door.npc_open()

# Blitz DeltaYaw (radians, -pi..pi): the turn that would face the point.
func _yaw_to(point: Vector3) -> float:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	return wrapf(atan2(-flat.x, -flat.z) - rotation.y, -PI, PI)

# CurveAngle on radians: moves 1 / smooth of the way per 70 Hz frame.
func _curve_angle(wanted: float, current: float, smooth: float, fps: float) -> float:
	return lerp_angle(current, wanted, minf(fps / smooth, 1.0))

# CurveValue: moves 1 / smooth of the way per frame without overshooting.
func _curve_value(wanted: float, current: float, smooth: float, fps: float) -> float:
	var step := (wanted - current) * (fps / smooth)
	if wanted < current:
		return maxf(current + step, wanted)
	return minf(current + step, wanted)

func _step(run: bool = false) -> void:
	steps_played += 1
	if kind == Kind.GUARD:
		Sfx.play_at(self, "SFX/Character/MTF/Step%d.ogg" % randi_range(1, 3), 8.0, randf_range(0.5, 0.7))
	else:
		var metal := 0
		var facility := _facility()
		if facility != null:
			var room: Node3D = facility.room_at(global_position)
			if room != null and room.has_method("step_type_at"):
				metal = room.step_type_at(global_position)
		var file := "SFX/Step/%s%s%d.ogg" % ["Run" if run else "Step", "Metal" if metal == 1 else "", randi_range(1, 3)]
		Sfx.play_at(self, file, 8.0, randf_range(0.3, 0.5))

func say(relative: String, volume: float = 1.0) -> void:
	var source := Sfx.stream(relative)
	if source != null:
		_voice.stream = source
		_voice.volume_db = linear_to_db(maxf(volume, 0.0001))
		_voice.play()

# ---- animation (AnimateNPC / SetNPCFrame) ----------------------------------------------------------

func animate(start: float, quit: float, anim_speed: float, fps: float, loop: bool = true) -> void:
	var new_time := frame
	if anim_speed > 0.0:
		new_time = maxf(minf(frame + anim_speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		if loop:
			new_time = frame + anim_speed * fps
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = maxf(minf(frame + anim_speed * fps, high), low)
	set_frame(new_time)

func set_frame(value: float) -> void:
	if absf(frame - value) < 0.001:
		return
	frame = value
	_visual.set_frame(frame)

func in_view(camera: Camera3D) -> bool:
	return EntityInView.mesh(camera, _visual.mesh_instance)
