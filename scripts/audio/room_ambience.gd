extends RefCounted
class_name RoomAmbience

const MAX_EMITTERS := 8
const NEAR_ROOM := 16.0

var facility: FacilityMap
var _clips: Array[String] = [""]

func _init(owner_facility: FacilityMap) -> void:
	facility = owner_facility
	var ini: IniFile = IniFile.parse(ContentPaths.existing_file("Data/rooms.ini"))
	var index := 1
	while true:
		var clip := ini.get_value("room ambience", "ambience%d" % index, "").replace("\\", "/")
		if clip.is_empty():
			break
		_clips.append(clip)
		index += 1

func voice_of(room: FacilityRoom, slot: int) -> AudioStreamPlayer3D:
	return room.emitter_voices[slot] if slot < room.emitter_voices.size() else null

# UpdateRooms (MapSystem.bb 5612): a room within 16 of the player in x and z loops each emitter the player's collider is inside the range of.
func update() -> void:
	var player: CharacterBody3D = GameState.player
	if player == null or player.camera == null:
		return
	var at := player.global_position
	for room: FacilityRoom in facility.rooms.built.values():
		if room.emitters.is_empty():
			continue
		if absf(room.global_position.x - at.x) >= NEAR_ROOM or absf(room.global_position.z - at.z) >= NEAR_ROOM:
			continue
		for slot in room.emitters.size():
			var emitter: Dictionary = room.emitters[slot]
			var source: Vector3 = room.to_global(emitter.position)
			if source.distance_to(at) < float(emitter.range):
				_loop(room, slot, source, player.camera.global_position)

# LoopSound2 (Main.bb 8941): the clip restarts only once it has ended, and the volume follows the camera's distance.
func _loop(room: FacilityRoom, slot: int, source: Vector3, camera_at: Vector3) -> void:
	var id := int(room.emitters[slot].id)
	if id <= 0 or id >= _clips.size():
		return
	if room.emitter_voices.size() < room.emitters.size():
		room.emitter_voices.resize(room.emitters.size())
	var voice := room.emitter_voices[slot]
	if voice == null or not is_instance_valid(voice):
		var stream := Sfx.stream(_clips[id])
		if stream == null:
			return
		voice = AudioStreamPlayer3D.new()
		voice.stream = stream
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		voice.max_distance = 0.0
		room.add_child(voice)
		room.emitter_voices[slot] = voice
	voice.global_position = source
	var range_m := maxf(float(room.emitters[slot].range), 1.0)
	var volume := 1.0 - camera_at.distance_to(source) / range_m
	voice.volume_db = linear_to_db(maxf(volume, 0.0001))
	if not voice.playing:
		voice.play()
