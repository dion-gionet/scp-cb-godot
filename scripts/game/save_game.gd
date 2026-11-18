extends RefCounted
class_name SaveGame
# One save slot (SaveGame / LoadGame in the original). The facility is generated again from the
# saved map seed, then what the run changed is put back: the player, inventory, worn items,
# taken items, door and elevator states, items lying around, 173 and 049, achievements, the rooms and documents found, decals.

const LEGACY_SLOT := "autosave"
const VERSION := 1

# The slot Save / Load / the pause menu act on; the legacy single file is slot 0.
static var current_slot := LEGACY_SLOT

# The bot sets its own folder: suite games run side by side and their menu tests create and delete saves.
static var dir := "user://saves"

static func path_of(slot: String) -> String:
	return dir + "/" + slot + ".json"

static func _slot_or_current(slot: String) -> String:
	return current_slot if slot.is_empty() else slot

static func exists(slot := "") -> bool:
	return FileAccess.file_exists(path_of(_slot_or_current(slot)))

static func read(slot := "") -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_of(_slot_or_current(slot))))
	if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION:
		return parsed
	return {}

static func write(data: Dictionary, slot := "") -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var target := path_of(_slot_or_current(slot))
	# written next to the slot and renamed over it: a crash or a full disk cannot leave half a save behind
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	var failed := file.get_error() != OK
	file.close()
	if failed or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(target)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	return true

static func delete(slot := "") -> void:
	if exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_of(_slot_or_current(slot))))

# LoadSaveGames: every slot file as {slot, name, saved_at, version, compatible}, newest first.
static func list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + file_name))
		if not parsed is Dictionary:
			continue
		var slot := file_name.get_basename()
		result.append({
			"slot": slot,
			"name": str(parsed.get("name", slot)),
			"saved_at": str(parsed.get("saved_at", "")),
			"version": int(parsed.get("version", 0)),
			"compatible": int(parsed.get("version", 0)) == VERSION,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.saved_at != b.saved_at:
			return a.saved_at > b.saved_at
		return a.slot < b.slot)
	return result

# Menu.bb 392-396: a name already used gets " (n)" appended, n counting the saves that share it.
static func unique_name(wanted: String) -> String:
	var same := 0
	for entry in list():
		if entry.name == wanted or entry.slot == wanted:
			same += 1
	var result := wanted if same == 0 else "%s (%d)" % [wanted, same + 1]
	while exists(result):
		same += 1
		result = "%s (%d)" % [wanted, same + 1]
	return result

static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _unvec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# Everything needed to rebuild the run; the facility must be active.
static func capture(main: Node) -> Dictionary:
	var facility: FacilityMap = main.facility
	var hud: Node = main.hud
	var player: Node3D = GameState.player
	facility.rooms.save_all_rooms()
	var inventory: Array = []
	for i in hud.items.size():
		inventory.append({"name": hud.items[i], "data": hud.item_data[i]})
	var dropped: Array = []
	for node in main.get_tree().get_nodes_in_group("pickup"):
		var item := node as Node3D
		if item == null or item.has_meta("fill_id") or item.is_queued_for_deletion():
			continue
		var record := {"name": str(item.get_meta("item_name", "")), "tempname": str(item.get_meta("tempname", "")), "state": float(item.get_meta("state", 0.0)), "cr": float(item.get_meta("cr", 1.0)), "cg": float(item.get_meta("cg", 1.0)), "cb": float(item.get_meta("cb", 1.0)), "ca": float(item.get_meta("ca", 1.0)), "pos": _vec(item.global_position)}
		if item.has_meta("inv"):
			record["inv"] = item.get_meta("inv")
		if item.has_meta("pose"):
			record["pose"] = float(item.get_meta("pose"))
		dropped.append(record)
	var data := {
		"version": VERSION,
		"seed": facility.generator.seed_value,
		"difficulty": GameState.difficulty,
		"custom": [GameState.custom_perma_death, GameState.custom_save_anywhere, GameState.custom_aggressive_npcs, GameState.custom_other_factors],
		"name": GameState.save_name,
		"used_console": GameState.used_console,
		"access_code": GameState.access_code,
		"player": {
			"pos": _vec(player.global_position), "yaw": player.rotation.y, "pitch": player.user_pitch,
			"stamina": player.stamina, "blink_timer": player.blink_timer, "blink_freq": player.blink_freq,
			"crouching": player.crouching,
		},
		"health": {"injuries": GameState.injuries, "bloodloss": GameState.bloodloss, "infect": GameState.infect, "scp1025": GameState.scp1025},
		"status": _capture_status(),
		"wearing": {
			"gas_mask": GameState.wearing_gas_mask, "vest": GameState.wearing_vest,
			"hazmat": GameState.wearing_hazmat, "night_vision": GameState.wearing_night_vision, "ring714": GameState.wearing_714, "mask1499": GameState.wearing_1499,
		},
		"inventory": inventory,
		"taken_items": GameState.taken_items.keys(),
		"door_states": GameState.door_states,
		"elevator_states": GameState.elevator_states,
		"dropped": dropped,
		"achievements": GameState.achievements.keys(),
		"rooms_found": GameState.rooms_found.keys(),
		"docs_found": GameState.docs_found.keys(),
		"decals": GrowingDecal.capture_all(main.get_tree()),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var statue: Node3D = GameState.scp173
	if statue != null:
		data["scp173"] = {"pos": _vec(statue.global_position), "active": statue.active, "idle": statue.idle, "contained": statue.contained, "target": facility.mtf.units.find(statue.target_node)}
	var units: Array = []
	for unit in facility.mtf.units:
		units.append({"pos": _vec(unit.global_position), "yaw": unit.rotation.y, "state": unit.state, "state2": unit.state2, "state3": unit.state3, "enemy": _vec(unit.enemy), "dead": unit.is_dead, "leader": facility.mtf.units.find(unit.leader), "target": ("106" if unit.target != null and unit.target == facility.scp106 else ("049" if unit.target != null and unit.target == facility.scp049 else "")), "last_seen": unit.last_seen, "frame": unit.frame})
	data["mtf"] = {"timer": facility.mtf.timer, "units": units, "camera_timer": facility.mtf.camera_check_timer, "detected": facility.mtf.player_detected}
	if facility.pocket != null and facility.pocket.player_inside:
		data["pocket"] = facility.pocket.capture()     # Save.bb keeps the player in the pocketdimension room and its EventStates
	data["sl_lever"] = {"pitch": facility.events.sl.lever_pitch, "on": facility.events.sl.lever_on, "scp008_done": facility.events.sl.scp008_done, "state2": facility.events.sl.scene_state2}
	var scp096: Node = facility.scp096
	if scp096 != null and is_instance_valid(scp096):
		data["scp096"] = {"pos": _vec(scp096.global_position), "yaw": scp096.rotation.y, "state": scp096.state, "state2": scp096.state2, "frame": scp096.frame}
	data["remote"] = {"on": facility.remote_door_on, "pitches": facility.ccont_pitches, "ccont": facility.ccont_state, "state": facility.events.room079.state, "state2": facility.events.room079.state2, "gate_a": facility.gate_a_unlocked, "gate_b": facility.gate_b_unlocked, "light": GameState.secondary_light, "femur": [facility.events.femur.state, facility.events.femur.magnets, facility.events.femur.timer, facility.events.femur.transmission, facility.events.femur.levers, facility.events.femur.platform_y], "contained": facility.contained_106, "knob914": facility.scp914_knob_roll, "r049": [facility.events.room049.state, facility.events.room049.pitches], "i427": [GameState.i427_using, GameState.i427_timer], "coins294": facility.scp294_coins, "refined": GameState.refined_items, "super": [GameState.super_man, GameState.super_man_timer], "nuke": [facility.nuke_lever_pitch if facility.nuke_lever_pitch != INF else 999.0, facility.nuke_remote_on], "coffin": [facility.events.coffin.lever_pitch, facility.events.coffin.event_state2, facility.events.coffin.guard_state, facility.coffin_is_106()], "r860": [Array(facility.forest_grid), facility.forest_seed]}
	data["start_scene"] = facility.start_scene.save_data() if facility.start_scene != null and is_instance_valid(facility.start_scene) else {"running": false}
	data["map_doors"] = _capture_map_doors(facility)
	data["lockroom096_done"] = facility._lockroom096_done
	if facility.ambient != null:
		data["ambient"] = facility.ambient.save_data()
	data["servers"] = {"state": facility.events.servers.state, "state2": facility.events.servers.state2, "state3": facility.events.servers.state3}
	var zombies: Array = []
	for zombie in facility.zombies008:
		if is_instance_valid(zombie):
			zombies.append({"pos": _vec(zombie.global_position), "yaw": zombie.rotation.y, "state": zombie.state, "hp": zombie.hp, "dead": zombie.is_dead, "idle": zombie.idle, "frame": zombie.frame, "medibay": zombie == facility.events.medibay.zombie, "kind": str(zombie.get("kind") if zombie.get("kind") != null else "008")})
	data["zombies008"] = {"list": zombies, "medibay_entered": facility.events.medibay.entered, "medibay_timer": facility.events.medibay.timer}
	var sleepers: Array = []
	for npc in facility.scp966s:
		if is_instance_valid(npc):
			sleepers.append({"pos": _vec(npc.global_position), "yaw": npc.rotation.y, "state": npc.state, "state3": npc.state3, "frame": npc.frame})
	data["scp966"] = {"state": facility.events.room966.state, "list": sleepers}
	data["mt"] = {"state": facility.events.mt.state, "generated": facility.events.mt.generated}
	data["r008"] = {"state": facility.events.room008.state, "window": facility.events.room008.window_broken}
	data["r3servers"] = facility.events.room3servers.moved_173.keys()
	var dim: Node = facility.dimension
	if dim != null:
		data["d1499"] = {"visits": dim.visits, "church": dim.church_state, "prev": _vec(dim.prev_position), "last": _vec(dim.last_position) if dim.last_position != Vector3.INF else [], "inside": dim.inside}
	var scp049: Node = facility.scp049
	if scp049 != null and is_instance_valid(scp049):
		data["scp049"] = {"pos": _vec(scp049.global_position), "idle": scp049.idle, "state": scp049.state, "yaw": scp049.rotation.y}
	var scp106: Node = facility.scp106
	if scp106 != null and is_instance_valid(scp106):
		data["scp106"] = {"pos": _vec(scp106.global_position), "state": scp106.state, "yaw": scp106.rotation.y}
	data["actors"] = _capture_actors(main, facility)
	return data

const STATUS_FIELDS := ["blink_effect", "blink_effect_timer", "eye_stuck", "eye_irritation", "stamina_effect", "stamina_effect_timer", "vomit_timer", "vomit_prev_injuries", "vomit_prev_bloodloss", "camera_shake_timer", "death_timer", "heal_timer", "blur_timer", "sanity"]

static func _capture_status() -> Dictionary:
	var out := {"vomit": GameState.vomit, "death_msg": GameState.death_msg}
	for field in STATUS_FIELDS:
		out[field] = GameState.get(field)
	return out

# Old saves have no "status": the effects keep their defaults.
static func _restore_status(saved: Dictionary) -> void:
	for field in STATUS_FIELDS:
		if saved.has(field):
			GameState.set(field, float(saved[field]))
	GameState.vomit = bool(saved.get("vomit", false))
	GameState.death_msg = str(saved.get("death_msg", ""))

# The NPCs that events make (the 035 host and tentacles, 939's specimens, 066, 372, 513-1, the vision's officer, the corridor's corpse and
# guard, and whatever an ambient event keeps in its `_nodes`): each node writes its own save_state(); `links` keeps which event slot held
# which of them, so that the event finds its actor again.
const ACTOR_GROUPS := ["scp939", "scp066", "scp372", "scp513_1", "tentacle", "scp035_host", "scp1123_officer"]

static func _capture_actors(main: Node, facility: FacilityMap) -> Dictionary:
	var nodes: Array = []
	var uid_of := {}
	var add := func(node: Variant) -> void:
		if is_instance_valid(node) and node is Node3D and node.has_method("save_state") and not node.is_queued_for_deletion() and not uid_of.has(node.get_instance_id()):
			uid_of[node.get_instance_id()] = nodes.size()
			nodes.append(node)
	for group in ACTOR_GROUPS:
		for node in main.get_tree().get_nodes_in_group(group):
			add.call(node)
	for human in facility.humans:
		if is_instance_valid(human) and human.has_meta("role"):
			add.call(human)
	var links := {}
	if facility.ambient != null:
		for key in facility.ambient._nodes:
			var held: Dictionary = facility.ambient._nodes[key]
			for slot in held:
				add.call(held[slot])
				if is_instance_valid(held[slot]) and held[slot] is Node and uid_of.has(held[slot].get_instance_id()):
					if not links.has(key):
						links[key] = {}
					links[key][slot] = uid_of[held[slot].get_instance_id()]
	var records: Array = []
	for node in nodes:
		var record: Dictionary = node.save_state()
		var groups: Array = []
		for group in node.get_groups():
			if not str(group).begins_with("_"):
				groups.append(str(group))
		record["base"] = node.get_class()
		record["script"] = node.get_script().resource_path
		record["pos"] = _vec(node.global_position)
		record["yaw"] = node.rotation.y
		record["groups"] = groups
		records.append(record)
	return {"list": records, "links": links}

# The save is a file the player can edit or swap: only the game's own scripts on 3D node classes are made.
static func _actor_allowed(base: String, script_path: String) -> bool:
	return script_path.begins_with("res://scripts/") and script_path.ends_with(".gd") and ClassDB.class_exists(base) and ClassDB.is_parent_class(base, "Node3D")

static func _restore_actors(main: Node, facility: FacilityMap, data: Dictionary) -> void:
	for group in ACTOR_GROUPS:
		for old in main.get_tree().get_nodes_in_group(group):
			if old.is_in_group("human_npc"):
				facility.remove_human(old)
			else:
				old.queue_free()
	var made: Array = []
	for record in data.get("list", []):
		var at := _unvec(record.pos)
		var node: Node3D
		if str(record.script).ends_with("human_npc.gd"):
			node = facility.spawn_human(int(record.kind), at, int(record.texture), str(record.model))
		else:
			var base := str(record.base)
			var script_path := str(record.script)
			if not _actor_allowed(base, script_path):
				push_warning("Save: actor skipped (%s on %s)" % [script_path, base])
				made.append(null)      # keeps the slots that `links` counts
				continue
			node = ClassDB.instantiate(base)
			node.set_script(load(script_path))
			facility.get_parent().add_child(node)
			node.global_position = at
		node.rotation.y = float(record.yaw)
		node.load_state(record)
		for group in record.groups:
			node.add_to_group(str(group))
		made.append(node)
	var links: Dictionary = data.get("links", {})
	for key in links:
		var held: Dictionary = facility.ambient._nodes.get(key, {})
		for slot in links[key]:
			var index := int(links[key][slot])
			if index >= 0 and index < made.size() and made[index] != null:
				held[slot] = made[index]
		facility.ambient._nodes[key] = held

static func _capture_map_doors(facility: FacilityMap) -> Dictionary:
	var out := {}
	for edge in facility.rooms.doors:
		var door: Node3D = facility.rooms.doors[edge]
		if is_instance_valid(door):
			out[str(edge)] = {"open": door.open, "locked": door.locked, "auto_close": door.auto_close}
	return out

# Old saves have no "map_doors": the doors keep what the generator gave them.
static func _restore_map_doors(facility: FacilityMap, data: Dictionary) -> void:
	var saved: Dictionary = data.get("map_doors", {})
	for edge in saved:
		var door: Node3D = facility.rooms.doors.get(str(edge))
		if door == null or not is_instance_valid(door):
			continue
		var state: Dictionary = saved[edge]
		door.reset_to(bool(state.get("open", false)), bool(state.get("locked", false)))
		door.auto_close = bool(state.get("auto_close", false))

# Called after reset_run and before the facility is entered: run state the rooms read as they
# are built (taken items, door and elevator states, the access code).
static func apply_before_rooms(data: Dictionary) -> void:
	GameState.difficulty = int(data.get("difficulty", 1))
	var custom: Array = data.get("custom", [])
	if custom.size() == 4:
		GameState.custom_perma_death = bool(custom[0])
		GameState.custom_save_anywhere = bool(custom[1])
		GameState.custom_aggressive_npcs = bool(custom[2])
		GameState.custom_other_factors = int(custom[3])
	GameState.save_name = str(data.get("name", "untitled"))
	GameState.used_console = bool(data.get("used_console", false))
	GameState.access_code = str(data.get("access_code", GameState.access_code))
	GameState.taken_items = {}
	for key in data.get("taken_items", []):
		GameState.taken_items[str(key)] = true
	GameState.door_states = data.get("door_states", {}).duplicate(true)
	GameState.elevator_states = data.get("elevator_states", {}).duplicate(true)
	for key in data.get("achievements", []):
		GameState.achievements[str(key)] = true
	for key in data.get("rooms_found", []):
		GameState.rooms_found[str(key)] = true
	for key in data.get("docs_found", []):
		GameState.docs_found[str(key)] = true

# Called once the facility is active: the player, what they carry and the NPCs.
static func apply_after_rooms(main: Node, data: Dictionary) -> void:
	var facility: FacilityMap = main.facility
	_restore_event_nodes(main, facility)
	_restore_map_doors(facility, data)
	_restore_player(main, facility, data)
	_restore_npcs(main, facility, data)
	facility.resume_start_scene(data.get("start_scene", {}))
	GrowingDecal.restore_all(main.world, data.get("decals", []))

# The event state the rooms read as they are built: written between the map generation and the room build.
static func restore_event_state(facility: FacilityMap, data: Dictionary) -> void:
	var lever_data: Dictionary = data.get("sl_lever", {})
	facility.events.sl.lever_pitch = float(lever_data.get("pitch", 10.0))
	facility.events.sl.lever_on = bool(lever_data.get("on", true))
	facility.events.sl.scp008_done = bool(lever_data.get("scp008_done", false))
	facility.events.sl.scene_state2 = float(lever_data.get("state2", 0.0))
	var r008: Dictionary = data.get("r008", {})
	facility.events.room008.state = int(r008.get("state", 2 if facility.events.sl.scp008_done else 0))
	facility.events.room008.window_broken = bool(r008.get("window", false))
	facility.events.room3servers.moved_173 = {}
	for key in data.get("r3servers", []):
		facility.events.room3servers.moved_173[str(key)] = true
	var remote: Dictionary = data.get("remote", {})
	facility.remote_door_on = bool(remote.get("on", true))
	facility.ccont_pitches = remote.get("pitches", [10.0, 10.0, 10.0]).duplicate()
	facility.ccont_state = float(remote.get("ccont", 0.0))
	facility.events.room079.state = float(remote.get("state", 0.0))
	if facility.events.room079.state < 3.0:
		facility.events.room079.state = 0.0      # the guard is not saved: the room places him again
	facility.events.room079.state2 = float(remote.get("state2", 0.0))
	facility.gate_a_unlocked = bool(remote.get("gate_a", false))
	facility.gate_b_unlocked = bool(remote.get("gate_b", false))
	GameState.secondary_light = float(remote.get("light", 1.0))
	var femur: Array = remote.get("femur", [])
	if femur.size() == 6:
		facility.events.femur.state = int(femur[0])
		facility.events.femur.magnets = bool(femur[1])
		facility.events.femur.timer = float(femur[2])
		facility.events.femur.transmission = bool(femur[3])
		facility.events.femur.levers = femur[4].duplicate()
		facility.events.femur.platform_y = float(femur[5])
	facility.contained_106 = bool(remote.get("contained", false))
	facility.scp914_knob_roll = float(remote.get("knob914", 0.0))
	facility.scp294_coins = int(remote.get("coins294", 0))
	var coffin: Array = remote.get("coffin", [10.0, 0, 0])
	facility.events.coffin.lever_pitch = float(coffin[0])
	facility.events.coffin.event_state2 = int(coffin[1])
	facility.events.coffin.guard_state = int(coffin[2])
	var r860: Array = remote.get("r860", [[], 0])
	facility.forest_grid = PackedInt32Array()
	for cell in r860[0]:
		facility.forest_grid.append(int(cell))
	facility.forest_seed = int(r860[1])
	facility.events.room860.state = 0.0
	var r049: Array = remote.get("r049", [0.0, [81.0, -11.0]])
	facility.events.room049.state = float(r049[0]) if float(r049[0]) >= 0.0 else 70.0 * 241.0      # the capture scene is not resumable
	facility.events.room049.pitches = r049[1].duplicate()
	var locket: Array = remote.get("i427", [false, 0.0])
	GameState.i427_using = bool(locket[0])
	GameState.i427_timer = float(locket[1])
	GameState.refined_items = int(remote.get("refined", 0))
	var fast: Array = remote.get("super", [false, 0.0])
	GameState.super_man = bool(fast[0])
	GameState.super_man_timer = float(fast[1])
	var nuke: Array = remote.get("nuke", [999.0, false])
	facility.nuke_lever_pitch = INF if float(nuke[0]) >= 999.0 else float(nuke[0])
	facility.nuke_remote_on = bool(nuke[1])

# Give the rooms' levers the loaded positions (they copy their own back every frame).
static func _restore_event_nodes(main: Node, facility: FacilityMap) -> void:
	for stray_lever in main.get_tree().get_nodes_in_group("sl_lever"):
		stray_lever.pitch = facility.events.sl.lever_pitch
	for key in facility.rooms.built:
		var built: Node = facility.rooms.built[key]
		if not is_instance_valid(built) or not "extras" in built or built.extras == null or not "levers" in built.extras:
			continue
		var pitches: Array = []
		match str(built.room_name):
			"room2ccont":
				pitches = facility.ccont_pitches
			"room106":
				pitches = facility.events.femur.levers
			"room049":
				pitches = facility.events.room049.pitches
			"room2nuke":
				if facility.nuke_lever_pitch != INF:
					pitches = [facility.nuke_lever_pitch]
		for n in mini(pitches.size(), built.extras.levers.size()):
			built.extras.levers[n].pitch = float(pitches[n])

static func _restore_player(main: Node, facility: FacilityMap, data: Dictionary) -> void:
	var hud: Node = main.hud
	hud.nv_picture = ""
	var player: CharacterBody3D = GameState.player
	var saved: Dictionary = data.player
	var at := _unvec(saved.pos)
	var in_1499: bool = int(data.wearing.get("mask1499", 0)) > 0 and at.y > 700.0
	GameState.wearing_1499 = int(data.wearing.get("mask1499", 0))
	player.velocity = Vector3.ZERO
	player.global_position = at
	facility.after_teleport()
	if data.has("pocket") and facility.pocket != null:
		facility.pocket.restore(data.pocket, player)
	if facility.dimension != null:
		facility.dimension.reset()
		var saved_dim: Dictionary = data.get("d1499", {})
		var last: Array = saved_dim.get("last", [])
		facility.dimension.last_position = _unvec(last) if last.size() == 3 else Vector3.INF
		facility.dimension.visits = int(saved_dim.get("visits", 0))
		facility.dimension.church_state = float(saved_dim.get("church", 0.0))
	if in_1499 and facility.dimension != null:
		var d: Dictionary = data.get("d1499", {})
		facility.dimension.visits = int(d.get("visits", 0))
		facility.dimension.church_state = float(d.get("church", 0.0))
		facility.dimension.prev_position = _unvec(d.get("prev", _vec(at)))
		facility.dimension.resume(player)
	player.rotation.y = float(saved.yaw)
	player.user_pitch = float(saved.pitch)
	player.camera.rotation.x = -deg_to_rad(player.user_pitch)
	player.stamina = float(saved.stamina)
	player.blink_timer = float(saved.blink_timer)
	player.blink_freq = float(saved.blink_freq)
	player.crouching = bool(saved.crouching)
	GameState.injuries = float(data.health.injuries)
	GameState.bloodloss = float(data.health.bloodloss)
	GameState.infect = float(data.health.get("infect", 0.0))
	_restore_status(data.get("status", {}))
	var illnesses: Array = data.health.get("scp1025", [])
	for i in mini(illnesses.size(), GameState.scp1025.size()):
		GameState.scp1025[i] = float(illnesses[i])
	GameState.wearing_gas_mask = int(data.wearing.gas_mask)
	GameState.wearing_vest = int(data.wearing.vest)
	GameState.wearing_hazmat = int(data.wearing.hazmat)
	GameState.wearing_night_vision = int(data.wearing.night_vision)
	GameState.wearing_714 = bool(data.wearing.get("ring714", false))
	GameState.wearing_1499 = int(data.wearing.get("mask1499", 0))
	var inventory: Array = data.inventory
	for i in mini(inventory.size(), hud.items.size()):
		hud.items[i] = str(inventory[i].name)
		hud.item_data[i] = inventory[i].data if inventory[i].data is Dictionary else {}
	var pocket_note := _pocket_note(facility)
	for entry in data.get("dropped", []):
		# saves from before the note had a fill_id kept the pocket's own note (one more per save and load) as dropped
		# (across the floor only: the saved one had fallen there, the map's own is made 0.5 above it)
		if pocket_note != null and str(entry.name) == "Burnt Note" and _flat_distance(_unvec(entry.pos), pocket_note.global_position) < 0.3:
			continue
		var pickup := RoomFill.make_pickup(str(entry.name), str(entry.tempname), entry)
		pickup.set_meta("state", float(entry.get("state", 0.0)))
		main.world.add_child(pickup)
		pickup.global_position = _unvec(entry.pos)

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func _pocket_note(facility: FacilityMap) -> Node3D:
	if facility.pocket == null:
		return null
	for node in facility.pocket.get_children():
		if node is Node3D and str(node.get_meta("fill_id", "")) == FacilityMap.PocketDimension.NOTE_ID:
			return node
	return null

static func _restore_npcs(main: Node, facility: FacilityMap, data: Dictionary) -> void:
	var statue: Node3D = GameState.scp173
	if statue != null and data.has("scp173"):
		statue.velocity = Vector3.ZERO
		statue.global_position = _unvec(data.scp173.pos)
		statue.floor_y = statue.global_position.y
		statue.active = bool(data.scp173.active)
		statue.idle = int(data.scp173.get("idle", 0))
		statue.contained = bool(data.scp173.get("contained", false))
	for old_unit in facility.mtf.units.duplicate():
		facility.mtf.remove(old_unit)
	if data.has("mtf"):
		facility.mtf.timer = float(data.mtf.timer)
		facility.mtf.camera_check_timer = float(data.mtf.get("camera_timer", 0.0))
		facility.mtf.player_detected = bool(data.mtf.get("detected", false))
		var made: Array = []
		for entry in data.mtf.units:
			var unit: Node = facility.mtf.spawn(_unvec(entry.pos))
			unit.rotation.y = float(entry.yaw)
			unit.angle = unit.rotation.y
			unit.state = int(entry.state)
			unit.state2 = float(entry.state2)
			unit.state3 = float(entry.state3)
			unit.enemy = _unvec(entry.enemy)
			unit.is_dead = bool(entry.dead)
			unit.last_seen = float(entry.last_seen)
			unit.set_frame(float(entry.frame))
			made.append(unit)
		for i in made.size():
			var leader_index := int(data.mtf.units[i].leader)
			if leader_index >= 0 and leader_index < made.size():
				made[i].leader = made[leader_index]
		if statue != null and data.has("scp173"):
			var holder := int(data.scp173.get("target", -1))
			if holder >= 0 and holder < made.size():
				statue.target_node = made[holder]
	if data.has("scp096"):
		var shy: Node = facility.spawn_096(_unvec(data.scp096.pos), int(data.scp096.state), float(data.scp096.yaw))
		shy.state2 = float(data.scp096.state2)
		shy.frame = float(data.scp096.frame)
	facility._lockroom096_done = bool(data.get("lockroom096_done", false))
	if facility.ambient != null and data.has("ambient"):
		facility.ambient.load_data(data.ambient)
	if data.has("actors"):
		_restore_actors(main, facility, data.actors)
	if data.has("servers"):
		facility.events.servers.state = float(data.servers.state)
		if facility.events.servers.state > 0.0 and facility.events.servers.state < 70.0 * 45.0:
			facility.events.servers.state = 70.0 * 45.0      # the scene is not saved: it counts as over
		facility.events.servers.state2 = float(data.servers.state2)
		facility.events.servers.state3 = float(data.servers.state3)
	for old_zombie in facility.zombies008.duplicate():
		facility.remove_zombie008(old_zombie)
	if data.has("zombies008"):
		facility.events.medibay.entered = bool(data.zombies008.get("medibay_entered", false))
		facility.events.medibay.timer = float(data.zombies008.get("medibay_timer", 0.0))
		for entry in data.zombies008.list:
			var zombie: Node = facility.spawn_zombie049(_unvec(entry.pos), int(entry.state)) if str(entry.get("kind", "008")) == "049-2" else facility.spawn_zombie008(_unvec(entry.pos), int(entry.state))
			zombie.rotation.y = float(entry.yaw)
			zombie.hp = float(entry.hp)
			zombie.is_dead = bool(entry.dead)
			zombie.idle = float(entry.idle)
			zombie.set_frame(float(entry.frame))
			if bool(entry.get("medibay", false)):
				facility.events.medibay.zombie = zombie
	if data.has("mt"):
		facility.events.mt.state = int(data.mt.state)
		facility.events.mt.generated = bool(data.mt.generated)
	for old_sleeper in facility.scp966s.duplicate():
		facility.remove_scp966(old_sleeper)
	if data.has("scp966"):
		facility.events.room966.state = int(data.scp966.state)
		for entry in data.scp966.list:
			var sleeper: Node = facility.spawn_scp966(_unvec(entry.pos))
			sleeper.rotation.y = float(entry.yaw)
			sleeper.state = int(entry.state)
			sleeper.state3 = float(entry.state3)
			sleeper.set_frame(float(entry.frame))
	if data.has("scp106"):
		var old_man: Node = facility.spawn_106(float(data.scp106.state))
		old_man.global_position = _unvec(data.scp106.pos)
		old_man.rotation.y = float(data.scp106.yaw)
	if data.has("scp049"):
		var npc: Node = facility.spawn_049(float(data.scp049.idle))
		npc.state = int(data.scp049.state)
		if (npc.state == 5 or npc.state == 0) and not facility.events.sl.waiting_049(npc):
			npc.state = 2    # the scene's walk is not resumable: he carries on hunting
		npc.global_position = _unvec(data.scp049.pos)
		npc.rotation.y = float(data.scp049.yaw)
	# units that were backing away from 106 or 049 look at them again
	if data.has("mtf"):
		for i in mini(facility.mtf.units.size(), data.mtf.units.size()):
			match str(data.mtf.units[i].get("target", "")):
				"106":
					facility.mtf.units[i].target = facility.scp106
				"049":
					facility.mtf.units[i].target = facility.scp049
