class_name RoRAiObservationStore
extends RefCounted

const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const ObservationQueries := preload("res://scripts/simulation_observation_queries.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")

# AI consumes legal simulation knowledge, not render state. Keep that projection
# on its own lifecycle and retain compact entity records between decisions. The
# unchanged records are reused; changed records are replaced without modifying
# earlier observations. Each observer retains its own fog-filtered entity set.

var observer_caches: Dictionary = {}


func clear() -> void:
	observer_caches.clear()


func observe_with_queries(world, tick: int, observer_team: int, options: Dictionary = {}) -> Dictionary:
	return ObservationQueries.enrich(world, observe(world, tick, observer_team, options), options)


# Retain legal factual records only; placement and command queries are explicit.
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

	var units: Array = []
	var seen_unit_ids: Dictionary = {}
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if not _entity_visible(unit, observer_team, observer_states, fog_map_size):
			continue
		var unit_id := int(unit.get("id", -1))
		var projected := _project_entity(cache["units"], unit, observer_team)
		if int(unit.get("team", 0)) != observer_team and world.are_teams_allied(observer_team, int(unit.get("team", 0))):
			projected["components"] = projected.get("components", {}).duplicate(true)
			var allied_cargo: Dictionary = projected.get("components", {}).get("cargo", {})
			if bool(allied_cargo.get("enabled", false)):
				allied_cargo["count"] = unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()
		units.append(projected)
		seen_unit_ids[unit_id] = true
	_prune_entity_cache(cache["units"], seen_unit_ids)
	_sort_by_entity_id_if_needed(units)
	_observe_stage(probe, prefix + ".units", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	# Resource knowledge already has an incremental fog-memory cache in the
	# world. Reuse its immutable AI projection rather than introducing another
	# owner for the same data.
	var resources: Array
	if world.has_method("get_known_ai_resource_snapshot"):
		resources = world.get_known_ai_resource_snapshot(observer_team)
	else:
		resources = world.get_known_ai_resources(observer_team).duplicate() if world.has_method("get_known_ai_resources") else _project_resources(world.get_known_resources(observer_team), observer_team)
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
	_observe_stage(probe, prefix + ".player_state", stage_started)
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
		"navigation": {},
		"build_sites": {},
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
	var immutable := ReadContract.ai(source, observer_team, entity_cache.get(entity_id, {}))
	if entity_id >= 0:
		entity_cache[entity_id] = immutable
	# Decorations belong to this observation and cannot mutate retained rows.
	return immutable.duplicate()


func _remember_visible_building(memories: Dictionary, building_id: int, building: Dictionary) -> void:
	var existing: Dictionary = memories.get(building_id, {})
	var source := building
	if not existing.is_empty() and AnimationController.clip_for_state(String(building.get("anim_state", AnimationController.IDLE))) != "attack":
		source = building.duplicate()
		if existing.has("anim"):
			source["anim"] = existing["anim"]
	memories[building_id] = ReadContract.render(source, existing)


func _add_population_point_costs(world, projected: Dictionary, observer_team: int) -> void:
	projected["production_queue"] = projected.get("production_queue", []).duplicate(true)
	for order_value in projected.get("production_queue", []):
		var order: Dictionary = order_value
		if String(order.get("order_type", "unit")) == "unit":
			order["population_points_cost"] = world.unit_population_points_cost(String(order.get("kind", "")), observer_team)


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
