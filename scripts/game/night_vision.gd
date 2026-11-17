extends Node
# Night vision goggles (Main.bb RenderWorld2 / MouseLook, Items.bb). GameState.wearing_night_vision is 1 (the plain
# goggles), 2 (the super ones with the data display) or 3 (the very fine ones); what it changes:
#  - models are lit with ambient Min(Brightness * 2, 255) (255 for the very fine pair), rooms with +15 / 255 on
#    their lightmaps, and the fog reaches 30 (light_fog.gd)
#  - a green (1), blue (2) or red (3) overlay and a different vignette (hud.gd), with the battery bars on the left
#  - plain and super goggles drain their item's `state` (0.02 per frame, x2 for the super pair); at 100 the screen
#    warns, at 0 the batteries die, the player blinks and the view stays black until the goggles come off
#  - the super pair refreshes its readout every 600 frames: the screen blacks out for 10 frames, and the names and
#    positions of the NPCs it labels are the ones taken then
# While the screen is black (IsNVGBlinking) 173 moves even though the player faces it.


var power := 0                 # Int(state) of the worn goggles
var timer := 0.0               # NVTimer
var snapshot: Array = []       # [{name, pos}] at the last refresh (NVX, NVY, NVZ)

func _physics_process(delta: float) -> void:
	var facility := get_parent()
	var holder := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	var player: CharacterBody3D = GameState.player
	var hud := get_tree().get_first_node_in_group("hud")
	if holder == null or player == null or hud == null or not facility.active:
		return
	var s := GameState
	var fps := delta * 70.0
	var kind := s.wearing_night_vision
	var env := holder.environment
	# ambient light of models (RenderWorld2) and the rooms' lightmap lift (AmbientLightRooms)
	if kind != 0:
		var ambient := 1.0 if kind == 3 else minf(MeshLoader.entity_ambient() * 2.0, 1.0)
		MeshLoader.set_ambient(env, ambient)
		s.room_ambient = 15.0 / 255.0
		RenderingServer.global_shader_parameter_set(&"room_ambient", s.room_ambient)
	else:
		var normal := GameState.ambient_override if GameState.ambient_override >= 0.0 else MeshLoader.entity_ambient()
		MeshLoader.set_ambient(env, normal)
		s.room_ambient = 0.0
		RenderingServer.global_shader_parameter_set(&"room_ambient", 0.0)
	s.nvg_blinking = false
	s.nvg_battery = 2
	if kind == 0:
		timer = 0.0
		return
	if kind == 1 or kind == 2:
		var index := _worn_item(hud, "nvgoggles" if kind == 1 else "supernv")
		if index >= 0:
			var data: Dictionary = hud.item_data[index]
			var state := float(data.get("state", 0.0)) - fps * 0.02 * kind
			data["state"] = state
			power = int(state)
			if state <= 0.0:
				s.nvg_battery = 0
				if s.nvg_battery != _last_battery:
					hud.message("The batteries in these night vision goggles died.", 5.0)
					player.blink_timer = -1.0
			elif state <= 100.0:
				s.nvg_battery = 1
		_last_battery = s.nvg_battery
	if s.nvg_battery == 0 and kind != 3:
		s.nvg_blinking = true
	if kind == 2 and s.nvg_battery != 0 and (player.blink_timer < -16.0 or player.blink_timer > -6.0):
		timer -= fps
		if timer <= 0.0:
			_take_snapshot(facility, player)
			s.nvg_blinking = true
			if timer <= -10.0:
				timer = 600.0

var _last_battery := 2

func _worn_item(hud: Node, tempname: String) -> int:
	for i in hud.items.size():
		if not hud.items[i].is_empty() and str(hud.item_data[i].get("tempname", "")) == tempname:
			return i
	return -1

# np\NVX / NVY / NVZ of every NPC the display names
func _take_snapshot(facility: FacilityMap, player: Node3D) -> void:
	snapshot.clear()
	var statue: Node3D = GameState.scp173
	if statue != null and is_instance_valid(statue):
		snapshot.append({"name": "SCP-173", "pos": statue.global_position})
	if facility.scp106 != null and is_instance_valid(facility.scp106):
		snapshot.append({"name": "SCP-106", "pos": facility.scp106.global_position})
	if facility.scp049 != null and is_instance_valid(facility.scp049):
		snapshot.append({"name": "SCP-049", "pos": facility.scp049.global_position})
	for unit in facility.mtf.units:
		if is_instance_valid(unit):
			snapshot.append({"name": "Human", "pos": unit.global_position})
	for human in facility.humans:
		if is_instance_valid(human):
			snapshot.append({"name": "Human", "pos": human.global_position})
