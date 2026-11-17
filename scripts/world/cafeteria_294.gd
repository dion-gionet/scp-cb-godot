extends Node3D
# The cafeteria and the SCP-294 machine in it (MapSystem.bb FillRoom "room2cafeteria", UpdateEvents.bb Case "room2cafeteria").
# Objects[0] is the machine, Objects[1] the spout where cups appear. Within 1.5 of the machine and looking at it the hand shows;
# a click takes a Quarter or a Coin from the selected item (two are needed: the count is kept in the facility, EventState2) and
# with both in, opens the keyboard (scp294_panel.gd) unless a cup is still standing at the spout. When the drink is out the
# count starts over. The two cups on the tables are Orange Juice and Coffee. (The room's SCP-066 is made by `_ev_room2cafeteria`.)


var room: FacilityRoom

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var drinks := [["Cup of Orange Juice", Color(240.0 / 255.0, 175.0 / 255.0, 70.0 / 255.0)], ["Cup of Coffee", Color(87.0 / 255.0, 62.0 / 255.0, 45.0 / 255.0)]]
	var cups: Array = []
	for child in room.get_children():
		if child.is_in_group("pickup") and str(child.get_meta("tempname", "")) == "cup":
			cups.append(child)
	cups.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_meta("fill_id", "")) < str(b.get_meta("fill_id", "")))
	for i in mini(cups.size(), drinks.size()):
		cups[i].set_cup(drinks[i][0], drinks[i][1], 1.0)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# True when nothing lies at the spout (the original compares the two coordinates for equality).
func spout_free() -> bool:
	var spout: Vector3 = room.object_point(1)
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and _flat_distance(pickup.global_position, spout) < 0.02:
			return false
	return true

func spawn_cup(cup_name: String, color: Color, alpha: float) -> void:
	var cup := RoomFill.make_pickup(cup_name, "cup", {"cr": color.r, "cg": color.g, "cb": color.b, "ca": alpha})
	GameState.player.get_parent().add_child(cup)
	cup.global_position = room.object_point(1)

# The panel calls this when the drink is out.
func dispensed() -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		facility.scp294_coins = 0

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	if GameState.using_294 or not room.world_bounds().has_point(player.global_position):
		return
	var machine: Vector3 = room.object_point(0)
	if _flat_distance(player.global_position, machine) >= 1.5 or absf(player.global_position.y - machine.y) > 4.0:
		return
	GameState.give_achievement("294")
	var camera: Camera3D = player.camera
	if not camera.is_position_in_frustum(machine):
		return
	GameState.hand_icon = true
	if not Input.is_action_just_pressed("interact"):
		return
	click(facility)

# MouseHit1 at the machine.
func click(facility: FacilityMap) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var free := spout_free()
	var inserted := false
	if facility.scp294_coins < 2 and hud != null:
		var held: String = hud.selected_tempname()
		if held == "25ct" or held == "coin":
			hud.remove_selected()
			facility.scp294_coins += 1
			Sfx.play_global(self, "SFX/SCP/294/coin_drop.ogg")
			inserted = true
	if facility.scp294_coins == 2:
		var panel := get_tree().get_first_node_in_group("scp294_panel")
		if free and panel != null:
			panel.open(self)
	elif facility.scp294_coins == 1 and not inserted:
		if hud != null:
			hud.message("You need to insert another Quarter in order to use this machine.", 5.0)
	elif not inserted:
		if hud != null:
			hud.message("You need to insert two Quarters in order to use this machine.", 5.0)
