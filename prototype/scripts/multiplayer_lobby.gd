class_name RoRMultiplayerLobby
extends RefCounted

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var settings: Dictionary = {}
var player_count: int = 0


func configure_from_skirmish(requested_settings: Dictionary) -> String:
	var slots: Variant = requested_settings.get("players")
	if not slots is Array:
		return "lobby_players_missing"
	var count := 0
	for slot_value in slots:
		if slot_value is Dictionary and bool(slot_value.get("enabled", false)):
			count += 1
	if count < 2 or count > 8:
		return "lobby_player_count_invalid"
	settings = requested_settings.duplicate(true)
	settings["networked"] = true
	player_count = count
	for slot_value in settings["players"]:
		var slot: Dictionary = slot_value
		if bool(slot.get("enabled", false)):
			slot["controller"] = "human" if int(slot.get("team", 0)) == 1 else "remote"
	return validation_error()


func invite_code() -> String:
	if not validation_error().is_empty():
		return ""
	return "ROR1-" + Marshalls.raw_to_base64(JSON.stringify(settings).to_utf8_buffer())


func load_invite(code: String) -> String:
	if not code.begins_with("ROR1-") or code.length() > 8192:
		return "lobby_invite_invalid"
	var bytes := Marshalls.base64_to_raw(code.substr(5))
	if bytes.is_empty():
		return "lobby_invite_invalid"
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not decoded is Dictionary or not bool(decoded.get("networked", false)):
		return "lobby_invite_invalid"
	return configure_from_skirmish(decoded)


func configure(requested_player_count: int, options: Dictionary = {}) -> String:
	if requested_player_count < 2 or requested_player_count > 8:
		return "lobby_player_count_invalid"
	player_count = requested_player_count
	settings = SkirmishSettings.default_settings()
	settings["networked"] = true
	for key in ["map_size_id", "map_type_id", "seed", "resource_preset_id", "starting_age_id", "population_limit", "victory_mode_id", "allied_victory_enabled", "full_tech_tree", "ai_difficulty_id"]:
		if options.has(key):
			settings[key] = options[key]
	var slots: Array = settings["players"]
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		slot["enabled"] = index < requested_player_count
		slot["controller"] = "human" if index == 0 else "remote"
	return validation_error()


func set_slot(team: int, civilization_id: int, alliance_id: int, controller_type: String = "remote") -> String:
	if team < 1 or team > player_count or controller_type not in ["human", "remote"]:
		return "lobby_slot_invalid"
	if team == 1 and controller_type != "human" or team != 1 and controller_type == "human":
		return "lobby_host_controller_invalid"
	var slots: Array = settings.get("players", [])
	for slot_value in slots:
		var slot: Dictionary = slot_value
		if int(slot.get("team", 0)) == team:
			slot["civilization_id"] = civilization_id
			slot["alliance_id"] = alliance_id
			slot["controller"] = controller_type
			return validation_error()
	return "lobby_slot_missing"


func validation_error() -> String:
	if settings.is_empty():
		return "lobby_unconfigured"
	var normalized: Dictionary = SkirmishSettings.normalize(settings)
	return "" if bool(normalized.get("valid", false)) else String(normalized.get("errors", ["lobby_invalid"])[0])


func participant_teams() -> Array[int]:
	var result: Array[int] = []
	for slot_value in settings.get("players", []):
		var slot: Dictionary = slot_value
		if bool(slot.get("enabled", false)) and String(slot.get("controller", "")) in ["human", "remote"]:
			result.append(int(slot.get("team", 0)))
	result.sort()
	return result


func build_match() -> Dictionary:
	var error := validation_error()
	if not error.is_empty():
		return {"valid": false, "errors": [error]}
	return SkirmishSettings.build(settings)
