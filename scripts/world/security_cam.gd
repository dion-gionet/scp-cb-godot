extends Node3D
class_name SecurityCam
# A security camera and, if it has one, the monitor that shows what it sees
# (MapSystem.bb CreateSecurityCam / UpdateSecurityCams / UpdateMonitorSaving).
#  - the camera swings back and forth by +-`turn` around `angle` (0.2 degrees per frame, it goes
#    1.3 times as far as it shows before turning back) while the player is in or near the room
#  - the monitor shows the camera's view, redrawn every `render_interval` frames, but only
#    while the player looks at it with open eyes
#  - on Euclid a click on a monitor within 1 unit selects it, and that is where the game may be
#    saved (AllowSaving)
# Positions come from data/room_fill.json in room-local Blitz metres (z is flipped here).

const RS := MeshLoader.ROOM_SCALE
const DEFAULT_LAYERS := 0xFFFFF                  # what every camera, the player's included, draws
const CHAMBER_LAYER := 1 << 20                   # the hidden chamber while a feed draws it: no camera but a feed's sees this layer
const FEED_LAYER := 1 << 21                      # nothing is on it; the room shaders skip their fog for a camera that has it (no CameraFogMode on sc\Cam)

static var coffin_cam: SecurityCam = null     # CoffinCam: the camera in SCP-895's chamber, whose picture 079 can broadcast

var room: Node3D
var data: Dictionary = {}
var curr_angle := 0.0
var direction := 0
var has_screen := false
var allow_saving := false
var in_sight := false
var renders := 0            # how many times the feed has been redrawn (tests)
var coffin_renders := 0     # how many of them showed the CoffinCam's view (tests)
var coffin_effect := 0          # CoffinEffect: 0 none, 1 always SCP-895 (the one in its chamber), 2 079 may broadcast it here, 3 079 is broadcasting it
var screen_on := true           # Screen: the lever in SCP-895's chamber turns the monitor there on and off
var player_state := 0           # PlayerState: how far the horror pictures have gone (0, 1, 2)
var _gore: Array[Texture2D] = []
var _ai_face: Texture2D
var _channel: Node = null       # soundCHN: the horror sound, 079's broadcast and the camera's hum share one channel

var _base: Node3D
var _head: Node3D
var _screen: Node3D          # ScrObj: the picture, the overlay and the monitor model hang off it
var _picture: MeshInstance3D
var _overlay: MeshInstance3D
var _viewport: SubViewport
var _feed_camera: Camera3D
var _state := 0.0
var _noise: Texture2D
var _overlay_texture: Texture2D

func setup(room_node: Node3D, def: Dictionary) -> void:
	room = room_node
	data = def
	has_screen = bool(def.get("screen", false))
	coffin_effect = int(def.get("coffin", 0))
	allow_saving = bool(def.get("allow_saving", false)) and has_screen
	if coffin_effect == 1:
		coffin_cam = self
	position = Vector3(float(def.x), float(def.y), -float(def.z))
	_build()

func _build() -> void:
	add_to_group("security_cam")
	# the housing (CamBaseOBJ, 0.0015) and the head that tilts (CamOBJ, 0.01)
	_base = Node3D.new()
	add_child(_base)
	var base_mesh := MeshLoader.load_x(ContentPaths.existing_file("GFX/map/cambase.x"))
	var base_visual := MeshInstance3D.new()
	base_visual.mesh = base_mesh
	base_visual.scale = Vector3.ONE * 0.0015
	_base.add_child(base_visual)
	_head = Node3D.new()
	add_child(_head)
	var head_visual := MeshInstance3D.new()
	head_visual.mesh = MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/CamHead.b3d"))
	head_visual.scale = Vector3.ONE * 0.01
	_head.add_child(head_visual)
	_head.position = Vector3(0.0, -0.083, 0.0)
	_apply_angles()
	if has_screen and data.has("screen_at"):
		_build_screen()

func _build_screen() -> void:
	var at: Dictionary = data.screen_at
	_screen = Node3D.new()
	room.add_child(_screen)
	_screen.position = Vector3(float(at.x), float(at.y), -float(at.z))
	_screen.rotation.y = deg_to_rad(float(data.get("screen_yaw", 0.0)))
	var size := Vector2(1.0, 1.0)
	var scale := RS * 4.5 * 0.4
	var monitor_mesh := MeshLoader.load_b3d_world(ContentPaths.existing_file("GFX/map/monitor.b3d"))
	var box := monitor_mesh.get_aabb()
	size = Vector2(box.size.x, box.size.y) * scale * 0.95
	if data.has("sprite_scale"):
		size = Vector2(float(data.sprite_scale.x), float(data.sprite_scale.y)) * 2.0
	if bool(data.get("monitor", true)):
		var monitor := MeshInstance3D.new()
		monitor.mesh = monitor_mesh
		monitor.scale = Vector3.ONE * scale
		_screen.add_child(monitor)
	_picture = _quad(size)
	_screen.add_child(_picture)
	var picture_material := StandardMaterial3D.new()
	picture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	picture_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	picture_material.albedo_color = Color.BLACK
	_picture.material_override = picture_material
	if bool(data.get("overlay", true)):
		_noise = MeshLoader._load_texture(ContentPaths.existing_file("GFX/monitortexture.jpg"))
		_overlay = _quad(size)
		_overlay.position.z = 0.0005
		_overlay.material_override = GammaBlend.make(_noise, Color.WHITE, true)
		_screen.add_child(_overlay)

func _quad(size: Vector2) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad

# What the camera is turned to now: base yaw = angle + the swing, head pitch from TurnEntity.
func _apply_angles() -> void:
	var swing := clampf(curr_angle, -float(data.turn), float(data.turn))
	var yaw := deg_to_rad(float(data.angle) + swing)
	_base.rotation.y = yaw
	_head.rotation = Vector3(-deg_to_rad(_entity_pitch(float(data.pitch))), yaw, 0.0)

# UpdateSecurityCams re-applies RotateEntity(CameraObj, EntityPitch(CameraObj), ...), and EntityPitch folds a turn past
# straight down back into -90..90: the coffin camera's TurnEntity 120 ends up looking 60 degrees down, not over its back.
static func _entity_pitch(pitch: float) -> float:
	var p := wrapf(pitch, -180.0, 180.0)
	if p > 90.0:
		return 180.0 - p
	if p < -90.0:
		return -180.0 - p
	return p

func head_forward() -> Vector3:
	return _head.global_transform.basis * Vector3(0.0, 0.0, -1.0)

# sc\room\dist < 6 Or PlayerRoom = sc\room (MapSystem.bb 6380): r\dist is Max(|dx|, |dz|) from the room's origin.
func _close(player: Node3D, facility: FacilityMap) -> bool:
	if not room is FacilityRoom:
		return true
	if RoomRegistry.room_dist(room.global_position, player.global_position) < 6.0:
		return true
	return facility != null and facility.drawing.player_room == room

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or room == null:
		return
	var fps := delta * 70.0
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if not _close(player, facility):
		in_sight = false
		if coffin_cam == self and not bool(data.get("follow", false)):
			_swing(fps)
		return
	_coffin_broadcast(facility)
	var following := bool(data.get("follow", false))
	if following:
		_follow_player(player, fps)
	else:
		_swing(fps)
	_detect_player(player, facility, following)
	if has_screen and _screen != null:
		_update_screen(fps, player)
	if not in_sight and not _channel_playing():
		_channel = Sfx.play_at(self, "SFX/General/Camera.ogg", 4.0)

func _swing(fps: float) -> void:
	var turn := float(data.turn)
	if turn > 0.0:
		if direction == 0:
			curr_angle += 0.2 * fps
			if curr_angle > turn * 1.3:
				direction = 1
		else:
			curr_angle -= 0.2 * fps
			if curr_angle < -turn * 1.3:
				direction = 0
	_apply_angles()

# The picture sits in its housing, so the line of sight ends at the front of it: room2sl's monitor wall has an invisible
# collision face 0.28 in front of the screen's origin that would otherwise always hide the feed.
func _sight_target(eye: Vector3) -> Vector3:
	var spot := _screen.global_position
	return spot + (eye - spot).normalized() * minf(0.45, eye.distance_to(spot) * 0.5)

func _screen_visible(player: CharacterBody3D) -> bool:
	var camera: Camera3D = player.camera
	var spot := _screen.global_position
	if not camera.is_position_in_frustum(spot):
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, _sight_target(camera.global_position))
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_screen(fps: float, player: CharacterBody3D) -> void:
	if not screen_on:
		in_sight = false
		(_picture.material_override as StandardMaterial3D).albedo_color = Color.BLACK
		return
	_state += fps
	in_sight = player.blink_timer > -5.0 and _screen_visible(player)
	_coffin_effects(fps, player)
	if in_sight and _state >= float(data.get("render_interval", 12)):
		_render_feed()
		_state = 0.0
	_broadcast_079()
	if allow_saving and GameState.save_type() == 1:
		_monitor_saving(player)

# The picture is redrawn from the camera's own point of view (CameraRange 0.05..8, CameraZoom 0.8).
func _render_feed() -> void:
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(512, 512)
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport.own_world_3d = false
		_viewport.audio_listener_enable_3d = false
		_feed_camera = Camera3D.new()
		_feed_camera.near = 0.05
		_feed_camera.far = 8.0
		_viewport.add_child(_feed_camera)
		add_child(_viewport)
		var material := _picture.material_override as StandardMaterial3D
		material.albedo_color = Color.WHITE
		material.albedo_texture = _viewport.get_texture()
	var source: SecurityCam = self
	if coffin_effect == 3 and coffin_cam != null and is_instance_valid(coffin_cam) and randi_range(1, 5) != 5:
		source = coffin_cam
		coffin_renders += 1
	_feed_camera.fov = rad_to_deg(2.0 * atan(1.0 / float(source.data.get("zoom", 0.8))))
	_feed_camera.global_transform = Transform3D(source._head.global_transform.basis, source._head.global_position + source.head_forward() * 0.1)
	_feed_camera.cull_mask = ((CHAMBER_LAYER | DEFAULT_LAYERS) if source != self else DEFAULT_LAYERS) | FEED_LAYER
	_feed_camera.environment = _unfogged_environment()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1
	if source != self:
		_show_chamber_for_draw(source.room)

static var _feed_environment: Environment = null
static var _feed_environment_frame := -1

# The world's environment without its fog, shared by the feed cameras and copied again on each frame a feed draws, so the
# changes made to the world's (night vision ambient, gamma, a gate's background) reach the feeds as well.
func _unfogged_environment() -> Environment:
	if _feed_environment_frame == Engine.get_process_frames():
		return _feed_environment
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if holder == null or holder.environment == null:
		return null
	_feed_environment = holder.environment.duplicate() as Environment
	_feed_environment.fog_enabled = false
	_feed_environment.volumetric_fog_enabled = false
	_feed_environment_frame = Engine.get_process_frames()
	return _feed_environment

static var _lent: Dictionary = {}

# The chamber is hidden like any room far away (HideEntity); the broadcast shows it (ShowEntity) for one picture. Its visuals move to
# CHAMBER_LAYER for as long as it is shown, which only a feed camera draws, so the player's view never sees it. The picture is
# drawn within two process frames.
func _show_chamber_for_draw(chamber: Node3D) -> void:
	var visual: Node3D = chamber.get("visual")
	if _lent.is_empty():
		var root: Node3D = null
		if not chamber.visible:
			root = chamber
		elif visual != null and not visual.visible:
			root = visual
		if root == null:
			return
		_lent = {"users": 0, "room_was": chamber.visible, "visual_was": visual != null and visual.visible, "layers": []}
		_move_to_chamber_layer(root, _lent.layers)
		chamber.visible = true
		if visual != null:
			visual.visible = true
	var lent := _lent
	lent.users += 1
	await get_tree().process_frame
	await get_tree().process_frame
	lent.users -= 1
	if lent.users > 0:
		return
	_lent = {}
	for entry in lent.layers:
		if is_instance_valid(entry[0]):
			entry[0].layers = entry[1]
	var shown_by_rule := false
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		shown_by_rule = facility.drawing.ring_rooms.has(chamber)
	if is_instance_valid(chamber) and not shown_by_rule:
		chamber.visible = lent.room_was
		if visual != null and is_instance_valid(visual):
			visual.visible = lent.visual_was

func _move_to_chamber_layer(node: Node, saved: Array) -> void:
	if node is VisualInstance3D:
		saved.append([node, node.layers])
		node.layers = CHAMBER_LAYER
	for child in node.get_children():
		_move_to_chamber_layer(child, saved)

func _channel_playing() -> bool:
	return _channel != null and is_instance_valid(_channel) and _channel.playing

func _set_overlay(texture: Texture2D) -> void:
	if _overlay != null and texture != _overlay_texture:
		_overlay_texture = texture
		(_overlay.material_override as ShaderMaterial).set_shader_parameter("tex", texture)

func _ai_picture() -> Texture2D:
	if _ai_face == null:
		_ai_face = MeshLoader._load_texture(ContentPaths.existing_file("GFX/AIface.jpg"))
	return _ai_face

# UpdateSecurityCams: a monitor in sight that carries nothing, or one 079 may broadcast 895 on (effect 2), flickers to 079's face
# now and then (PlayerState is how long between flickers: MilliSecs Mod PlayerState below Rand(600)), with its broadcast sound
# once the channel is free; the first broadcast on an effect-2 monitor turns it into effect 3, the chamber's feed.
func _broadcast_079() -> void:
	if not ((in_sight and coffin_effect == 0) or coffin_effect == 2):
		return
	if player_state == 0:
		player_state = randi_range(60000, 65000)
	if int(GameState.clock_ms()) % player_state >= randi_range(1, 600):
		_set_overlay(_noise)
		return
	if not _channel_playing():
		_channel = Sfx.play_global(self, "SFX/SCP/079/Broadcast%d.ogg" % randi_range(1, 3))
		if coffin_effect == 2:
			coffin_effect = 3
			player_state = 0
	_set_overlay(_ai_picture())

# UpdateMonitorSaving: within 1 unit, in view and unobstructed, the hand shows and a click selects the monitor.
func _monitor_saving(player: CharacterBody3D) -> void:
	var camera: Camera3D = player.camera
	var near := camera.global_position.distance_to(_screen.global_position) < 1.0
	if near and _screen_visible(player):
		GameState.hand_icon = true
		if Input.is_action_just_pressed("interact") or select_requested:
			select_requested = false
			GameState.selected_monitor = self
	elif GameState.selected_monitor == self:
		GameState.selected_monitor = null
	if GameState.selected_monitor == self and in_sight:
		# the view is drawn toward the monitor (the pull is slow: Sanity is 0)
		var to := _screen.global_position - camera.global_position
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), 1.0 / 200.0)
		var flat := Vector2(to.x, to.z).length()
		player.user_pitch = lerpf(player.user_pitch, clampf(-rad_to_deg(atan2(to.y, flat)), -70.0, 70.0), 1.0 / 200.0)
		player.camera.rotation.x = -deg_to_rad(player.user_pitch)

var select_requested := false   # a test clicks the monitor

func _exit_tree() -> void:
	if coffin_cam == self:
		coffin_cam = null
	if GameState.selected_monitor == self:
		GameState.selected_monitor = null
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()

# room2sl: the monitor within `within` of the eye and in line of sight (EntityDistance + EntityVisible; no view cone).
func screen_near_and_visible(eye: Vector3, within: float) -> bool:
	if _screen == null or not is_instance_valid(_screen):
		return false
	if eye.distance_to(_screen.global_position) >= within:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, _sight_target(eye))
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# FollowPlayer cameras turn to the player (CurveAngle 75) and look down between 40 and 70 degrees.
var _follow_yaw := 0.0
var _follow_pitch := 40.0
var _follow_started := false

func _follow_player(player: CharacterBody3D, fps: float) -> void:
	var eye: Vector3 = player.camera.global_position
	var from := _head.global_position
	var flat := Vector2(eye.x - from.x, eye.z - from.z)
	var world_yaw := atan2(-flat.x, -flat.y)
	var wanted_yaw := world_yaw - global_rotation.y
	if not _follow_started:
		_follow_started = true
		_follow_yaw = wanted_yaw
	_follow_yaw = lerp_angle(_follow_yaw, wanted_yaw, minf(fps / 75.0, 1.0))
	var down := rad_to_deg(atan2(from.y - eye.y, flat.length()))
	_follow_pitch = lerpf(_follow_pitch, clampf(down, 40.0, 70.0), minf(fps / 75.0, 1.0))
	_base.rotation.y = _follow_yaw
	_head.rotation = Vector3(-deg_to_rad(_follow_pitch), _follow_yaw, 0.0)

# UpdateSecurityCams: during a camera check, a camera that has the player in view reports it
# (a fixed one only inside +-60 degrees of where it looks).
func _detect_player(player: CharacterBody3D, facility: FacilityMap, following: bool) -> void:
	if facility == null or facility.mtf.camera_check_timer <= 0.0:
		return
	var eye: Vector3 = player.camera.global_position
	if not following:
		var to_eye := eye - _head.global_position
		var yaw := wrapf(atan2(-to_eye.x, -to_eye.z) - _head.global_rotation.y, -PI, PI)
		if absf(rad_to_deg(yaw)) >= 60.0:
			return
	var query := PhysicsRayQueryParameters3D.create(_head.global_position, eye)
	query.collision_mask = 1
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		facility.mtf.camera_check_detected = true

# UpdateSecurityCams clears room2sl's cameras every frame. The other monitors' effect 2 is set by the coffin event
# (room895_event.gd) every 3 s, and effect 3 (079 is showing it) by the broadcast.
func _coffin_broadcast(facility: FacilityMap) -> void:
	if facility == null or coffin_effect == 1:
		return
	if room != null and "room_name" in room and room.room_name == "room2sl":
		coffin_effect = 0

# UpdateSecurityCams: looking at a monitor that shows SCP-895 wears the sanity down, pulls the eyes onto the screen, and on the
# way flashes the horror pictures over it, blurs the view, and makes the player sick; at -1000 (and having vomited) it kills.
func _coffin_effects(fps: float, player: CharacterBody3D) -> void:
	var s := GameState
	if not (coffin_effect == 1 or coffin_effect == 3) or s.wearing_714 or s.wearing_hazmat >= 3 or s.wearing_gas_mask >= 3:
		return
	if in_sight:
		s.sanity -= fps
		s.restore_sanity = false
	if s.sanity < -1000.0 and s.vomit_timer < -10.0:
		player.kill("\"What we know is that he died of cardiac arrest. My guess is that it was caused by SCP-895, although it has never been observed affecting video equipment from this far before. Further testing is needed to determine whether SCP-895's \"Red Zone\" is increasing.\"")
		return
	if s.vomit_timer < 0.0 and s.sanity < -800.0:
		s.restore_sanity = false
		s.sanity = -1010.0
	if not in_sight:
		return
	var camera: Camera3D = player.camera
	var smooth := minf(maxf(15000.0 / maxf(-s.sanity, 0.001), 20.0), 200.0)
	var to := _screen.global_position - camera.global_position
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(fps / smooth, 1.0))
	var flat := Vector2(to.x, to.z).length()
	player.user_pitch = lerpf(player.user_pitch, -rad_to_deg(atan2(to.y, flat)), minf(fps / smooth, 1.0))
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	if _overlay == null:
		return
	if s.sanity < -800.0:
		if randi_range(1, 3) == 1:
			_set_overlay(_noise)
		if randi_range(1, 6) < 5:
			_set_overlay(_gore_picture())
			if player_state == 1:
				Sfx.play_global(self, "SFX/Horror/Horror1.ogg")
			player_state = 2
			if not _channel_playing():
				_channel = Sfx.play_global(self, "SFX/Horror/Horror4.ogg")
			if coffin_effect == 3 and randi_range(1, 200) == 1:
				coffin_effect = 2
				player_state = randi_range(10000, 20000)
		s.blur_timer = 1000.0
		if s.vomit_timer == 0.0:
			s.vomit_timer = 1.0
	elif s.sanity < -500.0:
		if randi_range(1, 7) == 1:
			_set_overlay(_noise)
		if randi_range(1, 50) == 1:
			_set_overlay(_gore_picture())
			if player_state == 0:
				Sfx.play_global(self, "SFX/Horror/Horror0.ogg")
			player_state = maxi(player_state, 1)
			if coffin_effect == 3 and randi_range(1, 100) == 1:
				coffin_effect = 2
				player_state = randi_range(10000, 20000)
	else:
		_set_overlay(_noise)

func _gore_picture() -> Texture2D:
	if _gore.is_empty():
		for i in range(1, 7):
			_gore.append(MeshLoader._load_texture(ContentPaths.existing_file("GFX/895pics/pic%d.jpg" % i)))
	return _gore[randi_range(0, 5)]
