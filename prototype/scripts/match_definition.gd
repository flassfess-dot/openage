class_name RoRMatchDefinition
extends RefCounted

const DEFAULT_PATH := "res://data/matches/prototype_match.json"
const ScenarioDefinition := preload("res://scripts/scenario_definition.gd")


static func load_json(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "errors": ["match_file_missing:%s" % path]}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"valid": false, "errors": ["match_json_invalid:%s" % path]}
	var result := normalize(parsed)
	result["source_path"] = path
	return result


static func normalize(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var errors: Array[String] = []
	var map: Dictionary = result.get("map", {})
	var size_values: Array = map.get("size", [])
	if size_values.size() != 2:
		errors.append("map_size_required")
		map["size"] = Vector2i(24, 24)
	else:
		map["size"] = Vector2i(int(size_values[0]), int(size_values[1]))
		if map["size"].x < 8 or map["size"].y < 8 or map["size"].x > 256 or map["size"].y > 256:
			errors.append("map_size_out_of_range")
	map["seed"] = int(map.get("seed", 1))
	var generator: Dictionary = map.get("generator", {})
	if String(generator.get("type", "")) == "fixed_source":
		var terrain_ids: Array = generator.get("terrain_ids", [])
		var vertex_levels: Array = generator.get("vertex_levels", [])
		if terrain_ids.size() != map["size"].x * map["size"].y:
			errors.append("fixed_map_terrain_size_mismatch")
		if vertex_levels.size() != (map["size"].x + 1) * (map["size"].y + 1):
			errors.append("fixed_map_vertex_size_mismatch")
	result["map"] = map

	var teams: Dictionary = {}
	var human_teams: Array[int] = []
	for player_value in result.get("players", []):
		var player: Dictionary = player_value
		var team := int(player.get("team", 0))
		if team <= 0:
			errors.append("player_team_invalid")
		elif teams.has(team):
			errors.append("player_team_duplicate:%d" % team)
		else:
			teams[team] = true
		var controller := String(player.get("controller", "ai"))
		if controller not in ["human", "ai"]:
			errors.append("player_controller_invalid:%d" % team)
		elif controller == "human":
			human_teams.append(team)
		if int(player.get("civilization_id", -1)) < 0:
			errors.append("player_civilization_invalid:%d" % team)
		if player.has("population_limit"):
			player["population_limit"] = int(player["population_limit"])
			if int(player["population_limit"]) <= 0:
				errors.append("player_population_limit_invalid:%d" % team)
		var start := _vector2(player.get("start", []), Vector2(-1, -1))
		if start.x < 0.0 or start.y < 0.0 or start.x >= map["size"].x or start.y >= map["size"].y:
			errors.append("player_start_out_of_bounds:%d" % team)
		player["start"] = start
		_normalize_player_technology_settings(player, team, errors)
		_normalize_player_source_ai(player, team, map["size"], errors)
	if teams.size() < 2:
		errors.append("at_least_two_players_required")
	if human_teams.size() > 1:
		errors.append("multiple_local_humans_unsupported")

	var normalized_alliances: Array = []
	for alliance_value in result.get("alliances", []):
		if not alliance_value is Array or alliance_value.size() < 2:
			errors.append("alliance_pair_invalid")
			continue
		var first_team := int(alliance_value[0])
		var second_team := int(alliance_value[1])
		if first_team == second_team or not teams.has(first_team) or not teams.has(second_team):
			errors.append("alliance_player_invalid:%d:%d" % [first_team, second_team])
			continue
		normalized_alliances.append([first_team, second_team])
	result["alliances"] = normalized_alliances

	var normalized_diplomacy: Array = []
	var diplomacy_pairs: Dictionary = {}
	for relation_value in result.get("diplomacy", []):
		if not relation_value is Dictionary:
			errors.append("diplomacy_entry_invalid")
			continue
		var relation_entry: Dictionary = relation_value.duplicate(true)
		var source_team := int(relation_entry.get("source_team", 0))
		var target_team := int(relation_entry.get("target_team", 0))
		var relation := String(relation_entry.get("relation", ""))
		var pair_key := "%d:%d" % [source_team, target_team]
		if source_team == target_team or not teams.has(source_team) or not teams.has(target_team):
			errors.append("diplomacy_player_invalid:%s" % pair_key)
			continue
		if relation not in ["ally", "neutral", "enemy"]:
			errors.append("diplomacy_relation_invalid:%s" % pair_key)
			continue
		if diplomacy_pairs.has(pair_key):
			errors.append("diplomacy_pair_duplicate:%s" % pair_key)
			continue
		diplomacy_pairs[pair_key] = true
		relation_entry["source_team"] = source_team
		relation_entry["target_team"] = target_team
		relation_entry["relation"] = relation
		normalized_diplomacy.append(relation_entry)
	result["diplomacy"] = normalized_diplomacy

	for entity_value in result.get("entities", []):
		var entity: Dictionary = entity_value
		var category := String(entity.get("category", ""))
		if category not in ["unit", "building", "resource", "objective"]:
			errors.append("entity_category_invalid:%s" % category)
		var position := _vector2(entity.get("position", []), Vector2(-1, -1))
		if position.x < 0.0 or position.y < 0.0 or position.x >= map["size"].x or position.y >= map["size"].y:
			errors.append("entity_out_of_bounds:%s" % String(entity.get("kind", "unknown")))
		entity["position"] = position

	var marker_ids: Dictionary = {}
	for marker_value in result.get("presentation_markers", []):
		if not marker_value is Dictionary:
			errors.append("presentation_marker_invalid")
			continue
		var marker: Dictionary = marker_value
		var marker_id := int(marker.get("id", 0))
		if marker_ids.has(marker_id):
			errors.append("presentation_marker_id_duplicate:%d" % marker_id)
		marker_ids[marker_id] = true
		var marker_position := _vector2(marker.get("position", []), Vector2(-1, -1))
		if marker_position.x < 0.0 or marker_position.y < 0.0 or marker_position.x >= map["size"].x or marker_position.y >= map["size"].y:
			errors.append("presentation_marker_out_of_bounds:%d" % marker_id)
		marker["position"] = marker_position
		if int(marker.get("graphic_id", -1)) < 0 or String(marker.get("asset_name", "")).is_empty():
			errors.append("presentation_marker_asset_invalid:%d" % marker_id)

	var environment_ids: Dictionary = {}
	for item_value in result.get("presentation_environment", []):
		if not item_value is Dictionary:
			errors.append("presentation_environment_invalid")
			continue
		var item: Dictionary = item_value
		var item_id := int(item.get("id", 0))
		if environment_ids.has(item_id):
			errors.append("presentation_environment_id_duplicate:%d" % item_id)
		environment_ids[item_id] = true
		var item_position := _vector2(item.get("position", []), Vector2(-1, -1))
		if item_position.x < 0.0 or item_position.y < 0.0 or item_position.x >= map["size"].x or item_position.y >= map["size"].y:
			errors.append("presentation_environment_out_of_bounds:%d" % item_id)
		item["position"] = item_position
		if String(item.get("kind", "")) not in ["terrain_feature", "presentation_scenery", "ambient_actor"]:
			errors.append("presentation_environment_kind_invalid:%d" % item_id)
		if int(item.get("graphic_id", -1)) < 0 or String(item.get("asset_name", "")).is_empty():
			errors.append("presentation_environment_asset_invalid:%d" % item_id)

	var obstruction_ids: Dictionary = {}
	for obstruction_value in result.get("static_obstructions", []):
		if not obstruction_value is Dictionary:
			errors.append("static_obstruction_invalid")
			continue
		var obstruction: Dictionary = obstruction_value
		var obstruction_id := int(obstruction.get("id", 0))
		if obstruction_ids.has(obstruction_id):
			errors.append("static_obstruction_id_duplicate:%d" % obstruction_id)
		obstruction_ids[obstruction_id] = true
		var obstruction_position := _vector2(obstruction.get("position", []), Vector2(-1, -1))
		if obstruction_position.x < 0.0 or obstruction_position.y < 0.0 or obstruction_position.x >= map["size"].x or obstruction_position.y >= map["size"].y:
			errors.append("static_obstruction_out_of_bounds:%d" % obstruction_id)
		obstruction["position"] = obstruction_position
		var occupied_cells: Array = []
		for cell_value in obstruction.get("occupied_cells", []):
			var cell := Vector2i(int(cell_value[0]), int(cell_value[1])) if cell_value is Array and cell_value.size() >= 2 else Vector2i(-1, -1)
			if cell.x < 0 or cell.y < 0 or cell.x >= map["size"].x or cell.y >= map["size"].y:
				errors.append("static_obstruction_cell_out_of_bounds:%d" % obstruction_id)
			else:
				occupied_cells.append(cell)
		if occupied_cells.is_empty():
			errors.append("static_obstruction_cells_required:%d" % obstruction_id)
		obstruction["occupied_cells"] = occupied_cells
		if int(obstruction.get("graphic_id", -1)) < 0 or String(obstruction.get("asset_name", "")).is_empty():
			errors.append("static_obstruction_asset_invalid:%d" % obstruction_id)

	var scenario_result := ScenarioDefinition.normalize(result.get("scenario_definition", {}), teams, map["size"])
	result["scenario_definition"] = scenario_result["value"]
	errors.append_array(scenario_result["errors"])

	result["local_team"] = human_teams[0] if not human_teams.is_empty() else int(result.get("local_team", 1))
	result["valid"] = errors.is_empty()
	result["errors"] = errors
	return result


static func _vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _normalize_player_technology_settings(player: Dictionary, team: int, errors: Array[String]) -> void:
	var mode := String(player.get("starting_technology_mode", "age_start"))
	if mode not in ["age_start", "post_iron"]:
		errors.append("player_starting_technology_mode_invalid:%d" % team)
		mode = "age_start"
	player["starting_technology_mode"] = mode
	if mode == "post_iron" and int(player.get("starting_age_technology_id", -1)) != 103:
		errors.append("player_post_iron_requires_iron_age:%d" % team)

	var normalized_nodes: Array = []
	for node_value in player.get("disabled_technology_nodes", []):
		if not node_value is Dictionary:
			errors.append("player_disabled_technology_node_invalid:%d" % team)
			continue
		var node: Dictionary = node_value.duplicate(true)
		var slot := int(node.get("slot", -1))
		var kind := String(node.get("kind", ""))
		if slot < 0 or slot > 15:
			errors.append("player_disabled_technology_node_slot_invalid:%d" % team)
		if String(node.get("node", "")).is_empty():
			errors.append("player_disabled_technology_node_name_missing:%d" % team)
		if kind == "building":
			if int(node.get("source_object_id", -1)) < 0:
				errors.append("player_disabled_technology_building_invalid:%d" % team)
		elif kind == "age":
			if int(node.get("technology_id", -1)) not in [101, 102, 103]:
				errors.append("player_disabled_technology_age_invalid:%d" % team)
		else:
			errors.append("player_disabled_technology_node_kind_invalid:%d" % team)
		normalized_nodes.append(node)
	player["disabled_technology_nodes"] = normalized_nodes


static func _normalize_player_source_ai(player: Dictionary, team: int, map_size: Vector2i, errors: Array[String]) -> void:
	var settings: Dictionary = player.get("ai", {})
	var source_profile := String(settings.get("profile", "")) == "source_campaign_v1"
	if not player.has("source_ai"):
		if source_profile and bool(settings.get("enabled", true)):
			errors.append("source_ai_contract_required:%d" % team)
		return
	var contract_value: Variant = player.get("source_ai")
	if not contract_value is Dictionary:
		errors.append("source_ai_contract_invalid:%d" % team)
		return
	var contract: Dictionary = contract_value
	if int(contract.get("schema_version", 0)) != 1:
		errors.append("source_ai_schema_unsupported:%d" % team)
	if String(contract.get("status", "")) not in ["normalized", "partial", "integrated"]:
		errors.append("source_ai_status_invalid:%d" % team)

	for number_value in contract.get("strategic_numbers", []):
		if not number_value is Dictionary:
			errors.append("source_ai_strategic_number_invalid:%d" % team)
			continue
		var number: Dictionary = number_value
		var source_id := int(number.get("source_id", -1))
		if source_id < 0:
			errors.append("source_ai_strategic_number_id_invalid:%d" % team)
		if String(number.get("capability", "")).is_empty() or String(number.get("runtime_semantics", "")) not in ["implemented", "source_documented_noop", "pending"]:
			errors.append("source_ai_strategic_number_capability_invalid:%d" % team)

	for order_value in contract.get("build_order", []):
		if not order_value is Dictionary:
			errors.append("source_ai_build_order_invalid:%d" % team)
			continue
		var order: Dictionary = order_value
		var order_type := String(order.get("type", ""))
		if order_type not in ["unit", "technology", "building"]:
			errors.append("source_ai_build_order_type_invalid:%d" % team)
		var producer_source_id := int(order.get("producer_source_unit_id", -1))
		if int(order.get("source_id", -1)) < 0 or (order_type != "building" and producer_source_id < 0) or int(order.get("target_count", 0)) <= 0:
			errors.append("source_ai_build_order_entry_invalid:%d" % team)
		if order_type in ["unit", "building"] and String(order.get("runtime_alias", "")).is_empty():
			errors.append("source_ai_build_order_alias_missing:%d" % team)

	for marker_value in contract.get("target_markers", []):
		if not marker_value is Dictionary:
			errors.append("source_ai_target_marker_invalid:%d" % team)
			continue
		var marker: Dictionary = marker_value
		var position := _vector2(marker.get("position", []), Vector2(-1, -1))
		if position.x < 0.0 or position.y < 0.0 or position.x >= map_size.x or position.y >= map_size.y:
			errors.append("source_ai_target_marker_out_of_bounds:%d" % team)
		marker["position"] = position
	player["source_ai"] = contract
