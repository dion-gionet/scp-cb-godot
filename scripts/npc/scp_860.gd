extends CharacterBody3D
# The monster of SCP-860-1 (NPCs.bb NPCtype860, UpdateNPCs "forestmonster" / Find860Angle). It lives only while the player is in the
# forest and is run by the event (room860_event.gd), which sets `state`:
#   0 hidden (parked 100 m below)
#   1 shows itself briefly 2.3 m above the ground between a free cell and the player's cell; it does not move until the player
#     looks at it, then stands in one of three poses, walks off away from the player and vanishes beyond 15 m
#   2 appears on the path in a cell next to the player's and follows the path towards the player, slowly (0.3 of its speed); at
#     4.5 m, or after the player has been running a while, it turns to 3
#   3 runs at the player along the path (0.8 of its speed) and, within 1.1, claws (frames 451-493): the kill comes at frame 461
# With one of the Log documents carried, the agent sprite (Agent I.J.) may stand beside it in state 1.


const SPEED := 8.0 / 100.0 * 70.0         # NPCs.ini speed 8.0 per 100 frames, at 70 Hz
const GRAVITY := 0.005 * 70.0 * 70.0
const MODEL_SCALE := 0.5 / 20.0

var forest: Node3D = null
var in_forest := false                    # the event's EventState = 1
var state := 0
var state2 := 0.0
var state3 := 0.0
var frame := 1.0
var curr_speed := 0.0
var drop_speed := 0.0
var spawned := false                       # state 1 or 2 has placed it since it was parked

var agent_state := 0.0                     # ForestNPCData[2]: 0 not shown, 1 shown, 2 decided not to
var agent_base := 0                        # ForestNPCData[0]
var agent_blink := 0.0                     # ForestNPCData[1]
var agent: Sprite3D = null
var _agent_texture: Texture2D = null

var _visual: Node3D
var _eyes: MeshInstance3D
var _eyes_material: ShaderMaterial
var _voice: AudioStreamPlayer3D
var _slash: AudioStream = null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("scp860")
	var body := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	body.shape = shape
	add_child(body)
	_visual = B3DModel.new()
	_visual.load_file(ContentPaths.existing_file("GFX/npcs/forestmonster.b3d"))
	_visual.scale = Vector3.ONE * MODEL_SCALE
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)           # the model lies on its back: RotateEntity n\obj, pitch - 90
	_visual.position = Vector3(0.0, -0.1, 0.0)
	add_child(_visual)
	_visual.set_frame(frame)
	_eyes = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	_eyes.mesh = quad
	_eyes_material = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_file("GFX/npcs/860_eyes.png")), Color(1, 1, 1, 0), true, true, false)
	_eyes.material_override = _eyes_material
	_eyes.top_level = true
	_eyes.visible = false
	add_child(_eyes)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 30.0
	add_child(_voice)
	visible = false
	global_position = Vector3(0.0, -110.0, 0.0)

func _exit_tree() -> void:
	if agent != null and is_instance_valid(agent):
		agent.queue_free()

func park() -> void:
	state = 0
	state2 = 0.0
	spawned = false
	global_position = Vector3(0.0, -110.0, 0.0)
	velocity = Vector3.ZERO

func set_parked_marker() -> void:
	global_position = Vector3(0.0, -110.0, 0.0)
	spawned = false

func _player() -> CharacterBody3D:
	return GameState.player

func _in_view(point: Vector3) -> bool:
	var player := _player()
	return player != null and player.camera.is_position_in_frustum(point)

func _face(direction: Vector3, smooth: float, fps: float) -> void:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.y), minf(fps / smooth, 1.0))

func animate(start: float, quit: float, anim_speed: float, fps: float, loop: bool = true) -> void:
	var new_time := frame
	if anim_speed > 0.0:
		new_time = maxf(minf(frame + anim_speed * fps, quit), start)
		if loop and new_time >= quit:
			new_time = start
	else:
		var low := minf(start, quit)
		var high := maxf(start, quit)
		new_time = frame + anim_speed * fps
		if loop:
			if new_time < low:
				new_time = high
			elif new_time > high:
				new_time = low
		else:
			new_time = clampf(new_time, low, high)
	set_frame(new_time)

func set_frame(value: float) -> void:
	if absf(frame - value) < 0.001:
		return
	frame = value
	_visual.set_frame(frame)

func _step_sound(range_m: float, volume: float) -> void:
	Sfx.play_at(self, "SFX/Step/StepForest%d.ogg" % randi_range(1, 3), range_m, volume)

func _cry(low: int, high: int, range_m: float = 10.0) -> void:
	_voice.stream = Sfx.stream("SFX/SCP/860/Cancer%d.ogg" % randi_range(low, high))
	_voice.max_distance = range_m
	_voice.play()

func _flat_distance_cell(world: Vector3) -> Vector2i:
	return forest.cell_of(world)

# Find860Angle: the direction to the next path cell that is nearer the player's cell, or straight to the player on the same cell.
func path_direction(player_position: Vector3) -> Vector3:
	var target := player_position
	var player_cell: Vector2i = forest.cell_of(player_position)
	var cell: Vector2i = forest.cell_of(global_position)
	if cell != player_cell:
		var found := false
		for x2 in range(maxi(cell.x - 1, 0), mini(cell.x + 1, forest.GRID - 1) + 1):
			for z2 in range(maxi(cell.y - 1, 0), mini(cell.y + 1, forest.GRID - 1) + 1):
				if found:
					continue
				if forest.grid[z2 * forest.GRID + x2] > 0 and (x2 != cell.x or z2 != cell.y) and (x2 == cell.x or z2 == cell.y):
					if absi(player_cell.x - x2) + absi(player_cell.y - z2) < absi(player_cell.x - cell.x) + absi(player_cell.y - cell.y):
						target = forest.blitz_world(Vector3(x2 * forest.TILE, 0.0, z2 * forest.TILE))
						found = true
	return Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)

func _physics_process(delta: float) -> void:
	var player := _player()
	if player == null or forest == null or not is_instance_valid(forest):
		return
	var fps := delta * 70.0
	_update_agent(player)
	visible = state != 0
	if state == 0:
		_eyes.visible = false
		state2 = 0.0
		global_position = Vector3(0.0, -100.0, 0.0)
		return
	var dist := global_position.distance_to(player.global_position)
	var previous_frame := frame
	match state:
		1:
			_state_one(player, dist, fps, delta)
		2:
			_state_two(player, dist, fps, delta, previous_frame)
		3:
			_state_three(player, dist, fps, delta, previous_frame)
	if state != 0:
		_eyes_update(player, dist)

func _ground_y() -> float:
	return forest.global_position.y

func _move(direction_speed: float, delta: float, gravity: bool) -> void:
	var forward := -global_transform.basis.z
	velocity.x = forward.x * direction_speed
	velocity.z = forward.z * direction_speed
	if gravity:
		drop_speed = maxf(drop_speed - GRAVITY * delta, -0.2 * 70.0)
		velocity.y = drop_speed
	else:
		velocity.y = 0.0
	move_and_slide()
	if is_on_floor():
		drop_speed = 0.0

func _state_one(player: CharacterBody3D, dist: float, fps: float, delta: float) -> void:
	drop_speed = 0.0
	if global_position.y <= -100.0:
		# a free cell next to the player's (not on the path), the monster between it and the player
		var player_cell: Vector2i = forest.cell_of(player.global_position)
		var placed := false
		for x2 in range(maxi(player_cell.x - 1, 1), mini(player_cell.x + 1, forest.GRID) + 1, 2):
			for z2 in range(maxi(player_cell.y - 1, 1), mini(player_cell.y + 1, forest.GRID) + 1, 2):
				if placed:
					continue
				if forest.grid[z2 * forest.GRID + x2] == 0:
					var spot: Vector3 = forest.blitz_world(Vector3(int((x2 + player_cell.x) / 2) * 12.0, 0.0, int((z2 + player_cell.y) / 2) * 12.0))
					spot.y = _ground_y() + 2.3
					global_position = spot
					if _in_view(spot):
						global_position = Vector3(0.0, -110.0, 0.0)
					else:
						placed = true
		if global_position.y > -100.0:
			Sfx.play_at(self, "SFX/Step/StepForest%d.ogg" % randi_range(1, 3), 15.0, 0.5)
			if agent_state != 1.0:
				agent_state = 0.0
			match randi_range(1, 3):
				1:
					look_at_player(player)
					set_frame(2.0)
				2:
					look_at_player(player)
					set_frame(201.0)
				3:
					look_at_player(player)
					rotation.y += PI * 0.5
					set_frame(299.0)
			state2 = 0.0
		return
	global_position.y = _ground_y() + 2.3
	_agent_logic(player)
	if state2 == 0.0:
		# does not move until the player looks at it
		if _in_view(global_position):
			state2 = 1.0
			if randi_range(1, 8) == 1:
				_cry(0, 2, 20.0)
	else:
		if frame <= 199.0:
			animate(2.0, 199.0, 0.5, fps, false)
			if frame == 199.0:
				set_frame(298.0)
				_step_sound(15.0, 1.0)
		elif frame <= 297.0:
			look_at_player(player)
			animate(200.0, 297.0, 0.5, fps, false)
			if frame == 297.0:
				set_frame(298.0)
				_step_sound(15.0, 1.0)
		else:
			# NPCs.bb turns away: point_direction(npc, player) is the direction from the player to the monster
			_face(global_position - player.global_position, 20.0, fps)
			animate(298.0, 316.0, curr_speed * 10.0 / 70.0, fps)
			curr_speed = curr_speed + (SPEED - curr_speed) * minf(fps / 10.0, 1.0)
			_move(curr_speed, delta, false)
			if dist > 15.0:
				park()
				return

func look_at_player(player: Node3D) -> void:
	var to := player.global_position - global_position
	rotation.y = atan2(-to.x, -to.z)

func _state_two(player: CharacterBody3D, dist: float, fps: float, delta: float, previous_frame: float) -> void:
	if global_position.y <= -100.0:
		var player_cell: Vector2i = forest.cell_of(player.global_position)
		var placed := false
		for x2 in range(maxi(player_cell.x - 1, 1), mini(player_cell.x + 1, forest.GRID) + 1):
			for z2 in range(maxi(player_cell.y - 1, 1), mini(player_cell.y + 1, forest.GRID) + 1):
				if placed:
					continue
				# a nearby path cell that is not the player's, in the same row or column
				if forest.grid[z2 * forest.GRID + x2] > 0 and (x2 != player_cell.x or z2 != player_cell.y) and (x2 == player_cell.x or z2 == player_cell.y):
					var spot: Vector3 = forest.blitz_world(Vector3(x2 * 12.0, 0.0, z2 * 12.0))
					spot.y = _ground_y() + 1.0
					global_position = spot
					drop_speed = 0.0
					if _in_view(spot):
						player.blink_timer = -10.0
					else:
						placed = true
		return
	_face(path_direction(player.global_position), 80.0, fps)
	curr_speed = curr_speed + (SPEED * 0.3 - curr_speed) * minf(fps / 50.0, 1.0)
	_move(curr_speed, delta, true)
	animate(494.0, 569.0, curr_speed * 25.0 / 70.0, fps)
	if state2 == 0.0:
		if dist < 8.0 and _in_view(global_position):
			Sfx.play_global(self, "SFX/SCP/860/Chase%d.ogg" % randi_range(1, 2))
			_cry(0, 2)
			state2 = 1.0
	if player.curr_speed > 0.03 * 70.0:
		state3 += fps
		if randf_range(0.0, 5000.0) < state3 and not _voice.playing:
			_cry(0, 2)
	else:
		state3 = maxf(state3 - fps, 0.0)
	if dist < 4.5 or state3 > randf_range(200.0, 250.0):
		_cry(3, 5)
		state = 3
	if dist > 20.0:
		park()
		return
	if (previous_frame < 533.0 and frame >= 533.0) or (previous_frame > 568.0 and frame < 2.0):
		_step_sound(15.0, 0.6)

func _state_three(player: CharacterBody3D, dist: float, fps: float, delta: float, previous_frame: float) -> void:
	_face(path_direction(player.global_position), 40.0, fps)
	if _slash == null:
		_slash = Sfx.stream("SFX/General/Slash1.ogg")
	var attacking: bool = dist < 1.1 or (frame > 451.0 and frame < 493.0) or player.dead
	if attacking:
		GameState.death_msg = ""
		curr_speed = curr_speed + (0.0 - curr_speed) * minf(fps / 5.0, 1.0)
		animate(451.0, 493.0, 0.5, fps, false)
		if previous_frame < 461.0 and frame >= 461.0:
			if not player.dead:
				player.kill("")
			Sfx.play_global(self, "SFX/General/Slash1.ogg")
		if previous_frame < 476.0 and frame >= 476.0:
			Sfx.play_global(self, "SFX/General/Slash2.ogg")
		if previous_frame < 486.0 and frame >= 486.0:
			Sfx.play_global(self, "SFX/General/Slash2.ogg")
	else:
		curr_speed = curr_speed + (SPEED * 0.8 - curr_speed) * minf(fps / 10.0, 1.0)
		animate(298.0, 316.0, curr_speed * 10.0 / 70.0, fps)
		if previous_frame < 307.0 and frame >= 307.0:
			_step_sound(10.0, 1.0)
	_move(curr_speed, delta, true)

# The eyes far away: the forest's fog hides the monster beyond 8 m, but its two eyes are drawn on a sphere of 8 m around the camera.
func _eyes_update(player: CharacterBody3D, dist: float) -> void:
	if dist > 8.0:
		var head := global_position + Vector3(0.0, 30.0 * 0.025, 0.0) + global_transform.basis * Vector3(0.0, 0.0, 33.0 * 0.025)
		var from: Vector3 = player.camera.global_position
		_eyes.global_position = from + (head - from).normalized() * 8.0
		_eyes.visible = true
		_eyes_material.set_shader_parameter("color", Color(1, 1, 1, minf(dist - 8.0, 1.0)))
	else:
		_eyes.visible = false

func _agent_texture_at(frame_index: int) -> Texture2D:
	if _agent_texture == null:
		var image := MeshLoader.load_image(ContentPaths.existing_file("GFX/npcs/AgentIJ.AIJ"))
		if image == null or image.is_empty():
			return null
		_agent_texture = ImageTexture.create_from_image(image)
	var atlas := AtlasTexture.new()
	atlas.atlas = _agent_texture
	atlas.region = Rect2(frame_index * 140.0, 0.0, 140.0, 410.0)
	return atlas

func _ensure_agent() -> void:
	if agent != null and is_instance_valid(agent):
		return
	agent = Sprite3D.new()
	agent.pixel_size = 1.5 / 410.0
	agent.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	agent.shaded = false
	agent.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	agent.visible = false
	agent.top_level = true
	add_child(agent)

func _update_agent(player: CharacterBody3D) -> void:
	_ensure_agent()
	if agent_state == 1.0:
		agent.visible = true
		if state != 1:
			if (player.blink_timer < -8.0 and player.blink_timer > -12.0) or not _in_view(agent.global_position):
				agent_state = 0.0
				agent.visible = false
	else:
		agent.visible = false

func _agent_logic(player: CharacterBody3D) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if agent_state == 0.0:
		var chance := 0
		var amount := 0
		if hud != null:
			for i in hud.items.size():
				var name: String = hud.items[i]
				if name == "Log #1" or name == "Log #2" or name == "Log #3":
					amount += 1
					chance += 10 * amount
		if randi_range(1, 860 - chance) == 1:
			agent_state = 1.0
			agent_base = 0 if randi_range(1, 2) == 1 else 2
			agent_blink = 0.0
			agent.visible = true
			var at := global_position + Vector3(0.0, 0.5, 0.0)
			var side := global_transform.basis * Vector3(0.75, 0.0, 0.0)
			agent.global_position = at + side
			agent.texture = _agent_texture_at(agent_base)
		else:
			agent_state = 2.0
	elif agent_state == 1.0:
		if agent_blink == 0.0:
			if randi_range(1, 200) == 1:
				agent_blink = 1.0
				agent.texture = _agent_texture_at(agent_base + 1)
		elif agent_blink > 0.0 and agent_blink < 5.0:
			agent_blink = minf(agent_blink + 1.0, 5.0)
		else:
			agent_blink = 0.0
			agent.texture = _agent_texture_at(agent_base)
