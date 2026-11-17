extends RefCounted
class_name EventPlan
# Which room gets which event: Main.bb InitEvents / CreateEvent. Every room holds at most one event; an event made later does
# not take a room that already has one. `plan` maps a room key ("x,y") to the event's name. The map's seed (and the difficulty)
# fix the plan, so a loaded game gets the same one again; the events' own state is kept by ambient_events.gd.
#
# CreateEvent(name, room, id, prob):
#   prob = 0   the id-th matching room without an event (the counter starts at 1 and counts rooms that already have one, so an
#              id of 0 and an id of 1 both mean the first free room)
#   prob > 0   every matching room without an event, each with that chance (id is ignored); Rnd is drawn for every matching
#              room, the ones that already hold an event too (Blitz evaluates both sides of And)
# The draws continue the map's Blitz generator from where InitNewGame calls InitEvents (map_generator.gd rng_before_events).


var plan: Dictionary = {}
var broken_gw_key := ""         # the room2gw whose door was knocked out (room2gw_brokendoor)

var _rooms: Array[Dictionary] = []
var _rng := BlitzRng.new()

static func build(rooms: Array[Dictionary], rng_state: int, aggressive: bool) -> RefCounted:
	var made: RefCounted = (load("res://scripts/world/event_plan.gd") as GDScript).new()
	made.assign_all(rooms, rng_state, aggressive)
	return made

func event_of(key: String) -> String:
	return str(plan.get(key, ""))

# The keys of the rooms that were given the event.
func rooms_with(event_name: String) -> Array[String]:
	var out: Array[String] = []
	for key in plan:
		if plan[key] == event_name:
			out.append(str(key))
	return out

func _create(event_name: String, room_name: String, id: int, prob: float = 0.0) -> void:
	if prob == 0.0:
		var counter := 0
		for room in _rooms:
			if room_name.is_empty() or str(room.name) == room_name:
				counter += 1
				if counter >= id and not plan.has(room.key):
					plan[room.key] = event_name
					return
		return
	var chance := BlitzRng._f32(prob)
	for room in _rooms:
		if room_name.is_empty() or str(room.name) == room_name:
			if _rng.rnd(0.0, 1.0) < chance and not plan.has(room.key):
				plan[room.key] = event_name

func assign_all(rooms: Array[Dictionary], rng_state: int, aggressive: bool) -> void:
	_rooms = rooms
	plan = {}
	_rng.state = rng_state
	var a := 1.0 if aggressive else 0.0       # SelectedDifficulty\aggressiveNPCs
	_create("173", "173", 0)
	_create("alarm", "start", 0)
	_create("pocketdimension", "pocketdimension", 0)
	# 7% chance that 106 appears in the rooms named "tunnel"
	_create("tunnel106", "tunnel", 0, 0.07 + 0.1 * a)
	# the chance for 173 appearing in the first lockroom is about 66%, in the later ones 30%
	if _rng.rand(1, 3) < 3:
		_create("lockroom173", "lockroom", 0)
	_create("lockroom173", "lockroom", 0, 0.3 + 0.5 * a)
	_create("room2trick", "room2", 0, 0.15)
	_create("1048a", "room2", 0, 1.0)
	_create("room2storage", "room2storage", 0)
	# 096 spawns in the first (and last) lockroom2
	_create("lockroom096", "lockroom2", 0)
	_create("endroom106", "endroom", _rng.rand(0, 1))
	_create("room2poffices2", "room2poffices2", 0)
	_create("room2fan", "room2_2", 0, 1.0)
	_create("room2elevator2", "room2elevator", 0)
	_create("room2elevator", "room2elevator", _rng.rand(1, 2))
	_create("room3storage", "room3storage", 0, 0)
	_create("tunnel2smoke", "tunnel2", 0, 0.2)
	_create("tunnel2", "tunnel2", _rng.rand(0, 2), 0)
	_create("tunnel2", "tunnel2", 0, 0.2 * a)
	# 173 appears in half of the "room2doors" rooms
	_create("room2doors173", "room2doors", 0, 0.5 + 0.4 * a)
	# the anomalous duck in room2offices2 rooms
	_create("room2offices2", "room2offices2", 0, 0.7)
	_create("room2closets", "room2closets", 0)
	_create("room2cafeteria", "room2cafeteria", 0)
	_create("room3pitduck", "room3pit", 0)
	_create("room3pit1048", "room3pit", 1)
	# the door that opens by itself in room2offices3
	_create("room2offices3", "room2offices3", 0, 1.0)
	_create("room2servers", "room2servers", 0)
	_create("room3servers", "room3servers", 0)
	_create("room3servers", "room3servers2", 0)
	# the dead guard
	_create("room3tunnel", "room3tunnel", 0, 0.08)
	_create("room4", "room4", 0)
	if _rng.rand(1, 5) < 5:
		match _rng.rand(1, 3):
			1:
				_create("682roar", "tunnel", _rng.rand(0, 2), 0)
			2:
				_create("682roar", "room3pit", _rng.rand(0, 2), 0)
			3:
				_create("682roar", "room2z3", 0, 0)
	_create("testroom173", "room2testroom2", 0, 1.0)
	_create("room2tesla", "room2tesla", 0, 0.9)
	_create("room2nuke", "room2nuke", 0, 0)
	if _rng.rand(1, 5) < 5:
		_create("coffin106", "coffin", 0, 0)
	else:
		_create("coffin", "coffin", 0, 0)
	_create("checkpoint", "checkpoint1", 0, 1.0)
	_create("checkpoint", "checkpoint2", 0, 1.0)
	_create("room3door", "room3", 0, 0.1)
	_create("room3door", "room3tunnel", 0, 0.1)
	if _rng.rand(1, 2) == 1:
		_create("106victim", "room3", _rng.rand(1, 2))
		_create("106sinkhole", "room3_2", _rng.rand(2, 3))
	else:
		_create("106victim", "room3_2", _rng.rand(1, 2))
		_create("106sinkhole", "room3", _rng.rand(2, 3))
	_create("106sinkhole", "room4", _rng.rand(1, 2))
	_create("room079", "room079", 0, 0)
	_create("room049", "room049", 0, 0)
	_create("room012", "room012", 0, 0)
	_create("room035", "room035", 0, 0)
	_create("008", "008", 0, 0)
	_create("room106", "room106", 0, 0)
	_create("pj", "roompj", 0, 0)
	_create("914", "914", 0, 0)
	_create("buttghost", "room2toilets", 0, 0)
	_create("toiletguard", "room2toilets", 1, 0)
	_create("room2pipes106", "room2pipes", _rng.rand(0, 3))
	_create("room2pit", "room2pit", 0, 0.4 + 0.4 * a)
	_create("testroom", "testroom", 0)
	_create("room2tunnel", "room2tunnel", 0)
	_create("room2ccont", "room2ccont", 0)
	_create("gateaentrance", "gateaentrance", 0)
	_create("gatea", "gatea", 0)
	_create("exit1", "exit1", 0)
	_create("room205", "room205", 0)
	_create("room860", "room860", 0)
	_create("room966", "room966", 0)
	_create("room1123", "room1123", 0, 0)
	_create("room2tesla", "room2tesla_lcz", 0, 0.9)
	_create("room2tesla", "room2tesla_hcz", 0, 0.9)
	_create("room4tunnels", "room4tunnels", 0)
	_create("room_gw", "room2gw", 0, 1.0)
	_create("dimension1499", "dimension1499", 0)
	_create("room1162", "room1162", 0)
	_create("room2scps2", "room2scps2", 0)
	_create("room_gw", "room3gw", 0, 1.0)
	_create("room2sl", "room2sl", 0)
	_create("medibay", "medibay", 0)
	_create("room2shaft", "room2shaft", 0)
	_create("room1lifts", "room1lifts", 0)
	_create("room2gw_b", "room2gw_b", _rng.rand(0, 1))
	_create("096spawn", "room4pit", 0, 0.6 + 0.2 * a)
	_create("096spawn", "room3pit", 0, 0.6 + 0.2 * a)
	_create("096spawn", "room2pipes", 0, 0.4 + 0.2 * a)
	_create("096spawn", "room2pit", 0, 0.5 + 0.2 * a)
	_create("096spawn", "room3tunnel", 0, 0.6 + 0.2 * a)
	_create("096spawn", "room4tunnels", 0, 0.7 + 0.2 * a)
	_create("096spawn", "tunnel", 0, 0.6 + 0.2 * a)
	_create("096spawn", "tunnel2", 0, 0.4 + 0.2 * a)
	_create("096spawn", "room3z2", 0, 0.7 + 0.2 * a)
	_create("room2pit", "room2_4", 0, 0.4 + 0.4 * a)
	_create("room2offices035", "room2offices", 0)
	_create("room2pit106", "room2pit", 0, 0.07 + 0.1 * a)
	_create("room1archive", "room1archive", 0, 1.0)
	broken_gw_key = broken_gw(_rooms)

# FillRoom room2gw (MapSystem.bb:5115): after its two doors, the first room2gw in creation order whose Rand(1, 2) is 1.
static func broken_gw(rooms: Array[Dictionary]) -> String:
	var rng := BlitzRng.new()
	for room in rooms:
		if str(room.name) == "room2gw" and room.has("fill_rng"):
			rng.state = int(room.fill_rng)
			FillRoomRng._skip(rng, 2)
			if rng.rand(1, 2) == 1:
				return str(room.key)
	return ""
