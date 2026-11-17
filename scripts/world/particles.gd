extends Node3D
class_name Particles
# Particles.bb: CreateParticle / UpdateParticles and the emitters (CreateEmitter / UpdateEmitters) with the gas they give off.
#  - a particle moves along its heading by `speed` a frame, its height by `yspeed` (which `gravity` * 0.004 pulls on; a negative
#    gravity lifts it), fades by `a_change`, grows by `size_change` and ends when its life (frames) or its size or alpha run out
#  - sprites are upright billboards (SpriteViewMode 3) with a random roll (RotateEntity 0,0,Rnd(360))
#  - a sprite scaled to `size` is 2 * size across
#  - pictures 1, 2, 3, 4 and 7 are additive, the others take their own alpha; none of them is fogged (EntityFX 8)
#  - picture 9 is hg.pt drawn with EntityBlend 2 (multiply), as the pocket dimension's pillar room does
#  - a particle can follow a node (the original parents its pivot to one)
#  - picture 11 is the DevilParticleSystem's ParticleEffect[1] smoke (smoke2.png): it faces the camera, takes the AmbientLight
#    (EntityFX 34: lit, but its quads have no normals, so only the ambient reaches them) and the fog
#  - an emitter makes one particle a frame while the player is in its room or the room is within 8 of them, and hisses
#  - InSmoke: within 0.8 of an emitter (and 5 in height), without a gas mask or hazmat suit, the eyes burn: the view blurs after
#    6 s of it and 24 s kill (decontamination gas); the player coughs now and then
# Each picture is drawn by one MultiMesh.


const PICTURES := ["GFX/smoke.png", "GFX/flash.jpg", "GFX/dust.jpg", "GFX/npcs/hg.pt", "GFX/map/sun.jpg", "GFX/bloodsprite.png", "GFX/smoke2.png", "GFX/spark.jpg", "GFX/particle.png", "GFX/npcs/hg.pt", "GFX/Spark.png", "GFX/smoke2.png"]
const ADDITIVE := [1, 2, 3, 4, 7, 10]
const SPARK_PICTURE := 10
const DEVIL_SMOKE_PICTURE := 11
const HG_MULTIPLIED := 9
const AMOUNT := 2               # options.ini "particle amount"
const CAPACITY := 1500          # per picture
const SMOKE_DEATH := "Subject D-9341 found dead in [DATA REDACTED]. Cause of death: Suffocation due to decontamination gas."

class Particle:
	extends RefCounted
	var pos := Vector3.ZERO
	var dir := Vector3.FORWARD
	var speed := 0.0
	var yspeed := 0.0
	var gravity := 0.0
	var alpha := 1.0
	var size := 0.03
	var size_change := 0.0
	var size_mult := 1.0          # the DevilParticleSystem's size velocity: size = (size + size_change) * size_mult a frame
	var a_change := 0.0
	var lifetime := 200.0
	var image := 0
	var roll := 0.0
	var life := 0.0
	var tint_from := Color.WHITE
	var tint_to := Color.WHITE
	var floor_y := -INF
	var floor_bounce := 0.0
	var align_to_fall := false
	var follow: Node3D = null
	var follow_offset := Vector3.ZERO
	var follow_local := false

var _items: Array[Particle] = []
var _meshes: Array = []                       # per picture: {instance, multi}, made when first used
var emitters: Array[Dictionary] = []
var in_smoke := false
var _cough: AudioStreamPlayer = null

func count() -> int:
	return _items.size()

# CreateParticle(x, y, z, image, size, gravity, lifetime)
func create(at: Vector3, image: int, size: float, gravity: float = 1.0, lifetime: float = 200.0) -> Particle:
	if _items.size() >= CAPACITY * 4:
		return null
	var p := Particle.new()
	p.pos = at
	p.image = clampi(image, 0, PICTURES.size() - 1)
	p.size = size
	p.gravity = gravity * 0.004
	p.lifetime = lifetime
	p.life = lifetime
	p.roll = randf() * TAU
	_items.append(p)
	return p

# The way an entity with Blitz pitch and yaw (degrees) faces: a positive pitch looks down.
static func heading(pitch_deg: float, yaw_deg: float) -> Vector3:
	return Basis.from_euler(Vector3(-deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)) * Vector3(0.0, 0.0, -1.0)

# RotateEntity p\pvt, Rnd(360), Rnd(360), 0
static func random_heading() -> Vector3:
	return heading(randf() * 360.0, randf() * 360.0)

# A direction a little off `heading` (TurnEntity by up to `spread` degrees in pitch and yaw)
static func scatter(heading: Vector3, spread: float) -> Vector3:
	var side := heading.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = heading.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(heading).normalized()
	return heading.rotated(side, deg_to_rad(randf_range(-spread, spread))).rotated(up, deg_to_rad(randf_range(-spread, spread))).normalized()

# CreateEmitter(type 0) in a room: `heading` is the direction the jets go, in world space. Settings the room changes after the
# call go in `settings` (rand_angle, speed, size_change, a_change, gravity).
func add_emitter(at: Vector3, heading: Vector3, room: Node3D, room_key: String, settings: Dictionary = {}) -> Dictionary:
	var emitter := {
		"pos": at, "dir": heading.normalized(), "room": room, "key": room_key,
		"size": 0.03, "gravity": -0.2, "lifetime": 200.0, "size_change": 0.005, "speed": 0.004, "rand_angle": 20.0,
		"a_change": -0.008, "min_image": 0, "max_image": 0, "carry": 0.0, "voice": null, "follow": null,
	}
	for key in settings:
		emitter[key] = settings[key]
	emitters.append(emitter)
	return emitter

# The nuke going off (UpdateEvents.bb ExplosionTimer = 140): smoke pours up from below the player.
func nuke_smoke(collider_at: Vector3) -> void:
	for i in 10 + 10 * (AMOUNT + 1) + 1:
		var at := collider_at + Vector3(randf_range(-0.5, 0.5), -randf_range(0.2, 1.5), randf_range(-0.5, 0.5))
		var p := create(at, 0, randf_range(0.2, 0.6), 0.0, 350.0)
		if p != null:
			p.dir = Vector3.UP
			p.speed = randf_range(0.05, 0.07)

# ParticleEffect[0] (Main.bb, the DevilParticleSystem template "electric spark"): for 7 frames an emitter gives 6 blue sparks a frame
# within 0.1 of the point, drifting up to 0.0375 a frame on each axis, pulled down by 0.001 a frame and bouncing on the floor at
# y 0 (half the speed); they live 20-30 frames, fade out and are turned along their fall.
const SPARK_FRAMES := 7
const SPARKS_PER_FRAME := 6
var _bursts: Array[Dictionary] = []

func spark_burst(at: Vector3) -> void:
	_bursts.append({"pos": at, "left": SPARK_FRAMES, "carry": 0.0})

func _update_bursts(fps: float) -> void:
	for i in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[i]
		burst.carry += fps
		while burst.carry >= 1.0 and burst.left > 0:
			burst.carry -= 1.0
			burst.left -= 1
			for n in SPARKS_PER_FRAME:
				_spark(burst.pos)
		if burst.left <= 0:
			_bursts.remove_at(i)

func _spark(at: Vector3) -> void:
	var life := float(randi_range(20, 30))
	var p := create(at + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), SPARK_PICTURE, randf_range(0.03125, 0.0625) * randf_range(0.7, 1.0), 0.0, life)
	if p == null:
		return
	var heading := Vector3(randf_range(-0.0375, 0.0375), 0.0, randf_range(-0.0375, 0.0375))
	p.speed = heading.length()
	p.dir = heading.normalized() if p.speed > 0.0 else Vector3.FORWARD
	p.yspeed = randf_range(-0.0375, 0.0375)
	p.gravity = 0.001
	p.a_change = -1.0 / life
	p.tint_from = Color(0.0, 0.0, 1.0)
	p.tint_to = Color(101.0 / 255.0, 101.0 / 255.0, 1.0)
	p.floor_y = 0.0
	p.floor_bounce = 0.5
	p.align_to_fall = true

# CreateDevilEmitter(.., particleID 1, maxTime 4) and UpdateDevilEmitters (Particles.bb 226): while the player is in the room or
# it is within 8, SetEmitter starts a ParticleEffect[1] emitter, then the timer runs to 4 and back to 0, so one every 5 frames.
# That emitter lives 3 frames past its first (age 0 to 3 make a particle each, age 4 ends it): 4 puffs of smoke2.png that rise
# 0.02-0.025 a frame, are 0.4 x 0.5-1.5 (half size) growing by (s + 0.01) * 1.01 a frame, and fade out over 30-45 frames.
const DEVIL_SMOKE_PUFFS := 4
var _devil_emitters: Array[Dictionary] = []
var _smoke_bursts: Array[Dictionary] = []

func add_devil_smoke(at: Vector3, room_key: String) -> void:
	_devil_emitters.append({"pos": at, "key": room_key, "timer": 0.0})

func _update_devil_emitters(fps: float) -> void:
	var player: CharacterBody3D = GameState.player
	var facility := get_parent() as FacilityMap
	if player != null and fps > 0.0 and not _devil_emitters.is_empty():
		var player_key := str(facility.record_at(player.global_position).get("key", ""))
		for e in _devil_emitters:
			var rec: Dictionary = facility.rooms.by_grid.get(e.key, {})
			if not (e.key == player_key or (not rec.is_empty() and RoomRegistry.room_dist(rec.position, player.global_position) < 8.0)):
				continue
			if e.timer == 0.0:
				_smoke_bursts.append({"pos": e.pos, "left": DEVIL_SMOKE_PUFFS, "carry": 1.0})
				e.timer = fps
			elif e.timer < 4.0:
				e.timer = minf(e.timer + fps, 4.0)
			else:
				e.timer = 0.0
	for i in range(_smoke_bursts.size() - 1, -1, -1):
		var burst := _smoke_bursts[i]
		while burst.carry >= 1.0 and burst.left > 0:
			burst.carry -= 1.0
			burst.left -= 1
			_devil_puff(burst.pos)
		burst.carry += fps
		if burst.left <= 0:
			_smoke_bursts.remove_at(i)

func _devil_puff(at: Vector3) -> void:
	var life := float(randi_range(30, 45))
	var p := create(at, DEVIL_SMOKE_PICTURE, 0.4 * randf_range(0.5, 1.5), 0.0, life + 1.0)
	if p == null:
		return
	p.roll = 0.0
	p.yspeed = randf_range(0.02, 0.025)
	p.a_change = -1.0 / life
	p.size_change = 0.01
	p.size_mult = 1.01

func _physics_process(delta: float) -> void:
	var fps := delta * 70.0
	_update_devil_emitters(fps)
	_update_bursts(fps)
	_update_emitters(fps)
	_update_particles(fps)
	_draw()

func _update_emitters(fps: float) -> void:
	in_smoke = false
	var player: CharacterBody3D = GameState.player
	var facility := get_parent() as FacilityMap
	if player == null:
		return
	var ppos := player.global_position
	var player_key := str(facility.record_at(ppos).get("key", ""))
	var gas_protected := GameState.wearing_gas_mask != 0 or GameState.wearing_hazmat != 0
	for i in range(emitters.size() - 1, -1, -1):
		var e: Dictionary = emitters[i]
		var room: Variant = e.room
		if room == null or not is_instance_valid(room):
			if e.voice != null and is_instance_valid(e.voice):
				(e.voice as Node).queue_free()
			emitters.remove_at(i)
			continue
		if e.follow != null and is_instance_valid(e.follow):
			e.pos = (e.follow as Node3D).global_position
		var rec: Dictionary = facility.rooms.by_grid.get(e.key, {})
		var near: bool = e.key == player_key or (not rec.is_empty() and RoomRegistry.room_dist(rec.position, ppos) < 8.0)
		if not near or fps <= 0.0:
			if e.voice != null and is_instance_valid(e.voice):
				(e.voice as Node).queue_free()
				e.voice = null
			continue
		e.carry += fps
		while e.carry >= 1.0:
			e.carry -= 1.0
			var p := create(e.pos, randi_range(int(e.min_image), int(e.max_image)), float(e.size), float(e.gravity), float(e.lifetime))
			if p != null:
				p.speed = float(e.speed)
				p.dir = scatter(e.dir, float(e.rand_angle))
				p.size_change = float(e.size_change)
				p.a_change = float(e.a_change)
		if e.voice == null or not is_instance_valid(e.voice):
			e.voice = _hiss(e.pos)
		if not in_smoke and not gas_protected:
			var flat := Vector2(player.camera.global_position.x - e.pos.x, player.camera.global_position.z - e.pos.z).length()
			if flat < 0.8 and absf(player.camera.global_position.y - e.pos.y) < 5.0:
				in_smoke = true
	if in_smoke:
		_breathe_smoke(player, fps)

func _hiss(at: Vector3) -> AudioStreamPlayer3D:
	var stream := Sfx.stream("SFX/General/Hiss.ogg")
	if stream == null:
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.max_distance = 10.0
	add_child(voice)
	voice.global_position = at
	voice.finished.connect(func() -> void: if is_instance_valid(voice): voice.play())
	voice.play()
	return voice

# InSmoke in UpdateEmitters
func _breathe_smoke(player: CharacterBody3D, fps: float) -> void:
	var s := GameState
	if s.eye_irritation > 70.0 * 6.0:
		s.blur_volume = maxf(s.blur_volume, (s.eye_irritation - 70.0 * 6.0) / (70.0 * 24.0))
	if s.eye_irritation > 70.0 * 24.0:
		player.kill(SMOKE_DEATH)
	if not player.dead and randi_range(1, 150) == 1:
		if _cough == null or not is_instance_valid(_cough) or not _cough.playing:
			_cough = Sfx.play_global(self, "SFX/Character/D9341/Cough%d.ogg" % randi_range(1, 3))
	s.eye_irritation += fps * 4.0

func _update_particles(fps: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		var p := _items[i]
		p.pos += p.dir * (p.speed * fps)
		if p.gravity != 0.0:
			p.yspeed -= p.gravity * fps
		p.pos.y += p.yspeed * fps
		if p.pos.y < p.floor_y:
			p.yspeed *= -p.floor_bounce
		if p.align_to_fall:
			p.roll = atan2(p.yspeed, p.dir.x * p.speed)
		if p.follow != null:
			if is_instance_valid(p.follow):
				p.pos = p.follow.to_global(p.follow_offset) if p.follow_local else p.follow.global_position + p.follow_offset
			else:
				p.follow = null
		if p.a_change != 0.0:
			p.alpha = clampf(p.alpha + p.a_change * fps, 0.0, 1.0)
		if p.size_mult != 1.0:
			p.size = (p.size + p.size_change * fps) * pow(p.size_mult, fps)
		elif p.size_change != 0.0:
			p.size += p.size_change * fps
		p.lifetime -= fps
		if p.lifetime <= 0.0 or p.size < 0.00001 or p.alpha <= 0.0:
			_items[i] = _items[_items.size() - 1]
			_items.pop_back()

func _back_to_front() -> Array:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _items
	var eye := camera.global_position
	var mixed: Array = []
	var order: Array = []
	for p in _items:
		if p.image in ADDITIVE or p.image == HG_MULTIPLIED:
			order.append(p)
		else:
			mixed.append([p.pos.distance_squared_to(eye), p])
	if mixed.size() > 1:
		mixed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry in mixed:
		order.append(entry[1])
	return order

func _picture_mesh(image: int) -> Dictionary:
	while _meshes.size() < PICTURES.size():
		_meshes.append(null)
	if _meshes[image] != null:
		return _meshes[image]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.use_colors = image == SPARK_PICTURE      # only sparks are tinted
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	multi.mesh = quad
	multi.instance_count = CAPACITY
	multi.visible_instance_count = 0
	var material := ShaderMaterial.new()
	var shader := "particle_add" if image in ADDITIVE else ("particle_mul" if image == HG_MULTIPLIED else ("particle_devil" if image == DEVIL_SMOKE_PICTURE else "particle_mix"))
	material.shader = load("res://shaders/%s.gdshader" % shader)
	# One MultiMesh at the world's origin holds every particle, so by depth it sorts as the farthest thing in the map and
	# every decal was drawn over the smoke in front of it. Decals lie on surfaces, behind anything in the air.
	material.render_priority = 1
	var path := ContentPaths.existing_image(PICTURES[image])
	material.set_shader_parameter("tex", MeshLoader._load_texture(path))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))
	instance.top_level = true
	add_child(instance)
	instance.global_transform = Transform3D.IDENTITY
	_meshes[image] = {"instance": instance, "multi": multi}
	return _meshes[image]

# Blitz3D draws alpha entities back to front. Only the alpha-mixed pictures depend on it (additive and multiplied ones give
# the same result in any order), so those are drawn farthest first.
func _draw() -> void:
	var used: Dictionary = {}
	for p in _back_to_front():
		var entry := _picture_mesh(p.image)
		var multi: MultiMesh = entry.multi
		var index: int = used.get(p.image, 0)
		if index >= CAPACITY:
			continue
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * p.size), p.pos))
		multi.set_instance_custom_data(index, Color(p.alpha, p.roll, 0.0, 0.0))
		if p.image == SPARK_PICTURE:
			multi.set_instance_color(index, p.tint_from.lerp(p.tint_to, 1.0 - p.lifetime / p.life) if p.life > 0.0 else Color.WHITE)
		used[p.image] = index + 1
	for image in range(_meshes.size()):
		if _meshes[image] != null:
			(_meshes[image].multi as MultiMesh).visible_instance_count = used.get(image, 0)
