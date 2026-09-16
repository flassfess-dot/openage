class_name RoRSimulationSnapshot
extends RefCounted

const FORMAT_VERSION: int = 1


static func canonical(world, tick: int, controller = null) -> Dictionary:
	var snapshot := {
		"format_version": FORMAT_VERSION,
		"tick": tick,
		"world": _world_state(world),
	}
	if controller != null:
		snapshot["controller"] = _controller_state(controller)
	return snapshot


static func presentation(world, tick: int, observer_team: int = 0, options: Dictionary = {}) -> Dictionary:
	var fog = world.get_fog_of_war()
	var compact_entities := bool(options.get("compact_entities", false))
	var include_navigation := bool(options.get("include_navigation", true))
	var include_build_sites := bool(options.get("include_build_sites", true))
	var include_fog_cells := bool(options.get("include_fog_cells", true))
	var include_projectiles := bool(options.get("include_projectiles", true))
	var include_scenario := bool(options.get("include_scenario", true))
	var include_worker_command_options := bool(options.get("include_worker_command_options", true))
	var requested_production_only := bool(options.get("requested_production_only", false))
	var production_requests: Array = options.get("production_requests", [])
	var planning_technology_ids: Array = options.get("planning_technology_ids", [])
	var requested_build_site_kinds: Array = options.get("requested_build_site_kinds", [])
	var maximum_build_sites_per_kind := maxi(1, int(options.get("maximum_build_sites_per_kind", 4)))
	var build_site_search_radius := maxi(1, int(options.get("build_site_search_radius", 12)))
	var preferred_build_sites: Dictionary = options.get("preferred_build_sites", {})
	var strict_preferred_build_site_kinds: Array = options.get("strict_preferred_build_site_kinds", [])
	var requested_build_options: Array = []
	var available_requested_build_site_kinds: Array = []
	if observer_team > 0 and not requested_build_site_kinds.is_empty():
		for option_value in world.get_build_options(observer_team):
			var option: Dictionary = option_value
			if String(option.get("kind", "")) in requested_build_site_kinds:
				requested_build_options.append(option)
				if bool(option.get("accepted", false)):
					available_requested_build_site_kinds.append(String(option.get("kind", "")))
	var units: Array = []
	for unit in world.get_units():
		if observer_team <= 0 or world.is_entity_visible_to(observer_team, unit):
			var presentation_unit := _presentation_entity(unit, observer_team, compact_entities)
			if observer_team > 0 and int(unit.get("team", 0)) == observer_team and world.entity_is_worker(unit):
				if not requested_build_options.is_empty():
					presentation_unit["command_options"] = {"build": requested_build_options}
				elif include_worker_command_options:
					presentation_unit["command_options"] = {"build": world.get_build_options(observer_team)}
			units.append(presentation_unit)
	var resources: Array = []
	for resource in world.get_resources():
		if observer_team <= 0 or world.is_entity_visible_to(observer_team, resource, true):
			resources.append(_presentation_entity(resource, observer_team, compact_entities))
	var objectives: Array = []
	for objective in world.victory_objectives:
		if not bool(objective.get("active", true)):
			continue
		if observer_team <= 0 or world.is_entity_visible_to(observer_team, objective, true):
			objectives.append(_presentation_entity(objective, observer_team, compact_entities))
	var buildings: Array = []
	for building in world.get_buildings():
		if observer_team <= 0 or world.is_entity_visible_to(observer_team, building, true):
			var presentation_building := _presentation_entity(building, observer_team, compact_entities)
			presentation_building["target_domains"] = world.combat_target_domains(building)
			if world.trade_system.is_trade_dock(building):
				presentation_building["trade"] = world.trade_system.presentation_for_dock(building)
			if observer_team > 0 and int(building.get("team", 0)) == observer_team:
				presentation_building["builder_count"] = building.get("builders", {}).size()
				if requested_production_only:
					presentation_building["command_options"] = _requested_production_options(world, building, observer_team, production_requests)
				else:
					presentation_building["command_options"] = {
						"train": world.get_unit_production_options(int(building.get("id", -1)), observer_team),
						"research": world.get_research_options(int(building.get("id", -1)), observer_team),
					}
				if not planning_technology_ids.is_empty():
					_append_planning_research_options(world, presentation_building, building, observer_team, planning_technology_ids)
			buildings.append(presentation_building)
	var projectiles: Array = []
	if include_projectiles:
		for projectile in world.get_projectiles():
			if observer_team <= 0 or world.is_entity_visible_to(observer_team, projectile):
				projectiles.append(_presentation_entity(projectile, observer_team, compact_entities))
	var build_sites: Dictionary = {}
	if observer_team > 0 and not requested_build_site_kinds.is_empty():
		build_sites = world.get_local_build_sites(
			observer_team,
			available_requested_build_site_kinds,
			maximum_build_sites_per_kind,
			build_site_search_radius,
			preferred_build_sites,
			strict_preferred_build_site_kinds
		)
	elif observer_team > 0 and include_build_sites:
		build_sites = world.get_mixed_domain_build_sites(observer_team)
	return {
		"format_version": FORMAT_VERSION,
		"tick": tick,
		"observer_team": observer_team,
		"map_size": world.map_size,
		"units": _sort_entity_copies(units),
		"resources": _sort_entity_copies(resources),
		"objectives": _sort_entity_copies(objectives),
		"buildings": _sort_entity_copies(buildings),
		"projectiles": _sort_entity_copies(projectiles),
		"ai_distress_signals": world.get_attack_distress_signals(observer_team) if observer_team > 0 else [],
		"navigation": _presentation_navigation(world, fog, observer_team) if include_navigation else {},
		"build_sites": build_sites,
		"fog_revision": int(fog.revision),
		"fog": _presentation_fog(fog, observer_team) if include_fog_cells else {"observer_team": observer_team, "cells": []},
		"player_state": _presentation_player_state(world, observer_team),
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"match_result": world.get_victory_result(),
		"scenario": world.scenario_system.presentation_state(observer_team) if include_scenario else {},
	}


static func _world_state(world) -> Dictionary:
	var fog = world.get_fog_of_war()
	var economy: Dictionary = world.get_economy_snapshot()
	return {
		"map_size": world.map_size,
		"simulation_seed": int(world.simulation_seed),
		"rng_state": int(world.simulation_rng.state),
		"next_entity_id": int(world.entity_id_sequence.peek()),
		"next_production_order_id": int(world.next_production_order_id),
		"units": _sorted_entities(world.get_units()),
		"embarked_units": _sorted_entities(world.get_embarked_units()),
		"resources": _sorted_entities(world.get_resources()),
		"buildings": _sorted_entities(world.get_buildings()),
		"projectiles": _sorted_entities(world.get_projectiles()),
		"resolved_projectiles": _sorted_entities(world.get_resolved_projectiles()),
		"ai_distress": world.ai_distress_system.canonical_state(),
		"static_obstructions": _sorted_entities(world.get_static_obstructions()),
		"civilizations": world.civilization_by_team.duplicate(true),
		"players": world.player_registry.canonical_state(),
		"population": economy["population"],
		"population_reserved": economy["population_reserved"],
		"population_cap": economy["population_cap"],
		"population_limit": economy["population_limit"],
		"population_housing": economy["population_housing"],
		"population_housing_enabled": economy["population_housing_enabled"],
		"resource_stockpiles": economy["resource_stockpiles"],
		"trade": world.trade_system.canonical_state(),
		"resource_approach_slots": world.resource_approach_slots.duplicate(true),
		"building_approach_slots": world.building_approach_slots.duplicate(true),
		"destination_reservations": world.destination_reservations.reservations.duplicate(true),
		"terrain_vertex_levels": world.terrain_elevation.vertex_levels.duplicate(true),
		"fog": _fog_state(fog),
		"technology_team_states": world.technology_system.team_states.duplicate(true),
		"victory": _victory_state(world),
		"food": int(world.get_food()),
		"wood": int(world.get_wood()),
		"kills": int(world.kills),
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"last_failures": {
			"build": String(world.last_build_failure),
			"production": String(world.last_production_failure),
			"research": String(world.last_research_failure),
		},
	}


static func _controller_state(controller) -> Dictionary:
	return {
		"tick": int(controller.tick_index),
		"next_command_sequence": int(controller.next_command_sequence),
		"next_formation_group_id": int(controller.next_formation_group_id),
		"pending_commands": _pending_commands(controller.command_queue),
		"formation_groups": _formation_groups(controller.formation_groups),
	}


static func _sorted_entities(source: Array) -> Array:
	var result: Array = []
	for entity in source:
		var canonical_entity: Dictionary = entity.duplicate(true)
		# Selection belongs to player-control/presentation state and must not
		# change deterministic simulation hashes.
		canonical_entity.erase("selected")
		result.append(canonical_entity)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _presentation_entity(entity: Dictionary, observer_team: int = 0, compact: bool = false) -> Dictionary:
	if compact:
		return _compact_ai_entity(entity)
	var result: Dictionary = entity.duplicate(true)
	result.erase("selected")
	var cargo: Dictionary = result.get("components", {}).get("cargo", {})
	if bool(cargo.get("enabled", false)):
		cargo["count"] = cargo.get("passenger_ids", []).size()
		if observer_team > 0 and int(entity.get("team", 0)) != observer_team:
			cargo.erase("passenger_ids")
			cargo.erase("count")
	var trade: Dictionary = result.get("components", {}).get("trade", {})
	if bool(trade.get("enabled", false)) and observer_team > 0 and int(entity.get("team", 0)) != observer_team:
		for private_field in ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]:
			trade.erase(private_field)
	return result


static func _compact_ai_entity(entity: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in [
		"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
		"pos", "hp", "state", "task", "target_id", "target_building_id", "diagnostic_reason", "movement_domain", "combat_enabled", "retaliation_target_id", "amount",
		"resource_type_id", "harvestable", "footprint_radius", "rally_point", "attack_range",
	]:
		if entity.has(key):
			result[key] = entity[key]
	if entity.has("unit_lineage"):
		result["unit_lineage"] = entity.get("unit_lineage", []).duplicate()
	if entity.has("behavior_tags"):
		result["behavior_tags"] = entity.get("behavior_tags", []).duplicate()
	if entity.has("allowed_gatherer_domains"):
		result["allowed_gatherer_domains"] = entity.get("allowed_gatherer_domains", []).duplicate()
	var worker: Dictionary = entity.get("components", {}).get("worker", {})
	result["components"] = {"worker": {"enabled": bool(worker.get("enabled", false))}}
	if entity.has("production_queue"):
		var queue: Array = []
		for order_value in entity.get("production_queue", []):
			var order: Dictionary = order_value
			queue.append({
				"order_type": String(order.get("order_type", "unit")),
				"kind": String(order.get("kind", "")),
				"technology_id": int(order.get("technology_id", -1)),
			})
		result["production_queue"] = queue
	return result


static func _requested_production_options(world, building: Dictionary, team: int, requests: Array) -> Dictionary:
	var result := {"train": [], "research": []}
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	var building_id := int(building.get("id", -1))
	var seen_units: Dictionary = {}
	var seen_technologies: Dictionary = {}
	for request_value in requests:
		var request: Dictionary = request_value
		if not lineage.has(int(request.get("producer_source_unit_id", -1))):
			continue
		if String(request.get("type", "")) == "unit":
			var kind := String(request.get("runtime_alias", ""))
			if not kind.is_empty() and not seen_units.has(kind):
				result["train"].append(world.get_unit_production_availability(building_id, team, kind))
				seen_units[kind] = true
		elif String(request.get("type", "")) == "technology":
			var technology_id := int(request.get("source_id", -1))
			if technology_id >= 0 and not seen_technologies.has(technology_id):
				result["research"].append(world.get_research_availability(building_id, team, technology_id))
				seen_technologies[technology_id] = true
	return result


static func _append_planning_research_options(world, presentation_building: Dictionary, source_building: Dictionary, team: int, technology_ids: Array) -> void:
	var command_options: Dictionary = presentation_building.get("command_options", {})
	var research_options: Array = command_options.get("research", [])
	var known: Dictionary = {}
	for option_value in research_options:
		known[int(option_value.get("technology_id", -1))] = true
	for technology_id_value in technology_ids:
		var technology_id := int(technology_id_value)
		if technology_id <= 0 or known.has(technology_id):
			continue
		var option: Dictionary = world.get_research_availability(int(source_building.get("id", -1)), team, technology_id)
		if String(option.get("reason", "")) in ["wrong_research_location", "invalid_research_building", "technology_disabled", "already_researched", "already_researching"]:
			continue
		research_options.append(option)
		known[technology_id] = true
	command_options["research"] = research_options
	presentation_building["command_options"] = command_options


static func _sort_entity_copies(source: Array) -> Array:
	var result: Array = source.duplicate()
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _presentation_fog(fog, observer_team: int) -> Dictionary:
	var cells: PackedByteArray = fog.snapshot(observer_team) if observer_team > 0 else PackedByteArray()
	return {
		"observer_team": observer_team,
		"cells": cells,
	}


static func _presentation_navigation(world, fog, observer_team: int) -> Dictionary:
	var result := {
		"land": [],
		"water": [],
		"frontier": {"land": [], "water": []},
	}
	if observer_team <= 0:
		return result
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			var cell := Vector2i(x, y)
			if fog.state_at_cell(observer_team, cell) == 0:
				continue
			var point := Vector2(x + 0.5, y + 0.5)
			var borders_unknown := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + offset
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < world.map_size.x and neighbor.y < world.map_size.y and fog.state_at_cell(observer_team, neighbor) == 0:
					borders_unknown = true
					break
			if world.navigation_grid.surface_accessible(cell, "land"):
				result["land"].append(point)
				if borders_unknown:
					result["frontier"]["land"].append(point)
			if world.navigation_grid.surface_accessible(cell, "water"):
				result["water"].append(point)
				if borders_unknown:
					result["frontier"]["water"].append(point)
	return result


static func _presentation_player_state(world, observer_team: int) -> Dictionary:
	if observer_team <= 0:
		return {}
	return {
		"team": observer_team,
		"allies": world.get_allied_teams(observer_team),
		"relations": world.get_team_relations(observer_team),
		"status": world.player_registry.status(observer_team),
		"players": world.player_registry.public_states(),
		"food": int(world.get_resource_amount(observer_team, 0)),
		"wood": int(world.get_resource_amount(observer_team, 1)),
		"stone": int(world.get_resource_amount(observer_team, 2)),
		"gold": int(world.get_resource_amount(observer_team, 3)),
		"population": int(world.get_population(observer_team)),
		"population_reserved": int(world.get_reserved_population(observer_team)),
		"population_cap": int(world.get_population_cap(observer_team)),
		"population_limit": int(world.economy_system.get_population_limit(observer_team)),
		"population_housing": int(world.economy_system.get_population_housing(observer_team)),
		"age": int(world.get_current_age(observer_team)),
		"researched_technologies": world.get_researched_technologies(observer_team),
		"kills": int(world.get_kills()),
	}


static func _pending_commands(source: Array) -> Array:
	var ordered: Array = source.duplicate()
	ordered.sort_custom(func(left, right):
		if int(left.tick) != int(right.tick):
			return int(left.tick) < int(right.tick)
		return int(left.sequence_id) < int(right.sequence_id)
	)
	var result: Array = []
	for command in ordered:
		result.append({
			"tick": int(command.tick),
			"issuer_id": int(command.issuer_id),
			"sequence_id": int(command.sequence_id),
			"type": String(command.command_type()),
			"unit_ids": command.unit_ids.duplicate(),
			"params": command.params.duplicate(true),
		})
	return result


static func _formation_groups(source: Dictionary) -> Array:
	var ids: Array = source.keys()
	ids.sort()
	var result: Array = []
	for group_id_value in ids:
		var group = source[group_id_value]
		result.append({
			"group_id": int(group.group_id),
			"member_ids": group.member_ids.duplicate(),
			"anchor": group.anchor,
			"forward": group.forward,
			"formation_type": String(group.formation_type),
			"preferred_formation_type": String(group.preferred_formation_type),
			"spacing": float(group.spacing),
			"slots": group.slots.duplicate(true),
			"assignments": group.assignments.duplicate(true),
			"state": String(group.state),
			"state_ticks": int(group.state_ticks),
			"lifecycle_revision": int(group.lifecycle_revision),
			"last_transition_reason": String(group.last_transition_reason),
			"slot_constraint_mode": String(group.slot_constraint_mode),
			"maximum_slot_error": float(group.maximum_slot_error),
			"policy": group.policy.duplicate(true),
			"engagement_forward": group.engagement_forward,
			"route": group.route.duplicate(),
			"corridor_modes": group.corridor_modes.duplicate(),
			"required_corridor_width": int(group.required_corridor_width),
			"has_compression": bool(group.has_compression),
		})
	return result


static func _fog_state(fog) -> Dictionary:
	var players: Array = fog.states_by_player.keys()
	players.sort()
	var states: Dictionary = {}
	for player in players:
		var cells: Array = []
		for value in fog.states_by_player[player]:
			cells.append(int(value))
		states[int(player)] = cells
	return {
		"revision": int(fog.revision),
		"states_by_player": states,
		"allies_by_player": fog.allies_by_player.duplicate(true),
	}


static func _victory_state(world) -> Dictionary:
	return {
		"objectives": world.victory_objectives.duplicate(true),
		"scores": world.score_by_team.duplicate(true),
		"rules": world.victory_system.rules.duplicate(true),
		"elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"hold_seconds": world.victory_system.hold_seconds.duplicate(true),
		"result": world.victory_system.result.duplicate(true),
		"scenario": world.scenario_system.canonical_state(),
	}
