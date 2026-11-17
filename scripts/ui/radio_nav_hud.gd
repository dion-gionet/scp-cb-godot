extends Control
# The radio transceiver and the S-NAV navigators held up on screen (Main.bb DrawGUI, Case "radio" and Case "nav").
# The radio's picture sits in the bottom right corner with its battery bars, the channel number and a marquee; its channels
# are the user track player, the warning loop, the on-site radio, the emergency channel, chatter, static, and (veryfine) the
# buzzed access code. The navigator draws the walls of the rooms around the player, the room the player is in at the middle.
# Pictures and offsets are laid out in screen pixels (UIKit.pixel_scale); the digital fonts follow MenuScale (height / 1024).


const RADIOS := ["radio", "18vradio", "fineradio", "veryfineradio"]

var hud: Node
var _textures: Dictionary = {}
var _map: Control                 # the navigator's screen: the walls are clipped to it
var _chan: Dictionary = {}        # RadioCHN: channel -> AudioStreamPlayer
var _acc := 0.0
var _text := ""
var _nav_origin := Vector2.ZERO   # the navigator's x, y (the player's mark)
var _nav_item := ""
var _nav_state := 0.0
var _user_tracks: Array[String] = []
var _user_enabled := false
var _user_ready := false
# RadioState(0..8): 0 user track, 1 alarm count, 2 on-site radio step, 3 and 4 the random lines, 5 the key hint shown,
# 6 and 7 the buzz timers of the code channel, 8 the digit; RadioState3/RadioState4 remember which lines were heard
var rs: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var rs3: Array[bool] = [false, false, false, false, false, false, false, false]
var rs4: Array[bool] = [false, false, false, false, false, false, false, false, false, false]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_map = Control.new()
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	add_child(_map)

func _k() -> float:
	return UIKit.pixel_scale(self)

func _s() -> float:
	return size.y / 1024.0

# LoadImage + MaskImage(255, 0, 255): the magenta becomes transparent.
func _masked(relative: String) -> Texture2D:
	if _textures.has(relative):
		return _textures[relative]
	var texture: Texture2D = null
	var path := ContentPaths.existing_image(relative)
	if FileAccess.file_exists(path):
		var image := MeshLoader.load_image(path)
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			var data := image.get_data()
			var i := 0
			while i < data.size():
				if data[i] > 245 and data[i + 1] < 10 and data[i + 2] > 245:
					data[i + 3] = 0
				i += 4
			image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
			# the cleared pixels keep their magenta, which linear filtering bleeds into the edges
			image.fix_alpha_edges()
			texture = ImageTexture.create_from_image(image)
	_textures[relative] = texture
	return texture

func _tempname() -> String:
	return hud.selected_tempname()

func _is_radio() -> bool:
	return _tempname() in RADIOS

func _is_nav() -> bool:
	return _tempname() == "nav"

func _data() -> Dictionary:
	return hud.item_data[hud.selected]

func _process(_delta: float) -> void:
	var active: bool = hud.selected >= 0 and (_is_radio() or _is_nav())
	visible = active
	if active:
		queue_redraw()
		_map.queue_redraw()
	else:
		_map.visible = false

# The number keys 1 to 5 choose the radio's channel (KeyHit(2..6)); the veryfine radio has no channels. True if used.
func handle_key(keycode: int) -> bool:
	if hud.selected < 0 or not _is_radio() or _tempname() == "veryfineradio":
		return false
	if keycode < KEY_1 or keycode > KEY_5:
		return false
	if float(_data().get("state", 0.0)) > 0.0 and not _in_dead_zone():
		select_channel(keycode - KEY_1)
	return true

func select_channel(channel: int) -> void:
	var data := _data()
	var current := int(data.get("state2", 0.0))
	if current != channel:
		Sfx.play_global(self, "SFX/Radio/squelch.ogg")
		_pause(current)
	data["state2"] = float(channel)
	_resume(channel)

func _in_dead_zone() -> bool:
	return _room() == "pocketdimension" or GameState.coffin_distance < 4.0

func _room() -> String:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or GameState.player == null:
		return ""
	return facility.room_name_at(GameState.player.global_position)

func _play(channel: int, relative: String) -> void:
	var source := Sfx.stream(relative)
	if source == null:
		return
	var player: AudioStreamPlayer = _chan.get(channel)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		add_child(player)
		_chan[channel] = player
	player.stream = source
	player.stream_paused = false
	player.play()

func _playing(channel: int) -> bool:
	var player: AudioStreamPlayer = _chan.get(channel)
	return player != null and is_instance_valid(player) and player.playing

func _resume(channel: int) -> void:
	var player: AudioStreamPlayer = _chan.get(channel)
	if player != null and is_instance_valid(player):
		player.stream_paused = false

func _pause(channel: int) -> void:
	var player: AudioStreamPlayer = _chan.get(channel)
	if player != null and is_instance_valid(player):
		player.stream_paused = true

func _pause_all() -> void:
	for channel in _chan:
		_pause(int(channel))

func _random_chance(low: int, high: int) -> float:
	return float(maxi(randi_range(low, high), 0))

# ---- the logic, 70 Hz ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if hud == null:
		return
	if hud.selected >= 0 and _is_nav():
		var nav := _data()
		if float(nav.get("state", 0.0)) <= 100.0:
			nav["state"] = maxf(0.0, float(nav.get("state", 0.0)) - delta * 70.0 * 0.005)
	if hud.selected < 0 or not _is_radio():
		_pause_all()      # With nothing selected every channel is paused
		return
	var data := _data()
	var fps := delta * 70.0
	if float(data.get("state", 0.0)) <= 100.0:
		data["state"] = maxf(0.0, float(data.get("state", 0.0)) - fps * 0.004)
	if rs[5] == 0.0:
		hud.message("Use the numbered keys 1 through 5 to cycle between various channels.", 5.0)
		rs[5] = 1.0
		rs[0] = -1.0
	if float(data.get("state", 0.0)) <= 0.0:
		return
	_acc += fps
	var steps := 0
	while _acc >= 1.0 and steps < 8:
		_acc -= 1.0
		steps += 1
		_step(data)
	_acc = minf(_acc, 1.0)

func _step(data: Dictionary) -> void:
	_text = ""
	if _in_dead_zone():
		_resume(5)
		if not _playing(5):
			_play(5, "SFX/Radio/static.ogg")
		return
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var channel := int(data.get("state2", 0.0))
	match channel:
		0:
			_user_channel()
		1:
			_resume(1)
			_text = "        WARNING - CONTAINMENT BREACH          "
			if not _playing(1):
				if rs[1] >= 5.0:
					_play(1, "SFX/Radio/RadioAlarm2.ogg")
					rs[1] = 0.0
				else:
					rs[1] += 1.0
					_play(1, "SFX/Radio/RadioAlarm.ogg")
		2:
			_resume(2)
			_text = "        SCP Foundation On-Site Radio          "
			if not _playing(2):
				rs[2] += 1.0
				if rs[2] == 17.0:
					rs[2] = 1.0
				if floorf(rs[2] / 2.0) == ceilf(rs[2] / 2.0):
					_play(2, "SFX/Radio/scpradio%d.ogg" % int(rs[2] / 2.0))
				else:
					_play(2, "SFX/Radio/scpradio0.ogg")
		3:
			_resume(3)
			_text = "             EMERGENCY CHANNEL - RESERVED FOR COMMUNICATION IN THE EVENT OF A CONTAINMENT BREACH         "
			if not _playing(3):
				_play(3, "SFX/Radio/static.ogg")
			if facility != null and facility.mtf.timer > 0.0:
				rs[3] += _random_chance(-10, 1)
				for k in 7:
					if int(rs[3]) == [40, 400, 800, 1200, 1600, 2000, 2400][k] and not rs3[k]:
						_play(3, "SFX/Character/MTF/Random%d.ogg" % (k + 1))
						rs[3] += 1.0
						rs3[k] = true
		4:
			_resume(6)
			if not _playing(6):
				_play(6, "SFX/Radio/static.ogg")
			_resume(4)
			if not _playing(4):
				if facility != null and not facility.remote_door_on and rs[8] == 0.0:
					_play(4, "SFX/Radio/Chatter3.ogg")
					rs[8] = 1.0
				else:
					rs[4] += _random_chance(-10, 1)
					_chatter(facility)
		5:
			_resume(5)
			if not _playing(5):
				_play(5, "SFX/Radio/static.ogg")
	if _tempname() == "veryfineradio":
		_code_channel()

func _chatter(facility: FacilityMap) -> void:
	var at := int(rs[4])
	var lines := {10: [0, "SFX/Radio/OhGod.ogg"], 100: [1, "SFX/Radio/Chatter2.ogg"], 158: [2, "SFX/Radio/franklin1.ogg"], 200: [3, "SFX/Radio/Chatter4.ogg"],
		260: [4, "SFX/SCP/035/RadioHelp1.ogg"], 300: [5, "SFX/Radio/Chatter1.ogg"], 350: [6, "SFX/Radio/franklin2.ogg"], 400: [7, "SFX/SCP/035/RadioHelp2.ogg"],
		450: [8, "SFX/Radio/franklin3.ogg"], 600: [9, "SFX/Radio/franklin4.ogg"]}
	if not lines.has(at):
		return
	var index: int = lines[at][0]
	if at == 10 and facility != null and facility.contained_106:
		return
	if at == 158:
		if not (facility != null and facility.mtf.timer == 0.0 and not rs4[2]):
			return
		_play(4, lines[at][1])
		rs[4] += 1.0
		rs[2] = 1.0          # the original sets RadioState(2) here, not RadioState4(2)
		return
	if rs4[index]:
		return
	_play(4, lines[at][1])
	rs[4] += 1.0
	rs4[index] = true

func _user_channel() -> void:
	_resume(0)
	_text = "        USER TRACK PLAYER - "
	if not _user_ready:
		_user_ready = true
		_user_enabled = GameState.enable_user_tracks
		if _user_enabled:
			var folder := ContentPaths.existing_file("SFX/Radio/UserTracks")
			for file_name in DirAccess.get_files_at(folder):
				if file_name.get_extension().to_lower() == "ogg":
					_user_tracks.append(file_name)
	if not _user_enabled:
		if not _playing(0):
			_play(0, "SFX/Radio/static.ogg")
		_text += "NOT ENABLED     "
	elif _user_tracks.is_empty():
		if not _playing(0):
			_play(0, "SFX/Radio/static.ogg")
		_text += "NO TRACKS FOUND     "
	else:
		if not _playing(0):
			# UserTrackMode: Repeat steps through the files in order, Random picks any
			if GameState.user_track_mode != 0:
				rs[0] = float(int(maxf(rs[0], 0.0)) + 1 if int(maxf(rs[0], 0.0)) < _user_tracks.size() - 1 else 0)
			else:
				rs[0] = float(randi_range(0, _user_tracks.size() - 1))
			_play_track()
		else:
			_text += _user_tracks[int(rs[0])].to_upper() + "          "

func _play_track() -> void:
	var folder := ContentPaths.existing_file("SFX/Radio/UserTracks")
	var path := folder.path_join(_user_tracks[int(rs[0])])
	var source := AudioStreamOggVorbis.load_from_file(path)
	if source == null:
		return
	var player: AudioStreamPlayer = _chan.get(0)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		add_child(player)
		_chan[0] = player
	player.stream = source
	player.stream_paused = false
	player.play()

# The "code channel" of the veryfine radio: it buzzes the access code, digit by digit, with a pause between.
func _code_channel() -> void:
	_resume(0)
	if not _playing(0):
		_play(0, "SFX/Radio/static.ogg")
	rs[6] += 1.0
	var digits := GameState.access_code
	var digit := int(digits.substr(int(rs[8]), 1)) if int(rs[8]) < digits.length() else 0
	if rs[6] - 1.0 <= rs[7] * 50.0 and rs[6] > rs[7] * 50.0:
		Sfx.play_global(self, "SFX/Radio/buzz.ogg")
		rs[7] += 1.0
		if rs[7] >= digit:
			rs[7] = 0.0
			rs[6] = -100.0
			rs[8] += 1.0
			if rs[8] == 4.0:
				rs[8] = 0.0
				rs[6] = -200.0
	_text = ""
	for i in randi_range(5, 30) + 1:
		_text += char(randi_range(33, 126))

func _draw() -> void:
	if hud.selected < 0:
		return
	if _is_radio():
		_draw_radio()
	elif _is_nav():
		_draw_nav()
	else:
		_map.visible = false

func _draw_radio() -> void:
	_map.visible = false
	var k := _k()
	var image := _masked("GFX/items/radioHUD.png")
	if image == null:
		return
	var data := _data()
	var picture := image.get_size()
	var origin := size - picture * k
	draw_texture_rect(image, Rect2(origin, picture * k), false)
	var state := float(data.get("state", 0.0))
	if state <= 0.0 or _in_dead_zone():
		return
	var at := origin + Vector2(66.0, 419.0) * k
	var ink := Color8(30, 30, 30)
	if state <= 100.0:
		for i in 5:
			var bar := Rect2(at + Vector2(0.0, 8.0 * i) * k, Vector2(43.0 - i * 6.0, 4.0) * k)
			if ceilf(state / 20.0) > 4 - i:
				draw_rect(bar, ink)
			else:
				draw_rect(bar, ink, false, 1.0)
	var small := UIKit.font("digital")
	var small_size := UIKit.font_size("digital", _s())
	var big_size := UIKit.font_size("digital_large", _s())
	draw_string(small, at + Vector2(60.0 * k, small.get_ascent(small_size)), "CHN", HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, ink)
	var number := str(randi_range(0, 9)) if _tempname() == "veryfineradio" else str(int(data.get("state2", 0.0)) + 1)
	var width := small.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size).x
	var centre := at + Vector2(97.0, 16.0) * k
	draw_string(small, Vector2(centre.x - width * 0.5, centre.y - small.get_height(big_size) * 0.5 + small.get_ascent(big_size)), number, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, ink)
	if not _text.is_empty():
		var window := _text
		if _tempname() != "veryfineradio":
			window = _text.substr(0, int(Time.get_ticks_msec() / 300.0) % _text.length()).right(10)
		draw_string(small, at + Vector2(32.0 * k, 33.0 * k + small.get_ascent(small_size)), window, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, ink)

func _nav_works() -> bool:
	var room := _room()
	if room == "room860":
		var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
		if facility != null and facility.events.room860.state == 1.0:
			return false
	return not (room == "pocketdimension" or room == "dimension1499")

func _draw_nav() -> void:
	var k := _k()
	var image := _masked("GFX/items/Navigator.png")
	if image == null:
		return
	var data := _data()
	var item_name: String = hud.items[hud.selected]
	var state := float(data.get("state", 0.0))
	var width := 287.0 * k
	var height := 256.0 * k
	var centre := Vector2(size.x - image.get_width() * k * 0.5 + 20.0 * k, size.y - image.get_height() * k * 0.4 - 85.0 * k)
	var top_left := Vector2(centre.x - image.get_width() * k * 0.5, centre.y - image.get_height() * k * 0.5 + 85.0 * k)
	draw_texture_rect(image, Rect2(top_left, image.get_size() * k), false)
	var base_ink := Color8(100, 0, 0) if item_name == "S-NAV Navigator" else Color8(30, 30, 30)
	var font := UIKit.font("digital")
	var font_size := int(22.0 * _s())
	var blink_on := Time.get_ticks_msec() % 1000 > 300
	_map.visible = false
	if not _nav_works():
		if blink_on:
			var red := Color8(200, 0, 0)
			_center_text(font, font_size, Vector2(centre.x, centre.y + height * 0.5 - 80.0 * k), "ERROR 06", red)
			_center_text(font, font_size, Vector2(centre.x, centre.y + height * 0.5 - 60.0 * k), "LOCATION UNKNOWN", red)
		return
	if state <= 0.0 or (_room() == "coffin" and randf() * (GameState.coffin_distance + 15.0) <= 1.0):
		return          # SCP-895 makes the screen drop out
	_nav_origin = centre
	_nav_item = item_name
	_nav_state = state
	var screen := Rect2(top_left + Vector2(80.0, 70.0) * k, Vector2(270.0, 230.0) * k)
	_map.position = screen.position
	_map.size = screen.size
	_map.visible = true
	draw_rect(screen, base_ink, false, 1.0)
	if blink_on:
		if item_name != "S-NAV 310 Navigator" and item_name != "S-NAV Navigator Ultimate":
			draw_string(font, Vector2(centre.x - width * 0.5 + 10.0 * k, centre.y - height * 0.5 + 10.0 * k + font.get_ascent(font_size)), "MAP DATABASE OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_ink)
		var player := GameState.player
		var yaw := rad_to_deg(player.rotation.y) - 90.0
		var p1 := centre + Vector2(cos(deg_to_rad(yaw)) * 6.0, -sin(deg_to_rad(yaw)) * 6.0) * k
		var p2 := centre + Vector2(cos(deg_to_rad(yaw - 140.0)) * 5.0, -sin(deg_to_rad(yaw - 140.0)) * 5.0) * k
		var p3 := centre + Vector2(cos(deg_to_rad(yaw + 140.0)) * 5.0, -sin(deg_to_rad(yaw + 140.0)) * 5.0) * k
		draw_line(p1, p2, base_ink)
		draw_line(p1, p3, base_ink)
		draw_line(p2, p3, base_ink)
	if item_name == "S-NAV Navigator Ultimate" and Time.get_ticks_msec() % 600 < 400:
		_draw_scps(centre, width, height, font, font_size)
	if state <= 100.0:
		var meter := Rect2(centre + Vector2(-width * 0.5 + 196.0 * k, -height * 0.5 + 10.0 * k), Vector2(80.0, 20.0) * k)
		draw_rect(meter, base_ink, false, 1.0)
		var bars := _masked("GFX/navigator/batterymeter.png")
		if bars != null:
			for i in range(1, int(ceilf(state / 10.0)) + 1):
				draw_texture_rect(bars, Rect2(meter.position + Vector2(i * 8.0 - 6.0, 4.0) * k, bars.get_size() * k), false)

func _center_text(font: Font, font_size: int, at: Vector2, text: String, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(at.x - w * 0.5, at.y + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

# The Ultimate navigator also marks the SCPs within 32 m (173 by rings of 8 m, the others by their distance).
func _draw_scps(centre: Vector2, width: float, height: float, font: Font, font_size: int) -> void:
	var player := GameState.player
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if player == null or facility == null:
		return
	var k := _k()
	var camera: Vector3 = player.camera.global_position
	var found := 0
	var red := Color8(100, 0, 0)
	var list: Array = [[GameState.scp173, "SCP-173", true], [facility.scp106, "SCP-106", false], [facility.scp096, "SCP-096", false], [facility.scp049, "SCP-049", false]]
	for entry in list:
		var npc: Node = entry[0]
		if npc == null or not is_instance_valid(npc) or not (npc is Node3D):
			continue
		var dist: float = camera.distance_to((npc as Node3D).global_position)
		if entry[2]:
			dist = ceilf(dist / 8.0) * 8.0
		if dist >= 8.0 * 4.0:
			continue
		var radius: float = dist * (3.0 if entry[2] else 1.5) * k
		draw_arc(centre + Vector2(0.0, -7.0 * k), radius, 0.0, TAU, 48, red)
		draw_string(font, Vector2(centre.x - width * 0.5 + 10.0 * k, centre.y - height * 0.5 + (30.0 + 20.0 * found) * k + font.get_ascent(font_size)), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, red)
		found += 1
	if _room() == "coffin" and GameState.coffin_distance < 8.0:
		var ring := randf_range(4.0, 8.0) * 1.5 * k
		draw_arc(centre + Vector2(0.0, -7.0 * k), ring, 0.0, TAU, 48, red)
		draw_string(font, Vector2(centre.x - width * 0.5 + 10.0 * k, centre.y - height * 0.5 + (30.0 + 20.0 * found) * k + font.get_ascent(font_size)), "SCP-895", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, red)

# The walls of the rooms near the player, in the navigator's screen (_map's own coordinates).
func _draw_map() -> void:
	if not _map.visible or GameState.player == null:
		return
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null:
		return
	var k := _k()
	var player: Node3D = GameState.player
	var record: Dictionary = facility.record_at(player.global_position)
	if record.is_empty():
		return
	var layout: Dictionary = {}
	for room in facility.generator.rooms:
		layout[room.grid] = true
	var everything := _nav_item == "S-NAV 310 Navigator" or _nav_item == "S-NAV Navigator Ultimate"
	var ink_origin := _nav_origin - _map.position
	var bx := player.global_position.x
	var bz := -player.global_position.z
	var x := ink_origin.x - 12.0 * k + fposmod((bx - 4.0) + 8.0, 8.0) * 3.0 * k
	var y := ink_origin.y + 12.0 * k - fposmod((bz - 4.0) + 8.0, 8.0) * 3.0 * k
	var gx: int = record.grid.x + 1
	var gz: int = record.grid.y + 1
	var borders: Array[Texture2D] = []
	for i in 4:
		borders.append(_masked("GFX/navigator/roomborder%d.png" % i))
	for x2 in range(maxi(0, gx - 6), gx + 7):
		for z2 in range(maxi(0, gz - 6), gz + 7):
			var cell := Vector2i(x2, z2)
			if not layout.has(cell):
				continue
			if not (GameState.coffin_distance > 16.0 or randf() * 16.0 < GameState.coffin_distance):
				continue
			if not (everything or GameState.rooms_found.has("%d,%d" % [x2, z2])):
				continue
			var at := Vector2(x + (gx - 1 - x2) * 24.0 * k, y - (gz - 1 - z2) * 24.0 * k) - Vector2(12.0, 12.0) * k
			if not layout.has(Vector2i(x2 + 1, z2)):
				_map.draw_texture_rect(borders[3], Rect2(at, borders[3].get_size() * k), false)
			if not layout.has(Vector2i(x2 - 1, z2)):
				_map.draw_texture_rect(borders[1], Rect2(at, borders[1].get_size() * k), false)
			if not layout.has(Vector2i(x2, z2 - 1)):
				_map.draw_texture_rect(borders[0], Rect2(at, borders[0].get_size() * k), false)
			if not layout.has(Vector2i(x2, z2 + 1)):
				_map.draw_texture_rect(borders[2], Rect2(at, borders[2].get_size() * k), false)
