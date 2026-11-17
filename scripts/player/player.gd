extends CharacterBody3D

# Ported from Main.bb MovePlayer / MouseLook. Blitz units run at 70 frames per second, so
# per-frame values are scaled by 70 (and 70*70 for accelerations).
const WALK_SPEED := 0.018 * 70.0
const SPRINT_MULT := 2.5
# DropSpeed -= 0.006 per frame, clamped at -2.0 per frame.
const GRAVITY := 0.006 * 70.0 * 70.0
const MAX_FALL := 2.0 * 70.0
# Collider is EntityRadius(0.15, 0.30) at its centre; the camera sits 0.6 above that centre,
# 0.3 lower while crouched (CrouchState * -0.3). Origin here is at the feet.
const EYE_STAND := 0.9
const CROUCH_DROP := 0.3
# mouselook_x_inc (0.3) * (mouse sensitivity 0.0 + 0.6), degrees per pixel at steady state.
const MOUSE_DEG_PER_PIXEL := 0.3 * 0.6
const PITCH_LIMIT := 70.0

var blink_timer := 490.0
var blink_freq := 490.0
var crouching := false
var stamina := 100.0
var dead := false
var kill_timer := 0.0
var kill_anim := 0
var head_drop_speed := 0.0
var head_pos := Vector3.ZERO
var head_pitch := 0.0
var head_yaw := 0.0
var _head_view := false
var death_yaw := 0.0
var death_pitch := 0.0

var crouch_state := 0.0
var camera_shake := 0.0   # degrees; decays by 0.1 per frame (MouseLook)
# PlayerSoundVolume: how far the player is heard; steps set it (4 sprinting, 2.5 - 0.6 crouch walking)
# and it eases back to 0 (CurveValue, smooth 5).
var sound_volume := 0.0
# FallTimer: below zero the player has been dragged down (SCP-106); it counts further negative
# each frame while the view sinks to the floor and darkens, and movement is locked.
var fall_timer := 0.0
var camera_zoom := 0.0    # CurrCameraZoom: fov pinch from 173 scares, decays 1 per frame
var zoom_override := 0.0  # a direct CameraZoom factor for one frame (0 = none), set after MouseLook by the gate A ending
var scripted := false       # a cutscene owns the body and the camera (the intro wake-up)
var drag_factor := 0.0      # a scene slows the player each frame: CurrSpeed -= CurrSpeed * drag_factor
var sprinting := false
const BASE_FOV := 90.0     # horizontal (the camera keeps its width): Blitz3D's CameraZoom 1
var curr_speed := 0.0
var shake := 0.0
var _pitch_jitter := 0.0
var _jolt := Vector2.ZERO      # degrees (pitch, yaw) the camera is turned for the next frame only
var user_pitch := 0.0
var _mouse_raw := Vector2.ZERO
var _mouse_smooth := Vector2.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | HumanNpc.PLAYER_BLOCK_LAYER
	floor_snap_length = 0.2
	if OS.get_environment("SCP_PROBE") == "1" or OS.get_environment("SCP_BOT") == "1":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_mouse_raw += event.relative

func _physics_process(delta: float) -> void:
	if dead:
		_update_death(delta * 70.0)
		return
	if kill_timer != 0.0:
		restore_view()
	var fps := delta * 70.0
	_update_super_man(fps)
	_update_drink_timers(fps)
	if dead:
		return
	sound_volume += (0.0 - sound_volume) * minf(fps / 5.0, 1.0)
	_update_blink(fps)
	_update_look(fps)
	_update_zoom(fps)
	_update_health(fps)
	if scripted:
		velocity = Vector3.ZERO
		_mouse_raw = Vector2.ZERO
		_mouse_smooth = Vector2.ZERO
		return
	if GameState.noclip:
		_noclip_move(delta)
		return
	if Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	if GameState.is_zombie:
		crouching = false     # If IsZombie Then Crouch = False
	var crouch_target := 1.0 if crouching else 0.0
	if absf(crouch_state - crouch_target) < 0.001:
		crouch_state = crouch_target
	else:
		crouch_state += (crouch_target - crouch_state) * minf(fps / 10.0, 1.0)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if GameState.force_move > 0.0:
		input = Vector2(0.0, -1.0)      # ForceMove: the body walks forward by itself
	if GameState.unable_to_move:
		input = Vector2.ZERO
	var hud := get_tree().get_first_node_in_group("hud")
	if fall_timer < 0.0:
		fall_timer -= fps
		input = Vector2.ZERO
	if hud != null and hud.item_use != null and hud.item_use.locks_movement():
		input = Vector2.ZERO   # putting on a vest or using a first aid kit holds you still
	var moving := input != Vector2.ZERO
	# Stamina regenerates every frame (slower while moving). Sprinting drains it, and running
	# dry drops it to -20 so sprint stays locked until it climbs back above 0.
	stamina = minf(stamina + 0.15 * fps * (1.0 / 1.25 if curr_speed > 0.0 else 1.25), 100.0)
	if GameState.wearing_hazmat == 1 or (hud != null and _carries(hud, "finevest")):
		stamina = minf(stamina, 60.0)
	if GameState.infinite_stamina or (not GameState.wearing_714 and (GameState.wearing_gas_mask == 2 or GameState.wearing_hazmat == 2 or GameState.wearing_1499 == 2)):
		stamina = minf(100.0, stamina + (100.0 - stamina) * 0.01 * fps)
	if GameState.wearing_714:
		stamina = minf(stamina, 10.0)
		GameState.sanity = maxf(-850.0, GameState.sanity)
	var sprint := 1.0
	sprinting = false
	if moving and not crouching and not GameState.is_zombie and GameState.force_move == 0.0 and Input.is_action_pressed("sprint") and stamina > 0.0:
		sprint = SPRINT_MULT
		sprinting = true
		stamina -= fps * 0.4 * GameState.stamina_effect
		if stamina <= 0.0:
			stamina = -20.0
	if moving:
		var phase_before := fmod(shake, 360.0)
		shake = fmod(shake + fps * minf(sprint, 1.5) * 7.0, 720.0)
		if phase_before < 180.0 and fmod(shake, 360.0) >= 180.0:
			if GameState.step_set != 2 and not GameState.pd_step_active():
				sound_volume = maxf(sound_volume, 4.0 if sprint == 1.0 else 2.5 - (1.0 if crouching else 0.0) * 0.6)
	# CurrSpeed eases toward the target (CurveValue, smooth 20) and drops to 0 when keys release.
	if moving:
		var target := WALK_SPEED * (3.0 if GameState.super_man else 1.0) * sprint / (1.0 + crouch_state)
		if GameState.force_move > 0.0:
			target *= GameState.force_move
		target /= maxf((GameState.injuries + 3.0) / 3.0, 1.0)
		if GameState.injuries > 0.5:
			target *= minf(sin(deg_to_rad(shake / 2.0)) + 1.2, 1.0)
		curr_speed += (target - curr_speed) * minf(fps / 20.0, 1.0)
		curr_speed -= curr_speed * minf(drag_factor, 1.0)
		var dir := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		velocity.x = dir.x * curr_speed
		velocity.z = dir.z * curr_speed
	else:
		curr_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	else:
		velocity.y = -0.05
	if moving and (is_on_floor() or _step_hold > 0.0) and _step_rise <= 0.0:
		_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	_step_assist(delta)
	if GameState.unable_to_move:
		velocity = Vector3.ZERO     # UnableToMove: no walking and no falling
	else:
		move_and_slide()
	_update_camera()
	_update_item_hint()
	if Input.is_action_just_pressed("interact"):
		_interact()
	if Input.is_action_just_pressed("drop_item"):
		if hud and hud.has_method("drop_selected"):
			hud.drop_selected(self)

# MouseLook: raw mouse speed is smoothed (CurveValue, smooth 6 / (sens + 1) * smoothing 1.0),
# yaw turns the collider, pitch is limited to +-70 degrees.
func _update_look(fps: float) -> void:
	if fall_timer < 0.0:
		return          # the Head branch turns the camera instead
	# CurveValue(speed, current, (6 / (MouseSens + 1)) * MouseSmooth): MouseSens is the slider's -0.5..0.5
	var smooth_time := maxf(6.0 / (GameState.mouse_sensitivity - 0.5 + 1.0) * GameState.mouse_smoothing, 0.0001)
	var blend := minf(fps / smooth_time, 1.0)
	_mouse_smooth += (_mouse_raw - _mouse_smooth) * blend
	mouse_speed = _mouse_smooth + test_mouse_speed
	_mouse_raw = Vector2.ZERO
	if _mouse_smooth.length_squared() < 0.00001:
		_mouse_smooth = Vector2.ZERO
		return
	# MouseLook: speed * (MouseSensitivity + 0.6) with the option running -0.5..0.5; the vest slows turning
	var look_scale := MOUSE_DEG_PER_PIXEL / (1.0 + GameState.wearing_vest) * (GameState.mouse_sensitivity + 0.1) / 0.6
	rotate_y(-deg_to_rad(_mouse_smooth.x * look_scale))
	user_pitch = clampf(user_pitch + _mouse_smooth.y * look_scale * (-1.0 if GameState.invert_mouse else 1.0), -PITCH_LIMIT, PITCH_LIMIT)
	camera.rotation.x = -deg_to_rad(user_pitch)

# Head bob and sway: up = sin(Shake) / (20 + CrouchState*20) * 0.6, roll from sin(Shake/2).
func _update_camera() -> void:
	if fall_timer < 0.0:
		_update_head(get_physics_process_delta_time() * 70.0)
		_head_view = true
		return
	if _head_view:
		_head_view = false
		restore_view()
	var up := sin(deg_to_rad(shake)) / (20.0 + crouch_state * 20.0) * 0.6
	var eye := EYE_STAND - crouch_state * CROUCH_DROP + up
	camera.position.y = eye
	var roll := clampf(sin(deg_to_rad(shake / 2.0)) * 2.5 * minf(GameState.injuries + 0.25, 3.0), -8.0, 8.0)
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null and facility.pocket != null:
		roll += facility.pocket.camera_roll()
	# CameraShake jitters the view by up to +-shake degrees and decays 0.1 per frame.
	camera.rotation.y = deg_to_rad(randf_range(-camera_shake, camera_shake) + _jolt.y)
	var pitch_jitter := deg_to_rad(randf_range(-camera_shake, camera_shake) - _jolt.x)
	_jolt = Vector2.ZERO
	camera.rotation.x += pitch_jitter - _pitch_jitter     # on top of whatever set the pitch since last frame
	_pitch_jitter = pitch_jitter
	camera_shake = maxf(camera_shake - 0.1 * 70.0 * get_physics_process_delta_time(), 0.0)
	camera.rotation.z = deg_to_rad(roll)

# TurnEntity Camera, pitch, yaw between MouseLook and the render: one frame of a turned view, the aim is kept.
func jolt(pitch_deg: float, yaw_deg: float) -> void:
	_jolt = Vector2(pitch_deg, yaw_deg)

# MovePlayer, SuperMan (SCP-914 very fine on the player): three times the pace, the view shakes and blurs, and 50 s later it ends.
func _update_super_man(fps: float) -> void:
	if not GameState.super_man:
		return
	GameState.super_man_timer += fps
	camera_shake = absf(sin(deg_to_rad(GameState.super_man_timer / 5.0))) * GameState.super_man_timer / 1500.0
	if GameState.super_man_timer > 70.0 * 50.0:
		kill("A Class D jumpsuit found in [DATA REDACTED]. Upon further examination, the jumpsuit was found to be filled with 12.5 kilograms of blue ash-like substance. Chemical analysis of the substance remains non-conclusive. Most likely related to SCP-914.")
	else:
		GameState.blur_timer = 500.0

# MovePlayer: DeathTimer (a slow poison from SCP-294) and StaminaEffect running out.
func _update_drink_timers(fps: float) -> void:
	var s := GameState
	if s.death_timer > 0.0:
		s.death_timer -= fps
		if s.death_timer < 1.0:
			s.death_timer = -1.0
	elif s.death_timer < 0.0:
		kill(s.death_msg)
	if s.stamina_effect_timer > 0.0:
		s.stamina_effect_timer -= fps / 70.0
	elif s.stamina_effect != 1.0:
		s.stamina_effect = 1.0

func eyes_closed() -> bool:
	return blink_timer <= -6.0 and blink_timer >= -16.0

# Kill() and the dead branch of MovePlayer: the camera follows a Head entity (radius 0.15) that
# falls and tips up or down by KillAnim; KillTimer runs the blur and the fade (see the HUD).
func _update_death(fps: float) -> void:
	GameState.blur_timer = absf(kill_timer * 5.0)
	kill_timer -= fps * 0.8
	_update_blur(fps)
	_update_head(fps)

# MovePlayer's branch for KillTimer < 0 or FallTimer < 0 (Main.bb 4441-4472): the camera sits on the Head, which slides along its
# own yaw by HeadDropSpeed and tips to -90 or +90 by KillAnim until it rests on a floor; the camera pitches 40 past it and
# the mouse still turns the camera (not the Head).
func _update_head(fps: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(head_pos, head_pos + Vector3.DOWN * 0.16, collision_mask, [get_rid()])
	var on_floor := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var curve := fps / 20.0
	if on_floor:
		head_drop_speed = 0.0
	else:
		var sign := 1.0 if kill_anim == 0 else -1.0
		var forward := Basis.from_euler(Vector3(-deg_to_rad(head_pitch), deg_to_rad(head_yaw), 0.0)) * Vector3(0.0, 0.0, -1.0)
		head_pos += forward * head_drop_speed * sign
		head_pitch += (-90.0 * sign - head_pitch) * minf(curve, 1.0)
		death_pitch += (head_pitch - 40.0 * sign - death_pitch) * minf(fps / 40.0, 1.0)
		head_drop_speed -= 0.002 * fps
	var look_scale := MOUSE_DEG_PER_PIXEL * (GameState.mouse_sensitivity + 0.1) / 0.6
	death_yaw -= _mouse_raw.x * look_scale
	death_pitch += _mouse_raw.y * look_scale * (-1.0 if GameState.invert_mouse else 1.0)
	_mouse_raw = Vector2.ZERO
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(death_pitch), deg_to_rad(death_yaw), 0.0)), head_pos)

# 106's grab and room049's capture: FallTimer = Min(-1, FallTimer), the Head put at the camera and turned to the camera's yaw
# + Rand(-45, 45) (NPCs.bb 1147-1150, UpdateEvents.bb 5782-5785).
func start_fall() -> void:
	if fall_timer < 0.0:
		return
	fall_timer = -1.0
	_drop_head(camera.global_rotation_degrees.y, float(randi_range(-45, 45)))

# The Head put at the camera (PositionEntity Head, camera; ResetEntity): `yaw` is the camera's, the Head turned `head_turn` off it.
func _drop_head(yaw: float, head_turn: float) -> void:
	head_pos = camera.global_position
	head_drop_speed = 0.0
	head_pitch = 0.0
	death_yaw = yaw
	head_yaw = yaw + head_turn
	death_pitch = user_pitch

func restore_view() -> void:
	kill_timer = 0.0
	camera.position = Vector3(0.0, EYE_STAND, 0.0)
	camera.rotation = Vector3(-deg_to_rad(user_pitch), 0.0, 0.0)

func kill(message: String) -> void:
	if GameState.god_mode:
		return
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	kill_timer = -1.0
	kill_anim = randi_range(0, 1)
	_drop_head(rotation_degrees.y, 0.0)
	Sfx.play_global(self, "SFX/Character/D9341/Damage1.ogg")
	GameState.player_died.emit(message if not message.is_empty() else GameState.death_msg)

# Main.bb: KeyHit sets the timer to 0 (even mid-blink), holding the key pins it at -10
# (eyes shut), a blink runs from 0 down to -20, then the timer resets to a random frequency.
func _update_blink(fps: float) -> void:
	# Eye drops: slower blinking for a while; the strongest ones keep the eyes open (EyeStuck).
	if GameState.blink_effect_timer > 0.0:
		GameState.blink_effect_timer -= fps / 70.0
	elif GameState.blink_effect != 1.0:
		GameState.blink_effect = 1.0
	if GameState.eye_stuck > 0.0:
		blink_timer = blink_freq
		var stuck_before := GameState.eye_stuck
		GameState.eye_stuck = maxf(GameState.eye_stuck - fps, 0.0)
		if GameState.eye_stuck < 9000.0:
			GameState.blur_timer = maxf(GameState.blur_timer, (9000.0 - GameState.eye_stuck) * 0.5)
		if GameState.eye_stuck < 9000.0 and stuck_before >= 9000.0:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null:
				hud.message("The eyedrops are causing your eyes to tear up.", 6.0)
	if Input.is_action_just_pressed("blink"):
		blink_timer = 0.0
	if Input.is_action_pressed("blink") and blink_timer < -10.0:
		blink_timer = -10.0
	if blink_timer < 0.0:
		if blink_timer <= -20.0:
			var lo := 490.0 - 35.0 * GameState.other_factors()
			blink_freq = randf_range(lo, lo + 210.0)
			blink_timer = blink_freq
		blink_timer -= fps
	else:
		blink_timer -= fps * 0.6 * GameState.blink_effect
		if GameState.eye_irritation > 0.0:
			blink_timer -= minf(GameState.eye_irritation / 100.0 + 1.0, 4.0) * fps
	GameState.eye_irritation = maxf(0.0, GameState.eye_irritation - fps)
	GameState.eyes_open = not eyes_closed()

func blink_alpha() -> float:
	if blink_timer < 0.0 and blink_timer > -5.0:
		return sin(absf(blink_timer) * deg_to_rad(18.0))
	if blink_timer <= -5.0 and blink_timer >= -15.0:
		return 1.0
	if blink_timer < -15.0 and blink_timer > -20.0:
		return absf(sin(blink_timer * deg_to_rad(18.0)))
	return 0.0

# UpdateItems: the nearest item within 1.2 of the camera that is inside the view frustum and
# not behind a wall is the one E picks up. Door buttons only work when you stand at the
# button (horizontal distance < 0.7, pick ray 0.6), so pressing a door by its leaf does nothing.
func closest_item() -> Node3D:
	var best: Node3D = null
	var best_dist := 1.2
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("pickup"):
		var item := node as Node3D
		if item == null or not item.is_inside_tree():
			continue
		var d := camera.global_position.distance_to(item.global_position)
		if d >= best_dist or not camera.is_position_in_frustum(item.global_position):
			continue
		var hit := MeshLoader.pick_ray(space, camera.global_position, item.global_position, get_rid())
		if hit.is_empty() or camera.global_position.distance_to(hit.position) > d - 0.05:
			best = item
			best_dist = d
	return best

func _update_item_hint() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("set_hint"):
		return
	var item := closest_item()
	hud.set_hint("E  take %s" % str(item.get_meta("item_name", "item")) if item else "")

# UpdateDoors: the button the hand points at and a click presses. It does not depend on where the player
# looks: a door at rest with a button less than 0.7 away on the floor plane, which the camera could touch
# (an unobstructed line of at most EntityPick's 0.6 reach), can be pressed with the back turned.
# Returns {"door": Node3D, "button": Node3D} or {}.
const BUTTON_REACH := 0.75    # camera to the middle of the button (the original picks with a 0.6 ray to its surface)

func closest_door_button() -> Dictionary:
	if GameState.grabbed_lever != null:
		return {}    # GrabbedEntity = 0 is required for a door button
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var doors: Array = facility.doors_near(global_position, 6.5) if facility != null else get_tree().get_nodes_in_group("door")
	var best := {}
	var best_flat := INF
	var space := get_world_3d().direct_space_state
	for node in doors:
		var door := node as Node3D
		if door == null or not "buttons" in door or (door.has_method("at_rest") and not door.at_rest()):
			continue
		for button in door.buttons:
			var flat := Vector2(button.global_position.x - global_position.x, button.global_position.z - global_position.z)
			if absf(flat.x) >= 1.0 or absf(flat.y) >= 1.0 or flat.length() >= 0.7 or flat.length() >= best_flat:
				continue
			if camera.global_position.distance_to(button.global_position) > BUTTON_REACH:
				continue
			var hit := MeshLoader.pick_ray(space, camera.global_position, button.global_position, get_rid())
			if not hit.is_empty() and not hit.collider.has_meta("button"):
				continue
			best = {"door": door, "button": button}
			best_flat = flat.length()
	return best

# UpdateButton: a free-standing button (not a door's) within 0.8 of the player that the camera can see.
func closest_plain_button() -> Node3D:
	if GameState.grabbed_lever != null:
		return null
	var best: Node3D = null
	var best_dist := 0.8
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("plain_button"):
		var button := node as Node3D
		if button == null or not button.is_inside_tree():
			continue
		var dist := camera.global_position.distance_to(button.global_position)   # the Blitz collider is where the camera is
		if dist >= best_dist:
			continue
		var hit := MeshLoader.pick_ray(space, camera.global_position, button.global_position, get_rid())
		if hit.is_empty() or hit.collider.has_meta("button"):
			best = button
			best_dist = dist
	return best

func _interact() -> void:
	if GameState.using_294:
		return
	var item := closest_item()
	if item:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("try_pickup") and hud.try_pickup(item):
			if item.has_meta("fill_id"):
				GameState.taken_items[str(item.get_meta("fill_id"))] = true
			item.queue_free()
		return
	var plain := closest_plain_button()
	if plain != null:
		plain.press()
		return
	var pressed := closest_door_button()
	if not pressed.is_empty():
		pressed.door.use(pressed.button)
		return
	if not interact_ray.is_colliding():
		return
	var hit := interact_ray.get_collider()
	if not is_instance_valid(hit):
		return
	if hit.has_meta("screen_image"):
		var screen_hud := get_tree().get_first_node_in_group("hud")
		if screen_hud != null and screen_hud.has_method("show_screen"):
			screen_hud.show_screen(str(hit.get_meta("screen_image")))
		return
	var node: Node = hit
	while node:
		if node.has_method("use"):
			if node.is_in_group("door"):
				return    # doors are pressed through closest_door_button (the leaf and the aim do not matter)
			node.use()
			return
		node = node.get_parent()

# NoClip in Main.bb: the collider turns to the camera and moves freely, ignoring collision.
func _noclip_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera.global_transform.basis * Vector3(input.x, 0.0, input.y)
	var speed := WALK_SPEED * GameState.noclip_speed
	if Input.is_action_pressed("sprint"):
		speed *= SPRINT_MULT
	elif Input.is_action_pressed("crouch"):
		speed *= 0.5
	velocity = Vector3.ZERO
	global_position += dir * speed * delta
	if Input.is_action_just_pressed("interact"):
		_interact()

func _carries(hud: Node, tempname: String) -> bool:
	for data in hud.item_data:
		if str(data.get("tempname", "")) == tempname:
			return true
	return false

# CurrCameraZoom = Max(CurrCameraZoom, value); the view zooms by Min(1 + zoom / 400, 1.1).
func add_camera_zoom(value: float) -> void:
	camera_zoom = maxf(camera_zoom, value)

func _update_zoom(fps: float) -> void:
	camera_zoom = maxf(camera_zoom - fps, 0.0)
	var factor := minf(1.0 + camera_zoom / 400.0, 1.1)
	if zoom_override > 0.0:
		factor = zoom_override
		zoom_override = 0.0
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_FOV) * 0.5) / factor))

func is_sprinting() -> bool:
	return sprinting

# Blitz3D's ellipsoid rode up stairs and kerbs on its own; a Godot capsule is stopped by the
# riser. When the way ahead is blocked at foot level but free STEP_HEIGHT higher, lift onto the
# tread (the ground under it is found with a downward test move).
const STEP_HEIGHT := 0.32

func _step_up(motion: Vector3) -> void:
	if motion.length_squared() < 0.000001:
		return
	var probe := motion.normalized() * maxf(motion.length(), 0.06)
	var here := global_transform
	if not test_move(here, probe):
		return
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	if test_move(here, up):
		return
	var raised := here.translated(up)
	var reach := motion.normalized() * 0.2   # the capsule centre ends just past the riser edge
	if test_move(raised, reach):
		return
	var over := raised.translated(reach)
	var params := PhysicsTestMotionParameters3D.new()
	params.from = over
	params.motion = Vector3(0.0, -STEP_HEIGHT - 0.02, 0.0)
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return   # a drop, not a step
	var rise := STEP_HEIGHT + result.get_travel().y
	if rise < 0.02:
		return
	# Rise over the next few frames at STEP_RISE_SPEED (no jump forward): the capsule keeps its
	# walking speed and the camera climbs smoothly; _step_assist applies it.
	_step_rise = rise

const STEP_RISE_SPEED := 2.0   # m/s while climbing a riser
const STEP_HOLD_TIME := 0.14   # s of no gravity after the lift, long enough to get over the edge
var _step_rise := 0.0
var mouse_speed := Vector2.ZERO        # mouse_x_speed_1 / mouse_y_speed_1: the smoothed mouse movement per frame (levers read it)
var test_mouse_speed := Vector2.ZERO   # tests add to it
var _step_hold := 0.0

func _step_assist(delta: float) -> void:
	# the floor snap would pull the capsule straight back down while it is being lifted
	floor_snap_length = 0.0 if (_step_rise > 0.0 or _step_hold > 0.0) else 0.2
	if _step_rise > 0.0:
		var up := minf(_step_rise, STEP_RISE_SPEED * delta)
		if test_move(global_transform, Vector3(0.0, up, 0.0)):
			_step_rise = 0.0     # a ceiling or lip got in the way: stop lifting
		else:
			global_position.y += up
			_step_rise -= up
			if _step_rise <= 0.0:
				_step_hold = STEP_HOLD_TIME
		velocity.y = 0.0
	elif _step_hold > 0.0:
		_step_hold -= delta
		velocity.y = 0.0

# Main.bb MovePlayer / DrawGUI health: injuries over 1 bleed (Bloodloss climbs, the view blurs and
# the player is forced to crouch past 60), 100 is death. BlurTimer feeds BlurVolume, which eases
# back to 0 (CurveValue, smooth 20) and is capped at 0.95. Sanity, once lowered, comes back 1 per frame.
func _update_blur(fps: float) -> void:
	var s := GameState
	s.blur_volume = minf(s.blur_volume + (0.0 - s.blur_volume) / 20.0 * minf(fps, 20.0), 0.95)
	if s.blur_timer > 0.0:
		s.blur_volume = maxf(minf(0.95, s.blur_timer / 1000.0), s.blur_volume)
		s.blur_timer = maxf(s.blur_timer - fps, 0.0)

func _update_health(fps: float) -> void:
	var s := GameState
	_update_blur(fps)
	s.light_blink = maxf(s.light_blink - fps / 35.0, 0.0)
	if s.sanity < 0.0 and s.restore_sanity:
		s.sanity = minf(s.sanity + fps, 0.0)
	s.restore_sanity = true
	if s.injuries > 1.0:
		s.blur_timer = maxf(maxf(sin(deg_to_rad(GameState.clock_ms() / 100.0)) * s.bloodloss * 30.0, s.bloodloss * 2.0 * (2.0 - crouch_state)), s.blur_timer)
		if not (s.i427_using or s.i427_timer >= 70.0 * 360.0):
			s.bloodloss = minf(s.bloodloss + (minf(s.injuries, 3.5) / 300.0) * fps, 100.0)
	if s.heal_timer > 0.0:
		s.heal_timer -= fps / 70.0
		s.bloodloss = minf(s.bloodloss + (2.0 / 400.0) * fps, 100.0)
		s.injuries = maxf(s.injuries - (fps / 70.0) / 30.0, 0.0)
	if s.bloodloss > 0.0:
		if randf_range(0.0, 200.0) < minf(s.injuries, 4.0):
			GrowingDecal.drip(self, "GFX/blooddrop%d.png" % randi_range(1, 2), randf_range(0.03, 0.08) * minf(s.injuries, 3.0))
		camera_zoom = maxf(camera_zoom, (sin(deg_to_rad(GameState.clock_ms() / 20.0)) + 1.0) * s.bloodloss * 0.2)
		if s.bloodloss > 60.0:
			crouching = true
		var audio := get_tree().get_first_node_in_group("audio")
		if s.bloodloss >= 100.0:
			kill("")
		elif audio != null and s.bloodloss > 80.0:
			audio.heartbeat(0.75 + (s.bloodloss - 80.0) * 0.0125, maxf(150.0 - (s.bloodloss - 80.0) * 5.0, 70.0))
		elif audio != null and s.bloodloss > 35.0:
			audio.heartbeat((s.bloodloss - 35.0) / 60.0, 70.0 + s.bloodloss)
