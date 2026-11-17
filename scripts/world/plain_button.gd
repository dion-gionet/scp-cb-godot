extends Node3D
class_name PlainButton
# A button that is not part of a door (Main.bb CreateButton / MapSystem.bb UpdateButton): the Button.x model at 0.03. Within 0.8
# of the player with a clear line from the camera it becomes the ClosestButton, and a click presses it (`pressed` is emitted).
# `Player._interact` and the hand icon ask `Player.closest_plain_button()`, which looks through the "plain_button" group.

signal pressed


func _ready() -> void:
	add_to_group("plain_button")
	var mesh := MeshLoader.load_x(ContentPaths.assets_root.path_join("GFX/map/Button.x"))
	if mesh.get_surface_count() > 0:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.scale = Vector3.ONE * 0.03
		add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("button", true)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, 0.12, 0.12)
	col.shape = box
	body.add_child(col)
	add_child(body)

func press() -> void:
	pressed.emit()
