extends RefCounted
class_name LightSprites
# The two sprites every rmesh light gets (MapSystem.bb AddLight, shown by UpdateRoomLights):
#  - the fixture: a small additive point (light1.jpg, ScaleSprite 0.13), there while the room lights have power
#  - the glow: a coloured additive halo (lightsprite.jpg, 0.3-0.5 scale, flickering), only for a light within 8.5 of
#    the camera that the camera can see, fading out with distance (alpha = 1 - (distance + 0.5) / 7.5), and drawn over
#    everything since its visibility was already tested.
# Rooms with volumetric lighting (rooms.ini usevolumelighting: 049's, 513's and 966's rooms and the maintenance tunnels)
# also hang a light cone (lightcone.b3d, additive, alpha 0.15 in the light's colour, scaled with the glow's flicker) from
# every light, and the lights of flicker class 5 and up now and then throw a spark (the original rolls 1 in 400 each time a
# light's turn comes round, every 8 frames: a burst of electric sparks, Light1-3 and a 10-frame flash lying flat above the light).
# Each light's flicker class (Rand(1, 10)) sets how far the glow's size jumps: under 5 by +-0.02, 5-9 by +-0.05,
# 10 by +-0.1 around 0.4; in the 173 room they all hold to +-0.02.
# Size: a Blitz sprite is a 2 x 2 quad, so ScaleSprite(s, v, v) makes it 2 v across (GLOW_SPAN).


const SHOW_DISTANCE := 8.5
const GLOW_SPAN := 2.0
const SIGHT_LAYER := 32
const RETEST_FRAMES := 8.0

const VOLUME_ROOMS := ["room049", "room513", "room966", "tunnel", "tunnel2", "room2ctunnel", "room3tunnel", "room4tunnels"]
static var _cone_mesh: ArrayMesh
static var _cone_texture: Texture2D
static var _spark_texture: Texture2D

static var _fixture_texture: Texture2D
static var _glow_texture: Texture2D

static func attach(room: Node3D, light: Light3D, color: Color, volume: bool = false) -> void:
	if _fixture_texture == null:
		_fixture_texture = MeshLoader._load_texture(ContentPaths.existing_image("GFX/light1.jpg"))
		_glow_texture = MeshLoader._load_texture(ContentPaths.existing_image("GFX/lightsprite.jpg"))
	var fixture := MeshInstance3D.new()
	var fixture_quad := QuadMesh.new()
	fixture_quad.size = Vector2.ONE * 0.13 * GLOW_SPAN
	fixture.mesh = fixture_quad
	fixture.material_override = GammaBlend.make(_fixture_texture, Color.WHITE, true, true)
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixture.position = light.position
	room.add_child(fixture)
	var glow := MeshInstance3D.new()
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2.ONE * 0.4 * GLOW_SPAN
	glow.mesh = glow_quad
	var glow_material := GammaBlend.make(_glow_texture, color, true, true, false, true)
	glow_material.render_priority = 10
	glow_material.set_shader_parameter("billboard_roll", randf() * TAU)      # RotateEntity LightSprites2, 0, 0, Rand(360)
	glow.material_override = glow_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = light.position
	glow.visible = false
	room.add_child(glow)
	if volume:
		if _cone_mesh == null:
			_cone_mesh = B3DModel.static_mesh(ContentPaths.existing_file("GFX/lightcone.b3d"), true)
			_cone_texture = MeshLoader._load_texture(ContentPaths.existing_image("GFX/lightcone.png"))
			_spark_texture = MeshLoader._load_texture(ContentPaths.existing_image("GFX/particle.png"))
		var cone := MeshInstance3D.new()
		cone.mesh = _cone_mesh
		cone.material_override = GammaBlend.make(_cone_texture, Color(color.r, color.g, color.b, 0.15), true)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = light.position
		cone.scale = Vector3.ONE * 0.005
		room.add_child(cone)
		light.set_meta("cone", cone)
		var spark := MeshInstance3D.new()
		var spark_quad := QuadMesh.new()
		spark_quad.size = Vector2.ONE * 2.0
		spark.mesh = spark_quad
		spark.material_override = GammaBlend.make(_spark_texture, Color.WHITE, true)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.position = light.position + Vector3(0.0, 0.05, 0.0)
		spark.rotation.x = PI * 0.5      # RotateEntity -90 (SpriteViewMode 2): lies flat, facing down
		spark.visible = false
		room.add_child(spark)
		light.set_meta("spark", spark)
		light.set_meta("spark_frames", 0.0)
	light.set_meta("fixture", fixture)
	light.set_meta("glow", glow)
	light.set_meta("glow_color", color)
	light.set_meta("flicker", randi_range(1, 10))

# One frame for one light. `near` is the 8.5 radius test already made for the Blitz light itself.
static func update(light: Light3D, camera: Camera3D, powered: bool, in_173_room: bool, space: PhysicsDirectSpaceState3D) -> void:
	var fixture: MeshInstance3D = light.get_meta("fixture") if light.has_meta("fixture") else null
	var glow: MeshInstance3D = light.get_meta("glow") if light.has_meta("glow") else null
	if fixture == null or glow == null:
		return
	fixture.visible = powered
	var cone: MeshInstance3D = light.get_meta("cone") if light.has_meta("cone") else null
	if cone != null:
		_update_cone(light, cone, powered and GameState.room_lights, in_173_room)
	if not powered or camera == null or not GameState.room_lights:   # EnableRoomLights (the options' "Enable room lights")
		glow.visible = false
		return
	# MapSystem.bb 7917, 8042-8045: UpdateRoomLightsTimer is global and grows by FPSfactor for every light handled, so each
	# light is tested for sight and given its alpha only once in about 8 passes; on the others its size is only re-rolled.
	# The original's uneven frame time keeps the lights' turns moving; at the port's fixed step a global timer would lock onto
	# the same lights, so each light counts its own 8 frames, from a random start.
	var wait: float = light.get_meta("retest_wait", randf() * RETEST_FRAMES) + 70.0 / Engine.physics_ticks_per_second
	var retest := wait >= RETEST_FRAMES
	light.set_meta("retest_wait", wait - RETEST_FRAMES if retest else wait)
	if not retest:
		if glow.visible:
			glow.mesh.size = Vector2.ONE * _glow_size(light, in_173_room) * GLOW_SPAN
		return
	var distance := camera.global_position.distance_to(light.global_position)
	if distance >= SHOW_DISTANCE:
		glow.visible = false
		return
	var alpha := 1.0 - clampf((distance + 0.5) / 7.5, 0.0, 1.0)
	if alpha <= 0.0:
		glow.visible = false
		return
	if not _visible_from(camera.global_position, light.global_position, space):
		glow.visible = false
		return
	glow.mesh.size = Vector2.ONE * _glow_size(light, in_173_room) * GLOW_SPAN
	var color: Color = light.get_meta("glow_color")
	(glow.material_override as ShaderMaterial).set_shader_parameter("color", Color(color.r, color.g, color.b, alpha))
	glow.visible = true

static func _glow_size(light: Light3D, in_173_room: bool) -> float:
	var flicker: int = light.get_meta("flicker", 1)
	if in_173_room or flicker < 5:
		return randf_range(0.38, 0.42)
	if flicker < 10:
		return randf_range(0.35, 0.45)
	return randf_range(0.3, 0.5)

# EntityVisible to the light's pivot is a thin line, not a sweep of the pivot's EntityRadius: lamps a 0.05 sphere cannot reach
# show the flare in the original. LoadRMesh makes the room's pickable mesh double-sided (FlipMesh copy, MapSystem.bb:518-521)
# and the port's drawn faces are one-sided, so the room is also tested from the light's end. Props get no flipped copy.
static func _visible_from(from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	return MeshLoader.pick_ray(space, from, to, RID(), 1 | SIGHT_LAYER).is_empty() and MeshLoader.pick_ray(space, to, from, RID()).is_empty()

# The cone follows the glow's size jumps (ScaleEntity 0.005 + Max((size - 0.4) * 0.025, 0)); a spark flashes for 10 frames.
static func _update_cone(light: Light3D, cone: MeshInstance3D, powered: bool, in_173_room: bool) -> void:
	cone.visible = powered
	var spark: MeshInstance3D = light.get_meta("spark")
	if not powered:
		spark.visible = false
		return
	var flicker: int = light.get_meta("flicker", 1)
	var size := _glow_size(light, in_173_room)
	cone.scale = Vector3.ONE * (0.005 + maxf((size - 0.4) * 0.025, 0.0))
	var step := 70.0 / Engine.physics_ticks_per_second
	var frames: float = light.get_meta("spark_frames", 0.0)
	if frames > 0.0 and frames < 10.0:
		spark.visible = true
		light.set_meta("spark_frames", frames + step)
		return
	spark.visible = false
	light.set_meta("spark_frames", 0.0)
	if flicker > 4 and randf() < step / (8.0 * 400.0):
		_throw_spark(light, spark, step)

# SetEmitter(ParticleEffect[0]) on the light, PlaySound2(IntroSFX(Rand(10, 12))) and the flash
static func _throw_spark(light: Light3D, spark: MeshInstance3D, step: float) -> void:
	var facility := light.get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null and facility.particles != null:
		facility.particles.spark_burst(light.global_position)
	Sfx.play_at(spark, "SFX/Room/Intro/Light%d.ogg" % randi_range(1, 3), 10.0)
	spark.visible = true
	light.set_meta("spark_frames", step)
