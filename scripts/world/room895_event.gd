extends Node3D
# SCP-895's chamber (UpdateEvents.bb Case "coffin" / "coffin106", MapSystem.bb FillRoom "coffin"):
#  - a lever beside the door (starts up, pitch 10): it turns the chamber's own monitor on, and while it is up and the player is
#    past the first zone 079 can show the feed on the other monitors (facility.coffin_broadcast, security_cam.gd)
#  - Objects[1] is the coffin, 6 m down the pit. Within 1.5 of it the 895 achievement is given and, in the "coffin106" version
#    (4 maps in 5) while 106 is not contained, a corrosion stain grows under the coffin and 106 is sent there (state -0.1)
#  - within 3 of it a dead guard hangs over the pit (frame 270, a radio at his belt); once the player is 5 away he screams, a
#    second later he falls into the pit, lands (frames 270-286) with a blood pool, and his radio keeps hissing
#  - with night vision (plain, super or very fine, with power left, no ring) within 4 of the coffin the player is turned to face
#    it and looks up, the sanity falls (1.1 per frame, divided by the goggles' kind), the view blurs and the goggles' overlay shows
#    horror pictures (below -500 now and then, below -800 mostly, with vomiting); at -1000 and after vomiting it kills
#  - the music is silent in the room, and CoffinDistance is the player's distance to the coffin (to the room outside it)
# Positions are room-local Blitz metres, z flipped here.

const RS := 8.0 / 2048.0

const PIT_FLOOR := -1531.0 * RS            # the pit's floor, room-local y
const GUARD_FEET_OFFSET := 0.2              # the guard's collider centre is 0.2 above his feet

var room: FacilityRoom
var lever: Node3D
var guard: CharacterBody3D = null
var _phase := 0                     # PrevState of the guard: 0 hangs, 1 falls, 2 lies in the pit
var _scream_wait := 0.0             # State2: frames the guard still hangs after he screams
var _fall_speed := 0.0
var _landed := false
var _radio: AudioStreamPlayer3D = null
var _idle_voice: AudioStreamPlayer3D = null
var _guard_voice: AudioStreamPlayer3D = null

func build(room_node: FacilityRoom) -> void:
	room = room_node
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	lever = Node3D.new()
	lever.set_script(Lever)
	add_child(lever)
	var pitch := 10.0
	if facility != null:
		pitch = float(facility.events.coffin.lever_pitch)
	lever.setup(Vector3(-800.0 * RS, 180.0 * RS, 336.0 * RS), 0.0, pitch, 0.04)
	if facility != null and facility.events.coffin.guard_state > 0:
		_make_guard(2)

func _exit_tree() -> void:
	GameState.coffin_distance = 100.0
	if GameState.music_override == "none":
		GameState.music_override = ""

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null or room == null or lever == null or not facility.active:
		return
	var fps := delta * 70.0
	facility.events.coffin.lever_pitch = lever.pitch
	var now := GameState.clock_ms()
	if facility.events.coffin.next_broadcast_ms < now:
		_set_monitors(facility, player)
		facility.events.coffin.next_broadcast_ms = now + 3000.0
	var coffin: Vector3 = room.object_point(1)
	var inside: bool = room.world_bounds().has_point(player.global_position)
	if not inside:
		GameState.coffin_distance = player.global_position.distance_to(room.global_position)
		if GameState.music_override == "none":
			GameState.music_override = ""
		_update_guard(player, fps, false)
		return
	var dist := player.global_position.distance_to(coffin)
	GameState.coffin_distance = dist
	if dist < 1.5:
		GameState.give_achievement("895")
		if facility.coffin_is_106() and not facility.contained_106 and facility.events.coffin.event_state2 == 0:
			_send_106(facility, coffin)
	elif dist < 3.0:
		if guard == null and facility.events.coffin.guard_state == 0:
			_make_guard(0)
	elif dist > 5.0:
		if is_instance_valid(guard) and _phase == 0:
			_scream()
	_update_guard(player, fps, true)
	_night_vision(player, fps, dist, coffin)
	GameState.music_override = "none"

func _set_monitors(facility: FacilityMap, player: CharacterBody3D) -> void:
	if facility.zone_at(player.global_position) <= 0:
		return
	var feed_on: bool = lever.pitch > 0.0
	for cam: SecurityCam in get_tree().get_nodes_in_group("security_cam"):
		var cam_room: Variant = cam.room.get("room_name") if cam.room != null else null
		if feed_on:
			if cam.coffin_effect == 0 and cam_room != "room106" and cam_room != "room205":
				cam.coffin_effect = 2
		elif cam.coffin_effect != 1:
			cam.coffin_effect = 0
		if cam.room == room:
			cam.screen_on = feed_on

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

# The stain under the coffin; 106 is moved there and told to come up (state -0.1).
func _send_106(facility: FacilityMap, coffin: Vector3) -> void:
	GrowingDecal.make(room, Vector3(coffin.x, room.global_position.y + PIT_FLOOR + 0.01, coffin.z), "GFX/decal1.png", 0.05, 0.001, 0.8, true)
	var old_man: Node = facility.scp106
	if old_man != null and is_instance_valid(old_man) and old_man.state > 0.0:
		old_man.global_position = Vector3(coffin.x, -10240.0 * RS, coffin.z)
		old_man.state = -0.1
		old_man.visible = true
		facility.events.coffin.event_state2 = 1

func _make_guard(phase: int) -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var at := room.global_position + Vector3(0.0, -GUARD_FEET_OFFSET, 0.0)
	if phase == 2:
		at.y = room.global_position.y + PIT_FLOOR + 0.15
	guard = facility.spawn_human(0, at)
	guard.state = 8
	guard.is_dead = true
	guard.rotation.y = room.rotation.y + PI * 0.5
	guard.set_frame(286.0 if phase == 2 else 270.0)
	guard.set_physics_process(false)         # the event holds him (GravityMult 0) and drops him itself
	_phase = phase
	_landed = phase == 2
	if phase == 2:
		facility.events.coffin.guard_state = 2
		_start_radio()
	else:
		_idle_voice = _voice_at(guard, "SFX/Room/895Chamber/GuardIdle%d.ogg" % randi_range(1, 3), 14.0)

func _voice_at(npc: Node3D, relative: String, range_m: float) -> AudioStreamPlayer3D:
	var source := Sfx.stream(relative)
	if source == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = source
	voice.max_distance = range_m
	npc.add_child(voice)
	voice.play()
	voice.finished.connect(voice.queue_free)
	return voice

func _scream() -> void:
	if _idle_voice != null and is_instance_valid(_idle_voice):
		_idle_voice.stop()
	_guard_voice = _voice_at(guard, "SFX/Room/895Chamber/GuardScream%d.ogg" % randi_range(1, 3), 100.0)
	_phase = 1
	_scream_wait = 0.0
	(get_tree().get_first_node_in_group("facility") as FacilityMap).events.coffin.guard_state = 1

func _start_radio() -> void:
	if guard == null or (_radio != null and is_instance_valid(_radio)):
		return
	var source := Sfx.stream("SFX/Room/895Chamber/GuardRadio.ogg")
	if source == null:
		return
	_radio = AudioStreamPlayer3D.new()
	_radio.stream = source
	_radio.max_distance = 5.0
	guard.add_child(_radio)
	_radio.finished.connect(func() -> void: if is_instance_valid(_radio): _radio.play())
	_radio.play()

func _update_guard(_player: CharacterBody3D, fps: float, inside: bool) -> void:
	if guard == null or not is_instance_valid(guard) or not inside:
		return
	if _phase == 1:
		_start_radio()
		if _scream_wait < 70.0:
			_scream_wait += fps
			return
		var delta := fps / 70.0
		_fall_speed = maxf(_fall_speed - 0.005 * 70.0 * 70.0 * delta, -0.2 * 70.0)
		var stop_y := room.global_position.y + PIT_FLOOR + 0.35 - GUARD_FEET_OFFSET
		if guard.global_position.y > stop_y:
			guard.global_position.y += _fall_speed * delta
			return
		if not _landed:
			_landed = true
			Sfx.play_global(self, "SFX/General/BodyFall.ogg")
			GrowingDecal.make(room, Vector3(room.global_position.x, room.global_position.y + PIT_FLOOR + 0.01, room.global_position.z), "GFX/decal4.png", 0.4, 0.0, 1.0, false)
		guard.animate(270.0, 286.0, 0.4, fps, false)
		if guard.frame >= 286.0:
			_phase = 2
			(get_tree().get_first_node_in_group("facility") as FacilityMap).events.coffin.guard_state = 2

func _night_vision(player: CharacterBody3D, fps: float, dist: float, coffin: Vector3) -> void:
	var s := GameState
	var hud := _hud()
	var kind := s.wearing_night_vision
	if kind == 0 or dist >= 4.0 or s.wearing_714 or not _has_power(hud, kind):
		return
	var to := coffin - player.global_position
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(fps / 4.0, 1.0))
	var flat := Vector2(to.x, to.z).length()
	var up := -60.0 * minf(maxf((2.0 - flat) / 2.0, 0.0), 1.0)
	player.user_pitch = player.user_pitch * 0.8 + up * 0.2
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	s.sanity -= fps * 1.1 / float(kind)
	s.restore_sanity = false
	s.blur_timer = (sin(deg_to_rad(s.clock_ms() / 10.0))) * absf(s.sanity)
	if s.vomit_timer < 0.0:
		s.restore_sanity = false
		s.sanity = -1010.0
	if s.sanity < -1000.0:
		hud.nv_picture = ""
		if s.vomit_timer < -10.0:
			if kind > 1:
				player.kill("\"Class D viewed SCP-895 through a pair of digital night vision goggles, presumably enhanced by SCP-914. It might be possible that the subject was able to resist the memetic effects partially through these goggles. The goggles have been stored for further study.\"")
			else:
				player.kill("\"Class D viewed SCP-895 through a pair of digital night vision goggles, killing him.\"")
	elif s.sanity < -800.0:
		if randi_range(1, 3) == 1:
			hud.nv_picture = ""
		if randi_range(1, 6) < 5:
			hud.nv_picture = "GFX/895pics/pic%d.jpg" % randi_range(1, 6)
			var worn := _worn_item(hud, kind)
			if worn >= 0:
				if float(hud.item_data[worn].get("state2", 0.0)) == 1.0:
					Sfx.play_global(self, "SFX/Horror/Horror1.ogg")
				hud.item_data[worn]["state2"] = 2.0
		s.blur_timer = 1000.0
		if s.vomit_timer == 0.0:
			s.vomit_timer = 1.0
	elif s.sanity < -500.0:
		if randi_range(1, 7) == 1:
			hud.nv_picture = ""
		if randi_range(1, 50) == 1:
			hud.nv_picture = "GFX/895pics/pic%d.jpg" % randi_range(1, 6)
			var worn := _worn_item(hud, kind)
			if worn >= 0:
				if float(hud.item_data[worn].get("state2", 0.0)) == 0.0:
					Sfx.play_global(self, "SFX/Horror/Horror0.ogg")
				hud.item_data[worn]["state2"] = 1.0
	else:
		hud.nv_picture = ""
		var worn := _worn_item(hud, kind)
		if worn >= 0:
			hud.item_data[worn]["state2"] = 0.0

func _worn_item(hud: Node, kind: int) -> int:
	var wanted: String = ["nvgoggles", "supernv", "finenvgoggles"][kind - 1]
	for i in hud.items.size():
		if not hud.items[i].is_empty() and str(hud.item_data[i].get("tempname", "")) == wanted:
			return i
	return -1

func _has_power(hud: Node, kind: int) -> bool:
	var index := _worn_item(hud, kind)
	return index >= 0 and (float(hud.item_data[index].get("state", 0.0)) > 0.0 or kind == 3)
