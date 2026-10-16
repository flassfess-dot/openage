class_name RoRMatchPreferences
extends RefCounted

const PATH := "user://settings/game_menu.cfg"
var values := {"music": 0.65, "sound": 0.85, "scroll": 1.0, "fullscreen": false, "screen_size": Vector2i(1280, 720)}

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	for key in values:
		var value: Variant = config.get_value("game", key, values[key])
		if typeof(value) == typeof(values[key]): values[key] = value
	values["music"] = clampf(float(values["music"]), 0, 1)
	values["sound"] = clampf(float(values["sound"]), 0, 1)
	values["scroll"] = clampf(float(values["scroll"]), 0.25, 3)
	var screen: Vector2i = values["screen_size"]
	values["screen_size"] = Vector2i(clampi(screen.x, 640, 7680), clampi(screen.y, 480, 4320))

func save_settings(updated: Dictionary) -> Error:
	for key in values:
		if updated.has(key) and typeof(updated[key]) == typeof(values[key]): values[key] = updated[key]
	var config := ConfigFile.new()
	for key in values: config.set_value("game", key, values[key])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://settings"))
	return config.save(PATH)
