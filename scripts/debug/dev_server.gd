extends Node
# Dev control channel (SCP_DEV=1): a localhost TCP server speaking JSON lines, one request per line, one reply per line.
#   {"cmd":"state"}                     player, room, event state, NPCs
#   {"cmd":"console","line":"tp room2"} any developer-console command (debug_commands.gd)
#   {"cmd":"teleport","room":"room2"}   or {"cmd":"teleport","x":..,"y":..,"z":..} in Blitz coordinates
#   {"cmd":"advance","seconds":2.5}     lets game time pass, then replies
#   {"cmd":"input","action":"move_forward","seconds":1.0}
#   {"cmd":"look","yaw":90,"pitch":0}   yaw in Blitz degrees; pitch up is positive
#   {"cmd":"place","x":..,"y":..,"z":..,"yaw":..,"pitch":..}  the numbers the original console's `status` prints (collider position, camera rotation)
#   {"cmd":"shot","path":"C:/x.png"}    needs a window (SCP_SHOT=1)
#   {"cmd":"trace","on":true,"path":"C:/t.jsonl","interval":0.5}
#   {"cmd":"event","room":"room2test1074"}  the ambient event state {s, s2, s3} of a room key
#   {"cmd":"unlit","on":true}           the debug menu's "Disable lighting" (F4): every material unlit, for screenshots of dark places;
#                                       "fog":false also lifts the depth fog (the pocket dimension's is black from 0.5 to 6)
#   {"cmd":"window","w":1920,"h":1080,"borderless":true}   applies a resolution like the launcher; "pw","ph" force the
#                                       window's own size (what borderless fullscreen does to a smaller resolution)
#   {"cmd":"mouse","x":..,"y":..,"button":"press"}   warps the cursor (window pixels), optionally presses or releases the
#                                       left button there; "fill":true picks up the items within 3, "open":true opens the inventory
#   {"cmd":"pocket"}                    sends the player into the pocket dimension (what 106 does); then teleport to leave it
#   {"cmd":"rooms"}                     the generated map
#   {"cmd":"sounds","on":true}          start (and clear) the sound log; {"cmd":"sounds"} returns it, "on":false also stops it.
#                                       Each entry: t (s since on), sound (asset path), at (Blitz coords, null if unpositioned), dist
#   {"cmd":"quit"}
# Coordinates in replies are Blitz ones (z flipped), as the console's `status` prints them.

const NPC_GROUPS := ["scp049", "scp0492", "scp066", "scp096", "scp106", "scp1499", "scp372", "scp513_1", "scp860", "scp939", "scp966",
	"scp008z", "mtf", "human_npc", "apache", "tentacle", "scp1123_officer", "scp035_host"]

var main: Node
var port := 7777
var _server := TCPServer.new()
var _clients: Array = []
var _busy := false
var _trace_file: FileAccess
var _trace_interval := 0.5
var _trace_clock := 0.0
var _trace_time := 0.0
var _sound_log: Array = []
var _sound_on := false
var _sound_clock := 0.0
var _sound_time := 0.0
var _sound_seen: Dictionary = {}      # player instance id -> [stream, playback position] at the last look

func start(main_node: Node) -> void:
	main = main_node
	process_mode = Node.PROCESS_MODE_ALWAYS     # keeps answering while the inventory or the pause menu pauses the tree
	var wanted := OS.get_environment("SCP_DEV_PORT")
	if wanted.is_valid_int():
		port = int(wanted)
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("dev server cannot listen on %d (error %d)" % [port, err])
		get_tree().quit(3)
		return
	print("DEV listening 127.0.0.1:", port)

func _process(delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_clients.append({"peer": peer, "buffer": ""})
	for client in _clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			client.buffer += peer.get_utf8_string(available)
		if _busy:
			continue
		var newline: int = client.buffer.find("\n")
		if newline >= 0:
			var line: String = client.buffer.substr(0, newline)
			client.buffer = client.buffer.substr(newline + 1)
			_serve(client, line)
	_trace_time += delta
	if _sound_on:
		_sample_sounds(delta)
	if _trace_file != null:
		_trace_clock += delta
		if _trace_clock >= _trace_interval:
			_trace_clock = 0.0
			_trace_file.store_line(JSON.stringify(_state()))
			_trace_file.flush()

func _serve(client: Dictionary, line: String) -> void:
	_busy = true
	var reply := await _handle(line)
	_busy = false
	var peer: StreamPeerTCP = client.peer
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())

func _handle(line: String) -> Dictionary:
	var request = JSON.parse_string(line)
	if typeof(request) != TYPE_DICTIONARY:
		return {"ok": false, "error": "not a JSON object"}
	var cmd := str(request.get("cmd", ""))
	if cmd != "quit" and cmd != "ping" and GameState.player == null:
		return {"ok": false, "error": "no game running"}
	match cmd:
		"ping":
			return {"ok": true}
		"state":
			return {"ok": true, "state": _state()}
		"console":
			return {"ok": true, "output": _console(str(request.get("line", "")))}
		"teleport":
			if request.has("room"):
				return {"ok": true, "output": _console("teleport " + str(request.room))}
			return {"ok": true, "output": _console("tele %s %s %s" % [request.get("x", 0), request.get("y", 0), request.get("z", 0)])}
		"advance":
			await get_tree().create_timer(float(request.get("seconds", 1.0))).timeout
			return {"ok": true, "state": _state()}
		"input":
			var action := str(request.get("action", ""))
			if not InputMap.has_action(action):
				return {"ok": false, "error": "unknown action " + action}
			Input.action_press(action)
			await get_tree().create_timer(float(request.get("seconds", 0.2))).timeout
			Input.action_release(action)
			return {"ok": true, "state": _state()}
		"look":
			return _look(request)
		"place":
			var at: Vector3 = GameState.player.global_position
			var target := Vector3(float(request.get("x", at.x)), float(request.get("y", at.y)), -float(request.get("z", -at.z)))
			GameState.player.global_position = target
			GameState.player.velocity = Vector3.ZERO
			main.facility.after_teleport()
			await get_tree().physics_frame
			return _look(request)
		"shot":
			return await _shot(str(request.get("path", "")))
		"trace":
			return _trace(request)
		"event":
			var ambient = _facility().ambient
			return {"ok": true, "state": ambient.state_of(str(request.get("room", ""))) if ambient else {}}
		"window":
			return await _window(request)
		"mouse":
			return await _mouse(request)
		"pocket":
			_facility().enter_pocket(GameState.player)
			return {"ok": true}
		"unlit":
			for node in get_tree().get_nodes_in_group("debug_overlay"):
				node._set_unlit(bool(request.get("on", true)))
			if request.get("fog", true) == false:
				_no_fog()
			return {"ok": true}
		"rooms":
			return {"ok": true, "rooms": _rooms()}
		"sounds":
			if request.has("on"):
				_sound_on = bool(request.on)
				if _sound_on:
					_sample_sounds(0.0, true)      # what already plays is not new
					_sound_log = []
					_sound_time = 0.0
			return {"ok": true, "on": _sound_on, "sounds": _sound_log}
		"quit":
			get_tree().quit()
			return {"ok": true}
	return {"ok": false, "error": "unknown cmd " + cmd}

# Every 0.1 s: the players that started a stream since the last look (new, switched to another stream, or played again from
# an earlier position).
func _sample_sounds(delta: float, now := false) -> void:
	_sound_time += delta
	_sound_clock += delta
	if _sound_clock < 0.1 and not now:
		return
	_sound_clock = 0.0
	var listener: Vector3 = GameState.player.global_position
	var seen: Dictionary = {}
	for node in get_tree().root.find_children("*", "", true, false):
		if not (node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D) or not node.playing or node.stream == null:
			continue
		var id: int = node.get_instance_id()
		var sound: String = node.stream.resource_name if not node.stream.resource_name.is_empty() else node.stream.resource_path
		if sound.is_empty():
			sound = "node:" + str(node.name)      # a stream not read through Sfx.stream
		var at: float = node.get_playback_position()
		seen[id] = [sound, at]
		var before: Array = _sound_seen.get(id, [])
		if not before.is_empty() and before[0] == sound and at >= float(before[1]):
			continue
		var entry := {"t": snappedf(_sound_time, 0.01), "sound": sound, "at": null, "dist": null}
		if node is Node3D:
			var p: Vector3 = (node as Node3D).global_position
			entry.at = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(-p.z, 0.01)]
			entry.dist = snappedf(p.distance_to(listener), 0.01)
		_sound_log.append(entry)
	_sound_seen = seen

# Lifts the depth fog (the environment's and the room shader's) until something sets it again, e.g. the pocket dimension's 0.5-6 black.
func _no_fog() -> void:
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if holder != null:
		holder.environment.fog_enabled = false
	RenderingServer.global_shader_parameter_set(&"room_fog_range", Vector2(100000.0, 200000.0))

func _window(request: Dictionary) -> Dictionary:
	GameState.graphic_width = int(request.get("w", GameState.graphic_width))
	GameState.graphic_height = int(request.get("h", GameState.graphic_height))
	GameState.borderless_windowed = bool(request.get("borderless", false))
	GameState.fullscreen = bool(request.get("fullscreen", false))
	var window := get_window()
	WindowSetup.apply_game(window)
	if request.has("pw"):
		window.size = Vector2i(int(request.pw), int(request.ph))
	for i in 20:
		await get_tree().process_frame
	return {"ok": true, "size": str(window.size), "position": str(window.position), "canvas": str(window.get_visible_rect().size), "mode": window.mode}

func _mouse(request: Dictionary) -> Dictionary:
	var hud: Node = main.hud
	if bool(request.get("fill", false)):
		for node in get_tree().get_nodes_in_group("pickup"):
			if node.global_position.distance_to(GameState.player.global_position) < 3.0:
				hud.try_pickup(node)
	if bool(request.get("open", false)):
		hud.open_inventory()
	var at := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
	Input.warp_mouse(at)
	if request.has("button"):
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = request.button == "press"
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
	for i in 5:
		await get_tree().process_frame
	var inventory: Control = hud._inventory
	return {"ok": true, "viewport_mouse": str(get_viewport().get_mouse_position()), "inventory_hover": inventory.hover_slot() if inventory.visible else -1}

func _look(request: Dictionary) -> Dictionary:
	var player: CharacterBody3D = GameState.player
	if request.has("yaw"):
		player.rotation.y = deg_to_rad(float(request.yaw))
	if request.has("pitch"):
		player.user_pitch = float(request.pitch)
		player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	return {"ok": true, "yaw": snappedf(rad_to_deg(player.rotation.y), 0.01), "pitch": snappedf(player.user_pitch, 0.01)}

func _facility() -> FacilityMap:
	return get_tree().get_first_node_in_group("facility") as FacilityMap

func _console(line: String) -> Array:
	var commands := DebugCommands.new(self)
	var texts: Array = []
	for entry in commands.run(line):
		texts.append(str(entry[0]))
	return texts

func _blitz(pos: Vector3) -> Array:
	return [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(-pos.z, 0.001)]

func _state() -> Dictionary:
	var player: CharacterBody3D = GameState.player
	var facility := _facility()
	var state := {
		"t": snappedf(_trace_time, 0.001),
		"player": {"pos": _blitz(player.global_position), "yaw": snappedf(rad_to_deg(player.rotation.y), 0.01),
			"pitch": snappedf(player.user_pitch, 0.01), "stamina": snappedf(player.stamina, 0.01),
			"blink": snappedf(player.blink_timer, 0.01), "dead": player.dead},
		"injuries": snappedf(GameState.injuries, 0.001),
		"bloodloss": snappedf(GameState.bloodloss, 0.001),
	}
	if facility != null:
		state["room"] = facility.room_name_at(player.global_position)
		state["facility_active"] = facility.active
		var ambient = facility.ambient
		var key := ""
		var record: Dictionary = facility.record_at(player.global_position)
		if not record.is_empty():
			state["grid"] = [record.grid.x, record.grid.y]
			key = "%d,%d" % [record.grid.x, record.grid.y]
		if ambient != null and key != "" and ambient.states.has(key):
			state["event"] = ambient.states[key]
	var npcs: Array = []
	var statue: Node3D = GameState.scp173
	if statue != null:
		npcs.append(_npc("scp173", statue))
	for group in NPC_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				npcs.append(_npc(group, node))
	state["npcs"] = npcs
	return state

func _npc(kind: String, node: Node3D) -> Dictionary:
	var info := {"kind": kind, "pos": _blitz(node.global_position), "visible": node.visible}
	for property in ["state", "npc_state", "mode", "hp", "health"]:
		if property in node:
			info[property] = node.get(property)
	return info

func _rooms() -> Array:
	var rooms: Array = []
	var facility := _facility()
	if facility == null or facility.generator == null:
		return rooms
	for record in facility.generator.rooms:
		rooms.append({"name": str(record.name), "pos": _blitz(record.position), "grid": [record.grid.x, record.grid.y],
			"angle": record.get("angle", 0)})
	return rooms

func _shot(path: String) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "headless has no rendering; start the instance with a window (SCP_SHOT=1)"}
	if path.is_empty():
		return {"ok": false, "error": "path required"}
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(path)
	return {"ok": err == OK, "path": path}

func _trace(request: Dictionary) -> Dictionary:
	if _trace_file != null:
		_trace_file.close()
		_trace_file = null
	if bool(request.get("on", true)):
		var path := str(request.get("path", ""))
		if path.is_empty():
			return {"ok": false, "error": "path required"}
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_trace_file = FileAccess.open(path, FileAccess.WRITE)
		_trace_interval = float(request.get("interval", 0.5))
		_trace_clock = 0.0
		return {"ok": _trace_file != null}
	return {"ok": true}
