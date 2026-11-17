extends RefCounted
class_name RemoteDoors
# RemoteDoorOn (MapSystem.bb Global RemoteDoorOn, UpdateEvents.bb): the control room's third lever. It starts up, and while it is
# up SCP-079 holds the doors he owns:
#   - 079's own chamber door (RoomDoors[0] of room079) shuts again as soon as it is opened enough to walk through
#   - the doors to the two gates (exit1 RoomDoors[4], gateaentrance RoomDoors[1]) do the same until he has opened them (the
#     gate's EventState3), and are locked outright while the lever is down
# The same error click plays every time (DoorError).


# A door open far enough to pass, or with the player at the frame, is shut again with the error click.
static func slam(door: Node3D, player: Node3D) -> void:
	if door == null or not is_instance_valid(door) or not door.open:
		return
	if door.openstate > 50.0 or (player != null and player.global_position.distance_to(door.global_position) < 0.5):
		door.open = false
		Sfx.play_at(door, "SFX/Door/DoorError.ogg", 10.0)

# The gate door: locked with the lever down, shut again with it up until 079 has opened the gate, free after that.
static func gate(door: Node3D, facility: FacilityMap, unlocked: bool, player: Node3D) -> void:
	if door == null or not is_instance_valid(door):
		return
	if not facility.remote_door_on:
		door.locked = true
	elif not unlocked:
		door.locked = false
		slam(door, player)
	else:
		door.locked = false
