extends RefCounted
class_name KeyNames
# KeyName.bb: the names the controls menu shows for the DirectInput scancodes options.ini [binds] stores,
# and the Godot key at each of those scancodes. Scancodes without a name show blank, as in the original.

const NAMES := {
	1: "Esc", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0", 12: "-", 13: "=",
	14: "Backspace", 15: "TAB", 16: "Q", 17: "W", 18: "E", 19: "R", 20: "T", 21: "Y", 22: "U", 23: "I", 24: "O",
	25: "P", 26: "[", 27: "]", 28: "Enter", 29: "Left Ctrl", 30: "A", 31: "S", 32: "D", 33: "F", 34: "G", 35: "H",
	36: "J", 37: "K", 38: "L", 39: ";", 40: "'", 42: "Left Shift", 43: "\\", 44: "Z", 45: "X", 46: "C", 47: "V",
	48: "B", 49: "N", 50: "M", 51: ",", 52: ".", 54: "Right Shift", 56: "Left Alt", 57: "Space", 58: "Caps Lock",
	59: "F1", 60: "F2", 61: "F3", 62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9", 68: "F10",
	157: "Right Control", 184: "Right Alt", 200: "Up", 203: "Left", 205: "Right", 208: "Down",
}

const KEYS := {
	1: KEY_ESCAPE, 2: KEY_1, 3: KEY_2, 4: KEY_3, 5: KEY_4, 6: KEY_5, 7: KEY_6, 8: KEY_7, 9: KEY_8, 10: KEY_9, 11: KEY_0,
	12: KEY_MINUS, 13: KEY_EQUAL, 14: KEY_BACKSPACE, 15: KEY_TAB, 16: KEY_Q, 17: KEY_W, 18: KEY_E, 19: KEY_R, 20: KEY_T,
	21: KEY_Y, 22: KEY_U, 23: KEY_I, 24: KEY_O, 25: KEY_P, 26: KEY_BRACKETLEFT, 27: KEY_BRACKETRIGHT, 28: KEY_ENTER,
	29: KEY_CTRL, 30: KEY_A, 31: KEY_S, 32: KEY_D, 33: KEY_F, 34: KEY_G, 35: KEY_H, 36: KEY_J, 37: KEY_K, 38: KEY_L,
	39: KEY_SEMICOLON, 40: KEY_APOSTROPHE, 41: KEY_QUOTELEFT, 42: KEY_SHIFT, 43: KEY_BACKSLASH, 44: KEY_Z, 45: KEY_X,
	46: KEY_C, 47: KEY_V, 48: KEY_B, 49: KEY_N, 50: KEY_M, 51: KEY_COMMA, 52: KEY_PERIOD, 53: KEY_SLASH,
	55: KEY_KP_MULTIPLY, 56: KEY_ALT, 57: KEY_SPACE, 58: KEY_CAPSLOCK, 59: KEY_F1, 60: KEY_F2, 61: KEY_F3, 62: KEY_F4,
	63: KEY_F5, 64: KEY_F6, 65: KEY_F7, 66: KEY_F8, 67: KEY_F9, 68: KEY_F10, 87: KEY_F11, 88: KEY_F12,
	199: KEY_HOME, 200: KEY_UP, 201: KEY_PAGEUP, 203: KEY_LEFT, 205: KEY_RIGHT, 207: KEY_END, 208: KEY_DOWN,
	209: KEY_PAGEDOWN, 210: KEY_INSERT, 211: KEY_DELETE, 54: KEY_SHIFT, 157: KEY_CTRL, 184: KEY_ALT,
}

# KeyName(Min(key, 210))
static func name_of(scancode: int) -> String:
	return NAMES.get(mini(scancode, 210), "")

static func godot_key(scancode: int) -> Key:
	return KEYS.get(scancode, KEY_NONE)

# The scancode of a key event, 0 for keys the table does not know. Godot reports both Shift, Ctrl and Alt keys as one
# keycode and tells them apart by location.
static func scancode_of(event: InputEventKey) -> int:
	var key := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if event.location == KEY_LOCATION_RIGHT:
		match key:
			KEY_SHIFT:
				return 54
			KEY_CTRL:
				return 157
			KEY_ALT:
				return 184
	for scancode in KEYS:
		if KEYS[scancode] == key:
			return scancode
	return 0
