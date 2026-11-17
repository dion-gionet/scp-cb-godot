extends Node
class_name HitchLogger
# Logs every frame that takes longer than THRESHOLD_MS of wall time, with the room and the position, to the console and to
# user://hitches.log, so stutters on a real GPU (shader compilation, driver work) can be reported from play. Turned on from the
# debug menu's World tab, or at start with SCP_HITCH_LOG=1. Each time it is turned on the log starts afresh.

const THRESHOLD_MS := 33
const LOG_PATH := "user://hitches.log"

var enabled := false:
	set(value):
		enabled = value
		set_process(value)
		_last_usec = 0
		_file = null
		if value:
			_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
			_write("--- hitch log, %s, renderer %s, %s" % [Time.get_datetime_string_from_system(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
var _last_usec := 0
var _file: FileAccess

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	enabled = OS.get_environment("SCP_HITCH_LOG") == "1"

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		if ms > THRESHOLD_MS and not get_tree().paused:
			_write("%.1f s  %.1f ms  %s" % [now / 1000000.0, ms, _where()])
	_last_usec = now

func _where() -> String:
	var player: Node3D = GameState.player
	if player == null or not is_instance_valid(player):
		return "(no player)"
	var at := player.global_position
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var room := facility.room_name_at(at) if facility != null else ""
	return "%s  (%.1f, %.1f, %.1f)" % [room if not room.is_empty() else "?", at.x, at.y, -at.z]

func _write(line: String) -> void:
	print("HITCH ", line)
	if _file != null:
		_file.store_line(line)
		_file.flush()
