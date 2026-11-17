extends Node
# One elevator: two doors and two cab markers (MapSystem.bb UpdateElevators). Whoever stands in
# the cab of the closed pair is teleported to the other cab after 500 frames (7.1 s).


const ROOM_SCALE := 8.0 / 2048.0
const CAB_HALF := 280.0 * ROOM_SCALE        # a cab is a 2.19 m cube around its marker
const EDGE := CAB_HALF - 0.22               # entities keep this far from the cab walls

var door1: Node3D
var door2: Node3D
var cab1: Node3D
var cab2: Node3D
var state := 0.0
var one_way := false         # gate A's lift: arriving locks both doors and ends the elevator
var slam_096 := false        # gate B's / gate A's lift: an angry SCP-096 gets into it (Update096ElevatorEvent)
var slam_state := 0.0
var enabled := true           # room049 turns its lifts off while the chamber has no power
var rotates := false          # UpdateElevators with ignorerotation False (the maintenance tunnels): the cabs face different ways, so what rides turns with them
var _move_sfx: AudioStreamPlayer3D
var _slam_voice: AudioStreamPlayer3D

func setup(first_door: Node3D, second_door: Node3D, first_cab: Node3D, second_cab: Node3D) -> void:
	door1 = first_door
	door2 = second_door
	cab1 = first_cab
	cab2 = second_cab
	# Started like the original: the first door is open, so state is "car at door 1".
	state = 0.0

func _physics_process(delta: float) -> void:
	if door1 == null or door2 == null or not is_instance_valid(door1) or not is_instance_valid(door2):
		return
	if not enabled:
		return
	var fps := delta * 70.0
	var player: Node3D = GameState.player
	if slam_096 and _slam_active():
		_update_slam(fps, player)
		return
	door1.elevator_state = 1
	door2.elevator_state = 1
	if door1.open and not door2.open and door1.openstate >= 180.0:
		state = -1.0
		door1.locked = false
		if door2.call_pressed:
			door1.toggle()
	elif door2.open and not door1.open and door2.openstate >= 180.0:
		state = 1.0
		door2.locked = false
		if door1.call_pressed:
			door2.toggle()
	elif absf(door1.openstate - door2.openstate) < 0.2:
		door1.elevator_state = 2
		door2.elevator_state = 2
	door1.call_pressed = false
	door2.call_pressed = false
	door1.locked = true
	door2.locked = true
	if door1.open:
		door1.elevator_state = 3
		if player and _in_cab(player.global_position, cab1, fps):
			door1.locked = false
			door1.elevator_state = 1
	if door2.open:
		door2.elevator_state = 3
		if player and _in_cab(player.global_position, cab2, fps):
			door2.locked = false
			door2.elevator_state = 1
	if door1.open or door2.open:
		return
	door1.locked = true
	door2.locked = true
	if door1.openstate != 0.0 or door2.openstate != 0.0:
		return
	if state < 0.0:
		state -= fps
		if one_way and state < -1.5 and state + fps >= -1.5:
			var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
			if facility != null and not facility.contained_106:
				Sfx.play_global(self, "SFX/SCP/106/Laugh.ogg")
		var inside := player != null and _in_cab(player.global_position, cab1, fps)
		if inside:
			_ride(player, state)
		if state < -500.0:
			door1.locked = true
			door2.locked = false
			state = 0.0
			_arrive(cab1, cab2, door2, door1, inside, fps)
	else:
		state += fps
		var inside_b := player != null and _in_cab(player.global_position, cab2, fps)
		if inside_b:
			_ride(player, state)
		if state > 500.0:
			door1.locked = false
			door2.locked = true
			state = 0.0
			_arrive(cab2, cab1, door1, door2, inside_b, fps)

# Curr096 is neither sitting (0) nor walking about (5): it takes over from the lift.
func _slam_active() -> bool:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or facility.scp096 == null or not is_instance_valid(facility.scp096):
		return false
	var shy: Node = facility.scp096
	return slam_state > 0.0 or (shy.state != 0 and shy.state != 5)

# Main.bb Update096ElevatorEvent: with the player in the cab and the door shut, 096 appears just outside, slams the door
# for 7 s (shakes at 1.9, 4.2, 5.9, 7.25 and 8.1 s, the door held at 20 until 8.1 s) and then tears it open and chases.
func _update_slam(fps: float, player: Node3D) -> void:
	var shy: Node = (get_tree().get_first_node_in_group("facility") as FacilityMap).scp096
	var previous := slam_state
	if slam_state < 0.0:
		slam_state = 0.0
		previous = 0.0
	if door1.openstate == 0.0 and not door1.open and player != null:
		var d: Vector3 = player.global_position - cab1.global_position
		var limit := CAB_HALF + 0.015 * fps
		if absf(d.x) <= limit and absf(d.z) <= limit and absf(d.y) <= limit:
			door1.locked = true
			if slam_state == 0.0:
				var outward: Vector3 = door1.global_position - cab1.global_position
				outward.y = 0.0
				shy.global_position = door1.global_position + Vector3(0.0, 1.0, 0.0) + outward.normalized() * 0.5
				shy.velocity = Vector3.ZERO
				shy.rotation.y = atan2(-(cab1.global_position.x - shy.global_position.x), -(cab1.global_position.z - shy.global_position.z))
				shy.state = 6
				shy.set_frame(0.0)
				slam_state += fps * 1.4
	if slam_state > 0.0:
		if previous == 0.0:
			if _slam_voice == null:
				_slam_voice = AudioStreamPlayer3D.new()
				_slam_voice.max_distance = 20.0
				_slam_voice.stream = Sfx.stream("SFX/SCP/096/ElevatorSlam.ogg")
				add_child(_slam_voice)
			_slam_voice.global_position = door1.global_position
			_slam_voice.play()
		var t := slam_state
		if t > 70.0 * 1.9 and t < 70.0 * 2.0 + fps:
			player.camera_shake = 7.0
		elif t > 70.0 * 4.2 and t < 70.0 * 4.25 + fps:
			player.camera_shake = 1.0
		elif t > 70.0 * 5.9 and t < 70.0 * 5.95 + fps:
			player.camera_shake = 1.0
		elif t > 70.0 * 7.25 and t < 70.0 * 7.3 + fps:
			player.camera_shake = 1.0
			door1.fast_open = true
			door1.open = true
			shy.state = 4
			shy.last_seen = 1
		elif t > 70.0 * 8.1 and t < 70.0 * 8.15 + fps:
			player.camera_shake = 1.0
		if slam_state <= 70.0 * 8.1:
			door1.openstate = minf(door1.openstate, 20.0)
		slam_state += fps * 1.4

# The offset from the cab left, turned by the difference of the cabs' yaws (UpdateElevators works in Blitz's x and z, z the other way round).
func _carried_offset(offset: Vector3, forward: bool) -> Vector2:
	var dist := Vector2(offset.x, offset.z).length()
	var turn := _yaw_degrees(cab2) - _yaw_degrees(cab1)
	var dir := rad_to_deg(atan2(-offset.z, offset.x)) + (turn if forward else -turn)
	return Vector2(cos(deg_to_rad(dir)) * dist, -sin(deg_to_rad(dir)) * dist)

# RotateEntity ..., EntityYaw(room2) + angleDist(EntityYaw(entity), EntityYaw(room1)): written so in both directions, which is wrong for the ride back.
func _turn_with_cab(entity: Node3D) -> void:
	var relative := wrapf(rad_to_deg(entity.global_rotation.y) - _yaw_degrees(cab1), -180.0, 180.0)
	entity.global_rotation.y = deg_to_rad(_yaw_degrees(cab2) + relative)

func _yaw_degrees(cab: Node3D) -> float:
	return rad_to_deg(cab.global_rotation.y)

func _in_cab(point: Vector3, cab: Node3D, fps: float) -> bool:
	var d := point - cab.global_position
	var limit := CAB_HALF + 0.015 * fps
	return absf(d.x) < limit and absf(d.z) < limit and absf(d.y) < limit

func _ride(player: Node3D, travel: float) -> void:
	# CameraShake = Sin(Abs(State) / 3) * 0.3 and the "Moving" loop while the car runs.
	player.camera_shake = maxf(sin(deg_to_rad(absf(travel) / 3.0)), 0.0) * 0.3
	if _move_sfx == null:
		_move_sfx = AudioStreamPlayer3D.new()
		_move_sfx.stream = Sfx.stream("SFX/General/Elevator/Moving.ogg")
		_move_sfx.max_distance = 20.0
		add_child(_move_sfx)
	if _move_sfx.stream and not _move_sfx.playing:
		_move_sfx.play()

func _arrive(from_cab: Node3D, to_cab: Node3D, open_door: Node3D, close_door: Node3D, inside: bool, fps: float) -> void:
	var moved: Array[Node3D] = []
	var player: Node3D = GameState.player
	if player and inside:
		moved.append(player)
	var statue: Node3D = GameState.scp173
	if statue and _in_cab(statue.global_position, from_cab, fps):
		moved.append(statue)
	for node in get_tree().get_nodes_in_group("pickup"):
		var item := node as Node3D
		if item and _in_cab(item.global_position, from_cab, fps):
			moved.append(item)
	for entity in moved:
		var offset := entity.global_position - from_cab.global_position
		var x := clampf(offset.x, -EDGE, EDGE)
		var z := clampf(offset.z, -EDGE, EDGE)
		if rotates:
			var carried := _carried_offset(offset, from_cab == cab1)
			x = clampf(carried.x, -EDGE, EDGE)
			z = clampf(carried.y, -EDGE, EDGE)
			_turn_with_cab(entity)
		entity.global_position = to_cab.global_position + Vector3(x, 0.1 * fps + offset.y, z)
		if entity is CharacterBody3D:
			(entity as CharacterBody3D).velocity = Vector3.ZERO
		if entity.has_method("wake"):
			entity.wake()
	if player and inside:
		(get_tree().get_first_node_in_group("facility") as FacilityMap).after_teleport()
	open_door.toggle(not inside)
	close_door.open = false
	if one_way and inside:
		open_door.locked = true
		close_door.locked = true
		set_physics_process(false)
	if inside:
		open_door.call("_play_door_sound", true)
	var beep := Sfx.stream("SFX/General/Elevator/Beep.ogg")
	if beep != null:
		var player3d := AudioStreamPlayer3D.new()
		player3d.stream = beep
		player3d.max_distance = 4.0
		from_cab.add_child(player3d)
		player3d.play()
		player3d.finished.connect(player3d.queue_free)
