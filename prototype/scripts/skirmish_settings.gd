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
		"allied_victory_enabled": false,
		"full_tech_tree": false,
		"players": slots,
	}


static func normalize(source: Dictionary) -> Dictionary:
	var settings := default_settings()
	for key in source:
		settings[key] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
	var errors: Array[String] = []
	if int(settings.get("schema_version", 0)) != 1:
		errors.append("skirmish_settings_schema_unsupported")
	settings["schema_version"] = int(settings.get("schema_version", 0))
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
	if not settings.get("allied_victory_enabled") is bool:
		errors.append("skirmish_allied_victory_invalid")
	if not settings.get("full_tech_tree") is bool:
		errors.append("skirmish_full_tech_tree_invalid")
	if not _array_has_int(source_catalog.get("population_limits", []), int(settings.get("population_limit", 0))):
		errors.append("skirmish_population_limit_invalid")
	settings["population_limit"] = int(settings.get("population_limit", 0))
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
		if civilization_id < 0 or civilization_id > 16:
			errors.append("skirmish_player_civilization_invalid:%d" % team)
		if controller not in (["human", "ai", "remote"] if bool(settings.get("networked", false)) else ["human", "ai"]):
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
	var starts := _start_positions(settings["players"].size(), size, String(settings["map_type_id"]), int(settings["seed"]), map_type_entry)
	var civilization_rng := RandomNumberGenerator.new()
	civilization_rng.seed = int(settings["seed"]) ^ 0x52C7A8D1
	var definition_players: Array = []
	var entities: Array = []
	for index in range(settings["players"].size()):
		var slot: Dictionary = settings["players"][index]
		var team := int(slot["team"])
		var civilization_id := int(slot["civilization_id"])
		if civilization_id == 0:
			civilization_id = civilization_rng.randi_range(1, 16)
		var start: Vector2 = starts[index]
		definition_players.append({
			"team": team,
			"controller": String(slot["controller"]),
			"civilization_id": civilization_id,
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
		entities.append({"category": "building", "team": team, "kind": "town_center", "position": start, "resource_exclusion_radius_cells": 2})
		for position in _starting_villager_positions(start, size):
			entities.append({"category": "unit", "team": team, "kind": "villager", "position": position, "selected": team == 1, "resource_exclusion_radius_cells": 1})

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
		"allied_victory_enabled": bool(settings["allied_victory_enabled"]),
		"full_tech_tree": bool(settings["full_tech_tree"]),
		"skirmish_settings": settings.duplicate(true),
	}
	if bool(settings.get("networked", false)):
		raw_definition["networked"] = true
	var definition := MatchDefinition.normalize(raw_definition)
	if not bool(definition.get("valid", false)):
		return {"valid": false, "errors": definition.get("errors", []), "settings": settings, "definition": definition}
	var map_data := RandomMapGenerator.generate(definition)
	var objective_entities := _generated_victory_objectives(definition, map_data)
	var required_objective_modes: int = definition.get("victory_rules", []).filter(func(rule): return String(rule.get("type", "")) in ["ruins", "artifacts"]).size()
	if objective_entities.size() != required_objective_modes * 2:
		return {"valid": false, "errors": ["victory_objective_placement_failed"], "settings": settings, "definition": definition, "map_data": map_data}
	if not objective_entities.is_empty():
		raw_definition["entities"].append_array(objective_entities)
		definition = MatchDefinition.normalize(raw_definition)
		if not bool(definition.get("valid", false)):
			return {"valid": false, "errors": definition.get("errors", []), "settings": settings, "definition": definition, "map_data": map_data}
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


static func _start_positions(count: int, size: Vector2i, map_type: String, seed: int = 1, map_profile: Dictionary = {}) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x726F5231
	if map_type in ["mediterranean", "narrows"]:
		var first_side_count := int(ceil(float(count) * 0.5))
		var second_side_count := count - first_side_count
		for index in range(count):
			var first_side := index < first_side_count
			var rank := index if first_side else index - first_side_count
			var side_count := first_side_count if first_side else second_side_count
			var spacing := clampf(float(rank + 1) / float(side_count + 1) + rng.randf_range(-0.025, 0.025), 0.08, 0.92)
			if map_type == "mediterranean":
				result.append(_safe_start_position(Vector2(size.x * spacing, size.y * ((0.23 if first_side else 0.77) + rng.randf_range(-0.025, 0.025))), Vector2(size) * 0.5, size, map_type, map_profile, seed))
			else:
				result.append(_safe_start_position(Vector2(size.x * ((0.23 if first_side else 0.77) + rng.randf_range(-0.025, 0.025)), size.y * spacing), Vector2(size) * 0.5, size, map_type, map_profile, seed))
		return result
	var center := Vector2(size) * 0.5
	# Eight large islands need more room on the outer ring: the normal ring
	# forces their coastlines to shrink until starts lose food-bearing land.
	var radius_fraction := 0.36 if map_type == "islands" and count >= 8 else 0.32 if map_type in ["islands", "small_islands"] else 0.25 if map_type == "continental" else 0.28
	var radius := minf(float(size.x), float(size.y)) * radius_fraction
	var minimum_margin := maxf(8.0, mini(size.x, size.y) * 0.18) if map_type in ["coastal", "continental"] else 5.0
	var phase := rng.randf_range(-PI / float(maxi(1, count)), PI / float(maxi(1, count)))
	for index in range(count):
		var angle := -PI * 0.5 + phase + TAU * float(index) / float(maxi(1, count)) + rng.randf_range(-0.035, 0.035)
		var point := center + Vector2(cos(angle), sin(angle)) * radius * rng.randf_range(0.96, 1.04)
		point.x = clampf(point.x, minimum_margin, float(size.x) - 5.0)
		point.y = clampf(point.y, minimum_margin, float(size.y) - 5.0)
		result.append(_safe_start_position(point, center, size, map_type, map_profile, seed))
	return result


static func _safe_start_position(candidate: Vector2, center: Vector2, size: Vector2i, map_type: String, map_profile: Dictionary, seed: int) -> Vector2:
	if map_type not in ["coastal", "continental", "mediterranean", "hill_country", "narrows"]:
		return candidate
	var cliffs: Dictionary = {}
	for cliff_cell in RandomMapGenerator._profile_cliff_cells(size, String(map_profile.get("cliff_profile", "")), seed):
		cliffs[cliff_cell] = true
	for radius in range(11):
		for delta_y in range(-radius, radius + 1):
			for delta_x in range(-radius, radius + 1):
				if maxi(absi(delta_x), absi(delta_y)) != radius:
					continue
				var point := candidate + Vector2(delta_x, delta_y)
				if point.x < 5.0 or point.y < 5.0 or point.x >= size.x - 5.0 or point.y >= size.y - 5.0:
					continue
				if _start_site_clear(point, size, map_type, map_profile, seed, cliffs):
					return point
	return center


static func _start_site_clear(point: Vector2, size: Vector2i, map_type: String, map_profile: Dictionary, seed: int, cliffs: Dictionary) -> bool:
	var cells: Array[Vector2i] = []
	var center_cell := Vector2i(point)
	for offset_y in range(-2, 3):
		for offset_x in range(-2, 3):
			cells.append(center_cell + Vector2i(offset_x, offset_y))
	for villager_position in _starting_villager_positions(point, size):
		cells.append(Vector2i(villager_position))
	for cell in cells:
		if cliffs.has(cell) or RandomMapGenerator._seeded_water_cell(cell, size, [], map_type, map_profile, seed):
			return false
	return true


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
	var rules: Array = entry.get("rules", [])
	return rules.duplicate(true) if not rules.is_empty() else [{"type": "conquest"}]


static func _generated_victory_objectives(definition: Dictionary, map_data: Dictionary) -> Array:
	var categories: Array[String] = []
	for rule_value in definition.get("victory_rules", []):
		var rule_type := String(rule_value.get("type", ""))
		if rule_type in ["ruins", "artifacts"] and rule_type not in categories:
			categories.append(rule_type)
	if categories.is_empty():
		return []
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	var cliff_cells: Dictionary = {}
	for cell_value in map_data.get("cliff_cells", []):
		cliff_cells[Vector2i(cell_value)] = true
	if terrain_ids.size() != size.x * size.y:
		return []
	var excluded: Dictionary = {}
	for cliff_cell in cliff_cells.keys():
		_mark_victory_exclusion(excluded, Vector2i(cliff_cell), size, 1)
	var starts: Array[Vector2] = []
	for player_value in definition.get("players", []):
		var start := Vector2(player_value.get("start", Vector2.ZERO))
		starts.append(start)
		_mark_victory_exclusion(excluded, Vector2i(floori(start.x), floori(start.y)), size, 4)
	for entity_value in definition.get("entities", []) + map_data.get("resources", []):
		var position := Vector2(entity_value.get("position", Vector2.ZERO))
		_mark_victory_exclusion(excluded, Vector2i(floori(position.x), floori(position.y)), size, 2)
	var result: Array = []
	var count_per_category := mini(2, starts.size())
	var total_cells := size.x * size.y
	var start_index := posmod(int(map_data.get("seed", 1)), total_cells)
	for category in categories:
		for _objective_index in range(count_per_category):
			var chosen := Vector2i(-1, -1)
			var best_distance := -1.0
			for offset in range(total_cells):
				var index := (start_index + offset) % total_cells
				var cell := Vector2i(index % size.x, floori(float(index) / float(size.x)))
				if cell.x < 2 or cell.y < 2 or cell.x >= size.x - 2 or cell.y >= size.y - 2 or excluded.has(cell) or cliff_cells.has(cell):
					continue
				if int(terrain_ids[index]) in [1, 4, 22]:
					continue
				var candidate := Vector2(cell) + Vector2.ONE * 0.5
				var minimum_distance := INF
				for start in starts:
					minimum_distance = minf(minimum_distance, candidate.distance_squared_to(start))
				for placed_value in result:
					minimum_distance = minf(minimum_distance, candidate.distance_squared_to(Vector2(placed_value["position"])))
				if minimum_distance > best_distance:
					best_distance = minimum_distance
					chosen = cell
			if chosen.x < 0:
				return result
			var position := Vector2(chosen) + Vector2.ONE * 0.5
			if category == "artifacts":
				result.append({"category": "unit", "team": 0, "kind": "artifact", "source_unit_id": 159, "position": position})
			else:
				# Imported RoR ruin objectives use source graphic 8. Keep the
				# generated objective visible through the same presentation path.
				result.append({"category": "objective", "team": 0, "kind": "ruin", "source_unit_id": 158, "graphic_id": 8, "asset_name": "graphic_8", "position": position})
			_mark_victory_exclusion(excluded, chosen, size, 4)
	return result


static func _mark_victory_exclusion(excluded: Dictionary, cell: Vector2i, size: Vector2i, radius: int) -> void:
	for y in range(maxi(0, cell.y - radius), mini(size.y - 1, cell.y + radius) + 1):
		for x in range(maxi(0, cell.x - radius), mini(size.x - 1, cell.x + radius) + 1):
			excluded[Vector2i(x, y)] = true


static func _player_ai_settings(policy: Dictionary, enabled: bool) -> Dictionary:
	var result := policy.duplicate(true)
	result.erase("valid")
	result.erase("errors")
	result["enabled"] = enabled
	return result
