extends Node
# SCP-008 infection (Main.bb UpdateInfect). GameState.infect runs from 0 to 100:
#  - above 0 a green overlay pulses and the view blurs; the heart beats faster with it; voices whisper at
#    10, 25, 40, 55, 70, 85 and 100 / 6 ... (Voices0-6) and the player is told about the fever (20), nausea (40, 60)
#    and faintness (80)
#  - at 91.5 the eyes close and the body will not move (IsZombie, UnableToMove); at 92.7 the player is carried into the
#    SCP-008 chamber's upper room, where a scientist stands (KillScientist1)
#  - from 93 the player is forced to walk toward the scientist (ForceMove 0.75, injuries 2.5); at 94.7 the scientist is
#    heard being eaten (KillScientist2) and at 96 the run ends with the death message
#  - where nobody can carry the player (the pocket dimension, gate A, the surface of gate B, 1499) the infection simply kills at 93+
# SCP-500 sets it back to 0 (item_use.gd).


const RS := 8.0 / 2048.0

var scientist: CharacterBody3D = null
var room_008: Node3D = null
var teleported := false
var killed := false
var messages: Array[String] = []     # what the player was told (tests)
var voices: Array[int] = []

var _scream_played := false
var _owns_flags := false       # this node set IsZombie / UnableToMove / ForceMove (other events, the 049 chamber, set them too)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_parent()
	if player == null or not facility.active:
		return
	update(delta * 70.0, player, facility)

func _can_teleport(facility: FacilityMap, player: Node3D) -> bool:
	var name: String = facility.room_name_at(player.global_position)
	if name in ["pocketdimension", "dimension1499", "gatea"]:
		return false
	if name == "room860" and facility.events.room860.state == 1.0:
		return false
	if name == "exit1" and player.global_position.y > 1040.0 * RS:
		return false
	return true

func update(fps: float, player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	if s.infect <= 0.0:
		s.infect_overlay = 0.0
		if _owns_flags:
			s.is_zombie = false
			s.unable_to_move = false
			s.force_move = 0.0
			_owns_flags = false
		teleported = false
		killed = false
		_scream_played = false
		return
	if player.dead and not killed:
		return
	var can_teleport := _can_teleport(facility, player)
	if s.infect < 93.0:
		var before := s.infect
		if not s.i427_using and s.i427_timer < 70.0 * 360.0:
			s.infect = minf(s.infect + fps * 0.002, 100.0)
		s.blur_timer = maxf(s.infect * 3.0 * (2.0 - player.crouch_state), s.blur_timer)
		var audio := get_tree().get_first_node_in_group("audio")
		if audio != null:
			audio.heartbeat(s.infect / 120.0, 100.0)
		s.infect_overlay = minf(pow(s.infect * 0.2, 2.0) / 1000.0, 0.5) * (sin(deg_to_rad(GameState.clock_ms() / 8.0)) + 2.0)
		for i in 7:
			if s.infect > i * 15 + 10 and before <= i * 15 + 10:
				voices.append(i)
				Sfx.play_global(self, "SFX/SCP/008/Voices%d.ogg" % i)
		if s.infect > 20.0 and before <= 20.0:
			_tell("You feel kinda feverish.")
		elif s.infect > 40.0 and before <= 40.0:
			_tell("You feel nauseated.")
		elif s.infect > 60.0 and before <= 60.0:
			_tell("The nausea's getting worse.")
		elif s.infect > 80.0 and before <= 80.0:
			_tell("You feel very faint.")
		elif s.infect >= 91.5:
			player.blink_timer = maxf(minf(-10.0 * (s.infect - 91.5), player.blink_timer), -10.0)
			s.is_zombie = true
			s.unable_to_move = true
			_owns_flags = true
			if s.infect >= 92.7 and before < 92.7 and can_teleport:
				_carry_to_chamber(player, facility)
	else:
		var before := s.infect
		s.infect = minf(s.infect + fps * 0.004, 100.0)
		if can_teleport and scientist != null and is_instance_valid(scientist):
			_scene(fps, player, before)
		elif not can_teleport:
			_kill_where_found(player, facility)
		elif not teleported:
			# nobody to carry the player (the chamber is missing): it ends here
			_kill_where_found(player, facility)

func _tell(text: String) -> void:
	messages.append(text)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.message(text, 6.0)

# The player is put in the SCP-008 chamber's upper room and a scientist (the "008 zombie scene") stands opposite.
func _carry_to_chamber(player: CharacterBody3D, facility: FacilityMap) -> void:
	var record := {}
	for candidate in facility.generator.rooms:
		if str(candidate.name) == "008":
			record = candidate
			break
	if record.is_empty():
		return
	room_008 = facility.rooms.get_room(record)
	if room_008 == null:
		return
	var spot: Vector3 = room_008.object_point(7)
	var scientist_spot: Vector3 = room_008.object_point(6)
	if spot == Vector3.INF or scientist_spot == Vector3.INF:
		return
	player.global_position = spot
	player.velocity = Vector3.ZERO
	facility.after_teleport()
	if scientist != null and is_instance_valid(scientist):
		facility.remove_human(scientist)
	scientist = facility.spawn_human(HumanNpc.Kind.CLASS_D, scientist_spot + Vector3(0.0, 0.2, 0.0), 3)
	scientist.state = 6
	Sfx.play_at(scientist, "SFX/SCP/008/KillScientist1.ogg", 14.0)
	teleported = true
	GameState.unable_to_move = false

# Infect 93 .. 100 in the chamber: the player walks to the scientist and is killed (the original's Kill() comes at 94.7 and its
# death screen is held until 96; here the death is called at 96).
func _scene(fps: float, player: CharacterBody3D, before: float) -> void:
	var s := GameState
	var infect := s.infect
	var to_scientist := scientist.global_position - player.global_position
	var yaw := atan2(-to_scientist.x, -to_scientist.z)
	if infect < 94.7:
		s.infect_overlay = 0.5 * (sin(deg_to_rad(GameState.clock_ms() / 8.0)) + 2.0)
		s.blur_timer = 900.0
		if infect > 94.5:
			player.blink_timer = maxf(minf(-50.0 * (infect - 94.5), player.blink_timer), -10.0)
		player.rotation.y = yaw
		scientist.rotation.y = atan2(to_scientist.x, to_scientist.z)
		_look_at(player, scientist.global_position + Vector3(0.0, 0.9, 0.0))
		s.force_move = 0.75
		_owns_flags = true
		s.injuries = 2.5
		s.bloodloss = 0.0
		s.unable_to_move = false
		scientist.animate(357.0, 381.0, 0.3, fps)
	elif infect < 98.5:
		s.infect_overlay = 0.5 * (sin(deg_to_rad(GameState.clock_ms() / 5.0)) + 2.0)
		s.blur_timer = 950.0
		s.force_move = 0.0
		s.unable_to_move = true
		_look_at(player, scientist.global_position + Vector3(0.0, 0.5, 0.0))
		if before < 94.7:
			Sfx.play_at(scientist, "SFX/SCP/008/KillScientist2.ogg", 14.0)
			var floor_y := (room_008.global_position.y if room_008 != null else 0.0) + 544.0 * RS + 0.01
			GrowingDecal.make(get_parent().get_parent(), Vector3(scientist.global_position.x, floor_y, scientist.global_position.z), "GFX/decal4.png", 0.8, 0.0, 1.0, false)
		if infect > 96.0:
			player.blink_timer = maxf(minf(-10.0 * (infect - 96.0), player.blink_timer), -10.0)
			if not killed:
				killed = true
				player.kill("Subject D-9341 found ingesting Dr. [REDACTED] at Sector [REDACTED]. Subject was immediately terminated by Nine-Tailed Fox and sent for autopsy. SCP-008 infection was confirmed, after which the body was incinerated.")
		if randi_range(1, 50) == 1:
			_blood_spray()
		# the scientist's body twitches (frames 13-19 and back)
		if scientist.state2 == 0.0:
			scientist.animate(13.0, 19.0, 0.3, fps, false)
			if scientist.frame >= 19.0:
				scientist.state2 = 1.0
		else:
			scientist.animate(19.0, 13.0, -0.3, fps, false)
			if scientist.frame <= 13.0:
				scientist.state2 = 0.0

func _blood_spray() -> void:
	var blood := (get_parent() as FacilityMap).particles.create(scientist.global_position, 5, randf_range(0.05, 0.1), 0.15, 200.0)
	if blood != null:
		blood.speed = 0.01
		blood.size_change = 0.01
		blood.alpha = 0.5
		blood.a_change = -0.01
		blood.dir = Particles.random_heading()

func _look_at(player: CharacterBody3D, point: Vector3) -> void:
	var to: Vector3 = point - player.camera.global_position
	var flat := Vector2(to.x, to.z).length()
	var pitch := atan2(to.y, flat)
	player.camera.rotation.x = pitch
	player.user_pitch = -rad_to_deg(pitch)

func _kill_where_found(player: CharacterBody3D, facility: FacilityMap) -> void:
	var s := GameState
	player.blink_timer = maxf(minf(-10.0 * (s.infect - 96.0), player.blink_timer), -10.0)
	if killed:
		return
	var room: String = facility.room_name_at(player.global_position)
	var text := ""
	if room == "dimension1499":
		text = "The whereabouts of SCP-1499 are still unknown, but a recon team has been dispatched to investigate reports of a violent attack to a church in the Russian town of [REDACTED]."
	elif room == "gatea" or room == "exit1":
		text = "Subject D-9341 found wandering around Gate %s. Subject was immediately terminated by Nine-Tailed Fox and sent for autopsy. SCP-008 infection was confirmed, after which the body was incinerated." % ("A" if room == "gatea" else "B")
	killed = true
	player.kill(text)
