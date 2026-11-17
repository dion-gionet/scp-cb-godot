class_name EventStates
extends RefCounted
# What the room events remember. The state lives here, not in the room, so the saves and the bot's world reset find it in one place.

class Group extends RefCounted:
	func reset() -> void:
		var fresh: Object = get_script().new()
		for property in get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				set(property.name, fresh.get(property.name))

class Room049 extends Group:
	var state := 0.0                  # EventState of room049 (0 not visited, 1 .. 241 * 70 the power sequence, -1 .. -280 caught by 049)
	var pitches: Array = [81.0, -11.0]   # its two levers (power feed, generator)

class Room966 extends Group:
	var state := 0                    # EventState of room966: 0 not entered, 1 counting, 2 the two Sleep Killers are made

class Room860 extends Group:
	var state := 0.0
	var state2 := 0.0
	var state3 := 0.0
	var light := 1.0                  # PrevSecondaryLightOn

class Coffin extends Group:
	var lever_pitch := 10.0
	var event_state2 := 0              # EventState2: 1 once 106 was sent to the coffin
	var guard_state := 0               # PrevState of the guard: 0 not made, 1 falling, 2 lies in the pit
	var next_broadcast_ms := 0.0       # EventState: when the monitors are next set (every 3 s)

class Femur extends Group:
	var state := 0                    # EventState of room106: 0 waiting, 1 the breaker has run, 2 106 is loose
	var magnets := true               # EventState2: the magnets are on (a new game starts with them on)
	var timer := 0.0                  # EventState3: frames since the breaker, counted while the sound transmission is on
	var transmission := false         # SoundTransmission: the lever that carries the cell's sound (and the static) to the speakers
	var levers: Array = [81.0, -81.0] # the room's two levers (magnets, transmission)
	var platform_y := -980.0 * MeshLoader.ROOM_SCALE    # the magnet platform's height (Objects[6])
	var subject: Node = null           # NPC[0] of the room
	var radio_static: AudioStreamPlayer = null
	var voice: AudioStreamPlayer = null     # SoundCHN2: the subject's mutters, the breaker, the bait line

class Sl extends Group:
	var lever_on := true       # room2sl EventState3: the checkpoint lockdown lever is up (InitNewGame sets it: the lockdown is on from the start)
	var lever_pitch := 10.0    # the room2sl lever handle
	var scp008_done := false      # the 008 event reached EventState 2: the lever in the SCP-008 chamber was pulled (it unlocks checkpoint2)
	var scene_state2 := 0.0       # room2sl EventState2 (room2sl_scene.gd): below 0 049 still waits for the monitor

	# 049 still waits above room2sl for the monitor: the scene resumes when the player comes in (Save.bb 1026-1030)
	func waiting_049(npc: Node) -> bool:
		return npc.state == 0 and scene_state2 <= 0.0

class GateA extends Group:
	var state := 0.0             # EventState of gatea (0 not begun)
	var state2 := 0.0
	var state3 := 0.0

class Exit1 extends Group:
	var state := 0.0             # EventState of exit1 (0 = the surface not visited, 1 = the helicopter circles, 2 = the battle)
	var state2 := 0.0
	var state3 := 0.0

class Room079 extends Group:
	var state := 0.0           # EventState of room079: 1 the guard is placed, 2 waiting, 3 she spoke, 10001 she refused
	var state2 := 0.0          # EventState2: 1 she has spoken, 2 she has opened the gates
	var voice: AudioStreamPlayer = null     # e\SoundCHN of room079: Speech, Refuse, then GateB

class Servers extends Group:
	var state := 0.0           # EventState of room2servers (the 096 scene, then the levers); 0 = not begun
	var state2 := 0.0          # the fuel pump's level
	var state3 := 0.0          # the generator's level
	var guard: Node = null     # NPC[0] of the scene
	var killed := false

class Medibay extends Group:
	var entered := false    # EventState of the medibay: the zombie has been created
	var timer := 0.0        # EventState2: the wake-up timer
	var zombie: Node = null

class Mt extends Group:
	var state := 0            # EventState of room2tunnel: 2 once the player has been up in the tunnels (106 and the two 966s are placed)
	var generated := false    # the grid has been made: the SCP-500-01 and the goggles in the generator room exist

class Room008 extends Group:
	var state := 0                 # EventState of "008": 0 not entered, 1 the alarm (173 was put in the room), 2 the lid is down
	var window_broken := false     # EventState2: 173 broke the window (the cut and the infection happen once)

class Room3Servers extends Group:
	var moved_173: Dictionary = {} # room key -> true: EventState3, 173 was put in that room3servers once

var room049 := Room049.new()
var room966 := Room966.new()
var room860 := Room860.new()
var coffin := Coffin.new()
var femur := Femur.new()
var sl := Sl.new()
var gatea := GateA.new()
var exit1 := Exit1.new()
var room079 := Room079.new()
var servers := Servers.new()
var medibay := Medibay.new()
var mt := Mt.new()
var room008 := Room008.new()
var room3servers := Room3Servers.new()

func reset() -> void:
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var group := get(property.name) as Group
			if group != null:
				group.reset()
