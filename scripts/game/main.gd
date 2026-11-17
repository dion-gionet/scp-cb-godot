extends Node

const GAMMA_SHADER := "res://shaders/screen_gamma.gdshader"

var world: Node3D
var intro_scene: Node
var menu: Control
var hud: CanvasLayer
var facility: FacilityMap

var _harness: Node
var _gamma: CanvasLayer

func _ready() -> void:
	GameState.load_settings()
	_make_gamma_layer()
	if _interactive():
		if GameState.launcher_enabled:
			await _run_launcher()
		WindowSetup.apply_game(get_window())
		GameState.apply_settings()
	if _interactive() and GameState.play_startup_video and StartupVideos.available():
		await _play_startup_videos()
	_show_menu()
	if _interactive():
		menu.start_boot_music()
		_loading_screen().show_percent(100, true)   # the start-up's DrawLoading(100, True): any key opens the menu
	if OS.get_environment("SCP_BOT") == "1":
		_dev().launch_bot()
	elif OS.get_environment("SCP_PROBE") == "1":
		_dev().run_probe()
	elif OS.get_environment("SCP_MENUSHOT") == "1":
		_dev().menu_shots()
	elif OS.get_environment("SCP_AUTOSHOT") == "1":
		await start_game()   # timed screenshots of the normal start path (dev_harness.autoshot)

# The scripted probes, bot launcher and timed screenshots live in the dev harness.
func _interactive() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for name in ["SCP_BOT", "SCP_PROBE", "SCP_MENUSHOT", "SCP_AUTOSHOT"]:
		if OS.get_environment(name) == "1":
			return false
	return true

# Main.bb: UpdateLauncher runs before anything else is loaded; EXIT ends the program.
func _run_launcher() -> void:
	WindowSetup.show_launcher(get_window())
	var launcher := Launcher.new()
	add_child(launcher)
	launcher.exited.connect(get_tree().quit)
	await launcher.launched
	launcher.queue_free()

# Main.bb PlayStartupVideos, right after the launcher and before anything else is loaded.
func _play_startup_videos() -> void:
	var videos := StartupVideos.new()
	add_child(videos)
	videos.play()
	await videos.finished
	videos.queue_free()

func _loading_screen() -> Node:
	var screen := LoadingScreen.new()
	add_child(screen)
	return screen

# LoadEntities' DrawLoading(0) before the run is built, InitNewGame / InitLoadGame's DrawLoading(100) after it; the
# game waits behind the screen until a key is pressed. `build` takes the progress callback (percent of the loading bar).
func _with_loading_screen(build: Callable) -> void:
	var screen := _loading_screen()
	screen.show_percent(0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var progress := func(percent: float) -> void:
		screen.show_percent(int(percent))
		await RenderingServer.frame_post_draw
	await build.call(progress)
	screen.show_percent(100)
	get_tree().paused = true
	await screen.closed
	get_tree().paused = false

func start_game_with_loading() -> void:
	_with_loading_screen(start_game)

func load_game_with_loading() -> void:
	if SaveGame.read().is_empty():
		return
	_with_loading_screen(load_game)

# ScreenGamma, applied over everything as the end of the main loop does (see shaders/screen_gamma.gdshader).
func _make_gamma_layer() -> void:
	_gamma = CanvasLayer.new()
	_gamma.layer = 127
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load(GAMMA_SHADER)
	rect.material = material
	_gamma.add_child(rect)
	add_child(_gamma)

func _process(_delta: float) -> void:
	if _gamma == null:
		return
	_gamma.visible = not is_equal_approx(GameState.screen_gamma, 1.0)
	if _gamma.visible:
		(_gamma.get_child(0).material as ShaderMaterial).set_shader_parameter("gamma", GameState.screen_gamma)

func _dev() -> Node:
	if _harness == null:
		_harness = load("res://scripts/tests/dev_harness.gd").new()
		_harness.main = self
		add_child(_harness)
	return _harness

func _shot(label: String) -> void:
	if OS.get_environment("SCP_SHOT") != "1":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tests/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(label + ".png")
	var err := image.save_png(path)
	print("SHOT ", path, " err=", err, " size=", image.get_size())

func start_game(progress: Callable = Callable()) -> void:
	if menu:
		menu.visible = false
	GameState.reset_run()
	var loading := not GameState.pending_load.is_empty()
	if loading:
		SaveGame.apply_before_rooms(GameState.pending_load)
	GameState.playing = true
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Blitz AmbientLight: brightness / 255 on every colour channel, which the models are lit with
	MeshLoader.set_ambient(environment, MeshLoader.entity_ambient())
	environment.ambient_light_energy = 1.0
	environment.fog_density = 1.0     # depth fog is scaled by the density; Godot's default 0.01 left it almost clear
	env.environment = environment
	env.add_to_group("world_env")
	world.add_child(env)
	var audio := Node.new()
	audio.set_script(load("res://scripts/audio/audio_director.gd"))
	audio.name = "Audio"
	world.add_child(audio)
	facility = FacilityMap.new()
	facility.name = "Facility"
	world.add_child(facility)
	await RoomRegistry.report(progress, 45.0)
	facility.build_layout()
	if OS.get_environment("SCP_PROBE") == "1":
		print("PROBE layout ", facility.summarize())
	if loading:
		SaveGame.restore_event_state(facility, GameState.pending_load)
	await facility.rooms.build_all(progress)
	await RoomRegistry.report(progress, 80.0)
	var room := Node3D.new()
	room.name = "Chamber"
	room.set_script(load("res://scripts/world/chamber.gd"))
	world.add_child(room)
	room.build()
	facility.register_intro_room(room)
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player/player.gd"))
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.15
	capsule.height = 0.6
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = capsule
	col.position.y = 0.3
	player.add_child(col)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 0.9, 0)
	camera.keep_aspect = Camera3D.KEEP_WIDTH   # Blitz3D: CameraZoom 1 is a 90 degree field of view across the width
	camera.fov = 90.0
	player.add_child(camera)
	var ray := RayCast3D.new()
	ray.name = "InteractRay"
	ray.target_position = Vector3(0, 0, -1.2)
	ray.collision_mask = 1 | 16   # world and the screens
	camera.add_child(ray)
	# UpdateEvents intro: wake up in the Class-D cell, not in the containment doorway.
	var spawn := Vector3(-(3224.0 + 1024.0) * MeshLoader.ROOM_SCALE, 0.0, -8.0 * MeshLoader.ROOM_SCALE)
	spawn.y = room.floor_height(spawn.x, spawn.z, 1.05) + 0.05
	player.position = spawn
	player.rotation.y = deg_to_rad(255.0)
	world.add_child(player)
	GameState.player = player
	var statue := CharacterBody3D.new()
	statue.name = "SCP173"
	statue.set_script(load("res://scripts/npc/scp_173.gd"))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	statue.add_child(mesh_instance)
	var drag := AudioStreamPlayer3D.new()
	drag.name = "Drag"
	statue.add_child(drag)
	var body := CollisionShape3D.new()
	# EntityRadius 0.23, 0.32: roughly a capsule 0.23 wide and 0.64 tall.
	var sphere := CapsuleShape3D.new()
	sphere.radius = 0.23
	sphere.height = 0.64
	body.shape = sphere
	body.position.y = 0.32
	statue.add_child(body)
	var statue_pos := Vector3(32.0 * MeshLoader.ROOM_SCALE, 0.0, -1072.0 * MeshLoader.ROOM_SCALE)
	statue_pos.y = room.floor_height(statue_pos.x, statue_pos.z) + 0.05
	statue.position = statue_pos
	statue.floor_y = statue_pos.y
	statue.rotation.y = deg_to_rad(-190.0)
	world.add_child(statue)
	GameState.scp173 = statue
	if not loading and OS.get_environment("SCP_PROBE") != "1":
		if GameState.intro_enabled:
			# UpdateEvents "173": wake up in the cell, the escort, the demonstration, the breach
			statue.active = false
			intro_scene = Node.new()
			intro_scene.set_script(load("res://scripts/intro/intro_scene.gd"))
			world.add_child(intro_scene)
			intro_scene.begin(room, facility)
		else:
			_enter_facility.call_deferred()   # IntroEnabled = False: the game starts in the breach
	hud = _make_hud()
	if OS.get_environment("SCP_AUTOSHOT") == "1":
		_dev().autoshot()
	add_child(hud)
	var overlay := Control.new()
	overlay.set_script(load("res://scripts/ui/debug_overlay.gd"))
	hud.add_child(overlay)
	if loading:
		_after_loaded_facility()

func _enter_facility() -> void:
	if facility == null or GameState.player == null:
		return
	var intro_room := world.get_node_or_null("Chamber") if world else null
	facility.enter_after_breach(GameState.player, GameState.scp173, intro_room)

func _free_world() -> void:
	if world:
		world.queue_free()
		world = null
	if hud:
		hud.queue_free()
		hud = null
	get_tree().paused = false

func return_to_menu(after_ending := false) -> void:
	_free_world()
	GameState.reset_run()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu()
	menu.tab = 0
	menu._rebuild()
	if after_ending:
		menu.play_end_breath()

func _show_menu() -> void:
	if menu == null:
		menu = _make_menu()
		add_child(menu)
	menu.visible = true

func _make_menu() -> Control:
	var root := Control.new()
	root.set_script(load("res://scripts/ui/main_menu.gd"))
	root.new_game_pressed.connect(start_game_with_loading)
	root.load_game_pressed.connect(load_game_with_loading)
	return root

func _make_hud() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.set_script(load("res://scripts/ui/hud.gd"))
	return layer

# The state of the run goes to the single save slot; false when there is nothing to save.
func save_game() -> bool:
	if facility == null or not facility.active or GameState.player == null:
		return false
	return SaveGame.write(SaveGame.capture(self))

func load_game(progress: Callable = Callable()) -> void:
	var data := SaveGame.read()
	if data.is_empty():
		return
	_free_world()
	await get_tree().process_frame
	GameState.requested_seed = int(data.seed)
	GameState.pending_load = data
	await start_game(progress)

func _after_loaded_facility() -> void:
	var data := GameState.pending_load
	GameState.pending_load = {}
	facility.loading_save = true
	_enter_facility()
	SaveGame.apply_after_rooms(self, data)
