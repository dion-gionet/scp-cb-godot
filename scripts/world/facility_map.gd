extends Node3D
class_name FacilityMap

const WaypointGraph = preload("res://scripts/world/waypoint_graph.gd")
const AmbientEvents = preload("res://scripts/world/ambient_events.gd")

var events := EventStates.new()
var mtf := MtfDirector.new(self)
var rooms := RoomRegistry.new(self)
var ambience := RoomAmbience.new(self)
var drawing := RoomDrawing.new(self)
var ambient: Node = null          # the events the rooms run on their own (InitEvents + UpdateEvents)
var particles: Particles = null   # the particles and the gas/steam jets (Particles.bb)

var generator: RefCounted
var active := false
var start_node: Node
var graph := WaypointGraph.new()

# Every model an NPC or an event loads during play is parsed once, here while the level loads, so that a squad or a monster
# appearing later is not a stall of 20 to 250 ms (the first MTF unit cost 250 ms; tool `hitchhunt` measures the rest). The SCP
# chambers that spawn the others are on every map, so all are read: about 1.3 s and 140 MB more than the first three.
const PREWARM_MODELS := ["GFX/npcs/MTF2.b3d", "GFX/npcs/scp-049.b3d", "GFX/npcs/106_2.b3d", "GFX/npcs/scp096.b3d", "GFX/npcs/scp-966.b3d",
	"GFX/npcs/zombiesurgeon.b3d", "GFX/npcs/zombie1.b3d", "GFX/npcs/guard.b3d", "GFX/npcs/classd.b3d", "GFX/npcs/clerk.b3d",
	"GFX/npcs/035.b3d", "GFX/npcs/035tentacle.b3d", "GFX/npcs/scp-939.b3d", "GFX/npcs/bll.b3d", "GFX/npcs/1499-1.b3d",
	"GFX/npcs/forestmonster.b3d", "GFX/npcs/naziofficer.b3d", "GFX/npcs/372.b3d", "GFX/npcs/scp-066.b3d", "GFX/npcs/scp-1048.b3d",
	"GFX/npcs/scp-1048a.b3d", "GFX/npcs/scp-1048pp.b3d", "GFX/npcs/duck_low_res.b3d", "GFX/apache.b3d", "GFX/apacherotor.b3d",
	"GFX/apacherotor2.b3d", "GFX/NPCs/682arm.b3d"]

func _prewarm_models() -> void:
	for file in PREWARM_MODELS:
		var path := ContentPaths.existing_file(file)
		if B3DModel._cache.has(path):
			continue
		var model := B3DModel.new()
		model.load_file(path)
		model.free()

func build_layout() -> void:
	add_to_group("facility")
	_prewarm_models()
	var catalog := RoomCatalog.new()
	catalog.load_from_ini()
	generator = MapGenerator.new()
	var forced_seed := OS.get_environment("SCP_SEED")
	var chosen := GameState.requested_seed
	if not forced_seed.is_empty():
		chosen = int(forced_seed) if forced_seed.is_valid_int() else BlitzRng.seed_number(forced_seed)
	generator.generate(catalog, chosen, GameState.intro_enabled)
	rooms.by_grid.clear()
	drawing.forget_neighbours()
	for room in generator.rooms:
		room["key"] = "%d,%d" % [room.grid.x, room.grid.y]
		rooms.by_grid[room.key] = room
	particles = Particles.new()
	particles.name = "Particles"
	add_child(particles)
	# InitEvents: which room holds which event (ambient_events.gd runs the ones that happen on their own)
	ambient = AmbientEvents.new()
	ambient.name = "AmbientEvents"
	add_child(ambient)
	ambient.setup(self)
	# CreateRoom(0, ROOM1, (MapWidth - 1) * 8, 500, 8, "gatea"): gate A hangs 500 up at the east edge, outside the grid; the
	# entrance's lift links the two.
	var gate_template := catalog.get_template("gatea")
	if not gate_template.is_empty():
		gatea_record = {"name": "gatea", "mesh": str(gate_template.mesh), "shape": 1, "zone": 0, "grid": Vector2i(generator.width - 1, -1), "angle": 0, "position": Vector3(float(generator.width - 1) * 8.0, 500.0, -8.0), "large": false, "key": "gatea", "off_grid": true}
		rooms.by_grid["gatea"] = gatea_record
	dimension = Dimension1499.new()
	dimension.name = "Dimension1499"
	add_child(dimension)
	dimension.setup(self, catalog.get_template("dimension1499"))
	rooms.plan_doors()

func summarize() -> String:
	if generator == null:
		return "no map"
	return generator.summarize()

func enter_after_breach(player: Node3D, statue: Node, intro_room: Node, place_actors: bool = true) -> bool:
	if active:
		return true
	var record: Dictionary = generator.start_room if generator else {}
	if record.is_empty():
		push_error("Generated map has no start room")
		return false
	GameState.light_energy = 1.0     # the rooms keep their lightmaps as they are (nothing in the original dims them after the breach)
	if start_node == null:
		push_error("The start room has no node")
		return false
	# UpdateEvents "alarm": arriving in the start room opens its small cell door (RoomDoors[2])
	# and the door of the first adjacent room (RoomDoors[5]); the containment door is already open.
	var scene_door: Node3D = null
	var cell_door = start_node.door_slots.get(2)
	if cell_door != null:
		cell_door.open = true
	for edge in rooms.doors:
		var def: Dictionary = rooms.door_defs.get(edge, {})
		var start_key := "%d,%d" % [record.grid.x, record.grid.y]
		if str(def.get("a", "")) == start_key or str(def.get("b", "")) == start_key:
			rooms.doors[edge].open = true
			scene_door = rooms.doors[edge]
			break
	var shift := Vector3(3712.0, 384.0, -1312.0) * MeshLoader.ROOM_SCALE
	# The original maps the player's offset from the intro room into [start], which only
	# lands somewhere sensible for positions inside the 173 chamber. This port's player is
	# still in the Class-D cell at breach, so use fixed spots on the open chamber floor
	# (floor y=1.5; verified with physics rays). x 11-12 is under a catwalk, so avoid it.
	if place_actors:
		var cell := Vector3(14.0, shift.y + 0.05, -5.5)
		player.velocity = Vector3.ZERO
		player.global_position = start_node.to_global(cell)
		player.rotation.y = start_node.rotation.y + deg_to_rad(255.0)
		if statue:
			var statue_local := Vector3(14.0, shift.y + 0.01, -8.0)
			statue.velocity = Vector3.ZERO
			statue.global_position = start_node.to_global(statue_local)
			statue.rotation.y = start_node.rotation.y + deg_to_rad(-190.0)
			statue.active = true
			var to_statue: Vector3 = statue.global_position - player.global_position
			player.rotation.y = atan2(-to_statue.x, -to_statue.z)
	if intro_room:
		intro_room.queue_free()
	active = true
	after_teleport()
	if start_scene_enabled and not loading_save:
		begin_start_scene(scene_door)
	if spawn_106_enabled:
		spawn_106()
	print("FACILITY angle=", record.angle, " entered rooms=", rooms.built.size(), " player=", player.global_position, " start=", start_node.global_position)
	return true

# MapSystem.bb UpdateRooms: PlayerZone 0 = LCZ, 1 = HCZ, 2 = EZ from the grid row (z / 8).
func zone_at(pos: Vector3) -> int:
	# the original builds the intro room at z (MapHeight - 1) * 8, the light containment end (MapSystem.bb 7579); the port's
	# sits at the world origin, which the rows below would read as the entrance zone
	if intro_active:
		return 0
	var row := -pos.z / 8.0
	if row < 6.0:
		return 2
	if row < 12.0:
		return 1
	return 0

# Links queued waypoints a few per physics frame (the room collision must exist first).
const Infection = preload("res://scripts/game/infection.gd")
var infection: Node = null      # the SCP-008 infection (UpdateInfect)
const LightFog = preload("res://scripts/game/light_fog.gd")
var light_fog: Node = null      # the fog of war (LightVolume)
const NightVision = preload("res://scripts/game/night_vision.gd")
var night_vision: Node = null   # the goggles' battery, refresh and ambient
const DustMotes = preload("res://scripts/game/dust_motes.gd")
var dust_motes: Node = null

# UpdateRooms runs after every teleport: the rooms around the player are shown and solid before the next physics step.
func after_teleport() -> void:
	drawing.after_teleport()

func room_name_at(pos: Vector3) -> String:
	return rooms.room_name_at(pos)

func room_at(pos: Vector3) -> Node3D:
	return rooms.room_at(pos)

func record_at(pos: Vector3) -> Dictionary:
	return rooms.record_at(pos)

func doors_near(pos: Vector3, radius: float) -> Array[Node3D]:
	return rooms.doors_near(pos, radius)

func adjacent_records(record: Dictionary) -> Array[Dictionary]:
	return rooms.adjacent_records(record)

func waypoints() -> Array[Vector3]:
	return rooms.waypoints()

func _physics_process(delta: float) -> void:
	if infection == null:
		infection = Infection.new()
		infection.name = "Infection"
		add_child(infection)
		light_fog = LightFog.new()
		light_fog.name = "LightFog"
		add_child(light_fog)
		night_vision = NightVision.new()
		night_vision.name = "NightVision"
		add_child(night_vision)
		dust_motes = DustMotes.new()
		dust_motes.name = "DustMotes"
		add_child(dust_motes)
	if not active and intro_active and GameState.player != null:
		_update_lights(GameState.player.global_position)
	if active:
		ambience.update()
		drawing.update()    # UpdateRooms (PlayerRoom) comes first in UpdateEvents, before the events and UpdateRoomLights
		if GameState.player != null:
			check_049_trigger(GameState.player.global_position)
			_update_lights(GameState.player.global_position)
		_update_explosion(delta * 70.0)
		_update_079_gates()
		_update_femur(delta * 70.0)
		_mark_room_found()
		_recheck_items()
		_update_096_events()
		mtf.update(delta * 70.0)
	monitor_timer = monitor_timer + delta * 70.0 if monitor_timer < 100.0 else 0.0
	if graph.pending_count() > 0 and not rooms.building:
		graph.process_pending(get_world_3d().direct_space_state, _door_bodies(), 12)


var _items_due_ms := 0.0

func _recheck_items() -> void:
	var now: float = GameState.clock_ms()
	if now < _items_due_ms:
		return
	_items_due_ms = now + 700.0
	for node in get_tree().get_nodes_in_group("pickup"):
		if node.has_method("recheck_near") and not node.is_physics_processing():
			node.recheck_near()

func speak_079(relative: String) -> void:
	if events.room079.voice != null and is_instance_valid(events.room079.voice):
		events.room079.voice.stop()
		events.room079.voice.queue_free()
	events.room079.voice = Sfx.play_global(self, relative)

func speaking_079() -> bool:
	return events.room079.voice != null and is_instance_valid(events.room079.voice) and events.room079.voice.playing

# EventState2 = 1 (she has spoken) and the remote doors back on (the lever in the control room): she tells the facility that
# the gates are open, and both gate events are told (their EventState3 = 1). Not tied to either room.
func _update_079_gates() -> void:
	if events.room079.state2 == 1.0 and remote_door_on:
		speak_079("SFX/SCP/079/GateB.ogg")
		events.room079.state2 = 2.0
		gate_a_unlocked = true
		gate_b_unlocked = true

# ---- the femur breaker (room106; the room's own part is femur_room.gd) -----------------------------------------------------

var scp914_knob_roll := 0.0             # the knob of SCP-914 (saved)
var scp294_coins := 0                    # EventState2 of the cafeteria: quarters put into SCP-294 (it needs two)

# SCP-895's chamber (UpdateEvents "coffin"): the event plan gives the room "coffin106" (80 %) or "coffin". The event is
# never removed and there is one such room, so the plan alone decides.
func coffin_is_106() -> bool:
	return ambient != null and not ambient.plan.rooms_with("coffin106").is_empty()

# SCP-860-1: the room860 event (EventState 1 while the player is in the forest, 2: which door it came in by, 3: the monster timer) and the forest
var forest_grid: PackedInt32Array = PackedInt32Array()
var forest_seed := 0
var scp966s: Array[Node] = []

# UpdateEvents room106, the part outside the player-in-room block: the timer runs and the radio static plays while the
# transmission is on, wherever the player is.
func _update_femur(fps: float) -> void:
	if not events.femur.transmission:
		return
	if events.femur.state == 1:
		events.femur.timer = minf(events.femur.timer + fps, 4000.0)
	if events.femur.radio_static == null or not is_instance_valid(events.femur.radio_static) or not events.femur.radio_static.playing:
		events.femur.radio_static = Sfx.play_global(self, "SFX/Radio/static.ogg")

var _door_rids: Array[RID] = []
var _door_rids_version := -1

func _door_bodies() -> Array[RID]:
	if _door_rids_version != rooms.door_version:
		_door_rids_version = rooms.door_version
		_door_rids.clear()
		for node in get_tree().get_nodes_in_group("door"):
			for body in node.find_children("*", "StaticBody3D", true, false):
				_door_rids.append((body as StaticBody3D).get_rid())
	return _door_rids

# FindPath for NPCs: {"status": 0 there / 1 found / 2 unreachable, "points": [Vector3]}.
func find_path(from: Vector3, to: Vector3, mtf := false) -> Dictionary:
	return graph.find_path(get_world_3d().direct_space_state, _door_bodies(), from, to, mtf)

# ---- room graph helpers for NPCs (PlayerRoom, Room\Adjacent[], PlayerInReachableRoom) ----

# PlayerInReachableRoom: false where NPCs cannot follow (pocket dimension, gate A, 1499, the
# surface of gate B, 860's forest, 049's lower chamber unless it may spawn there or the difficulty is Keter).
func reachable_room(pos: Vector3, can_spawn_in_049_chamber: bool = false) -> bool:
	var name := room_name_at(pos)
	if name in ["pocketdimension", "gatea", "dimension1499", "173"]:
		return false
	if name == "exit1" and pos.y > 1040.0 * MeshLoader.ROOM_SCALE:
		return false
	if name == "room860" and events.room860.state == 1.0:
		return false
	if not can_spawn_in_049_chamber and not GameState.aggressive_npcs() and name == "room049" and pos.y <= -2848.0 * MeshLoader.ROOM_SCALE:
		return false
	return true

# SCP-049: created by the room2sl or room049 event.
const Scp049 = preload("res://scripts/npc/scp_049.gd")
var scp049: Node = null
var spawn_049_enabled := true    # tests switch the event spawn off

# 049 is created when PlayerRoom is the room (Main.bb QuickLoadEvents): room2sl's event starts as the player enters
# the room (UE 8116), room049's at "load2" once the player is in its lower chamber (UE 5649).
func check_049_trigger(player_pos: Vector3) -> void:
	if not spawn_049_enabled:
		return
	var here := drawing.player_room
	if here == null:
		return
	if here.room_name == "room2sl":
		begin_room2sl(here)    # the event of that room creates 049 (or takes back a loaded one still waiting) and runs the scene
		return
	if scp049 != null:
		return
	if here.room_name == "room049" and in_049_chamber(player_pos.y):
		spawn_049(1.0)

func in_049_zone(pos: Vector3) -> bool:
	var name := room_name_at(pos)
	if name == "room2sl":
		return true
	return name == "room049" and in_049_chamber(pos.y)

static func in_049_chamber(y: float) -> bool:
	return y <= -2848.0 * MeshLoader.ROOM_SCALE

# CreateNPC(NPCtype049) with State 2 and Idle 1: hidden until the player is somewhere it can
# teleport to, then it appears two rooms away.
func spawn_049(idle: float = 1.0) -> Node:
	if scp049 != null and is_instance_valid(scp049):
		scp049.queue_free()   # there is only ever one
	scp049 = CharacterBody3D.new()
	scp049.set_script(Scp049)
	scp049.name = "SCP049"
	scp049.idle = idle
	get_parent().add_child(scp049)
	if GameState.player != null:
		scp049.global_position = GameState.player.global_position + Vector3(0.0, -500.0, 0.0)
	return scp049

# UpdateRoomLights: a room light only exists for the entities near the camera (8.5 units).
func _update_lights(player_pos: Vector3) -> void:
	var camera: Camera3D = GameState.player.camera if GameState.player != null else null
	var origin: Vector3 = camera.global_position if camera != null else player_pos
	var space := get_world_3d().direct_space_state
	var player_room: Node3D = drawing.player_room
	var lit_rooms: Array[Node3D] = []
	# the intro room is room "173" of the original's map and the PlayerRoom until the breach
	if intro_active and is_instance_valid(intro_chamber):
		player_room = intro_chamber
		lit_rooms.append(intro_chamber)
	var in_173 := player_room != null and player_room == intro_chamber or player_room is FacilityRoom and (player_room as FacilityRoom).room_name == "173"
	for key in rooms.built:
		var room: Node3D = rooms.built[key]
		if not is_instance_valid(room) or not "lights" in room:
			continue
		# r\dist < HideDistance * 0.7 Or r = PlayerRoom (MapSystem.bb 7907)
		if room != player_room and RoomRegistry.room_dist(room.global_position, player_pos) >= NpcGravity.HIDE_DISTANCE * 0.7:
			continue
		lit_rooms.append(room)
	# the models are lit by the shown lights in Blitz3D's entity order: the rooms as created, each room's lights in turn
	var shown: Array[Light3D] = []
	for room in lit_rooms:
		for light: Light3D in room.lights:
			light.visible = GameState.lights_on and origin.distance_to(light.global_position) < 8.5
			LightSprites.update(light, camera, GameState.lights_on, in_173, space)
			if light.is_visible_in_tree() and light.has_meta("blitz_range"):     # the lights are children of r\obj, which UpdateRooms hides
				shown.append(light)
	for light: Light3D in get_tree().get_nodes_in_group("entity_lights"):
		if light.is_visible_in_tree():
			shown.append(light)
	EntityLights.upload(shown)

var scp106: Node = null
var spawn_106_enabled := true

# CreateNPC(NPCtypeOldMan) with State = 70 * 60 * Rand(12, 17): he appears 12-17 minutes in.
func spawn_106(state: float = INF) -> Node:      # INF: the counter that brings him 12-17 minutes into the game (every real State, hunting ones included, is below it)
	if scp106 != null and is_instance_valid(scp106):
		scp106.queue_free()
	scp106 = CharacterBody3D.new()
	scp106.set_script(Scp106)
	scp106.name = "SCP106"
	scp106.state = state if state != INF else generator.scp106_state
	get_parent().add_child(scp106)
	if GameState.player != null:
		scp106.global_position = GameState.player.global_position + Vector3(0.0, -30.0, 0.0)
	return scp106

const PocketDimension = preload("res://scripts/world/pocket_dimension.gd")
var pocket: Node3D = null

func build_pocket() -> void:
	pocket = Node3D.new()
	pocket.set_script(PocketDimension)
	add_child(pocket)
	pocket.build()
	pocket.set_shown(false)

func enter_pocket(player: CharacterBody3D) -> void:
	pocket.enter(player)

# Where the player comes out: the first room with one of the given names (a point on its floor
# the original names: room2shaft (1560, 0, 250), room106 (0, 0, -720), a tunnel's middle), else
# the start room.
func pocket_exit(names: Array) -> Vector3:
	for wanted in names:
		for record in generator.rooms:
			if str(record.name) != str(wanted):
				continue
			var room := rooms.get_room(record)
			if room == null:
				continue
			var local := Vector3.ZERO
			match str(wanted):
				"room2shaft":
					local = Vector3(1560.0, 0.0, -250.0) * MeshLoader.ROOM_SCALE
				"room106":
					local = Vector3(0.0, 0.0, 720.0) * MeshLoader.ROOM_SCALE
			var floor_height: float = room.floor_y(local.x, local.z)
			return room.to_global(Vector3(local.x, floor_height + 0.02, local.z))
	var start: Dictionary = generator.start_room
	var start_room := rooms.get_room(start)
	return start_room.to_global(Vector3(14.0, 1.55, -5.5))

func after_pocket_exit() -> void:
	after_teleport()
	release_lockdown()

# Getting out of the pocket dimension ends the light containment lockdown (UpdateEvents "pocketdimension", all three
# exits: room2sl's EventState3 = 0, the lever set to pitch 0, the checkpoint monitors off).
func release_lockdown() -> void:
	events.sl.lever_on = false
	events.sl.lever_pitch = 0.0
	for lever in get_tree().get_nodes_in_group("sl_lever"):
		lever.pitch = 0.0

# NPCs.bb OldMan "spawn106": he does not come in the 1499 dimension, in room860's forest nor in 049's lower chamber; once the gate A event has begun he always may.
func can_106_spawn(pos: Vector3) -> bool:
	if events.gatea.state != 0.0:
		return true
	var name := room_name_at(pos)
	if name == "dimension1499" or events.room860.state == 1.0:
		return false
	return not (name == "room049" and pos.y <= -2848.0 * MeshLoader.ROOM_SCALE)

var humans: Array[Node] = []
var monitor_timer := 0.0      # MonitorTimer: the lockdown pictures flash every 100 frames

# CreateNPC(NPCtypeGuard / NPCtypeD, x, y, z); texture_id is the argument of ChangeNPCTextureID.
func spawn_human(kind: int, pos: Vector3, texture_id: int = -1, model: String = "") -> CharacterBody3D:
	var human := CharacterBody3D.new()
	human.set_script(HumanNpc)
	human.setup(kind, texture_id, model)
	human.name = "Guard" if kind == HumanNpc.Kind.GUARD else ("Clerk" if kind == HumanNpc.Kind.CLERK else "ClassD")
	get_parent().add_child(human)
	human.global_position = pos
	humans.append(human)
	return human

const Scp096 = preload("res://scripts/npc/scp_096.gd")
var scp096: Node = null            # Curr096
var gatea_record: Dictionary = {}
var contained_106 := false         # Contained106: the femur breaker was used (not in the game yet): gate A's ending is A2 then
var exit1_centre := Vector3.INF    # exit1 Objects[3]: the helicopters' sound falls off from here
var nuke_lever_pitch := INF         # the remote detonation lever (saved)
var nuke_remote_on := false        # the room2nuke event's remote detonation (not in the game yet): gate B's ending B2 needs it
var remote_door_on := true         # RemoteDoorOn: the control room's lever (room2ccont); on it keeps 079's door shut and the gates barred
var ccont_pitches: Array = [10.0, 10.0, 10.0]    # room2ccont's levers (primary light, secondary light, remote doors) (saved)
var ccont_state := 0.0             # EventState of room2ccont: 1 once the secondary light lever was looked at
var gate_a_unlocked := false       # gateaentrance EventState3: 079 has opened the gate
var gate_b_unlocked := false       # exit1 EventState3
var spawn_096_rooms := true        # tests turn the lockroom event off

# CreateNPC(NPCtype096, x, y, z); `state` is n\State (0 sitting, 5 walking about, 6 held by an event).
func spawn_096(pos: Vector3, state: int = 0, yaw: float = 0.0) -> CharacterBody3D:
	if scp096 != null and is_instance_valid(scp096):
		scp096.queue_free()
	var shy := CharacterBody3D.new()
	shy.set_script(Scp096)
	shy.name = "SCP096"
	shy.state = state
	shy.rotation.y = yaw
	get_parent().add_child(shy)
	shy.global_position = pos
	scp096 = shy
	return shy

# The nuke / explosion (UpdateEvents.bb, end of UpdateEvents): shakes, a flash, and 160 frames in the player is "killed" and the
# ending named by the event follows (`GameState.selected_ending` is set by it).
var explosion_ending := ""

func _update_explosion(fps: float) -> void:
	var s := GameState
	var player: CharacterBody3D = s.player
	if player == null:
		return
	s.light_flash = maxf(s.light_flash - fps / 70.0, 0.0)
	if s.explosion_timer <= 0.0:
		return
	s.explosion_timer += fps
	if s.explosion_timer < 140.0:
		if s.explosion_timer - fps < 5.0:
			Sfx.play_global(self, "SFX/Ending/GateB/Nuke1.ogg")
			player.camera_shake = 10.0
			s.explosion_timer = 5.0
		player.camera_shake = player.camera_shake + (s.explosion_timer / 60.0 - player.camera_shake) * minf(fps / 50.0, 1.0)
	else:
		player.camera_shake = minf(s.explosion_timer / 20.0, 20.0)
		if s.explosion_timer - fps < 140.0:
			player.blink_timer = 1.0
			Sfx.play_global(self, "SFX/Ending/GateB/Nuke2.ogg")
			particles.nuke_smoke(player.global_position + Vector3(0.0, 0.3, 0.0))
		s.light_flash = minf((s.explosion_timer - 140.0) / 10.0, 5.0)
		if s.explosion_timer > 160.0 and not explosion_ending.is_empty():
			var hud := get_tree().get_first_node_in_group("hud")
			var code := explosion_ending
			explosion_ending = ""
			s.explosion_timer = 0.0
			if hud != null:
				hud.start_ending(code)
		elif s.explosion_timer > 500.0:
			s.explosion_timer = 0.0

func _mark_room_found() -> void:
	if GameState.player == null:
		return
	var record := record_at(GameState.player.global_position)
	if not record.is_empty():
		GameState.rooms_found["%d,%d" % [record.grid.x, record.grid.y]] = true

# UpdateEvents "lockroom096": the first time the player is in that room, 096 sits in its middle.
var _lockroom096_done := false

func _first_room_named(room_name: String) -> Dictionary:
	for room in generator.rooms:
		if str(room.name) == room_name:
			return room
	return {}

func _update_096_events() -> void:
	if _lockroom096_done or not spawn_096_rooms or GameState.player == null:
		return
	var pos: Vector3 = GameState.player.global_position
	var record := record_at(pos)
	if str(record.get("name", "")) != "lockroom2" or record != _first_room_named("lockroom2"):
		return
	_lockroom096_done = true
	if scp096 == null:
		spawn_096(Vector3(record.position.x, record.position.y + 0.05, record.position.z), 0, deg_to_rad(float(record.angle) + 45.0))

const Scp008Zombie = preload("res://scripts/npc/scp_008_zombie.gd")
var zombies008: Array[Node] = []

# CreateNPC(NPCtype008, x, y, z) followed by n\State = state (the console and the 914 recipe use 1 / 2, the medibay 0).
func spawn_zombie008(pos: Vector3, state: int = 2) -> CharacterBody3D:
	var zombie := CharacterBody3D.new()
	zombie.set_script(Scp008Zombie)
	zombie.name = "SCP008Zombie%d" % (zombies008.size() + 1)
	zombie.state = state
	get_parent().add_child(zombie)
	zombie.global_position = pos
	zombies008.append(zombie)
	return zombie

const Scp966 = preload("res://scripts/npc/scp_966.gd")
func spawn_scp966(pos: Vector3) -> CharacterBody3D:
	var npc := CharacterBody3D.new()
	npc.set_script(Scp966)
	npc.name = "SCP966_%d" % (scp966s.size() + 1)
	get_parent().add_child(npc)
	npc.global_position = pos
	scp966s.append(npc)
	return npc

func remove_scp966(npc: Node) -> void:
	scp966s.erase(npc)
	if is_instance_valid(npc):
		npc.queue_free()

# CreateNPC(NPCtypeZombie, x, y, z): an SCP-049-2, kept in the same list (the Nine-Tailed Fox shoot both).
const Dimension1499 = preload("res://scripts/world/dimension_1499.gd")
var dimension: Node = null
const Scp0492 = preload("res://scripts/npc/scp_049_2.gd")
func spawn_zombie049(pos: Vector3, state: int = 0) -> CharacterBody3D:
	var zombie := CharacterBody3D.new()
	zombie.set_script(Scp0492)
	zombie.name = "SCP0492Zombie%d" % (zombies008.size() + 1)
	zombie.state = state
	get_parent().add_child(zombie)
	zombie.global_position = pos
	zombies008.append(zombie)
	return zombie

func remove_zombie008(zombie: Node) -> void:
	zombies008.erase(zombie)
	if zombie == events.medibay.zombie:
		events.medibay.zombie = null
	if is_instance_valid(zombie):
		zombie.queue_free()

func remove_human(human: Node) -> void:
	humans.erase(human)
	if is_instance_valid(human):
		human.queue_free()

const StartScene = preload("res://scripts/world/start_scene.gd")
var start_scene: Node = null
var start_scene_enabled := OS.get_environment("SCP_BOT") != "1"     # the bot runs without it unless a scenario asks
var start_scene_adopt: Dictionary = {}   # people the intro carried over: "guard" (NPC[0]) and "scientist" (NPC[1])

var loading_save := false     # a loaded game resumes the scene from its save (resume_start_scene) instead of starting it

func resume_start_scene(saved: Dictionary) -> void:
	loading_save = false
	if not bool(saved.get("running", false)):
		return
	if start_scene != null and is_instance_valid(start_scene):
		start_scene.queue_free()
	start_scene = Node.new()
	start_scene.set_script(StartScene)
	start_scene.name = "StartScene"
	add_child(start_scene)
	start_scene.resume(start_node, start_neighbour_door(), saved)

func begin_start_scene(neighbour_door: Node3D) -> void:
	if start_scene != null and is_instance_valid(start_scene):
		start_scene.queue_free()
	start_scene = Node.new()
	start_scene.set_script(StartScene)
	start_scene.name = "StartScene"
	add_child(start_scene)
	start_scene.begin(start_node, neighbour_door, start_scene_adopt)

# RoomDoors[5] of the start room: the door of the first neighbouring room.
func start_neighbour_door() -> Node3D:
	var start_key := "%d,%d" % [generator.start_room.grid.x, generator.start_room.grid.y]
	for edge in rooms.doors:
		var def: Dictionary = rooms.door_defs.get(edge, {})
		if str(def.get("a", "")) == start_key or str(def.get("b", "")) == start_key:
			return rooms.doors[edge]
	return null

# The intro room is not part of the generated map, but its waypoints and door frames join the
# graph so the guards can walk the escort route.
var intro_active := false
var intro_chamber: Node3D = null

func register_intro_room(chamber: Node3D) -> void:
	intro_chamber = chamber
	for point in chamber.waypoints:
		graph.add_point(point, "intro", "intro", false)
	for point in chamber.door_waypoints:
		graph.add_point(point, "intro", "intro", true)

func unregister_intro_room() -> void:
	intro_active = false
	intro_chamber = null
	graph.remove_owner("intro")

# ---- the room2sl scene (UpdateEvents.bb "room2sl") -----------------------------------------------------------

const Room2slScene = preload("res://scripts/world/room2sl_scene.gd")
var room2sl_scene: Node = null

# 049 is created in the cell, and the scene walks it out and along the catwalk; if 049 already exists
# (room049, a save) the room only keeps its monitors.
func begin_room2sl(room: Node3D) -> void:
	if room == null:
		return
	if scp049 != null and is_instance_valid(scp049) and not events.sl.waiting_049(scp049):
		return
	if room2sl_scene != null and is_instance_valid(room2sl_scene):
		return
	room2sl_scene = Node.new()
	room2sl_scene.set_script(Room2slScene)
	room2sl_scene.name = "Room2slScene"
	add_child(room2sl_scene)
	room2sl_scene.begin(room)

# The doors that join a generated room to its neighbours (Room\AdjDoor[]).
func room_edge_doors(room: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for key in rooms.built:
		if rooms.built[key] != room:
			continue
		for edge in rooms.door_defs:
			var def: Dictionary = rooms.door_defs[edge]
			if (str(def.a) == key or str(def.b) == key) and rooms.doors.has(edge):
				out.append(rooms.doors[edge])
	return out
