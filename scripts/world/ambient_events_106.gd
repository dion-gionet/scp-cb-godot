extends Node
# The scares that bring SCP-106 into the facility's rooms (UpdateEvents.bb): tunnel106, room2pit106, room2pipes106, 106sinkhole, 106victim
# and endroom106. While one runs it holds 106 (`idle`: his own code stands aside) and sets his place, turn and animation itself, as the
# original does with Curr106\Idle = True; when it ends he hunts on (State -10 or so) or goes back outside (State -10000).
# `host` is ambient_events.gd, which keeps the events' states (EventState/2/3 = s/s2/s3) and runs these in the same loop.

const RS := 8.0 / 2048.0

var host: Node

func _old() -> Node3D:
	var old: Node3D = host._valid(host.facility.scp106)
	return old

func _world() -> Node:
	return host.facility.get_parent()

func _contained() -> bool:
	return host.facility.contained_106

# a corrosion stain on the floor (pitch 90 in the original) or the ceiling (pitch -90)
func _stain(at: Vector3, size: float, growth: float, ceiling: bool = false, alpha: float = 0.8, stains: bool = false) -> MeshInstance3D:
	var pitch := PI * 0.5 if ceiling else -PI * 0.5
	return GrowingDecal.make(_world(), at, "GFX/decal1.png", size, growth, alpha, stains, Vector3(pitch, randf() * TAU, 0.0))

func _yaw(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

# CurveValue on an angle (radians)
func _turn_to(old: Node3D, target: float, smooth: float, fps: float) -> void:
	old.rotation.y += wrapf(target - old.rotation.y, -PI, PI) / smooth * fps

# "tunnel106" (7% of the tunnels): while 106 is outside, or hunting but out of sight and over 5 away, the player nearing the middle of
# the tunnel (within 3, or by chance) sees a stain spread on the ceiling; then 106 comes down out of it (frames 55-104), is let go, falls
# through the floor and surfaces under the player to hunt. If the player goes more than 8 away first, he is told to go away.
func _ev_tunnel106(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var old := _old()
	if old == null:
		return
	var player: CharacterBody3D = c.player
	var fps: float = c.fps
	if st.s == 0.0:
		if c.dist < 5.0 and c.dist > 0.0:
			if old.state >= 0.0:
				st.s = 1.0
			elif old.state <= -10.0 and old.global_position.distance_to(player.global_position) > 5.0 and not host._in_view(player, old.global_position + Vector3(0.0, 0.8, 0.0)):
				st.s = 1.0
				st.s2 = 1.0
		elif _contained():
			host._remove(c.key)
		return
	if st.s == 1.0:
		if c.dist < 3.0 or randi_range(1, 7000) == 1:
			st.s = 2.0
			_stain(Vector3(rec.position.x, rec.position.y + 445.0 * RS, rec.position.z), randf_range(0.5, 0.7), 0.0, true, randf_range(0.7, 0.85))
			Sfx.play_global(self, "SFX/Horror/Horror10.ogg")
		elif c.dist > 8.0:
			old.idle = false
			if randi_range(1, 5) != 1:
				old.state = -10000.0
			host._remove(c.key)
		return
	if st.s2 == 1.0:
		GameState.music_override = "106"
	st.s += fps
	if st.s <= 180.0:
		old.idle = true
		old.state = 1.0
		old.visible = true
		old.global_position = Vector3(rec.position.x, player.global_position.y + 1.15 - minf(sin(deg_to_rad(st.s)) * 1.5, 1.1), rec.position.z)
		old.rotation.y = _yaw(old.global_position, player.camera.global_position)
		old.animate(55.0, 104.0, 0.1, fps)
	elif st.s > 180.0 and st.s < 300.0:
		old.idle = false
		old.state = -10.0
		old.global_position = Vector3(rec.position.x, rec.position.y - 3.0, rec.position.z)
		old.path_timer = 70.0 * 10.0
		old._route_status = 0
		old._route_index = 0
		_stain(Vector3(rec.position.x, rec.position.y + 0.01, rec.position.z), 0.05, 0.01, false, 0.8, true)
		st.s = 300.0
	elif st.s < 800.0:
		if old.global_position.y >= player.global_position.y - 0.05:
			_finish_tunnel(c.key)
		else:
			old.global_position.y += (player.global_position.y - old.global_position.y) / 50.0 * fps
			if old.global_position.y < rec.position.y - 0.1:
				old.curr_speed = 0.0
	else:
		_finish_tunnel(c.key)

func _finish_tunnel(key: String) -> void:
	if GameState.music_override == "106":
		GameState.music_override = ""
	host._remove(key)

# "room2pit106": 106 waits at Objects[7] below the pit room, facing the player and trembling (frames 334-494) from when they enter it;
# after 800 frames he lets go once the player blinks.
func _ev_room2pit106(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var old := _old()
	if old == null or _contained() or old.state <= 0.0:
		return
	if st.s == 0.0:
		if c.in_room:
			st.s = 1.0
		return
	var player: CharacterBody3D = c.player
	var spot: Vector3 = c.room.object_point(7)
	if spot == Vector3.INF:
		return
	st.s += c.fps
	var yaw := _yaw(spot, player.camera.global_position) + deg_to_rad(sin(deg_to_rad(GameState.clock_ms() / 20.0)) * 6.0)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	old.visible = true
	old.idle = true
	old.rotation.y = yaw
	old.global_position = spot + forward * (sin(deg_to_rad(GameState.clock_ms() / 15.0)) * 0.06)
	old.animate(334.0, 494.0, 0.3, c.fps)
	if st.s > 800.0 and player.blink_timer < -5.0:
		old.idle = false
		host._remove(c.key)

# "room2pipes106": from when the player enters, 106 walks to the middle of the room between its two ends (Objects[0] and [1]), looks
# around (frames 334-494, turning), and walks back out; he stops and hunts if the player comes within 4 and he faces them, and stains
# open on the walls (Objects[2] and [3]).
func _ev_room2pipes106(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var old := _old()
	if old == null or _contained():
		return
	if st.s == 0.0:
		if c.in_room:
			st.s = 1.0
		return
	var player: CharacterBody3D = c.player
	var o0: Vector3 = c.room.object_point(0)
	var o1: Vector3 = c.room.object_point(1)
	if o0 == Vector3.INF or o1 == Vector3.INF:
		return
	var step: float = c.fps * 0.7
	st.s += step
	var floor_y: float = player.global_position.y
	var span := Vector2(o1.x - o0.x, o1.z - o0.z).length()
	var toward := Vector3(o1.x - o0.x, 0.0, o1.z - o0.z).normalized()
	old.visible = true
	if st.s < 50.0:
		old.idle = true
		old.rotation.y = _yaw(o0, o1)
		old.global_position = Vector3(o0.x, floor_y, o0.z) + toward * (span * 0.5 * (st.s / 50.0))
		old.animate(284.0, 333.0, 0.02 * 35.0, c.fps)
	elif st.s < 200.0:
		old.idle = true
		old.animate(334.0, 494.0, 0.2, c.fps)
		old.global_position = Vector3((o0.x + o1.x) / 2.0, floor_y, (o0.z + o1.z) / 2.0)
		_turn_to(old, deg_to_rad(st.s), 30.0, c.fps)
		if old.global_position.distance_to(player.global_position) < 4.0:
			var to_player := _yaw(old.global_position, player.global_position)
			if fposmod(rad_to_deg(to_player - old.rotation.y), 360.0) < 80.0:
				old.state = -11.0
				old.idle = false
				Sfx.play_global(self, "SFX/Horror/Horror10.ogg")
				st.s = 260.0
	elif st.s < 250.0:
		old.idle = true
		old.rotation.y = _yaw(o0, o1)
		old.global_position = Vector3(o0.x, floor_y, o0.z) + toward * (span * ((st.s - 150.0) / 100.0))
		old.animate(284.0, 333.0, 0.02 * 35.0, c.fps)
	if st.s / 250.0 > 0.3 and (st.s - step) / 250.0 <= 0.3:
		Sfx.play_global(self, "SFX/Horror/Horror6.ogg")
		GameState.blur_timer = 800.0
		_wall_stain(c.room.object_point(2), float(rec.angle) - 90.0)
	if st.s / 250.0 > 0.65 and (st.s - step) / 250.0 <= 0.65:
		_wall_stain(c.room.object_point(3), float(rec.angle) + 90.0)
	if st.s > 250.0:
		old.idle = false
		host._remove(c.key)

# CreateDecal(0, x, y, z, 0, yaw, ...): a stain on a wall that spreads; `yaw` is the room angle -90 or +90
func _wall_stain(at: Vector3, yaw: float) -> void:
	if at == Vector3.INF:
		return
	GrowingDecal.make(_world(), at, "GFX/decal1.png", 0.1, 0.003, 0.8, false, Vector3(0.0, deg_to_rad(yaw), randf() * TAU))

# "106sinkhole": a stain 2.5 across lies in the middle of the room. Within 2 of it the player slows and sinks into a crouch (and the
# sinkhole's groan loops); within 0.5 they are drawn into the middle and down, the view darkening and smearing, until 2 down: the
# pocket dimension takes them.
func _ev_106sinkhole(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = host._nodes.get(c.key, {})
	if st.s == 0.0:
		_stain(Vector3(rec.position.x + randf_range(-0.5, 0.5), rec.position.y + 0.01, rec.position.z + randf_range(-0.5, 0.5)), 2.5, 0.0)
		st.s = 1.0
		return
	if not c.in_room:
		st.s2 = 0.0
		_release(nodes)
		return
	if not nodes.has("groan") or not is_instance_valid(nodes["groan"]):
		var groan: AudioStreamPlayer3D = host._loop_at(c.room, "SFX/Room/Sinkhole.ogg", 4.5, 1.5)
		if groan != null:
			groan.global_position = Vector3(rec.position.x, rec.position.y + 0.5, rec.position.z)
		nodes["groan"] = groan
		host._nodes[c.key] = nodes
	var flat := Vector2(player.global_position.x - rec.position.x, player.global_position.z - rec.position.z).length()
	if flat >= 2.0:
		_release(nodes)
		return
	GameState.mark_pd_step()
	player.curr_speed += (0.0 - player.curr_speed) / maxf(flat * 50.0, 1.0) * c.fps
	player.crouch_state = (2.0 - flat) / 2.0
	if flat < 0.5:
		if st.s2 == 0.0:
			Sfx.play_global(self, "SFX/Room/SinkholeFall.ogg")
		nodes["holding"] = true
		GameState.unable_to_move = true
		player.global_position.x += (rec.position.x - player.global_position.x) / 10.0 * c.fps
		player.global_position.z += (rec.position.z - player.global_position.z) / 10.0 * c.fps
		player.global_position.y += ((rec.position.y - st.s2) - player.global_position.y) / 25.0 * c.fps
		player.velocity = Vector3.ZERO
		st.s2 = minf(st.s2 + c.fps / 200.0, 2.0)
		GameState.light_blink = minf(st.s2 * 5.0, 10.0)
		GameState.blur_timer = st.s2 * 500.0
		if st.s2 == 2.0:
			_release(nodes)
			host.facility.enter_pocket(player)
	else:
		_release(nodes)

func _release(nodes: Dictionary) -> void:
	if nodes.get("holding", false):
		GameState.unable_to_move = false
		nodes["holding"] = false

# "106victim": the first time the player is in the room a stain spreads on the ceiling; after 200 frames a body in 106's marks falls out
# of it and lies on the floor
func _ev_106victim(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if _contained():
		return
	var nodes: Dictionary = host._nodes.get(c.key, {})
	if c.in_room and st.s == 0.0:
		var stain := _stain(Vector3(rec.position.x, rec.position.y + 799.0 * RS, rec.position.z), 0.05, 0.0015, true)
		Sfx.play_at(stain, "SFX/SCP/106/Decay3.ogg", 15.0)
		st.s = 1.0
	if st.s <= 0.0:
		return
	var body: Node3D = host._valid(nodes.get("body"))
	if body == null:
		st.s += c.fps
	if st.s <= 200.0:
		return
	if body == null:
		body = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(rec.position.x, rec.position.y + 900.0 * RS, rec.position.z), 5)
		body.rotation.y = randf() * TAU
		body.state = 6
		nodes["body"] = body
		host._nodes[c.key] = nodes
		Sfx.play_global(self, "SFX/Horror/Horror0.ogg")
		Sfx.play_at(body, "SFX/SCP/106/Decay2.ogg", 15.0)
	# EntityType HIT_PLAYER every frame, then 0 above y 0.6 (UpdateEvents.bb 7249, 7258); the collider centre is 0.2 above the feet
	var solid: bool = body.global_position.y <= rec.position.y + 0.4
	body.set("collision_layer", 4 | (HumanNpc.PLAYER_BLOCK_LAYER if solid else 0))
	if body.global_position.y > rec.position.y + 0.15:
		body.animate(1.0, 10.0, 0.12, c.fps, false)
		_push_player_from_body(c.player, body)
	else:
		st.s += c.fps
		body.animate(11.0, 19.0, 0.25, c.fps, false)
		if not nodes.has("fell"):
			nodes["fell"] = true
			Sfx.play_global(self, "SFX/General/BodyFall.ogg")
			# 1.0, not the original's de\Size: nothing calls ScaleSprite with it, so the sprite keeps scale 1 (until a saved game is loaded, Save.bb 999)
			_stain(Vector3(rec.position.x, rec.position.y + 0.001, rec.position.z), 1.0, 0.0)
		if st.s > 400.0:
			host._remove(c.key)

# UpdateEvents.bb 7221-7227: the translation swaps the axes (x gets the z offset, z the x offset), which is how the original does it
func _push_player_from_body(player: CharacterBody3D, body: Node3D) -> void:
	var off := player.global_position - body.global_position
	var dist := off.length()
	if dist >= 0.8 or dist <= 0.0:
		return
	var flat := Vector2(off.x, off.z)
	if flat.length() <= 0.0:
		return
	flat = flat.normalized()
	var m := (dist - 0.8) * (dist - 0.8)
	player.global_position += Vector3(-flat.y * m, 0.0, -flat.x * m)

# "endroom106": a janitor is let into a dead-end room as the player nears it (unless 106 is already out); when the player is in the room he
# walks to its middle, a stain opens under him and 106 pulls him under (his frames 41-58, 106's 112-206) and leaves; if the player is near,
# he turns on them.
func _ev_endroom106(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if _contained():
		return
	var old := _old()
	if old == null:
		return
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var centre := Vector3(rec.position.x, rec.position.y, rec.position.z)
	var janitor: Node3D = host._valid(nodes.get("janitor"))
	if st.s == 0.0:
		if c.dist < 8.0 and c.dist > 0.0:
			if old.state < 0.0:
				host._remove(c.key)
				return
			var door: Node3D = c.room.door_slots.get(0)
			var at: Vector3 = door.global_position if door != null else centre
			janitor = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(at.x, rec.position.y + 0.2, at.z), 4)
			janitor.rotation.y = _yaw(janitor.global_position, centre)
			janitor.global_position += Vector3(-sin(janitor.rotation.y), 0.0, -cos(janitor.rotation.y)) * 0.5
			nodes["janitor"] = janitor
			host._nodes[c.key] = nodes
			Sfx.play_at(c.room, "SFX/Door/EndroomDoor.ogg", 15.0)
			st.s = 1.0
		return
	if janitor == null:
		return
	if st.s == 1.0:
		if c.in_room:
			janitor.state = 1
			st.s = 2.0
			Sfx.play_global(self, "SFX/Character/Janitor/106Abduct.ogg")
			if nodes.has("idle") and is_instance_valid(nodes["idle"]):
				(nodes["idle"] as Node).queue_free()
		elif c.dist < 8.0:
			if not nodes.has("idle") or not is_instance_valid(nodes["idle"]):
				nodes["idle"] = host._loop_at(janitor, "SFX/Character/Janitor/Idle.ogg", 15.0)
		return
	if st.s == 2.0:
		if Vector2(janitor.global_position.x - centre.x, janitor.global_position.z - centre.z).length() < 1.5 and janitor.global_position.distance_to(centre) < 4.0:
			_stain(Vector3(centre.x, centre.y + 0.01, centre.z), 0.05, 0.008)
			st.s = 3.0
		return
	var dist := Vector2(janitor.global_position.x - centre.x, janitor.global_position.z - centre.z).length()
	old.idle = true
	old.visible = true
	old.global_position = Vector3(centre.x, centre.y, centre.z)
	old.rotation.y = _yaw(old.global_position, janitor.global_position)
	if dist < 0.4:
		if janitor.state == 1:
			janitor.set_frame(41.0)
		st.s += c.fps / 2.0
		janitor.state = 6
		janitor.curr_speed += (0.0 - janitor.curr_speed) / 25.0 * c.fps
		janitor.global_position.x += (centre.x - janitor.global_position.x) / 25.0 * c.fps
		janitor.global_position.z += (centre.z - janitor.global_position.z) / 25.0 * c.fps
		janitor.global_position.y = centre.y + 0.1 - st.s / 70.0
		janitor.animate(41.0, 58.0, 0.1, c.fps, false)
		old.animate(206.0, 112.0, -1.0, c.fps, false)
	else:
		old.animate(112.0, 206.0, 1.5, c.fps, false)
	var near := maxf(janitor.global_position.distance_to(player.global_position), 0.05)
	player.curr_speed = minf(player.curr_speed - player.curr_speed * (0.15 / near) * c.fps, player.curr_speed)
	if st.s > 100.0:
		old.global_position.y -= 100.0
		old.idle = false
		if player.global_position.distance_to(centre) < 2.5:
			old.state = -0.1
		host.facility.remove_human(janitor)
		host._remove(c.key)
