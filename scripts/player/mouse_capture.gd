class_name MouseCapture
extends RefCounted
# Every place that takes or gives back the mouse goes through here, so the web build knows whether the game wants it captured.
# A browser grants pointer lock only inside a click or key press: the request made while a run loads is refused and the engine
# falls back to a visible cursor, so the first click or key press afterwards asks again.

static var wanted := false

static func capture() -> void:
	wanted = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

static func release() -> void:
	wanted = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func set_captured(on: bool) -> void:
	if on:
		capture()
	else:
		release()

static func is_gesture(event: InputEvent) -> bool:
	return (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed() and not (event is InputEventKey and event.echo)

static func retry_on_gesture(event: InputEvent) -> void:
	if wanted and OS.has_feature("web") and is_gesture(event) and not _pointer_locked():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

static func _pointer_locked() -> bool:
	return int(JavaScriptBridge.eval("document.pointerLockElement ? 1 : 0", true)) == 1
