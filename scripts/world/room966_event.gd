extends Node3D
# SCP-966's room (UpdateEvents.bb Case "room966", Main.bb LoadEvents): the first time the player is in the room, half a second
# later (30 frames) a Sleep Killer is made at Objects[0] and the next frame another at Objects[2]; the event is then over
# (facility.events.room966.state 2).

var room: FacilityRoom
var _timer := 0.0

func build(room_node: FacilityRoom) -> void:
	room = room_node

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or not facility.active:
		return
	if facility.events.room966.state >= 2 or not room.world_bounds().has_point(player.global_position):
		return
	if facility.events.room966.state == 0:
		facility.events.room966.state = 1
		_timer = 0.0
	_timer += delta * 70.0
	if _timer > 30.0:
		facility.spawn_scp966(NpcGravity.feet(room.object_point(0)))
		facility.spawn_scp966(NpcGravity.feet(room.object_point(2)))
		facility.events.room966.state = 2
