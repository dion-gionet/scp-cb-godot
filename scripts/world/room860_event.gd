extends Node3D
# SCP-860's test chamber (UpdateEvents.bb Case "room860", MapSystem.bb FillRoom "room860"): a locked wooden door in the room;
# with the SCP-860 key selected, a click within 1 m opens it onto the forest that hangs 30 m above (forest.gd). In the forest:
#  - the fog is close and blue-grey (0.5-8, 98/133/162; darker as the monster closes in), the camera sees 8.5, 106 does nothing,
#    the steps and the ambience are the forest's, the music is "8601" ("8601Cancer" while the monster hunts)
#  - the player is kept between 1.5 below and 0.5 above the forest's level: below it the player falls to death
#  - the monster (scp_860.gd) is sent every 500 frames of walking (the timer counts 1 + the player's speed a frame while the monster
#    is hidden or 20 m away): after 3000 frames (2500 on the hard levels) a growing chance makes it hunt (state 2, and the timer
#    drops by 1000-2000); otherwise it only shows itself (state 1)
#  - the doors at either end are the way out; only the far one (the one the player did not come in by) opens, the other "will not budge"
# The three Log documents lie in the forest, one in each third.

const RS := 8.0 / 2048.0
const Scp860 = preload("res://scripts/npc/scp_860.gd")

var room: FacilityRoom
var forest: Node3D = null
var monster: CharacterBody3D = null
var wooden_door: Node3D            # Objects[3]: the door of the chamber (it never moves; the forest is behind it)
var wooden_door_b: Node3D          # Objects[4]
var door_frame: Node3D             # Objects[2]
var _previous_far := 4000.0
var _view_set := false             # the forest's fog, camera range, music and steps are applied

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	door_frame = _wooden(Vector3(184.0 * RS, 0.0, 0.0), Vector3(45.0, 45.0, 80.0) * RS, 0.0, "GFX/map/forest/door_frame.b3d")
	wooden_door = _wooden(Vector3(112.0 * RS, 0.0, -0.05), Vector3(46.0, 45.0, 46.0) * RS, 0.0, "GFX/map/forest/door.b3d")
	wooden_door_b = _wooden(Vector3(256.0 * RS, 0.0, 0.05), Vector3(46.0, 45.0, 46.0) * RS, PI, "GFX/map/forest/door.b3d")
	if facility == null:
		return
	# CreateMap made the forest inside FillRoom: the map generator kept its grid and the generator state PlaceForest began with
	if facility.forest_grid.is_empty():
		var record: Dictionary = facility.rooms.by_grid.get(room.room_key, {})
		if record.has("forest_grid"):
			facility.forest_grid = record.forest_grid
			facility.forest_seed = int(record.forest_state)
		else:
			var rng := BlitzRng.new()
			rng.seed_rnd(int(facility.generator.seed_value))
			facility.forest_grid = Forest.generate_grid(rng)
			facility.forest_seed = rng.state
	forest = Forest.new()
	forest.top_level = true
	room.get_parent().add_child(forest)    # not parented to the room (FillRoom, MapSystem.bb 2152): the event hides and shows it, UpdateRooms does not
	forest.global_position = room.global_position + Vector3(0.0, 30.0, 0.0)
	var detail_rng := BlitzRng.new()
	detail_rng.state = facility.forest_seed
	forest.build(facility.forest_grid, detail_rng)
	forest.set_shown(false)
	var index := 0
	for entry in forest.logs:
		var id := "forest|log%d" % index
		index += 1
		if GameState.taken_items.has(id):
			continue
		var pickup := RoomFill.make_pickup(str(entry.name), "paper")
		pickup.set_meta("fill_id", id)
		add_child(pickup)
		pickup.top_level = true
		pickup.global_position = entry.pos

func _wooden(at: Vector3, scale_value: Vector3, yaw: float, mesh_path: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	var visual := MeshInstance3D.new()
	visual.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file(mesh_path))
	visual.scale = scale_value
	holder.add_child(visual)
	add_child(holder)
	return holder

func _exit_tree() -> void:
	_restore_view(null)
	if GameState.step_set == 2:
		GameState.step_set = 0

func _inside(player: Node3D, facility: FacilityMap) -> bool:
	if facility.events.room860.state == 1.0:
		return true       # PlayerRoom stays the chamber while the player is in the forest above it
	var bounds: AABB = room.world_bounds()
	var p := player.global_position
	if p.x < bounds.position.x or p.x > bounds.end.x or p.z < bounds.position.z or p.z > bounds.end.z:
		return false
	return bounds.has_point(p)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or forest == null or not facility.active:
		return
	var fps := delta * 70.0
	if _view_set and facility.events.room860.state != 1.0:
		_restore_view(player)      # out of the forest by another way than its door (the console's teleport)
	if not _inside(player, facility):
		forest.set_shown(false)
		return
	if facility.events.room860.state == 1.0:
		_in_forest(player, facility, fps)
	else:
		_in_room(player, facility)

func _in_room(player: CharacterBody3D, facility: FacilityMap) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if not facility.contained_106 and facility.scp106 != null and is_instance_valid(facility.scp106):
		facility.scp106.idle = false
	forest.set_shown(false)
	var door_at := wooden_door.global_position
	var flat := Vector2(door_at.x - player.global_position.x, door_at.z - player.global_position.z).length()
	if flat >= 1.0:
		return
	GameState.hand_icon = true
	if not Input.is_action_just_pressed("interact"):
		return
	if hud.selected_tempname() != "scp860":
		Sfx.play_global(self, "SFX/Door/WoodenDoorBudge.ogg")
		hud.message("The door will not budge.", 5.0)
		return
	Sfx.play_global(self, "SFX/Door/WoodenDoorOpen.ogg")
	hud.deselect()
	player.blink_timer = -10.0
	facility.events.room860.state = 1.0
	facility.events.room860.state3 = 0.0
	if monster == null:
		monster = Scp860.new()
		monster.forest = forest
		monster.name = "SCP860_2"
		add_child(monster)
		monster.top_level = true
	monster.state = 0
	facility.events.room860.light = GameState.secondary_light
	GameState.secondary_light = 1.0
	# the door on the far side of the room from the player's view of it, as the original reckons
	var to_room: Vector3 = room.global_position - player.camera.global_position
	var yaw := rad_to_deg(atan2(-to_room.x, -to_room.z)) - rad_to_deg(room.rotation.y)
	yaw = fposmod(yaw, 360.0)
	var index := 1
	facility.events.room860.state2 = 0.0
	if yaw > 90.0 and yaw < 270.0:
		index = 0
		facility.events.room860.state2 = 1.0
	var door: Node3D = forest.doors[index]
	var eye_height := player.global_position.y - room.global_position.y
	player.global_position = Vector3(door.global_position.x, door.global_position.y + eye_height + 0.5, door.global_position.z)
	player.rotation.y = deg_to_rad(180.0 * index)
	player.global_position += player.global_transform.basis * Vector3(-0.5, 0.0, -0.5)
	player.velocity = Vector3.ZERO
	forest.set_shown(true)
	forest.update_visible(player.global_position)

func _in_forest(player: CharacterBody3D, facility: FacilityMap, fps: float) -> void:
	var s := GameState
	var hud := get_tree().get_first_node_in_group("hud")
	s.step_set = 2
	if facility.scp106 != null and is_instance_valid(facility.scp106):
		facility.scp106.idle = true
	forest.set_shown(true)
	forest.update_visible(player.global_position)
	if monster != null:
		if (monster.state2 == 1.0 and monster.state > 1) or monster.state > 2:
			s.music_override = "8601Cancer"
		else:
			s.music_override = "8601"
	# the fall, and the forest's ceiling
	if not s.noclip:
		var level: float = forest.global_position.y
		if player.global_position.y <= level - 1.5:
			player.kill("")
			player.blink_timer = -2.0
		elif player.global_position.y > level + 0.5:
			player.global_position.y += ((level + 0.5) - player.global_position.y) * minf(fps, 1.0)
	# the monster is sent
	if monster != null:
		var distance := monster.global_position.distance_to(player.global_position)
		if monster.state == 0 or distance > 20.0:
			var before: float = facility.events.room860.state3
			facility.events.room860.state3 += (1.0 + player.curr_speed / 70.0) * fps
			var aggressive := 1 if s.aggressive_npcs() else 0
			if fmod(facility.events.room860.state3, 500.0) < 10.0 and fmod(before, 500.0) > 490.0:
				if facility.events.room860.state3 > 3000.0 - 500.0 * aggressive and randf_range(0.0, 10000.0 + 500.0 * aggressive) < facility.events.room860.state3:
					monster.state = 2
					monster.global_position = Vector3(0.0, -110.0, 0.0)
					facility.events.room860.state3 -= randf_range(1000.0, 2000.0 - 500.0 * aggressive)
				else:
					monster.state = 1
					monster.global_position = Vector3(0.0, -110.0, 0.0)
	# the doors
	for i in 2:
		var door: Node3D = forest.doors[i]
		if door == null:
			continue
		if player.global_position.distance_to(door.global_position) < 0.5 and _in_view(player.camera, door):
			s.hand_icon = true
			if Input.is_action_just_pressed("interact"):
				if float(i) == facility.events.room860.state2:
					_leave(player, facility, hud)
					return
				else:
					Sfx.play_global(self, "SFX/Door/WoodenDoorBudge.ogg")
					hud.message("The door will not budge.", 5.0)
	# the look
	var x := 2.0
	if monster != null:
		x = maxf(1.0 - monster.state3 / 300.0, 0.1)
	s.fog_color = Color(minf(98.0 * x / 255.0, 1.0), minf(133.0 * x / 255.0, 1.0), minf(162.0 * x / 255.0, 1.0))
	s.fog_override = Vector4(0.5, 8.0, 0.0, 0.0)
	_view_set = true
	if player.camera.far != 8.5:
		_previous_far = player.camera.far
		player.camera.far = 8.5

func _leave(player: CharacterBody3D, facility: FacilityMap, hud: Node) -> void:
	player.blink_timer = -10.0
	Sfx.play_global(self, "SFX/Door/WoodenDoorOpen.ogg")
	var out: Vector3 = door_frame.global_position
	player.global_position = Vector3(out.x, room.global_position.y + 0.5, out.z)
	player.rotation.y = room.rotation.y + deg_to_rad(180.0 * facility.events.room860.state2)
	player.global_position += player.global_transform.basis * Vector3(0.0, 0.0, -1.5)
	player.velocity = Vector3.ZERO
	GameState.secondary_light = facility.events.room860.light
	facility.events.room860.state = 0.0
	facility.events.room860.state3 = 0.0
	forest.set_shown(false)
	_restore_view(player)
	if monster != null:
		monster.state = 0

func _restore_view(player: Node3D) -> void:
	_view_set = false
	if GameState.fog_override.x == 0.5:
		GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	if GameState.music_override in ["8601", "8601Cancer"]:
		GameState.music_override = ""
	GameState.step_set = 0
	if player != null and player.camera != null:
		player.camera.far = _previous_far

func _in_view(camera: Camera3D, door: Node3D) -> bool:
	var visual := door.get_child(0) as MeshInstance3D
	if visual == null or visual.mesh == null:
		return camera.is_position_in_frustum(door.global_position)
	return EntityInView.mesh(camera, visual)
