extends Node3D
# The gate A entrance (UpdateEvents.bb Case "gateaentrance"): its door to the facility (RoomDoors[1], the heavy one) follows the
# control room's remote door lever and SCP-079's say-so (remote_doors.gd), like gate B's. Only read while the player is in the room.


var room: FacilityRoom

func build(room_node: FacilityRoom) -> void:
	room = room_node

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	if room.world_bounds().has_point(player.global_position):
		RemoteDoors.gate(room.door_slots.get(1), facility, facility.gate_a_unlocked, player)
