class_name RoRSkirmishSettings
extends RefCounted

const CATALOG_PATH := "res://data/skirmish/settings_catalog.json"
const MatchDefinition := preload("res://scripts/match_definition.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const RandomMapContract := preload("res://scripts/random_map_contract.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const RandomMapQuality := preload("res://scripts/random_map_quality.gd")
const SkirmishAiPolicy := preload("res://scripts/skirmish_ai_policy.gd")


static func catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"valid": false, "errors": ["skirmish_catalog_missing"]}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		return {"valid": false, "errors": ["skirmish_catalog_invalid"]}
	var result: Dictionary = parsed
	result["ai_difficulties"] = SkirmishAiPolicy.difficulty_entries()
	result["valid"] = int(result.get("schema_version", 0)) == 1
	result["errors"] = [] if bool(result["valid"]) else ["skirmish_catalog_schema_unsupported"]
	return result


static func default_settings() -> Dictionary:
	var slots: Array = []
	for slot in range(1, 9):
		slots.append({
			"enabled": slot <= 2,
			"team": slot,
			"controller": "human" if slot == 1 else "ai",
			"civilization_id": 13 if slot == 1 else 8 if slot == 2 else ((slot - 1) % 16) + 1,
			"color_index": slot,
			"alliance_id": slot,
		})
	return {
		"schema_version": 1,
		"map_size_id": "standard",
		"map_type_id": "grasslands",
		"seed": 41721,
		"resource_preset_id": "standard",
		"starting_age_id": "stone",
		"population_limit": 50,
		"ai_difficulty_id": "standard",
		"victory_mode_id": "conquest",
		"players": slots,
	}


static func normalize(source: Dictionary) -> Dictionary:
	var settings := default_settings()
	for key in source:
		settings[key] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
	var errors: Array[String] = []
	if int(settings.get("schema_version", 0)) != 1:
		errors.append("skirmish_settings_schema_unsupported")
	var source_catalog := catalog()
	if not bool(source_catalog.get("valid", false)):
		errors.append_array(source_catalog.get("errors", []))
		return {"valid": false, "errors": errors, "settings": settings}

	_validate_catalog_reference(settings, source_catalog, "map_size_id", "map_sizes", errors)
	_validate_catalog_reference(settings, source_catalog, "map_type_id", "map_types", errors)
	_validate_catalog_reference(settings, source_catalog, "resource_preset_id", "resource_presets", errors)
	_validate_catalog_reference(settings, source_catalog, "starting_age_id", "starting_ages", errors)
	_validate_catalog_reference(settings, source_catalog, "ai_difficulty_id", "ai_difficulties", errors)
	_validate_catalog_reference(settings, source_catalog, "victory_mode_id", "victory_modes", errors)
	if not _array_has_int(source_catalog.get("population_limits", []), int(settings.get("population_limit", 0))):
		errors.append("skirmish_population_limit_invalid")
	settings["seed"] = int(settings.get("seed", 1))
	if int(settings["seed"]) <= 0:
		errors.append("skirmish_seed_invalid")

	var normalized_players: Array = []
	var teams: Dictionary = {}
	var colors: Dictionary = {}
	var human_count := 0
	var human_team := 0
	for player_value in settings.get("players", []):
		if not player_value is Dictionary:
			errors.append("skirmish_player_invalid")
			continue
		var player: Dictionary = player_value.duplicate(true)
		if not bool(player.get("enabled", false)):
			continue
		var team := int(player.get("team", 0))
		var color_index := int(player.get("color_index", 0))
		var civilization_id := int(player.get("civilization_id", 0))
		var controller := String(player.get("controller", "ai"))
		var alliance_id := int(player.get("alliance_id", team))
		if team < 1 or team > 8 or teams.has(team):
			errors.append("skirmish_player_team_invalid:%d" % team)
		else:
			teams[team] = true
		if color_index < 1 or color_index > 8 or colors.has(color_index):
			errors.append("skirmish_player_color_invalid:%d" % color_index)
		else:
			colors[color_index] = true
		if civilization_id < 1 or civilization_id > 16:
			errors.append("skirmish_player_civilization_invalid:%d" % team)
		if controller not in ["human", "ai"]:
			errors.append("skirmish_player_controller_invalid:%d" % team)
		elif controller == "human":
			human_count += 1
			human_team = team
		if alliance_id < 1 or alliance_id > 8:
			errors.append("skirmish_player_alliance_invalid:%d" % team)
		player["team"] = team
		player["color_index"] = color_index
		player["civilization_id"] = civilization_id
		player["controller"] = controller
		player["alliance_id"] = alliance_id
		normalized_players.append(player)
	normalized_players.sort_custom(func(left, right): return int(left.get("team", 0)) < int(right.get("team", 0)))
	var limits: Dictionary = source_catalog.get("player_count", {})
	if normalized_players.size() < int(limits.get("minimum", 2)) or normalized_players.size() > int(limits.get("maximum", 8)):
		errors.append("skirmish_player_count_invalid")
	if human_count != 1:
		errors.append("skirmish_local_human_count_invalid")
	elif human_team != 1:
		errors.append("skirmish_local_human_team_invalid")
	var size_entry := _entry(source_catalog.get("map_sizes", []), String(settings.get("map_size_id", "")))
	if not size_entry.is_empty() and normalized_players.size() > int(size_entry.get("max_players", 8)):
		errors.append("skirmish_map_player_capacity_exceeded")
	settings["players"] = normalized_players
	return {"valid": errors.is_empty(), "errors": errors, "settings": settings}


static func build(source: Dictionary) -> Dictionary:
	var normalized := normalize(source)
	if not bool(normalized.get("valid", false)):
		return {"valid": false, "errors": normalized.get("errors", []), "settings": normalized.get("settings", {})}
	var settings: Dictionary = normalized["settings"]
	var source_catalog := catalog()
	var size_entry := _entry(source_catalog.get("map_sizes", []), String(settings["map_size_id"]))
	var map_type_entry := _entry(source_catalog.get("map_types", []), String(settings["map_type_id"]))
	var resource_entry := _entry(source_catalog.get("resource_presets", []), String(settings["resource_preset_id"]))
	var age_entry := _entry(source_catalog.get("starting_ages", []), String(settings["starting_age_id"]))
	var victory_entry := _entry(source_catalog.get("victory_modes", []), String(settings["victory_mode_id"]))
	var ai_policy := SkirmishAiPolicy.resolve("random_map_balanced", String(settings["ai_difficulty_id"]))
	if not bool(ai_policy.get("valid", false)):
		return {"valid": false, "errors": ai_policy.get("errors", []), "settings": settings}
	var size_values: Array = size_entry.get("size", [72, 72])
	var size := Vector2i(int(size_values[0]), int(size_values[1]))
	var starts := _start_positions(settings["players"].size(), size, String(settings["map_type_id"]))
	var definition_players: Array = []
	var entities: Array = []
	for index in range(settings["players"].size()):
		var slot: Dictionary = settings["players"][index]
		var team := int(slot["team"])
		var start: Vector2 = starts[index]
		definition_players.append({
			"team": team,
			"controller": String(slot["controller"]),
			"civilization_id": int(slot["civilization_id"]),
			"color_index": int(slot["color_index"]),
			"alliance_id": int(slot["alliance_id"]),
			"start": start,
			"population_limit": int(settings["population_limit"]),
			"population_housing": 4,
			"starting_resources": resource_entry.get("resources", {}).duplicate(true),
			"starting_age_technology_id": int(age_entry.get("technology_id", 100)),
			"starting_technology_mode": "age_start",
			"ai": _player_ai_settings(ai_policy, String(slot["controller"]) == "ai"),
		})
		entities.append({"category": "building", "team": team, "kind": "town_center", "position": start})
		for position in _starting_villager_positions(start, size):
			entities.append({"category": "unit", "team": team, "kind": "villager", "position": position, "selected": team == 1})

	var raw_definition := {
		"schema_version": 1,
		"id": "generated_skirmish",
		"title": "Rise of Rome — случайная игра",
		"start_message": "Развивайте поселение и одержите победу",
		"map": {
			"size": [size.x, size.y],
			"seed": int(settings["seed"]),
			"type_id": String(settings["map_type_id"]),
			"generator": RandomMapContract.build(map_type_entry, size, starts),
		},
		"players": definition_players,
		"entities": entities,
		"alliances": _alliances(settings["players"]),
		"diplomacy": [],
		"victory_rules": _victory_rules(victory_entry),
		"skirmish_settings": settings.duplicate(true),
	}
	var definition := MatchDefinition.normalize(raw_definition)
	if not bool(definition.get("valid", false)):
		return {"valid": false, "errors": definition.get("errors", []), "settings": settings, "definition": definition}
	var map_data := RandomMapGenerator.generate(definition)
	var map_quality := RandomMapQuality.inspect(definition, map_data)
	if not bool(map_quality.get("valid", false)):
		return {"valid": false, "errors": map_quality.get("errors", []), "settings": settings, "definition": definition, "map_data": map_data, "map_quality": map_quality}
	var fingerprint := GameSaveArchive.fingerprint(definition)
	return {
		"valid": true,
		"errors": [],
		"settings": settings,
		"definition": definition,
		"map_data": map_data,
		"map_quality": map_quality,
		"identity": "generated://skirmish/%s" % fingerprint.left(24),
	}


static func _validate_catalog_reference(settings: Dictionary, source_catalog: Dictionary, key: String, collection: String, errors: Array[String]) -> void:
	if _entry(source_catalog.get(collection, []), String(settings.get(key, ""))).is_empty():
		errors.append("skirmish_%s_invalid" % key)


static func _entry(entries: Array, identifier: String) -> Dictionary:
	for value in entries:
		if value is Dictionary and String(value.get("id", "")) == identifier:
			return value
	return {}


static func _array_has_int(values: Array, expected: int) -> bool:
	return values.any(func(value): return int(value) == expected)


static func _start_positions(count: int, size: Vector2i, map_type: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var center := Vector2(size) * 0.5
	var radius := minf(float(size.x), float(size.y)) * 0.32
	var minimum_margin := maxf(8.0, mini(size.x, size.y) * 0.18) if map_type == "coastal" else 5.0
	for index in range(count):
		var angle := -PI * 0.5 + TAU * float(index) / float(maxi(1, count))
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		point.x = clampf(point.x, minimum_margin, float(size.x) - 5.0)
		point.y = clampf(point.y, minimum_margin, float(size.y) - 5.0)
		result.append(point)
	return result


static func _starting_villager_positions(start: Vector2, size: Vector2i) -> Array[Vector2]:
	var inward := (Vector2(size) * 0.5 - start).normalized()
	if inward.length_squared() <= 0.000001:
		inward = Vector2.DOWN
	var side := Vector2(-inward.y, inward.x)
	var forward_distance := 3.25
	return [
		start + inward * forward_distance - side * 1.1,
		start + inward * (forward_distance + 0.3),
		start + inward * forward_distance + side * 1.1,
	]


static func _alliances(players: Array) -> Array:
	var result: Array = []
	for first_index in range(players.size()):
		for second_index in range(first_index + 1, players.size()):
			if int(players[first_index].get("alliance_id", 0)) == int(players[second_index].get("alliance_id", -1)):
				result.append([int(players[first_index]["team"]), int(players[second_index]["team"])])
	return result


static func _victory_rules(entry: Dictionary) -> Array:
	if String(entry.get("id", "conquest")) == "score_60":
		return [{"type": "score", "score_limit": 0, "time_limit_seconds": int(entry.get("time_limit_seconds", 3600))}]
	return [{"type": "conquest"}]


static func _player_ai_settings(policy: Dictionary, enabled: bool) -> Dictionary:
	var result := policy.duplicate(true)
	result.erase("valid")
	result.erase("errors")
	result["enabled"] = enabled
	return result
