extends Node3D
# The control room (MapSystem.bb FillRoom "room2ccont", UpdateEvents.bb Case "room2ccont"): three levers on the wall, all up.
#   first   primary lighting (nothing reads it)
#   second  secondary lighting: while the player is in the room SecondaryLightOn follows it (CurveValue, smooth 10), so thrown
#           down the room lights go out and the screen darkens. Looking at it from within 1.5 for the first time plays a
#           horror sting and the lever drops by itself over the next 200 frames.
#   third   remote door control (RemoteDoorOn): up keeps 079's door and the gates shut (remote_doors.gd), down frees 079's door
#           and bars the gates until it goes back up.
# Everything is only read while the player is inside the room; the levers' positions are kept on the facility for the saves.


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var levers: Array[Node3D] = []
var _secondary_on := true

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	for n in 3:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		var start := 10.0
		if facility != null:
			start = float(facility.ccont_pitches[n])
		lever.setup(Vector3(-240.0 * RS, 1104.0 * RS, -(632.0 - 64.0 * n) * RS), 90.0, start)
		levers.append(lever)
	_secondary_on = levers[1].is_on()

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or levers.is_empty() or not facility.active:
		return
	for n in 3:
		facility.ccont_pitches[n] = levers[n].pitch
	if not room.world_bounds().has_point(player.global_position):
		return
	var fps := delta * 70.0
	if facility.ccont_state == 0.0 and levers[1].aimed_at(player.camera, 1.5):
		facility.ccont_state = 1.0
		Sfx.play_global(self, "SFX/Horror/Horror7.ogg")
		Sfx.play_global(self, "SFX/Interact/LeverFlip.ogg")
	var was_on := _secondary_on
	_secondary_on = levers[1].is_on()
	if was_on != _secondary_on and facility.ccont_state > 0.0:
		Sfx.play_at(levers[1], "SFX/General/LightSwitch.ogg", 10.0)
	var wanted := 1.0 if _secondary_on else 0.0
	GameState.secondary_light += (wanted - GameState.secondary_light) * minf(fps / 10.0, 1.0)
	facility.remote_door_on = levers[2].is_on()
	if facility.ccont_state > 0.0 and facility.ccont_state < 200.0:
		facility.ccont_state += fps
		levers[1].pitch += (-85.0 - levers[1].pitch) * minf(fps / 5.0, 1.0)
