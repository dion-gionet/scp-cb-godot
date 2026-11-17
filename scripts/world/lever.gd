extends Node3D
class_name Lever
# A lever (MapSystem.bb UpdateLever): a base and a handle (leverbase.x / leverhandle.x, scale 0.04) that swings
# between pitch -80 and +80. Within 0.8 of the handle and looking at it (a 0.65 pick of a 0.1 sphere) the hand
# shows and a click grabs it; while held the mouse moves it (mouse_y_speed * 8 degrees a frame, at most 30) and
# a click-less handle falls to the nearer end (CurveValue, smooth 10). Past +-75 it clunks.
# "On" is pitch > 0. Positions are the room's, in room-local Godot coordinates.


var pitch := 10.0              # Blitz pitch of the handle
var locked := false
var flips := 0                 # times it passed a clunk point (tests)

var _handle: Node3D
var _model_scale := 0.04
var _pick_centre := Vector3.ZERO     # the handle's pick sphere, in the handle's frame
var _pick_radius := 0.1

func setup(local_pos: Vector3, handle_yaw_deg: float, start_pitch: float, model_scale: float = 0.04) -> void:
	_model_scale = model_scale
	position = local_pos
	pitch = start_pitch
	var base := MeshInstance3D.new()
	base.mesh = MeshLoader.load_x(ContentPaths.existing_file("GFX/map/leverbase.x"))
	base.scale = Vector3.ONE * _model_scale
	base.rotation.y = deg_to_rad(handle_yaw_deg + 180.0)     # every FillRoom turns the base half round from the handle
	add_child(base)
	_handle = Node3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = MeshLoader.load_x(ContentPaths.existing_file("GFX/map/leverhandle.x"))
	visual.scale = Vector3.ONE * _model_scale
	_handle.add_child(visual)
	add_child(_handle)
	_handle.rotation = Vector3(-deg_to_rad(pitch), deg_to_rad(handle_yaw_deg), 0.0)
	var box := visual.mesh.get_aabb()
	_pick_centre = (box.position + box.size * 0.5) * _model_scale
	_pick_radius = maxf(0.1, box.size.length() * _model_scale * 0.5)

func is_on() -> bool:
	return pitch > 0.0

func handle_point() -> Vector3:
	return _handle.to_global(_pick_centre)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or _handle == null:
		return
	var fps := delta * 70.0
	var camera: Camera3D = player.camera
	var dist := camera.global_position.distance_to(_handle.global_position)
	var holding := Input.is_action_pressed("interact")
	if dist < 8.0:
		if dist < 0.8 and not locked and camera.is_position_in_frustum(handle_point()):
			if aimed_at(camera):
				GameState.hand_icon = true
				if Input.is_action_just_pressed("interact"):
					GameState.grabbed_lever = self
			var before := pitch
			if holding and GameState.grabbed_lever == self:
				GameState.hand_icon = true
				GameState.arrow_icons[0] = true
				GameState.arrow_icons[2] = true
				pitch = clampf(pitch + clampf(player.mouse_speed.y * 8.0, -30.0, 30.0), -80.0, 80.0)
			if pitch > 75.0 and before <= 75.0 or pitch < -75.0 and before >= -75.0:
				flips += 1
				Sfx.play_at(self, "SFX/Interact/LeverFlip.ogg", 6.0)
		if not holding:
			var target := 80.0 if pitch > 0.0 else -80.0
			pitch += (target - pitch) * minf(fps / 10.0, 1.0)
			if GameState.grabbed_lever == self:
				GameState.grabbed_lever = null
	if not holding and GameState.grabbed_lever == self:
		GameState.grabbed_lever = null    # GrabbedEntity is cleared whenever the button is up, however far away the lever is
	_handle.rotation.x = -deg_to_rad(pitch)

# EntityPick(Camera, 0.65) = the handle: the view ray passes within the sphere.
func aimed_at(camera: Camera3D, reach: float = 0.65) -> bool:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var centre := handle_point()
	var along := clampf((centre - origin).dot(forward), 0.0, reach)
	return (origin + forward * along).distance_to(centre) <= _pick_radius

func _exit_tree() -> void:
	if GameState.grabbed_lever == self:
		GameState.grabbed_lever = null
