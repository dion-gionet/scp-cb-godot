extends CanvasLayer
class_name StartupVideos
# Main.bb PlayStartupVideos: GFX\menu\startup_Undertow, then startup_TSS, each a silent video with its own .ogg
# soundtrack at SFXVolume. A clip ends when its soundtrack does or on any key; a blank frame separates the two.
# The picture is as wide as the screen at 16:9 and centred, so a wider screen crops it and a taller one gets bars.
# The pack carries the videos as Ogg Theora (the original's .avi is MPEG-4, which Godot cannot play).

signal finished

const CLIPS: Array[String] = ["startup_Undertow", "startup_TSS"]
const FOLDER := "GFX/menu/"
const ASPECT := 16.0 / 9.0

var clip_index := -1
var skipped_clips := 0
var running := false

var _video: VideoStreamPlayer
var _audio: AudioStreamPlayer

static func clip_paths(clip: String) -> Dictionary:
	return {"video": ContentPaths.existing_file(FOLDER + clip + ".ogv"), "audio": ContentPaths.existing_file(FOLDER + clip + ".ogg")}

static func available() -> bool:
	for clip in CLIPS:
		var paths := clip_paths(clip)
		if not FileAccess.file_exists(paths.video) or not FileAccess.file_exists(paths.audio):
			return false
	return true

func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.add_child(_video)
	_audio = AudioStreamPlayer.new()
	_audio.finished.connect(_next_clip)
	add_child(_audio)
	get_viewport().size_changed.connect(_fit_video)
	_fit_video()

func play() -> void:
	running = true
	_next_clip()

func _next_clip() -> void:
	_video.stop()
	_audio.stop()
	clip_index += 1
	while clip_index < CLIPS.size() and not _start(CLIPS[clip_index]):
		skipped_clips += 1
		clip_index += 1
	if clip_index >= CLIPS.size():
		running = false
		finished.emit()
		return
	if clip_index > 0:
		_video.visible = false
		await get_tree().process_frame
		_video.visible = true

func _start(clip: String) -> bool:
	var paths := clip_paths(clip)
	if not FileAccess.file_exists(paths.video) or not FileAccess.file_exists(paths.audio):
		return false
	var stream := VideoStreamTheora.new()
	stream.file = paths.video
	var sound := AudioStreamOggVorbis.load_from_file(paths.audio)
	if sound == null:
		return false
	_video.stream = stream
	_audio.stream = sound
	_video.play()
	_audio.play()
	return true

func _fit_video() -> void:
	if _video == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var height := screen.x / ASPECT
	_video.size = Vector2(screen.x, height)
	_video.position = Vector2(0.0, (screen.y - height) / 2.0)

func _input(event: InputEvent) -> void:
	if running and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_next_clip()
