class_name GameVersion
extends RefCounted
# The port's own SemVer number lives in project.godot (application/config/version); ORIGINAL is the Blitz3D release it
# follows, shown as SemVer build metadata ("1.0.0+cb1.3.11"). Saves have their own SaveGame.VERSION.

const ORIGINAL := "1.3.11"

static func number() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func full() -> String:
	return "%s+cb%s" % [number(), ORIGINAL]

static func file_safe() -> String:
	return full().replace("+", "-")
