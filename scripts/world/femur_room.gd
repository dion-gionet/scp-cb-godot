extends Node3D
# SCP-106's containment chamber (MapSystem.bb FillRoom "room106", UpdateEvents.bb Case "room106"): the femur breaker.
#  - two levers at the observation window (Objects[1] the magnets, starts up; Objects[3] the sound transmission, starts down) and
#    the red button; the lure subject hangs in the cell (Objects[5]); the magnet platform (room1062.b3d, Objects[6]) sits at the
#    bottom of the chamber, rising to -980 with a wobble when the magnets are on and sinking to -1280 when off
#  - the transmission lever must be up for the button to work (it also carries the cell's sound and radio static to the speakers
#    everywhere: facility_map._update_femur); the button starts the breaker (state 1, FemurBreaker.ogg)
#  - 2500 frames on (the timer counts only while the transmission is up): 106 rises into the cell (bait: music 106, the
#    106Bait line, a stain). If the magnets are already on at that instant he comes out at once. 3200 frames on, magnets on = 106
#    is caught (Contained106), magnets off = he comes out of the platform and hunts (state 2). Between 2500 and 3200 the
#    transmission lever cannot be moved.
# Everything here only runs while the player is inside the room, except what the facility keeps (timer, levers, platform).


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
var levers: Array[Node3D] = []       # magnets, transmission
var button: Node3D
var platform: Node3D
var _button_pressed := false
var _subject_back := false           # the lure subject's breathing runs back (n\Idle)

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	for n in 2:
		var lever := Node3D.new()
		lever.set_script(Lever)
		add_child(lever)
		var start := 81.0 if n == 0 else -81.0
		if facility != null:
			start = float(facility.events.femur.levers[n])
		lever.setup(Vector3(-(555.0 - 81.0 * n) * RS, -576.0 * RS, -3040.0 * RS), -180.0, start)
		levers.append(lever)
	button = Node3D.new()
	button.set_script(PlainButton)
	button.position = Vector3(-146.0 * RS, -576.0 * RS, -3045.0 * RS)
	add_child(button)
	button.pressed.connect(func() -> void: _button_pressed = true)
	_build_platform(facility)

func _build_platform(facility: FacilityMap) -> void:
	platform = Node3D.new()
	var spot: Vector3 = room.fill_objects.get(6, Vector3(784.0 * RS, -980.0 * RS, -720.0 * RS))
	platform.position = Vector3(spot.x, facility.events.femur.platform_y if facility != null else spot.y, spot.z)
	add_child(platform)
	var mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/room1062.b3d"))
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3.ONE * RS
	platform.add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(Transform3D(Basis.from_scale(Vector3.ONE * RS), Vector3.ZERO) * mesh.get_faces())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	platform.add_child(body)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or levers.is_empty() or not facility.active:
		return
	var fps := delta * 70.0
	for n in 2:
		facility.events.femur.levers[n] = levers[n].pitch
	var subject := _subject(facility)
	var inside: bool = room.world_bounds().has_point(player.global_position)
	if not inside:
		if GameState.music_override in ["none", "106"] and GameState.selected_ending.is_empty():
			GameState.music_override = ""
		return
	if GameState.music_override.is_empty() or GameState.music_override == "none":
		GameState.music_override = "none"      # ShouldPlay = 66: no music in the chamber
	if subject != null:
		_hold_subject(subject, fps)
	_platform(facility, fps)
	var magnets_before: bool = facility.events.femur.magnets
	var platform_y: float = facility.events.femur.platform_y
	levers[0].locked = platform_y < -990.0 * RS and platform_y > -1275.0 * RS
	if GameState.grabbed_lever == levers[0]:
		facility.events.femur.magnets = levers[0].is_on()
	if facility.events.femur.magnets != magnets_before:
		Sfx.play_global(self, "SFX/Room/106Chamber/%s.ogg" % ("MagnetUp" if facility.events.femur.magnets else "MagnetDown"))
	var window: bool = facility.events.femur.state == 1 and facility.events.femur.timer <= 3200.0 and facility.events.femur.timer >= 2500.0
	levers[1].locked = window
	if not window:
		facility.events.femur.transmission = levers[1].is_on()
	if not facility.events.femur.transmission:
		_stop_voices(facility)
	if facility.events.femur.state == 0:
		_waiting(facility, fps)
	elif facility.events.femur.state == 1:
		_broken(facility, fps)
	_button_pressed = false

# NPC[0]: a Class D made once (the lure subject), at (1088, 1096, 1728) of the room.
func _subject(facility: FacilityMap) -> Node:
	if facility.events.femur.subject == null or not is_instance_valid(facility.events.femur.subject):
		facility.events.femur.subject = facility.spawn_human(HumanNpc.Kind.CLASS_D, room.to_global(Vector3(1088.0, 1096.0, -1728.0) * RS), -1)
		facility.events.femur.subject.state = 6
	return facility.events.femur.subject

# State 6: collider at Objects[5] (+0.1), the model 0.32 lower (NPCs.bb 2809); breathing between frames 17 and 19.
func _hold_subject(subject: Node, fps: float) -> void:
	subject.state = 6
	if not _subject_back:
		subject.animate(17.0, 19.0, 0.01, fps, false)
		if subject.frame == 19.0:
			_subject_back = true
	else:
		subject.animate(19.0, 17.0, -0.01, fps, false)
		if subject.frame == 17.0:
			_subject_back = false
	var at: Vector3 = room.object_point(5)
	if at != Vector3.INF:
		subject.global_position = at + Vector3(0.0, 0.1 - 0.32, 0.0)
		subject.velocity = Vector3.ZERO
		subject.rotation.y = room.rotation.y + PI

# The platform: up with a wobble while the magnets are on, down when off (CurveValue 200).
func _platform(facility: FacilityMap, fps: float) -> void:
	var t: float = GameState.clock_ms()
	var y: float = facility.events.femur.platform_y
	if facility.events.femur.magnets:
		var wanted := -980.0 * RS + sin(deg_to_rad(t * 0.04)) * 0.07
		y += (wanted - y) / 200.0 * fps
		platform.rotation.x = deg_to_rad(sin(deg_to_rad(t * 0.03)))
		platform.rotation.z = deg_to_rad(-sin(deg_to_rad(t * 0.025)))
	else:
		y += (-1280.0 * RS - y) / 200.0 * fps
		platform.rotation.x = 0.0
		platform.rotation.z = 0.0
	facility.events.femur.platform_y = y
	platform.position.y = y

func _say(facility: FacilityMap, relative: String) -> void:
	_stop_voices(facility)
	facility.events.femur.voice = Sfx.play_global(facility, relative)

func _speaking(facility: FacilityMap) -> bool:
	return facility.events.femur.voice != null and is_instance_valid(facility.events.femur.voice) and facility.events.femur.voice.playing

func _stop_voices(facility: FacilityMap) -> void:
	if facility.events.femur.voice != null and is_instance_valid(facility.events.femur.voice):
		facility.events.femur.voice.stop()
		facility.events.femur.voice.queue_free()
	facility.events.femur.voice = null
	if facility.events.femur.radio_static != null and is_instance_valid(facility.events.femur.radio_static):
		facility.events.femur.radio_static.stop()
		facility.events.femur.radio_static.queue_free()
	facility.events.femur.radio_static = null

# State 0: the subject mutters now and then; the button (with the transmission on) starts the breaker.
func _waiting(facility: FacilityMap, fps: float) -> void:
	if not facility.events.femur.transmission:
		return
	if randf() < fps / 100.0 and not _speaking(facility):
		_say(facility, "SFX/Character/LureSubject/Idle%d.ogg" % randi_range(1, 6))
	if _button_pressed:
		facility.events.femur.state = 1
		_say(facility, "SFX/Room/106Chamber/FemurBreaker.ogg")

# State 1: sniffling until 2000, then the bait from 2500 on.
func _broken(facility: FacilityMap, fps: float) -> void:
	var timer: float = facility.events.femur.timer
	if facility.events.femur.transmission and timer < 2000.0 and not _speaking(facility):
		_say(facility, "SFX/Character/LureSubject/Sniffling.ogg")
	if timer < 2500.0:
		return
	var man: Node = facility.scp106
	if man == null or not is_instance_valid(man):
		return
	var before := timer - fps
	if facility.events.femur.magnets and before < 2500.0:
		_release(facility, man)        # the magnets were on too soon: he is out at once
		return
	GameState.music_override = "106"
	var spot: Vector3 = room.fill_objects.get(5, Vector3.ZERO)
	if not facility.contained_106:
		man.idle = true
		man.visible = true
		man.state = -11.0
		man.global_position = room.to_global(Vector3(spot.x, (700.0 + 108.0 * minf(timer - 2500.0, 800.0) / 320.0) * RS, spot.z))
		man.rotation.y = room.rotation.y      # Objects[5]'s yaw (room + 180) + 180
		man.animate(206.0, 250.0, 0.1, fps)
	if before < 2500.0:
		var stain := GrowingDecal.make(get_parent(), room.to_global(Vector3(spot.x, 936.0 * RS, spot.z)), "GFX/decal1.png", 0.1, 0.003, 0.01, false) as GrowingDecal
		stain.alpha_change = 0.005
		_say(facility, "SFX/Character/LureSubject/106Bait.ogg")
	elif before < 2900.0 and timer >= 2900.0:
		_smear_lens()
	elif timer > 3200.0:
		if facility.events.femur.magnets:
			facility.contained_106 = true
		else:
			_release(facility, man)

# Objects[7] is the room's security camera: the stain is turned to the head's angles plus Rand(10,20) pitch and +30 yaw, moved 0.05 up
# and 0.2 ahead, then parented at the head's own angles (the 180 turn is commented out in the original).
func _smear_lens() -> void:
	if room.cams.is_empty():
		return
	var head: Node3D = room.cams[0]._head
	var turned := Basis.from_euler(Vector3(head.global_rotation.x - deg_to_rad(randi_range(10, 20)), head.global_rotation.y + deg_to_rad(30.0), 0.0))
	var offset := head.global_basis.orthonormalized().inverse() * (turned * Vector3(0.0, 0.05, -0.2))
	var decal := GrowingDecal.make(head, head.to_global(offset), "GFX/decal1.png", 0.05, 0.002, 0.01, false, Vector3.ZERO)
	decal.position = offset
	decal.alpha_change = 0.005

# 106 comes out of the magnet platform and hunts; the event is over (state 2).
func _release(facility: FacilityMap, man: Node) -> void:
	var spot: Vector3 = room.fill_objects.get(6, Vector3.ZERO)
	man.global_position = room.to_global(Vector3(spot.x, facility.events.femur.platform_y, spot.z))
	facility.contained_106 = false
	man.visible = true
	man.idle = false
	man.state = -11.0
	facility.events.femur.state = 2
