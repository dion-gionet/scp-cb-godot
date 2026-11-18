extends CanvasLayer
# The door keypad (Main.bb DrawGUI, "SelectedDoor"). The original moves the camera 0.22 in front of the
# pressed keypad and points it there, so the 3D keypad on the wall is what you see; KeyPadHUD.jpg (317 x 462)
# is loaded but never drawn, only its size places the text and the 4 x 3 grid of buttons:
# 1 2 3 0 / 4 5 6 ENTER / 7 8 9 CLEAR. The game is paused while it is open; right click or Escape puts it away.
# Four digits at most.

const IMAGE_SIZE := Vector2(317.0, 462.0)
# Main.bb 4887-4900: the HUD scale is the projected height of +-MeshHeight(Button.x)*0.015 over 462.
const BUTTON_MESH_HEIGHT := 5.04473
const VIEW_DISTANCE := 0.22
const CELL_ORIGIN := Vector2(44.0, 249.0)   # of the first button, in image pixels
const CELL_SIZE := Vector2(54.0, 65.0)
const CELL_PITCH := Vector2(58.5, 67.0)
# (n + 1) + row * 4 -> what the button does
const KEYS := {1: "1", 2: "2", 3: "3", 4: "0", 5: "4", 6: "5", 7: "6", 8: "ENTER", 9: "7", 10: "8", 11: "9", 12: "CLEAR"}

var door: Node3D
var button: Node3D
var _camera: Camera3D = null
var _camera_saved := Transform3D.IDENTITY
var input := ""
var message := ""
var _timer := 0.0            # frames, counting down while ACCESS DENIED blinks
var _panel: Control
var _title: Label
var _entry: Label
var _scale := 1.0
var _small_font := 22      # Font3 and Font4 (DS-Digital 22 and 60 x height / 1024)
var _large_font := 60
var _cells: Array[Control] = []

func _ready() -> void:
	add_to_group("keypad")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_title = _make_label()
	_entry = _make_label()
	for index in range(1, 13):
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_cell_input.bind(index))
		_panel.add_child(cell)
		_cells.append(cell)

func _make_label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UIKit.font("digital"))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
	return label

func is_open() -> bool:
	return visible

func open(for_door: Node3D, pressed: Node3D = null) -> void:
	door = for_door
	button = pressed
	input = ""
	message = ""
	_timer = 0.0
	_face_button()
	_layout()
	visible = true
	get_tree().paused = true
	MouseCapture.release()
	_refresh()

func close() -> void:
	visible = false
	door = null
	button = null
	if _camera != null and is_instance_valid(_camera):
		_camera.transform = _camera_saved
	_camera = null
	get_tree().paused = false
	var player: Node = GameState.player
	if player and not player.dead and OS.get_environment("SCP_BOT") != "1" and OS.get_environment("SCP_PROBE") != "1":
		MouseCapture.capture()

# A pivot at the button, turned to its yaw - 180 and moved 0.22 along it: the camera stands there and points at the button.
func _face_button() -> void:
	var player: Node = GameState.player
	if button == null or not is_instance_valid(button) or player == null or not "camera" in player:
		return
	var outward := button.global_transform.basis.z
	outward.y = 0.0
	if outward.length() < 0.0001:
		return
	_camera = player.camera
	_camera_saved = _camera.transform
	var at := button.global_position
	_camera.global_position = at + outward.normalized() * VIEW_DISTANCE
	_camera.look_at(at, Vector3.UP)

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if _camera != null and button != null:
		var half := Vector3(0.0, BUTTON_MESH_HEIGHT * 0.015, 0.0)
		var top := _camera.unproject_position(button.global_position + half)
		var bottom := _camera.unproject_position(button.global_position - half)
		_scale = absf(bottom.y - top.y) / 462.0
	else:
		_scale = viewport_size.x * BUTTON_MESH_HEIGHT * 0.015 / (VIEW_DISTANCE * 462.0)    # 90 degrees across, 0.22 away
	var size := IMAGE_SIZE * _scale
	_panel.size = size
	_panel.position = viewport_size * 0.5 - size * 0.5
	for i in _cells.size():
		var n := i % 4
		var row := i / 4
		_cells[i].position = (CELL_ORIGIN + Vector2(CELL_PITCH.x * n, CELL_PITCH.y * row)) * _scale
		_cells[i].size = CELL_SIZE * _scale
	# AAText centred on y: Font3 for the title and the message, Font4 for the digits
	var menu_scale := viewport_size.y / 1024.0
	_small_font = UIKit.font_size("digital", menu_scale)
	_large_font = UIKit.font_size("digital_large", menu_scale)
	_title.add_theme_font_size_override("font_size", _small_font)
	_title.size = Vector2(size.x, _small_font * 2.0)
	_title.position = Vector2(0.0, 70.0 * _scale - _small_font)
	_entry.add_theme_font_size_override("font_size", _large_font)
	_entry.size = Vector2(size.x, _large_font * 2.0)
	_entry.position = Vector2(0.0, 124.0 * _scale - _large_font)

func _refresh() -> void:
	if message.is_empty():
		_title.text = "ACCESS CODE: "
		_entry.text = input
	else:
		_title.text = ""
		_entry.text = message if int(_timer) % 70 < 35 else ""

func _process(delta: float) -> void:
	if not visible:
		return
	if not message.is_empty():
		_timer -= delta * 70.0
		_refresh()
		if _timer <= 0.0:
			close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()

func _on_cell_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press(index)

# One of the twelve buttons (1..12); the same code path the mouse uses.
func press(index: int) -> void:
	if not visible or not message.is_empty() or door == null:
		return
	_sound("SFX/Interact/Button.ogg")
	var key: String = KEYS[index]
	match key:
		"ENTER":
			if input == door.code:
				_sound("SFX/Interact/ScannerUse1.ogg")
				if door.code == GameState.access_code:
					GameState.give_achievement("maynard")
				elif door.code == "7816":
					GameState.give_achievement("harp")
				var target := door
				close()
				target.keypad_open()
				return
			_sound("SFX/Interact/ScannerUse2.ogg")
			message = "ACCESS DENIED"
			_entry.add_theme_font_size_override("font_size", _small_font)
			_timer = 210.0
			input = ""
		"CLEAR":
			input = ""
		_:
			input += key
			if input.length() > 4:
				input = input.substr(0, 4)
	_refresh()

func _sound(relative: String) -> void:
	var source := Sfx.stream(relative)
	if source == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = source
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
