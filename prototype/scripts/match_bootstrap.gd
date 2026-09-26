class_name RoRMatchBootstrap
extends RefCounted

const RESOURCE_IDS := {"food": 0, "wood": 1, "stone": 2, "gold": 3}


static func apply(world, definition: Dictionary, map_data: Dictionary) -> Dictionary:
	world.set_simulation_seed(int(map_data.get("seed", 1)))
	world.full_tech_tree_enabled = bool(definition.get("full_tech_tree", false))
	world.configure_players(definition.get("players", []))
	world.begin_bulk_load()
	world.reset_game(false, true)
	world.configure_map_data(map_data)
	var obstructions: Array = definition.get("static_obstructions", []).duplicate(true)
	var cliff_cells: Array = map_data.get("cliff_cells", [])
	for index in range(cliff_cells.size()):
		var cell: Vector2i = cliff_cells[index]
		obstructions.append({"id": -100000 - index, "kind": "cliff", "position": Vector2(cell) + Vector2(0.5, 0.5), "occupied_cells": [cell]})
	world.configure_static_obstructions(obstructions)

	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		var team := int(player.get("team", 0))
		for resource_name in player.get("starting_resources", {}):
			if RESOURCE_IDS.has(resource_name):
				world.set_resource_amount(team, int(RESOURCE_IDS[resource_name]), int(player["starting_resources"][resource_name]))
		if player.has("population_limit"):
			world.set_population_cap(team, int(player["population_limit"]))
		if player.has("population_housing"):
			world.set_population_housing(team, int(player["population_housing"]))
		world.apply_scenario_technology_nodes(team, player.get("disabled_technology_nodes", []))

	for alliance_value in definition.get("alliances", []):
		var alliance: Array = alliance_value
		if alliance.size() >= 2:
			world.set_alliance(int(alliance[0]), int(alliance[1]), true)
	for relation_value in definition.get("diplomacy", []):
		var relation: Dictionary = relation_value
		world.set_diplomacy_relation(
			int(relation.get("source_team", 0)),
			int(relation.get("target_team", 0)),
			String(relation.get("relation", "enemy"))
		)
	world.configure_scenario_definition(definition.get("scenario_definition", {}))
	world.configure_victory_rules(definition.get("victory_rules", [{"type": "conquest"}]), bool(definition.get("allied_victory_enabled", true)))

	var selected_ids: Array[int] = []
	var entities: Array = definition.get("entities", []).duplicate(true)
	for generated_resource_value in map_data.get("resources", []):
		var generated_resource: Dictionary = generated_resource_value.duplicate(true)
		generated_resource["placement_validated"] = true
		entities.append(generated_resource)
	for entity_value in entities:
		var entity: Dictionary = entity_value
		var category := String(entity.get("category", ""))
		var position: Vector2 = entity.get("position", Vector2.ZERO)
		match category:
			"unit":
				var unit: Dictionary = world.add_unit(int(entity.get("team", 0)), String(entity.get("kind", "villager")), position, false)
				_apply_source_identity(world, unit, entity)
				if bool(entity.get("selected", false)):
					selected_ids.append(int(unit["id"]))
			"building":
				var building: Dictionary = world.create_building(int(entity.get("team", 0)), String(entity.get("kind", "town_center")), position, bool(entity.get("completed", true)))
				_apply_source_identity(world, building, entity)
				if bool(entity.get("selected", false)):
					selected_ids.append(int(building["id"]))
			"resource":
				var resource: Dictionary
				if entity.has("scenario_object_id") or bool(entity.get("placement_validated", false)):
					resource = world.add_scenario_resource(String(entity.get("kind", "tree")), position, int(entity.get("amount", 0)))
				else:
					resource = world.add_resource(String(entity.get("kind", "tree")), position, int(entity.get("amount", 0)))
				_apply_source_identity(world, resource, entity)
			"objective":
				var objective: Dictionary = world.add_victory_object(String(entity.get("kind", "artifact")), position, int(entity.get("team", 0)), bool(entity.get("completed", true)))
				_apply_source_identity(world, objective, entity)
	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		if player.has("starting_age_technology_id"):
			world.set_starting_age(
				int(player.get("team", 0)),
				int(player["starting_age_technology_id"]),
				String(player.get("starting_technology_mode", "age_start")) == "post_iron"
			)
	world.end_bulk_load()
	var naval_start_zones: Array = map_data.get("naval_start_zones", [])
	var active_team_count: int = definition.get("players", []).filter(func(player): return int(player.get("team", 0)) > 0).size()
	var naval_start_guarantees_met: bool = naval_start_zones.size() == active_team_count and naval_start_zones.all(func(zone):
		return world.map_supports_foundation("dock", Vector2(zone.get("dock_position", Vector2.ZERO)))
	)

	return {
		"local_team": int(definition.get("local_team", 1)),
		"selected_ids": selected_ids,
		"message": String(definition.get("start_message", "")),
		"naval_start_zones": naval_start_zones.duplicate(true),
		"naval_start_guarantees_met": naval_start_guarantees_met,
	}


static func _apply_source_identity(world, runtime_entity: Dictionary, source_entity: Dictionary) -> void:
	if source_entity.has("source_unit_id"):
		var source_unit_id := int(source_entity["source_unit_id"])
		runtime_entity["scenario_source_unit_id"] = source_unit_id
		if String(source_entity.get("category", "")) in ["unit", "building"] and source_unit_id != int(runtime_entity.get("source_unit_id", -1)):
			world.apply_unit_upgrade_to_entity(runtime_entity, source_unit_id)
		runtime_entity["source_unit_id"] = source_unit_id
		runtime_entity.get("components", {}).get("identity", {})["source_unit_id"] = source_unit_id
	for key in ["scenario_object_id", "source_state", "source_angle", "source_elevation", "source_frame", "source_graphic_id", "source_graphic_asset_name", "source_requested_graphic_asset_name", "source_asset_fallback_reason", "source_depleted_graphic_id", "source_depleted_asset_name", "static_field_node", "graphic_id", "asset_name"]:
		if source_entity.has(key):
			runtime_entity[key] = source_entity[key]
