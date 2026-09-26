class_name RoRRandomMapSourceProfile
extends RefCounted

const CATALOG_PATH := "res://data/skirmish/ror_random_maps.json"

static var _profiles: Dictionary = {}


static func get_profile(profile_id: String) -> Dictionary:
	if _profiles.is_empty():
		_load_profiles()
	return _profiles.get(profile_id, {}).duplicate(true)


static func _load_profiles() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return
	for profile_value in parsed.get("profiles", []):
		if profile_value is Dictionary:
			var profile: Dictionary = profile_value
			_profiles[String(profile.get("profile_id", ""))] = profile
