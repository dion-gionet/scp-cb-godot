extends CharacterBody3D
# SCP-173 (NPCs.bb UpdateNPCs, NPCtype173). Rules, in the original's order:
#  - inside 15 units it freezes whenever it is in the camera frustum with the eyes open
#    (EntityInView ignores walls); while frozen it only plays its scare cues
#  - unobserved and beyond 50 units it occasionally jumps to a waypoint 15-25 units from you,
#    beyond 12 units (0.8 * HideDistance) it hops to the nearby waypoint closest to you
#  - within 12 units it chases: it remembers where it last saw you (visible and < 10 units),
#    walks there, and otherwise wanders; inside 0.65 units of a visible player it snaps the neck
# Its face is on the model's +Z side and the model is mounted at a half turn, so the node's
# forward (-Z) is the way it looks.


const SPEED := 0.38 * 70.0                 # NPCs.ini speed 38 / 100, per frame at 70 fps
var speed := SPEED * GameState.npc_speed_factor()                      # the console's 173speed (per second)
const KILL_DISTANCE := 0.65
const HIDE_DISTANCE := 15.0
const FAR_DISTANCE := 50.0
const GRAVITY := 0.005 * 70.0 * 70.0
const MAX_FALL := 0.2 * 70.0

var active := false
# Idle: 0 normal, 1 held still by an MTF unit that is watching it, 2 boxed by the MTF leader, 3 back in its chamber
var idle := 0
var contained := false
var target_node: Node = null
var floor_y := 0.31
var mesh_depth := 1.0
var enemy_pos := Vector3.ZERO
var has_enemy := false
var move_state := 0.0         # n\State: drag-sound volume, rises while it moves, fades when watched
var _prev_xz := Vector2.ZERO
var _last_dist := 0.0
var _last_scare_ms := -100000.0

@onready var visual: MeshInstance3D = $MeshInstance3D
@onready var drag: AudioStreamPlayer3D = $Drag
var box: MeshInstance3D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var mesh := MeshLoader.load_b3d(ContentPaths.existing_file("GFX/npcs/173_2.b3d"))
	visual.mesh = mesh
	mesh_depth = maxf(mesh.get_aabb().size.z, 0.001)
	var fit := 0.35 / mesh_depth
	visual.scale = Vector3(fit, fit, fit)
	visual.position.y = 0.0
	visual.rotation.y = PI
	var today := Time.get_date_dict_from_system()
	if int(today.month) == 10 and int(today.day) == 31:       # CreateNPC: on the 31st of October he is a jack-o'-lantern
		GameState.halloween = true
	if GameState.halloween:
		set_skin(true)
	box = MeshInstance3D.new()
	box.mesh = MeshLoader.load_b3d(ContentPaths.existing_file("GFX/173box.b3d"))
	box.scale = Vector3.ONE * MeshLoader.ROOM_SCALE
	box.rotation.y = PI
	box.visible = false
	add_child(box)
	var drag_path := ContentPaths.existing_file("SFX/SCP/173/StoneDrag.ogg")
	if FileAccess.file_exists(drag_path):
		drag.stream = AudioStreamOggVorbis.load_from_file(drag_path)
		drag.max_distance = 10.0
		drag.volume_db = -80.0

# EntityTexture(n\obj, 173h.pt or 173texture.jpg, 0, 0): the jack-o'-lantern skin (a JPEG with another name) or the stone one
func set_skin(jack_o_lantern: bool) -> bool:
	var file := "GFX/npcs/173h.pt" if jack_o_lantern else "GFX/npcs/173texture.jpg"
	var image := MeshLoader.load_image(ContentPaths.existing_file(file))
	if image == null:
		return false
	var texture := ImageTexture.create_from_image(image)
	for i in visual.get_surface_override_material_count():
		var material := visual.get_active_material(i)
		if material is StandardMaterial3D or material is EntityMaterial:
			var own = material.duplicate()
			own.albedo_texture = texture
			visual.set_surface_override_material(i, own)
	return true

func _physics_process(delta: float) -> void:
	if idle != 2:
		visual.position.y = 0.0
		box.visible = false
	if not active:
		drag.stop()
		return
	if idle > 0:
		drag.stop()
		velocity.x = 0.0
		velocity.z = 0.0
		if idle == 2:
			_follow_leader(delta)
		else:
			_fall(delta)
		return
	var player: CharacterBody3D = GameState.player
	if player == null or player.dead:
		return
	var fps := delta * 70.0
	var dist := player.global_position.distance_to(global_position)
	var seen := false       # "temp": the player is visible from here and closer than 10
	var observed := false   # "move = False"
	if dist < HIDE_DISTANCE:
		if dist < 10.0 and _collider_sight(player):
			seen = true
			enemy_pos = player.global_position
			has_enemy = true
		if not player.eyes_closed() and not GameState.nvg_blinking and player.camera.is_position_in_frustum(global_position + Vector3(0.0, 0.8, 0.0)):
			observed = true
	var here := Vector2(global_position.x, global_position.z)
	var moved_volume := clampf(here.distance_to(_prev_xz) / maxf(fps, 0.001) * 2.5, 0.0, 1.0)
	_prev_xz = here
	if observed:
		velocity.x = 0.0
		velocity.z = 0.0
		_scare_cues(player, dist, seen)
		move_state = maxf(0.0, move_state - fps / 20.0)
		_last_dist = dist
		_fall(delta)
	elif dist > FAR_DISTANCE:
		if randi() % 70 == 0:
			_teleport_far(player)
		_fall(delta)
	elif dist > HIDE_DISTANCE * 0.8:
		if randi() % 70 == 0:
			if TeleportCloser.run(self):
				velocity = Vector3.ZERO
		_fall(delta)
	else:
		move_state += (moved_volume - move_state) * minf(fps / 3.0, 1.0)
		_chase(player, dist, seen, delta)
	_update_drag(dist)

# Idle = 2 (boxed): it trails the MTF leader that contained it, or appears at his side when it is
# far from the player and out of sight.
func _follow_leader(delta: float) -> void:
	var bob := sin(deg_to_rad(GameState.clock_ms() * 0.08)) * 0.02
	visual.position.y = 0.37 + bob
	box.position.y = 0.27 + bob
	box.visible = true
	if target_node == null or not is_instance_valid(target_node):
		return
	var player: CharacterBody3D = GameState.player
	var hidden := false
	if player != null and global_position.distance_to(player.global_position) > HIDE_DISTANCE * 0.7:
		hidden = not _line_of_sight(player)
	if hidden:
		global_position = target_node.global_position + Vector3(0.0, 0.3, 0.0)
		velocity = Vector3.ZERO
		return
	_face(target_node.global_position)
	var gap := global_position.distance_to(target_node.global_position)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var pace := 0.016 * 70.0 * maxf(minf((gap * 2.0 - 1.0) * 0.5, 1.0), -0.5)
	velocity.x = forward.x * pace
	velocity.z = forward.z * pace
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

func _fall(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()

func _chase(player: CharacterBody3D, dist: float, seen: bool, delta: float) -> void:
	var walking := false
	if seen:
		if dist < KILL_DISTANCE:
			# KillTimer >= 0 And (Not GodMode): inside range it only kills; it never steps or turns.
			if not GameState.god_mode:
				_snap(player)
		else:
			_face(player.global_position)
			walking = true
	elif has_enemy:
		var gap := Vector2(enemy_pos.x - global_position.x, enemy_pos.z - global_position.z)
		if gap.length() > 0.5:
			_face(enemy_pos)
			walking = true
			if randi() % 500 == 0:
				has_enemy = false
		else:
			has_enemy = false
	else:
		if randi() % 400 == 0:
			rotation.y = randf() * TAU
		walking = true
	if walking:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		velocity.x = forward.x * speed
		velocity.z = forward.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	NpcGravity.apply(self, delta, GRAVITY, MAX_FALL)
	move_and_slide()
	_try_open_doors()   # only reached while it is free to move: in the chase branch, unseen, within 12

# PointEntity: turn so the face (node forward, -Z) points at the target.
func _face(target: Vector3) -> void:
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat.length() > 0.01:
		rotation.y = atan2(-flat.x, -flat.z)

func _line_of_sight(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var to: Vector3 = player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or from.distance_to(hit.position) > from.distance_to(to) - 0.3

# EntityVisible(n\Collider, Collider): from the centre of 173's collider to the centre of the player's
func _collider_sight(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, 0.32, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 0.3, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or from.distance_to(hit.position) > from.distance_to(to) - 0.3

func _update_drag(dist: float) -> void:
	if drag.stream == null:
		return
	if dist < HIDE_DISTANCE and move_state > 0.02:
		drag.volume_db = linear_to_db(clampf(move_state, 0.001, 1.0))
		if not drag.playing:
			drag.play()
	elif drag.playing:
		drag.stop()

func _scare_cues(player: Node, dist: float, seen: bool) -> void:
	GameState.blur_volume = maxf(maxf(minf((4.0 - dist) / 6.0, 0.9), 0.1), GameState.blur_volume)
	# CurrCameraZoom: the view shudders and zooms when it is close.
	if dist < 3.5:
		player.add_camera_zoom((sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * 15.0 * maxf((3.5 - dist) / 3.5, 0.0))
	var now := GameState.clock_ms()
	if dist < 3.5 and now - _last_scare_ms > 60000 and seen:
		_play_global("SFX/Horror/Horror%d.ogg" % randi_range(3, 4))
		_last_scare_ms = now
	if dist < 1.5 and randi() % 700 == 0:
		_play_here("SFX/SCP/173/Rattle%d.ogg" % randi_range(1, 3))
	if dist < 1.5 and _last_dist > 2.0 and seen:
		player.add_camera_zoom(40.0)
		var audio := get_tree().get_first_node_in_group("audio")
		if audio:
			audio.heartbeat(0.5, 140.0)
		_play_global("SFX/Horror/Horror%d.ogg" % [1, 2, 9, 10, 14][randi() % 5])

func _play_global(relative: String) -> void:
	Sfx.play_global(self, relative)

func _play_here(relative: String) -> void:
	Sfx.play_at(self, relative, 10.0)

# ---- teleporting -------------------------------------------------------------------

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

# NPCs.bb 768-789: with Rand(70) = 1 the first non-door waypoint (in creation order) that passes Rand(5) = 1 and lies 15-25 from the
# player on both axes. Not while the player is in exit1, gatea or the pocket dimension.
func _teleport_far(player: Node3D) -> void:
	var facility := _facility()
	if facility == null:
		return
	var room := facility.room_name_at(player.global_position)
	if room == "exit1" or room == "gatea" or room == "pocketdimension":
		return
	for p in facility.waypoints():
		if randi() % 5 != 0:
			continue
		var dx := absf(player.global_position.x - p.x)
		var dz := absf(player.global_position.z - p.z)
		if dx < 25.0 and dx > 15.0 and dz < 25.0 and dz > 15.0:
			global_position = p + Vector3(0.0, 0.25, 0.0)
			velocity = Vector3.ZERO
			return

func _snap(player: Node) -> void:
	active = false
	Sfx.play_global(self, "SFX/SCP/173/NeckSnap%d.ogg" % randi_range(1, 3))
	# The neck snap also turns the player's head 80-100 degrees (TurnEntity Camera).
	player.rotate_y(deg_to_rad(randf_range(80.0, 100.0)) * (1.0 if randi() % 2 == 0 else -1.0))
	player.kill(_death_message(player))

func _death_message(player: Node3D) -> String:
	var facility := _facility()
	var room := "173"
	if facility != null and facility.active:
		room = facility.room_name_at(player.global_position)
	match room:
		"lockroom", "room2closets", "coffin":
			return "Subject D-9341. Cause of death: Fatal cervical fracture. The surveillance tapes confirm that the subject was killed by SCP-173."
		"173", "start":
			return "Subject D-9341. Cause of death: Fatal cervical fracture. According to Security Chief Franklin who was present at SCP-173's containment chamber during the breach, the subject was killed by SCP-173 as soon as the disruptions in the electrical network started."
		"room2doors":
			return "\"If I'm not mistaken, one of the main purposes of these rooms was to stop SCP-173 from moving further in the event of a containment breach. So, who's brilliant idea was it to put A GODDAMN MAN-SIZED VENTILATION DUCT in there?\""
	return "Subject D-9341. Cause of death: Fatal cervical fracture. Assumed to be attacked by SCP-173."

# UpdateNPCs, the "actively move towards the player" branch (not watched, closer than 12): ~1 in 20 frames, if 173 stands
# within 0.5 of a door button, the door is neither locked nor keycard/code protected and at rest, and the button is in
# reach of a short pick from 0.5 above him (nothing in the way), it opens the door.
func _try_open_doors() -> void:
	if randi() % 20 != 0:
		return
	var facility := _facility()
	var nearby: Array = facility.doors_near(global_position, 1.0) if facility != null else get_tree().get_nodes_in_group("door")
	for node in nearby:
		var door := node as Node3D
		# d\Code = "" and d\KeyCard = 0 (so scanners and keypads stay shut too)
		if door == null or door.locked or door.open or door.keycard != 0 or not door.code.is_empty():
			continue
		if door.openstate > 0.0 and door.openstate < 180.0:
			continue
		for button in door.buttons:
			var d: Vector3 = button.global_position - global_position
			if absf(d.x) < 0.5 and absf(d.z) < 0.5 and _button_in_reach(button.global_position):
				door.npc_open()
				break

# EntityPick(pvt, 0.5) = the button, from a pivot 0.5 above 173 pointed at it.
func _button_in_reach(button: Vector3) -> bool:
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, button)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.is_empty() or from.distance_to(hit.position) > from.distance_to(button) - 0.1)
