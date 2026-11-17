extends RefCounted
# What SCP-914 does to an item (Main.bb Use914). `refine` returns a plan, the room carries it out:
#   remove    the item is destroyed (RemoveItem)
#   outputs   [[name, tempname, state], ...] new items at the output booth
#   decal     [decal id, size, alpha, raised] a stain on the output floor (CreateDecal 0 / 3 / 7)
#   npc       "008" (a zombie) or "1499" (the 1499 inhabitant, not in the game) rises at the output
#   explode   ExplosionTimer = 135
#   offset    the outputs appear this far (Blitz world axes) from the output pivot (the cigarettes)
#   panel     the metal panel / 148 ingot: look for a nearby item to fuse with (RefineWithPanel)
#   sound     a sound played everywhere (SCP-513's)
# Anything not listed is simply carried over to the output booth (Default).
# Rand(n) of Blitz is 1..n; `difficulty` is 0 Safe, 1 Euclid, 2 Keter (SelectedDifficulty\otherFactors).

const ROUGH := "rough"
const COARSE := "coarse"
const ONE := "1:1"
const FINE := "fine"
const VERY_FINE := "very fine"

static func _rand(n: int) -> int:
	return randi_range(1, n)

static func _out(name: String, tempname: String, state: float = 0.0) -> Array:
	return [name, tempname, state]

static func _plan(remove: bool = false, outputs: Array = [], decal: Array = []) -> Dictionary:
	return {"remove": remove, "outputs": outputs, "decal": decal, "npc": "", "explode": false, "offset": Vector3.ZERO, "panel": false, "sound": ""}

static func _stain(small: bool = true) -> Array:
	return [0, 0.12, 1.0, 0.005] if small else [0, 0.2, 0.8, 0.010]

static func _is_rough(setting: String) -> bool:
	return setting == ROUGH or setting == COARSE

# The cards "fine" and "very fine" chances (1 in n).
static func _card_chance(difficulty: int, easy: int, normal: int, hard: int) -> int:
	return [easy, normal, hard][clampi(difficulty, 0, 2)]

# Omni or Mastercard for the level 5 / very fine cards: Rand(0, (MAXACHIEVEMENTS - 1) * k - (found - 1) * 3) = 0
static func _omni_or_master(difficulty: int, achievements_found: int) -> Array:
	var k: int = [3, 4, 5][clampi(difficulty, 0, 2)]
	var top: int = (GameState.MAX_ACHIEVEMENTS - 1) * k - (achievements_found - 1) * 3
	if randi_range(0, maxi(top, 0)) == 0:
		return _out("Key Card Omni", "key6")
	return _out("Mastercard", "misc")

static func refine(item_name: String, tempname: String, setting: String, difficulty: int = 1, achievements_found: int = 0) -> Dictionary:
	match item_name:
		"Gas Mask", "Heavy Gas Mask":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain())
				ONE:
					return _plan()
				_:
					return _plan(true, [_out("Gas Mask", "supergasmask")])
		"SCP-1499":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain())
				ONE:
					return _plan(true, [_out("Gas Mask", "gasmask")])
				FINE:
					return _plan(true, [_out("SCP-1499", "super1499")])
				_:
					var plan := _plan(true)
					plan.npc = "1499"
					return plan
		"Ballistic Vest":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain())
				ONE:
					return _plan()
				FINE:
					return _plan(true, [_out("Heavy Ballistic Vest", "finevest")])
				_:
					return _plan(true, [_out("Bulky Ballistic Vest", "veryfinevest")])
		"Clipboard":
			if _is_rough(setting):
				return _plan(true, [], [7, 0.12, 1.0, 0.005])
			return _plan()
		"Cowbell":
			if _is_rough(setting):
				return _plan(true, [], _stain(false))
			return _plan()
		"Night Vision Goggles":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain())
				ONE:
					return _plan()
				FINE:
					return _plan(true, [_out("Night Vision Goggles", "finenvgoggles")])
				_:
					return _plan(true, [_out("Night Vision Goggles", "supernv", 1000.0)])
		"Metal Panel", "SCP-148 Ingot":
			if setting == ROUGH or setting == COARSE:
				return _plan(true, [_out("SCP-148 Ingot", "scp148ingot")])
			var plan := _plan()
			plan.panel = true
			return plan
		"Severed Hand", "Black Severed Hand":
			if _is_rough(setting):
				return _plan(true, [], [3, 0.12, 1.0, 0.005])
			if item_name == "Severed Hand":
				return _plan(true, [_out("Black Severed Hand", "hand2")])
			return _plan(true, [_out("Severed Hand", "hand")])
		"First Aid Kit", "Blue First Aid Kit":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain())
				ONE:
					if _rand(2) == 1:
						return _plan(true, [_out("Blue First Aid Kit", "firstaid2")])
					return _plan(true, [_out("First Aid Kit", "firstaid")])
				FINE:
					return _plan(true, [_out("Small First Aid Kit", "finefirstaid")])
				_:
					return _plan(true, [_out("Strange Bottle", "veryfinefirstaid")])
		"Level 1 Key Card", "Level 2 Key Card", "Level 3 Key Card", "Level 4 Key Card", "Level 5 Key Card", "Key Card":
			return _key_card(item_name, setting, difficulty, achievements_found)
		"Key Card Omni":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], [0, 0.07, 1.0, 0.005])
				ONE:
					return _plan(true, [_out("Mastercard", "misc") if _rand(2) == 1 else _out("Playing Card", "misc")])
				_:
					return _plan(true, [_out("Key Card Omni", "key6")])
		"Playing Card", "Coin", "Quarter":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], [0, 0.07, 1.0, 0.005])
				ONE:
					return _plan(true, [_out("Level 1 Key Card", "key1")])
				_:
					return _plan(true, [_out("Level 2 Key Card", "key2")])
		"Mastercard":
			match setting:
				ROUGH:
					return _plan(true, [], [0, 0.07, 1.0, 0.005])
				COARSE:
					return _plan(true, [_out("Quarter", "25ct"), _out("Quarter", "25ct"), _out("Quarter", "25ct"), _out("Quarter", "25ct")])
				ONE:
					return _plan(true, [_out("Level 1 Key Card", "key1")])
				_:
					return _plan(true, [_out("Level 2 Key Card", "key2")])
		"S-NAV 300 Navigator", "S-NAV 310 Navigator", "S-NAV Navigator", "S-NAV Navigator Ultimate":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [_out("Electronical components", "misc")])
				ONE:
					return _plan(true, [_out("S-NAV Navigator", "nav", 100.0)])
				FINE:
					return _plan(true, [_out("S-NAV 310 Navigator", "nav", 100.0)])
				_:
					return _plan(true, [_out("S-NAV Navigator Ultimate", "nav", 101.0)])
		"Radio Transceiver":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [_out("Electronical components", "misc")])
				ONE:
					return _plan(true, [_out("Radio Transceiver", "18vradio", 100.0)])
				FINE:
					return _plan(true, [_out("Radio Transceiver", "fineradio", 101.0)])
				_:
					return _plan(true, [_out("Radio Transceiver", "veryfineradio", 101.0)])
		"SCP-513":
			if _is_rough(setting):
				var plan := _plan(true, [], _stain(false))
				plan.sound = "SFX/SCP/513/914Refine.ogg"
				plan.remove_513_1 = true
				return plan
			return _plan(true, [_out("SCP-513", "scp513")])
		"Some SCP-420-J", "Cigarette":
			var plan := _plan(true)
			match setting:
				ROUGH, COARSE:
					plan.decal = _stain(false)
				ONE:
					plan.outputs = [_out("Cigarette", "cigarette")]
					plan.offset = Vector3(1.5, 0.5, 1.0)
				FINE:
					plan.outputs = [_out("Joint", "420s")]
					plan.offset = Vector3(1.5, 0.5, 1.0)
				_:
					plan.outputs = [_out("Smelly Joint", "420s")]
					plan.offset = Vector3(1.5, 0.5, 1.0)
			return plan
		"9V Battery", "18V Battery", "Strange Battery":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain(false))
				ONE:
					return _plan(true, [_out("18V Battery", "18vbat")])
				_:
					return _plan(true, [_out("Strange Battery", "killbat")])
		"ReVision Eyedrops", "RedVision Eyedrops", "Eyedrops":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain(false))
				ONE:
					return _plan(true, [_out("RedVision Eyedrops", "eyedrops")])
				FINE:
					return _plan(true, [_out("Eyedrops", "fineeyedrops")])
				_:
					return _plan(true, [_out("Eyedrops", "supereyedrops")])
		"Hazmat Suit":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], _stain(false))
				ONE:
					return _plan(true, [_out("Hazmat Suit", "hazmatsuit")])
				_:
					return _plan(true, [_out("Hazmat Suit", "hazmatsuit2")])
		"Syringe":
			return _syringe(tempname, setting)
		"SCP-500-01", "Upgraded pill", "Pill":
			match setting:
				ROUGH, COARSE:
					return _plan(false, [], _stain(false))        # the pill is left where it was (RemoveItem sits in the other branches)
				ONE:
					return _plan(true, [_out("Pill", "pill")])
				FINE:
					return _plan(true, [_out("SCP-427", "scp427") if not _has_427() else _out("Upgraded pill", "scp500death")])
				_:
					return _plan(true, [_out("Upgraded pill", "scp500death")])
	match tempname:
		"cup":
			return _cup(setting)
		"paper":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], [7, 0.12, 1.0, 0.005])
				ONE:
					var docs := ["Document SCP-106", "Document SCP-079", "Document SCP-173", "Document SCP-895", "Document SCP-682", "Document SCP-860"]
					return _plan(true, [_out(docs[_rand(6) - 1], "paper")])
				_:
					return _plan(true, [_out("Origami", "misc")])
	return _plan()

# Case "fine" of the SCP-500 pill: the 427 is only made once (an item of that name anywhere, picked up or not).
static func _has_427() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for pickup in tree.get_nodes_in_group("pickup"):
		if str(pickup.get_meta("tempname", "")) == "scp427":
			return true
	var hud := tree.get_first_node_in_group("hud")
	if hud != null:
		for data in hud.item_data:
			if str(data.get("tempname", "")) == "scp427":
				return true
	return false

static func _syringe(tempname: String, setting: String) -> Dictionary:
	match tempname:
		"syringe":
			match setting:
				ROUGH, COARSE:
					return _plan(true, [], [0, 0.07, 1.0, 0.005])
				ONE:
					return _plan(true, [_out("Small First Aid Kit", "finefirstaid")])
				FINE:
					return _plan(true, [_out("Syringe", "finesyringe")])
				_:
					return _plan(true, [_out("Syringe", "veryfinesyringe")])
		"finesyringe":
			match setting:
				ROUGH:
					return _plan(true, [], [0, 0.07, 1.0, 0.005])
				COARSE:
					return _plan(true, [_out("First Aid Kit", "firstaid")])
				ONE:
					return _plan(true, [_out("Blue First Aid Kit", "firstaid2")])
				_:
					return _plan(true, [_out("Syringe", "veryfinesyringe")])
		"veryfinesyringe":
			if setting == VERY_FINE:
				var plan := _plan(true)
				plan.npc = "008"
				return plan
			return _plan(true, [_out("Electronical components", "misc")])
	return _plan(true)

static func _cup(setting: String) -> Dictionary:
	match setting:
		ROUGH, COARSE:
			return _plan(true, [], _stain(false))
		ONE:
			return _plan(true, [_out("cup", "cup")])          # the room gives it the opposite colour
		FINE:
			return _plan(true, [_out("cup", "cup", 1.0)])
		_:
			var plan := _plan(true, [_out("cup", "cup", 2.0)])
			plan.explode = _rand(5) == 1
			return plan

static func _key_card(item_name: String, setting: String, difficulty: int, achievements_found: int) -> Dictionary:
	match setting:
		ROUGH, COARSE:
			return _plan(true, [], [0, 0.07, 1.0, 0.005])
		ONE:
			return _plan(true, [_out("Playing Card", "misc")])
		VERY_FINE:
			return _plan(true, [_omni_or_master(difficulty, achievements_found)])
	# fine
	match item_name:
		"Level 1 Key Card":
			var master := _card_chance(difficulty, 0, 5, 4)
			if master > 0 and _rand(master) == 1:
				return _plan(true, [_out("Mastercard", "misc")])
			return _plan(true, [_out("Level 2 Key Card", "key2")])
		"Level 2 Key Card":
			var master := _card_chance(difficulty, 0, 4, 3)
			if master > 0 and _rand(master) == 1:
				return _plan(true, [_out("Mastercard", "misc")])
			return _plan(true, [_out("Level 3 Key Card", "key3")])
		"Level 3 Key Card":
			if _rand(_card_chance(difficulty, 10, 15, 20)) == 1:
				return _plan(true, [_out("Level 4 Key Card", "key4")])
			return _plan(true, [_out("Playing Card", "misc")])
		"Level 4 Key Card":
			var master := _card_chance(difficulty, 0, 4, 3)
			if master > 0 and _rand(master) == 1:
				return _plan(true, [_out("Mastercard", "misc")])
			return _plan(true, [_out("Level 5 Key Card", "key5")])
		"Level 5 Key Card":
			return _plan(true, [_omni_or_master(difficulty, achievements_found)])
	return _plan(true)

# SCP-148 and its panel with a gas mask, vest or hazmat suit lying within 180 units: the item that fuses with it
# (by tempname), or "" when it is something else.
static func panel_fusion(other_tempname: String) -> Array:
	match other_tempname:
		"gasmask", "supergasmask":
			return _out("Heavy Gas Mask", "gasmask3")
		"vest":
			return _out("Heavy Ballistic Vest", "finevest")
		"hazmatsuit", "hazmatsuit2":
			return _out("Heavy Hazmat Suit", "hazmatsuit3")
	return []
