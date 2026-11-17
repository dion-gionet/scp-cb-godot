extends Node3D
# Lift call buttons that do nothing (UpdateEvents.bb "room1lifts" and "room2shaft": UpdateButton on Objects[...], then
# "The elevator appears to be broken." with ButtonSFX2 and a 5 s message). Built by facility_room for those two rooms.

const RS := 8.0 / 2048.0

var buttons: Array[Node3D] = []

# spots: [raw x, y, z of the FillRoom call, yaw]
func build(spots: Array) -> void:
	for spot in spots:
		var button := Node3D.new()
		button.set_script(PlainButton)
		add_child(button)
		button.position = Vector3(spot[0] * RS, spot[1] * RS, -spot[2] * RS)
		button.rotation.y = deg_to_rad(float(spot[3]))
		button.pressed.connect(_pressed.bind(button))
		buttons.append(button)

func _pressed(button: Node3D) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.message("The elevator appears to be broken.", 5.0)
	Sfx.play_at(button, "SFX/Interact/Button2.ogg", 10.0)
