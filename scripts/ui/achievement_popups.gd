extends Control
class_name AchievementPopups
# Achievements.bb CreateAchievementMsg / UpdateAchievementMsg: a 264 x 84 box slides in from the right edge, stays 70 * 7 frames,
# slides out; newer boxes push older ones up.

const HOLD_FRAMES := 70.0 * 7.0

var messages: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameState.achievement_unlocked.connect(add)
	UIKit.prewarm()

func add(index: int) -> void:
	messages.append({"index": index, "x": 0.0, "time": 1.0, "title": "Achievement Unlocked - " + AchievementInfo.title(index), "picture": AchievementInfo.picture(index)})

func _process(delta: float) -> void:
	if messages.is_empty():
		return
	var fps := delta * 70.0
	var width := 264.0 * UIKit.menu_scale(self) * 4.0 / 3.0
	for message in messages:
		var time: float = message.time
		if time > 0.0 and time < HOLD_FRAMES:
			message.time = time + fps
			if message.x > -width:
				message.x = maxf(message.x - 4.0 * fps, -width)
		elif time >= HOLD_FRAMES:
			message.time = -1.0
		elif time == -1.0:
			if message.x < 0.0:
				message.x = minf(message.x + 4.0 * fps, 0.0)
			else:
				message.time = 0.0
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].time == 0.0:
			messages.remove_at(i)
	queue_redraw()

func _draw() -> void:
	var s := UIKit.menu_scale(self)
	var scale_value := s * 4.0 / 3.0
	var width := 264.0 * scale_value
	var height := 84.0 * scale_value
	for i in messages.size():
		var message := messages[i]
		var y := size.y - height * (messages.size() - i)
		var x: float = size.x + message.x
		UIKit.draw_frame(self, Rect2(x, y, width, height), s)
		var picture_rect := Rect2(x + 10.0 * scale_value, y + 10.0 * scale_value, 64.0 * scale_value, 64.0 * scale_value)
		draw_rect(picture_rect, Color.BLACK)
		var picture: Texture2D = message.picture
		if picture != null:
			draw_texture_rect(picture, picture_rect, false)
		draw_rect(picture_rect, Color8(50, 50, 50), false)
		UIKit.draw_row_text(self, Vector2(x + 84.0 * scale_value, y + 10.0 * scale_value), message.title, width - 94.0 * scale_value, height, Color.WHITE, s)
