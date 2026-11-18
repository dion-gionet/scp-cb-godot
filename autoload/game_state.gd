extends Node

signal player_died(message: String)

var playing: bool = false
var eyes_open: bool = true
var light_energy: float = 1.0
var fog_of_war := true          # debug menu: the original's darkness fog (light_fog.gd)
var player: Node3D
var scp173: Node3D
var grabbed_lever: Node = null       # GrabbedEntity: the lever the player holds
var death_msg: String = ""          # DeathMSG: what the death screen says when nothing else does
var god_mode: bool = false
var secondary_light: float = 1.0    # SecondaryLightOn: 1 powered, 0 out (room2ccont's lever fades it)
var lights_on: bool:                # the room lights are powered (SecondaryLightOn > 0.5)
	get:
		return secondary_light > 0.5
	set(value):
		secondary_light = 1.0 if value else 0.0
# Menu choices and options that outlive a run (reset_run leaves them alone).
var requested_seed: int = -1
var pending_load: Dictionary = {}     # a loaded save waiting for the facility to be built
var difficulty: int = 1
var music_volume: float = -1.0       # 0..1, loaded from options.ini on first use
var sound_volume: float = -1.0:
	set(value):
		sound_volume = value
		apply_sfx_volume()
var mouse_sensitivity: float = 0.5   # slider position; 0.5 is the original default (0)
var mouse_smoothing: float = 1.0     # options.ini "mouse smoothing" 0..2 (the slider shows it as a percentage of 200); 1.0 is the default
var invert_mouse: bool = false       # options.ini "invert mouse y"
var console_enabled: bool = false     # options.ini "console enabled" (off in the shipped options.ini)
var used_console := false             # Main.bb UsedConsole: set when the console is closed; the "console" achievement needs it false at the ending
# The rest of SaveOptionsINI (Main.bb), with options.ini's defaults.
var vsync := true
var anti_alias := true
var room_lights := true
var screen_gamma := 1.0
var particle_amount := 2              # 0 minimal, 1 reduced, 2 full
var texture_details := 3              # Texture LOD Bias 0.8, 0.4, 0.0, -0.4, -0.8
var enable_user_tracks := true
var user_track_mode := 1              # 1 repeat, 0 random
var hud_enabled := true
var console_on_error := false
var achievement_popups := true
var framelimit := 0
var aa_text := false
# The launcher's choices (Main.bb / Menu.bb UpdateLauncher), with the shipped options.ini's defaults.
var graphic_width := 1280
var graphic_height := 720
var fullscreen := false
var borderless_windowed := false
var launcher_enabled := true
var play_startup_video := true        # options.ini [options] play startup video; the bot and a missing pack skip it
var gfx_driver := 1                   # 1-based like SelectedGFXDriver; here the screen the window opens on
var launcher_width := 640
var launcher_height := 480
# [binds]: DirectInput scancodes, as the original stores them
var binds := {"right": 32, "left": 30, "up": 17, "down": 31, "blink": 57, "sprint": 42, "inventory": 15, "crouch": 29, "save": 63, "console": 61}
# Difficulty CUSTOM's choices (Difficulty.bb defaults)
var custom_perma_death := false
var custom_save_anywhere := true
var custom_aggressive_npcs := true
var custom_other_factors := 0
var save_name := ""                   # CurrSave
var halloween := false              # the console's halloween: 173 is a jack-o'-lantern
var noclip: bool = false

# The run's tallies shown on the ending screen (Achievements.bb Achievements(), Rooms\found, ItemTemplates\found).
const ACHIEVEMENT_ORDER := ["008", "012", "035", "049", "055", "079", "096", "106", "148", "205", "294", "372", "420", "427", "500", "513", "714", "789", "860", "895", "914", "939", "966", "970", "1025", "1048", "1123", "maynard", "harp", "snav", "omni", "console", "tesla", "pd", "1162", "1499", "keter"]
const MAX_ACHIEVEMENTS := 37
var achievements: Dictionary = {}     # per run: NullGame clears them, the save keeps them
var rooms_found: Dictionary = {}
var docs_found: Dictionary = {}
var refined_items := 0
var selected_ending := ""            # SelectedEnding: "" while the game runs
var no_target := false               # the console's notarget: NPCs ignore the player (debug)
var noclip_speed := 2.0               # NoClipSpeed
var infinite_stamina := false       # InfiniteStamina
var show_fps := false               # ShowFPS
var debug_hud := false              # DebugHUD
var wireframe := false              # WireframeState
var fog_override := Vector4(-1.0, 0.0, 0.0, 0.0)   # (begin, end, ...) the gates' own fog; x < 0: the light-volume fog
var fog_color := Color(0.78, 0.78, 0.78)
var pd_step_tick := -10               # CurrStepSFX = 1 is reset every frame in UpdateEvents; events stamp the physics frame they set it
func mark_pd_step() -> void:
	pd_step_tick = Engine.get_physics_frames()
func pd_step_active() -> bool:
	return Engine.get_physics_frames() - pd_step_tick <= 1
var step_set := 0                    # CurrStepSFX: 2 = the forest's steps
var ambient_override := -1.0         # the gates' ambient light (140 / 255); < 0: the options' brightness
var deaf_timer := 0.0                # DeafTimer (frames): every sound effect is silent while it runs (SCP-066)
var light_dim := 0.0                 # SCP-066's darkness: how much of the light volume is taken off this frame
var save_blocked := false            # CanSave = False: an event (SCP-1123's vision) refuses saving
var light_flash := 0.0               # LightFlash: a white flash that fades 1 per 70 frames (explosions, turrets)
var explosion_timer := 0.0           # ExplosionTimer: the nuke and the 294 drinks
var super_man := false             # SuperMan: SCP-914 turned the player into something faster (and short-lived)
var super_man_timer := 0.0
var vomit_timer := 0.0            # VomitTimer: seconds of feeling sick (> 0), then the vomiting (< 0, down to -15)
var vomit := false                # the vomiting has begun
var vomit_prev_injuries := 0.0
var vomit_prev_bloodloss := 0.0
var camera_shake_timer := 0.0     # CameraShakeTimer: seconds the view shakes (a drink)
var death_timer := 0.0            # DeathTimer: frames until a drink kills (> 0 counting, -1 dead)
var stamina_effect := 1.0         # StaminaEffect: how fast the stamina drains (1 = normal)
var stamina_effect_timer := 0.0   # seconds before it wears off
var using_294 := false            # the drinks machine's panel is open
var heal_timer := 0.0              # HealTimer: seconds a syringe keeps healing (and bleeding a little)
var wearing_1499 := 0               # Wearing1499: 0 no, 1 SCP-1499, 2 the finer mask (the player is in its dimension while it is on)
var i427_using := false            # SCP-427 is open
var scp1025: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # SCP1025state: common cold, chicken pox, lung cancer, appendicitis, asthma, cardiac arrest
var i427_timer := 0.0              # I_427Timer: frames it has been open (360 s makes the change, 420 s ends it)

func no_target_mode() -> bool:
	return no_target

# the paper items of the item table (docamount)
func docs_templates() -> Array:
	var out: Array = []
	var RoomFill = load("res://scripts/world/room_fill.gd")
	RoomFill._ensure()
	for item_name in RoomFill._data.get("item_templates", {}):
		if str(RoomFill._data.item_templates[item_name].get("tempname", "")) == "paper":
			out.append(item_name)
	return out

signal achievement_unlocked(index: int)

func give_achievement(name: String) -> void:
	if achievements.has(name):
		return
	achievements[name] = true
	var index := ACHIEVEMENT_ORDER.find(name)
	if achievement_popups and index >= 0:
		achievement_unlocked.emit(index)

func achievements_unlocked() -> int:
	var count := 0
	for key in ACHIEVEMENT_ORDER:
		if achievements.has(key):
			count += 1
	return count

# scpsEncountered = 1 + the first 25 achievements (the SCP ones)
func scps_encountered() -> int:
	var count := 1
	for i in 25:
		if achievements.has(ACHIEVEMENT_ORDER[i]):
			count += 1
	return count

# Worn items (Main.bb Wearing*): 0 = not worn, otherwise the variant level.
var wearing_gas_mask: int = 0
var wearing_vest: int = 0
var wearing_hazmat: int = 0
var wearing_night_vision: int = 0
var nvg_blinking := false       # IsNVGBlinking: the goggles' screen is black (refreshing, or the batteries died)
var room_ambient := 0.0         # what the rooms' lightmaps are lifted by (night vision)
var nvg_battery := 2            # hasBattery: 0 dead, 1 low (100 or less left), 2 fine
var wearing_714: bool = false
# Health model: injuries 0..4, bloodloss 0..100 (no damage sources are ported yet).
var injuries: float = 0.0
var bloodloss: float = 0.0
var infect: float = 0.0               # Infect: SCP-008 infection, 0 to 100 (UpdateInfect)
var infect_overlay: float = 0.0       # alpha of the green InfectOverlay (set by the infection)
var is_zombie: bool = false           # IsZombie: no crouching, sprinting or inventory
var unable_to_move: bool = false      # UnableToMove: the body will not walk (the view still turns)
var force_move: float = 0.0           # ForceMove: walk forward by itself at this fraction of the walking pace
# BlurTimer (frames) feeds BlurVolume, which the HUD blurs the view by; Sanity runs 0 down to -1000.
var blur_timer: float = 0.0
var blur_volume: float = 0.0
var sanity: float = 0.0
var restore_sanity := true      # RestoreSanity: SCP-895 (in a monitor or through goggles) keeps the sanity from coming back
var coffin_distance := 100.0    # CoffinDistance: how far the player is from SCP-895 (the radio and the navigator feel it)
var light_blink: float = 0.0     # LightBlink: the lights flicker, darkening the view (decays by 1 per 35 frames)
# Set by events that take over the music (ShouldPlay): a track name under SFX/Music, or "".
var music_override: String = ""
var _npc_music := ""
var _npc_music_frame := -100

# An NPC's per-frame ShouldPlay: it lapses when the NPC stops asking (physics ticks).
func request_npc_music(track: String) -> void:
	_npc_music = track
	_npc_music_frame = Engine.get_physics_frames()

func npc_music() -> String:
	return _npc_music if Engine.get_physics_frames() - _npc_music_frame <= 3 else ""
var intro_enabled: bool = true      # options.ini "intro enabled": the cell and the escort before the breach
var selected_monitor: Object = null  # SelectedMonitor: the security monitor the player clicked (Euclid saving)
var arrow_icons: Array[bool] = [false, false, false, false]   # DrawArrowIcon: up, right, down, left of the hand
var hand_icon := false                # DrawHandIcon, asked for by something that is not a door button or an item
# Eye drops: BlinkEffect scales the blink timer's countdown while BlinkEffectTimer (s) runs.
var blink_effect: float = 1.0
var blink_effect_timer: float = 0.0
var eye_stuck: float = 0.0   # frames the eyes are held open (super eye drops)
var eye_irritation: float = 0.0   # EyeIrritation: gas in the eyes makes them blink faster (frames, counts down)
# Main.bb: four digits, each 1..9, used by the keypad doors and the code documents.
var access_code: String = ""
# Rooms stream in and out; what happened in them has to outlive their nodes.
var taken_items: Dictionary = {}   # "roomkey|iN" -> true once picked up
var door_states: Dictionary = {}   # "roomkey|dN" -> {open, locked}
var elevator_states: Dictionary = {}   # "roomkey|eN" -> the car's trip counter

func _ready() -> void:
	# AmbientLightRooms: the grey added to every room's lightmap (15 / 255 with night vision on); read by shaders/lightmap.gdshader
	RenderingServer.global_shader_parameter_add(&"room_ambient", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add(&"room_fog_range", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(100000.0, 200000.0))
	RenderingServer.global_shader_parameter_add(&"room_fog_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	RenderingServer.global_shader_parameter_add(&"output_compat", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0 if compat else 0.0)
	# the models' AmbientLight and the room lights shown for them (shaders/entity.gdshaderinc)
	RenderingServer.global_shader_parameter_add(&"entity_ambient", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE * 50.0 / 255.0)
	for light_global in [&"entity_light_pos_a", &"entity_light_pos_b", &"entity_light_col_a", &"entity_light_col_b"]:
		RenderingServer.global_shader_parameter_add(light_global, RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO))
	_make_sfx_bus()

# Every player but the music goes through the "Sfx" bus. Its gain is SFXVolume, which the original gives every channel it
# starts (PlaySound_Strict, PlaySound2, LoopSound2); DeafTimer zeroes SFXVolume and leaves the music alone.
const SFX_BUS := &"Sfx"

func _make_sfx_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, SFX_BUS)
		AudioServer.set_bus_send(index, &"Master")
	get_tree().node_added.connect(_route_player)
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_route_player(node)
		stack.append_array(node.get_children())
	apply_sfx_volume()

func _route_player(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and not node.has_meta("music"):
		node.bus = SFX_BUS

func apply_sfx_volume() -> void:
	var index := AudioServer.get_bus_index(SFX_BUS)
	if index < 0:
		return
	var volume := sound_volume if sound_volume >= 0.0 else 1.0
	AudioServer.set_bus_volume_db(index, -80.0 if deaf_timer > 0.0 else linear_to_db(maxf(volume, 0.0001)))

# MilliSecs() as the game sees it: simulated time, so a test run faster than real time behaves the same.
func clock_ms() -> float:
	return float(Engine.get_physics_frames()) * 1000.0 / float(Engine.physics_ticks_per_second)

func reset_run() -> void:
	playing = false
	selected_ending = ""
	used_console = false
	fog_override = Vector4(-1.0, 0.0, 0.0, 0.0)
	ambient_override = -1.0
	light_flash = 0.0
	explosion_timer = 0.0
	super_man = false
	super_man_timer = 0.0
	vomit_timer = 0.0
	vomit = false
	camera_shake_timer = 0.0
	death_timer = 0.0
	stamina_effect = 1.0
	stamina_effect_timer = 0.0
	using_294 = false
	heal_timer = 0.0
	wearing_1499 = 0
	i427_using = false
	i427_timer = 0.0
	rooms_found = {}
	docs_found = {}
	achievements = {}
	refined_items = 0
	eyes_open = true
	light_energy = 1.0
	player = null
	scp173 = null
	death_msg = ""
	grabbed_lever = null
	god_mode = false
	noclip = false
	debug_hud = false
	if wireframe:
		wireframe = false
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	scp1025 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	wearing_gas_mask = 0
	wearing_vest = 0
	wearing_hazmat = 0
	wearing_night_vision = 0
	nvg_blinking = false
	nvg_battery = 2
	wearing_714 = false
	injuries = 0.0
	infect = 0.0
	infect_overlay = 0.0
	is_zombie = false
	unable_to_move = false
	force_move = 0.0
	bloodloss = 0.0
	blur_timer = 0.0
	blur_volume = 0.0
	save_blocked = false
	deaf_timer = 0.0
	apply_sfx_volume()
	light_dim = 0.0
	sanity = 0.0
	restore_sanity = true
	step_set = 0
	coffin_distance = 100.0
	light_blink = 0.0
	music_override = ""
	secondary_light = 1.0
	selected_monitor = null
	blink_effect = 1.0
	blink_effect_timer = 0.0
	eye_stuck = 0.0
	eye_irritation = 0.0
	access_code = ""
	taken_items = {}
	door_states = {}
	elevator_states = {}
	for _i in 4:
		access_code += str(randi_range(1, 9))

# GetINIInt: "true" and "false" are 1 and 0, anything else is Int() of the text.
static func ini_int(ini: IniFile, section: String, key: String, fallback: int) -> int:
	var raw := ini.get_value(section, key, "").strip_edges().to_lower()
	match raw:
		"":
			return fallback
		"true":
			return 1
		"false":
			return 0
	return int(raw)

func _load_launcher_settings(ini: IniFile) -> void:
	launcher_width = mini(ini_int(ini, "launcher", "launcher width", launcher_width), 1024)
	launcher_height = mini(ini_int(ini, "launcher", "launcher height", launcher_height), 768)
	launcher_enabled = ini_int(ini, "launcher", "launcher enabled", int(launcher_enabled)) != 0
	graphic_width = ini_int(ini, "options", "width", graphic_width)
	graphic_height = ini_int(ini, "options", "height", graphic_height)
	fullscreen = ini_int(ini, "options", "fullscreen", int(fullscreen)) != 0
	borderless_windowed = ini_int(ini, "options", "borderless windowed", int(borderless_windowed)) != 0
	gfx_driver = maxi(ini_int(ini, "options", "gfx driver", gfx_driver), 1)

# options.ini [audio] volumes, once per session.
func load_settings() -> void:
	if music_volume >= 0.0 and sound_volume >= 0.0:
		return
	var ini := IniFile.parse(ContentPaths.existing_file("options.ini"))
	intro_enabled = str(ini.get_value("options", "intro enabled", "1")) != "0"
	play_startup_video = ini_int(ini, "options", "play startup video", 1) != 0
	if OS.get_environment("SCP_BOT") == "1" and OS.get_environment("SCP_INTRO") != "1":
		intro_enabled = false   # the bot starts in the breach unless a test asks for the intro
	if music_volume < 0.0:
		music_volume = clampf(float(ini.get_value("audio", "music volume", "0.5")), 0.0, 1.0)
	if sound_volume < 0.0:
		sound_volume = clampf(float(ini.get_value("audio", "sound volume", "1.0")), 0.0, 1.0)
	mouse_smoothing = clampf(float(ini.get_value("options", "mouse smoothing", "1.0")), 0.0, 2.0)
	invert_mouse = str(ini.get_value("options", "invert mouse y", "0")) != "0"
	var flag := func(section: String, key: String, fallback: bool) -> bool:
		return int(ini.get_value(section, key, "1" if fallback else "0")) != 0
	vsync = flag.call("options", "vsync", vsync)
	anti_alias = flag.call("options", "antialias", anti_alias)
	room_lights = flag.call("options", "room lights enabled", room_lights)
	screen_gamma = float(ini.get_value("options", "screengamma", str(screen_gamma)))
	particle_amount = int(ini.get_value("options", "particle amount", str(particle_amount)))
	texture_details = int(ini.get_value("options", "texture details", str(texture_details)))
	enable_user_tracks = flag.call("audio", "enable user tracks", enable_user_tracks)
	user_track_mode = int(ini.get_value("audio", "user track setting", str(user_track_mode)))
	hud_enabled = flag.call("options", "HUD enabled", hud_enabled)
	console_on_error = flag.call("console", "auto opening", console_on_error)
	achievement_popups = flag.call("options", "achievement popup enabled", achievement_popups)
	show_fps = flag.call("options", "show FPS", show_fps)
	framelimit = int(ini.get_value("options", "framelimit", str(framelimit)))
	aa_text = flag.call("options", "antialiased text", aa_text)
	_load_launcher_settings(ini)
	for key in BIND_KEYS:
		binds[key] = int(ini.get_value("binds", BIND_KEYS[key], str(binds[key])))
	# what the player changed in the menus last time wins over the shipped options.ini
	var saved := ConfigFile.new()
	if saved.load("user://options.cfg") == OK:
		music_volume = clampf(float(saved.get_value("options", "music_volume", music_volume)), 0.0, 1.0)
		sound_volume = clampf(float(saved.get_value("options", "sound_volume", sound_volume)), 0.0, 1.0)
		mouse_sensitivity = clampf(float(saved.get_value("options", "mouse_sensitivity", mouse_sensitivity)), 0.0, 1.0)
		mouse_smoothing = clampf(float(saved.get_value("options", "mouse_smoothing", mouse_smoothing)), 0.0, 2.0)
		invert_mouse = bool(saved.get_value("options", "invert_mouse", invert_mouse))
		console_enabled = bool(saved.get_value("options", "console_enabled", console_enabled))
		if OS.get_environment("SCP_BOT") != "1":   # the bot plays with the shipped options.ini
			for key in SAVED_OPTIONS:
				set(key, saved.get_value("options", key, get(key)))
			intro_enabled = bool(saved.get_value("options", "intro_enabled", intro_enabled))
			var saved_binds: Variant = saved.get_value("options", "binds", binds)
			if saved_binds is Dictionary:
				binds.merge(saved_binds, true)
	apply_settings()

const BIND_KEYS := {"right": "Right key", "left": "Left key", "up": "Up key", "down": "Down key", "blink": "Blink key", "sprint": "Sprint key", "inventory": "Inventory key", "crouch": "Crouch key", "save": "Save key", "console": "Console key"}
const SAVED_OPTIONS := ["vsync", "anti_alias", "room_lights", "screen_gamma", "particle_amount", "texture_details", "enable_user_tracks", "user_track_mode", "hud_enabled", "console_on_error", "achievement_popups", "show_fps", "framelimit", "aa_text", "graphic_width", "graphic_height", "fullscreen", "borderless_windowed", "launcher_enabled", "gfx_driver"]

# The menus' choices, kept for the next session (the original rewrites options.ini).
func save_settings() -> void:
	apply_settings()
	if OS.get_environment("SCP_BOT") == "1":
		return
	settings_config().save("user://options.cfg")

func settings_config() -> ConfigFile:
	var saved := ConfigFile.new()
	saved.set_value("options", "music_volume", music_volume)
	saved.set_value("options", "sound_volume", sound_volume)
	saved.set_value("options", "mouse_sensitivity", mouse_sensitivity)
	saved.set_value("options", "mouse_smoothing", mouse_smoothing)
	saved.set_value("options", "invert_mouse", invert_mouse)
	saved.set_value("options", "console_enabled", console_enabled)
	for key in SAVED_OPTIONS:
		saved.set_value("options", key, get(key))
	saved.set_value("options", "intro_enabled", intro_enabled)
	saved.set_value("options", "binds", binds)
	return saved

# What the options change outside the game logic: Flip 1 / 0, AntiAlias (fullscreen only), TextureLodBias, the
# frame limit, the key binds and the menus' text smoothing.
func apply_settings() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		var root := get_tree().root
		root.msaa_3d = Viewport.MSAA_4X if anti_alias and fullscreen and not borderless_windowed else Viewport.MSAA_DISABLED
		root.texture_mipmap_bias = texture_lod_bias()
		Engine.max_fps = framelimit
	apply_binds()
	UIKit.set_antialiased(aa_text)

func texture_lod_bias() -> float:
	return [0.8, 0.4, 0.0, -0.4, -0.8][clampi(texture_details, 0, 4)]

const BIND_ACTIONS := {"up": "move_forward", "left": "move_left", "down": "move_back", "right": "move_right", "blink": "blink", "sprint": "sprint", "inventory": "inventory", "crouch": "crouch", "save": "quick_save"}

func apply_binds() -> void:
	for key in BIND_ACTIONS:
		var action: String = BIND_ACTIONS[key]
		var keycode := KeyNames.godot_key(int(binds[key]))
		if keycode == KEY_NONE or not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var bound := InputEventKey.new()
		bound.physical_keycode = keycode
		InputMap.action_add_event(action, bound)

func console_key() -> Key:
	return KeyNames.godot_key(int(binds.console))

# Difficulty.bb: SAFE / EUCLID / KETER.
#   aggressiveNPCs: only Keter    permaDeath: only Keter
#   saveType: 0 anywhere (Safe), 1 on screens (Euclid), 2 on quit (Keter)
#   otherFactors: 0 easy, 1 normal, 2 hard
#   CUSTOM (3): the player's choices; it saves anywhere or on screens.
const CUSTOM := 3

func aggressive_npcs() -> bool:
	return custom_aggressive_npcs if difficulty == CUSTOM else difficulty >= 2

func perma_death() -> bool:
	return custom_perma_death if difficulty == CUSTOM else difficulty >= 2

func save_type() -> int:
	if difficulty == CUSTOM:
		return 0 if custom_save_anywhere and not custom_perma_death else 1
	return clampi(difficulty, 0, 2)

func other_factors() -> int:
	return custom_other_factors if difficulty == CUSTOM else clampi(difficulty, 0, 2)

func npc_speed_factor() -> float:
	return [1.0, 1.1, 1.2][other_factors()]
