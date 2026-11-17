extends Node
# Smaller set pieces of single rooms (UpdateEvents.bb): room_gw (the guards' airlocks), room2fan, room2elevator and room2elevator2,
# room2poffices2, testroom173 and room2closets. `host` is ambient_events.gd (it keeps EventState/2/3 as s/s2/s3 and runs these).

const RS := 8.0 / 2048.0
const Tentacle = preload("res://scripts/npc/scp_tentacle.gd")

var host: Node

func _world() -> Node:
	return host.facility.get_parent()

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _stain(at: Vector3, size: float, texture: String = "GFX/decal4.png", orientation: Vector3 = Vector3.INF) -> MeshInstance3D:
	return GrowingDecal.make(_world(), at, texture, size, 0.0, 0.8, false, orientation)

# "room_gw" (every room2gw and room3gw): both doors stay locked (open); stepping into the airlock (within 1.4 of Objects[0]) shuts both and
# sounds the alarm for 7 s while steam fills it (and, in the one with the broken door, sparks fly); then they open again. Out of the
# airlock the player must go 2.4 away before it will work again.
func _ev_room_gw(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var room: Node3D = c.room
	var door_a: Node3D = room.door_slots.get(0)
	var door_b: Node3D = room.door_slots.get(1)
	if door_a == null or door_b == null:
		return
	door_a.locked = true
	door_b.locked = true
	var spot: Vector3 = room.object_point(0)
	if spot == Vector3.INF:
		return
	var broken: bool = host.plan.broken_gw_key == c.key
	if broken and not host._nodes.get(c.key, {}).has("trimmed"):
		var nodes: Dictionary = host._nodes.get(c.key, {})
		nodes["trimmed"] = true
		host._nodes[c.key] = nodes
		door_b.drop_second_leaf()
	if not c.in_room:
		st.s3 = 0.0
		return
	var player: CharacterBody3D = c.player
	var fps: float = c.fps
	var nodes_now: Dictionary = host._nodes.get(c.key, {})
	if st.s == 0.0:
		var flat := Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length()
		if flat < 1.4 and st.s3 == 0.0:
			st.s = 1.0
			if broken:
				var sparks := Sfx.play_at(room, "SFX/Door/DoorSparks.ogg", 5.0)
				if sparks != null:
					sparks.global_position = door_b.global_position
			nodes_now.erase("steam")
			host._nodes[c.key] = nodes_now
			door_a.locked = false
			door_b.locked = false
			if door_a.open:
				door_a.toggle(true)
			if door_b.open:
				door_b.toggle(true)
			Sfx.play_global(self, "SFX/Alarm/Alarm5.ogg")
		elif flat > 2.4:
			st.s3 = 0.0
		return
	if st.s2 < 70.0 * 7.0:
		st.s2 += fps
		door_a.open = false
		door_b.open = false
		if st.s2 < 70.0:
			if broken:
				_sparks(room, door_b, rec)
		elif st.s2 > 70.0 * 3.0:
			var jets: Array = []
			if str(room.room_name) == "room3gw":
				jets = [Vector3(-288.0, 416.0, 320.0), Vector3(192.0, 416.0, 320.0)]
			else:
				jets = [Vector3(312.0, 416.0, -128.0), Vector3(312.0, 416.0, 224.0)]
			for jet in jets:
				var puff = host.facility.particles.create(room.to_global(Vector3(jet.x * RS, jet.y * RS, -jet.z * RS)), 6, 0.8, 0.0, 50.0)
				if puff != null:
					puff.speed = 0.025
					puff.dir = Vector3.DOWN
					puff.a_change = -0.02
			if not nodes_now.has("steam"):
				var voice := Sfx.play_at(room, "SFX/Door/Airlock.ogg", 5.0)
				if voice != null:
					voice.global_position = spot
				nodes_now["steam"] = voice
				host._nodes[c.key] = nodes_now
	else:
		st.s = 0.0
		st.s2 = 0.0
		st.s3 = 1.0
		if not door_a.open:
			door_a.locked = false
			door_b.locked = false
			door_a.toggle(true)
			door_b.toggle(true)

# spark.jpg flecks from the broken door (Particles image 7, additive, 4 a frame at the ParticleAmount of the options)
func _sparks(room: Node3D, door: Node3D, _rec: Dictionary) -> void:
	var yaw: float = door.rotation.y + PI * 0.5
	var at: Vector3 = door.global_position + Vector3(0.0, randf_range(0.0, 0.05), 0.0)
	at += Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.2
	for i in 4:
		var spark = host.facility.particles.create(at, 7, 0.0075, 0.0, 25.0)
		if spark != null:
			spark.speed = randf_range(0.01, 0.05)
			var pitch := deg_to_rad(randf_range(-45.0, 0.0))
			var turn := yaw + deg_to_rad(randf_range(-10.0, 10.0))
			spark.dir = Vector3(-sin(turn) * cos(pitch), -sin(pitch), -cos(turn) * cos(pitch)).normalized()
			spark.a_change = -0.05

# "room2fan" (every room2_2): the fan in the ceiling (Objects[0], built with the room) switches on and off every 15 to 30 s while the
# player is within 16, spinning up and down (CurveValue, smooth 150) with FanOn / FanOff and its drone while they are in the room
func _ev_room2fan(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if c.room.fan == null:
		return
	var fan: Node3D = c.room.fan
	var nodes: Dictionary = host._nodes.get(c.key, {})
	if c.in_room:
		fan.rotate_object_local(Vector3.RIGHT, deg_to_rad(st.s3 * c.fps))
		if st.s3 > 0.01:
			if not nodes.has("drone") or not is_instance_valid(nodes["drone"]):
				var drone: AudioStreamPlayer3D = host._loop_at(fan, "SFX/Ambient/Room ambience/Fan.ogg", 5.0)
				nodes["drone"] = drone
				host._nodes[c.key] = nodes
			if is_instance_valid(nodes.get("drone")):
				(nodes["drone"] as AudioStreamPlayer3D).volume_db = linear_to_db(maxf(st.s3 / 4.0, 0.0001))
		st.s3 += (st.s2 * 5.0 - st.s3) / 150.0 * c.fps
	if c.dist < 16.0:
		if st.s < 0.0:
			st.s = float(randi_range(15, 30)) * 70.0
			var before: float = st.s2
			st.s2 = float(randi_range(0, 1))
			if not c.in_room:
				st.s3 = st.s2 * 5.0
			elif before == 0.0 and st.s2 == 1.0:
				Sfx.play_at(fan, "SFX/Ambient/Room ambience/FanOn.ogg", 8.0)
			elif before == 1.0 and st.s2 == 0.0:
				Sfx.play_at(fan, "SFX/Ambient/Room ambience/FanOff.ogg", 8.0)
		else:
			st.s -= c.fps

# "room2elevator": a guard stands in the room (made within 8 of it) facing the player; as they come within 5 (or after a while) he
# runs for the lift door at Objects[1]; there the door shuts on him, a scream plays and the room shakes for 13 s, and he is gone,
# leaving blood on the floor and the wall. The door unlocks for the player when it is over and locks again once it opens.
func _ev_room2elevator(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var room: Node3D = c.room
	var door: Node3D = room.door_slots.get(0)
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var guard: Node3D = host._valid(nodes.get("guard"))
	var player: CharacterBody3D = c.player
	if st.s == 0.0:
		if c.dist < 8.0 and c.dist > 0.0:
			guard = host.facility.spawn_human(HumanNpc.Kind.GUARD, Vector3(rec.position.x, rec.position.y + 0.2, rec.position.z))
			guard.rotation.y = host._yaw_toward(guard.global_position, player.global_position)
			nodes["guard"] = guard
			host._nodes[c.key] = nodes
			st.s = 1.0
		return
	var door_point: Vector3 = room.object_point(1)
	var floor_point: Vector3 = room.object_point(0)
	if st.s == 1.0:
		if (c.dist < 5.0 or randi_range(1, 700) == 1) and guard != null and door_point != Vector3.INF:
			st.s = 2.0
			guard.state = 5
			guard.enemy = door_point
	elif st.s == 2.0:
		if guard != null and door_point != Vector3.INF and guard.global_position.distance_to(door_point) < 2.0:
			if door != null:
				door.open = false
				Sfx.play_at(door, "SFX/Door/ElevatorClose1.ogg", 8.0)
			Sfx.play_global(self, "SFX/Room/Room2ElevatorDeath.ogg")
			st.s = 2.05
	elif st.s < 13.0 * 70.0:
		st.s += c.fps
		if st.s > 6.7 * 70.0 and st.s < 7.4 * 70.0:
			player.camera_shake = 7.4 - st.s / 70.0
		elif st.s > 8.6 * 70.0 and st.s < 10.6 * 70.0:
			player.camera_shake = 10.6 - st.s / 70.0
		elif st.s > 12.6 * 70.0:
			player.camera_shake = 0.0
			if st.s - c.fps < 12.6 * 70.0 and guard != null:
				host.facility.remove_human(guard)
				nodes.erase("guard")
				if floor_point != Vector3.INF:
					_stain(Vector3(floor_point.x, rec.position.y + 0.0005, floor_point.z), 1.0, "GFX/decal4.png", Vector3(-PI * 0.5, randf() * TAU, 0.0))
					# 1.0, not the original's de\Size: nothing calls ScaleSprite with it, so the sprite keeps scale 1 (until a saved game is loaded, Save.bb 999)
					_stain(Vector3(floor_point.x, rec.position.y + 0.002, floor_point.z), 1.0, "GFX/decal8.png", Vector3(-PI * 0.5, randf() * TAU, 0.0))
				if door_point != Vector3.INF:
					_stain(door_point, 1.0, "GFX/decal4.png", Vector3(0.0, deg_to_rad(float(rec.angle) + 270.0), 0.0))
			if door != null:
				door.locked = false
	else:
		if door != null and door.open:
			door.locked = true
			host._remove(c.key)

# "room4tunnels": within 10 a Class D corpse (body1.jpg, frame 19, State 8) lies at the room centre +1 +1, turned 20-60 degrees off the room's yaw
func _ev_room4tunnels(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if c.dist >= 10.0 or c.dist <= 0.0:
		return
	var body: Node3D = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(rec.position.x + 1.0, rec.position.y + 0.5, rec.position.z - 1.0), 8)
	body.rotation.y = deg_to_rad(float(rec.angle) - randi_range(20, 60))
	body.set_frame(19.0)
	body.state = 8
	host._remove(c.key)

# "room2elevator2": when the player is within 8 a body lies in a pool of blood at Objects[0]
func _ev_room2elevator2(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if c.dist >= 8.0 or c.dist <= 0.0:
		return
	var spot: Vector3 = c.room.object_point(0)
	if spot == Vector3.INF:
		host._remove(c.key)
		return
	_stain(Vector3(spot.x, rec.position.y + 0.0005, spot.z), 1.0, "GFX/decal4.png", Vector3(-PI * 0.5, randf() * TAU, 0.0))
	var body: Node3D = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(spot.x, rec.position.y + 0.2, spot.z), 0)
	body.rotation.y = deg_to_rad(float(rec.angle) - 80.0)
	body.set_frame(19.0)
	body.state = 8
	host._remove(c.key)

# "room2poffices2": in the room, with the remote door control on, the keypad door opens by itself when the player comes within 1.5; once it
# is fully open a sting plays, and from then on, near the burnt note at Objects[0], the heart races, breathing is heard and 106's counter
# runs three times faster
func _ev_room2poffices2(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var door: Node3D = c.room.door_slots.get(0)
	if door == null:
		return
	var player: CharacterBody3D = c.player
	if st.s == 0.0:
		if door.open:
			if door.openstate >= 180.0:
				st.s = 1.0
				Sfx.play_global(self, "SFX/Horror/Horror5.ogg")
		elif player.global_position.distance_to(door.global_position) < 1.5 and host.facility.remote_door_on:
			door.open = true
	else:
		var note: Vector3 = c.room.object_point(0)
		if note != Vector3.INF and player.global_position.distance_to(note) < 2.0:
			var audio := get_tree().get_first_node_in_group("audio")
			if audio != null:
				audio.heartbeat_curve(0.5, 120.0, 5.0, 150.0, c.fps)
			var nodes: Dictionary = host._nodes.get(c.key, {})
			if not nodes.has("breath") or not is_instance_valid(nodes["breath"]):
				var breath: AudioStreamPlayer3D = host._loop_at(c.room, "SFX/SCP/106/Breathing.ogg", 5.0, 0.3)
				nodes["breath"] = breath
				host._nodes[c.key] = nodes
			var old: Node3D = host._valid(host.facility.scp106)
			if old != null:
				old.state -= c.fps * 3.0

# "testroom173": once the door of the test room is open and the player is in it, 173 is put at Objects[0], behind a window; the glass shows
# and 173 waits there. With the player 1.4 away from the window and blinking after 12 s it breaks through and stands at Objects[1]
# (it is dropped if it has been taken far from the room; within 1 of the window it comes sooner).
func _ev_testroom173(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var statue: Node3D = GameState.scp173
	if statue == null or statue.idle != 0:
		return
	var player: CharacterBody3D = c.player
	var room: Node3D = c.room
	var behind: Vector3 = room.object_point(0)
	var window: Vector3 = room.object_point(1)
	if behind == Vector3.INF or window == Vector3.INF:
		return
	var nodes: Dictionary = host._nodes.get(c.key, {})
	if st.s == 0.0:
		var door: Node3D = room.door_slots.get(0)
		if door != null and door.open:
			host._put_173(Vector3(behind.x, rec.position.y + 0.31, behind.z))
			st.s = 1.0
		return
	if not nodes.has("glass") or not is_instance_valid(nodes["glass"]):
		var glass := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		glass.mesh = quad
		glass.material_override = GammaBlend.make(MeshLoader._load_texture(ContentPaths.existing_image("GFX/map/glass.png")), Color.WHITE, false, false)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass.scale = Vector3(182.0 * RS * 0.5, 192.0 * RS * 0.5, 1.0)
		room.add_child(glass)
		glass.position = Vector3(-632.0 * RS, 224.0 * RS, 208.0 * RS)
		nodes["glass"] = glass
		host._nodes[c.key] = nodes
	st.s += c.fps
	var dist := player.global_position.distance_to(window)
	if dist < 1.0:
		st.s = maxf(st.s, 70.0 * 12.0)
	elif dist > 1.4:
		if st.s > 70.0 * 12.0 and player.blink_timer <= -10.0:
			if statue.global_position.distance_to(behind) > 5.0:
				host._remove(c.key)
			else:
				Sfx.play_at(statue, "SFX/General/GlassBreak.ogg", 10.0)
				(nodes["glass"] as Node).queue_free()
				nodes.erase("glass")
				host._put_173(Vector3(window.x, rec.position.y + 0.31, window.z))
				host._remove(c.key)

# "room2closets": the first time the player is in the room (and 173 is free) a janitor and a scientist are in the storeroom's two
# corners at Objects[0] and [1], the janitor running (Escape1) and the scientist (Escape2) calling out. After 3.5 s he stops; at 6.5 s a
# sting and the light switch; the player is made to blink, and while the eyes are shut 173 breaks both necks (7.5 s and 8 s: a wallet with
# two quarters falls where the janitor was) and at 8.5 s is put between them, turned to the player.
func _ev_room2closets(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	var statue: Node3D = GameState.scp173
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var player: CharacterBody3D = c.player
	var janitor: Node3D = host._valid(nodes.get("janitor"))
	var scientist: Node3D = host._valid(nodes.get("scientist"))
	if st.s == 0.0:
		if c.in_room and statue != null and statue.idle < 2:
			var first: Vector3 = c.room.object_point(0)
			var second: Vector3 = c.room.object_point(1)
			if first == Vector3.INF or second == Vector3.INF:
				host._remove(c.key)
				return
			janitor = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(first.x, rec.position.y + 0.2, first.z), 4)
			scientist = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, Vector3(second.x, rec.position.y + 0.2, second.z), 2)
			janitor.rotation.y = host._yaw_toward(janitor.global_position, scientist.global_position)
			scientist.rotation.y = host._yaw_toward(scientist.global_position, janitor.global_position)
			nodes["janitor"] = janitor
			nodes["scientist"] = scientist
			host._nodes[c.key] = nodes
			Sfx.play_at(janitor, "SFX/Room/Storeroom/Escape1.ogg", 12.0)
			st.s = 1.0
		return
	if janitor == null or scientist == null:
		return
	st.s += c.fps
	var centre := Vector3(rec.position.x, rec.position.y, rec.position.z)
	var angle := deg_to_rad(float(rec.angle))
	if st.s < 70.0 * 3.5:
		scientist.rotation.y = lerp_angle(scientist.rotation.y, angle + PI * 0.5, minf(c.fps / 100.0, 1.0))
		janitor.state = 1
		if st.s > 70.0 * 3.2 and st.s - c.fps <= 70.0 * 3.2:
			Sfx.play_at(c.room, "SFX/Room/Intro/173Vent.ogg", 15.0)
	elif st.s < 70.0 * 6.5:
		if st.s - c.fps < 70.0 * 3.5:
			janitor.state = 0
			Sfx.play_at(scientist, "SFX/Room/Storeroom/Escape2.ogg", 12.0)
		if st.s > 70.0 * 4.5:
			janitor.rotation.y = lerp_angle(janitor.rotation.y, host._yaw_toward(janitor.global_position, centre), minf(c.fps / 30.0, 1.0))
		var aim: float = host._yaw_toward(scientist.global_position, centre) + deg_to_rad(sin(st.s) * 25.0)
		scientist.rotation.y = lerp_angle(scientist.rotation.y, aim, minf(c.fps / 30.0, 1.0))
	else:
		if st.s - c.fps < 70.0 * 6.5:
			Sfx.play_global(self, "SFX/Horror/Horror0.ogg")
			Sfx.play_global(self, "SFX/General/LightSwitch.ogg")
		player.blink_timer = maxf((70.0 * 6.5 - st.s) / 5.0 - randf_range(0.0, 2.0), -10.0)
		if player.blink_timer == -10.0:
			if st.s > 70.0 * 7.5 and st.s - c.fps <= 70.0 * 7.5:
				Sfx.play_at(janitor, "SFX/SCP/173/NeckSnap1.ogg", 8.0)
				var wallet := RoomFill.make_pickup("Wallet", "wallet")
				_world().add_child(wallet)
				var heading := scientist.global_position - janitor.global_position
				heading.y = 0.0
				heading = heading.normalized()
				var toss := Vector3(0.4 * heading.z - 0.2 * heading.x, 0.0, -0.4 * heading.x - 0.2 * heading.z)
				var spot := janitor.global_position + toss
				var floor_hit := MeshLoader.pick_ray(janitor.get_world_3d().direct_space_state, spot + Vector3(0.0, 0.05, 0.0), spot + Vector3(0.0, -9.95, 0.0), RID())
				wallet.global_position = Vector3(spot.x, floor_hit.position.y, spot.z) if not floor_hit.is_empty() else spot
				var slots: Array = []
				for i in 10:
					slots.append({})
				for i in 2:
					slots[i] = {"name": "Quarter", "data": {"tempname": "25ct", "icon": str(RoomFill.item_template("Quarter", "25ct").get("icon", "GFX/items/INVcoin.jpg")), "state": 0.0}}
				wallet.set_meta("inv", slots)
			if st.s > 70.0 * 8.0 and st.s - c.fps <= 70.0 * 8.0:
				Sfx.play_at(scientist, "SFX/SCP/173/NeckSnap2.ogg", 8.0)
			janitor.set_frame(60.0)
			janitor.state = 8
			scientist.set_frame(19.0)
			scientist.state = 6
		if st.s > 70.0 * 8.5 and statue != null:
			var between: Vector3 = (janitor.global_position + scientist.global_position) * 0.5
			host._put_173(Vector3(between.x, rec.position.y + 0.31, between.z))
			statue.rotation.y = host._yaw_toward(statue.global_position, player.global_position)
			host._remove(c.key)

# "room2offices035": once SCP-035 has been let out (the room035 event is -1) the offices hold his victim: a body in 035's skin at the
# room's middle (moved half a metre off it) lying at frame 19, and when the player comes within 2.5 of it a tentacle rises 0.6 beyond it.
# The tentacle is dropped once the player is more than 15 away.
func _ev_room2offices035(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	var released := false
	for room in host.facility.generator.rooms:
		if str(room.name) == "room035" and host.facility.ambient.states.has(room.key) and float(host.facility.ambient.state_of(room.key).s) < 0.0:
			released = true
			break
	if not released:
		return
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var body: Node3D = host._valid(nodes.get("body"))
	var tentacle: Node3D = host._valid(nodes.get("tentacle"))
	var player: CharacterBody3D = c.player
	if c.dist < 8.0:
		var angle := deg_to_rad(float(rec.angle))
		if body == null:
			var yaw := angle + PI
			var spot := Vector3(rec.position.x, rec.position.y + 0.2, rec.position.z) - 0.5 * Vector3(sin(angle), 0.0, cos(angle))
			body = host.facility.spawn_human(HumanNpc.Kind.CLASS_D, spot, 7)
			body.rotation.y = yaw
			body.state = 3
			body.set_frame(19.0)
			nodes["body"] = body
			host._nodes[c.key] = nodes
		if tentacle == null and body.global_position.distance_to(player.global_position) < 2.5:
			tentacle = Node3D.new()
			tentacle.set_script(Tentacle)
			_world().add_child(tentacle)
			var ahead := Vector3(body.global_position.x, rec.position.y, body.global_position.z) + 0.6 * Vector3(-sin(angle), 0.0, -cos(angle))
			tentacle.global_position = ahead
			tentacle.face(angle)
			tentacle.in_offices = true
			nodes["tentacle"] = tentacle
			host._nodes[c.key] = nodes
	elif c.dist > 15.0 and tentacle != null:
		tentacle.queue_free()
		nodes.erase("tentacle")

# "room2scps2": within 15 of the room Emily Ross screams from Objects[0] (heard 100 m off) and a stain appears there; when the scream is
# over the keycard door (RoomDoors[0]) is unlocked. If 106 is contained or already chasing (State below 0) the door is unlocked at once
# with the stain, and the event ends.
func _ev_room2scps2(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if c.dist >= 15.0:
		return
	var room: Node3D = c.room
	var door: Node3D = room.door_slots.get(0)
	var spot: Vector3 = room.object_point(0)
	if spot == Vector3.INF:
		host._remove(c.key)
		return
	var chasing: bool = host.facility.contained_106 or (host.facility.scp106 != null and is_instance_valid(host.facility.scp106) and float(host.facility.scp106.state) < 0.0)
	if chasing:
		st.s = 2.0
	if st.s < 2.0:
		var nodes: Dictionary = host._nodes.get(c.key, {})
		if st.s == 0.0:
			var scream := Node3D.new()
			room.add_child(scream)
			scream.global_position = spot
			var voice_player: AudioStreamPlayer3D = Sfx.play_at(scream, "SFX/Character/Scientist/EmilyScream.ogg", 100.0)
			if voice_player != null:
				voice_player.finished.connect(scream.queue_free)
			nodes["scream"] = voice_player
			host._nodes[c.key] = nodes
			# 1.0, not the original's de\Size: nothing calls ScaleSprite with it, so the sprite keeps scale 1 (until a saved game is loaded, Save.bb 999)
			_stain(Vector3(spot.x, room.global_position.y + 2.0 * RS, spot.z), 1.0, "GFX/decal1.png")
			st.s = 1.0
		else:
			var voice: Variant = nodes.get("scream")
			if voice == null or not is_instance_valid(voice) or not (voice as AudioStreamPlayer3D).playing:
				st.s = 2.0
				if door != null:
					door.locked = false
	else:
		if door != null:
			door.locked = false
		# 1.0, not the original's de\Size: nothing calls ScaleSprite with it, so the sprite keeps scale 1 (until a saved game is loaded, Save.bb 999)
		_stain(Vector3(spot.x, room.global_position.y + 2.0 * RS, spot.z), 1.0, "GFX/decal1.png")
		host._remove(c.key)

# "room2cafeteria": next to the 294 machine's work, UpdateEvents makes SCP-066 at the room's middle (0.5 up) the first time it runs.
func _ev_room2cafeteria(rec: Dictionary, st: Dictionary, _c: Dictionary) -> void:
	if st.s == 0.0 or get_tree().get_first_node_in_group("scp066") == null:
		var ball := CharacterBody3D.new()
		ball.set_script(load("res://scripts/npc/scp_066.gd"))
		_world().add_child(ball)
		ball.global_position = Vector3(rec.position.x, 0.2, rec.position.z)
		st.s = 1.0

# "pj": the first time the player comes within 2.5 of the middle of the room, a rustle and SCP-372 is made; the event is over.
func _ev_pj(rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var player: CharacterBody3D = c.player
	if Vector2(player.global_position.x - rec.position.x, player.global_position.z - rec.position.z).length() < 2.5:
		Sfx.play_global(self, "SFX/SCP/372/Rustle%d.ogg" % randi_range(0, 2))
		var shape := Node3D.new()
		shape.set_script(load("res://scripts/npc/scp_372.gd"))
		_world().add_child(shape)
		shape.global_position = Vector3(0.0, -50.0, 0.0)
		host._remove(c.key)


# "room3pitduck": in the room, a duck (`duck_low_res.b3d`, `duck1.png`, scale 0.07) stands at Objects[0] turned to the room's centre. While it
# is off screen a timer runs; past 300 a 1-in-200 roll per tick plays the Saxophone joke from the duck (range 6) and resets the timer.
# On screen the sound is stopped.
func _ev_room3pitduck(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var room: Node3D = c.room
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var duck: Node3D = host._valid(nodes.get("duck"))
	if duck == null:
		var spot: Vector3 = room.object_point(0)
		if spot == Vector3.INF:
			host._remove(c.key)
			return
		duck = _make_duck(room, true)
		duck.global_position = spot
		var toward := room.global_position - spot
		if Vector2(toward.x, toward.z).length() > 0.001:
			duck.global_rotation = Vector3(0.0, atan2(-toward.x, -toward.z), 0.0)
		nodes["duck"] = duck
		host._nodes[c.key] = nodes
		return
	var player: CharacterBody3D = c.player
	var voice: AudioStreamPlayer3D = host._valid(nodes.get("voice"))
	if player.camera.is_position_in_frustum(duck.global_position):
		if voice != null:
			voice.stop()
			voice.queue_free()
			nodes.erase("voice")
		return
	st.s += c.fps
	if randi_range(1, 200) == 1 and st.s > 300.0:
		st.s = 0.0
		if voice != null:
			voice.queue_free()
		var played := Sfx.play_at(duck, "SFX/SCP/Joke/Saxophone.ogg", 6.0)
		if played != null:
			nodes["voice"] = played

# "room2offices2": while in the room, each tick the blink timer is between -12 and -8 the duck (`duck_low_res.b3d`, own texture, scale 0.07)
# jumps to a random one of the pivots Objects[1..4] with a random yaw. It starts on one of them, unturned.
func _ev_room2offices2(_rec: Dictionary, _st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var room: Node3D = c.room
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var duck: Node3D = host._valid(nodes.get("duck"))
	var player: CharacterBody3D = c.player
	var spot: Vector3 = room.object_point(randi_range(1, 4))
	if spot == Vector3.INF:
		host._remove(c.key)
		return
	if duck == null:
		duck = _make_duck(room, false)
		duck.global_position = spot
		nodes["duck"] = duck
		host._nodes[c.key] = nodes
		return
	if player.blink_timer < -8.0 and player.blink_timer > -12.0:
		duck.global_position = spot
		duck.rotation.y = deg_to_rad(randf_range(0.0, 360.0))

func _make_duck(room: Node3D, painted: bool) -> Node3D:
	var duck := Node3D.new()
	room.add_child(duck)
	var model := B3DModel.new()
	model.load_file(ContentPaths.existing_file("GFX/npcs/duck_low_res.b3d"))
	model.scale = Vector3.ONE * 0.07
	duck.add_child(model)
	if painted:
		var picture := MeshLoader._load_texture(ContentPaths.existing_file("GFX/npcs/duck1.png"))
		var mesh: ArrayMesh = model.mesh_instance.mesh
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			var own: Material = material.duplicate() if (material is StandardMaterial3D or material is EntityMaterial) else MeshLoader.entity_material(picture, false)
			own.albedo_texture = picture
			model.mesh_instance.set_surface_override_material(i, own)
	return duck

# "room3pit1048": in the room, SCP-1048 (a paper bird, `scp-1048pp.b3d`, its sheet painted with one of the twenty drawings) stands at
# Objects[0] turned to the player. Seen within 3 m on screen (EventState 1, the achievement) it unfolds (frames 1-205) and then keeps
# moving (205-353); within 1.5 a click takes the drawing (the "Drawing" paper then shows that picture) and the event is over.
func _ev_room3pit1048(_rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var room: Node3D = c.room
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var pivot: Node3D = host._valid(nodes.get("pivot"))
	var spot: Vector3 = room.object_point(0)
	if spot == Vector3.INF:
		host._remove(c.key)
		return
	if not nodes.has("path"):
		nodes["path"] = "GFX/items/1048/1048_%d.jpg" % randi_range(1, 20)
		RoomFill.item_template("Drawing")["image"] = nodes["path"]
	if pivot == null:
		pivot = Node3D.new()
		room.add_child(pivot)
		var model := B3DModel.new()
		model.load_file(ContentPaths.existing_file("GFX/npcs/scp-1048pp.b3d"))
		model.scale = Vector3.ONE * 0.05
		model.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		pivot.add_child(model)
		pivot.global_position = spot
		var picture := MeshLoader._load_texture(ContentPaths.existing_file(str(nodes["path"])))
		var mesh: ArrayMesh = model.mesh_instance.mesh
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if (material is StandardMaterial3D or material is EntityMaterial) and material.albedo_texture == MeshLoader._white_tex():
				var own = material.duplicate()
				own.albedo_texture = picture
				model.mesh_instance.set_surface_override_material(i, own)
		nodes["pivot"] = pivot
		nodes["model"] = model
		nodes["frame"] = 414.0 if st.s == 0.0 else (1.0 if st.s == 1.0 else 205.0)
		model.set_frame(float(nodes["frame"]))
		host._nodes[c.key] = nodes
	var model_node: Node3D = nodes["model"]
	var player: CharacterBody3D = c.player
	var flat := Vector2(player.global_position.x - pivot.global_position.x, player.global_position.z - pivot.global_position.z)
	if flat.length() > 0.001:
		pivot.global_rotation = Vector3(0.0, atan2(-flat.x, -flat.y), 0.0)
	var dist: float = (player.global_position + Vector3(0.0, 0.3, 0.0)).distance_to(pivot.global_position)
	var frame: float = nodes["frame"]
	match int(st.s):
		0:
			if dist < 3.0 and player.camera.is_position_in_frustum(pivot.global_position + Vector3(0.0, 0.3, 0.0)):
				st.s = 1.0
				GameState.give_achievement("1048")
		1:
			frame = minf(frame + 0.5 * c.fps, 205.0)
			if frame == 205.0:
				st.s = 2.0
		2:
			frame += 1.0 * c.fps
			if frame >= 353.0:
				frame = 205.0
			if dist < 1.5:
				GameState.hand_icon = true
				if Input.is_action_just_pressed("interact"):
					var hud := _hud()
					var drawing := RoomFill.make_pickup("Drawing", "paper")
					_world().add_child(drawing)
					if hud.try_pickup(drawing):
						drawing.queue_free()
						pivot.queue_free()
						host._remove(c.key)
					else:
						drawing.queue_free()
	nodes["frame"] = frame
	model_node.set_frame(frame)

# "room2shaft": on the first frame a guard stands at the bottom of the shaft, Objects[1] (turned the way the room faces,
# a pose held at frame 286, State 8); the broken lift button is the room's own (broken_lift_buttons.gd).
func _ev_room2shaft(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if st.s != 0.0:
		return
	var spot: Vector3 = c.room.object_point(1)
	if spot == Vector3.INF:
		return
	var guard: Node3D = host.facility.spawn_human(HumanNpc.Kind.GUARD, Vector3(spot.x, spot.y + 0.1, spot.z))
	guard.rotation.y = deg_to_rad(float(rec.angle) + 180.0)
	guard.set_frame(286.0)
	guard.state = 8
	st.s = 1.0

# "checkpoint" (checkpoint1 and checkpoint2): the first time the player is in the room, a Rand(2) puts SCP-1048 (scp-1048.b3d, 0.05) at
# Objects[0] (checkpoint1 (720, 120, 333), checkpoint2 (-720, 120, 464)), lying at frame 267, turned to face the player (pitch -90,
# yawed at them every frame). Once the player looks within 40 degrees of it it waves (267 to 283 at 0.3, back at -0.2), and once the
# player looks more than 90 degrees away it is gone. EventState3 is `s3`: 0 not yet decided, 1 waiting, 2 waving, 3 lowering, 4 waiting
# to be looked away from, 5 done. (The ToZone sound of the same block is in checkpoint_monitors.gd.)
func _ev_checkpoint(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var room: Node3D = c.room
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = host._nodes.get(c.key, {})
	var model := host._valid(nodes.get("model")) as Node3D
	if st.s3 == 0.0:
		if randi_range(1, 2) == 1:
			GameState.give_achievement("1048")
			var spot := Vector3(720.0, 120.0, -333.0) if str(rec.name) == "checkpoint1" else Vector3(-720.0, 120.0, -464.0)
			model = B3DModel.new()
			model.load_file(ContentPaths.existing_file("GFX/npcs/scp-1048.b3d"))
			model.scale = Vector3.ONE * 0.05
			room.add_child(model)
			model.position = spot * RS
			model.set_frame(267.0)
			nodes["model"] = model
			nodes["frame"] = 267.0
			host._nodes[c.key] = nodes
		st.s3 = 1.0
		return
	if model == null or st.s3 >= 5.0:
		return
	var to_model := model.global_position - player.global_position
	var yaw := atan2(-(player.global_position.x - model.global_position.x), -(player.global_position.z - model.global_position.z))
	var looked_at := absf(angle_difference(player.rotation.y, atan2(-to_model.x, -to_model.z)))
	var frame: float = float(nodes.get("frame", 267.0))
	match int(st.s3):
		1:
			model.global_rotation = Vector3(deg_to_rad(90.0), yaw, 0.0)
			if looked_at < deg_to_rad(40.0):
				st.s3 = 2.0
		2:
			model.global_rotation = Vector3(deg_to_rad(90.0), yaw, 0.0)
			frame = host._animate_frame(frame, 267.0, 283.0, 0.3, c.fps, false)
			if frame >= 283.0:
				st.s3 = 3.0
		3:
			frame = host._animate_frame(frame, 267.0, 283.0, -0.2, c.fps, false)
			if frame <= 267.0:
				st.s3 = 4.0
		4:
			if looked_at > deg_to_rad(90.0):
				model.queue_free()
				nodes.erase("model")
				st.s3 = 5.0
				return
	nodes["frame"] = frame
	model.set_frame(frame)

# "testroom": on entry SCP-1048 (scp-1048.b3d) is put at the side of the room opposite the player, 720 to one side, and crawls across
# (frames 284-295, 0.008 a frame along its own y) until it is past |x| 725. Within 2.5 of Objects[6] a warning sounds once and the six
# pipes (Objects[0..5], which the FillRoom loop makes and the extractor misses) start to hiss. The event goes when both have happened.
func _ev_testroom(rec: Dictionary, st: Dictionary, c: Dictionary) -> void:
	if not c.in_room:
		return
	var room: Node3D = c.room
	var player: CharacterBody3D = c.player
	var nodes: Dictionary = host._nodes.get(c.key, {})
	if st.s == 0.0:
		var side := room.to_local(player.global_position).z
		var temp := -1.0 if side == 0.0 else signf(side)
		var model := B3DModel.new()
		model.load_file(ContentPaths.existing_file("GFX/npcs/scp-1048.b3d"))
		model.scale = Vector3.ONE * 0.05
		room.add_child(model)
		model.position = Vector3(-720.0 * RS, 0.0, -816.0 * temp * RS)
		model.rotation = Vector3(deg_to_rad(90.0), deg_to_rad(-90.0), 0.0)
		model.set_frame(297.0)
		nodes["model"] = model
		nodes["frame"] = 297.0
		host._nodes[c.key] = nodes
		st.s = 1.0
	var spot: Vector3 = room.object_point(6)
	if st.s > 0.0 and spot != Vector3.INF and player.global_position.distance_to(spot) < 2.5:
		Sfx.play_global(host, "SFX/SCP/079/TestroomWarning.ogg")
		for xt in 2:
			for zt in range(-1, 2):
				var at: Vector3 = room.to_global(Vector3((-236.0 + 280.0 * xt) * RS, -700.0 * RS, -384.0 * zt * RS))
				host.facility.particles.add_emitter(at, Vector3.DOWN, room, c.key, {"rand_angle": 5.0, "speed": 0.042, "size_change": 0.0025})
		st.s = -st.s
	var model := host._valid(nodes.get("model")) as Node3D
	if model != null:
		var frame: float = host._animate_frame(float(nodes.get("frame", 297.0)), 284.0, 295.0, 0.3, c.fps)
		nodes["frame"] = frame
		model.set_frame(frame)
		model.position += model.basis.orthonormalized() * Vector3(0.0, -0.008 * c.fps, 0.0)
		if absf(model.position.x) > 725.0 * RS:
			model.queue_free()
			nodes.erase("model")
			st.s *= 2.0
	if st.s == -2.0:
		host._remove(c.key)
