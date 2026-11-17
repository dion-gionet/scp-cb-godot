extends SceneTree
# One-off data extraction from the 1.3.11 Blitz source:
#   godot --headless --path . -s tools/extract_fill_room.gd
# Reads MapSystem.bb (FillRoom) and Items.bb (InitItemTemplates) and writes
# data/room_fill.json with, per room template: doors and items in room-local Blitz metres
# (x, y, z as written in the source with RoomScale applied), plus item template icons.
# Calls whose coordinates are not plain arithmetic on r\x / r\y / r\z are skipped and counted.

const ROOM_SCALE := 8.0 / 2048.0

var _tokens: Array[String] = []
var _pos := 0
var _fail := false

func _initialize() -> void:
	var root := OS.get_environment("SCP_BLITZ_SRC")
	if root.is_empty():
		push_error("set SCP_BLITZ_SRC to a checkout of https://github.com/Regalis11/scpcb")
		quit(1)
		return
	var map_text := FileAccess.get_file_as_string(root.path_join("MapSystem.bb"))
	var items_text := FileAccess.get_file_as_string(root.path_join("Items.bb"))
	if map_text.is_empty() or items_text.is_empty():
		push_error("source files not found under %s" % root)
		quit(1)
		return
	var result := {"rooms": {}, "item_templates": {}, "item_variants": {}, "item_order": []}
	var stats := {"doors": 0, "doors_skipped": 0, "items": 0, "items_skipped": 0}
	_extract_rooms(map_text, result.rooms, stats)
	_extract_item_templates(items_text, result.item_templates, result.item_variants, result.item_order)
	var out_dir := ProjectSettings.globalize_path("res://data")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(out_dir.path_join("room_fill.json"), FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % out_dir.path_join("room_fill.json"))
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t", true))
	file.close()
	print("EXTRACT rooms=", result.rooms.size(), " templates=", result.item_templates.size(), " ", stats)
	quit()

# ------------------------------------------------------------------ FillRoom

func _extract_rooms(text: String, rooms: Dictionary, stats: Dictionary) -> void:
	var lines := text.split("\n")
	var start := -1
	var end := -1
	for i in lines.size():
		if start < 0 and lines[i].begins_with("Function FillRoom("):
			start = i
		elif start >= 0 and lines[i].begins_with("End Function"):
			end = i
			break
	var names: Array[String] = []
	var block_start := -1
	for i in range(start, end + 1):
		var line := _strip_comment(lines[i])
		var case_names := _top_level_case(line)
		if not case_names.is_empty() or i == end:
			if block_start >= 0:
				_extract_block(lines, block_start, i, names, rooms, stats)
			names = case_names
			block_start = i + 1
	print("EXTRACT FillRoom lines ", start + 1, "..", end + 1)

func _top_level_case(line: String) -> Array[String]:
	var result: Array[String] = []
	if not line.begins_with("		Case \""):
		return result
	var rest := line.substr(2).strip_edges()
	for part in _split_args(rest.trim_prefix("Case")):
		var p := part.strip_edges()
		if p.begins_with("\"") and p.ends_with("\"") and p.length() >= 2:
			result.append(p.substr(1, p.length() - 2).to_lower())
	return result

# A Case that serves several templates ("room2gw", "room2gw_b") may keep a branch for one of them (If r\RoomTemplate\Name = "room2gw_b"):
# the lines in it belong to that template only, so the block is read once per template then.
func _extract_block(lines: PackedStringArray, from: int, to: int, names: Array[String], rooms: Dictionary, stats: Dictionary) -> void:
	var guards := _template_guards(lines, from, to)
	for room_name in names:
		var only := room_name if not guards.is_empty() else ""
		var found := _collect_block(lines, from, to, only, guards, stats if room_name == names[0] else {"doors": 0, "doors_skipped": 0, "items": 0, "items_skipped": 0})
		var exact: bool = found.exact
		if rooms.has(room_name):
			exact = false
		var entry: Dictionary = rooms.get(room_name, {"doors": [], "items": [], "objects": {}, "cams": []})
		entry["draws"] = found.draws if exact else -1
		entry.doors.append_array(found.doors)
		entry.items.append_array(found.items)
		entry.cams.append_array(found.cams)
		for key in found.objects:
			entry.objects[key] = found.objects[key]
		rooms[room_name] = entry

# The line numbers inside an `If r\RoomTemplate\Name = "x"` block (up to its EndIf), with the template they are for.
func _template_guards(lines: PackedStringArray, from: int, to: int) -> Dictionary:
	var guards := {}
	var regex := RegEx.create_from_string("^If\\s+r\\\\RoomTemplate\\\\Name\\s*=\\s*\"([^\"]+)\"\\s*(Then)?\\s*$")
	var depth := 0
	var open_name := ""
	var open_depth := 0
	for i in range(from, to):
		var line := _strip_comment(lines[i]).strip_edges()
		var flow := _draw_flow(line, depth)
		var found := regex.search(line)
		if open_name.is_empty() and found != null:
			open_name = found.get_string(1).to_lower()
			open_depth = depth
		elif not open_name.is_empty():
			if int(flow.depth_after) <= open_depth:
				open_name = ""
			else:
				guards[i] = open_name
		depth = int(flow.depth_after)
	return guards

func _collect_block(lines: PackedStringArray, from: int, to: int, only: String, guards: Dictionary, stats: Dictionary) -> Dictionary:
	var doors: Array = []
	var items: Array = []
	var objects: Dictionary = {}
	var cams := _parse_cams(lines, from, to)
	var draws := 0
	var exact := true
	var depth := 0
	var loop := {}
	for i in range(from, to):
		var line := _strip_comment(lines[i])
		if guards.has(i) and guards[i] != only:
			var skipped := _draw_flow(line, depth)
			depth = int(skipped.depth_after)
			continue
		loop = _track_for_loop(line, loop)
		var flow := _draw_flow(line, depth)
		var line_draws := _draw_calls(line)
		for call in line_draws:
			if call.at >= int(flow.then_at) or int(flow.depth_before) > 0:
				call["conditional"] = true
		depth = int(flow.depth_after)
		var at := line.find("CreateDoor(")
		if at >= 0:
			var door := _parse_door(lines, i, line, at)
			if door.is_empty():
				stats.doors_skipped += 1
			else:
				stats.doors += 1
				doors.append(door)
		_parse_object_position(line, objects)
		_parse_button_push(line, loop, doors)
		at = line.find("CreateItem(")
		if at >= 0:
			var item := _parse_item(line, at)
			if item.is_empty():
				stats.items_skipped += 1
			else:
				_parse_item_state(lines, i, line, at, item)
				var before := draws
				var exact_before := exact
				for call in line_draws:
					if int(call.at) >= at:
						break
					before += 1
					exact_before = exact_before and not call.has("conditional")
				var close := _matching_paren(line, at + "CreateItem".length())
				for call in line_draws:
					if int(call.at) > at and int(call.at) < close:
						before += 1
						exact_before = exact_before and not call.has("conditional")
				item["draw"] = before if exact_before else -1
				stats.items += 1
				items.append(item)
		for call in line_draws:
			draws += 1
			exact = exact and not call.has("conditional")
	return {"doors": doors, "items": items, "objects": objects, "cams": cams, "draws": draws, "exact": exact}

# The calls on a line that draw a random number, in order: Rand and Rnd, CreateDoor (Rand(8), after its arguments) and
# CreateItem (Rand(360), after its arguments).
static var _draw_re: RegEx = null

func _draw_calls(line: String) -> Array[Dictionary]:
	if _draw_re == null:
		_draw_re = RegEx.create_from_string("(?<![A-Za-z0-9_\\\\])(Rand|Rnd|CreateDoor|CreateItem)\\s*\\(")
	var out: Array[Dictionary] = []
	for m in _draw_re.search_all(line):
		out.append({"at": m.get_start(), "name": m.get_string(1)})
	return out

# How a line nests: draws inside an If, loop or Select body, after the Then of a one-line If, or in a loop header may not be
# made exactly once, so the draws after them have no fixed index.
func _draw_flow(line: String, depth: int) -> Dictionary:
	var out := {"depth_before": depth, "depth_after": depth, "then_at": line.length() + 1}
	var words := line.strip_edges().to_lower().replace("(", " ").split(" ", false)
	if words.is_empty():
		return out
	match words[0]:
		"if":
			var then_at := line.to_lower().find(" then")
			if then_at >= 0 and not line.substr(then_at + 5).strip_edges().is_empty():
				out.then_at = then_at + 5
			else:
				out.depth_after = depth + 1
		"endif":
			out.depth_after = maxi(depth - 1, 0)
		"end":
			if words.size() > 1 and words[1] in ["if", "select"]:
				out.depth_after = maxi(depth - 1, 0)
		"for", "while", "repeat", "select":
			out.depth_before = depth + 1
			out.depth_after = depth + 1
		"next", "wend", "until", "forever":
			out.depth_after = maxi(depth - 1, 0)
	return out

func _matching_paren(line: String, open_at: int) -> int:
	var level := 0
	for i in range(open_at, line.length()):
		if line[i] == "(":
			level += 1
		elif line[i] == ")":
			level -= 1
			if level == 0:
				return i
	return line.length()

func _parse_door(lines: PackedStringArray, index: int, line: String, at: int) -> Dictionary:
	var args := _call_args(line, at + "CreateDoor".length())
	if args.size() < 5:
		return {}
	var x: Variant = _eval(args[1])
	var y: Variant = _eval(args[2])
	var z: Variant = _eval(args[3])
	var angle: Variant = _eval(args[4])
	if x == null or y == null or z == null or angle == null:
		return {}
	var door := {
		"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001),
		"yaw": float(angle), "open": false, "big": 0, "keycard": 0, "code": "",
		"locked": false, "buttons": true, "single": false, "slot": -1, "free_buttons": [],
	}
	if args.size() > 6:
		door.open = _truthy(args[6])
	if args.size() > 7:
		var big: Variant = _eval(args[7])
		door.big = int(big) if big != null else 0
	if args.size() > 8:
		var key: Variant = _eval(args[8])
		door.keycard = int(key) if key != null else 0
	if args.size() > 9:
		var code := args[9].strip_edges()
		if code.begins_with("\"") and code.ends_with("\"") and code.length() >= 2:
			door.code = code.substr(1, code.length() - 2)
		elif code == "Str(AccessCode)":
			door.code = "$ACCESS"        # the run's four-digit AccessCode
		elif code == "temp":
			door.code = "$ACCESS3"       # room2tunnel: (AccessCode * 3) mod 10000, at least 1000
	if args.size() > 10 and _truthy(args[10]):
		door.hit_mesh = true
	# the variable the door is assigned to, e.g. "d" or "r\RoomDoors[1]"
	var left := line.substr(0, line.find("CreateDoor(")).strip_edges()
	var variable := ""
	if left.ends_with("="):
		variable = left.trim_suffix("=").strip_edges().replace(".Doors", "")
	if variable.contains("RoomDoors["):
		var open_bracket := variable.find("[")
		door.slot = int(variable.substr(open_bracket + 1, variable.find("]") - open_bracket - 1))
	var unparented := {}
	if not variable.is_empty():
		var last := mini(index + 9, lines.size() - 1)
		for j in range(index + 1, last + 1):
			var follow := _strip_comment(lines[j])
			if follow.contains("CreateDoor("):
				break
			for statement in follow.split(":"):
				var s := statement.strip_edges()
				if s.begins_with("r\\RoomDoors[") and s.replace(" ", "").ends_with("]=" + variable):
					door.slot = int(s.substr(s.find("[") + 1, s.find("]") - s.find("[") - 1))
				elif s.begins_with(variable + "\\"):
					var attr := s.substr(variable.length() + 1)
					var eq := attr.find("=")
					if eq > 0:
						var key := attr.substr(0, eq).strip_edges().to_lower()
						var value := attr.substr(eq + 1).strip_edges()
						match key:
							"locked":
								door.locked = _truthy(value)
							"open":
								door.open = _truthy(value)
							"dir":
								var dir_value: Variant = _eval(value)
								if dir_value != null:
									door["dir"] = int(dir_value)
				elif s.begins_with("EntityParent") and s.contains(variable + "\\buttons["):
					var parent_args := _entity_args(s, "EntityParent")
					var parent_index := _button_index(parent_args[0], variable)
					if parent_index >= 0 and parent_args.size() >= 2:
						if parent_args[1].strip_edges() == "0":
							unparented[parent_index] = true
						else:
							unparented.erase(parent_index)
				elif s.begins_with("PositionEntity") and s.contains(variable + "\\buttons["):
					_parse_button_move(s, variable, door, unparented)
				elif s.begins_with("RotateEntity") and s.contains(variable + "\\buttons["):
					_parse_button_turn(s, variable, door, unparented)
				elif s.begins_with("FreeEntity") and s.contains(variable + "\\buttons["):
					var freed := _button_index(_entity_args(s, "FreeEntity")[0], variable)
					for i in ([freed] if freed >= 0 else [0, 1]):
						if not door.free_buttons.has(i):
							door.free_buttons.append(i)
					door.buttons = door.free_buttons.size() < 2
				elif s.begins_with("FreeEntity") and s.contains(variable + "\\obj2"):
					door.single = true
	if door.free_buttons.is_empty():
		door.erase("free_buttons")
	return door

func _parse_item(line: String, at: int) -> Dictionary:
	var args := _call_args(line, at + "CreateItem".length())
	if args.size() < 5:
		return {}
	var item_name := args[0].strip_edges()
	var tempname := args[1].strip_edges()
	if not (item_name.begins_with("\"") and tempname.begins_with("\"")):
		return {}
	var x: Variant = _eval(args[2])
	var y: Variant = _eval(args[3])
	var z: Variant = _eval(args[4])
	if x == null or y == null or z == null:
		return {}
	return {
		"name": item_name.trim_prefix("\"").trim_suffix("\""),
		"tempname": tempname.trim_prefix("\"").trim_suffix("\""),
		"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001),
	}

# ------------------------------------------------------------------ Items.bb

func _extract_item_templates(text: String, out: Dictionary, variants: Dictionary, order: Array) -> void:
	var lines := text.split("\n")
	for index in lines.size():
		var line := _strip_comment(lines[index])
		var at := line.find("CreateItemTemplate(")
		if at < 0 or line.begins_with("Function"):
			continue
		var args := _call_args(line, at + "CreateItemTemplate".length())
		if args.size() < 4:
			continue
		var item_name := _unquote(args[0])
		if item_name.is_empty():
			continue
		# "it\sound = N" is on the same line or the next one; PickSFX(N), 66 = silent, default 0
		var sound := _sound_of(line.substr(at))
		if sound < 0 and index + 1 < lines.size():
			sound = _sound_of(_strip_comment(lines[index + 1]))
		var entry := {
			"tempname": _unquote(args[1]),
			"model": _unquote(args[2]).replace("\\", "/"),
			"icon": _unquote(args[3]).replace("\\", "/"),
			"image": _unquote(args[4]).replace("\\", "/") if args.size() > 4 else "",
			"scale": float(_eval(args[5])) if args.size() > 5 and _eval(args[5]) != null else 1.0,
			"texture": _unquote(args[6]).replace("\\", "/") if args.size() > 6 else "",
			"sound": maxi(sound, 0),
		}
		out[item_name] = entry
		order.append([item_name, entry.tempname])      # ItemTemplates is walked in this order (SCP-1162)
		variants["%s|%s" % [item_name, entry.tempname]] = entry

func _sound_of(line: String) -> int:
	var matcher := RegEx.new()
	var bs := char(92)
	matcher.compile("sound%ss*=%ss*(%sd+)" % [bs, bs, bs])
	var found := matcher.search(line)
	return int(found.get_string(1)) if found else -1

func _unquote(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with("\"") and t.ends_with("\"") and t.length() >= 2:
		return t.substr(1, t.length() - 2)
	return ""

func _strip_comment(line: String) -> String:
	var in_quote := false
	for i in line.length():
		var c := line[i]
		if c == "\"":
			in_quote = not in_quote
		elif c == ";" and not in_quote:
			return line.substr(0, i).trim_suffix("\r")
	return line.trim_suffix("\r")

func _call_args(line: String, open_at: int) -> Array[String]:
	# open_at points just before the "(" of the call
	var open := line.find("(", open_at)
	if open < 0:
		return []
	var depth := 0
	var in_quote := false
	for i in range(open, line.length()):
		var c := line[i]
		if c == "\"":
			in_quote = not in_quote
		elif not in_quote:
			if c == "(":
				depth += 1
			elif c == ")":
				depth -= 1
				if depth == 0:
					return _split_args(line.substr(open + 1, i - open - 1))
	return []

func _split_args(text: String) -> Array[String]:
	var parts: Array[String] = []
	var depth := 0
	var in_quote := false
	var current := ""
	for i in text.length():
		var c := text[i]
		if c == "\"":
			in_quote = not in_quote
		if not in_quote:
			if c == "(":
				depth += 1
			elif c == ")":
				depth -= 1
			elif c == "," and depth == 0:
				parts.append(current)
				current = ""
				continue
		current += c
	parts.append(current)
	return parts

func _truthy(text: String) -> bool:
	var t := text.strip_edges().to_lower()
	if t == "true":
		return true
	if t == "false" or t.is_empty():
		return false
	var v: Variant = _eval(t)
	return v != null and float(v) != 0.0

# Evaluates +, -, *, /, parentheses over numbers, RoomScale, True/False and r\x r\y r\z (as 0).
func _eval(expression: String) -> Variant:
	_tokens = _tokenize(expression)
	_pos = 0
	_fail = false
	if _tokens.is_empty():
		return null
	var value := _expr()
	if _fail or _pos != _tokens.size():
		return null
	return value

func _tokenize(text: String) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == " " or c == "\t":
			i += 1
		elif "+-*/()".contains(c):
			out.append(c)
			i += 1
		elif c.is_valid_int() or c == ".":
			var j := i
			while j < text.length() and (text[j].is_valid_int() or text[j] == "."):
				j += 1
			out.append(text.substr(i, j - i))
			i = j
		elif c.to_lower() != c.to_upper() or c == "_" or c == "\\":
			var j := i
			while j < text.length() and (text[j].to_lower() != text[j].to_upper() or text[j].is_valid_int() or text[j] == "_" or text[j] == "\\" or text[j] == "[" or text[j] == "]"):
				j += 1
			out.append(text.substr(i, j - i))
			i = j
		else:
			out.append(c)
			i += 1
	return out

func _expr() -> float:
	var value := _term()
	while not _fail and _pos < _tokens.size() and (_tokens[_pos] == "+" or _tokens[_pos] == "-"):
		var op := _tokens[_pos]
		_pos += 1
		var rhs := _term()
		value = value + rhs if op == "+" else value - rhs
	return value

func _term() -> float:
	var value := _factor()
	while not _fail and _pos < _tokens.size() and (_tokens[_pos] == "*" or _tokens[_pos] == "/"):
		var op := _tokens[_pos]
		_pos += 1
		var rhs := _factor()
		if op == "*":
			value *= rhs
		elif rhs == 0.0:
			_fail = true
		else:
			value /= rhs
	return value

func _factor() -> float:
	if _pos >= _tokens.size():
		_fail = true
		return 0.0
	var token := _tokens[_pos]
	_pos += 1
	if token == "-":
		return -_factor()
	if token == "+":
		return _factor()
	if token == "(":
		var inner := _expr()
		if _pos < _tokens.size() and _tokens[_pos] == ")":
			_pos += 1
		else:
			_fail = true
		return inner
	if token.is_valid_float():
		return float(token)
	match token.to_lower():
		"roomscale":
			return ROOM_SCALE
		"r\\x", "r\\y", "r\\z":
			return 0.0
		"true":
			return 1.0
		"false":
			return 0.0
	_fail = true
	return 0.0

# PositionEntity(r\Objects[N], x, y, z[, True]) -> room-local marker N (cabs, waypoints...).
func _parse_object_position(line: String, objects: Dictionary) -> void:
	var at := line.find("PositionEntity")
	if at < 0:
		return
	var rest := line.substr(at + "PositionEntity".length()).strip_edges()
	if rest.begins_with("("):
		var close := rest.rfind(")")
		rest = rest.substr(1, close - 1) if close > 0 else rest.substr(1)
	var args := _split_args(rest)
	if args.size() < 4:
		return
	var target := args[0].strip_edges()
	if not target.to_lower().begins_with("r" + char(92) + "objects["):
		return
	var index_text := target.substr(10, target.find("]") - 10).strip_edges()
	if not index_text.is_valid_int():
		return
	var index := int(index_text)
	var x: Variant = _eval(args[1])
	var y: Variant = _eval(args[2])
	var z: Variant = _eval(args[3])
	if x == null or y == null or z == null:
		return
	objects[str(index)] = {"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001)}

# PositionEntity(d\buttons[i], x, y, z[, True]): a button moved to a global (room-relative) spot. Each axis is either an
# expression over r\x / r\y / r\z (stored) or EntityX / EntityY / EntityZ(<some button>, True), which keeps the button's own
# value on that axis (left out of "button_move"), so the sources that only change x or only z keep the rest of the default spot.
# Without the True flag the position is global only while the button is unparented (the lockrooms'
# EntityParent(d\buttons[i], 0) ... EntityParent(d\buttons[i], r\obj)), which "unparented" lists.
func _parse_button_move(statement: String, variable: String, door: Dictionary, unparented: Dictionary) -> void:
	var args := _entity_args(statement, "PositionEntity")
	if args.size() < 4:
		return
	var index := _button_index(args[0], variable)
	if index < 0:
		return
	if not (args.size() >= 5 and _truthy(args[4])) and not unparented.has(index):
		return
	var spot := {}
	for axis in 3:
		var axis_name: String = "xyz"[axis]
		var arg := args[axis + 1].strip_edges()
		if _kept_axis(arg, axis_name):
			continue
		var value: Variant = _eval(arg)
		if value == null:
			return
		spot[axis_name] = snappedf(float(value), 0.0001)
	if not spot.is_empty():
		_merge_button_move(door, index, spot)

func _merge_button_move(door: Dictionary, index: int, spot: Dictionary) -> void:
	var moves: Dictionary = door.get_or_add("button_move", {})
	var previous: Dictionary = moves.get(str(index), {})
	previous.merge(spot, true)
	moves[str(index)] = previous

static var _keep_re: RegEx = null

# The number in "<variable>\buttons[n]" (-1 when n is a loop variable or the text is another entity).
func _button_index(target: String, variable: String) -> int:
	var text := target.strip_edges()
	if not text.begins_with(variable + "\\buttons["):
		return -1
	var open_bracket := text.rfind("[")
	var number := text.substr(open_bracket + 1, text.find("]", open_bracket) - open_bracket - 1)
	return int(number) if number.is_valid_int() else -1

func _kept_axis(arg: String, axis_name: String) -> bool:
	if _keep_re == null:
		_keep_re = RegEx.create_from_string("(?i)^Entity([XYZ])\\(\\s*\\w+(\\\\\\w+(\\[\\d+\\])?)*\\\\buttons\\[\\d\\]\\s*,\\s*True\\s*\\)$")
	var found := _keep_re.search(arg)
	return found != null and found.get_string(1).to_lower() == axis_name

# RotateEntity(d\buttons[i], 0, yaw, 0) of an unparented button: the global (room-relative) yaw it faces.
func _parse_button_turn(statement: String, variable: String, door: Dictionary, unparented: Dictionary) -> void:
	var args := _entity_args(statement, "RotateEntity")
	if args.size() < 3:
		return
	var index := _button_index(args[0], variable)
	var yaw: Variant = _eval(args[2])
	if index < 0 or yaw == null or not (unparented.has(index) or (args.size() >= 5 and _truthy(args[4]))):
		return
	_merge_button_move(door, index, {"yaw": snappedf(float(yaw), 0.0001)})

static var _for_re: RegEx = null
static var _push_re: RegEx = null

func _track_for_loop(line: String, loop: Dictionary) -> Dictionary:
	if _for_re == null:
		_for_re = RegEx.create_from_string("^\\s*For\\s+(\\w+)%?\\s*=\\s*(\\d+)\\s+To\\s+(\\d+)\\s*$")
	var found := _for_re.search(line)
	if found:
		return {"var": found.get_string(1).to_lower(), "from": int(found.get_string(2)), "to": int(found.get_string(3))}
	if line.strip_edges().to_lower() == "next":
		return {}
	return loop

# MoveEntity r\RoomDoors[k]\buttons[b], x, y, z (k a number, or the variable of the enclosing For loop): the button is moved along
# its own axes, in the frame's units (the buttons are children of the frame, scaled RoomScale). "button_push" holds the raw x, y, z.
func _parse_button_push(line: String, loop: Dictionary, doors: Array) -> void:
	if _push_re == null:
		_push_re = RegEx.create_from_string("^\\s*MoveEntity\\s+r\\\\RoomDoors\\[(\\w+)\\]\\\\buttons\\[(\\d)\\]\\s*,(.*)$")
	var found := _push_re.search(line)
	if found == null:
		return
	var slots: Array[int] = []
	var slot_text := found.get_string(1)
	if slot_text.is_valid_int():
		slots.append(int(slot_text))
	elif not loop.is_empty() and slot_text.to_lower() == str(loop["var"]):
		for k in range(int(loop["from"]), int(loop["to"]) + 1):
			slots.append(k)
	var parts := _split_args(found.get_string(3))
	if slots.is_empty() or parts.size() < 3:
		return
	var x: Variant = _eval(parts[0])
	var y: Variant = _eval(parts[1])
	var z: Variant = _eval(parts[2])
	if x == null or y == null or z == null:
		return
	for slot in slots:
		for index in range(doors.size() - 1, -1, -1):
			var door: Dictionary = doors[index]
			if int(door.slot) != slot:
				continue
			if not door.has("button_push"):
				door["button_push"] = {}
			door.button_push[found.get_string(2)] = {"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001)}
			break

# CreateSecurityCam(x, y, z, r[, screen]) and the lines that follow it for that camera:
#   sc\angle, sc\turn, sc\FollowPlayer, sc\CoffinEffect, sc\AllowSaving, sc\RenderInterval,
#   TurnEntity(sc\CameraObj, pitch, 0, 0), PositionEntity(sc\ScrObj, x, y, z), TurnEntity(sc\ScrObj, 0, yaw, 0),
#   CameraZoom(sc\Cam, z), HideEntity sc\ScrOverlay / sc\MonitorObj
func _parse_cams(lines: PackedStringArray, from: int, to: int) -> Array:
	var cams: Array = []
	var current: Dictionary = {}
	for i in range(from, to):
		var line := _strip_comment(lines[i])
		var at := line.find("CreateSecurityCam(")
		if at >= 0:
			var args := _call_args(line, at + "CreateSecurityCam".length())
			if args.size() < 4:
				continue
			var x: Variant = _eval(args[0])
			var y: Variant = _eval(args[1])
			var z: Variant = _eval(args[2])
			if x == null or y == null or z == null:
				current = {}
				continue
			current = {
				"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001),
				"screen": args.size() > 4 and _truthy(args[4]), "angle": 0.0, "turn": 0.0, "pitch": 0.0,
				"follow": false, "coffin": 0, "allow_saving": args.size() > 4 and _truthy(args[4]),
				"render_interval": 12, "zoom": 0.8, "monitor": true, "overlay": true,
			}
			cams.append(current)
			continue
		if current.is_empty():
			continue
		for statement in line.split(":"):
			_parse_cam_statement(statement.strip_edges(), current)
	return cams

func _parse_cam_statement(s: String, cam: Dictionary) -> void:
	var bs := char(92)
	if s.begins_with("sc" + bs):
		var attr := s.substr(3)
		var eq := attr.find("=")
		if eq < 0:
			return
		var key := attr.substr(0, eq).strip_edges().to_lower()
		var value := attr.substr(eq + 1).strip_edges()
		match key:
			"angle":
				var v: Variant = _eval(value)
				if v != null:
					cam.angle = float(v)
			"turn":
				var v: Variant = _eval(value)
				if v != null:
					cam.turn = float(v)
			"followplayer":
				cam.follow = _truthy(value)
			"coffineffect":
				cam.coffin = 1 if _truthy(value) else 0
			"allowsaving":
				cam.allow_saving = _truthy(value)
			"renderinterval":
				var v: Variant = _eval(value)
				if v != null:
					cam.render_interval = int(v)
		return
	var lowered := s.to_lower()
	if lowered.begins_with("turnentity"):
		var args := _entity_args(s, "TurnEntity")
		if args.size() >= 4:
			var target := args[0].strip_edges().to_lower()
			if target == "sc" + bs + "cameraobj":
				var pitch: Variant = _eval(args[1])
				if pitch != null:
					cam.pitch = float(pitch)
			elif target == "sc" + bs + "scrobj":
				var yaw: Variant = _eval(args[2])
				if yaw != null:
					cam.screen_yaw = float(yaw)
	elif lowered.begins_with("positionentity"):
		var args := _entity_args(s, "PositionEntity")
		if args.size() >= 4 and args[0].strip_edges().to_lower() == "sc" + bs + "scrobj":
			var x: Variant = _eval(args[1])
			var y: Variant = _eval(args[2])
			var z: Variant = _eval(args[3])
			if x != null and y != null and z != null:
				cam.screen_at = {"x": snappedf(float(x), 0.0001), "y": snappedf(float(y), 0.0001), "z": snappedf(float(z), 0.0001)}
	elif lowered.begins_with("camerazoom"):
		var args := _entity_args(s, "CameraZoom")
		if args.size() >= 2:
			var zoom: Variant = _eval(args[1])
			if zoom != null:
				cam.zoom = float(zoom)
	elif lowered.begins_with("hideentity"):
		var rest := lowered.substr("hideentity".length()).strip_edges().trim_prefix("(").trim_suffix(")").strip_edges()
		if rest == "sc" + bs + "monitorobj":
			cam.monitor = false
		elif rest == "sc" + bs + "scroverlay":
			cam.overlay = false
	elif lowered.begins_with("scalesprite"):
		var args := _entity_args(s, "ScaleSprite")
		if args.size() >= 3 and args[0].strip_edges().to_lower() == "sc" + bs + "scrobj":
			var sx: Variant = _eval(args[1])
			var sy: Variant = _eval(args[2])
			if sx != null and sy != null:
				cam.sprite_scale = {"x": snappedf(float(sx), 0.0001), "y": snappedf(float(sy), 0.0001)}

# Arguments of "Name(a, b, c)" or "Name a, b, c".
func _entity_args(statement: String, name: String) -> Array[String]:
	var rest := statement.substr(name.length()).strip_edges()
	if rest.begins_with("("):
		return _call_args(statement, name.length())
	return _split_args(rest)

# `it\state = 80.0` (or the clipboard variable) in the statements that follow a CreateItem: the battery of a radio, a navigator or
# goggles, a flag of a document... until the next CreateItem or CreateDoor.
func _parse_item_state(lines: PackedStringArray, index: int, line: String, at: int, item: Dictionary) -> void:
	var left := line.substr(0, at).strip_edges()
	if not left.ends_with("="):
		return
	var variable := left.trim_suffix("=").strip_edges().replace(".Items", "")
	if variable.is_empty() or variable.contains("\\"):
		return
	var last := mini(index + 8, lines.size() - 1)
	for j in range(index + 1, last + 1):
		var follow := _strip_comment(lines[j])
		if follow.contains("CreateItem(") or follow.contains("CreateDoor("):
			break
		for statement in follow.split(":"):
			var s := statement.strip_edges()
			if s.begins_with("RotateEntity") and _entity_args(s, "RotateEntity").size() >= 3 and _entity_args(s, "RotateEntity")[0].strip_edges() == variable + "\\collider":
				# the yaw relative to the room: r\angle + n turned in the world, or n once parented to r\obj
				var yaw_text := _entity_args(s, "RotateEntity")[2].strip_edges()
				var yaw: Variant = _eval(yaw_text.replace("r\\angle", "0"))
				if yaw != null and (yaw_text.contains("r\\angle") or follow.contains("EntityParent(" + variable + "\\collider")):
					item["yaw"] = float(yaw)
			if s.begins_with(variable + "\\state") and not s.begins_with(variable + "\\state2"):
				var eq := s.find("=")
				if eq > 0:
					var value: Variant = _eval(s.substr(eq + 1).strip_edges())
					if value != null:
						item["state"] = float(value)
