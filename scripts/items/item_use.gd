extends Node
# Using the selected inventory item (Main.bb DrawGUI, "Select SelectedItem\itemtemplate\tempname").
# Selecting an item (keys 1-0) is what the original's click does; the rules below then run.

const Scp294Data = preload("res://scripts/items/scp294_data.gd")

const PAPER := ["paper", "ticket", "oldpaper"]
const GAS_MASKS := ["gasmask", "supergasmask", "gasmask3"]
const HAZMATS := ["hazmatsuit", "hazmatsuit2", "hazmatsuit3"]
const VESTS := ["vest", "finevest"]
const FIRST_AID := ["firstaid", "finefirstaid", "firstaid2"]
const EYE_DROPS := ["eyedrops", "fineeyedrops", "supereyedrops"]
const NIGHT_VISION := {"nvgoggles": 1, "supernv": 2, "finenvgoggles": 3}

var hud: CanvasLayer
var tempname := ""
var item_name := ""
var progress := 0.0          # SelectedItem\state, 0..100
var bottle_roll := 0           # tests: which of the strange bottle's five outcomes (0 = random)

# True while the item being used holds the player still (the progress-bar items).
func locks_movement() -> bool:
	if tempname == "scp1499" or tempname == "super1499":
		return GameState.wearing_hazmat == 0
	if tempname in VESTS:
		return true
	if tempname in HAZMATS:
		return GameState.wearing_vest == 0
	if tempname in FIRST_AID:
		return not (GameState.bloodloss == 0.0 and GameState.injuries == 0.0) and _can_use(false, true, true, false)
	return false

func on_selected() -> void:
	progress = 0.0
	hud.hide_item_ui()
	var index: int = hud.selected
	if index < 0:
		tempname = ""
		item_name = ""
		return
	tempname = hud.selected_tempname()
	item_name = hud.items[index]
	hud.show_item_icon(_icon_of(index))
	if tempname in ["radio", "18vradio", "fineradio", "veryfineradio", "nav", "scp1025"]:
		hud.hide_item_ui()       # these draw themselves (the radio, the navigator, the page)
	if tempname in PAPER:
		_show_document()
	elif tempname in GAS_MASKS:
		_use_gas_mask()
	elif tempname in EYE_DROPS:
		_use_eye_drops()
	elif NIGHT_VISION.has(tempname):
		_use_night_vision()
	elif tempname in FIRST_AID:
		if GameState.bloodloss == 0.0 and GameState.injuries == 0.0:
			_done("You do not need to use a first aid kit right now.")
		elif not _can_use(false, true, true):
			_done("")
	elif tempname == "scp500":
		# Main.bb Case "scp500": the pill cures the infection and restores the stamina
		if _can_use(false, false, true):
			hud.message("You swallowed the pill. Your nausea is fading." if GameState.infect > 0.0 else "You swallowed the pill.", 7.0)
			GameState.give_achievement("500")
			GameState.death_timer = 0.0
			GameState.infect = 0.0
			for i in 6:
				GameState.scp1025[i] = 0.0
			if GameState.player != null:
				GameState.player.stamina = 100.0
			if GameState.stamina_effect > 1.0:
				GameState.stamina_effect = 1.0
				GameState.stamina_effect_timer = 0.0
			hud.remove_selected()
		else:
			hud.deselect()
	elif tempname == "cup":
		_drink_cup()
	elif tempname in ["syringe", "finesyringe", "veryfinesyringe"]:
		_use_syringe()
	elif tempname == "veryfinefirstaid":
		_use_strange_bottle()
	elif tempname == "scp1025":
		_use_1025()
	elif tempname == "clipboard" or tempname == "wallet":
		hud.open_container(index)
	elif tempname == "scp513":
		Sfx.play_global(hud, "SFX/SCP/513/Bell1.ogg")
		if hud.get_tree().get_first_node_in_group("scp513_1") == null:
			var ghost := Node3D.new()
			ghost.set_script(load("res://scripts/npc/scp_513_1.gd"))
			hud.get_tree().get_first_node_in_group("facility").get_parent().add_child(ghost)
		hud.deselect()
	elif tempname == "cigarette":
		_use_cigarette()
	elif tempname == "420" or tempname == "420s":
		_use_joint()
	elif tempname == "scp427":
		GameState.i427_using = not GameState.i427_using
		if GameState.i427_using:
			GameState.give_achievement("427")
		hud.message("You opened the locket." if GameState.i427_using else "You closed the locket.", 5.0)
		hud.deselect()
	elif tempname == "pill":
		if _can_use(false, false, true):
			hud.message("You swallowed the pill.", 7.0)
			hud.remove_selected()
		else:
			hud.deselect()
	elif tempname == "scp500death":
		if _can_use(false, false, true):
			hud.message("You swallowed the pill.", 7.0)
			GameState.i427_timer = maxf(GameState.i427_timer, 70.0 * 360.0)
			hud.remove_selected()
		else:
			hud.deselect()
	elif tempname == "key":
		_use_lost_key()
	elif tempname == "badge":
		_use_badge()
	elif tempname == "coin":
		_use_coin()
	elif tempname == "1123":
		_use_1123()
	elif tempname == "scp714":
		# Items.bb: the ring goes on or off at once and is put away
		GameState.wearing_714 = not GameState.wearing_714
		if GameState.wearing_714:
			GameState.give_achievement("714")
		hud.message("You put on the ring." if GameState.wearing_714 else "You removed the ring.", 5.0)
		hud.deselect()
	elif tempname in HAZMATS and GameState.wearing_vest != 0:
		_done("")
	elif tempname == "scp1499" or tempname == "super1499":
		if GameState.wearing_hazmat != 0:
			_done("You are not able to wear SCP-1499 and a hazmat suit at the same time.")

func on_deselected() -> void:
	tempname = ""
	item_name = ""
	progress = 0.0
	hud.hide_item_ui()

func _physics_process(delta: float) -> void:
	if hud == null or tempname.is_empty():
		return
	var fps := delta * 70.0
	if tempname in HAZMATS:
		if GameState.wearing_vest == 0:
			_advance(fps / 4.0, _finish_hazmat)
	elif tempname in VESTS:
		_advance(fps / (2.0 + (0.5 if tempname == "finevest" else 0.0)), _finish_vest)
	elif tempname == "scp1499" or tempname == "super1499":
		if GameState.wearing_hazmat == 0:
			_advance(fps, _finish_1499)
	elif tempname in FIRST_AID:
		if locks_movement():
			var player: Node = GameState.player
			if player:
				player.crouching = true
			_advance(fps / 5.0, _finish_first_aid)

func _advance(step: float, finish: Callable) -> void:
	progress = minf(progress + step, 100.0)
	hud.set_progress(progress)
	if progress >= 100.0:
		progress = 0.0
		finish.call()

func _show_document() -> void:
	var template := RoomFill.item_template(item_name)
	var image := str(template.get("image", ""))
	if image.is_empty():
		return
	hud.show_document(image, item_name)
	if tempname == "oldpaper" and item_name.begins_with("Disciplinary Hearing") and _state() == 0.0:
		GameState.blur_timer = 1000.0
		hud.message("\"Why does this seem so familiar?\"", 10.0)
		_nostalgia(6, 10)
		_set_state(1.0)

func _use_gas_mask() -> void:
	var s := GameState
	if s.wearing_1499 != 0:
		_done("You need to take off SCP-1499 in order to put on the gas mask.")
		return
	if s.wearing_hazmat != 0:
		_done("You need to take off the hazmat suit in order to put on the gas mask.")
		return
	if s.wearing_gas_mask != 0:
		s.wearing_gas_mask = 0
		_done("You removed the gas mask.")
		return
	if tempname == "supergasmask":
		s.wearing_gas_mask = 2
		_done("You put on the gas mask and you can breathe easier.")
	else:
		s.wearing_gas_mask = 3 if tempname == "gasmask3" else 1
		_done("You put on the gas mask.")
	s.wearing_night_vision = 0

# Main.bb Case "nvgoggles" / "supernv" / "finenvgoggles": the same goggles toggle; a different pair is swapped in.
func _use_night_vision() -> void:
	var s := GameState
	if s.wearing_1499 != 0:
		_done("You need to take off SCP-1499 in order to put on the goggles.")
		return
	if s.wearing_hazmat != 0:
		_done("You need to take off the hazmat suit in order to put on the goggles.")
		return
	var kind: int = NIGHT_VISION[tempname]
	if s.wearing_night_vision == kind:
		s.wearing_night_vision = 0
		_done("You removed the goggles.")
	else:
		s.wearing_gas_mask = 0
		s.wearing_night_vision = kind
		_done("You put on the goggles.")

func _use_eye_drops() -> void:
	if not _can_use(false, false, false):
		_done("")
		return
	var s := GameState
	match tempname:
		"eyedrops":
			s.blink_effect = 0.6
			s.blink_effect_timer = randf_range(20.0, 30.0)
		"fineeyedrops":
			s.blink_effect = 0.4
			s.blink_effect_timer = randf_range(30.0, 40.0)
			s.bloodloss = maxf(s.bloodloss - 1.0, 0.0)
		"supereyedrops":
			s.blink_effect = 0.0
			s.blink_effect_timer = 60.0
			s.eye_stuck = 10000.0
	hud.remove_selected()

func _finish_vest() -> void:
	var s := GameState
	if s.wearing_vest > 0:
		# Taking it off drops it (DropItem after clearing the flag).
		s.wearing_vest = 0
		hud.message("You removed the vest.")
		hud.drop_selected(GameState.player)
	else:
		s.wearing_vest = 1 if tempname == "vest" else 2
		hud.message("You put on the vest and feel slightly encumbered." if tempname == "vest" else "You put on the vest and feel heavily encumbered.")
		hud.deselect()

func _finish_hazmat() -> void:
	var s := GameState
	if s.wearing_hazmat > 0:
		s.wearing_hazmat = 0
		hud.message("You removed the hazmat suit.")
		hud.drop_selected(GameState.player)
	else:
		s.wearing_hazmat = HAZMATS.find(tempname) + 1
		s.wearing_gas_mask = 0
		s.wearing_night_vision = 0
		hud.message("You put on the hazmat suit.")
		hud.deselect()

func _finish_first_aid() -> void:
	var s := GameState
	if tempname == "finefirstaid":
		s.bloodloss = 0.0
		s.injuries = maxf(0.0, s.injuries - 2.0)
		if s.injuries == 0.0:
			hud.message("You bandaged the wounds and took a painkiller. You feel fine.")
		elif s.injuries > 1.0:
			hud.message("You bandaged the wounds and took a painkiller, but you were not able to stop the bleeding.")
		else:
			hud.message("You bandaged the wounds and took a painkiller, but you still feel sore.")
	else:
		s.bloodloss = maxf(0.0, s.bloodloss - randf_range(10.0, 20.0))
		if s.injuries >= 2.5:
			hud.message("The wounds were way too severe to staunch the bleeding completely.")
			s.injuries = maxf(2.5, s.injuries - randf_range(0.3, 0.7))
		elif s.injuries > 1.0:
			s.injuries = maxf(0.5, s.injuries - randf_range(0.5, 1.0))
			hud.message("You bandaged the wounds but were unable to staunch the bleeding completely." if s.injuries > 1.0 else "You managed to stop the bleeding.")
		else:
			hud.message("You took a painkiller, easing the pain slightly." if s.injuries > 0.5 else "You took a painkiller, but it still hurts to walk.")
			s.injuries = 0.5
	hud.remove_selected()

# Main.bb CanUseItem (messages are skipped when only polling).
func _can_use(with_hazmat: bool, with_gas_mask: bool, with_eyewear: bool, speak: bool = true) -> bool:
	var s := GameState
	if not with_hazmat and s.wearing_hazmat != 0:
		if speak:
			hud.message("You can't use that item while wearing a hazmat suit.")
		return false
	if not with_gas_mask and (s.wearing_gas_mask != 0 or s.wearing_1499 != 0):
		if speak:
			hud.message("You can't use that item while wearing a gas mask.")
		return false
	if not with_eyewear and s.wearing_night_vision != 0:
		if speak:
			hud.message("You can't use that item while wearing headgear.")
		return false
	return true

func _icon_of(index: int) -> String:
	var data: Dictionary = hud.item_data[index]
	return str(data.get("icon", "GFX/items/INVpaper.png"))

func _done(text: String) -> void:
	if not text.is_empty():
		hud.message(text)
	hud.deselect()

# Main.bb Case "cup": what the cup holds is looked up in SCP-294.ini by its name, and the drink's lines apply. A refused drink
# (refusemessage) stays in the hand; any other becomes an empty cup in the same slot. "state" of a refined cup: x2 = state + 1
# multiplies the blink and stamina effects.
func _drink_cup() -> void:
	if not _can_use(false, false, true):
		hud.deselect()
		return
	var name := item_name.strip_edges().to_lower()
	if name.begins_with("cup of"):
		name = name.substr(7)
	elif name.begins_with("a cup of"):
		name = name.substr(9)
	var data: Dictionary = hud.item_data[hud.selected]
	var x2 := float(data.get("state", 0.0)) + 1.0
	var drink := Scp294Data.find(name)
	var s := GameState
	if not str(drink.get("message", "")).is_empty():
		hud.message(str(drink.message), 6.0)
	if Scp294Data.get_int(drink, "lethal") != 0 or Scp294Data.get_int(drink, "deathtimer") != 0:
		s.death_msg = str(drink.get("deathmessage", ""))
		if Scp294Data.get_int(drink, "lethal") != 0 and s.player != null:
			s.player.kill(s.death_msg)
	s.blur_timer = float(Scp294Data.get_int(drink, "blur")) * 70.0
	if s.vomit_timer == 0.0:
		s.vomit_timer = float(Scp294Data.get_int(drink, "vomit"))
	s.camera_shake_timer = Scp294Data.get_float(drink, "camerashake")
	s.injuries = maxf(s.injuries + float(Scp294Data.get_int(drink, "damage")), 0.0)
	s.bloodloss = maxf(s.bloodloss + float(Scp294Data.get_int(drink, "blood loss")), 0.0)
	if not str(drink.get("sound", "")).is_empty():
		Sfx.play_global(hud, str(drink.sound).replace("\\", "/"))
	s.death_timer = float(Scp294Data.get_int(drink, "deathtimer")) * 70.0
	s.blink_effect = Scp294Data.get_float(drink, "blink effect", 1.0) * x2
	s.blink_effect_timer = Scp294Data.get_float(drink, "blink effect timer", 1.0) * x2
	s.stamina_effect = Scp294Data.get_float(drink, "stamina effect", 1.0) * x2
	s.stamina_effect_timer = Scp294Data.get_float(drink, "stamina effect timer", 1.0) * x2
	if not str(drink.get("refusemessage", "")).is_empty():
		hud.message(str(drink.refusemessage), 6.0)
	else:
		var empty := RoomFill.item_template("Empty Cup", "emptycup")
		hud.items[hud.selected] = "Empty Cup"
		hud.item_data[hud.selected] = {"tempname": "emptycup", "icon": str(empty.get("icon", "GFX/items/INVcup.jpg")), "state": 0.0}
	hud.deselect()

func _state() -> float:
	return float(hud.item_data[hud.selected].get("state", 0.0))

func _set_state(value: float) -> void:
	hud.item_data[hud.selected]["state"] = value

func _room_name() -> String:
	var facility := hud.get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or GameState.player == null:
		return ""
	var room: Node3D = facility.room_at(GameState.player.global_position)
	return str(room.room_name) if room != null else ""

# Main.bb Case "syringe" / "finesyringe" / "veryfinesyringe".
func _use_syringe() -> void:
	if not _can_use(false, true, true):
		hud.deselect()
		return
	var s := GameState
	match tempname:
		"syringe":
			s.heal_timer = 30.0
			s.stamina_effect = 0.5
			s.stamina_effect_timer = 20.0
			hud.message("You injected yourself with the syringe and feel a slight adrenaline rush.", 8.0)
		"finesyringe":
			s.heal_timer = randf_range(20.0, 40.0)
			s.stamina_effect = randf_range(0.5, 0.8)
			s.stamina_effect_timer = randf_range(20.0, 30.0)
			hud.message("You injected yourself with the syringe and feel an adrenaline rush.", 8.0)
		_:
			match randi_range(1, 3):
				1:
					s.heal_timer = randf_range(40.0, 60.0)
					s.stamina_effect = 0.1
					s.stamina_effect_timer = 30.0
					hud.message("You injected yourself with the syringe and feel a huge adrenaline rush.", 8.0)
				2:
					s.super_man = true
					hud.message("You injected yourself with the syringe and feel a humongous adrenaline rush.", 8.0)
				3:
					s.vomit_timer = 30.0
					hud.message("You injected yourself with the syringe and feel a pain in your stomach.", 8.0)
	hud.remove_selected()

# Main.bb Case "veryfinefirstaid": the strange bottle.
func _use_strange_bottle() -> void:
	if not _can_use(false, false, true):
		hud.deselect()
		return
	var s := GameState
	var player: CharacterBody3D = s.player
	match (bottle_roll if bottle_roll > 0 else randi_range(1, 5)):
		1:
			s.injuries = 3.5
			hud.message("You started bleeding heavily.", 7.0)
		2:
			s.injuries = 0.0
			s.bloodloss = 0.0
			hud.message("Your wounds are healing up rapidly.", 7.0)
		3:
			s.injuries = maxf(0.0, s.injuries - randf_range(0.5, 3.5))
			s.bloodloss = maxf(0.0, s.bloodloss - randf_range(10.0, 100.0))
			hud.message("You feel much better.", 7.0)
		4:
			s.blur_timer = 10000.0
			s.bloodloss = 0.0
			hud.message("You feel nauseated.", 7.0)
		5:
			player.blink_timer = -10.0
			var name := _room_name()
			var on_surface: bool = name == "exit1" and player.global_position.y > 1040.0 * 8.0 / 2048.0
			if name == "dimension1499" or name == "gatea" or on_surface:
				s.injuries = 2.5
				hud.message("You started bleeding heavily.", 7.0)
			else:
				var facility := hud.get_tree().get_first_node_in_group("facility") as FacilityMap
				if facility != null:
					facility.enter_pocket(player)
					Sfx.play_global(hud, "SFX/SCP/914/PlayerUse.ogg")
					hud.message("For some inexplicable reason, you find yourself inside the pocket dimension.", 8.0)
	hud.remove_selected()

# Main.bb Case "cigarette": nothing to light it with; the third and sixth lines also drop it.
func _use_cigarette() -> void:
	if not _can_use(false, false, true):
		hud.deselect()
		return
	var removed := false
	if _state() == 0.0:
		match randi_range(1, 6):
			1:
				hud.message("\"I don't have anything to light it with. Umm, what about that... Nevermind.\"", 5.0)
			2:
				hud.message("You are unable to get lit.", 5.0)
			3:
				hud.message("\"I quit that a long time ago.\"", 5.0)
				removed = true
			4:
				hud.message("\"Even if I wanted one, I have nothing to light it with.\"", 5.0)
			5:
				hud.message("\"Could really go for one now... Wish I had a lighter.\"", 5.0)
			6:
				hud.message("\"Don't plan on starting, even at a time like this.\"", 5.0)
				removed = true
		if not removed:
			_set_state(1.0)
	else:
		hud.message("You are unable to get lit.", 5.0)
	if removed:
		hud.remove_selected()
	else:
		hud.deselect()

# Main.bb Case "420" (SCP-420-J) and "420s" (the joint that does not end well).
func _use_joint() -> void:
	if not _can_use(false, false, true):
		hud.deselect()
		return
	var s := GameState
	if tempname == "420":
		if s.wearing_714:
			hud.message("\"DUDE WTF THIS SHIT DOESN'T EVEN WORK\"", 5.0)
		else:
			hud.message("\"MAN DATS SUM GOOD ASS SHIT\"", 5.0)
			s.injuries = maxf(s.injuries - 0.5, 0.0)
			s.blur_timer = 500.0
			s.give_achievement("420")
			Sfx.play_global(hud, "SFX/Music/420J.ogg")
	else:
		if s.wearing_714:
			hud.message("\"DUDE WTF THIS SHIT DOESN'T EVEN WORK\"", 6.0)
		else:
			s.death_msg = "Subject D-9341 found in a comatose state in [DATA REDACTED]. The subject was holding what appears to be a cigarette while smiling widely. Chemical analysis of the cigarette has been inconclusive, although it seems to contain a high concentration of an unidentified chemical whose molecular structure is remarkably similar to that of tetrahydrocannabinol."
			hud.message("\"UH WHERE... WHAT WAS I DOING AGAIN... MAN I NEED TO TAKE A NAP...\"", 6.0)
			if s.player != null:
				s.player.kill(s.death_msg)
	hud.remove_selected()

# SCP-1162's pictures and keepsakes: the first look sets off a nostalgic voice (and sometimes a line).
func _nostalgia(first: int, last: int) -> void:
	Sfx.play_global(hud, "SFX/SCP/1162/NostalgiaCancer%d.ogg" % randi_range(first, last))

func _use_lost_key() -> void:
	if _state() == 0.0:
		_nostalgia(6, 10)
		hud.message("\"Isn't this the key to that old shack? The one where I... No, it can't be.\"", 10.0)
	_set_state(1.0)
	hud.deselect()

func _use_badge() -> void:
	_show_document()
	if _state() == 0.0:
		_nostalgia(6, 10)
		if item_name == "Old Badge":
			hud.message("\"Huh? This guy looks just like me!\"", 10.0)
		_set_state(1.0)

func _use_coin() -> void:
	if _state() == 0.0:
		_nostalgia(1, 5)
	_set_state(1.0)

# Main.bb Case "1123": touching SCP-1123 anywhere but its own room is fatal (with the ring of SCP-714 on, nothing happens).
func _use_1123() -> void:
	var s := GameState
	if s.wearing_714:
		return
	if _room_name() != "room1123":
		s.light_flash = 7.0
		Sfx.play_global(hud, "SFX/SCP/1123/Touch.ogg")
		if s.player != null:
			s.death_msg = "Subject D-9341 was shot dead after attempting to attack a member of Nine-Tailed Fox. Surveillance tapes show that the subject had been wandering around the site approximately 9 minutes prior, shouting the phrase \"get rid of the four pests\" in chinese. SCP-1123 was found in [REDACTED] nearby, suggesting the subject had come into physical contact with it. How exactly SCP-1123 was removed from its containment chamber is still unknown."
			s.player.kill(s.death_msg)
		return
	var facility := hud.get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or facility.ambient == null:
		return
	for record in facility.generator.rooms:
		if str(record.name) == "room1123":
			var st: Dictionary = facility.ambient.state_of(record.key)
			if st.s == 0.0:
				s.light_flash = 3.0
				Sfx.play_global(hud, "SFX/SCP/1123/Touch.ogg")
			st.s = maxf(1.0, st.s)
			return

# Main.bb Case "scp1499" / "super1499": the bar fills in 100 frames; then the mask goes on (and the player is carried into SCP-1499's
# dimension) or comes off (the dimension sends them back, see dimension_1499.gd).
func _finish_1499() -> void:
	var s := GameState
	var facility := hud.get_tree().get_first_node_in_group("facility") as FacilityMap
	if s.wearing_1499 > 0:
		s.wearing_1499 = 0
		hud._item_sound(item_name)
	else:
		s.wearing_1499 = 1 if tempname == "scp1499" else 2
		hud._item_sound(item_name)
		s.give_achievement("1499")
		s.wearing_gas_mask = 0
		s.wearing_night_vision = 0
		if facility != null and facility.dimension != null and s.player != null:
			facility.dimension.enter(s.player)
	hud.deselect()

# Main.bb Case "scp1025": a page of the book, picked again at random each time it is taken up; the illness it names starts
# (drink_effects.gd keeps it going while the page is held). The ring (SCP-714) protects.
func _use_1025() -> void:
	GameState.give_achievement("1025")
	var roll := randi_range(0, 5)
	hud.item_data[hud.selected]["state"] = float(roll)
	hud.show_document("GFX/items/1025/1025_%d.jpg" % roll, "SCP-1025")
