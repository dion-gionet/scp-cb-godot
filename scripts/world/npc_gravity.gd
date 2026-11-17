class_name NpcGravity
extends RefCounted
# The gravity rule at the end of UpdateNPCs (NPCs.bb 5003-5096) for the NPCs that move on collision. The rooms are all built, so
# nothing stands on "no floor loaded" here; what keeps a far NPC from falling through a hidden room (HideEntity turns its collision
# off) is the original's own rule: past HideDistance * 0.7 an NPC does not move vertically at all.

enum { NO_MOVE, FALL, HOLD }

const HIDE_DISTANCE := 15.0
const FLOOR_PRESS := -0.2

# CheckForNPCInFacility (NPCs.bb 7323) and CheckForPlayerInFacility (Main.bb 11558): 0 outside (the 1499 dimension), 1 the
# facility, 2 the tunnels.
static func in_facility(y: float) -> int:
	if y > 100.0:
		return 0
	if y < -10.0 or y > 7.0:
		return 2
	return 1

# NO_MOVE: DropSpeed 0 and no TranslateEntity. FALL: DropSpeed grows. HOLD: DropSpeed 0 (FallingPickDistance > 0 off the
# visible rooms). `always_near` is NPCtype1499, which skips the distance test (5002).
static func mode(body: Node3D, facility: FacilityMap, falling_pick_distance: float = 10.0, always_near: bool = false) -> int:
	var player: Node3D = GameState.player
	if player == null:
		return FALL
	var at := body.global_position
	var from := player.global_position
	# gravityDist is an Int in Blitz: the distance rounds
	if not always_near and roundi(Vector2(at.x - from.x, at.z - from.z).length()) >= HIDE_DISTANCE * 0.7:
		return NO_MOVE
	var level := in_facility(at.y)
	if level != in_facility(from.y):
		return NO_MOVE
	if level != 1 or facility.events.room860.state == 1.0 or facility.intro_active or _player_in_173(facility) or _in_visible_room(at, facility):
		return FALL
	return HOLD if falling_pick_distance > 0.0 else FALL

static func _player_in_173(facility: FacilityMap) -> bool:
	var room := facility.drawing.player_room
	return room is FacilityRoom and (room as FacilityRoom).room_name == "173"

# Any room of the visible set whose extents (4 x 4 without any) reach the NPC's x and z from the room's origin (5036-5072).
static func _in_visible_room(at: Vector3, facility: FacilityMap) -> bool:
	for room: Node3D in facility.drawing.ring_rooms:
		var size: Vector2 = facility.rooms.record_of(room).get("ext_size", Vector2.ZERO)
		if size == Vector2.ZERO:
			size = Vector2(4.0, 4.0)
		if absf(at.x - room.global_position.x) <= size.x and absf(at.z - room.global_position.z) <= size.y:
			return true
	return false

# Whether the NPC's drop speed grows this tick (anything but FALL leaves it at zero).
static func falls(body: Node3D, falling_pick_distance: float = 10.0, always_near: bool = false) -> bool:
	var facility := body.get_tree().get_first_node_in_group("facility") as FacilityMap
	return facility == null or mode(body, facility, falling_pick_distance, always_near) == FALL

# Sets body.velocity.y for this tick. On the floor it presses down, which is the original's DropSpeed 0 after CollidedFloor.
static func apply(body: CharacterBody3D, delta: float, gravity: float, max_fall: float, falling_pick_distance: float = 10.0, always_near: bool = false) -> void:
	if body.is_on_floor():
		body.velocity.y = FLOOR_PRESS
	elif falls(body, falling_pick_distance, always_near):
		body.velocity.y = maxf(body.velocity.y - gravity * delta, -max_fall)
	else:
		body.velocity.y = 0.0
