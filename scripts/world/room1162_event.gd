extends Node3D
# SCP-1162's room (UpdateEvents.bb Case "room1162"): a hole in the wall (Objects[0]). Reaching into it (within 0.75, a click, with nothing
# lying at it) takes a random one of the player's ten slots (looking from that slot on for one that is filled):
#  - a filled slot is traded (EventState3 1): the item is taken and one of a kind it is "good for" (IsItemGoodFor1162, in the template
#    order of the original, each with its own chance) drops out at (976, 128, -640); until one comes the trade is tried again each frame
#  - with the slot (and the ones after it) empty, 1162 takes something from the body (state 2): +5 injuries, a stain on the floor and an item
#    (over 15 injuries the player dies: "right lung was missing")
#  - 1 time in 8 on the way a "memory" is the trade instead (state 3 / 3.1: a lost key, the disciplinary hearing, a coin, a movie
#    ticket or an old badge, if the game does not have it yet); with an empty slot it costs injuries too
# EventState (the memory), EventState2 (the slot) and EventState3 are kept by facility.ambient.

const RS := 8.0 / 2048.0

const SLOTS := 10
const MEMORIES := {
	1: ["Lost Key", "key"], 2: ["Disciplinary Hearing DH-S-4137-17092", "oldpaper"], 3: ["Coin", "coin"],
	4: ["Movie Ticket", "ticket"], 5: ["Old Badge", "badge"],
}
const DEATH := "A dead Class D subject was discovered within the containment chamber of SCP-1162. An autopsy revealed that his right lung was missing, which suggests interaction with SCP-1162."

var room: FacilityRoom

func build(room_node: FacilityRoom) -> void:
	room = room_node

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

# IsItemGoodFor1162
static func good_for_1162(item_name: String, tempname: String) -> bool:
	match tempname:
		"key1", "key2", "key3", "misc", "420", "cigarette", "vest", "finevest", "gasmask", "radio", "18vradio", "clipboard", "eyedrops", "nvgoggles", "drawing":
			return true
	if tempname != "paper":
		return false
	if item_name.contains("Leaflet"):
		return false
	return not item_name.contains("Note") and not item_name.contains("Log")

func _slot_filled(index: int) -> bool:
	return not _hud().items[index].is_empty()

# the hole's pivot, and where the traded things drop out (976, 128, -640 in the room's space)
func _hole() -> Vector3:
	return room.object_point(0)

func _drop_point() -> Vector3:
	return room.to_global(Vector3(976.0 * RS, 128.0 * RS, 640.0 * RS))

func _item_exists(item_name: String) -> bool:
	var hud := _hud()
	for i in SLOTS:
		if hud.items[i] == item_name:
			return true
	for node in get_tree().get_nodes_in_group("pickup"):
		if str(node.get_meta("item_name", "")) == item_name:
			return true
	return false

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active or player.dead:
		return
	if str(facility.record_at(player.global_position).get("key", "")) != room.room_key:
		return
	var hud := _hud()
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	st.s = 0.0                       # the memory is only picked on the click
	var hole := _hole()
	if hole == Vector3.INF:
		return
	var free := true
	for node in get_tree().get_nodes_in_group("pickup"):
		if (node as Node3D).is_inside_tree() and (node as Node3D).global_position.distance_to(hole) < 0.75:
			free = false
	var grabbed := false
	if (player.global_position + Vector3(0.0, 0.45, 0.0)).distance_to(hole) < 0.75 and free and not hud.inventory_open:
		GameState.hand_icon = true
		grabbed = Input.is_action_just_pressed("interact")
	if grabbed:
		_choose(st)
	if st.s3 == 1.0:
		_trade(st)
	elif st.s3 == 2.0:
		_take_from_body(st)
	elif st.s3 >= 3.0:
		_memory(st, player)

# the slot and the kind of trade
func _choose(st: Dictionary) -> void:
	var slot := randi_range(0, SLOTS - 1)
	st.s2 = float(slot)
	if _slot_filled(slot):
		st.s3 = 1.0
		return
	for i in SLOTS:
		var index := (i + int(st.s2)) % SLOTS
		var empty := not _slot_filled(index)
		if not empty:
			st.s2 = float(index)
		if randi_range(1, 8) == 1:
			st.s3 = 3.1 if empty else 3.0
			st.s = float(randi_range(1, 5))
			var memory: Array = MEMORIES[int(st.s)]
			var exists := _item_exists(str(memory[0]))
			if exists:
				st.s3 = 1.0
				st.s = 0.0
			if not exists and not empty:
				break
		else:
			if empty:
				st.s3 = 2.0
			else:
				st.s3 = 1.0
				break

func _drop_item(item_name: String, tempname: String) -> void:
	var pickup := RoomFill.make_pickup(item_name, tempname)
	GameState.player.get_parent().add_child(pickup)
	pickup.global_position = _drop_point()

func _remove_slot(index: int) -> void:
	var hud := _hud()
	if hud.selected == index:
		hud.deselect()
	hud.items[index] = ""
	hud.item_data[index] = {}

# the trade of a filled slot: the templates in the original's order, each kind of item with its own chance
func _trade(st: Dictionary) -> void:
	var hud := _hud()
	var slot := int(st.s2)
	if not _slot_filled(slot):
		st.s3 = 0.0
		return
	var given := str(hud.item_data[slot].get("tempname", ""))
	for entry in RoomFill.item_order():
		var item_name := str(entry[0])
		var tempname := str(entry[1])
		if not good_for_1162(item_name, tempname):
			continue
		var create := false
		match given:
			"key":
				create = tempname == "key1" or (tempname == "key2" and randi_range(1, 2) == 1)
			"paper", "oldpaper":
				create = tempname == "paper" and randi_range(1, 12) == 1
			"gasmask", "gasmask3", "supergasmask", "hazmatsuit", "hazmatsuit2", "hazmatsuit3":
				create = tempname in ["gasmask", "gasmask3", "supergasmask", "hazmatsuit", "hazmatsuit2", "hazmatsuit3"]
			"key1", "key2", "key3":
				create = tempname in ["key1", "key2", "key3"] or (tempname == "misc" and randi_range(1, 6) == 1)
			"vest", "finevest":
				create = tempname in ["vest", "finevest"]
			_:
				create = tempname == "misc" and randi_range(1, 6) == 1
		if create:
			_remove_slot(slot)
			_drop_item(item_name, tempname)
			Sfx.play_global(self, "SFX/SCP/1162/Exchange%d.ogg" % randi_range(0, 4))
			st.s3 = 0.0
			GameState.give_achievement("1162")
			return

func _stain(player: CharacterBody3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0.0, 0.2, 0.0), player.global_position + Vector3(0.0, -0.4, 0.0))
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		GrowingDecal.make(player.get_parent(), hit.position + Vector3(0.0, 0.005, 0.0), "GFX/decal4.png", 0.75, 0.0, 0.8, false)

func _pain(player: CharacterBody3D, quiet_message: String) -> void:
	var s := GameState
	if s.injuries > 15.0:
		Sfx.play_global(self, "SFX/SCP/1162/BodyHorrorExchange%d.ogg" % randi_range(1, 4))
		s.light_flash = 5.0
		player.kill(DEATH)
	else:
		Sfx.play_global(self, "SFX/SCP/1162/BodyHorrorExchange%d.ogg" % randi_range(1, 4))
		s.light_flash = 5.0
		_hud().message(quiet_message, 5.0)

# nothing to trade: it takes from the body, every frame until it has paid with something
func _take_from_body(st: Dictionary) -> void:
	var player: CharacterBody3D = GameState.player
	GameState.injuries += 5.0
	_stain(player)
	for entry in RoomFill.item_order():
		if good_for_1162(str(entry[0]), str(entry[1])) and randi_range(1, 6) == 1:
			_drop_item(str(entry[0]), str(entry[1]))
			GameState.give_achievement("1162")
			st.s3 = 0.0
			_pain(player, "You feel a sudden overwhelming pain in your chest.")
			return

# a memory for a filled slot (3) or for the body (3.1)
func _memory(st: Dictionary, player: CharacterBody3D) -> void:
	var slot := int(st.s2)
	if st.s3 < 3.1:
		Sfx.play_global(self, "SFX/SCP/1162/Exchange%d.ogg" % randi_range(0, 4))
		if _slot_filled(slot):
			_remove_slot(slot)
	else:
		GameState.injuries += 5.0
		_stain(player)
		_pain(player, "You notice something moving in your pockets and a sudden pain in your chest.")
		st.s2 = 0.0
	var memory: Array = MEMORIES.get(int(st.s), [])
	if not memory.is_empty():
		_drop_item(str(memory[0]), str(memory[1]))
	GameState.give_achievement("1162")
	st.s3 = 0.0
