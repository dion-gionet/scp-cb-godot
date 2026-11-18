extends Control
# The developer console (Main.bb UpdateConsole): F3 opens a 300-pixel panel along the bottom with the output above a one-line
# input; the game stops while it is open. Enter runs the line, Up and Down bring back earlier commands, Tab completes, the
# wheel and the bar scroll. Commands live in debug_commands.gd. Messages: yellow commands, white replies, cyan help, green
# status, orange warnings, red errors.


var is_open := false
var messages: Array = []            # [{text, color, command}] oldest first
var history: Array[String] = []
var _history_index := -1
var _commands: RefCounted
var _panel: Panel
var _log: RichTextLabel
var entry_box: LineEdit
var _was_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_commands = DebugCommands.new(self)
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.92)
	style.border_color = Color(0.8, 0.8, 0.8)
	style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.add_theme_font_override("normal_font", UIKit.font("regular"))
	_panel.add_child(_log)
	entry_box = LineEdit.new()
	entry_box.max_length = 100
	entry_box.caret_blink = true
	entry_box.add_theme_font_override("font", UIKit.font("regular"))
	entry_box.text_submitted.connect(_submit)
	entry_box.gui_input.connect(_input_keys)
	_panel.add_child(entry_box)
	get_viewport().size_changed.connect(_layout)
	_layout()
	for text in ContentPaths.load_errors:
		say(text, Color(1, 0, 0))
	ContentPaths.load_failed.connect(_on_load_failed)

func _on_load_failed(text: String) -> void:
	say(text, Color(1, 0, 0))
	if GameState.console_on_error and not is_open:
		_open()

func _layout() -> void:
	var size_now := get_viewport_rect().size
	var scale_value := size_now.y / 1024.0
	var height := 300.0 * scale_value
	_panel.position = Vector2(0.0, size_now.y - height)
	_panel.size = Vector2(size_now.x, height)
	var font_size := maxi(int(15.0 * scale_value), 12)
	_log.add_theme_font_size_override("normal_font_size", font_size)
	entry_box.add_theme_font_size_override("font_size", font_size)
	var input_height := 30.0 * scale_value
	_log.position = Vector2(6.0, 4.0)
	_log.size = Vector2(size_now.x - 12.0, height - input_height - 8.0)
	entry_box.position = Vector2(0.0, height - input_height)
	entry_box.size = Vector2(size_now.x, input_height)

func say(text: String, color: Color = Color.WHITE, command: bool = false) -> void:
	messages.append({"text": text, "color": color, "command": command})
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "[lb]")])

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode) == GameState.console_key() and GameState.console_enabled:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and is_open:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if is_open:
		_close()
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if GameState.player == null or (hud != null and (hud.pause_menu.visible or hud.inventory_open or hud.ending_active())):
		return
	_open()

func _open() -> void:
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	MouseCapture.release()
	entry_box.clear()
	entry_box.grab_focus.call_deferred()
	_history_index = -1

func _close() -> void:
	is_open = false
	visible = false
	GameState.used_console = true
	entry_box.release_focus()
	get_tree().paused = _was_paused
	var player := GameState.player
	if player != null and not player.dead and not _was_paused:
		MouseCapture.capture()

func _submit(line: String) -> void:
	var text := line.strip_edges()
	entry_box.clear()
	_history_index = -1
	if text.is_empty():
		return
	history.append(text)
	say(text, Color(1, 1, 0), true)
	for entry in _commands.run(text):
		say(str(entry[0]), entry[1])
	entry_box.grab_focus.call_deferred()

# Up and Down walk the earlier commands (the original goes through the messages that were commands), Tab completes.
func _input_keys(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP:
			if not history.is_empty():
				_history_index = history.size() - 1 if _history_index < 0 else (_history_index - 1 + history.size()) % history.size()
				entry_box.text = history[_history_index]
				entry_box.caret_column = entry_box.text.length()
			entry_box.accept_event()
		KEY_DOWN:
			if not history.is_empty():
				_history_index = 0 if _history_index < 0 else (_history_index + 1) % history.size()
				entry_box.text = history[_history_index]
				entry_box.caret_column = entry_box.text.length()
			entry_box.accept_event()
		KEY_TAB:
			_complete()
			entry_box.accept_event()
		KEY_ESCAPE:            # the focused line edit takes the key before _unhandled_input sees it
			_toggle()
			entry_box.accept_event()

func _complete() -> void:
	var text := entry_box.text
	var space := text.find(" ")
	var pool: Array[String] = []
	var prefix := text.to_lower()
	var lead := ""
	if space < 0:
		pool = _commands.command_names()
	else:
		var command := text.substr(0, space).to_lower()
		lead = text.substr(0, space + 1)
		prefix = text.substr(space + 1).to_lower()
		match command:
			"teleport":
				var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
				for record in facility.generator.rooms:
					if not pool.has(str(record.name)):
						pool.append(str(record.name))
			"spawn":
				for key in _commands.SPAWN_ALIASES:
					pool.append(str(key))
			"spawnitem":
				for entry in RoomFill.spawnable():
					pool.append(str(entry.name).to_lower())
			"help":
				for key in _commands.HELP:
					pool.append(str(key))
			"ending":
				pool = ["a1", "a2", "b1", "b2", "b3"]
			"unlockexits":
				pool = ["a", "b"]
	var matches: Array[String] = []
	for candidate in pool:
		if candidate.to_lower().begins_with(prefix):
			matches.append(candidate)
	if matches.is_empty():
		return
	matches.sort()
	if matches.size() == 1:
		entry_box.text = lead + matches[0] + (" " if space < 0 else "")
	else:
		var common := matches[0]
		for candidate in matches:
			while not candidate.to_lower().begins_with(common.to_lower()):
				common = common.substr(0, common.length() - 1)
		entry_box.text = lead + common
		say("  ".join(matches.slice(0, 24)) + (" ..." if matches.size() > 24 else ""), Color(0.6, 0.6, 0.6))
	entry_box.caret_column = entry_box.text.length()

func execute(line: String, echo: bool = true) -> void:
	if echo:
		say(line, Color(1, 1, 0), true)
		history.append(line)
	for entry in _commands.run(line):
		say(str(entry[0]), entry[1])

func _exit_tree() -> void:
	if is_open and get_tree() != null:
		get_tree().paused = _was_paused
