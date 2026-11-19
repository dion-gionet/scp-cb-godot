extends Node3D
# room2storage, SCP-970's corridor (UpdateEvents.bb Case "room2storage", MapSystem.bb FillRoom "room2storage"): six doors in a row.
# Walking more than 2.85 m from the middle (730 units) carries the player 4 m back (1024 units) and moves the door beyond with them
# (RoomDoors[1] / [2] take the state of [3] / [4] and the other way round), so the corridor never ends. Each such step counts
# EventState up and, at some counts:
#   2 an inventory slot is emptied    5 +0.3 injuries    10 a stain    14 the first paper becomes another (1 in 6 each)    18 a strange
#   note lies by the wall    25 a corpse at the end    30 a slot becomes the note    35 four stains grow on the ceiling    40 the radio
#   50 a guard stands behind (gone at 52)    ... and 1 step in 10 a sound of the facility.
# Items near the middle that the player drops come in three (one 4 m either side); picking one up removes the others. The light is
# halved in the room (the corpse's end darker), the doors 1 and 4 stay locked while 173 or 106 is within 8. EventState is kept by
# facility.ambient (st.s = EventState, st.s2 = the lock timer).

const RS := 8.0 / 2048.0

const STEP := 1024.0 * RS
const EDGE := 730.0 * RS
const ITEM_EDGE := 264.0 * RS

var room: FacilityRoom
var corpse: CharacterBody3D = null
var guard: CharacterBody3D = null
var _copies: Array = []               # [{"all": [the item and its two copies]}]
var _voice: AudioStreamPlayer3D = null

func build(room_node: FacilityRoom) -> void:
	room = room_node

func _exit_tree() -> void:
	if GameState.light_dim > 0.0:
		GameState.light_dim = 0.0

func _angle() -> float:
	return room.rotation.y

# the room's point at a distance along the yaw (Blitz Cos / Sin of the angle, z flipped)
func _along(angle_degrees: float, distance_units: float) -> Vector3:
	var radians := deg_to_rad(angle_degrees)
	return room.global_position + Vector3(cos(radians), 0.0, -sin(radians)) * distance_units * RS

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active:
		return
	var fps := delta * 70.0
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	var here: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if not here:
		return
	if corpse == null or not is_instance_valid(corpse) or (guard == null and st.s >= 50.0 and st.s < 52.0):
		_adopt(facility)       # after a load
	_locks(facility, player, st, fps)
	GameState.light_dim = 0.5
	var local: Vector3 = room.to_local(player.global_position)
	var moved := false
	if local.x > EDGE:
		_slide_doors(-1)
		player.global_position = room.to_global(Vector3(local.x - STEP, local.y, local.z))
		moved = true
	elif local.x < -EDGE:
		_slide_doors(1)
		player.global_position = room.to_global(Vector3(local.x + STEP, local.y, local.z))
		moved = true
	if moved:
		GameState.give_achievement("970")
		_wrap_items(player)
		st.s += 1.0
		_count(facility, player, int(st.s))
		if randi_range(1, 10) == 1:
			var audio := get_tree().get_first_node_in_group("audio")
			if audio != null:
				audio.play_ambient_global(randi_range(0, 2))
	else:
		_unease(player, fps)
		_item_copies()
	_corpse_end(player, st)

func _adopt(facility: FacilityMap) -> void:
	for human in facility.humans:
		if not is_instance_valid(human) or human.global_position.distance_to(room.global_position) > 8.0:
			continue
		match str(human.get_meta("role", "")):
			"corpse":
				corpse = human
			"guard":
				guard = human

# Curr173 / Curr106 within 8 lock the middle doors (the MTF loop of the original tests 173 again and adds nothing)
func _locks(facility: FacilityMap, player: CharacterBody3D, st: Dictionary, fps: float) -> void:
	if st.s2 <= 0.0:
		var door_1: Node3D = room.door_slots.get(1)
		var door_4: Node3D = room.door_slots.get(4)
		door_1.locked = false
		door_4.locked = false
		var near_173: bool = GameState.scp173 != null and is_instance_valid(GameState.scp173) and player.global_position.distance_to(GameState.scp173.global_position) < 8.0
		var near_106: bool = facility.scp106 != null and is_instance_valid(facility.scp106) and player.global_position.distance_to(facility.scp106.global_position) < 8.0
		if near_173 or near_106:
			door_1.locked = true
			door_4.locked = true
		st.s2 = 70.0 * 5.0
	else:
		st.s2 -= fps

# direction -1: the player went out at +x: doors 1, 2 take 3, 4's state; +1: doors 3, 4 take 1, 2's
func _slide_doors(direction: int) -> void:
	for i in [1, 2]:
		var from_index: int = i + 2 if direction < 0 else i
		var to_index: int = i if direction < 0 else i + 2
		var source: Node3D = room.door_slots[from_index]
		var target: Node3D = room.door_slots[to_index]
		target.open = source.open
		target.openstate = source.openstate
		target.leaf_a.position = source.leaf_a.position
		if source.leaf_b != null and target.leaf_b != null:
			target.leaf_b.position = source.leaf_b.position
		source.open = false
		source.openstate = 0.0
		source.leaf_a.position = source._closed_a
		if source.leaf_b != null:
			source.leaf_b.position = source._closed_b

func _wrap_items(player: CharacterBody3D) -> void:
	for node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(node) or node.global_position.distance_to(player.global_position) >= 5.0:
			continue
		var at: Vector3 = room.to_local(node.global_position)
		if at.x > ITEM_EDGE:
			node.global_position = room.to_global(Vector3(at.x - STEP, at.y, at.z))
		elif at.x < -ITEM_EDGE:
			node.global_position = room.to_global(Vector3(at.x + STEP, at.y, at.z))

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _slot_template(item_name: String) -> Dictionary:
	var template := RoomFill.item_template(item_name, "paper")
	return {"tempname": "paper", "icon": str(template.get("icon", "GFX/items/INVpaper.jpg")), "state": 0.0}

func _count(facility: FacilityMap, player: CharacterBody3D, count: int) -> void:
	var hud := _hud()
	var world := get_parent()
	match count:
		2:
			var slot := randi_range(1, 10)
			if slot < hud.items.size() and not hud.items[slot].is_empty():
				hud.items[slot] = ""
				hud.item_data[slot] = {}
		5:
			GameState.injuries += 0.3
		10:
			GrowingDecal.make(world, _along(room.rotation_degrees.y - 90.0, 760.0) + Vector3(0.0, 0.0005, 0.0), "GFX/decal4.png", 0.5, 0.0, 0.8, false)
		14:
			for i in hud.items.size():
				if hud.item_data[i].get("tempname", "") == "paper" and not hud.items[i].is_empty():
					hud.items[i] = ""
					hud.item_data[i] = {}
					for item_name in RoomFill.item_order():
						var template := RoomFill.item_template(str(item_name))
						if str(template.get("tempname", "")) == "paper" and randi_range(1, 6) == 1:
							hud.items[i] = str(item_name)
							hud.item_data[i] = _slot_template(str(item_name))
							break
					break
		18:
			var note := RoomFill.make_pickup("Strange Note", "paper")
			world.add_child(note)
			note.global_position = room.to_global(Vector3(-344.0 * RS, 176.0 * RS, -272.0 * RS))
		25:
			var at := _along(room.rotation_degrees.y - 90.0, 760.0)
			corpse = facility.spawn_human(HumanNpc.Kind.CLASS_D, NpcGravity.feet(Vector3(at.x, room.global_position.y + 0.35, at.z), NpcGravity.CLASS_D_RADIUS), 1)
			corpse.rotation.y = deg_to_rad(room.rotation_degrees.y - 200.0)
			corpse.set_frame(80.0)
			corpse.state = 10
			corpse.set_meta("role", "corpse")
		30:
			var slot := randi_range(0, 9)
			hud.items[slot] = "Strange Note"
			hud.item_data[slot] = _slot_template("Strange Note")
		35:
			for i in 4:
				var ceiling := Vector3(room.global_position.x + randf_range(-2.0, 2.0), room.global_position.y + 700.0 * RS, room.global_position.z + randf_range(-2.0, 2.0))
				GrowingDecal.make(world, ceiling, "GFX/decal8.png", 0.05, 0.0005, 0.8, false, Vector3(PI * 0.5, randf() * TAU, 0.0))
		40:
			Sfx.play_global(self, "SFX/Radio/franklin4.ogg")
		60:
			if not GameState.halloween and GameState.scp173 != null and is_instance_valid(GameState.scp173):
				GameState.scp173.set_skin(true)        # only the picture changes; the console's halloween flag is untouched
		50:
			var behind := _along(room.rotation_degrees.y + 90.0, 600.0)
			guard = facility.spawn_human(HumanNpc.Kind.GUARD, NpcGravity.feet(Vector3(behind.x, room.global_position.y + 0.35, behind.z)))
			guard.state = 7
			guard.set_meta("role", "guard")
		52:
			if guard != null and is_instance_valid(guard):
				facility.remove_human(guard)
			guard = null

# no step this frame: the corpse unsettles anyone who sees it; the guard turns to the player
func _unease(player: CharacterBody3D, fps: float) -> void:
	if corpse != null and is_instance_valid(corpse) and corpse.global_position.distance_to(player.global_position) < 3.0:
		if player.camera.is_position_in_frustum(corpse.global_position + Vector3(0.0, 0.5, 0.0)):
			player.add_camera_zoom((sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * 15.0)
			var audio := get_tree().get_first_node_in_group("audio")
			if audio != null:
				audio.heartbeat(0.3, 120.0)
	if guard != null and is_instance_valid(guard):
		var flat := Vector2(player.global_position.x - guard.global_position.x, player.global_position.z - guard.global_position.z)
		if flat.length() > 0.001:
			guard.rotation.y += wrapf(atan2(-flat.x, -flat.y) - guard.rotation.y, -PI, PI) / 35.0 * fps

# a dropped item near the middle comes in three; taking any of the three takes all
func _item_copies() -> void:
	for group in _copies.duplicate():
		var members: Array = group
		var gone := false
		for member in members:
			if not is_instance_valid(member):
				gone = true
		if gone:
			for member in members:
				if is_instance_valid(member):
					member.queue_free()
			_copies.erase(group)
	for node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(node) or not node.has_meta("dropped") or node.has_meta("tripled"):
			continue
		var at: Vector3 = room.to_local(node.global_position)
		if absf(at.x) >= ITEM_EDGE or absf(at.z) > 3.5 or at.y > 4.0:
			continue
		node.set_meta("tripled", true)
		var members: Array = [node]
		for side in [-1.0, 1.0]:
			var copy := RoomFill.make_pickup(str(node.get_meta("item_name", "")), str(node.get_meta("tempname", "paper")), _item_data(node))
			node.get_parent().add_child(copy)
			copy.global_position = room.to_global(Vector3(at.x + STEP * side, at.y, at.z))
			copy.rotation = node.rotation
			copy.set_meta("tripled", true)
			members.append(copy)
		_copies.append(members)

# what an item holds (a cup's drink, a clipboard's papers), so that its copies are the same
func _item_data(node: Node) -> Dictionary:
	var data := {}
	for key in ["state", "cr", "cg", "cb", "ca", "pose"]:
		if node.has_meta(key):
			data[key] = float(node.get_meta(key))
	if node.has_meta("inv"):
		data["inv"] = (node.get_meta("inv") as Array).duplicate(true)
	return data

# past count 26 near the corpse its sound plays; below 30 the light is darker still, past 60 it floats and turns
func _corpse_end(player: CharacterBody3D, st: Dictionary) -> void:
	if st.s <= 26.0 or corpse == null or not is_instance_valid(corpse):
		return
	if absf(player.global_position.x - room.global_position.x) >= 8.0 or absf(player.global_position.z - room.global_position.z) >= 8.0:
		return
	if _voice == null or not is_instance_valid(_voice):
		_voice = Sfx.play_at(corpse, "SFX/SCP/970/Corpse.ogg", 10.0)
		if _voice != null:
			_voice.finished.connect(func() -> void: if is_instance_valid(_voice): _voice.play())
	if st.s < 30.0:
		GameState.light_dim = 0.6
	elif st.s > 60.0:
		corpse.set_physics_process(false)      # DropSpeed = 0: it hangs in the air
		corpse.animate(80.0, 61.0, -0.02, get_physics_process_delta_time() * 70.0, false)
		corpse.global_position.y = lerpf(corpse.global_position.y, room.global_position.y + 1.5 + sin(GameState.clock_ms() / 20.0 * PI / 180.0) * 0.1, minf(get_physics_process_delta_time() * 70.0 / 50.0, 1.0))
		corpse.rotation.y += deg_to_rad(0.1) * get_physics_process_delta_time() * 70.0
