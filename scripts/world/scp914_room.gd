extends Node3D
# SCP-914's room (MapSystem.bb FillRoom "914", UpdateEvents.bb Case "914"): the key and the knob (914key.x, 914knob.x, grabbed
# with a click and turned with the mouse's sideways movement, 2.5 degrees per unit), the two booth doors and the refining.
#  - the knob picks the setting by its roll (rough 90, coarse 40, 1:1 0, fine -40, very fine -90) and eases to the nearest one
#  - the key goes from 0 to 180 and, if anything lies loose in the world (the original compares against 200 and 104 metres,
#    so any loose item does), starts the machine: the output door shuts, 2 s later the intake door, the key turns back at 6 s
#  - at 12 s everything within 180 units of the intake is refined (scp914_recipes.gd) and put in the output booth, a player in
#    the intake (within 160) is moved there with the setting's effect; both doors open again
# The event only runs while the player is in the room; doors are the room's fill doors 1 (intake) and 2 (output), door 0 is
# the big keycard door.

const Recipes = preload("res://scripts/items/scp914_recipes.gd")

const RS := MeshLoader.ROOM_SCALE
const ROLL_SIGN := 1.0           # Blitz roll to the node's z rotation (checked against the panel's labels: rough is turned to the left)

var room: FacilityRoom
var key: Node3D
var knob: Node3D
var key_roll := 0.0
var knob_roll := 0.0
var state := 0.0                 # EventState: 0 idle, then frames since the key was turned
var state2 := 0.0                # EventState2: the big door has been opened (the music)
var setting := "1:1"
var refined := 0                 # items refined in the last cycle (tests)
var _grabbed: Node3D = null
var _key_box := AABB()
var _knob_box := AABB()
var _machine_sound: AudioStreamPlayer3D = null

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		knob_roll = facility.scp914_knob_roll
	key = _part("GFX/map/914key.x", 0)
	knob = _part("GFX/map/914knob.x", 1)
	key_roll = 0.0
	_apply_rolls()

func _part(path: String, index: int) -> Node3D:
	var node := Node3D.new()
	var mesh := MeshLoader.load_x(ContentPaths.existing_file(path))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3.ONE * RS
	node.add_child(visual)
	var box := mesh.get_aabb()
	var scaled := AABB(box.position * RS, box.size * RS).grow(0.01)
	if index == 0:
		_key_box = scaled
	else:
		_knob_box = scaled
	node.position = room.fill_objects.get(index, Vector3.ZERO)
	add_child(node)
	return node

func _apply_rolls() -> void:
	key.rotation.z = ROLL_SIGN * deg_to_rad(key_roll)
	knob.rotation.z = ROLL_SIGN * deg_to_rad(knob_roll)

func intake_door() -> Node3D:      # RoomDoors[0]
	return room._fill_doors[1] if room._fill_doors.size() > 2 else null

func output_door() -> Node3D:      # RoomDoors[1]
	return room._fill_doors[2] if room._fill_doors.size() > 2 else null

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# The setting a knob roll stands for, and the roll it settles to.
static func setting_of(roll: float) -> Array:
	var angle := wrapf(roll, 0.0, 360.0)
	if angle < 22.5:
		return ["1:1", 0.0]
	if angle < 67.5:
		return ["coarse", 40.0]
	if angle < 180.0:
		return ["rough", 90.0]
	if angle > 337.5:
		return ["1:1", -1.0]
	if angle > 292.5:
		return ["fine", -40.0]
	return ["very fine", -90.0]

func _loose_items() -> Array:
	var out: Array = []
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			out.append(pickup)
	return out

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or key == null or not facility.active:
		return
	facility.scp914_knob_roll = knob_roll
	if not room.world_bounds().has_point(player.global_position):
		_grabbed = null
		if GameState.music_override == "914":
			GameState.music_override = ""
		return
	var fps := delta * 70.0
	var camera: Camera3D = player.camera
	var big_door: Node3D = room._fill_doors[0] if room._fill_doors.size() > 0 else null
	if big_door != null and big_door.open:
		GameState.give_achievement("914")
		state2 = 1.0
	if state2 == 1.0 and (GameState.music_override.is_empty() or GameState.music_override == "none"):
		GameState.music_override = "914"
	_handle_grab(player, camera)
	_settle_knob(fps)
	if state > 0.0:
		_run_cycle(player, fps)
	_apply_rolls()
	if _machine_sound != null and is_instance_valid(_machine_sound):
		_machine_sound.global_position = knob.global_position

# EntityPick(Camera, 1): the part the view ray reaches within 1 unit.
func _pick(camera: Camera3D) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for part in [key, knob]:
		var box: AABB = _key_box if part == key else _knob_box
		var inverse := (part as Node3D).global_transform.affine_inverse()
		var from: Vector3 = inverse * camera.global_position
		var to: Vector3 = inverse * (camera.global_position - camera.global_transform.basis.z * 1.0)
		if box.intersects_segment(from, to) != null:
			var distance := camera.global_position.distance_to((part as Node3D).global_position)
			if distance < best_distance:
				best_distance = distance
				best = part
	return best

func _handle_grab(player: CharacterBody3D, camera: Camera3D) -> void:
	var picked := _pick(camera)
	if picked != null:
		GameState.hand_icon = true
		if Input.is_action_just_pressed("interact"):
			_grabbed = picked
	if not Input.is_action_pressed("interact"):
		_grabbed = null
	for part in [key, knob]:
		if _grabbed == part:
			if not camera.is_position_in_frustum((part as Node3D).global_position) or camera.global_position.distance_to((part as Node3D).global_position) > 1.0:
				_grabbed = null
	if _grabbed == null or state != 0.0:
		return
	GameState.hand_icon = true
	var turn: float = -player.mouse_speed.x * 2.5
	if _grabbed == key:
		key_roll = wrapf(key_roll + turn, -180.0, 180.0)
		var angle := wrapf(key_roll, 0.0, 360.0)
		GameState.arrow_icons[3] = angle > 181.0
		GameState.arrow_icons[1] = true
		if angle < 90.0:
			key_roll = 1.0
		elif angle < 180.0:
			key_roll = 180.0
		if angle < 181.0 and angle > 90.0 and not _loose_items().is_empty():
			_start()
	else:
		knob_roll = wrapf(knob_roll + turn, -180.0, 180.0)
		var angle := wrapf(knob_roll, 0.0, 360.0)
		GameState.arrow_icons[3] = true
		GameState.arrow_icons[1] = true
		if angle > 90.0:
			if angle < 180.0:
				knob_roll = 90.0
			elif angle < 270.0:
				knob_roll = -90.0

func _settle_knob(fps: float) -> void:
	if _grabbed == knob and state == 0.0:
		return
	var pair := setting_of(knob_roll)
	setting = str(pair[0])
	knob_roll = wrapf(knob_roll + (float(pair[1]) - knob_roll) * minf(fps / 20.0, 1.0), -180.0, 180.0)

func _start() -> void:
	state = 1.0
	_machine_sound = Sfx.play_at(knob, "SFX/SCP/914/Refining.ogg", 10.0)
	var out := output_door()
	if out != null:
		Sfx.play_at(out, "SFX/SCP/914/DoorClose.ogg", 14.0)

func start_for_test() -> void:
	_start()

func _run_cycle(player: CharacterBody3D, fps: float) -> void:
	var before := state
	state += fps
	var intake := intake_door()
	var output := output_door()
	if output != null:
		output.open = false
	if state > 70.0 * 2.0 and intake != null:
		if intake.open:
			Sfx.play_at(intake, "SFX/SCP/914/DoorClose.ogg", 14.0)
		intake.open = false
	var booth: Vector3 = room.object_point(2)
	var inside: bool = _flat_distance(player.global_position, booth) < 170.0 * RS
	if inside:
		if setting == "rough" or setting == "coarse":
			if state > 70.0 * 2.6 and before < 70.0 * 2.6:
				Sfx.play_global(self, "SFX/SCP/914/PlayerDeath.ogg")
		if state > 70.0 * 3.0:
			player.blink_timer = -10.0
			if setting == "rough":
				if _machine_sound != null and is_instance_valid(_machine_sound):
					_machine_sound.stop()
				player.kill("\"A heavily mutilated corpse found inside the output booth of SCP-914. DNA testing identified the corpse as Class D Subject D-9341. The subject had obviously been \"refined\" by SCP-914 on the \"Rough\" setting, but we are still confused as to how he ended up inside the intake booth and who or what wound the key.\"")
			elif before < 70.0 * 3.0:
				Sfx.play_global(self, "SFX/SCP/914/PlayerUse.ogg")
	if state > 70.0 * 6.0:
		key_roll = wrapf(key_roll + angle_difference(deg_to_rad(key_roll), 0.0) * 57.29578 * minf(fps / 10.0, 1.0), -180.0, 180.0)
	else:
		key_roll = 180.0
	if state > 70.0 * 12.0:
		_finish(player)

func _finish(player: CharacterBody3D) -> void:
	var booth: Vector3 = room.object_point(2)
	var output: Vector3 = room.object_point(3)
	refined = 0
	for pickup in _loose_items():
		if _flat_distance(pickup.global_position, booth) < 180.0 * RS:
			_refine(pickup, output)
	if _flat_distance(player.global_position, booth) < 160.0 * RS:
		var hud := get_tree().get_first_node_in_group("hud")
		match setting:
			"coarse":
				GameState.injuries = 4.0
				if hud != null:
					hud.message("You notice countless small incisions all around your body. They are bleeding heavily.", 8.0)
			"1:1":
				GameState.invert_mouse = not GameState.invert_mouse
			"fine", "very fine":
				GameState.super_man = true
		GameState.blur_timer = 1000.0
		player.global_position = output + Vector3(0.0, 1.0, 0.0)
		player.velocity = Vector3.ZERO
		(get_tree().get_first_node_in_group("facility") as FacilityMap).after_teleport()
	var intake := intake_door()
	var out := output_door()
	if intake != null:
		intake.open = true
		Sfx.play_at(intake, "SFX/SCP/914/DoorOpen.ogg", 14.0)
	if out != null:
		out.open = true
		Sfx.play_at(out, "SFX/SCP/914/DoorOpen.ogg", 14.0)
	key_roll = 0.0
	state = 0.0

# Use914 for one item.
func _refine(pickup: Node3D, output: Vector3) -> void:
	GameState.refined_items += 1
	refined += 1
	var item_name := str(pickup.get_meta("item_name", ""))
	var tempname := str(pickup.get_meta("tempname", ""))
	var plan := Recipes.refine(item_name, tempname, setting, GameState.other_factors(), GameState.achievements_unlocked())
	if plan.panel:
		plan = _panel_plan(pickup, output, plan)
	var world: Node = GameState.player.get_parent()
	if not plan.decal.is_empty():
		var id := int(plan.decal[0])
		var texture := "GFX/items/INVpaperstrips.jpg" if id == 7 else "GFX/decal%d.png" % (id + 1)
		GrowingDecal.make(world, Vector3(output.x, room.global_position.y + 8.0 * RS + float(plan.decal[3]), output.z), texture, float(plan.decal[1]), 0.0, float(plan.decal[2]), false)
	if str(plan.sound) != "":
		Sfx.play_global(self, str(plan.sound))
	if plan.get("remove_513_1", false):
		for ghost in get_tree().get_nodes_in_group("scp513_1"):
			ghost.queue_free()
	var color := Color(float(pickup.get_meta("cr", 1.0)), float(pickup.get_meta("cg", 1.0)), float(pickup.get_meta("cb", 1.0)))
	var spread := Vector2(0.9, 1.1) if setting == "fine" else Vector2(0.5, 1.5)
	for entry in plan.outputs:
		var made: Node3D
		if str(entry[1]) == "cup":
			var tint := {"ca": float(pickup.get_meta("ca", 1.0))}
			for key in ["cr", "cg", "cb"]:
				var c := float(pickup.get_meta(key, 1.0))
				tint[key] = 1.0 - c if setting == "1:1" else minf(c * randf_range(spread.x, spread.y), 1.0)
			made = RoomFill.make_pickup(item_name, "cup", tint)
		else:
			made = RoomFill.make_pickup(str(entry[0]), str(entry[1]))
		made.set_meta("state", float(entry[2]))
		world.add_child(made)
		var spot := output + Vector3(plan.offset.x, plan.offset.y, -plan.offset.z)
		made.global_position = spot
	if plan.explode:
		GameState.explosion_timer = 135.0
	match str(plan.npc):
		"008":
			var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
			if facility != null:
				facility.spawn_zombie008(output, 1)
		"1499":
			var home := get_tree().get_first_node_in_group("facility") as FacilityMap
			if home != null and home.dimension != null:
				var inhabitant: Node = home.dimension.spawn_loose(output)
				inhabitant.always_hostile = true
				inhabitant.set_state(1)
				inhabitant._voice_play("SFX/SCP/1499/Triggered.ogg")
	if plan.remove:
		_destroy(pickup)
	elif plan.outputs.is_empty() and plan.decal.is_empty():
		pickup.global_position = output       # Default: PositionEntity(item\collider, x, y, z) / ResetEntity
		pickup.wake()

# Metal Panel / SCP-148 Ingot, 1:1 to very fine: fuse with a gas mask, vest or hazmat suit lying near (RefineWithPanel).
func _panel_plan(pickup: Node3D, output: Vector3, plan: Dictionary) -> Dictionary:
	var other: Node3D = null
	for candidate in _loose_items():
		if candidate == pickup:
			continue
		if _flat_distance(candidate.global_position, pickup.global_position) < 180.0 * RS or _flat_distance(candidate.global_position, output) < 180.0 * RS:
			other = candidate
			break
	if other != null:
		var fused := Recipes.panel_fusion(str(other.get_meta("tempname", "")))
		if not fused.is_empty():
			_destroy(other)
			plan.remove = true
			plan.outputs = [fused]
		return plan
	if str(pickup.get_meta("item_name", "")) == "SCP-148 Ingot":
		plan.remove = true
		plan.outputs = [["Metal Panel", "scp148", 0.0]]
	return plan

func _destroy(pickup: Node) -> void:
	if pickup.has_meta("fill_id"):
		GameState.taken_items[str(pickup.get_meta("fill_id"))] = true
	pickup.remove_from_group("pickup")
	pickup.queue_free()
