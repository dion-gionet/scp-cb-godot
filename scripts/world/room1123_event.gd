extends Node3D
# SCP-1123's room (UpdateEvents.bb Case "room1123", MapSystem.bb FillRoom "room1123"). Using SCP-1123 inside its room (item_use.gd
# sets EventState to 1) sends the player into its vision, an upper level of the same room with wooden doors and a Nazi officer:
#   1 the player is carried to Objects[4], hurt (1 injury), blurred; the officer appears at Objects[6]
#   2 the officer watches; at 200 frames the music, at 1000 the door (Objects[11]) swings open and he speaks (Officer1, Officer2);
#     walking more than 1.53 from Objects[4] carries the player to Objects[5], facing away from the room's front
#   3 when RoomDoors[0] is open (160) the officer moves to Objects[7]
#   4 the room's door shuts behind the player once past the entry; the door at Objects[13] must be pushed open (click it from within 1):
#     it swings to 90 and when it is past 30 degrees the officer turns on the player (frames 27-54)
#   5 500 frames after the blow the player lies with 1.5 injuries and 70 blood loss between Objects[8] and [12], the officer by him
#   6 the officer stands over him speaking (Officer3, frames 75-128); when he has finished a shot is fired
#   7 the player is back in the room, flashed, with injuries, blood loss and light restored; the leaflet is gone; the achievement
# Saving is refused from 1 to 6. EventState is kept by facility.ambient (8 is "over"). Positions are the room's scaled space (z flipped).

const RS := 8.0 / 2048.0

var room: FacilityRoom
var officer: CharacterBody3D = null
var frames_and_doors: Dictionary = {}     # Objects[8..13]: three door frames and the three doors
var door_yaw: Dictionary = {11: 90.0, 9: 0.0, 13: 0.0}
var _voice: AudioStreamPlayer3D = null
var _music: AudioStreamPlayer = null
var _door_sound := false
var _was_here := false

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var placements := {
		8: [Vector3(-272.0, 512.0, 288.0), 90.0, Vector3(45.0, 45.0, 80.0), "door_frame"],
		9: [Vector3(-272.0, 512.0, 288.0 - 70.0), 10.0, Vector3(46.0, 45.0, 46.0), "door"],
		10: [Vector3(-272.0, 512.0, 736.0), 90.0, Vector3(45.0, 45.0, 80.0), "door_frame"],
		11: [Vector3(-272.0, 512.0, 736.0 - 70.0), 90.0, Vector3(46.0, 45.0, 46.0), "door"],
		12: [Vector3(-592.0, 512.0, -704.0), 0.0, Vector3(45.0, 45.0, 80.0), "door_frame"],
		13: [Vector3(-(592.0 + 70.0), 512.0, -704.0), 0.0, Vector3(46.0, 45.0, 46.0), "door"],
	}
	for index in placements:
		var entry: Array = placements[index]
		var at: Vector3 = entry[0]
		var node := MeshInstance3D.new()
		node.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/forest/%s.b3d" % entry[3]))
		var scale_raw: Vector3 = entry[2]
		node.scale = scale_raw * RS
		add_child(node)
		node.position = Vector3(at.x * RS, at.y * RS, -at.z * RS)
		node.rotation.y = deg_to_rad(float(entry[1]))
		frames_and_doors[index] = node
	door_yaw = {9: 10.0, 11: 90.0, 13: 0.0}

func _exit_tree() -> void:
	GameState.save_blocked = false
	_stop_sounds()

func _stop_sounds() -> void:
	for voice in [_voice, _music]:
		if voice != null and is_instance_valid(voice):
			voice.stop()
	_voice = null
	_music = null

func _set_door(index: int, yaw: float) -> void:
	door_yaw[index] = yaw
	(frames_and_doors[index] as Node3D).rotation.y = deg_to_rad(yaw)

func _curve_angle(target: float, current: float, smooth: float, fps: float) -> float:
	return current + wrapf(target - current, -180.0, 180.0) / maxf(smooth, 1.0) * fps

func _spot(index: int) -> Vector3:
	return room.object_point(index)

# PositionEntity Collider at a pivot (the pivots are collider height; the player's origin is the feet)
func _carry(player: CharacterBody3D, at: Vector3, yaw: float = NAN) -> void:
	player.global_position = Vector3(at.x, at.y - 0.3, at.z)
	player.velocity = Vector3.ZERO
	if not is_nan(yaw):
		player.rotation.y = yaw

func _make_officer(facility: FacilityMap) -> void:
	var at := _spot(6)
	officer = facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(at.x, at.y - 0.3, at.z), -1, "GFX/npcs/naziofficer.b3d")
	officer.add_to_group("scp1123_officer")

func _face(who: Node3D, point: Vector3) -> void:
	var flat := Vector2(point.x - who.global_position.x, point.z - who.global_position.z)
	if flat.length() > 0.0001:
		who.rotation.y = atan2(-flat.x, -flat.y)

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or facility.ambient == null or not facility.active or frames_and_doors.is_empty():
		return
	var fps := delta * 70.0
	var st: Dictionary = facility.ambient.state_of(room.room_key)
	var here: bool = str(facility.record_at(player.global_position).get("key", "")) == room.room_key
	if not here:
		if _was_here:
			_was_here = false
			GameState.save_blocked = false
		return
	_was_here = true
	GameState.save_blocked = st.s > 0.0 and st.s < 7.0
	if st.s >= 8.0 or st.s <= 0.0:
		return
	if st.s >= 2.0 and (officer == null or not is_instance_valid(officer)):
		officer = null
		for node in get_tree().get_nodes_in_group("scp1123_officer"):
			if is_instance_valid(node):
				officer = node
		if officer == null:
			_make_officer(facility)
	var s := GameState
	var door: Node3D = room.door_slots.get(0)
	match int(st.s):
		1:
			st.prev_injuries = s.injuries
			st.prev_bloodloss = s.bloodloss
			st.prev_light = s.secondary_light
			s.secondary_light = 1.0
			_make_officer(facility)
			_carry(player, _spot(4))
			player.camera_shake = 1.0
			s.blur_timer = 1200.0
			s.injuries = 1.0
			st.s = 2.0
		2:
			st.s2 += fps
			_face(officer, player.global_position)
			s.blur_timer = maxf(s.blur_timer, 100.0)
			if st.s2 > 200.0 and st.s2 - fps <= 200.0:
				_music = Sfx.play_global(self, "SFX/Music/1123.ogg")
			if st.s2 > 1000.0:
				if not _door_sound:
					_door_sound = true
					Sfx.play_global(self, "SFX/Door/1123DoorOpen.ogg")
				_set_door(11, _curve_angle(10.0, door_yaw[11], 40.0, fps))
				if st.s2 >= 1040.0 and st.s2 - fps < 1040.0:
					Sfx.play_at(officer, "SFX/SCP/1123/Officer1.ogg", 10.0)
				elif st.s2 >= 1400.0 and st.s2 - fps < 1400.0:
					Sfx.play_at(officer, "SFX/SCP/1123/Officer2.ogg", 10.0)
				officer.state = 3
				officer.animate(3.0, 26.0, 0.2, fps, true)
				if (player.global_position + Vector3(0.0, 0.3, 0.0)).distance_to(_spot(4)) > 392.0 * RS:
					player.blink_timer = -10.0
					s.blur_timer = 500.0
					_carry(player, _spot(5), room.rotation.y + PI)
					st.s = 3.0
		3:
			if door != null and door.openstate > 160.0:
				_music = Sfx.play_global(self, "SFX/Music/1123.ogg")
				var at := _spot(7)
				officer.global_position = Vector3(at.x, at.y - 0.3, at.z)
				officer.velocity = Vector3.ZERO
				st.s = 4.0
		4:
			var local: Vector3 = room.to_local(player.global_position)
			if local.x < 256.0 * RS and local.z < 480.0 * RS and door != null:
				door.open = false
			if door_yaw[13] == 0.0:
				if (player.global_position + Vector3(0.0, 0.3, 0.0)).distance_to(_spot(12)) < 1.0:
					s.hand_icon = true
					if Input.is_action_just_pressed("interact"):
						_set_door(13, 1.0)
						_set_door(11, 90.0)
						Sfx.play_global(self, "SFX/SCP/1123/Horror.ogg")
			else:
				_set_door(13, _curve_angle(90.0, door_yaw[13], 40.0, fps))
				if door_yaw[13] > 30.0:
					officer.state = 3
					_face(officer, player.global_position)
					officer.animate(27.0, 54.0, 0.5, fps, false)
					if officer.frame >= 54.0:
						st.s = 5.0
						st.s2 = 0.0
						_carry(player, Vector3(room.global_position.x, room.global_position.y + 0.3, room.global_position.z))
						player.blink_timer = -10.0
						s.blur_timer = 500.0
						s.injuries = 1.5
						s.bloodloss = 70.0
		5:
			st.s2 += fps
			if st.s2 > 500.0:
				_set_door(9, 90.0)
				_set_door(13, 0.0)
				var a := _spot(8)
				var b := _spot(12)
				var floor_spot := _spot(5)
				var middle := Vector3((a.x + b.x) * 0.5, floor_spot.y, (a.z + b.z) * 0.5)
				_carry(player, middle)
				var officer_at := Vector3((player.global_position.x + b.x) * 0.5, floor_spot.y - 0.3 + 0.2, (player.global_position.z + b.z) * 0.5)
				officer.global_position = officer_at
				officer.velocity = Vector3.ZERO
				s.injuries = 1.5
				s.bloodloss = 70.0
				player.blink_timer = -10.0
				GrowingDecal.make(get_parent(), Vector3(player.global_position.x, room.global_position.y + 512.0 * RS + 0.0005, player.global_position.z), "GFX/decal4.png", 0.5, 0.0, 0.8, false)
				_voice = Sfx.play_at(officer, "SFX/SCP/1123/Officer3.ogg", 7.0)
				st.s = 6.0
		6:
			_face(officer, player.global_position)
			officer.animate(75.0, 128.0, 0.04, fps, true)
			if _voice == null or not is_instance_valid(_voice) or not _voice.playing:
				Sfx.play_global(self, "SFX/SCP/1123/Gunshot.ogg")
				st.s = 7.0
		7:
			_carry(player, Vector3(room.global_position.x, room.global_position.y + 0.3, room.global_position.z))
			s.light_flash = 6.0
			s.blur_timer = 500.0
			s.injuries = float(st.get("prev_injuries", 0.0))
			s.bloodloss = float(st.get("prev_bloodloss", 0.0))
			s.secondary_light = float(st.get("prev_light", 1.0))
			_set_door(9, 0.0)
			player.crouching = false
			var hud := _hud()
			for i in hud.items.size():
				if hud.items[i] == "Leaflet":
					hud.items[i] = ""
					hud.item_data[i] = {}
					break
			s.give_achievement("1123")
			if officer != null and is_instance_valid(officer):
				facility.remove_human(officer)
			officer = null
			st.s = 8.0
			s.save_blocked = false
