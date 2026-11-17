extends Node3D
# room3storage (UpdateEvents.bb Case "room3storage", MapSystem.bb FillRoom): the storage area below the lifts. The lifts are
# facility_room's; this node holds what lies on the lower level: SCP-939's three specimens, the two levers that open RoomDoors[4]
# (the way to the last hall), the black severed hand with its stain, and the fall below the level (the pit's floor kills).
# Below -4600 units the specimens patrol their loops (Objects[4]-[8], [9]-[12], [13]-[16]; the first and third are told to ignore the
# player inside the trigger boxes "939-1_fix" and "939-3_fix"); anywhere else they do nothing. EventState (st.s) is 1 once they have
# been put on their loops.

const RS := 8.0 / 2048.0
const Scp939 = preload("res://scripts/npc/scp_939.gd")

const LEVEL_Y := -4600.0 * RS
const FALL_Y := -6400.0 * RS
# the loops: Objects[start] ... [last] and where each specimen starts
const START_OBJECTS := [4, 9, 13]
const FIRST_WAYPOINT := [5, 10, 14]
const LAST_WAYPOINT := [7, 12, 16]

var room: FacilityRoom
var levers: Array[Node3D] = []
var specimens: Array[Node3D] = []
var _restored := false
var _was_here := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var spots := [Vector3(3101.0, -5461.0, -6568.0), Vector3(1209.0, -5461.0, -3164.0)]
	for spot in spots:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		lever.setup(spot * RS, -180.0, -10.0, 0.04)
		levers.append(lever)

func _world() -> Node:
	return room.get_parent()

func _exit_tree() -> void:
	if GameState.music_override == "Room3Storage":
		GameState.music_override = ""

func _waypoints() -> Array:
	var points: Array = []
	for i in 17:
		points.append(room.object_point(i))
	return points

func _gather() -> void:
	specimens.clear()
	for node in get_tree().get_nodes_in_group("scp939"):
		if is_instance_valid(node):
			specimens.append(node)
	specimens.sort_custom(func(a: Node, b: Node) -> bool: return a.index < b.index)
	while specimens.size() < 3:
		var specimen := CharacterBody3D.new()
		specimen.set_script(Scp939)
		specimen.index = specimens.size()
		_world().add_child(specimen)
		specimen.global_position = Vector3(0.0, -200.0, 0.0)
		specimens.append(specimen)
		var st: Dictionary = _state()
		st.s = 0.0

func _state() -> Dictionary:
	return get_tree().get_first_node_in_group("facility").ambient.state_of(room.room_key)

func _hush() -> void:
	for node in get_tree().get_nodes_in_group("scp939"):
		if is_instance_valid(node):
			node.state = 66

func _put_hand(st: Dictionary) -> void:
	st.hand = 1.0
	var spots := [Vector2(2312.0, -952.0), Vector2(3032.0, 1288.0), Vector2(2824.0, 2808.0)]
	var record: Dictionary = get_tree().get_first_node_in_group("facility").rooms.by_grid.get(room.room_key, {})
	var spot: Vector2 = spots[int(record.get("hand_spot", randi_range(1, 3))) - 1]
	var at: Vector3 = room.to_global(Vector3(spot.x * RS, -5596.0 * RS + 1.0, -spot.y * RS))
	var hand := RoomFill.make_pickup("Black Severed Hand", "hand2")
	_world().add_child(hand)
	hand.global_position = at
	GrowingDecal.make(_world(), Vector3(at.x, room.global_position.y - 5632.0 * RS + 0.01, at.z), "GFX/decal4.png", 0.5, 0.0, 0.8, false)

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active or levers.size() < 2:
		return
	var st := _state()
	if not _restored:
		_restored = true
		if st.has("lever0"):
			for i in 2:
				levers[i].pitch = float(st["lever%d" % i])
	for i in 2:
		st["lever%d" % i] = levers[i].pitch
	var here: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if here:
		_was_here = true
	if not here:
		# a player who has fallen out through the bottom of the room's bounds is still in it (PlayerRoom stays)
		if _was_here and room.to_local(player.global_position).y < FALL_Y and not player.dead:
			_fall(player)
		if Vector2(player.global_position.x - room.global_position.x, player.global_position.z - room.global_position.z).length() > 40.0:
			_was_here = false
		_hush()
		_release_music()
		return
	var below: bool = room.to_local(player.global_position).y < LEVEL_Y
	if not below:
		st.s = 0.0
		_hush()
		_release_music()
		return
	GameState.give_achievement("939")
	GameState.music_override = "Room3Storage"
	if not st.has("hand"):
		_put_hand(st)
	_gather()
	if st.s == 0.0:
		var points := _waypoints()
		for i in 3:
			var start: Vector3 = points[START_OBJECTS[i]]
			var specimen: Node3D = specimens[i]
			specimen.global_position = Vector3(start.x, start.y - 0.1, start.z)
			specimen.velocity = Vector3.ZERO
			specimen.waypoints = points
			specimen.state = 2
			specimen.state2 = FIRST_WAYPOINT[i]
			specimen.prev_state = LAST_WAYPOINT[i]
		st.s = 1.0
	var door: Node3D = room.door_slots.get(4)
	if door != null:
		if not door.open and (levers[0].is_on() or levers[1].is_on()):
			door.open = true
			Sfx.play_at(door, "SFX/Door/Door2Open1_dist.ogg", 400.0)
		for lever in levers:
			lever.locked = door.open
	for specimen in specimens:
		if specimen.waypoints.is_empty():
			specimen.waypoints = _waypoints()       # after a load
	specimens[0].ignore_player = false
	specimens[2].ignore_player = false
	match room.trigger_at(player.global_position):
		"939-1_fix":
			specimens[0].ignore_player = true
		"939-3_fix":
			specimens[2].ignore_player = true
	if room.to_local(player.global_position).y < FALL_Y and not player.dead:
		_fall(player)

func _fall(player: CharacterBody3D) -> void:
	GameState.death_msg = ""
	Sfx.play_global(self, "SFX/Room/PocketDimension/Impact.ogg")
	player.kill("")

func _release_music() -> void:
	var tunnels: MtEvent = get_tree().get_first_node_in_group("facility").rooms.tunnels
	if GameState.music_override == "Room3Storage" and not (tunnels != null and tunnels.playing_music):
		GameState.music_override = ""
