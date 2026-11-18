extends Control
# The ending (Main.bb DrawEnding / InitCredits / DrawCredits). An ending code (a1, a2, b1, b2, b3) starts EndingTimer at -0.1 and it
# counts down by one per 70 Hz frame:
#   0 .. -360   the player has been "killed" (the console's `ending` sets KillTimer = -0.1): the view darkens and blurs
#   -200 on     (-360 here) the picture GFX/endingscreen.pt on black, the Ending music, the light switch sound; the picture
#               flickers in until -700 (it shows with a chance of min(|t| - 200, 155) / 150, else a black box); at -450
#               the ending's own voice line plays (SFX/Ending/Gate[A|B]/Ending<code>.ogg)
#   -700 on     the picture stays; from -1000 the "THE END" panel with the run's statistics and a MAIN MENU button
#               (the timer waits at -1111 for the click)
#   -2000 on    the credits scroll (Credits.txt, 0.5 pixel a frame; "*" lines are headings, the line before the "/" line is
#               the last one to scroll, and the lines after the "/" fade in, hold, fade out); a key press or the end
#               returns to the main menu.

signal finished


var code := ""
var ending_timer := 0.0
var active := false
var panel_requested := false

var _picture: Texture2D
var _credits_picture: Texture2D
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _light: AudioStreamPlayer
var _started_music := false
var _played_voice := false
var _credits: Array[String] = []
var _credits_timer := 0.0
var _credits_started := false
var _last_line := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 50
	_music = AudioStreamPlayer.new()
	_music.set_meta("music", true)
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	_light = AudioStreamPlayer.new()
	add_child(_light)

# SelectedEnding = code, KillTimer = -0.1
func start(new_code: String) -> void:
	if active:
		return
	code = new_code.to_lower()
	ending_timer = -0.1
	active = true
	visible = true
	panel_requested = false
	_started_music = false
	_played_voice = false
	_credits_started = false
	_credits_timer = 0.0
	GameState.selected_ending = code
	get_tree().paused = true
	MouseCapture.release()

func _process(delta: float) -> void:
	if not active:
		return
	var fps := delta * 70.0
	_music.volume_db = linear_to_db(maxf(GameState.music_volume, 0.0001))
	if ending_timer > -2000.0:
		ending_timer = maxf(ending_timer - fps, -1111.0)
	else:
		ending_timer -= fps
	if ending_timer > -360.0:
		GameState.blur_timer = maxf(GameState.blur_timer, absf(ending_timer * 5.0))
	if ending_timer <= -360.0 and not _started_music:
		_start_picture()
	if ending_timer <= -450.0 and not _played_voice:
		_play_voice()
	if ending_timer < -1000.0 and ending_timer > -2000.0 and not panel_requested:
		panel_requested = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null:
			hud.open_end_panel()
	if ending_timer <= -2000.0 and not _credits_started:
		_start_credits()
	queue_redraw()

func _start_picture() -> void:
	_started_music = true
	_picture = _load_picture("GFX/endingscreen.pt")
	var music := Sfx.stream("SFX/Music/Ending.ogg")
	if music != null:
		music.loop = true
		_music.stream = music
		_music.play()
	var light := Sfx.stream("SFX/General/LightSwitch.ogg")
	if light != null:
		_light.stream = light
		_light.play()

func _play_voice() -> void:
	_played_voice = true
	var gate := "GateA" if code.begins_with("a") else "GateB"
	var stream := Sfx.stream("SFX/Ending/%s/Ending%s.ogg" % [gate, code.to_upper()])
	if stream != null:
		_voice.stream = stream
		_voice.play()

func _load_picture(relative: String) -> Texture2D:
	var path := ContentPaths.existing_file(relative)
	if not FileAccess.file_exists(path):
		return null
	var image := MeshLoader.load_image(path)     # the .pt pictures are JPEG or PNG files under another name
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _start_credits() -> void:
	_credits_started = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.close_end_panel()
	_credits.clear()
	var file := FileAccess.open(ContentPaths.existing_file("Credits.txt"), FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			_credits.append(file.get_line().strip_edges(false, true).trim_prefix("﻿"))
	_last_line = _credits.size() - 1
	for i in _credits.size():
		if _credits[i].begins_with("/"):
			_last_line = i - 1
			break
	_credits_picture = _load_picture("GFX/creditsscreen.pt")
	_credits_timer = 0.0
	_music.stop()
	var music := Sfx.stream("SFX/Music/Credits.ogg")
	if music != null:
		_music.stream = music
		_music.play()

func _input(event: InputEvent) -> void:
	if _credits_started and event is InputEventKey and event.pressed and not event.echo:
		_finish()
		get_viewport().set_input_as_handled()

func _finish() -> void:
	if not active:
		return
	active = false
	visible = false
	_music.stop()
	_voice.stop()
	GameState.selected_ending = ""
	get_tree().paused = false
	finished.emit()

func _draw() -> void:
	if not active:
		return
	var view := size
	var k := UIKit.pixel_scale(self)
	if ending_timer > -360.0:
		# the death fade of the kill: darkA = |KillTimer / 400|
		draw_rect(Rect2(Vector2.ZERO, view), Color(0.0, 0.0, 0.0, minf(absf(ending_timer) / 400.0 + 0.0, 1.0)))
		return
	var white := code == "b2" or code == "a1"
	var background := Color.BLACK
	if white:
		var value := maxf(255.0 + ending_timer * 2.8, 0.0) / 255.0
		background = Color(value, value, value)
	draw_rect(Rect2(Vector2.ZERO, view), background)
	if ending_timer <= -2000.0:
		_draw_credits(view, k)
		return
	if _picture == null:
		return
	var picture_size := Vector2(800.0, 800.0) * k
	var origin := (view - picture_size) * 0.5
	if ending_timer > -700.0:
		if randf() * 150.0 < minf(absf(ending_timer) - 200.0, 155.0):
			draw_texture_rect(_picture, Rect2(origin, picture_size), false)
		else:
			draw_rect(Rect2(Vector2(100.0, 100.0), view - Vector2(200.0, 200.0)), Color.BLACK)
	else:
		draw_texture_rect(_picture, Rect2(origin, picture_size), false)

func _draw_credits(view: Vector2, k: float) -> void:
	var scale_menu := view.y / 1024.0
	var regular := UIKit.font("regular")
	var bold := UIKit.font("bold")
	var regular_size := int(21.0 * scale_menu)
	var bold_size := int(35.0 * scale_menu)
	if _credits_picture != null and randi_range(1, 300) > 1:
		var picture_size := Vector2(800.0, 800.0) * k
		draw_texture_rect(_credits_picture, Rect2((view - picture_size) * 0.5, picture_size), false)
	var credits_y := (ending_timer + 2000.0) / 2.0 + (view.y + 10.0)
	var stay := 0
	for i in _credits.size():
		var line := _credits[i]
		if line.begins_with("/"):
			continue
		if i > _last_line:
			stay += 1
			continue
		var y := credits_y + 24.0 * i * scale_menu
		if y < -40.0 or y > view.y + 40.0:
			continue
		if line.begins_with("*"):
			_centered(bold, bold_size, line.substr(1), y, Color.WHITE)
		else:
			_centered(regular, regular_size, line.replace("\t", "    "), y, Color.WHITE)
	var last_y := credits_y + 24.0 * _last_line * scale_menu
	if last_y < -regular.get_height(regular_size):
		_credits_timer += 0.5 * get_process_delta_time() * 70.0
		var shade := 0.0
		if _credits_timer >= 0.0 and _credits_timer < 255.0:
			shade = _credits_timer / 255.0
		elif _credits_timer >= 255.0:
			shade = 1.0
			if _credits_timer > 500.0:
				_credits_timer = -255.0
		else:
			shade = clampf(-_credits_timer / 255.0, 0.0, 1.0)
			if _credits_timer >= -1.0:
				_finish()
				return
		var tail := Color(shade, shade, shade)
		for i in range(_last_line + 1, _credits.size()):
			var text := _credits[i].trim_prefix("/")
			var y := view.y * 0.5 + 24.0 * (i - _last_line) * scale_menu - (stay + 1) / 2.0 * 24.0 * scale_menu
			_centered(regular, regular_size, text.replace("\t", "    "), y, tail)

func _centered(font: Font, font_size: int, text: String, y: float, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, y + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
