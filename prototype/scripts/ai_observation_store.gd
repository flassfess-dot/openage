class_name RoRAiObservationStore
extends RefCounted

const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")

# AI consumes legal simulation knowledge, not render state. Keep that projection
# on its own lifecycle and retain compact entity records between decisions. The
# records are updated in place, which removes most deep-copy churn while every
# observer still receives an isolated cache and fog-filtered entity set.

const AI_SCALAR_FIELDS: Array[String] = [
	"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
	"pos", "hp", "max_hp", "state", "task", "target_id", "target_building_id",
	"diagnostic_reason", "movement_domain", "combat_enabled", "retaliation_target_id",
	"amount", "resource_type_id", "harvestable", "footprint_radius", "rally_point",
	"attack_range", "projectile_id", "blast_range", "reachable_builder_ids",
]
const AI_ARRAY_FIELDS: Array[String] = [
	"unit_lineage", "behavior_tags", "allowed_gatherer_domains",
]
const BUILDING_MEMORY_SCALAR_FIELDS: Array[String] = [
	"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
	"health_unknown", "location_only", "pos", "previous_pos", "elevation",
	"source_elevation", "visual_height", "hp", "max_hp", "amount", "max_amount",
	"active", "logical_only", "state", "resource_state", "depletion_stage",
	"visible_when_depleted", "harvestable", "resource_type_id", "building_type",
	"movement_domain", "footprint_radius", "selection_radius", "selection_height",
	"anim", "anim_state", "facing", "presentation_facing", "death_phase",
	"death_elapsed", "construction_stage", "display_graphic_id", "source_frame",
	"source_graphic_id", "source_graphic_asset_name", "source_requested_graphic_asset_name",
	"source_asset_fallback_reason", "source_depleted_graphic_id",
	"source_depleted_asset_name", "combat_enabled", "task", "target_id",
	"target_building_id", "formation_forward", "carried_amount",
]

var observer_caches: Dictionary = {}


func clear() -> void:
	observer_caches.clear()


func observe(world, tick: int, observer_team: int, options: Dictionary = {}) -> Dictionary:
	if observer_team <= 0 or not _supports_retained_projection(options):
		return SimulationSnapshot.presentation(world, tick, observer_team, options)
	var probe: Variant = options.get("performance_probe")
	var prefix := String(options.get("performance_prefix", "presentation.ai.snapshot"))
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var fog = world.get_fog_of_war()
	fog.ensure_player(observer_team)
	var observer_states: PackedByteArray = fog.states_by_player[observer_team]
	var fog_map_size: Vector2i = fog.map_size
	var cache: Dictionary = _cache_for(observer_team)

	var requested_build_site_kinds: Array = options.get("requested_build_site_kinds", [])
	var requested_build_options: Array = []
	var available_requested_build_site_kinds: Array = []
	if not requested_build_site_kinds.is_empty():
		var build_options: Array = world.get_build_options_for_kinds(observer_team, requested_build_site_kinds) if world.has_method("get_build_options_for_kinds") else world.get_build_options(observer_team)
		for option_value in build_options:
			var option: Dictionary = option_value
			if String(option.get("kind", "")) not in requested_build_site_kinds:
				continue
			requested_build_options.append(option)
			if bool(option.get("accepted", false)):
				available_requested_build_site_kinds.append(String(option.get("kind", "")))
	_observe_stage(probe, prefix + ".setup", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var units: Array = []
	var seen_unit_ids: Dictionary = {}
	var restrict_command_options := options.has("command_option_entity_ids")
	var command_option_entity_lookup := _id_lookup(options.get("command_option_entity_ids", []))
	var include_worker_command_options := bool(options.get("include_worker_command_options", false))
	var worker_build_options: Array = []
	var worker_build_options_ready := false
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if not _entity_visible(unit, observer_team, observer_states, fog_map_size):
			continue
		var unit_id := int(unit.get("id", -1))
		var projected := _project_entity(cache["units"], unit, observer_team)
		if int(unit.get("team", 0)) != observer_team and world.are_teams_allied(observer_team, int(unit.get("team", 0))):
			var allied_cargo: Dictionary = projected.get("components", {}).get("cargo", {})
			if bool(allied_cargo.get("enabled", false)):
				allied_cargo["count"] = unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()
		if int(unit.get("team", 0)) == observer_team and world.entity_is_worker(unit) and (not restrict_command_options or command_option_entity_lookup.has(unit_id)):
			if not requested_build_options.is_empty():
				projected["command_options"] = {"build": requested_build_options}
			elif include_worker_command_options:
				if not worker_build_options_ready:
					worker_build_options = world.get_build_options(observer_team)
					worker_build_options_ready = true
				projected["command_options"] = {"build": worker_build_options}
		units.append(projected)
		seen_unit_ids[unit_id] = true
	_prune_entity_cache(cache["units"], seen_unit_ids)
	_sort_by_entity_id_if_needed(units)
	_observe_stage(probe, prefix + ".units", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	# Resource knowledge already has an incremental fog-memory cache in the
	# world. Reuse its immutable AI projection rather than introducing another
	# owner for the same data.
	var resources: Array = world.get_known_ai_resources(observer_team) if world.has_method("get_known_ai_resources") else _project_resources(world.get_known_resources(observer_team), observer_team)
	_observe_stage(probe, prefix + ".resources", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var objectives: Array = []
	var seen_objective_ids: Dictionary = {}
	for objective_value in world.victory_objectives:
		var objective: Dictionary = objective_value
		if not bool(objective.get("active", true)) or not _entity_visible(objective, observer_team, observer_states, fog_map_size):
			continue
		var objective_id := int(objective.get("id", -1))
		objectives.append(_project_entity(cache["objectives"], objective, observer_team))
		seen_objective_ids[objective_id] = true
	_prune_entity_cache(cache["objectives"], seen_objective_ids)
	_sort_by_entity_id_if_needed(objectives)
	_observe_stage(probe, prefix + ".objectives", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var buildings: Array = []
	var seen_building_ids: Dictionary = {}
	var remembered_buildings: Dictionary = world.last_known_buildings_by_player.get(observer_team, {})
	var blocked_population_queues := 0
	var requested_production_only := bool(options.get("requested_production_only", false))
	var production_requests: Array = options.get("production_requests", [])
	var planning_technology_ids: Array = options.get("planning_technology_ids", [])
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		var building_id := int(building.get("id", -1))
		var own_building := int(building.get("team", 0)) == observer_team
		if own_building:
			var own_queue: Array = building.get("production_queue", [])
			if not own_queue.is_empty() and String(own_queue[0].get("status", "")) == "blocked_population":
				blocked_population_queues += 1
		var visible_now := _entity_visible(building, observer_team, observer_states, fog_map_size)
		var knowledge: Dictionary = building
		if visible_now:
			_remember_visible_building(remembered_buildings, building_id, building)
		else:
			knowledge = remembered_buildings.get(building_id, {})
			if knowledge.is_empty():
				continue
			var remembered_position := Vector2(knowledge.get("pos", Vector2.ZERO))
			var remembered_cell := Vector2i(floori(remembered_position.x), floori(remembered_position.y))
			var remembered_state := int(fog.state_at_cell(observer_team, remembered_cell))
			if remembered_state != 1:
				if remembered_state == 2:
					remembered_buildings.erase(building_id)
				continue
		var projected := _project_entity(cache["buildings"], knowledge, observer_team)
		if not visible_now:
			projected["last_known"] = true
		else:
			projected["target_domains"] = world.combat_target_domains(building)
			if world.trade_system.is_trade_dock(building):
				projected["trade"] = world.trade_system.presentation_for_dock(building)
		if visible_now and own_building:
			_add_population_point_costs(world, projected, observer_team)
			if not restrict_command_options or command_option_entity_lookup.has(building_id):
				projected["builder_count"] = building.get("builders", {}).size()
				if String(building.get("state", "complete")) == "foundation" and (not bool(options.get("recover_abandoned_foundations_only", false)) or SimulationSnapshot.foundation_needs_recovery(building, units)):
					projected["reachable_builder_ids"] = world.reachable_builder_ids(building)
				if requested_production_only:
					projected["command_options"] = SimulationSnapshot.requested_production_options(world, building, observer_team, production_requests)
				elif bool(options.get("economic_production_options_only", false)):
					projected["command_options"] = SimulationSnapshot.economic_production_options(world, building, observer_team)
				else:
					projected["command_options"] = {
						"train": world.get_unit_production_options(building_id, observer_team),
						"research": world.get_research_options(building_id, observer_team),
					}
				if not planning_technology_ids.is_empty():
					SimulationSnapshot.append_planning_research_options(world, projected, building, observer_team, planning_technology_ids)
		buildings.append(projected)
		seen_building_ids[building_id] = true

	var remembered_ids: Array = remembered_buildings.keys()
	remembered_ids.sort()
	for missing_id_value in remembered_ids:
		var missing_id := int(missing_id_value)
		if world.find_building(missing_id) != null:
			continue
		var memory: Dictionary = remembered_buildings[missing_id]
		var memory_position := Vector2(memory.get("pos", Vector2.ZERO))
		var memory_state := int(fog.state_at_world(observer_team, memory_position))
		if memory_state == 2:
			remembered_buildings.erase(missing_id)
			continue
		if memory_state != 1:
			continue
		var projected_memory := _project_entity(cache["buildings"], memory, observer_team)
		projected_memory["last_known"] = true
		buildings.append(projected_memory)
		seen_building_ids[missing_id] = true
	world.last_known_buildings_by_player[observer_team] = remembered_buildings
	_prune_entity_cache(cache["buildings"], seen_building_ids)
	_sort_by_entity_id_if_needed(buildings)
	_observe_stage(probe, prefix + ".buildings", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var player_state: Dictionary = SimulationSnapshot.presentation_player_state(world, observer_team)
	player_state["blocked_population_queues"] = blocked_population_queues
	var include_navigation := bool(options.get("include_navigation", true))
	var navigation: Dictionary = world.ai_navigation_knowledge.snapshot(world, fog, observer_team, probe) if include_navigation else {}
	var build_site_filter: Callable = options.get("build_site_filter", Callable())
	if build_site_filter.is_valid() and not available_requested_build_site_kinds.is_empty():
		if bool(options.get("build_site_filter_navigation", false)):
			available_requested_build_site_kinds = build_site_filter.call(available_requested_build_site_kinds, units, buildings, player_state, navigation)
		else:
			available_requested_build_site_kinds = build_site_filter.call(available_requested_build_site_kinds, units, buildings, player_state)
	var site_options := options.duplicate()
	site_options["planning_units"] = units
	site_options["planning_buildings"] = buildings
	var build_sites := _build_sites(world, tick, observer_team, available_requested_build_site_kinds, site_options)
	_observe_stage(probe, prefix + ".build_sites", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var include_fog_cells := bool(options.get("include_fog_cells", false))
	var presented_fog: Dictionary = SimulationSnapshot.presentation_fog(fog, observer_team) if include_fog_cells else {"observer_team": observer_team, "cells": []}
	_observe_stage(probe, prefix + ".state", stage_started)
	return {
		"format_version": SimulationSnapshot.FORMAT_VERSION,
		"tick": tick,
		"observer_team": observer_team,
		"map_size": world.map_size,
		"units": units,
		"resources": resources,
		"objectives": objectives,
		"buildings": buildings,
		"projectiles": [],
		"overview": {"units": [], "resources": [], "buildings": []},
		"ai_distress_signals": world.get_attack_distress_signals(observer_team),
		"navigation": navigation,
		"build_sites": build_sites,
		"fog_revision": int(fog.revision_for_player(observer_team)),
		"fog_exploration_revision": int(fog.exploration_revision_for_player(observer_team)),
		"resource_memory_revision": int(world.known_resource_revision(observer_team)) if world.has_method("known_resource_revision") else 0,
		"fog": presented_fog,
		"player_state": player_state,
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"match_result": world.get_victory_result(),
		"match_elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"scenario": {},
	}


func _supports_retained_projection(options: Dictionary) -> bool:
	# The retained store intentionally implements the compact planner contract.
	# Rich render/scenario projections keep using the general snapshot path so a
	# future caller cannot silently receive a narrower payload than requested.
	return (
		bool(options.get("compact_entities", false))
		and not bool(options.get("compact_render_entities", false))
		and not bool(options.get("include_projectiles", true))
		and not bool(options.get("include_scenario", true))
		and not bool(options.get("include_overview", false))
		and not bool(options.get("include_overview_resources", false))
		and not options.has("entity_bounds")
		and options.get("always_include_entity_ids", []).is_empty()
	)


func _cache_for(observer_team: int) -> Dictionary:
	var cache: Dictionary = observer_caches.get(observer_team, {})
	if cache.is_empty():
		cache = {"units": {}, "buildings": {}, "objectives": {}}
		observer_caches[observer_team] = cache
	return cache


func _project_entity(entity_cache: Dictionary, source: Dictionary, observer_team: int) -> Dictionary:
	var entity_id := int(source.get("id", -1))
	var result: Dictionary = entity_cache.get(entity_id, {})
	if result.is_empty():
		result = SimulationSnapshot.compact_ai_entity(source, observer_team)
		if entity_id >= 0:
			entity_cache[entity_id] = result
	else:
		_refresh_entity_projection(result, source, observer_team)
	for decorator in ["last_known", "target_domains", "trade", "builder_count", "command_options"]:
		result.erase(decorator)
	return result


func _refresh_entity_projection(result: Dictionary, source: Dictionary, observer_team: int) -> void:
	for field in AI_SCALAR_FIELDS:
		if source.has(field):
			result[field] = source[field]
		else:
			result.erase(field)
	for field in ["resource_id", "path_request_id"]:
		if (observer_team <= 0 or int(source.get("team", 0)) == observer_team) and source.has(field):
			result[field] = int(source[field])
		else: result.erase(field)
	for field in AI_ARRAY_FIELDS:
		_sync_array_field(result, source, field)
	_sync_components(result, source, observer_team)
	_sync_production_queue(result, source, observer_team)


func _sync_components(result: Dictionary, source: Dictionary, observer_team: int) -> void:
	var own_entity := observer_team <= 0 or int(source.get("team", 0)) == observer_team
	var source_components: Dictionary = source.get("components", {})
	var components: Dictionary = result.get("components", {})
	var worker: Dictionary = source_components.get("worker", {})
	var projected_worker: Dictionary = components.get("worker", {})
	projected_worker["enabled"] = bool(worker.get("enabled", false))
	components["worker"] = projected_worker

	var order: Dictionary = source_components.get("order", {})
	if own_entity and not order.is_empty():
		var projected_order: Dictionary = components.get("order", {})
		projected_order["type"] = String(order.get("type", "none"))
		projected_order["target_entity_id"] = int(order.get("target_entity_id", -1))
		projected_order["completed"] = bool(order.get("completed", true))
		projected_order["completion_reason"] = String(order.get("completion_reason", ""))
		components["order"] = projected_order
	else:
		components.erase("order")

	var healing: Dictionary = source_components.get("healing", {})
	if bool(healing.get("enabled", false)):
		components["healing"] = {"enabled": true}
	else:
		components.erase("healing")
	var combat: Dictionary = source_components.get("combat", {})
	if not combat.is_empty():
		var projected_combat: Dictionary = components.get("combat", {})
		projected_combat["projectile_id"] = int(combat.get("projectile_id", source.get("projectile_id", -1)))
		projected_combat["blast_range"] = float(combat.get("blast_range", source.get("blast_range", 0.0)))
		components["combat"] = projected_combat
	else:
		components.erase("combat")
	var cargo: Dictionary = source_components.get("cargo", {})
	if bool(cargo.get("enabled", false)):
		var projected_cargo: Dictionary = components.get("cargo", {})
		projected_cargo["enabled"] = true
		projected_cargo["capacity"] = maxi(0, int(cargo.get("capacity", 0)))
		projected_cargo["allow_allied"] = bool(cargo.get("allow_allied", true))
		projected_cargo["allow_artifacts"] = bool(cargo.get("allow_artifacts", true))
		if own_entity:
			_sync_array_value(projected_cargo, "passenger_ids", cargo.get("passenger_ids", []))
		else:
			projected_cargo.erase("passenger_ids")
		projected_cargo.erase("count")
		components["cargo"] = projected_cargo
	else:
		components.erase("cargo")
	var trade: Dictionary = source_components.get("trade", {})
	if bool(trade.get("enabled", false)):
		var projected_trade: Dictionary = components.get("trade", {})
		projected_trade["enabled"] = true
		if own_entity:
			for field in ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]:
				if trade.has(field):
					projected_trade[field] = trade[field]
				else:
					projected_trade.erase(field)
		else:
			for field in ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]:
				projected_trade.erase(field)
		components["trade"] = projected_trade
	else:
		components.erase("trade")
	result["components"] = components


func _sync_production_queue(result: Dictionary, source: Dictionary, observer_team: int) -> void:
	if not source.has("production_queue") or (observer_team > 0 and int(source.get("team", 0)) != observer_team):
		result.erase("production_queue")
		return
	var source_queue: Array = source.get("production_queue", [])
	var projected_queue: Array = result.get("production_queue", [])
	var changed := not result.has("production_queue") or source_queue.size() != projected_queue.size()
	if not changed:
		for index in range(source_queue.size()):
			var source_order: Dictionary = source_queue[index]
			var projected_order: Dictionary = projected_queue[index]
			if String(projected_order.get("order_type", "unit")) != String(source_order.get("order_type", "unit")) or String(projected_order.get("kind", "")) != String(source_order.get("kind", "")) or int(projected_order.get("technology_id", -1)) != int(source_order.get("technology_id", -1)) or String(projected_order.get("status", "queued")) != String(source_order.get("status", "queued")) or int(projected_order.get("population_cost", 0)) != int(source_order.get("population_cost", 0)):
				changed = true
				break
	if not changed:
		return
	projected_queue = []
	for order_value in source_queue:
		var order: Dictionary = order_value
		projected_queue.append({
			"order_type": String(order.get("order_type", "unit")),
			"kind": String(order.get("kind", "")),
			"technology_id": int(order.get("technology_id", -1)),
			"status": String(order.get("status", "queued")),
			"population_cost": int(order.get("population_cost", 0)),
		})
	result["production_queue"] = projected_queue


func _remember_visible_building(memories: Dictionary, building_id: int, building: Dictionary) -> void:
	var existing: Dictionary = memories.get(building_id, {})
	if not _building_memory_matches(existing, building):
		memories[building_id] = SimulationSnapshot.compact_render_entity(building)


func _building_memory_matches(memory: Dictionary, building: Dictionary) -> bool:
	if memory.is_empty():
		return false
	for field in BUILDING_MEMORY_SCALAR_FIELDS:
		if memory.has(field) != building.has(field):
			return false
		if field == "anim" and AnimationController.clip_for_state(String(building.get("anim_state", AnimationController.IDLE))) != "attack":
			# Non-combat building animation is derived from presentation time. Its
			# simulation accumulator is not part of AI knowledge and must not force
			# a detached fog-memory copy on every decision.
			continue
		if building.has(field) and memory[field] != building[field]:
			return false
	for field in AI_ARRAY_FIELDS:
		if memory.has(field) != building.has(field):
			return false
		if building.has(field) and memory.get(field, []) != building.get(field, []):
			return false
	if memory.has("footprint") != building.has("footprint") or memory.get("footprint", {}) != building.get("footprint", {}):
		return false
	if memory.has("presentation_state_overrides") != building.has("presentation_state_overrides") or memory.get("presentation_state_overrides", {}) != building.get("presentation_state_overrides", {}):
		return false
	var source_components: Dictionary = building.get("components", {})
	var remembered_components: Dictionary = memory.get("components", {})
	var source_ownership: Dictionary = source_components.get("ownership", {})
	var remembered_ownership: Dictionary = remembered_components.get("ownership", {})
	if source_ownership.is_empty() != remembered_ownership.is_empty():
		return false
	if not source_ownership.is_empty() and int(source_ownership.get("civilization_id", 13)) != int(remembered_ownership.get("civilization_id", 13)):
		return false
	for component_name in ["worker", "conversion", "healing"]:
		var source_component: Dictionary = source_components.get(component_name, {})
		var remembered_component: Dictionary = remembered_components.get(component_name, {})
		if source_component.is_empty() != remembered_component.is_empty():
			return false
		if not source_component.is_empty() and bool(source_component.get("enabled", false)) != bool(remembered_component.get("enabled", false)):
			return false
	var source_cargo: Dictionary = source_components.get("cargo", {})
	var remembered_cargo: Dictionary = remembered_components.get("cargo", {})
	if source_cargo.is_empty() != remembered_cargo.is_empty():
		return false
	if not source_cargo.is_empty() and (bool(source_cargo.get("enabled", false)) != bool(remembered_cargo.get("enabled", false)) or maxi(0, int(source_cargo.get("capacity", 0))) != maxi(0, int(remembered_cargo.get("capacity", 0)))):
		return false
	var source_trade: Dictionary = source_components.get("trade", {})
	var remembered_trade: Dictionary = remembered_components.get("trade", {})
	if source_trade.is_empty() != remembered_trade.is_empty():
		return false
	if not source_trade.is_empty() and (bool(source_trade.get("enabled", false)) != bool(remembered_trade.get("enabled", false)) or int(source_trade.get("target_building_source_id", -1)) != int(remembered_trade.get("target_building_source_id", -1))):
		return false
	return true


func _add_population_point_costs(world, projected: Dictionary, observer_team: int) -> void:
	for order_value in projected.get("production_queue", []):
		var order: Dictionary = order_value
		if String(order.get("order_type", "unit")) == "unit":
			order["population_points_cost"] = world.unit_population_points_cost(String(order.get("kind", "")), observer_team)


func _build_sites(world, tick: int, observer_team: int, available_kinds: Array, options: Dictionary) -> Dictionary:
	if not available_kinds.is_empty():
		return SimulationSnapshot.requested_build_sites(world, tick, observer_team, available_kinds, options, options.get("planning_units", []), options.get("planning_buildings", []))
	if bool(options.get("include_build_sites", false)):
		return world.get_mixed_domain_build_sites(observer_team)
	return {}


func _project_resources(source: Array, observer_team: int) -> Array:
	var result: Array = []
	for resource_value in source:
		result.append(SimulationSnapshot.compact_ai_entity(resource_value, observer_team))
	return result


func _prune_entity_cache(entity_cache: Dictionary, seen_ids: Dictionary) -> void:
	for entity_id_value in entity_cache.keys():
		if not seen_ids.has(int(entity_id_value)):
			entity_cache.erase(entity_id_value)


func _sync_array_field(target: Dictionary, source: Dictionary, field: String) -> void:
	if source.has(field):
		_sync_array_value(target, field, source.get(field, []))
	else:
		target.erase(field)


func _sync_array_value(target: Dictionary, field: String, source_value: Array) -> void:
	var current: Array = target.get(field, [])
	if current != source_value:
		target[field] = source_value.duplicate()


func _id_lookup(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for entity_id_value in ids:
		result[int(entity_id_value)] = true
	return result


func _sort_by_entity_id_if_needed(entities: Array) -> void:
	var previous_id := -9223372036854775807
	for entity_value in entities:
		var entity_id := int(entity_value.get("id", -1))
		if entity_id < previous_id:
			entities.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
			return
		previous_id = entity_id


func _entity_visible(entity: Dictionary, observer_team: int, states: PackedByteArray, map_size: Vector2i) -> bool:
	if int(entity.get("team", 0)) == observer_team:
		return true
	var position := Vector2(entity.get("pos", entity.get("position", Vector2.ZERO)))
	var cell_x := floori(position.x)
	var cell_y := floori(position.y)
	if cell_x < 0 or cell_y < 0 or cell_x >= map_size.x or cell_y >= map_size.y:
		return false
	return int(states[cell_y * map_size.x + cell_x]) == 2


func _observe_stage(probe: Variant, metric: String, started: int) -> void:
	if probe != null:
		probe.observe_microseconds(metric, Time.get_ticks_usec() - started)
