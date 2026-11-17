extends Node3D
# The Apache helicopters of the gates (NPCs.bb NPCtypeApache). A flying body of radius 3, scaled 0.6, with a main rotor (three
# copies, the outer two 4 degrees either side and half transparent), a tail rotor, and a pair of lights.
#  state 0/1  hovering (rotors turning); a state 1 helicopter that sees the player within 30 / 30 / 20 (1 in 20 frames) goes to 2
#             with the third alarm
#  state 2    hunts the player; state 3 hunts the point in `enemy` (the battle at gate B, 106 at gate A)
#             - turns to face it, rises/falls to 8 above it, closes to 6.5 away, banks while it cannot see it
#             - while it sees the target and is within 20 it fires every 5 frames if aimed within 10 degrees: the shot at the player
#               lands with (10 / dist) / dist, with the original's death note
#  state 4    crash: spins, drifts to `enemy` faster and faster, at 0.3 from it the crash sound and a shake, then state 5 (wreck)
# `yaw`, `pitch` and `roll` are Blitz angles in degrees (pitch positive = nose down).


const MODEL_SCALE := 0.6

var state := 1
var state2 := 0.0
var enemy := Vector3.ZERO       # EnemyX/Y/Z
var reload := 0.0
var curr_speed := 0.0
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var path_status := 0           # "target is visible"
var path_timer := 0.0
var shots := 0
var gate_name := "B"

var _body: Node3D
var _rotor: Node3D
var _tail: Node3D
var _loop: AudioStreamPlayer3D

func _ready() -> void:
	rotation_order = EULER_ORDER_YXZ
	add_to_group("apache")
	_body = Node3D.new()
	add_child(_body)
	var hull := B3DModel.new()
	hull.load_file(ContentPaths.existing_file("GFX/apache.b3d"))
	hull.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(hull)
	_rotor = Node3D.new()
	_rotor.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(_rotor)
	for blur in [0.0, -4.0, 4.0]:
		var blade := B3DModel.new()
		blade.load_file(ContentPaths.existing_file("GFX/apacherotor.b3d"))
		blade.rotation.y = deg_to_rad(blur)
		_rotor.add_child(blade)
	_tail = Node3D.new()
	_tail.position = Vector3(0.0, 2.15, 5.48) * MODEL_SCALE
	_tail.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(_tail)
	var tail_blade := B3DModel.new()
	tail_blade.load_file(ContentPaths.existing_file("GFX/apacherotor2.b3d"))
	_tail.add_child(tail_blade)
	var light_texture := MeshLoader._load_texture(ContentPaths.existing_image("GFX/light1.jpg"))
	for side in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 2.0
		lamp.set_meta("blitz_range", 2.0)
		lamp.set_meta("blitz_colour", Color.WHITE)
		lamp.add_to_group("entity_lights")
		lamp.position = Vector3(1.65 * side, 1.17, 0.25) * MODEL_SCALE
		_body.add_child(lamp)
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.26
		glow.mesh = quad
		glow.material_override = GammaBlend.make(light_texture, Color.WHITE, true, true, false)
		glow.position = lamp.position
		_body.add_child(glow)
	_loop = AudioStreamPlayer3D.new()
	_loop.max_distance = 25.0
	var propeller := Sfx.stream("SFX/Character/Apache/Propeller.ogg")
	if propeller != null:
		propeller.loop = true
		_loop.stream = propeller
	add_child(_loop)
	_apply_angles()

func _apply_angles() -> void:
	rotation = Vector3(-deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll))

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or not facility.active:
		return
	var fps := delta * 70.0
	var dist := global_position.distance_to(player.global_position)
	if dist < 60.0:
		if not _loop.playing and state != 5:
			_loop.play()
		var volume := 1.0
		if facility.room_name_at(player.global_position) == "exit1" and facility.exit1_centre != Vector3.INF:
			volume = clampf(global_position.distance_to(facility.exit1_centre) / (8000.0 * MeshLoader.ROOM_SCALE), 0.0, 1.0)
		_loop.volume_db = linear_to_db(maxf(volume, 0.0001))
	elif _loop.playing:
		_loop.stop()
	match state:
		0, 1:
			_spin(fps)
			if state == 1 and not GameState.no_target_mode():
				var d := player.global_position - global_position
				if absf(d.x) < 30.0 and absf(d.z) < 30.0 and absf(d.y) < 20.0 and randi_range(1, 20) == 1:
					if _visible(player.global_position):
						state = 2
						Sfx.play_at(self, "SFX/Alarm/Alarm3.ogg", 50.0)
		2, 3:
			_spin(fps)
			_attack(fps, player, facility)
		4:
			_crash(fps)
	_apply_angles()

func _spin(fps: float) -> void:
	_rotor.rotation.y += deg_to_rad(20.0 * fps)
	_tail.rotation.x += deg_to_rad(20.0 * fps)

func _visible(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, point)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# Blitz yaw / pitch (degrees, pitch positive = nose down) of the direction to a point
func _yaw_to(point: Vector3) -> float:
	return rad_to_deg(atan2(-(point.x - global_position.x), -(point.z - global_position.z)))

func _pitch_to(point: Vector3) -> float:
	var horizontal := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	return rad_to_deg(atan2(-(point.y - global_position.y), horizontal))

func _curve_angle(wanted: float, current: float, smooth: float, fps: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(current), deg_to_rad(wanted), minf(fps / smooth, 1.0)))

func _curve_value(wanted: float, current: float, smooth: float, fps: float) -> float:
	var step := (wanted - current) * (fps / smooth)
	if wanted < current:
		return maxf(current + step, wanted)
	return minf(current + step, wanted)

func _attack(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var target: Vector3 = player.global_position if state == 2 else enemy
	if GameState.no_target_mode() and state == 2:
		state = 1
	if absf(target.x - global_position.x) >= 55.0 or absf(target.z - global_position.z) >= 55.0 or absf(target.y - global_position.y) >= 20.0:
		return
	var wanted_pitch := fposmod(_pitch_to(target), 360.0)
	pitch = _curve_angle(minf(wanted_pitch, 40.0), pitch, 40.0, fps)
	yaw = _curve_angle(_yaw_to(target), yaw, 90.0 if state == 2 else 90.0, fps)
	global_position.y = _curve_value(target.y + 8.0, global_position.y, 70.0, fps)
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	curr_speed = _curve_value(minf(flat - 6.5, 6.5) * 0.008, curr_speed, 50.0, fps)
	var heading := Vector3(-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))
	global_position += heading * curr_speed * fps
	if path_timer == 0.0:
		path_status = 1 if _visible(target) else 0
		path_timer = randf_range(100.0, 200.0)
	else:
		path_timer = minf(path_timer - fps, 0.0)
	if path_status == 1:
		roll = _curve_angle(0.0, roll, 40.0, fps)
		if reload <= 0.0 and flat < 20.0:
			var muzzle := global_position + Basis.from_euler(Vector3(-deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll)), EULER_ORDER_YXZ) * Vector3(0.0, 8.87 * (0.21 / 9.0), -8.87 * (1.7 / 9.0))
			var to_target := target - muzzle
			var aim := rad_to_deg(wrapf(atan2(-to_target.x, -to_target.z) - deg_to_rad(yaw), -PI, PI))
			if absf(aim) < 10.0:
				Sfx.play_at(self, "SFX/General/Gunshot2.ogg", 20.0)
				shots += 1
				if state == 2:
					var note := "\"CH-2 to control. Shot down a runaway Class D at Gate %s.\"" % gate_name
					var distance := maxf(global_position.distance_to(target), 0.1)
					Gunfire.shoot(self, muzzle, (10.0 / distance) * (1.0 / distance), note, false, true)
				else:
					Gunfire.flash(self, muzzle)
					Gunfire.light_up(self)
				reload = 5.0
	else:
		roll = _curve_angle(-20.0, roll, 40.0, fps)
	var strafe := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
	global_position += strafe * (-roll * 0.002) * fps
	reload -= fps

func _crash(fps: float) -> void:
	if state2 >= 300.0:
		return
	_spin(fps)
	yaw -= fps * 7.0
	state2 += fps * 0.3
	var to := enemy - global_position
	var step := to.normalized() * fps * 0.001 * state2
	global_position += step
	if global_position.distance_to(enemy) < 0.3:
		var player: CharacterBody3D = GameState.player
		if player != null:
			player.camera_shake = maxf(player.camera_shake, 3.0)
		Sfx.play_global(self, "SFX/Character/Apache/Crash%d.ogg" % randi_range(1, 2))
		state = 5
		_loop.stop()
