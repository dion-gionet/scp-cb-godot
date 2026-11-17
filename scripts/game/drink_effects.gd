extends Node
# After-effects of SCP-294's drinks (Items.bb Update294): the view shakes for CameraShakeTimer seconds, and a drink that sets
# VomitTimer makes the player sick (blur and shakes, coughing, retching in the last 10 s), then vomit (the screen blurs for 40 s,
# the injuries and blood loss are set to 1.5 and 70 and given back after 15 s, a green stain grows on the floor).


var _regurgitate_until := 0.0
var _vomit_sound: AudioStreamPlayer = null
var _froze := false          # this node set unable_to_move (Playable = False)

func _physics_process(delta: float) -> void:
	var s := GameState
	var player: CharacterBody3D = s.player
	if player == null or player.dead:
		return
	var fps := delta * 70.0
	var now := s.clock_ms()
	_update_427(player, fps)
	_update_1025(player, fps)
	if s.camera_shake_timer > 0.0:
		s.camera_shake_timer -= fps / 70.0
		player.camera_shake = 2.0
	if s.vomit_timer > 0.0:
		s.vomit_timer -= fps / 70.0
		if fmod(now, 1600.0) < randf_range(200.0, 400.0):
			if s.blur_timer == 0.0:
				s.blur_timer = randf_range(10.0, 20.0) * 70.0
			player.camera_shake = randf_range(0.0, 2.0)
		if randi_range(1, 50) == 50 and fmod(now, 4000.0) < 200.0:
			Sfx.play_global(self, "SFX/Character/D9341/Cough%d.ogg" % randi_range(1, 3))
		if s.vomit_timer < 10.0 and randf_range(0.0, 500.0 * maxf(s.vomit_timer, 0.0)) < 2.0:
			if _regurgitate_until == 0.0 and not s.vomit:
				Sfx.play_global(self, "SFX/SCP/294/Retch%d.ogg" % randi_range(1, 2))
				_regurgitate_until = now + 50.0
		if _regurgitate_until > now and _regurgitate_until != 0.0:
			player._mouse_raw.y += 1.0
		else:
			_regurgitate_until = 0.0
	elif s.vomit_timer < 0.0:
		s.vomit_timer -= fps / 70.0
		if s.vomit_timer > -5.0:
			if fmod(now, 400.0) < 50.0:
				player.camera_shake = 4.0
			player._mouse_raw.x = 0.0
			player._mouse_smooth.x = 0.0
			if not s.unable_to_move:
				s.unable_to_move = true
				_froze = true
		elif _froze:
			s.unable_to_move = false
			_froze = false
		if not s.vomit:
			_begin_vomit(player)
		player._mouse_raw.y += maxf(1.0 + s.vomit_timer / 10.0, 0.0)
		if s.vomit_timer < -15.0:
			if _vomit_sound != null and is_instance_valid(_vomit_sound):
				_vomit_sound.stop()
			s.vomit_timer = 0.0
			Sfx.play_global(self, "SFX/Character/D9341/breath0.ogg")
			s.injuries = s.vomit_prev_injuries
			s.bloodloss = s.vomit_prev_bloodloss
			s.vomit = false
	elif _froze:
		s.unable_to_move = false
		_froze = false

func _begin_vomit(player: CharacterBody3D) -> void:
	var s := GameState
	s.blur_timer = 40.0 * 70.0
	_vomit_sound = Sfx.play_global(self, "SFX/SCP/294/Vomit.ogg")
	s.vomit_prev_injuries = s.injuries
	s.vomit_prev_bloodloss = s.bloodloss
	s.injuries = 1.5
	s.bloodloss = 70.0
	s.eye_irritation = 9.0 * 70.0
	s.vomit = true
	var space := player.get_world_3d().direct_space_state
	var from: Vector3 = player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -2.0, 0.0))
	query.collision_mask = 1
	query.exclude = [player]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var spot: Vector3 = hit.position + Vector3(0.0, 0.005, 0.0)
	var decal := GrowingDecal.make(player.get_parent(), spot, "GFX/decal6.png", 0.001, 0.001, 1.0, false)
	decal.max_size = 0.6
	decal.rotation.y = PI
	(decal.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.0, randf_range(200.0, 255.0) / 255.0, 0.0, 1.0))

# ---- SCP-427 (Items.bb Use427): the locket heals while it is open; after 360 s open the change begins and 420 s ends it ----

var _sound_427: Array = [null, null]

func _loop_427(index: int, relative: String) -> void:
	var player_sound: AudioStreamPlayer = _sound_427[index]
	if player_sound == null or not is_instance_valid(player_sound) or not player_sound.playing:
		_sound_427[index] = Sfx.play_global(self, relative)

func _stop_427() -> void:
	for i in 2:
		var player_sound: AudioStreamPlayer = _sound_427[i]
		if player_sound != null and is_instance_valid(player_sound):
			player_sound.stop()
			player_sound.queue_free()
		_sound_427[i] = null

func _update_427(player: CharacterBody3D, fps: float) -> void:
	var s := GameState
	var before := s.i427_timer
	if s.i427_timer < 70.0 * 360.0:
		if not s.i427_using:
			_stop_427()
			return
		s.i427_timer += fps
		if s.injuries > 0.0:
			s.injuries = maxf(s.injuries - 0.0005 * fps, 0.0)
		if s.bloodloss > 0.0 and s.injuries <= 1.0:
			s.bloodloss = maxf(s.bloodloss - 0.001 * fps, 0.0)
		if s.infect > 0.0:
			s.infect = maxf(s.infect - 0.001 * fps, 0.0)
		for i in 6:
			if s.scp1025[i] > 0.0:
				s.scp1025[i] = maxf(float(s.scp1025[i]) - 0.001 * fps, 0.0)
		_loop_427(0, "SFX/SCP/427/Effect.ogg")
		if s.i427_timer >= 70.0 * 180.0:
			_loop_427(1, "SFX/SCP/427/Transform.ogg")
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null:
			if before < 70.0 * 60.0 and s.i427_timer >= 70.0 * 60.0:
				hud.message("You feel refreshed and energetic.", 5.0)
			elif before < 70.0 * 180.0 and s.i427_timer >= 70.0 * 180.0:
				hud.message("You feel gentle muscle spasms all over your body.", 5.0)
		return
	var hud2 := get_tree().get_first_node_in_group("hud")
	if hud2 != null:
		if before - fps < 70.0 * 360.0 and before >= 70.0 * 360.0:
			hud2.message("Your muscles are swelling. You feel more powerful than ever.", 5.0)
		elif before - fps < 70.0 * 390.0 and before >= 70.0 * 390.0:
			hud2.message("You can't feel your legs. But you don't need legs anymore.", 5.0)
	s.i427_timer += fps
	_loop_427(0, "SFX/SCP/427/Effect.ogg")
	_loop_427(1, "SFX/SCP/427/Transform.ogg")
	if randf_range(0.0, 200.0) < 2.0:
		_427_drip(player)
		s.blur_timer = 800.0
	if s.i427_timer >= 70.0 * 420.0:
		s.death_msg = "\"Requesting support from MTF Nu-7. We need more firepower to take this thing down.\""
		player.kill(s.death_msg)
	elif s.i427_timer >= 70.0 * 390.0:
		player.crouching = true

func _427_drip(player: CharacterBody3D) -> void:
	GrowingDecal.drip(player, "GFX/decal427.png", randf_range(0.03, 0.08) * 2.0)

# ---- SCP-1025 (Main.bb UpdateGUI, "SCP1025state"): the illness the book described; it only wears off while SCP-427 is open (or SCP-500 / death clears it).

func _update_1025(player: CharacterBody3D, fps: float) -> void:
	var s := GameState
	var hud: Node = get_parent()
	if hud.selected_tempname() == "scp1025" and not s.wearing_714:
		var roll := int(hud.item_data[hud.selected].get("state", 0.0))
		s.scp1025[roll] = maxf(1.0, float(s.scp1025[roll]))
	var audio := get_tree().get_first_node_in_group("audio")
	for i in 6:
		var value: float = s.scp1025[i]
		if value <= 0.0:
			continue
		match i:
			0:
				if randi_range(1, 1000) == 1:
					_cough()
				player.stamina -= fps * 0.3
			1:
				if randi_range(1, 9000) == 1 and hud.message_time_left() <= 0.0:
					hud.message("Your skin is feeling itchy.", 4.0)
			2:
				if randi_range(1, 800) == 1:
					_cough()
				player.stamina -= fps * 0.1
			3:
				if not (s.i427_using or s.i427_timer >= 70.0 * 360.0):
					s.scp1025[i] = value + fps * 0.0005
				var after: float = s.scp1025[i]
				if after > 20.0:
					if value <= 20.0:
						hud.message("The pain in your stomach is becoming unbearable.", 5.0)
					player.stamina -= fps * 0.3
				elif after > 10.0 and value <= 10.0:
					hud.message("Your stomach is aching.", 5.0)
			4:
				if player.stamina < 35.0:
					if randi_range(1, int(140.0 + player.stamina * 8.0)) == 1:
						_cough()
					player.curr_speed -= player.curr_speed * minf(fps / (10.0 + player.stamina * 15.0), 1.0)
			5:
				if not (s.i427_using or s.i427_timer >= 70.0 * 360.0):
					s.scp1025[i] = value + fps * 0.35
				var attack: float = s.scp1025[i]
				if attack > 110.0:
					s.blur_timer = maxf(s.blur_timer, 500.0)
					if attack > 140.0:
						player.kill("\"He died of a cardiac arrest after reading SCP-1025, that's for sure. Is there such a thing as psychosomatic cardiac arrest, or does SCP-1025 have some anomalous properties we are not yet aware of?\"")
						return
				elif audio != null:
					audio.heartbeat(1.0, 70.0 + attack)

var _cough_player: AudioStreamPlayer = null

func _cough() -> void:
	if _cough_player != null and is_instance_valid(_cough_player) and _cough_player.playing:
		return
	_cough_player = Sfx.play_global(self, "SFX/Character/D9341/Cough%d.ogg" % randi_range(1, 3))
