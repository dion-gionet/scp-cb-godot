extends RefCounted
class_name DebugCommands
# The developer console's commands (Main.bb UpdateConsole, NPCs.bb Console_SpawnNPC). `run(line)` returns the lines to print as
# [text, Color]; both the console (debug_console.gd) and the debug menu (debug_overlay.gd) go through it, so every menu button is a
# console command. Coordinates are Blitz ones (z flipped), as the original's `status` and `tele` use them.


const WHITE := Color(1, 1, 1)
const CYAN := Color(0, 1, 1)
const GREEN := Color(0, 1, 0)
const ORANGE := Color8(255, 150, 0)
const RED := Color(1, 0, 0)

var host: Node            # any node in the tree
var out: Array = []

# The commands in the order of the help pages.
const PAGES := [
	["asd", "status", "camerapick", "ending [code]", "noclipspeed [value]", "noclip [on/off]", "injure [value]", "infect [value]", "heal",
		"teleport [room name]", "tp", "tele [x] [y] [z]", "spawnitem [item name]", "wireframe [on/off]", "173speed [value]", "106speed [value]",
		"173state", "106state", "096state"],
	["spawn [npc type] [state]", "hold372 [on/off]", "reset096", "disable173", "enable173", "disable106", "enable106", "teleport173", "teleport106",
		"halloween", "sanic", "scp-420-j", "godmode [on/off]", "revive", "kill", "showfps", "debughud [on/off]", "camerafog [near] [far]",
		"gamma [value]", "infinitestamina [on/off]", "asd2", "notarget [on/off]"],
	["playmusic [clip + .wav/.ogg]", "stopsound", "unlockexits [a/b]", "toggle_warhead_lever", "spawnradio", "spawnnvg", "spawnnav",
		"seteventstate [state] [state2] [state3]", "giveachievement [id]", "427state [seconds]", "setblinkeffect [effect] [seconds]",
		"hidedistance [value]", "culling [on/off]", "spawnparticles [id]", "help [page / command]"],
]

const HELP := {
	"asd": ["Activates godmode, noclip, wireframe and", "sets fog distance to 15 near, 20 far"],
	"asd2": ["Activates godmode and infinite stamina and", "turns SCP-173 and SCP-106 off."],
	"camerafog": ["Sets the draw distance of the fog.", "The fog begins generating at 'near' units", "away from the camera and becomes completely opaque", "at 'far' units away from the camera.", "Example: camerafog 20 40"],
	"gamma": ["Sets the gamma correction.", "Should be set to a value between 0.0 and 2.0.", "Default is 1.0."],
	"noclip": ["Toggles noclip, unless a valid parameter", "is specified (on/off).", "Allows the camera to move in any direction while", "bypassing collision."],
	"godmode": ["Toggles godmode, unless a valid parameter", "is specified (on/off).", "Prevents player death under normal circumstances."],
	"wireframe": ["Toggles wireframe, unless a valid parameter", "is specified (on/off).", "Allows only the edges of geometry to be rendered,", "making everything else transparent."],
	"spawnitem": ["Spawns an item at the player's location.", "Any name that can appear in your inventory", "is a valid parameter.", "Example: spawnitem Key Card Omni"],
	"spawn": ["Spawns an NPC at the player's location.", "Valid parameters are:", "008zombie / 049 / 049-2 / 096 / 106 / 173 / 966 / 1499-1", "/ class-d / guard / mtf / apache", "/ 372 / 513-1 / tentacle / clerk"],
	"hold372": ["Debug only: keeps an SCP-372 awake 1.5 m ahead and a little to the left, at the edge of the view.", "Makes one if none exists; `hold372 off` lets it go."],
	"revive": ["Resets the player's death state after the dying", "animation triggers.", "Does not affect injury, blood loss", "or 008 infection values."],
	"teleport": ["Teleports the player to the first instance", "of the specified room. Any room that appears", "in rooms.ini is a valid parameter."],
	"tele": ["Teleports the player to the coordinates x y z", "(the ones status prints)."],
	"tp": ["Teleports the player 5 above the leader of the MTF."],
	"stopsound": ["Stops all currently playing sounds."],
	"camerapick": ["Prints the texture name and coordinates of", "the model the camera is pointing at."],
	"status": ["Prints player, camera, and room information."],
	"scp-420-j": ["Generates dank memes."],
	"playmusic": ["Will play tracks in .ogg format", "from \"SFX\\Music\\Custom\\\".", "With no name it goes back to the facility's music."],
	"infinitestamina": ["Toggles infinite stamina, unless a valid parameter", "is specified (on/off)."],
	"notarget": ["Toggles notarget, unless a valid parameter", "is specified (on/off).", "NPCs ignore the player."],
	"unlockexits": ["Unlocks the exit gates (a, b or both)."],
	"seteventstate": ["Sets the event states (use keep to leave one)", "of the event of the room the player is in.", "Example: seteventstate 1 keep 0"],
	"kill": ["Kills the player with a made-up report."],
	"ending": ["Starts an ending: a1, a2, b1, b2 or b3."],
	"hidedistance": ["HideDistance is fixed at 15 here: it weighs the room", "lights, the doors, the items and the NPC gravity as in", "the original. This only reports it."],
	"culling": ["Toggles the hiding of rooms that cannot be seen,", "unless a valid parameter is specified (on/off).", "On (the original's UpdateRooms): only the room you are in,", "its neighbours and theirs are drawn, and of those only", "your own room's walls and floor, a neighbour's while the", "door between is open and in view.", "Noclip switches it off while it is on."],
}

const SPAWN_ALIASES := {
	"008": "008", "008zombie": "008", "049": "049", "scp049": "049", "scp-049": "049",
	"049-2": "049-2", "0492": "049-2", "scp-049-2": "049-2", "scp049-2": "049-2", "049zombie": "049-2",
	"066": "066", "scp066": "066", "scp-066": "066",
	"096": "096", "scp096": "096", "scp-096": "096",
	"106": "106", "scp106": "106", "scp-106": "106", "larry": "106",
	"173": "173", "scp173": "173", "scp-173": "173", "statue": "173",
	"372": "372", "scp372": "372", "scp-372": "372",
	"513-1": "513-1", "5131": "513-1", "scp513-1": "513-1", "scp-513-1": "513-1",
	"860-2": "860-2", "8602": "860-2", "scp860-2": "860-2", "scp-860-2": "860-2",
	"939": "939", "scp939": "939", "scp-939": "939",
	"966": "966", "scp966": "966", "scp-966": "966",
	"1048-a": "1048-a", "scp1048-a": "1048-a", "scp-1048-a": "1048-a", "scp1048a": "1048-a", "scp-1048a": "1048-a",
	"1499-1": "1499-1", "14991": "1499-1", "scp-1499-1": "1499-1", "scp1499-1": "1499-1",
	"class-d": "class-d", "classd": "class-d", "d": "class-d",
	"guard": "guard", "mtf": "mtf", "apache": "apache", "helicopter": "apache", "tentacle": "tentacle", "clerk": "clerk",
}

# Events whose states the port keeps: room -> the three facility variables (EventState, EventState2, EventState3).
const EVENT_VARS := {
	"room049": ["events:room049:state"], "room966": ["events:room966:state"], "room860": ["events:room860:state", "events:room860:state2", "events:room860:state3"],
	"coffin": ["events:coffin:lever_pitch", "events:coffin:event_state2", "events:coffin:guard_state"], "room079": ["events:room079:state", "events:room079:state2"],
	"gatea": ["events:gatea:state", "events:gatea:state2", "events:gatea:state3"], "exit1": ["events:exit1:state", "events:exit1:state2", "events:exit1:state3"],
	"room2servers": ["events:servers:state", "events:servers:state2", "events:servers:state3"], "room106": ["events:femur:state"],
	"room2ccont": ["ccont_state"],
}

func _init(node: Node = null) -> void:
	host = node

func _say(text: String, color: Color = WHITE) -> void:
	out.append([text, color])

func _facility() -> FacilityMap:
	return host.get_tree().get_first_node_in_group("facility") as FacilityMap

func _hud() -> Node:
	return host.get_tree().get_first_node_in_group("hud")

func _player() -> CharacterBody3D:
	return GameState.player

func _toggle(current: bool, arg: String) -> bool:
	match arg:
		"on", "1", "true":
			return true
		"off", "0", "false":
			return false
	return not current

func _pieces(arg: String) -> PackedStringArray:
	var parts := PackedStringArray()
	for piece in arg.split(" ", false):
		parts.append(piece)
	return parts

func _blitz(pos: Vector3) -> String:
	return "%s, %s, %s" % [_num(pos.x), _num(pos.y), _num(-pos.z)]

func _num(value: float) -> String:
	return str(snappedf(value, 0.0001))

func _world_parent() -> Node:
	return _player().get_parent()

func run(line: String) -> Array:
	out = []
	var text := line.strip_edges()
	if text.is_empty():
		return out
	var space := text.find(" ")
	var command := (text.substr(0, space) if space > 0 else text).to_lower()
	var arg := text.substr(space + 1).strip_edges().to_lower() if space > 0 else ""
	var raw_arg := text.substr(space + 1).strip_edges() if space > 0 else ""
	if _player() == null and command != "help":
		_say("There is no game running.", RED)
		return out
	match command:
		"help":
			_help(arg)
		"asd":
			_set_wireframe(true)
			GameState.god_mode = true
			GameState.noclip = true
			GameState.fog_override = Vector4(15.0, 20.0, 0.0, 0.0)
		"asd2":
			GameState.god_mode = true
			GameState.infinite_stamina = true
			_disable_173()
			_disable_106()
		"status":
			_status()
		"camerapick":
			_camera_pick()
		"hidedistance":
			_say("Hidedistance stays at 15 (asked for %s); the guards that use it have it built in." % str(float(arg)))
		"culling", "roomculling":
			var facility := _facility()
			facility.drawing.enabled = _toggle(facility.drawing.enabled, arg)
			_say("CULLING ON" if facility.drawing.enabled else "CULLING OFF")
			if facility.drawing.enabled and GameState.noclip:
				_say("(it stands aside while noclip is on)")
		"ending":
			_ending(arg)
		"noclipspeed":
			GameState.noclip_speed = float(arg)
		"injure":
			GameState.injuries = float(arg)
		"infect":
			GameState.infect = float(arg)
		"heal":
			GameState.injuries = 0.0
			GameState.bloodloss = 0.0
		"teleport":
			_teleport(arg)
		"tp":
			_tp_leader()
		"tele":
			_tele(arg)
		"spawnitem":
			_spawn_item(arg)
		"wireframe":
			_set_wireframe(_toggle(GameState.wireframe, arg))
			_say("WIREFRAME ON" if GameState.wireframe else "WIREFRAME OFF")
		"173speed":
			var statue: Node = GameState.scp173
			if statue != null:
				statue.speed = float(arg) * 70.0
			_say("173's speed set to " + arg)
		"106speed":
			var old_man: Node = _facility().scp106
			if old_man != null and is_instance_valid(old_man):
				old_man.speed = float(arg) * 70.0
			_say("106's speed set to " + arg)
		"173state":
			_say_173()
		"106state":
			_say_106()
		"096state":
			_say_096()
		"reset096":
			var big: Node = _facility().scp096
			if big != null and is_instance_valid(big):
				big.state = 0
		"disable173":
			_disable_173()
		"enable173":
			_enable_173()
		"disable106":
			_disable_106()
		"enable106":
			_enable_106()
		"teleport173":
			var statue2: Node3D = GameState.scp173
			if statue2 != null:
				statue2.global_position = _player().global_position + Vector3(0.0, 0.2, 0.0)
				statue2.velocity = Vector3.ZERO
		"teleport106":
			var old_man2: Node = _facility().scp106
			if old_man2 != null and is_instance_valid(old_man2):
				old_man2.state = 0.0
				old_man2.idle = false
		"halloween":
			_halloween()
		"sanic":
			GameState.super_man = not GameState.super_man
			GameState.super_man_timer = 0.0
			_say("GOTTA GO FAST" if GameState.super_man else "WHOA SLOW DOWN")
		"scp-420-j", "420", "weed":
			_weed()
		"godmode", "god":
			GameState.god_mode = _toggle(GameState.god_mode, arg)
			_say("GODMODE ON" if GameState.god_mode else "GODMODE OFF")
		"revive", "undead", "resurrect":
			_revive()
		"kill", "suicide":
			_kill()
		"noclip", "fly":
			GameState.noclip = _toggle(GameState.noclip, arg)
			_player().velocity = Vector3.ZERO
			_say("NOCLIP ON" if GameState.noclip else "NOCLIP OFF")
		"showfps":
			GameState.show_fps = not GameState.show_fps
			_say("ShowFPS: " + str(GameState.show_fps))
		"debughud":
			GameState.debug_hud = _toggle(GameState.debug_hud, arg)
			_say("Debug Mode On" if GameState.debug_hud else "Debug Mode Off")
		"stopsound", "stfu":
			_stop_sound()
		"camerafog":
			var fog := _pieces(arg)
			if fog.size() >= 2:
				GameState.fog_override = Vector4(float(fog[0]), float(fog[1]), 0.0, 0.0)
				_say("Near set to: %s, far set to: %s" % [fog[0], fog[1]])
			else:
				GameState.fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
				_say("Fog back to the light-volume fog.")
		"gamma":
			_gamma(float(arg))
		"hold372":
			_hold_372(arg)
		"spawn":
			var parts := _pieces(arg)
			_spawn_npc(parts[0] if parts.size() > 0 else "", parts[1] if parts.size() > 1 else "")
		"infinitestamina", "infstam":
			GameState.infinite_stamina = _toggle(GameState.infinite_stamina, arg)
			_say("INFINITE STAMINA ON" if GameState.infinite_stamina else "INFINITE STAMINA OFF")
		"toggle_warhead_lever":
			_facility().nuke_remote_on = not _facility().nuke_remote_on
			_say("Remote detonation " + ("on." if _facility().nuke_remote_on else "off."))
		"unlockexits":
			_unlock_exits(arg)
		"playmusic":
			_play_music(raw_arg)
		"notarget":
			GameState.no_target = _toggle(GameState.no_target, arg)
			_say("NOTARGET ON" if GameState.no_target else "NOTARGET OFF")
		"spawnradio":
			_give_pickup("Radio Transceiver", "fineradio", 101.0)
		"spawnnvg":
			_give_pickup("Night Vision Goggles", "nvgoggles", 1000.0)
		"spawnnav":
			_give_pickup("S-NAV Navigator Ultimate", "nav", 101.0)
		"spawnpumpkin", "pumpkin":
			_say("What pumpkin?")
		"seteventstate":
			_set_event_state(arg)
		"spawnparticles":
			_say("Particle emitter with ID %d not found." % int(arg), ORANGE)
		"giveachievement":
			_give_achievement(arg)
		"427state":
			GameState.i427_timer = float(arg) * 70.0
		"setblinkeffect":
			var blink := _pieces(arg)
			if blink.size() >= 2:
				GameState.blink_effect = float(blink[0])
				GameState.blink_effect_timer = float(blink[1])
				_say("Set BlinkEffect to: %s and BlinkEffect timer: %s" % [blink[0], blink[1]])
		"jorge":
			_say("JORGE HAS BEEN EXPECTING YOU.")
		_:
			_say("Command not found.", RED)
	return out

func command_names() -> Array[String]:
	var names: Array[String] = []
	for page in PAGES:
		for entry in page:
			var word: String = str(entry).split(" ")[0]
			if not names.has(word):
				names.append(word)
	for extra in ["godmode", "noclip", "fly", "god", "stfu", "undead", "resurrect", "suicide", "weed", "420", "infstam", "pumpkin", "roomculling"]:
		if not names.has(extra):
			names.append(extra)
	names.sort()
	return names

func _help(topic: String) -> void:
	var name := topic
	if name.is_empty() or name.is_valid_int():
		var page := clampi(int(name) if name.is_valid_int() else 1, 1, PAGES.size())
		_say("LIST OF COMMANDS - PAGE %d/%d" % [page, PAGES.size()], CYAN)
		_say("******************************", CYAN)
		for entry in PAGES[page - 1]:
			_say("- " + str(entry), CYAN)
		_say("******************************", CYAN)
		if page < PAGES.size():
			_say("Use \"help %d/%d\" to find more commands." % [page + 1, PAGES.size()], CYAN)
		_say("Use \"help [command name]\" to get more information about a command.", CYAN)
		_say("******************************", CYAN)
		return
	var key := name
	match name:
		"noclip", "fly":
			key = "noclip"
		"godmode", "god":
			key = "godmode"
		"revive", "undead", "resurrect":
			key = "revive"
		"stopsound", "stfu":
			key = "stopsound"
		"weed", "scp-420-j", "420":
			key = "scp-420-j"
		"infinitestamina", "infstam":
			key = "infinitestamina"
		"kill", "suicide":
			key = "kill"
		"roomculling":
			key = "culling"
	if not HELP.has(key):
		_say("There is no help available for that command.", ORANGE)
		return
	_say("HELP - " + key, CYAN)
	_say("******************************", CYAN)
	for line in HELP[key]:
		_say(str(line), CYAN)
	_say("******************************", CYAN)

func _status() -> void:
	var player := _player()
	var facility := _facility()
	_say("******************************", GREEN)
	_say("Status: ", GREEN)
	_say("Coordinates: ", GREEN)
	_say("    - collider: " + _blitz(player.global_position), GREEN)
	_say("    - camera: " + _blitz(player.camera.global_position), GREEN)
	_say("Rotation: ", GREEN)
	_say("    - collider: 0.0, %s, 0.0" % _num(rad_to_deg(player.rotation.y)), GREEN)
	_say("    - camera: %s, %s, 0.0" % [_num(player.user_pitch), _num(rad_to_deg(player.rotation.y))], GREEN)
	var room_name: String = facility.room_name_at(player.global_position)
	_say("Room: " + room_name, GREEN)
	if EVENT_VARS.has(room_name):
		var vars: Array = EVENT_VARS[room_name]
		_say("Room event: " + room_name, GREEN)
		for i in vars.size():
			_say("-    state%s: %s" % ["" if i == 0 else str(i + 1), str(facility.get_indexed(vars[i]))], GREEN)
	var record: Dictionary = facility.record_at(player.global_position)
	if not record.is_empty():
		_say("Room coordinates: %d, %d" % [record.grid.x, record.grid.y], GREEN)
	_say("Room culling: " + ("off" if not facility.drawing.enabled else ("off while noclip is on" if GameState.noclip else "on")), GREEN)
	_say("Stamina: " + _num(player.stamina), GREEN)
	_say("Death timer: " + ("-1" if player.dead else "0"), GREEN)
	_say("Blinktimer: " + _num(player.blink_timer), GREEN)
	_say("Injuries: " + _num(GameState.injuries), GREEN)
	_say("Bloodloss: " + _num(GameState.bloodloss), GREEN)
	_say("******************************", GREEN)

func _camera_pick() -> void:
	var player := _player()
	var from: Vector3 = player.camera.global_position
	var to: Vector3 = from - player.camera.global_transform.basis.z * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	_say("******************************", GREEN)
	if hit.is_empty():
		_say("No entity  picked", GREEN)
	else:
		var collider: Node = hit.collider
		_say("Picked entity:", GREEN)
		_say("Node: %s (%s)" % [collider.name, str(collider.get_parent().name)], GREEN)
		_say("Texture name: " + _texture_of(collider), GREEN)
		_say("Coordinates: " + _blitz(hit.position), GREEN)
	_say("******************************", GREEN)

func _texture_of(node: Node) -> String:
	var holder: Node = node.get_parent() if node.get_parent() != null else node
	for candidate in [node, holder]:
		for child in candidate.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				var mesh := (child as MeshInstance3D).mesh
				for i in mesh.get_surface_count():
					var material := mesh.surface_get_material(i)
					if (material is StandardMaterial3D or material is EntityMaterial) and material.albedo_texture != null:
						return material.albedo_texture.resource_path.get_file()
					if material is ShaderMaterial:
						var picture: Variant = (material as ShaderMaterial).get_shader_parameter("albedo_texture")
						if picture is Texture2D:
							return (picture as Texture2D).resource_path.get_file()
	return "unknown"

func _hold_372(arg: String) -> void:
	var shapes: Array = host.get_tree().get_nodes_in_group("scp372")
	if arg == "off":
		for shape in shapes:
			shape.hold = false
		_say("SCP-372 released.")
		return
	if shapes.is_empty():
		_spawn_npc("372", "")
		shapes = host.get_tree().get_nodes_in_group("scp372")
	for shape in shapes:
		shape.hold = true
	_say("SCP-372 held at the edge of the view.")

func _revive() -> void:
	var player := _player()
	player.dead = false
	player.restore_view()
	player.velocity = Vector3.ZERO
	GameState.blur_timer = 0.0
	GameState.blur_volume = 0.0
	GameState.light_flash = 0.0
	GameState.god_mode = false
	GameState.noclip = false
	player.camera_shake = 0.0
	player.fall_timer = 0.0         # FallTimer = 0: 106's drag ends too
	var hud := _hud()
	if hud != null:
		hud.cancel_death()
	if not host.get_tree().paused:      # from the open console the game stays stopped until it closes
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _kill() -> void:
	var messages := [
		"[REDACTED]",
		"Subject D-9341 found dead in Sector [REDACTED]. The subject appears to have attained no physical damage, and there is no visible indication as to what killed him. Body was sent for autopsy.",
		"EXCP_ACCESS_VIOLATION",
		"Subject D-9341 found dead in Sector [REDACTED]. The subject appears to have scribbled the letters \"kys\" in his own blood beside him. No other signs of physical trauma or struggle can be observed. Body was sent for autopsy.",
	]
	var was_god := GameState.god_mode
	GameState.god_mode = false
	_player().kill(messages[randi_range(0, 3)])
	GameState.god_mode = was_god

func _ending(code: String) -> void:
	var hud := _hud()
	if hud == null:
		return
	if not code in ["a1", "a2", "b1", "b2", "b3"]:
		_say("Ending codes: a1, a2, b1, b2, b3.", ORANGE)
		return
	hud.start_ending(code.to_upper())

func _teleport(name: String) -> void:
	match name:
		"895", "scp-895":
			name = "coffin"
		"scp-914":
			name = "914"
		"offices", "office":
			name = "room2offices"
	var facility := _facility()
	for record in facility.generator.rooms:
		if str(record.name) == name:
			var player := _player()
			_leave_forest()
			player.global_position = record.position + Vector3(0.0, 0.7, 0.0)
			player.velocity = Vector3.ZERO
			facility.after_teleport()
			return
	_say("Room not found.", ORANGE)

# A teleport out of SCP-860's forest: the room below stops being the player's room (room860_event.gd then puts the fog, the
# camera range and the steps back) and the lights come back to what they were before the door was opened.
func _leave_forest() -> void:
	var facility := _facility()
	if facility.events.room860.state != 1.0:
		return
	facility.events.room860.state = 0.0
	facility.events.room860.state3 = 0.0
	GameState.secondary_light = facility.events.room860.light

func _tp_leader() -> void:
	for unit in _facility().mtf.units:
		if is_instance_valid(unit) and unit.leader == null:
			_leave_forest()
			_player().global_position = unit.global_position + Vector3(0.0, 5.0, 0.0)
			_player().velocity = Vector3.ZERO
			_facility().after_teleport()
			return

func _tele(arg: String) -> void:
	var p := _pieces(arg)
	if p.size() < 3:
		_say("Usage: tele [x] [y] [z]", ORANGE)
		return
	var target := Vector3(float(p[0]), float(p[1]), -float(p[2]))
	_leave_forest()
	_player().global_position = target
	_player().velocity = Vector3.ZERO
	_facility().after_teleport()
	_say("Teleported to coordinates (X|Y|Z): %s|%s|%s" % [p[0], p[1], p[2]])

func _spawn_item(arg: String) -> void:
	for entry in RoomFill.spawnable():
		if str(entry.name).to_lower() == arg or str(entry.tempname).to_lower() == arg:
			_give_pickup(str(entry.name), str(entry.tempname), -1.0)
			_say(str(entry.name) + " spawned.")
			return
	_say("Item not found.", ORANGE)

func _give_pickup(item_name: String, tempname: String, state: float) -> Node:
	var player := _player()
	var pickup := RoomFill.make_pickup(item_name, tempname)
	_world_parent().add_child(pickup)
	pickup.global_position = Vector3(player.global_position.x, player.camera.global_position.y, player.global_position.z)
	if state >= 0.0:
		pickup.set_meta("state", state)
	return pickup

func _weed() -> void:
	var player := _player()
	for i in range(1, 21):
		var angle := deg_to_rad(18.0 * i)
		var radius := randf_range(0.3, 0.5)
		var pickup: Node = RoomFill.make_pickup("Some SCP-420-J", "420") if randi_range(1, 2) == 1 else RoomFill.make_pickup("Joint", "420s")
		_world_parent().add_child(pickup)
		pickup.global_position = Vector3(player.global_position.x + cos(angle) * radius, player.camera.global_position.y, player.global_position.z - sin(angle) * radius)
	Sfx.play_global(host, "SFX/Music/420J.ogg")

func _give_achievement(arg: String) -> void:
	var id := int(arg)
	if arg.is_valid_int() and id >= 0 and id < GameState.MAX_ACHIEVEMENTS:
		var name: String = GameState.ACHIEVEMENT_ORDER[id] if id < GameState.ACHIEVEMENT_ORDER.size() else "extra%d" % id
		GameState.give_achievement(name)
		_say("Achievement %s unlocked." % name)
	else:
		_say("Achievement with ID %d doesn't exist." % id, ORANGE)

func _spawn_npc(kind: String, state_arg: String) -> void:
	var facility := _facility()
	var player := _player()
	var at := player.global_position + Vector3(0.0, 0.2, 0.0)
	var key: String = SPAWN_ALIASES.get(kind, "")
	var message := ""
	var npc: Node = null
	match key:
		"008":
			npc = facility.spawn_zombie008(at, 1)
			message = "SCP-008 infected human spawned."
		"049":
			npc = facility.spawn_049(0.0)
			npc.global_position = at
			npc.state = 1
			message = "SCP-049 spawned."
		"049-2":
			npc = facility.spawn_zombie049(at, 1)
			message = "SCP-049-2 spawned."
		"096":
			npc = facility.spawn_096(at, 5)
			message = "SCP-096 spawned."
		"106":
			npc = facility.spawn_106(0.0)      # State -1 in the original: active at once (spawn_106's -1 means the 12-17 minute counter)
			message = "SCP-106 spawned."
		"173":
			var statue: Node3D = GameState.scp173
			if statue == null:
				_say("SCP-173 is not in this game.", RED)
				return
			statue.global_position = at
			statue.velocity = Vector3.ZERO
			if statue.idle == 3:
				statue.idle = 0
			statue.visible = true
			message = "SCP-173 spawned."
		"966":
			npc = facility.spawn_scp966(at)
			message = "SCP-966 instance spawned."
		"1499-1":
			npc = facility.dimension.spawn_loose(at)
			message = "SCP-1499-1 instance spawned."
		"class-d":
			npc = facility.spawn_human(1, at)
			message = "D-Class spawned."
		"guard":
			npc = facility.spawn_human(0, at)
			message = "Guard spawned."
		"mtf":
			npc = facility.mtf.spawn(at)
			message = "MTF unit spawned."
		"apache":
			var heli := Node3D.new()
			heli.set_script(load("res://scripts/npc/apache.gd"))
			_world_parent().add_child(heli)
			heli.global_position = at + Vector3(0.0, 8.0, 0.0)
			npc = heli
			message = "Apache spawned."
		"860-2":
			_say("SCP-860-2 cannot be spawned with the console. Sorry!", RED)
			return
		"939":
			_say("SCP-939 instances cannot be spawned with the console. Sorry!", RED)
			return
		"1048-a":
			_say("SCP-1048-A cannot be spawned with the console. Sorry!", RED)
			return
		"372":
			var shape := Node3D.new()
			shape.set_script(load("res://scripts/npc/scp_372.gd"))
			_world_parent().add_child(shape)
			shape.global_position = at
			npc = shape
			message = "SCP-372 spawned."
		"513-1":
			var ghost := Node3D.new()
			ghost.set_script(load("res://scripts/npc/scp_513_1.gd"))
			_world_parent().add_child(ghost)
			ghost.global_position = at
			npc = ghost
			message = "SCP-513-1 spawned."
		"tentacle":
			var tentacle := Node3D.new()
			tentacle.set_script(load("res://scripts/npc/scp_tentacle.gd"))
			_world_parent().add_child(tentacle)
			tentacle.global_position = at
			npc = tentacle
			message = "SCP-035 tentacle spawned."
		"clerk":
			npc = facility.spawn_human(2, at)
			message = "Clerk spawned."
		"066":
			_say("NPC type not found.", RED)
			return
		_:
			_say("NPC type not found.", RED)
			return
	if npc != null and not state_arg.is_empty() and "state" in npc:
		npc.state = float(state_arg) if npc.state is float else int(float(state_arg))
		message += " (State = %s)" % str(npc.state)
	_say(message)

func _say_173() -> void:
	var statue: Node3D = GameState.scp173
	if statue == null:
		_say("SCP-173 has not spawned.")
		return
	_say("SCP-173")
	_say("Position: " + _blitz(statue.global_position))
	_say("Idle: " + str(statue.idle))
	_say("State: " + str(statue.move_state))

func _say_106() -> void:
	var old_man: Node3D = _facility().scp106
	if old_man == null or not is_instance_valid(old_man):
		_say("SCP-106 has not spawned.")
		return
	_say("SCP-106")
	_say("Position: " + _blitz(old_man.global_position))
	_say("Idle: " + str(old_man.idle))
	_say("State: " + str(old_man.state))

func _say_096() -> void:
	var big: Node3D = _facility().scp096
	if big == null or not is_instance_valid(big):
		_say("SCP-096 has not spawned.")
		return
	_say("SCP-096")
	_say("Position: " + _blitz(big.global_position))
	_say("State: " + str(big.state))

func _disable_173() -> void:
	var statue: Node3D = GameState.scp173
	if statue != null:
		statue.idle = 3
		statue.visible = false

func _enable_173() -> void:
	var statue: Node3D = GameState.scp173
	if statue != null:
		statue.idle = 0
		statue.visible = true

func _disable_106() -> void:
	var old_man: Node = _facility().scp106
	if old_man != null and is_instance_valid(old_man):
		old_man.idle = true
		old_man.state = 200000.0
	_facility().contained_106 = true

func _enable_106() -> void:
	var old_man: Node = _facility().scp106
	if old_man != null and is_instance_valid(old_man):
		old_man.idle = false
		old_man.visible = true
	_facility().contained_106 = false

func _halloween() -> void:
	var statue: Node3D = GameState.scp173
	if statue == null:
		return
	GameState.halloween = not GameState.halloween
	if not statue.set_skin(GameState.halloween):
		_say("The picture could not be read.", ORANGE)
		return
	_say("173 JACK-O-LANTERN ON" if GameState.halloween else "173 JACK-O-LANTERN OFF")

func _set_wireframe(on: bool) -> void:
	GameState.wireframe = on
	host.get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if on else Viewport.DEBUG_DRAW_DISABLED
	RenderingServer.set_debug_generate_wireframes(true)

func _gamma(value: float) -> void:
	var holder := host.get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if holder != null:
		holder.environment.adjustment_enabled = true
		holder.environment.adjustment_brightness = clampf(value, 0.0, 2.0)
	_say("Gamma set to " + str(int(value)))

func _stop_sound() -> void:
	var stack: Array[Node] = [host.get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.call("stop")
		for child in node.get_children():
			stack.append(child)
	_say("Stopped all sounds.")

func _play_music(name: String) -> void:
	if name.is_empty():
		if GameState.music_override.begins_with("Custom/"):
			GameState.music_override = ""
		return
	var base := name.get_basename()
	var path := ContentPaths.existing_file("SFX/Music/Custom/%s.ogg" % base)
	if not FileAccess.file_exists(path):
		_say("The track was not found (only .ogg is played).", ORANGE)
		return
	GameState.music_override = "Custom/" + base

func _unlock_exits(which: String) -> void:
	var facility := _facility()
	match which:
		"a":
			facility.gate_a_unlocked = true
			_say("Gate A is now unlocked.")
		"b":
			facility.gate_b_unlocked = true
			_say("Gate B is now unlocked.")
		_:
			facility.gate_a_unlocked = true
			facility.gate_b_unlocked = true
			_say("Gate A and B are now unlocked.")
	facility.remote_door_on = true

func _set_event_state(arg: String) -> void:
	var p := _pieces(arg)
	if p.size() < 3:
		_say("Too few parameters. This command requires 3.", ORANGE)
		return
	var facility := _facility()
	var room_name: String = facility.room_name_at(_player().global_position)
	if not EVENT_VARS.has(room_name):
		_say("The current room doesn't has any event applied.", ORANGE)
		return
	var vars: Array = EVENT_VARS[room_name]
	var shown: Array[String] = []
	for i in 3:
		if i < vars.size() and p[i] != "keep":
			var current: Variant = facility.get_indexed(vars[i])
			facility.set_indexed(vars[i], int(float(p[i])) if current is int else float(p[i]))
		shown.append(str(facility.get_indexed(vars[i])) if i < vars.size() else "0")
	_say("Changed event states from current player room to: " + "|".join(shown))
