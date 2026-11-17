extends "res://scripts/npc/scp_008_zombie.gd"
# SCP-1499-1, the inhabitants of SCP-1499's dimension (NPCs.bb NPCtype1499, UpdateNPCs "Case NPCtype1499"): speed 1.5 / 100 (x 0.9-1.1),
# model 1499-1.b3d at 0.08 / 4 (x 0.8-1.0), full bright. Within 45 of the player it acts (farther it is hidden and still).
# kind (n\PrevState): 0 citizen, 1 guard (the stairs, next to the king), 2 the king, 3 a front guard of the church.
#  - State 0 walks about (turning 45 degrees now and then, 80-110 away from a wall found 1.5 ahead), stands still for 500-1500
#    frames now and then, and two citizens within 20 may pair up and stand talking (frames 296 / 856 / 905); 1 in 5000 frames it
#    screams (203-295, State 2) with an idle sound; an even-numbered one within 10 that sees the player screams as well, and
#    within 5 (Triggered.ogg) the scream ends in an attack and wakes every other citizen (State 1)
#  - State 1 attacks: turns at the player and runs (x 1.75, guards x 2) with frames 1-62 (even IDs) or 100-167; within 0.75 it slashes
#    (State 3) if it is an even ID, a hostile one, a guard or a front guard, otherwise it only stands in front of the player (State 4)
#  - State 3 slashes (63-100 or 168-202, the blow at 89 / 189 within 0.85 and 60 degrees: injuries + 0.75-1.5 and a Slash sound; over 10 kills)
#  - State 4 stands in front of the player (296-320) until they step back past 0.85
# A citizen sees any other citizen in State 1 / 3 / 4 and joins in.


var kind := 0                  # n\PrevState
var always_hostile := false    # n\State3 = 1
var npc_id := 0                # n\ID (the parity matters)
var angle := 0.0               # n\Angle (radians)
var reload := 0.0              # n\Reload: busy talking / the king's speech
var target: Node = null        # n\Target: the citizen it is talking to
var sound_channel: AudioStreamPlayer3D = null
var _unit_scale := 0.02

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp1499")
	always_near = true
	speed = (1.5 / 100.0) * randf_range(0.9, 1.1)
	frame = 1.0
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	_body = CollisionShape3D.new()
	_body.shape = shape
	_body.position.y = shape.radius
	add_child(_body)
	_unit_scale = (0.08 / 4.0) * randf_range(0.8, 1.0)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/1499-1.b3d"))
	_visual.scale = Vector3.ONE * _unit_scale
	make_bright(_visual)
	_visual.rotation.y = PI
	add_child(_visual)
	_visual.set_frame(frame)
	_loop = AudioStreamPlayer3D.new()
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 20.0
	add_child(_voice)
	angle = rotation.y

func set_state(value: int) -> void:
	state = value

func make_king() -> void:
	kind = 2
	var texture: Texture2D = MeshLoader._load_texture(ContentPaths.existing_image("GFX/npcs/1499_King.jpg"))
	if _visual != null and _visual.mesh_instance != null:
		var material := MeshLoader.entity_material(texture, false)
		_visual.mesh_instance.material_override = material

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	if dist >= HIDE_DISTANCE * 3.0:
		_visual.visible = false
		velocity = Vector3.ZERO
		return
	_visual.visible = true
	var before := frame
	if kind == 0 and (state == 0 or state == 2):
		for other in get_tree().get_nodes_in_group("scp1499"):
			if other != self and other.kind == 0 and other.state != 0 and other.state != 2:
				state = 1
				state2 = 0.0
				break
	match state:
		0:
			_wander(fps, player, dist)
		1:
			_attack(fps, player, dist)
		2:
			curr_speed = 0.0
			animate(203.0, 295.0, 0.1, fps, false)
			if frame > 294.0:
				state = int(state2)
		3:
			_slash(fps, player, dist, before)
		4:
			curr_speed = _curve_value(0.0, curr_speed, 5.0, fps)
			animate(296.0, 320.0, 0.2, fps)
			rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 20.0, fps)
			if dist > 0.85:
				state = 1
	_gravity_step(delta, -global_transform.basis.z * curr_speed * fps / maxf(delta, 0.0001))

# ---- state 0 ---------------------------------------------------------------------------------------------------------

func _wander(fps: float, player: CharacterBody3D, dist: float) -> void:
	if kind == 0:
		if curr_speed == 0.0:
			if reload == 0.0:
				if state2 < 500.0 * randf_range(1.0, 3.0):
					curr_speed = 0.0
					state2 += fps
				else:
					curr_speed += 0.0001
			else:
				if state2 < 1500.0:
					curr_speed = 0.0
					state2 += fps
				else:
					if target != null and is_instance_valid(target):
						if target.target != null:
							target.target = null
						target.reload = 0.0
						target.angle += deg_to_rad(randf_range(-45.0, 45.0))
						target = null
						reload = 0.0
						angle += deg_to_rad(randf_range(-45.0, 45.0))
					if curr_speed == 0.0:
						curr_speed += 0.0001
		else:
			if target != null and is_instance_valid(target):
				state2 = 0.0
			if state2 < 10000.0 * randf_range(1.0, 3.0):
				curr_speed = _curve_value(speed, curr_speed, 10.0, fps)
				state2 += fps
			else:
				curr_speed = _curve_value(0.0, curr_speed, 50.0, fps)
			rotation.y = _curve_angle(angle, rotation.y, 10.0, fps)
			if target == null or not is_instance_valid(target):
				if randi_range(1, 200) == 1:
					angle += deg_to_rad(randf_range(-45.0, 45.0))
				if _wall_ahead():
					angle = rotation.y + deg_to_rad(randf_range(80.0, 110.0))
			else:
				angle = _yaw_wanted(target.global_position)
				if global_position.distance_to(target.global_position) < 1.5:
					curr_speed = 0.0
					target.curr_speed = 0.0
					reload = 1.0
					target.reload = 1.0
					set_frame([296.0, 856.0, 905.0][randi_range(0, 2)])
					target.set_frame([296.0, 856.0, 905.0][randi_range(0, 2)])
	else:
		rotation.y = _curve_angle(angle, rotation.y, 10.0, fps)
	if curr_speed == 0.0:
		_stand(fps, player)
	else:
		if npc_id % 2 == 0:
			animate(1.0, 62.0, curr_speed * 28.0, fps)
		else:
			animate(100.0, 167.0, curr_speed * 28.0, fps)
		if kind == 0 and (target == null or not is_instance_valid(target)) and randi_range(1, 1200) == 1:
			for other in get_tree().get_nodes_in_group("scp1499"):
				if other != self and other.kind == 0 and (other.target == null or not is_instance_valid(other.target)) and global_position.distance_to(other.global_position) < 20.0:
					target = other
					other.target = self
					other.curr_speed += 0.0001
					break
	# the scream, now and then, and at the sight of the player
	if (target == null or not is_instance_valid(target)) and kind == 0:
		if randi_range(1, 5000) == 1:
			state = 2
			state2 = 0.0
			if not _voice.playing and dist < 20.0:
				_voice_play("SFX/SCP/1499/Idle%d.ogg" % randi_range(1, 4))
		if npc_id % 2 == 0 and not GameState.no_target_mode():
			if dist < 10.0 and _clear_to(player):
				state = 2
				if dist < 5.0:
					_voice_play("SFX/SCP/1499/Triggered.ogg")
					state2 = 1.0
					for other in get_tree().get_nodes_in_group("scp1499"):
						if other != self and other.kind == 0:
							other.state = 1
							other.state2 = 0.0
				else:
					state2 = 0.0
				set_frame(203.0)
	elif kind == 1:
		if not GameState.no_target_mode() and dist < 4.0 and _clear_to(player):
			_voice_play("SFX/SCP/1499/Triggered.ogg")
			state = 1
			set_frame(203.0)

func _stand(fps: float, player: CharacterBody3D) -> void:
	if reload == 0.0 and kind != 2:
		animate(296.0, 320.0, 0.2, fps)
	elif reload == 0.0 and kind == 2:
		# 509-533, then 534-601, then one of the two again
		if frame <= 532.5:
			animate(509.0, 533.0, 0.2, fps, false)
		elif frame > 533.5 and frame <= 600.5:
			animate(534.0, 601.0, 0.2, fps, false)
		else:
			set_frame(509.0 if randi_range(0, 1) == 0 else 534.0)
	else:
		if kind == 2:
			animate(713.0, 855.0, 0.2, fps, false)
			if frame > 833.5:
				rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 10.0, fps)
		elif kind == 1:
			animate(602.0, 712.0, 0.2, fps, false)
			if frame > 711.5:
				reload = 0.0
		else:
			if frame <= 319.5:
				animate(296.0, 320.0, 0.2, fps, false)
			elif frame > 320.5 and frame < 903.5:
				animate(856.0, 904.0, 0.2, fps, false)
			elif frame > 904.5 and frame < 952.5:
				animate(905.0, 953.0, 0.2, fps, false)
			else:
				set_frame([296.0, 856.0, 905.0][randi_range(0, 2)])

func _attack(fps: float, player: CharacterBody3D, dist: float) -> void:
	if GameState.no_target_mode():
		state = 0
	if kind == 0:
		var music_room: String = _facility().room_name_at(player.global_position)
		if music_room == "dimension1499":
			GameState.music_override = "1499Danger"
	rotation.y = _curve_angle(_yaw_wanted(player.global_position), rotation.y, 20.0, fps)
	if state2 == 0.0:
		if kind == 1:
			curr_speed = _curve_value(speed * 2.0, curr_speed, 10.0, fps)
			if target != null and is_instance_valid(target):
				target.state = 1
		else:
			curr_speed = _curve_value(speed * 1.75, curr_speed, 10.0, fps)
		if npc_id % 2 == 0:
			animate(1.0, 62.0, curr_speed * 28.0, fps)
		else:
			animate(100.0, 167.0, curr_speed * 28.0, fps)
	if dist < 0.75:
		if npc_id % 2 == 0 or always_hostile or kind == 1 or kind == 3 or kind == 4:
			state2 = float(randi_range(1, 2))
			state = 3
			set_frame(63.0 if state2 == 1.0 else 168.0)
		else:
			state = 4

func _slash(fps: float, player: CharacterBody3D, dist: float, before: float) -> void:
	curr_speed = _curve_value(0.0, curr_speed, 5.0, fps)
	if state2 == 1.0:
		animate(63.0, 100.0, 0.6, fps, false)
		if before < 89.0 and frame >= 89.0:
			_blow(player, dist)
		elif frame >= 99.0:
			state2 = 0.0
			state = 1
	else:
		animate(168.0, 202.0, 0.6, fps, false)
		if before < 189.0 and frame >= 189.0:
			_blow(player, dist)
		elif frame >= 201.0:
			state2 = 0.0
			state = 1

func _blow(player: CharacterBody3D, dist: float) -> void:
	if dist > 0.85 or absf(rad_to_deg(_yaw_to(player.global_position))) > 60.0:
		return
	var s := GameState
	s.injuries += randf_range(0.75, 1.5)
	Sfx.play_at(self, "SFX/General/Slash%d.ogg" % randi_range(1, 2), 10.0)
	hits += 1
	if s.injuries > 10.0:
		var inside: bool = _facility().room_name_at(player.global_position) == "dimension1499"
		if inside:
			s.death_msg = "All personnel situated within Evacuation Shelter LC-2 during the breach have been administered Class-B amnestics due to Incident 1499-E. The Class D subject involved in the event died shortly after being shot by Agent [REDACTED]."
		else:
			s.death_msg = "An unidentified male and a deceased Class D subject were discovered in [REDACTED] by the Nine-Tailed Fox. The man was described as highly agitated and seemed to only speak Russian. He's been taken into a temporary holding area at [REDACTED] while waiting for a translator to arrive."
		player.kill(s.death_msg)

func _wall_ahead() -> bool:
	var from := global_position + Vector3(0.0, 0.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from - global_transform.basis.z * 1.5)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _clear_to(player: CharacterBody3D) -> bool:
	var from := global_position + Vector3(0.0, 0.6, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0.0, 0.3, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _voice_play(relative: String) -> void:
	var stream := Sfx.stream(relative)
	if stream == null:
		return
	_voice.stream = stream
	_voice.play()

func die() -> void:
	pass

# EntityFX 1: the inhabitants are full bright (the shared model's materials are made unshaded once).
static func make_bright(model: Node) -> void:
	if model == null or model.mesh_instance == null or model.mesh_instance.mesh == null:
		return
	var mesh: Mesh = model.mesh_instance.mesh
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if (material is BaseMaterial3D or material is EntityMaterial) and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			var bright = material.duplicate()
			bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(mesh as ArrayMesh).surface_set_material(surface, bright)
