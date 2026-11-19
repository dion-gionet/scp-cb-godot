extends Node3D
# The warhead room (MapSystem.bb FillRoom "room2nuke", UpdateEvents.bb Case "room2nuke"): two levers on the control wall (the
# first is the remote detonation, the second does nothing). Whatever the first one says is remembered when the player leaves,
# and the gate B ending reads it: up (the way it starts, pitch 10) the bomb goes off (ending B2), down it fails (B3). The event
# only reads the lever while the player is in the room, so an unvisited room counts as "off".


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var levers: Array[Node3D] = []
var body_spawned := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	for n in 2:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		var start := 10.0
		if n == 0 and facility != null and facility.nuke_lever_pitch != INF:
			start = facility.nuke_lever_pitch
		lever.setup(Vector3(-975.0 * RS, 1712.0 * RS, (502.0 - 132.0 * n) * RS), -90.0, start)
		levers.append(lever)

# EventState3 = 0: on the first pass a dead Class D lies at Objects[6] (body2.jpg, state 3, frame 40).
func _spawn_body(facility: FacilityMap) -> void:
	body_spawned = true
	var at := NpcGravity.feet(room.to_global(Vector3(1110.0 * RS, 0.5, 208.0 * RS)), NpcGravity.CLASS_D_RADIUS)
	var body := facility.spawn_human(HumanNpc.Kind.CLASS_D, at, HumanNpc.BODY2_TEXTURE)
	body.rotation.y = room.rotation.y + deg_to_rad(90.0)
	body.state = 3
	body.set_frame(40.0)
	body.is_dead = true

func _physics_process(_delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or levers.is_empty():
		return
	if not body_spawned:
		_spawn_body(facility)
	facility.nuke_lever_pitch = levers[0].pitch
	if room.world_bounds().has_point(player.global_position):
		facility.nuke_remote_on = levers[0].is_on()
