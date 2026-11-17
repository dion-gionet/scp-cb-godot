extends Node
# The room2sl event (UpdateEvents.bb Case "room2sl"): SCP-049 waits in a cell below the checkpoint. Once the
# player has looked at the room's monitor for a moment (and 5 s more have passed) he is put outside the hall
# door, walks to the catwalk and "opens" the doors with SCP-079's help, goes through three stops with his
# lines (Room2SL1, Room2SL2), and if he hears or sees the player the hunt begins; if he finds no one he walks
# off to a room 15-30 units away and goes idle for a minute.
#
# EventState2: -350 waiting for the monitor, then counts up to 0; 1 find the route to the catwalk;
# 2 walk it (the doors open when he is within 5); 3 the three stops (State3 1..5); 4 heard the player;
# 5 pick a far room; 6 walk there; 7 over.
#
# The sequence has no PlayerRoom guard (UE 8127+): it goes on wherever the player is. The first 12 frames after the player enters
# are the original's quick load of the event: the countdown cannot begin before it is over.
#
# Not ported: the checkpoint lever and its monitors (Levers[0], the room's two monitor sprites), the 049 chase music
# played while he walks (ShouldPlay 20), fast door speed.


var room: Node3D
var npc: CharacterBody3D
var event_state := 0.0
var event_state2 := 0.0:     # kept in events.sl.scene_state2 for a save
	set(value):
		event_state2 = value
		var facility := get_parent() as FacilityMap
		if facility != null:
			facility.events.sl.scene_state2 = value
var door_hall: Node3D       # RoomDoors[0]: the door at the hall level, keycard 3
var door_cell: Node3D       # RoomDoors[1]: the door above, keycard 3
var points := {}            # Objects[7], [15], [16], [17] in world space
var log: Array[int] = []    # EventState2 values it went through (tests)
var voices: Array[String] = []

var _reload := 0.0          # NPC[0]\Reload: the "079 opens the doors" sound has played
var _voice_end_ms := 0.0
var _voice_playing := false
var _cam: Node3D
var _delay := 12.0          # QuickLoad: the event's models load over about a dozen frames

func begin(room_node: Node3D) -> void:
	room = room_node
	var facility := get_parent() as FacilityMap
	door_hall = room.door_slots.get(0)
	door_cell = room.door_slots.get(1)
	for index in [7, 15, 16, 17]:
		points[index] = room.object_point(index)
	if not room.cams.is_empty():
		_cam = room.cams[0]
	var saved_state2: float = facility.events.sl.scene_state2
	event_state = 1.0
	event_state2 = -70.0 * 5.0
	if facility.scp049 != null and is_instance_valid(facility.scp049):
		# a loaded game: QuickLoadEvents keeps the NPC[0] the save linked back, and the countdown carries on unless it
		# never began (load3: If EventState2 = 0 Then EventState2 = -(70*5))
		npc = facility.scp049
		if saved_state2 < 0.0:
			event_state2 = saved_state2
	else:
		npc = facility.spawn_049(0.0)
		npc.state = 0
		npc.rotation.y = room.rotation.y + PI
		var spot: Vector3 = points[7]
		npc.global_position = spot + Vector3(0.0, 5.0, 0.0)    # CreateNPC(... Objects[7] Y + 5): up in the ceiling space, out of sight until he is released
	npc.prev_state = 2
	npc.velocity = Vector3.ZERO
	npc._follower.open_reach = 0.6     # he opens a door when he is within 0.6 of the next waypoint
	log.append(int(event_state2))

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	if player == null:
		return
	if npc == null or not is_instance_valid(npc):
		_finish()
		return
	var fps := delta * 70.0
	if _delay > 0.0:
		_delay -= fps
		return
	_run(fps, player)
	_hall_door(player)

# 049 is gone: whatever he was doing, the scene is over.
func _finish() -> void:
	if npc != null and is_instance_valid(npc):
		npc._follower.open_reach = 1.6
	queue_free()

func _set_state2(value: float) -> void:
	if int(value) != int(event_state2):
		log.append(int(value))
	event_state2 = value

func _run(fps: float, player: CharacterBody3D) -> void:
	if event_state2 < 0.0:
		if event_state2 == -70.0 * 5.0:
			# the countdown only starts when the player is near the monitor and can see it
			if _cam != null and is_instance_valid(_cam) and _cam.screen_near_and_visible(player.camera.global_position, 5.0):
				event_state2 = minf(event_state2 + fps, 0.0)
		else:
			event_state2 = minf(event_state2 + fps, 0.0)
		return
	if event_state2 == 0.0:
		_step_out()
	elif event_state2 == 1.0:
		if not npc.walking():
			npc.route_to(points[15])
		else:
			_set_state2(2.0)
	elif event_state2 == 2.0:
		_walk_to_catwalk()
	elif event_state2 == 3.0:
		_stops(fps, player)
	elif event_state2 == 4.0:
		if npc.state != 5:
			_set_state2(7.0)
			npc.state3 = 6.0
	elif event_state2 == 5.0:
		_pick_far_room(player)
	elif event_state2 == 6.0:
		_walk_away(player)

# 049 appears in front of the hall door farther from the cell (one unit outside it), standing, state 5.
func _step_out() -> void:
	var doors: Array[Node3D] = get_parent().room_edge_doors(room)
	if doors.is_empty():
		return
	var cell: Vector3 = points[7]
	var farthest: Node3D = doors[0]
	for door in doors:
		if door.global_position.distance_to(cell) > farthest.global_position.distance_to(cell):
			farthest = door
	var outside := Vector3(farthest.global_position.x, cell.y, farthest.global_position.z)
	var toward := room.global_position - outside
	toward.y = 0.0
	npc.global_position = outside - toward.normalized() * 1.0 + Vector3(0.0, 0.1, 0.0)    # PointEntity room, MoveEntity 0, 0, -1
	npc.rotation.y = atan2(-toward.x, -toward.z)
	npc.velocity = Vector3.ZERO
	npc.path_spot = npc.global_position
	npc.state = 5
	_set_state2(1.0)

func _walk_to_catwalk() -> void:
	if not npc.walking():
		_lock_and_open_doors()    # a hop can skip the approach: by the time he is on the catwalk the doors are 079's
		npc.state3 = 1.0
		_set_state2(3.0)
		npc.path_timer = 0.0
	else:
		if door_hall != null and is_instance_valid(door_hall) and npc.global_position.distance_to(door_hall.global_position) < 5.0:
			_lock_and_open_doors()

	if npc.state != 5:
		_set_state2(7.0)

# The three stops of the walk, each with its pose and line; State3 counts them.
func _stops(fps: float, player: CharacterBody3D) -> void:
	if npc.state != 5:
		_set_state2(7.0)
		return
	if npc._sees_player(player) == 2:
		_set_state2(4.0)
		return
	if npc.walking():
		return
	if npc.path_timer == 0.0:
		if npc.prev_state == 1:
			if not _voice_playing:
				_say("SFX/SCP/049/Room2SL1.ogg")
			elif _voice_over():
				npc.path_timer = 1.0
				_voice_playing = false
		elif npc.prev_state == 2:
			if npc.state3 == 3.0:
				if not _voice_playing:
					_say("SFX/SCP/049/Room2SL2.ogg")
				elif _voice_over():
					npc.path_timer = 1.0
					_voice_playing = false
			elif npc.frame() >= 1118.0:
				npc.path_timer = 1.0
	else:
		match int(npc.state3):
			1:
				npc.route_to(points[16])
				npc.prev_state = 1
			2:
				npc.route_to(points[15])
				npc.prev_state = 2
			3:
				npc.route_to(points[17])
				npc.prev_state = 2
			4:
				npc.route_to(npc.path_spot)
				npc.prev_state = 2
			5:
				_set_state2(5.0)
		npc.path_timer = 0.0
		npc.state3 += 1.0

func _say(relative: String) -> void:
	var source := Sfx.stream(relative)
	voices.append(relative)
	_voice_playing = true
	_voice_end_ms = GameState.clock_ms() + (source.get_length() * 1000.0 if source != null else 0.0)
	npc.say(relative)

func _voice_over() -> bool:
	return GameState.clock_ms() >= _voice_end_ms

# He gives up the post: ordinary hunting, and a route to a room 15-30 units away (out of the player's room).
func _pick_far_room(player: CharacterBody3D) -> void:
	npc.state = 2
	var facility := get_parent() as FacilityMap
	var here: Dictionary = facility.drawing.drawn_from
	for record in facility.generator.rooms:
		if record.get("grid", Vector2i.ZERO) == here.get("grid", Vector2i(-99, -99)):
			continue
		var away: float = record.position.distance_to(npc.global_position)
		if away > 15.0 and away < 30.0:
			var status: int = npc.route_to(Vector3(record.position.x, npc.global_position.y, record.position.z))
			npc.path_timer = 0.0
			if status == 1:
				_set_state2(6.0)
			break

func _walk_away(player: CharacterBody3D) -> void:
	if npc._sees_player(player) != 0 or npc.state2 > 0.0:
		_set_state2(7.0)
		return
	if not npc.walking():
		npc.idle = 70.0 * 60.0      # idle for a minute (twice as fast on Keter)
		_set_state2(7.0)

# The hall door: shut while he is on the other level and the player is at the hall level, open again
# when he is level with it; once the scene is over it stays open.
func _hall_door(player: CharacterBody3D) -> void:
	if door_hall == null or not is_instance_valid(door_hall):
		return
	if event_state2 < 7.0:
		if event_state2 > 2.0:
			if absf(door_hall.global_position.y - npc.global_position.y) > 1.0:
				if absf(door_hall.global_position.y - player.global_position.y) < 1.0 and door_hall.open:
					door_hall.toggle(false)
					Sfx.play_global(self, "SFX/Door/DoorClose079.ogg")
			elif not door_hall.open:
				door_hall.toggle()
				Sfx.play_global(self, "SFX/Door/DoorOpen079.ogg")
	elif not door_hall.open:
		door_hall.toggle()
		Sfx.play_global(self, "SFX/Door/DoorOpen079.ogg")

# SCP-079 locks both doors and opens them, once ("079 - OPEN DOORS IN ROOM2SL").
func _lock_and_open_doors() -> void:
	if door_hall == null or door_cell == null or not is_instance_valid(door_hall) or not is_instance_valid(door_cell):
		return
	door_hall.locked = true
	door_cell.locked = true
	if _reload == 0.0:
		Sfx.play_global(self, "SFX/Door/DoorOpen079.ogg")
		_reload = 1.0
	if not door_hall.open:
		door_hall.toggle()
	if not door_cell.open:
		door_cell.toggle()
