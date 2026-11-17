class_name AchievementInfo
extends RefCounted
# Data\achievementstrings.ini (Achievements.bb 22-33): title, description and picture of each achievement index.

static var _ini: IniFile

static func _data() -> IniFile:
	if _ini == null:
		_ini = IniFile.parse(ContentPaths.existing_file("Data/achievementstrings.ini"))
	return _ini

static func title(index: int) -> String:
	return _data().get_value("s%d" % index, "string1")

static func description(index: int) -> String:
	return _data().get_value("s%d" % index, "achvdesc")

static func picture(index: int) -> Texture2D:
	return UIKit.texture("GFX/menu/achievements/%s.jpg" % _data().get_value("s%d" % index, "image"))

static func locked_picture() -> Texture2D:
	return UIKit.texture("GFX/menu/achievements/achvlocked.jpg")

static func index_of(name: String) -> int:
	return GameState.ACHIEVEMENT_ORDER.find(name)
