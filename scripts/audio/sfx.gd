extends RefCounted
class_name Sfx
# One-shot sound effects with a shared stream cache, so a sound is read from disk once.

static var _streams: Dictionary = {}

static func stream(relative: String) -> AudioStreamOggVorbis:
	if _streams.has(relative):
		return _streams[relative]
	var path := ContentPaths.existing_file(relative)
	var result: AudioStreamOggVorbis = null
	if FileAccess.file_exists(path):
		result = AudioStreamOggVorbis.load_from_file(path)
		result.resource_name = relative      # what the dev server's sound log reports
	else:
		ContentPaths.report_error('Sound "%s" not found.' % relative.replace("/", "\\"))
	_streams[relative] = result
	return result

# Plays the sound unpositioned (volume 0..1) and frees the player when it ends.
static func play_global(parent: Node, relative: String, volume: float = 1.0) -> AudioStreamPlayer:
	var source := stream(relative)
	if source == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = source
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player

static func play_at(parent: Node3D, relative: String, max_distance: float = 14.0, volume: float = 1.0) -> AudioStreamPlayer3D:
	var source := stream(relative)
	if source == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = source
	player.max_distance = max_distance
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player
