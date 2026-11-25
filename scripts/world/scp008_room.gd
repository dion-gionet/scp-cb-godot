extends Node3D
# The SCP-008 chamber and its event (UpdateEvents.bb Case "008"; FillRoom "008" for the props).
#  - the container Objects[0] with its lid Objects[1] (008_2.b3d, the lever), the window Objects[2] (glass sprite),
#    the red alarm light Objects[5], 173's spawn point Objects[3] and attack point Objects[4]
#  - EventState 0: if 173 is out of reach it is moved into the room's corner; 1: the alarm sounds and the light blinks;
#    near the container (2 units) the doors lock, the window can break (173 appears at the container while the player
#    does not look, or blinks: a cut from the glass infects without a hazmat suit), and within 1 the lever can be pulled
#    with the mouse; gas rises from the container until it is down (pitch under 40). Then EventState 2: the doors
#    unlock, the alarm stops, the lever settles back and the event is over. The HCZ/EZ checkpoint is locked until this
#    happens (checkpoint_monitors.gd).


const RS := MeshLoader.ROOM_SCALE

var room: FacilityRoom
# EventState and the broken window are kept in events.room008 for a save; EventState2 is the window
var event_state := 0:
	set(value):
		event_state = value
		if _saved() != null:
			_saved().state = value
var event_state2: int:
	get:
		return 1 if window_broken else 0
var lever_pitch := 89.0         # the lid (Blitz pitch); under 40 the container counts as open
var gas_emitted := 0
var window_broken := false:
	set(value):
		window_broken = value
		if _saved() != null:
			_saved().window_broken = value
var light_on := false

var _lid: Node3D
var _window: MeshInstance3D
var _light: MeshInstance3D
var _gas_carry := 0.0
var _alarm: AudioStreamPlayer3D
var _door_a: Node3D     # RoomDoors[0] (linked to [1])
var _door_b: Node3D     # RoomDoors[1]
var _door_c: Node3D     # RoomDoors[2]

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var fo: Dictionary = room.fill_objects
	# the lid: pitch 89 up from the container's lip; pulling the mouse down lowers the pitch
	var lid_mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/008_2.b3d"))
	_lid = MeshInstance3D.new()
	(_lid as MeshInstance3D).mesh = lid_mesh
	_lid.scale = Vector3.ONE * RS
	_lid.position = fo.get(1, Vector3.ZERO)
	add_child(_lid)
	_lid.rotation.x = -deg_to_rad(lever_pitch)
	_window = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(256.0 * RS, 194.0 * RS)
	_window.mesh = quad
	_window.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/glass.png")))
	_window.position = fo.get(2, Vector3.ZERO)
	_window.rotation.y = deg_to_rad(90.0)
	_window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_window.visible = true
	add_child(_window)
	_light = MeshInstance3D.new()
	var dot := QuadMesh.new()
	dot.size = Vector2(0.04, 0.04)
	_light.mesh = dot
	_light.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/light2.jpg")), Color(1.0, 0.15, 0.1), true, true, false)
	_light.position = fo.get(5, Vector3.ZERO)
	_light.visible = false
	add_child(_light)
	_alarm = AudioStreamPlayer3D.new()
	var alarm_stream: AudioStreamOggVorbis = Sfx.stream("SFX/Alarm/Alarm.ogg")
	if alarm_stream != null:
		alarm_stream = alarm_stream.duplicate()      # the cached stream is shared with the start room's alarm, which must not loop
		alarm_stream.loop = true
		_alarm.stream = alarm_stream
	_alarm.max_distance = 5.0
	_alarm.position = fo.get(0, Vector3.ZERO)
	add_child(_alarm)
	# doors: RoomDoors[0] and [1] are linked, [2] is locked from the start
	var doors: Array = room._fill_doors
	if doors.size() >= 3:
		_door_a = doors[0]
		_door_b = doors[1]
		_door_c = doors[2]
		_door_a.linked_door = _door_b
		_door_b.linked_door = _door_a
		_door_c.locked = true
	# the event is over once the lever was pulled (a loaded game builds the room afterwards)
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		event_state = facility.events.room008.state
		window_broken = facility.events.room008.window_broken
		_window.visible = not window_broken
	if facility != null and facility.events.sl.scp008_done:
		event_state = 2
		lever_pitch = 1.0
		_lid.rotation.x = -deg_to_rad(lever_pitch)
		for door in [_door_a, _door_b, _door_c]:
			if door != null:
				door.locked = false

func container() -> Vector3:
	return room.to_global(room.fill_objects.get(0, Vector3.ZERO))

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null:
		return
	if event_state == 2 and facility.events.sl.scp008_done:
		_finish(delta)
		return
	var in_room: bool = room.world_bounds().has_point(player.global_position)
	if not in_room:
		_alarm.stop()
		_light.visible = false
		return
	GameState.give_achievement("008")
	var statue: Node3D = GameState.scp173
	if event_state == 0:
		if statue != null and statue.idle < 2 and statue.global_position.distance_to(player.global_position) > 15.0:
			var spot: Vector3 = room.to_global(room.fill_objects.get(3, Vector3.ZERO))
			statue.put_at_collider(Vector3(spot.x, room.global_position.y + 0.5, spot.z))
		event_state = 1
	elif event_state == 1:
		if not _alarm.playing:
			_alarm.play()
		light_on = int(GameState.clock_ms()) % 1000 < 500
		_light.visible = light_on
		var dist := player.global_position.distance_to(container())
		if dist < 2.0:
			_door_a.locked = true
			_door_b.locked = true
			if event_state2 == 0:
				_window.visible = true
				_try_break_window(player, statue)
			if dist < 1.0 and player.camera.is_position_in_frustum(container()):
				GameState.hand_icon = true
				if Input.is_action_pressed("interact"):
					GameState.arrow_icons[2] = true
					lever_pitch = clampf(lever_pitch + clampf(-player.mouse_speed.y, -10.0, 10.0), 35.0, 89.0)
			if GameState.wearing_hazmat == 0 and GameState.bloodloss > 0.0 and GameState.infect == 0.0:
				GameState.infect = 1.0     # bleeding next to the open container
		if lever_pitch < 40.0:
			event_state = 2
			facility.events.sl.scp008_done = true
			Sfx.play_global(self, "SFX/Interact/LeverFlip.ogg")
		else:
			_puff(facility, delta * 70.0)
	_lid.rotation.x = -deg_to_rad(lever_pitch)

func _puff(facility: FacilityMap, fps: float) -> void:
	_gas_carry += fps
	while _gas_carry >= 1.0:
		_gas_carry -= 1.0
		var p = facility.particles.create(container(), 6, 0.02, -0.12)
		if p != null:
			p.size_change = 0.012
			p.a_change = -0.015
			gas_emitted += 1

# The glass breaks when 173 can step up to the container unseen.
func _try_break_window(player: CharacterBody3D, statue: Node3D) -> void:
	if statue == null:
		return
	var attack: Vector3 = room.to_global(room.fill_objects.get(4, Vector3.ZERO))
	if statue.global_position.distance_to(attack) >= 3.0:
		return
	var unseen: bool = player.blink_timer < -10.0 or not player.camera.is_position_in_frustum(statue.global_position + Vector3(0.0, 0.5, 0.0))
	if unseen and statue.idle == 0:
		statue.put_at_collider(Vector3(attack.x, room.global_position.y + 0.5, attack.z))
		_window.visible = false
		window_broken = true
		if GameState.wearing_hazmat == 0:
			GameState.injuries += 0.1
			if GameState.infect == 0.0:
				GameState.infect = 1.0
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null:
				hud.message("The window shattered and a piece of glass cut your arm.", 8.0)
		Sfx.play_at(self, "SFX/General/GlassBreak.ogg", 12.0)

# EventState 2: the doors are free, the alarm is off, the lever settles back and the event ends.
func _finish(delta: float) -> void:
	_alarm.stop()
	_light.visible = false
	for door in [_door_a, _door_b, _door_c]:
		if door != null and is_instance_valid(door):
			door.locked = false
	lever_pitch += (1.0 - lever_pitch) * minf(delta * 70.0 / 15.0, 1.0)
	_lid.rotation.x = -deg_to_rad(lever_pitch)

func _saved() -> EventStates.Room008:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap if is_inside_tree() else null
	return facility.events.room008 if facility != null else null
