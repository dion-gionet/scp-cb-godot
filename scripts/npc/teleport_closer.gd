class_name TeleportCloser
extends RefCounted
# TeleportCloser (NPCs.bb 5124-5167): of the non-door waypoints 1-10 away from the NPC on both axes and farther than
# 16 (8 aggressive) from the player, the one nearest the player. Unless the NPC is in the facility proper (InFacility 1) and
# the difficulty is not aggressive, it goes there; in the facility it only goes when that waypoint lies between y -10 and 7.

static func run(npc: Node3D) -> bool:
	var player: Node3D = GameState.player
	if player == null:
		return false
	var best: Variant = pick(npc.global_position, player.global_position, NpcGravity.in_facility(npc.global_position.y))
	if best == null:
		return false
	npc.global_position = (best as Vector3) + Vector3(0.0, 0.15, 0.0)
	return true

# The waypoint the NPC would go to, or null.
static func pick(npc_pos: Vector3, player_pos: Vector3, in_facility: int) -> Variant:
	var facility := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("facility") as FacilityMap
	if facility == null:
		return null
	var aggressive := GameState.aggressive_npcs()
	var min_player := 16.0 - (8.0 if aggressive else 0.0)
	var best := Vector3.INF
	var best_dist := INF
	for p in facility.waypoints():
		var dx := absf(p.x - npc_pos.x)
		var dz := absf(p.z - npc_pos.z)
		if dx > 1.0 and dx < 10.0 and dz > 1.0 and dz < 10.0:
			var to_player := player_pos.distance_to(p)
			if to_player > min_player and to_player < best_dist:
				best = p
				best_dist = to_player
	if best == Vector3.INF:
		return null
	if in_facility == 1 and not aggressive and (best.y > 7.0 or best.y < -10.0):
		return null
	return best
