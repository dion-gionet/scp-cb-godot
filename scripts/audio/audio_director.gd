extends Node
# The facility's sound: zone music with cross-fades, random ambience, footsteps by floor
# material, breathing when tired, the heartbeat, and item pick-up/drop sounds.
# Sources: Main.bb UpdateMusic, the ambience block of the main loop, MovePlayer, LoadAllSounds.

# Music(0..2): the zone tracks selected by PlayerZone (0 LCZ, 1 HCZ, 2 EZ).
const ZONE_TRACKS := ["The Dread", "HeavyContainment", "EntranceZone"]
const INTRO_TRACK := "Intro"
# AmbientSFXAmount per folder: Zone1, Zone2, Zone3, General, Pre-breach (Forest is not used)
const AMBIENT_FOLDERS := ["Zone1", "Zone2", "Zone3", "General", "Pre-breach", "Forest"]
const AMBIENT_COUNTS := [11, 11, 12, 15, 5, 10]

var music_volume: float:
	get:
		return GameState.music_volume

var _music: AudioStreamPlayer
var _now_playing := ""
var _should_play := ""
var _music_fade := 1.0       # CurrMusicVolume
var _phase := 0.0            # previous footstep phase (Shake mod 360)
var _breath: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _heart_volume := 0.0
var _heart_rate := 70.0
var _heart_timer := 0.0
var _streams: Dictionary = {}
var steps_played := 0
var last_step_file := ""

func _ready() -> void:
	add_to_group("audio")
	GameState.load_settings()
	_music = AudioStreamPlayer.new()
	_music.set_meta("music", true)
	add_child(_music)
	_breath = AudioStreamPlayer.new()
	add_child(_breath)
	_heart = AudioStreamPlayer.new()
	add_child(_heart)

func _physics_process(delta: float) -> void:
	var player: CharacterBody3D = GameState.player
	_update_deaf(delta * 70.0)       # also in the menu: a run left while deaf must not leave the mix muted
	if player == null:
		return
	var fps := delta * 70.0
	_update_music(player, fps)
	_update_ambient(player, fps)
	_update_broadcast(player, fps)
	_update_steps(player)
	_update_breath(player)
	_update_heartbeat(fps)

func _update_music(player: Node3D, fps: float) -> void:
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or not facility.active:
		_should_play = INTRO_TRACK
	else:
		_should_play = ZONE_TRACKS[clampi(facility.zone_at(player.global_position), 0, 2)]
		if not GameState.music_override.is_empty():
			_should_play = GameState.music_override
		if not GameState.npc_music().is_empty() and not GameState.music_override.begins_with("Custom/"):
			_should_play = GameState.npc_music()
	if _now_playing != _should_play:
		# playing the wrong clip: fade out (FPSfactor / 250 per frame), then switch
		_music_fade = maxf(_music_fade - fps / 250.0, 0.0)
		if _music_fade == 0.0:
			_music.stop()
			_now_playing = _should_play
			var path := ContentPaths.existing_file("SFX/Music/%s.ogg" % _now_playing)
			if FileAccess.file_exists(path):
				var stream: AudioStreamOggVorbis = _stream(path)
				if stream != null:
					stream.loop = true
					_music.stream = stream
					_music.play()
	else:
		_music_fade += (1.0 - _music_fade) * minf(0.1 * fps, 1.0)
	_music.volume_db = linear_to_db(maxf(_music_fade * music_volume, 0.0001))

# PlaySound_Strict(AmbientSFX(zone, Rand(0, AmbientSFXAmount(zone) - 1))): one of the facility's sounds, unpositioned
func play_ambient_global(zone: int) -> void:
	var index := randi_range(1, AMBIENT_COUNTS[zone])
	_play_global("SFX/Ambient/%s/ambient%d.ogg" % [AMBIENT_FOLDERS[zone], index], 1.0)

var _was_deaf := false

# UpdateDeafPlayer: while DeafTimer runs the effects are silent
func _update_deaf(fps: float) -> void:
	if GameState.deaf_timer > 0.0:
		GameState.deaf_timer = maxf(GameState.deaf_timer - fps, 0.0)
	var deaf := GameState.deaf_timer > 0.0
	if deaf != _was_deaf:
		_was_deaf = deaf
		GameState.apply_sfx_volume()

func _update_ambient(player: Node3D, fps: float) -> void:
	# Rand(1500) = 1 each frame at 70 fps
	if randf() >= fps / 1500.0:
		return
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	var zone := 4   # pre-breach in the 173 chamber
	if facility != null and facility.active:
		zone = facility.zone_at(player.global_position)
	var in_forest: bool = facility != null and facility.active and facility.events.room860.state == 1.0
	if in_forest:
		zone = 5     # PlayerZone 5: SCP-860-1's forest
	elif randi() % 3 == 0 and zone != 4:
		zone = 3    # "general"
	var index := randi_range(1, AMBIENT_COUNTS[zone])
	var path := ContentPaths.existing_file("SFX/Ambient/%s/ambient%d.ogg" % [AMBIENT_FOLDERS[zone], index])
	if not FileAccess.file_exists(path):
		return
	var emitter := AudioStreamPlayer3D.new()
	emitter.stream = _stream(path)
	emitter.max_distance = 10.0
	add_child(emitter)
	emitter.global_position = Vector3(player.global_position.x + randf_range(-1.0, 1.0), 30.0 if in_forest else 0.0, player.global_position.z + randf_range(-1.0, 1.0))
	emitter.play()
	emitter.finished.connect(emitter.queue_free)

const NO_BROADCAST_ROOMS := ["pocketdimension", "gatea", "exit1", "room860", "room1123", "173", "dimension1499"]
var force_broadcast := false     # tests: the Rand(50000) = 3 roll succeeds on the next check

# Main.bb main loop: Rand(50000) = 3 each frame outside the pocket dimension, gate A and gate B's room, SCP-079 breaks into
# the speakers: LightBlink = Rnd(1, 2) and Broadcast1-7 (none in 860, 1123, the 173 chamber or 1499)
func _update_broadcast(player: Node3D, fps: float) -> void:
	if not force_broadcast and randf() >= fps / 50000.0:
		return
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility == null or not facility.active:
		return
	force_broadcast = false
	if facility.room_name_at(player.global_position) in NO_BROADCAST_ROOMS:
		return
	GameState.light_blink = randf_range(1.0, 2.0)
	Sfx.play_global(self, "SFX/SCP/079/Broadcast%d.ogg" % randi_range(1, 7))

# MovePlayer: a step each time Shake mod 360 crosses 180 while moving.
func _update_steps(player: CharacterBody3D) -> void:
	if GameState.noclip or player.dead:
		return
	var phase := fmod(player.shake, 360.0)
	if _phase < 180.0 and phase >= 180.0 and player.curr_speed > 0.0:
		_step(player)
	_phase = phase

func _step(player: CharacterBody3D) -> void:
	var metal := 0
	var facility := get_tree().get_first_node_in_group("facility") as FacilityMap
	if facility != null:
		var room: Node3D = facility.room_at(player.global_position)
		if room != null and room.has_method("step_type_at"):
			metal = room.step_type_at(player.global_position)
	var running: bool = player.is_sprinting()
	if GameState.step_set == 2:
		_play_global("SFX/Step/StepForest%d.ogg" % randi_range(1, 3), 1.0 - (1.0 if player.crouching else 0.0) * 0.4)      # CurrStepSFX 2: the forest
		steps_played += 1
		return
	if GameState.pd_step_active():
		last_step_file = "SFX/Step/StepPD%d.ogg" % randi_range(1, 3)
		_play_global(last_step_file, 1.0 - (1.0 if player.crouching else 0.0) * 0.4)
		steps_played += 1
		return
	var file := "SFX/Step/%s%s%d.ogg" % ["Run" if running else "Step", "Metal" if metal == 1 else "", randi_range(1, 8)]
	steps_played += 1
	last_step_file = file
	_play_global(file, 1.0 - (1.0 if player.crouching else 0.0) * 0.6)

func _update_breath(player: CharacterBody3D) -> void:
	if not Input.is_action_pressed("sprint") or _breath.playing:
		return
	var gas := 1 if GameState.wearing_gas_mask != 0 or GameState.wearing_1499 != 0 else 0
	var stamina: float = player.stamina
	var variant := -1
	var volume := 1.0
	if stamina < 5.0:
		variant = 0
	elif stamina < 50.0:
		variant = randi_range(1, 3)
		volume = clampf((70.0 - stamina) / 70.0, 0.0, 1.0)
	if variant < 0:
		return
	var path := ContentPaths.existing_file("SFX/Character/D9341/breath%d%s.ogg" % [variant, "gas" if gas == 1 else ""])
	if FileAccess.file_exists(path):
		_breath.stream = _stream(path)
		_breath.volume_db = linear_to_db(maxf(volume, 0.0001))
		_breath.play()

# HeartBeatRate = Max(rate, current), HeartBeatVolume = Max(volume, current).
func stop_breath() -> void:
	_breath.stop()

func heartbeat(volume: float, rate: float) -> void:
	_heart_volume = maxf(_heart_volume, volume)
	_heart_rate = maxf(_heart_rate, rate)

# HeartBeatRate = Max(rate, current), HeartBeatVolume = volume.
func heartbeat_set_volume(volume: float, rate: float) -> void:
	_heart_volume = volume
	_heart_rate = maxf(_heart_rate, rate)

# HeartBeatVolume = CurveValue(volume, HeartBeatVolume, vol_smooth), HeartBeatRate likewise.
func heartbeat_curve(volume: float, rate: float, vol_smooth: float, rate_smooth: float, fps: float) -> void:
	_heart_volume += (volume - _heart_volume) / maxf(vol_smooth / fps, 1.0)
	_heart_rate += (rate - _heart_rate) / maxf(rate_smooth / fps, 1.0)

func _update_heartbeat(fps: float) -> void:
	if _heart_volume <= 0.0:
		_heart_rate = 70.0
		return
	if _heart_timer <= 0.0:
		var path := ContentPaths.existing_file("SFX/Character/D9341/Heartbeat.ogg")
		if FileAccess.file_exists(path):
			_heart.stream = _stream(path)
			_heart.volume_db = linear_to_db(maxf(_heart_volume, 0.0001))
			_heart.play()
		_heart_timer = 70.0 * (60.0 / maxf(_heart_rate, 1.0))
	else:
		_heart_timer -= fps
	_heart_volume = maxf(_heart_volume - fps * 0.05, 0.0)

# PickSFX(template sound): 0..3, 66 is silent. Used for taking and dropping.
func play_item_sound(item_name: String) -> void:
	var template: Dictionary = RoomFill.item_template(item_name)
	var number := int(template.get("sound", 0))
	if number == 66:
		return
	_play_global("SFX/Interact/PickItem%d.ogg" % clampi(number, 0, 3), 1.0)


func _stream(path: String) -> AudioStreamOggVorbis:
	if not _streams.has(path):
		_streams[path] = AudioStreamOggVorbis.load_from_file(path)
	return _streams[path]

func _play_global(relative: String, volume: float) -> void:
	var path := ContentPaths.existing_file(relative)
	if not FileAccess.file_exists(path):
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _stream(path)
	sfx.volume_db = linear_to_db(maxf(volume, 0.0001))
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
