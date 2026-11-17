class_name MtfDirector
extends RefCounted
const MtfUnit = preload("res://scripts/npc/mtf_unit.gd")

var facility: FacilityMap

func _init(owner_facility: FacilityMap) -> void:
	facility = owner_facility

func update(fps: float) -> void:
	update_squad(fps)
	update_camera_check(fps)

# ---- the Nine-Tailed Fox (Main.bb UpdateMTF, NPCs.bb CreateNPC NPCtypeMTF) ------------------------------------

var units: Array[Node] = []
var timer := 0.0                 # MTFtimer, in 70 Hz frames: 0 = not arrived; 10000, 20000, 25000, 30000 = announcements made
var enabled := OS.get_environment("SCP_BOT") != "1"   # the bot runs without them unless a scenario asks
var announcements: Array[String] = []   # what the PA said (tests)
var _announcement: AudioStreamPlayer = null

func spawn(pos: Vector3, leader: Node = null) -> CharacterBody3D:
	var unit := CharacterBody3D.new()
	unit.set_script(MtfUnit)
	unit.name = "MTF%d" % (units.size() + 1)
	unit.leader = leader
	facility.get_parent().add_child(unit)
	unit.global_position = pos
	units.append(unit)
	return unit

func remove(unit: Node) -> void:
	units.erase(unit)
	if is_instance_valid(unit):
		unit.queue_free()

func play_announcement(relative: String) -> void:
	announcements.append(relative)
	if _announcement != null and is_instance_valid(_announcement):
		_announcement.stop()
		_announcement.queue_free()
	_announcement = Sfx.play_global(facility, relative)

# UpdateMTF: the first time the player gets within 30 of gate A's entrance, the announcement is made and
# three units appear behind the entrance; later announcements follow on a timer.
func update_squad(fps: float) -> void:
	var player := GameState.player
	if player == null or not enabled:
		return
	var here := facility.room_name_at(player.global_position)
	if here == "gateaentrance":
		return
	var reachable := facility.reachable_room(player.global_position)
	if timer == 0.0:
		if randf() * 30.0 < fps and here != "dimension1499":
			var entrance := {}
			for record in facility.generator.rooms:
				if str(record.name) == "gateaentrance":
					entrance = record
					break
			if entrance.is_empty() or absf(entrance.position.z - player.global_position.z) >= 30.0:
				return
			if reachable:
				play_announcement("SFX/Character/MTF/Announc.ogg")
			timer = fps
			var leader: Node = null
			for i in 3:
				var unit := spawn(Vector3(entrance.position.x + 0.3 * (i - 1), 1.0, entrance.position.z - 8.0), leader)
				if i == 0:
					leader = unit
		return
	if timer <= 70.0 * 120.0:
		timer += fps
	elif timer > 70.0 * 120.0 and timer < 10000.0:
		if reachable:
			play_announcement("SFX/Character/MTF/AnnouncAfter1.ogg")
		timer = 10000.0
	elif timer >= 10000.0 and timer <= 10000.0 + 70.0 * 120.0:
		timer += fps
	elif timer > 10000.0 + 70.0 * 120.0 and timer < 20000.0:
		if reachable:
			play_announcement("SFX/Character/MTF/AnnouncAfter2.ogg")
		timer = 20000.0
	elif timer >= 20000.0 and timer <= 20000.0 + 70.0 * 60.0:
		timer += fps
	elif timer > 20000.0 + 70.0 * 60.0 and timer < 25000.0:
		if reachable:
			if _player_holds_scp_item():
				play_announcement("SFX/Character/MTF/ThreatAnnouncPossession.ogg")
			else:
				play_announcement("SFX/Character/MTF/ThreatAnnounc%d.ogg" % randi_range(1, 3))
		timer = 25000.0
	elif timer >= 25000.0 and timer <= 25000.0 + 70.0 * 60.0:
		timer += fps
	elif timer > 25000.0 + 70.0 * 60.0 and timer < 30000.0:
		if reachable:
			play_announcement("SFX/Character/MTF/ThreatAnnouncFinal.ogg")
		timer = 30000.0

func _player_holds_scp_item() -> bool:
	var hud := facility.get_tree().get_first_node_in_group("hud")
	if hud == null:
		return false
	for item_name in hud.items:
		if item_name.begins_with("SCP-") and not item_name.begins_with("SCP-035") and not item_name.begins_with("SCP-093"):
			return true
	return false

# ---- the MTF camera check (NPCs.bb UpdateNPCs end, MapSystem.bb UpdateSecurityCams) -------------------------
# After a lost target an MTF leader sometimes announces a camera check. For the next 90 s every security camera that
# sees the player counts; then the PA says whether the player was found. If so, every unit knows where the player is
# for a minute (MeNPCSeesPlayer returns 3).
var camera_check_timer := 0.0
var camera_check_detected := false
var player_detected := false

func start_camera_check(fps: float) -> void:
	if camera_check_timer == 0.0 and randi_range(1, 15 - (7 if GameState.aggressive_npcs() else 0)) == 1:
		play_announcement("SFX/Character/MTF/AnnouncCameraCheck.ogg")
		camera_check_timer = fps

func update_camera_check(fps: float) -> void:
	if camera_check_timer > 0.0 and camera_check_timer < 70.0 * 90.0:
		camera_check_timer += fps
	elif camera_check_timer >= 70.0 * 90.0:
		camera_check_timer = 0.0
		if not player_detected:
			if camera_check_detected:
				play_announcement("SFX/Character/MTF/AnnouncCameraFound%d.ogg" % randi_range(1, 2))
				player_detected = true
				camera_check_timer = 70.0 * 60.0
			else:
				play_announcement("SFX/Character/MTF/AnnouncCameraNoFound.ogg")
		camera_check_detected = false
		if camera_check_timer == 0.0:
			player_detected = false
