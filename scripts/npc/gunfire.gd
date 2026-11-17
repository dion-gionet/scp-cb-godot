extends RefCounted
class_name Gunfire
# NPCs.bb Shoot(): a shot at the player. A muzzle flash, then (unless god mode) a hit with
# probability hit_prob: the vest decides what it does, the rest is leg, shoulder or head shots.
# Injuries are capped at 4. insta_kill ends the run at once. A shot that misses leaves a puff, sparks and a bullet hole in the wall
# behind the player when `impacts` is set (the original passes it for the Apaches that hunt the player).


static var last_message := ""     # what the player was told about the last hit
static var hits := 0
static var misses := 0

static func shoot(parent: Node3D, muzzle: Vector3, hit_prob: float, death_message: String = "", insta_kill: bool = false, impacts: bool = false) -> void:
	flash(parent, muzzle)
	light_up(parent)
	var player: CharacterBody3D = GameState.player
	if player == null or GameState.god_mode or player.dead:
		return
	if insta_kill:
		Sfx.play_global(parent, "SFX/General/BulletHit.ogg")
		hits += 1
		player.kill(death_message)
		return
	if randf() > hit_prob:
		misses += 1
		if impacts:
			_impact(parent, muzzle, player)
		return
	hits += 1
	# TurnEntity Camera after MouseLook: the next MouseLook sets the camera again, so the view only twitches for one frame
	player.jolt(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	var message := ""
	var s := GameState
	if s.wearing_vest > 0:
		if s.wearing_vest == 1:
			match randi_range(1, 8):
				1, 2, 3, 4, 5:
					s.blur_timer = 500.0
					player.stamina = 0.0
					message = "A bullet penetrated your vest, making you gasp."
					s.injuries += randf_range(0.1, 0.5)
				6:
					s.blur_timer = 500.0
					message = "A bullet hit your left leg."
					s.injuries += randf_range(0.8, 1.2)
				7:
					s.blur_timer = 500.0
					message = "A bullet hit your right leg."
					s.injuries += randf_range(0.8, 1.2)
				8:
					s.blur_timer = 500.0
					player.stamina = 0.0
					message = "A bullet struck your neck, making you gasp."
					s.injuries += randf_range(1.2, 1.6)
		else:
			if randi_range(1, 10) == 1:
				s.blur_timer = 500.0
				player.stamina -= 1.0
				message = "A bullet hit your chest. The vest absorbed some of the damage."
				s.injuries += randf_range(0.8, 1.1)
			else:
				message = "A bullet hit your chest. The vest absorbed most of the damage."
				s.injuries += randf_range(0.1, 0.5)
		if s.injuries >= 5.0 and randi_range(1, 3) == 1:
			player.kill(death_message)
	else:
		match randi_range(1, 6):
			1:
				player.kill(death_message)
			2:
				s.blur_timer = 500.0
				message = "A bullet hit your left leg."
				s.injuries += randf_range(0.8, 1.2)
			3:
				s.blur_timer = 500.0
				message = "A bullet hit your right leg."
				s.injuries += randf_range(0.8, 1.2)
			4:
				s.blur_timer = 500.0
				message = "A bullet hit your right shoulder."
				s.injuries += randf_range(0.8, 1.2)
			5:
				s.blur_timer = 500.0
				message = "A bullet hit your left shoulder."
				s.injuries += randf_range(0.8, 1.2)
			6:
				s.blur_timer = 500.0
				message = "A bullet hit your right shoulder."
				s.injuries += randf_range(2.5, 4.0)
	# the message is only replaced when the previous one has less than 64 * 4 frames left
	var hud := parent.get_tree().get_first_node_in_group("hud")
	if hud != null and not message.is_empty() and hud.message_time_left() < 64.0 * 4.0 / 70.0:
		hud.message(message, 6.0)
	last_message = message
	s.injuries = minf(s.injuries, 4.0)
	Sfx.play_global(parent, "SFX/General/BulletHit.ogg")

# A ray from the middle of the player away from the muzzle (the sideways part turned round, the height kept), 2.5 long.
static func _impact(parent: Node3D, muzzle: Vector3, player: CharacterBody3D) -> void:
	var facility := parent.get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or facility.particles == null:
		return
	var from := Vector3(player.global_position.x, (player.global_position.y + 0.3 + player.camera.global_position.y) * 0.5, player.global_position.z)
	var toward := (muzzle - from).normalized()
	var ray := Vector3(-toward.x, toward.y, -toward.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + ray * 2.5)
	query.collision_mask = 1
	var hit := parent.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	Sfx.play_global(parent, "SFX/General/BulletMiss.ogg", randf_range(0.8, 1.0))
	var particles := facility.particles
	var puff := particles.create(hit.position, 0, 0.03, 0.0, 80.0)
	if puff != null:
		puff.speed = 0.001
		puff.size_change = 0.003
		puff.alpha = 0.8
		puff.a_change = -0.01
		puff.dir = -ray
	for i in randi_range(2, 3) + 1:
		var fleck := particles.create(hit.position, 0, 0.006, 0.003, 80.0)
		if fleck != null:
			fleck.speed = 0.02
			fleck.alpha = 0.8
			fleck.a_change = -0.01
			fleck.dir = Particles.scatter(-ray, 10.0)
	var normal: Vector3 = hit.normal
	var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD
	var hole := GrowingDecal.make(facility.get_parent(), hit.position + normal * 0.001, "GFX/bullethole%d.jpg" % randi_range(1, 2), randf_range(0.028, 0.034), 0.0, 1.0, false, Basis.looking_at(-normal, up).get_euler(), true)
	(hole as GrowingDecal).lifetime = 70.0 * 20.0

# The muzzle flash: CreateParticle(x, y, z, 1, size, 0, 5), flash.jpg turned to a random roll. Shoot() and the MTF
# fade it by 0.15 a frame (size Rnd(0.08, 0.1)); the guard's idle shot (state 2) is 0.2 and does not fade.
static func flash(parent: Node3D, at: Vector3, size: float = -1.0, fade: bool = true) -> void:
	var facility := _facility(parent)
	if facility == null or facility.particles == null:
		return
	var p := facility.particles.create(at, 1, randf_range(0.08, 0.1) if size < 0.0 else size, 0.0, 5.0)
	if p != null and fade:
		p.a_change = -0.15

# LightVolume = TempLightVolume * 1.2: the fog opens up for a moment.
static func light_up(parent: Node3D) -> void:
	var facility := _facility(parent)
	if facility != null and facility.light_fog != null:
		facility.light_fog.flash()

static func _facility(parent: Node3D) -> FacilityMap:
	if parent == null or not parent.is_inside_tree():
		return null
	return parent.get_tree().get_first_node_in_group("facility") as FacilityMap
