extends CanvasLayer
# The keyboard of SCP-294 (Main.bb Use294): 294panel.jpg (1048 x 654, magenta is transparent) with a 10 x 5 grid of keys
# starting at (228, 342), 35.5 x 36.5 each (Data/SCP-294Keyboard.ini): digits 1..9 0, QWERTYUIOP, ASDFGHJKL and DISPENSE,
# ZXCVBNM - space and BACKSPACE, and a row of spaces. The display (centre at 907, 185) takes 15 characters. DISPENSE looks the
# text up in SCP-294.ini ("cup of" / "a cup of" in front is dropped): a drink plays its dispense sound and a cup appears at the
# machine's spout; anything else says OUT OF RANGE. The panel stays up while the sound plays (DISPENSING...), then goes. Right
# click or Escape puts it away. The game keeps running behind it.

const Scp294Data = preload("res://scripts/items/scp294_data.gd")

const IMAGE := "GFX/294panel.jpg"
const IMAGE_SIZE := Vector2(1048.0, 654.0)
const GRID_ORIGIN := Vector2(228.0, 342.0)
const TILE := Vector2(35.5, 36.5)
const DISPLAY_CENTRE := Vector2(907.0, 185.0)
const ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "DISPENSE"],
	["Z", "X", "C", "V", "B", "N", "M", "-", " ", "BACKSPACE"],
	[" ", " ", " ", " ", " ", " ", " ", " ", " ", " "],
]

var machine: Node = null          # the room's event: spawn_cup(name, colour, alpha) and dispensed()
var input := ""
var _sound: AudioStreamPlayer = null
var _sound_left := 0.0           # seconds of game time the dispense sound still has to run (the room's SoundCHN)
var _busy := false              # a dispense or an OUT OF RANGE sound is running
var _panel: TextureRect
var _display: Label
var _scale := 1.0
var _was_frozen := false
var _out_of_range := false

func _ready() -> void:
	add_to_group("scp294_panel")
	layer = 20
	visible = false
	_panel = TextureRect.new()
	_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tif (c.r > 0.96 && c.g < 0.04 && c.b > 0.96) { discard; }\n\tCOLOR = c;\n}\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	_panel.material = material
	var path := ContentPaths.existing_image(IMAGE)
	if FileAccess.file_exists(path):
		_panel.texture = ImageTexture.create_from_image(MeshLoader.load_image(path))
	add_child(_panel)
	_display = Label.new()
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_display)
	_panel.gui_input.connect(_on_panel_input)

func is_open() -> bool:
	return visible

func is_dispensing() -> bool:
	return _sound_left > 0.0

func open(for_machine: Node) -> void:
	machine = for_machine
	input = ""
	_busy = false
	_sound_left = 0.0
	_out_of_range = false
	_layout()
	visible = true
	GameState.using_294 = true
	_was_frozen = GameState.unable_to_move
	GameState.unable_to_move = true
	MouseCapture.release()
	_refresh()

func close() -> void:
	if not visible:
		return
	visible = false
	GameState.using_294 = false
	GameState.unable_to_move = _was_frozen
	input = ""
	machine = null
	var player: Node = GameState.player
	if player and not player.dead and OS.get_environment("SCP_BOT") != "1" and OS.get_environment("SCP_PROBE") != "1":
		MouseCapture.capture()

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_scale = minf(viewport_size.y * 0.8 / IMAGE_SIZE.y, viewport_size.x * 0.95 / IMAGE_SIZE.x)
	_panel.size = IMAGE_SIZE * _scale
	_panel.position = viewport_size * 0.5 - _panel.size * 0.5
	var font_size := int(round(30.0 * _scale))
	_display.add_theme_font_size_override("font_size", maxi(font_size, 12))
	_display.size = Vector2(300.0, 50.0) * _scale
	_display.position = DISPLAY_CENTRE * _scale - _display.size * 0.5

func _refresh() -> void:
	_display.text = input

func _physics_process(delta: float) -> void:
	if not visible:
		return
	if _busy:
		_sound_left = maxf(_sound_left - delta, 0.0)
		if _sound_left > 0.0:
			if not _out_of_range:
				input = "DISPENSING..."
		else:
			# the dispense sound is over: a drink closes the panel, OUT OF RANGE just clears the display
			var finished_drink := not _out_of_range
			_sound = null
			_busy = false
			_out_of_range = false
			input = ""
			if finished_drink:
				if machine != null and machine.has_method("dispensed"):
					machine.dispensed()
				close()
				return
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not is_dispensing():
		close()
		get_viewport().set_input_as_handled()

func _on_panel_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not is_dispensing():
			close()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		var image_point: Vector2 = event.position / _scale
		click_tile(int(floor((image_point.x - GRID_ORIGIN.x) / TILE.x)), int(floor((image_point.y - GRID_ORIGIN.y) / TILE.y)))

# MouseHit1 at a tile (column 0..9, row 0..4).
func click_tile(column: int, row: int) -> void:
	if not visible or is_dispensing():
		return
	if row < 0 or row > 4 or column < 0 or column > 9:
		return
	_sound_button()
	var key: String = ROWS[row][column]
	match key:
		"DISPENSE":
			_dispense()
			return
		"BACKSPACE":
			input = input.substr(0, maxi(input.length() - 1, 0))
		_:
			input += key
	input = input.substr(0, mini(input.length(), 15))
	_refresh()

# Typing for the tests: one click per character, then DISPENSE.
func type_and_dispense(text: String) -> void:
	input = ""
	for ch in text.to_upper():
		for row in ROWS.size():
			var column: int = (ROWS[row] as Array).find(String(ch))
			if column >= 0 and (ROWS[row][column] != "DISPENSE" and ROWS[row][column] != "BACKSPACE"):
				click_tile(column, row)
				break
	click_tile(9, 2)

func _dispense() -> void:
	if input.is_empty():
		return
	input = input.strip_edges().to_lower()
	if input.begins_with("cup of "):
		input = input.substr(7)
	elif input.begins_with("a cup of "):
		input = input.substr(9)
	if input.is_empty():
		return
	var drink := Scp294Data.find(input)
	if not drink.is_empty():
		var relative := str(drink.get("dispensesound", "")).replace("\\", "/")
		if relative.is_empty():
			relative = "SFX/SCP/294/dispense1.ogg"
		_sound = _play(relative)
		_sound_left = _length_of(relative)
		_busy = true
		_out_of_range = false
		if Scp294Data.get_int(drink, "explosion") != 0:
			GameState.explosion_timer = 135.0
			GameState.death_msg = str(drink.get("deathmessage", ""))
		var alpha := Scp294Data.get_float(drink, "alpha", 1.0)
		if Scp294Data.get_int(drink, "glow") != 0:
			alpha = -alpha
		if machine != null and machine.has_method("spawn_cup"):
			machine.spawn_cup("Cup of " + input, Scp294Data.get_color(drink), alpha)
	else:
		input = "OUT OF RANGE"
		_out_of_range = true
		_sound = _play("SFX/SCP/294/outofrange.ogg")
		_sound_left = _length_of("SFX/SCP/294/outofrange.ogg")
		_busy = true
	_refresh()

func _play(relative: String) -> AudioStreamPlayer:
	var path := ContentPaths.existing_file(relative)
	if not FileAccess.file_exists(path):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = AudioStreamOggVorbis.load_from_file(path)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free, CONNECT_DEFERRED)
	return player

func _sound_button() -> void:
	_play("SFX/Interact/Button.ogg")

func _length_of(relative: String) -> float:
	var path := ContentPaths.existing_file(relative)
	if not FileAccess.file_exists(path):
		return 0.1
	return maxf(AudioStreamOggVorbis.load_from_file(path).get_length(), 0.1)
