extends Node
# Walks a CharacterBody3D along a route from the facility's waypoint graph (FindPath).
# Attach it to the NPC, call path_to(target); it opens doors it comes up against, like the
# NPC code in the original does for waypoints that belong to a door.

var body: CharacterBody3D
var speed := 1.5
var points: Array[Vector3] = []
var index := 0
var status := 0          # 0 there / 1 route / 2 no route (last path_to)
var target := Vector3.ZERO
var stuck_time := 0.0
var hop_when_stuck := false    # a scripted walk may not be stranded: after 3 s stuck, hop to the next waypoint
var open_reach := 1.6          # how near a closed door must be before the walker opens it (049's scene in room2sl: 0.6, as the original)
var keep_shut: Node3D = null   # a door its owner has just closed behind it (049 in room2sl): not opened again on the way out

var _recovering := false      # backing to the previous waypoint's centre after getting stuck on a corner
var _recoveries := 0          # tries at the current waypoint (three, then it stays stuck for its owner to handle)

const REACH := 0.35
const GRAVITY := 20.0

func path_to(target_pos: Vector3) -> int:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	target = target_pos
	_exit_door = null
	keep_shut = null
	_recovering = false
	_recoveries = 0
	index = 0
	points = []
	stuck_time = 0.0
	if facility == null or body == null:
		status = 2
		return status
	var result: Dictionary = facility.find_path(body.global_position, target_pos)
	status = int(result.status)
	for p in result.points:
		points.append(p)
	return status

func has_arrived() -> bool:
	if status == 0:
		return true
	return status == 1 and index >= points.size()

func _physics_process(delta: float) -> void:
	if body == null or index >= points.size():
		return
	var goal := points[index]
	if _recovering:
		# stuck on a corner: back to the middle of the waypoint it just left, then try again from there
		goal = points[index - 1]
		if Vector2(goal.x - body.global_position.x, goal.z - body.global_position.z).length() < 0.08:
			_recovering = false
			stuck_time = 0.0
			goal = points[index]
	var flat := Vector3(goal.x - body.global_position.x, 0.0, goal.z - body.global_position.z)
	# door waypoints are passed through their centre; other points may be cut slightly
	if not _recovering and flat.length() < (0.1 if _at_door(goal) else REACH):
		_exit_door = _door_at(goal)
		index += 1
		stuck_time = 0.0
		_recoveries = 0
		return
	_open_doors()
	var direction := flat.normalized()
	# leaving a doorway: straight out along its axis until the frame is behind, not diagonally into the jamb
	if _exit_door != null and is_instance_valid(_exit_door) and not _recovering:
		var from_door := Vector2(body.global_position.x - _exit_door.global_position.x, body.global_position.z - _exit_door.global_position.z).length()
		if from_door < 0.8:
			var axis: Vector3 = _exit_door.global_transform.basis.z
			axis.y = 0.0
			axis = axis.normalized()
			if axis.dot(Vector3(goal.x - _exit_door.global_position.x, 0.0, goal.z - _exit_door.global_position.z)) < 0.0:
				axis = -axis
			direction = axis
		else:
			_exit_door = null
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	body.rotation.y = atan2(-direction.x, -direction.z)
	if body.is_on_floor():
		body.velocity.y = -0.1
	elif NpcGravity.falls(body):
		body.velocity.y -= GRAVITY * delta
	else:
		body.velocity.y = 0.0
	_step_up(direction * speed * delta, goal)
	if hop_when_stuck and stuck_time > 3.0:
		body.global_position = goal + Vector3(0.0, 0.15, 0.0)
		body.velocity = Vector3.ZERO
		index += 1
		stuck_time = 0.0
		return
	var before := body.global_position
	body.move_and_slide()
	if body.global_position.distance_to(before) < speed * delta * 0.25:
		stuck_time += delta
		if stuck_time > 0.8 and index > 0 and not _recovering and _recoveries < 3:
			_recovering = true
			_recoveries += 1
			stuck_time = 0.0
	else:
		stuck_time = 0.0

# A closed, unlocked door within `open_reach` of the walker (and ahead of it) is opened.
func _open_doors() -> void:
	for node in _doors_near(body.global_position, open_reach):
		var door := node as Node3D
		if door == null or door == keep_shut or door.open or door.locked or door.keycard != 0 or not door.code.is_empty():
			continue
		if door.openstate > 0.0 and door.openstate < 180.0:
			continue
		var flat := Vector2(door.global_position.x - body.global_position.x, door.global_position.z - body.global_position.z)
		if flat.length() < open_reach and absf(door.global_position.y - body.global_position.y) < 2.0:
			door.npc_open()

func _at_door(point: Vector3) -> bool:
	for node in _doors_near(point, 0.6):
		var door := node as Node3D
		if door != null and Vector2(door.global_position.x - point.x, door.global_position.z - point.z).length() < 0.6 and absf(door.global_position.y - point.y) < 1.0:
			return true
	return false

# Doors never move, so the facility's door index answers "which doors are around here".
func _doors_near(position_value: Vector3, radius: float) -> Array:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		return facility.doors_near(position_value, radius)
	return get_tree().get_nodes_in_group("door")

const STEP := 0.32

# Stairs: when the way ahead is blocked at foot level but free one STEP higher (and there is floor just past
# the edge), the body is lifted onto the step. Same rule as the player's step-up; the NPC capsule is lower than a
# tread's rise otherwise and would stand at the foot of the stairs for ever.
func _step_up(motion: Vector3, goal: Vector3) -> void:
	if not body.is_on_floor() or goal.y < body.global_position.y + 0.12 or motion.length_squared() < 0.000001:
		return
	var probe := motion.normalized() * maxf(motion.length(), 0.06)
	var here := body.global_transform
	if not body.test_move(here, probe):
		return
	var up := Vector3(0.0, STEP, 0.0)
	if body.test_move(here, up):
		return
	var raised := here.translated(up)
	var reach := motion.normalized() * 0.2
	if body.test_move(raised, reach):
		return
	var params := PhysicsTestMotionParameters3D.new()
	params.from = raised.translated(reach)
	params.motion = Vector3(0.0, -STEP - 0.02, 0.0)
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return
	var rise := STEP + result.get_travel().y
	if rise < 0.02:
		return
	body.global_position.y += rise
	body.global_position += reach * 0.5

var _exit_door: Node3D = null

func _door_at(point: Vector3) -> Node3D:
	for node in _doors_near(point, 0.6):
		var door := node as Node3D
		if door != null and Vector2(door.global_position.x - point.x, door.global_position.z - point.z).length() < 0.6 and absf(door.global_position.y - point.y) < 1.0:
			return door
	return null
