class_name RoRSimulationSnapshot
extends RefCounted

const EntityComponents := preload("res://scripts/entity_components.gd")

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
	var snapshot_probe: Variant = options.get("performance_probe")
	var snapshot_prefix := String(options.get("performance_prefix", "presentation.snapshot"))
	var snapshot_stage_started := Time.get_ticks_usec() if snapshot_probe != null else 0
	var fog = world.get_fog_of_war()
	var observer_states := PackedByteArray()
	var observer_allies: Dictionary = {}
	if observer_team > 0:
		# Snapshot projection can touch thousands of entities. Resolve the
		# observer's immutable visibility inputs once instead of routing every
		# entity through world -> visibility system -> fog dictionaries.
		fog.ensure_player(observer_team)
		observer_states = fog.states_by_player[observer_team]
		observer_allies = fog.allies_by_player.get(observer_team, {})
	var fog_map_size: Vector2i = fog.map_size
	var compact_entities := bool(options.get("compact_entities", false))
	var compact_render_entities := bool(options.get("compact_render_entities", false))
	var borrow_visible_render_entities := bool(options.get("borrow_visible_render_entities", false))
	var borrow_overview_entities := bool(options.get("borrow_overview_entities", false))
	var include_navigation := bool(options.get("include_navigation", true))
	var include_build_sites := bool(options.get("include_build_sites", true))
	var include_fog_cells := bool(options.get("include_fog_cells", true))
	var include_projectiles := bool(options.get("include_projectiles", true))
	var include_scenario := bool(options.get("include_scenario", true))
	var include_worker_command_options := bool(options.get("include_worker_command_options", true))
	var include_overview := bool(options.get("include_overview", false))
	var entity_bounds: Variant = options.get("entity_bounds")
	var has_entity_bounds: bool = false
	if entity_bounds is Rect2:
		has_entity_bounds = (entity_bounds as Rect2).has_area()
	var always_include_entity_ids: Array = options.get("always_include_entity_ids", [])
	var command_option_entity_ids: Array = options.get("command_option_entity_ids", [])
	var always_include_entity_lookup: Dictionary = {}
	for entity_id_value in always_include_entity_ids:
		always_include_entity_lookup[int(entity_id_value)] = true
	var command_option_entity_lookup: Dictionary = {}
	for entity_id_value in command_option_entity_ids:
		command_option_entity_lookup[int(entity_id_value)] = true
	var restrict_command_options := options.has("command_option_entity_ids")
	var requested_production_only := bool(options.get("requested_production_only", false))
	var production_requests: Array = options.get("production_requests", [])
	var planning_technology_ids: Array = options.get("planning_technology_ids", [])
	var requested_build_site_kinds: Array = options.get("requested_build_site_kinds", [])
	var maximum_build_sites_per_kind := maxi(1, int(options.get("maximum_build_sites_per_kind", 4)))
	var build_site_search_radius := maxi(1, int(options.get("build_site_search_radius", 12)))
	var build_site_cache_ticks := maxi(0, int(options.get("build_site_cache_ticks", 0)))
	var minimum_structure_gap := maxf(0.0, float(options.get("minimum_structure_gap", 0.0)))
	var preferred_build_sites: Dictionary = options.get("preferred_build_sites", {})
	var strict_preferred_build_site_kinds: Array = options.get("strict_preferred_build_site_kinds", [])
	var compact_render_projector: Callable = Callable(world, "compact_render_projection") if compact_render_entities and world.has_method("compact_render_projection") else Callable()
	var requested_build_options: Array = []
	var worker_build_options: Array = []
	var worker_build_options_ready := false
	var available_requested_build_site_kinds: Array = []
	if observer_team > 0 and not requested_build_site_kinds.is_empty():
		var build_options: Array = world.get_build_options_for_kinds(observer_team, requested_build_site_kinds) if world.has_method("get_build_options_for_kinds") else world.get_build_options(observer_team)
		for option_value in build_options:
			var option: Dictionary = option_value
			if String(option.get("kind", "")) in requested_build_site_kinds:
				requested_build_options.append(option)
				if bool(option.get("accepted", false)):
					available_requested_build_site_kinds.append(String(option.get("kind", "")))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".setup", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var units: Array = []
	var overview_units: Array = []
	var unit_control_projection_microseconds := 0
	var unit_render_projection_microseconds := 0
	var unit_acquisition_microseconds := 0
	var unit_overview_microseconds := 0
	var unit_detail_loop_microseconds := 0
	var unit_worker_options_microseconds := 0
	# The simulation spatial hash uses fine two-tile buckets for collision work.
	# On a sparse campaign viewport, visiting thousands of empty buckets costs
	# more than scanning a few hundred units. Switch to the bounded query only at
	# the population scale where it becomes cheaper and enables future 500-unit
	# players without penalizing today's campaign missions.
	var use_bounded_unit_query: bool = has_entity_bounds and world.has_method("get_units_in_bounds") and world.get_units().size() >= 512
	var unit_substage_started := Time.get_ticks_usec() if snapshot_probe != null else 0
	var detail_units: Array = world.get_units_in_bounds(entity_bounds) if use_bounded_unit_query else world.get_units()
	if has_entity_bounds and not always_include_entity_lookup.is_empty():
		var detailed_ids: Dictionary = {}
		for unit_value in detail_units:
			detailed_ids[int(unit_value.get("id", -1))] = true
		for entity_id_value in always_include_entity_lookup.keys():
			var entity_id := int(entity_id_value)
			if detailed_ids.has(entity_id):
				continue
			var selected_unit: Variant = world.find_unit(entity_id)
			if selected_unit != null:
				detail_units.append(selected_unit)
	if snapshot_probe != null:
		unit_acquisition_microseconds = Time.get_ticks_usec() - unit_substage_started
		unit_substage_started = Time.get_ticks_usec()
	if include_overview:
		for unit_value in world.get_units():
			var overview_unit: Dictionary = unit_value
			if _entity_visible_to_observer(overview_unit, observer_team, observer_states, observer_allies, fog_map_size):
				overview_units.append(overview_unit if borrow_overview_entities else _overview_entity(overview_unit))
	if snapshot_probe != null:
		unit_overview_microseconds = Time.get_ticks_usec() - unit_substage_started
		unit_substage_started = Time.get_ticks_usec()
	for unit in detail_units:
		if has_entity_bounds and not use_bounded_unit_query and not _entity_in_bounds(unit, entity_bounds) and not always_include_entity_lookup.has(int(unit.get("id", -1))):
			continue
		if _entity_visible_to_observer(unit, observer_team, observer_states, observer_allies, fog_map_size):
			var unit_id := int(unit.get("id", -1))
			var presentation_unit: Dictionary
			if compact_render_entities and always_include_entity_lookup.has(unit_id):
				var projection_started := Time.get_ticks_usec() if snapshot_probe != null else 0
				presentation_unit = _compact_control_entity(unit, observer_team, compact_render_projector)
				if snapshot_probe != null:
					unit_control_projection_microseconds += Time.get_ticks_usec() - projection_started
			elif compact_render_entities and borrow_visible_render_entities:
				# The in-process renderer is a trusted read-only consumer on the same
				# thread. Borrow unchanged visible records rather than copying dozens
				# of fields every fixed tick. Selected/control entities stay detached.
				presentation_unit = unit
			else:
				var projection_started := Time.get_ticks_usec() if snapshot_probe != null else 0
				presentation_unit = _presentation_entity(
					unit,
					observer_team,
					compact_entities,
					compact_render_entities,
					compact_render_projector
				)
				if snapshot_probe != null:
					unit_render_projection_microseconds += Time.get_ticks_usec() - projection_started
			if compact_entities and observer_team > 0 and int(unit.get("team", 0)) != observer_team and world.are_teams_allied(observer_team, int(unit.get("team", 0))):
				var allied_cargo: Dictionary = presentation_unit.get("components", {}).get("cargo", {})
				if bool(allied_cargo.get("enabled", false)):
					allied_cargo["count"] = unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()
			if observer_team > 0 and int(unit.get("team", 0)) == observer_team and world.entity_is_worker(unit) and (not restrict_command_options or command_option_entity_lookup.has(int(unit.get("id", -1)))):
				var worker_options_started := Time.get_ticks_usec() if snapshot_probe != null else 0
				if not requested_build_options.is_empty():
					presentation_unit["command_options"] = {"build": requested_build_options}
				elif include_worker_command_options:
					# Build availability belongs to the player/tick, not to an
					# individual worker. A multi-worker selection must not rebuild
					# the same detached option list once per selected villager.
					if not worker_build_options_ready:
						worker_build_options = world.get_build_options(observer_team)
						worker_build_options_ready = true
					presentation_unit["command_options"] = {"build": worker_build_options}
				if snapshot_probe != null:
					unit_worker_options_microseconds += Time.get_ticks_usec() - worker_options_started
			units.append(presentation_unit)
	if snapshot_probe != null:
		unit_detail_loop_microseconds = Time.get_ticks_usec() - unit_substage_started
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.acquire", unit_acquisition_microseconds)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.overview", unit_overview_microseconds)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.detail_loop", unit_detail_loop_microseconds)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.worker_options", unit_worker_options_microseconds)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.control_projection", unit_control_projection_microseconds)
		snapshot_probe.observe_microseconds(snapshot_prefix + ".units.render_projection", unit_render_projection_microseconds)
		snapshot_stage_started = Time.get_ticks_usec()
	var resources: Array = []
	var overview_resources: Array = []
	var resources_are_preordered: bool = observer_team > 0 and world.has_method("get_known_resources")
	var resources_use_shared_ai_projection: bool = (
		compact_entities
		and observer_team > 0
		and not has_entity_bounds
		and not include_overview
		and world.has_method("get_known_ai_resources")
	)
	var known_resources: Array
	if resources_use_shared_ai_projection:
		known_resources = world.get_known_ai_resources(observer_team)
	elif resources_are_preordered and has_entity_bounds and world.has_method("get_known_resources_in_bounds"):
		known_resources = world.get_known_resources_in_bounds(observer_team, entity_bounds)
	elif resources_are_preordered:
		known_resources = world.get_known_resources(observer_team)
	else:
		known_resources = world.get_resources()
	if include_overview:
		var overview_source_resources: Array = world.get_known_resources(observer_team) if resources_are_preordered else world.get_resources()
		for resource_value in overview_source_resources:
			overview_resources.append(resource_value if borrow_overview_entities else _overview_entity(resource_value))
	for resource in known_resources:
		var resource_id := int(resource.get("id", -1))
		if resources_use_shared_ai_projection or (compact_render_entities and borrow_visible_render_entities and not always_include_entity_lookup.has(resource_id)):
			resources.append(resource)
		else:
			resources.append(_presentation_entity(
					resource,
					observer_team,
					compact_entities,
					compact_render_entities and not always_include_entity_lookup.has(resource_id),
					compact_render_projector
				))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".resources", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var objectives: Array = []
	for objective in world.victory_objectives:
		if not bool(objective.get("active", true)):
			continue
		if _entity_visible_to_observer(objective, observer_team, observer_states, observer_allies, fog_map_size):
			objectives.append(_presentation_entity(objective, observer_team, compact_entities))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".objectives", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var buildings: Array = []
	var overview_buildings: Array = []
	var remembered_buildings: Dictionary = world.last_known_buildings_by_player.get(observer_team, {}) if observer_team > 0 else {}
	var live_building_ids: Dictionary = {}
	var blocked_population_queues := 0
	for building in world.get_buildings():
		if observer_team > 0 and int(building.get("team", 0)) == observer_team:
			var own_queue: Array = building.get("production_queue", [])
			if not own_queue.is_empty() and String(own_queue[0].get("status", "")) == "blocked_population":
				blocked_population_queues += 1
		var building_id := int(building.get("id", -1))
		live_building_ids[building_id] = true
		var visible_now := _entity_visible_to_observer(building, observer_team, observer_states, observer_allies, fog_map_size)
		var knowledge: Dictionary = building
		if visible_now and observer_team > 0:
			# Capture only legal, observed state. A later fogged snapshot never
			# projects the live dictionary again.
			remembered_buildings[building_id] = _compact_render_entity(building)
		elif observer_team > 0:
			knowledge = remembered_buildings.get(building_id, {})
			if knowledge.is_empty():
				continue
			var remembered_cell := Vector2i(floori(Vector2(knowledge.get("pos", Vector2.ZERO)).x), floori(Vector2(knowledge.get("pos", Vector2.ZERO)).y))
			if fog.state_at_cell(observer_team, remembered_cell) != 1:
				if fog.state_at_cell(observer_team, remembered_cell) == 2:
					remembered_buildings.erase(building_id)
				continue
		var building_in_detail_bounds := not has_entity_bounds or _entity_in_bounds(knowledge, entity_bounds) or always_include_entity_lookup.has(building_id)
		if not include_overview and not building_in_detail_bounds:
			continue
		if not knowledge.is_empty():
			if include_overview:
				overview_buildings.append(knowledge if borrow_overview_entities and visible_now else _overview_entity(knowledge))
			if not building_in_detail_bounds:
				continue
			var presentation_building: Dictionary
			if not visible_now:
				presentation_building = _compact_ai_entity(knowledge, observer_team) if compact_entities else _compact_render_entity(knowledge)
				presentation_building["last_known"] = true
			elif compact_render_entities and always_include_entity_lookup.has(building_id):
				presentation_building = _compact_control_entity(building, observer_team, compact_render_projector)
			else:
				presentation_building = _presentation_entity(
					building,
					observer_team,
					compact_entities,
					compact_render_entities,
					compact_render_projector
				)
			if visible_now:
				presentation_building["target_domains"] = world.combat_target_domains(building)
			if visible_now and world.trade_system.is_trade_dock(building):
				presentation_building["trade"] = world.trade_system.presentation_for_dock(building)
			if compact_entities and observer_team > 0 and int(building.get("team", 0)) == observer_team:
				for order_value in presentation_building.get("production_queue", []):
					var projected_order: Dictionary = order_value
					if String(projected_order.get("order_type", "unit")) == "unit":
						projected_order["population_points_cost"] = world.unit_population_points_cost(String(projected_order.get("kind", "")), observer_team)
			if observer_team > 0 and int(building.get("team", 0)) == observer_team and (not restrict_command_options or command_option_entity_lookup.has(int(building.get("id", -1)))):
				presentation_building["builder_count"] = building.get("builders", {}).size()
				if String(building.get("state", "complete")) == "foundation":
					presentation_building["reachable_builder_ids"] = world.reachable_builder_ids(building)
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
	if observer_team > 0:
		var missing_ids: Array = remembered_buildings.keys()
		missing_ids.sort()
		for missing_id_value in missing_ids:
			var missing_id := int(missing_id_value)
			if live_building_ids.has(missing_id):
				continue
			var memory: Dictionary = remembered_buildings[missing_id]
			var memory_position := Vector2(memory.get("pos", Vector2.ZERO))
			var memory_state: int = int(fog.state_at_world(observer_team, memory_position))
			if memory_state == 2:
				remembered_buildings.erase(missing_id)
				continue
			if memory_state != 1:
				continue
			if include_overview:
				overview_buildings.append(_overview_entity(memory))
			if not has_entity_bounds or _entity_in_bounds(memory, entity_bounds) or always_include_entity_lookup.has(missing_id):
				var last_known: Dictionary = _compact_ai_entity(memory, observer_team) if compact_entities else _compact_render_entity(memory)
				last_known["last_known"] = true
				buildings.append(last_known)
		world.last_known_buildings_by_player[observer_team] = remembered_buildings
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".buildings", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var projectiles: Array = []
	if include_projectiles:
		for projectile in world.get_projectiles():
			if _entity_visible_to_observer(projectile, observer_team, observer_states, observer_allies, fog_map_size):
				projectiles.append(_presentation_entity(projectile, observer_team, compact_entities))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".projectiles", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var build_sites: Dictionary = {}
	if observer_team > 0 and not requested_build_site_kinds.is_empty():
		if build_site_cache_ticks > 0 and world.has_method("get_cached_local_build_sites"):
			build_sites = world.get_cached_local_build_sites(
				observer_team,
				available_requested_build_site_kinds,
				tick,
				build_site_cache_ticks,
				maximum_build_sites_per_kind,
				build_site_search_radius,
				preferred_build_sites,
				strict_preferred_build_site_kinds,
				minimum_structure_gap
			)
		else:
			build_sites = world.get_local_build_sites(
				observer_team,
				available_requested_build_site_kinds,
				maximum_build_sites_per_kind,
				build_site_search_radius,
				preferred_build_sites,
				strict_preferred_build_site_kinds,
				minimum_structure_gap
			)
	elif observer_team > 0 and include_build_sites:
		build_sites = world.get_mixed_domain_build_sites(observer_team)
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".build_sites", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var navigation: Dictionary = world.ai_navigation_knowledge.snapshot(world, fog, observer_team, snapshot_probe) if include_navigation and observer_team > 0 else {}
	var presented_fog: Dictionary = _presentation_fog(fog, observer_team) if include_fog_cells else {"observer_team": observer_team, "cells": []}
	var player_state: Dictionary = _presentation_player_state(world, observer_team)
	if observer_team > 0:
		player_state["blocked_population_queues"] = blocked_population_queues
	var scenario: Dictionary = world.scenario_system.presentation_state(observer_team) if include_scenario else {}
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".state", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	var sorted_units := _sort_entity_copies(units)
	# get_known_resources maintains its cache in stable entity-ID order. Avoid
	# sorting thousands of copied forest nodes again for every AI decision.
	var sorted_resources := resources if resources_are_preordered else _sort_entity_copies(resources)
	var sorted_objectives := _sort_entity_copies(objectives)
	var sorted_buildings := _sort_entity_copies(buildings)
	var sorted_projectiles := _sort_entity_copies(projectiles)
	var sorted_overview_units := _sort_entity_copies(overview_units)
	var sorted_overview_resources := _sort_entity_copies(overview_resources)
	var sorted_overview_buildings := _sort_entity_copies(overview_buildings)
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".sort", Time.get_ticks_usec() - snapshot_stage_started)
	return {
		"format_version": FORMAT_VERSION,
		"tick": tick,
		"observer_team": observer_team,
		"map_size": world.map_size,
		"units": sorted_units,
		"resources": sorted_resources,
		"objectives": sorted_objectives,
		"buildings": sorted_buildings,
		"projectiles": sorted_projectiles,
		"overview": {
			"units": sorted_overview_units,
			"resources": sorted_overview_resources,
			"buildings": sorted_overview_buildings,
		},
		"ai_distress_signals": world.get_attack_distress_signals(observer_team) if observer_team > 0 else [],
		"navigation": navigation,
		"build_sites": build_sites,
		# Rendering only depends on this observer's grid. Enemy and neutral fog
		# changes must not invalidate the local player's cached fog mesh.
		"fog_revision": int(fog.revision_for_player(observer_team)),
		"fog_exploration_revision": int(fog.exploration_revision_for_player(observer_team)),
		"fog": presented_fog,
		"player_state": player_state,
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"match_result": world.get_victory_result(),
		"match_elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"scenario": scenario,
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
		"population_points": economy["population_points"],
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
		EntityComponents.sync_dynamic(canonical_entity)
		# Selection belongs to player-control/presentation state and must not
		# change deterministic simulation hashes.
		canonical_entity.erase("selected")
		canonical_entity.erase("formation_shared_motion")
		canonical_entity.erase("formation_shared_isolated")
		result.append(canonical_entity)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _presentation_entity(entity: Dictionary, observer_team: int = 0, compact: bool = false, compact_render: bool = false, compact_render_projector: Callable = Callable()) -> Dictionary:
	if compact:
		return _compact_ai_entity(entity, observer_team)
	if compact_render:
		if compact_render_projector.is_valid():
			return compact_render_projector.call(entity)
		return _compact_render_entity(entity)
	var result: Dictionary = entity.duplicate(true)
	EntityComponents.sync_dynamic(result)
	result.erase("selected")
	result.erase("formation_shared_motion")
	result.erase("formation_shared_isolated")
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


static func _compact_render_entity(entity: Dictionary) -> Dictionary:
	# A frame does not need authoritative movement paths, combat tables,
	# technology state or production internals for every visible object. Keep a
	# detached projection with the stable fields consumed by rendering, picking
	# and right-click context resolution. Selected entities bypass this path and
	# retain the complete presentation contract for HUD actions and commands.
	var result: Dictionary = {}
	for key in [
		"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
		"health_unknown", "location_only",
		"pos", "previous_pos", "elevation", "source_elevation", "visual_height",
		"hp", "max_hp", "amount", "max_amount", "active", "logical_only",
		"state", "resource_state", "depletion_stage", "visible_when_depleted",
		"harvestable", "resource_type_id", "building_type", "movement_domain",
		"footprint_radius", "selection_radius", "selection_height",
		"anim", "anim_state", "facing", "presentation_facing",
		"death_phase", "death_elapsed", "construction_stage",
		"display_graphic_id", "source_frame", "source_graphic_id", "source_graphic_asset_name",
		"source_requested_graphic_asset_name", "source_asset_fallback_reason",
		"source_depleted_graphic_id", "source_depleted_asset_name", "combat_enabled", "task", "target_id",
		"target_building_id", "formation_forward", "carried_amount",
	]:
		if entity.has(key):
			result[key] = entity[key]
	for array_key in ["behavior_tags", "unit_lineage", "allowed_gatherer_domains"]:
		if entity.has(array_key):
			result[array_key] = entity.get(array_key, []).duplicate()
	if entity.has("footprint"):
		result["footprint"] = entity.get("footprint", {}).duplicate(true)
	if entity.has("presentation_state_overrides"):
		result["presentation_state_overrides"] = entity.get("presentation_state_overrides", {}).duplicate()
	var source_components: Dictionary = entity.get("components", {})
	var components: Dictionary = {}
	var ownership: Dictionary = source_components.get("ownership", {})
	if not ownership.is_empty():
		components["ownership"] = {
			"civilization_id": int(ownership.get("civilization_id", 13)),
		}
	for component_name in ["worker", "conversion", "healing"]:
		var source_component: Dictionary = source_components.get(component_name, {})
		if not source_component.is_empty():
			components[component_name] = {
				"enabled": bool(source_component.get("enabled", false)),
			}
	var cargo: Dictionary = source_components.get("cargo", {})
	if not cargo.is_empty():
		components["cargo"] = {
			"enabled": bool(cargo.get("enabled", false)),
			"capacity": maxi(0, int(cargo.get("capacity", 0))),
		}
	var trade: Dictionary = source_components.get("trade", {})
	if not trade.is_empty():
		components["trade"] = {
			"enabled": bool(trade.get("enabled", false)),
			"target_building_source_id": int(trade.get("target_building_source_id", -1)),
		}
	result["components"] = components
	return result


static func _compact_control_entity(entity: Dictionary, observer_team: int = 0, compact_render_projector: Callable = Callable()) -> Dictionary:
	# Selected objects need gameplay/HUD data, but not authoritative paths,
	# destination reservations, AI bookkeeping or the full technology payload.
	# Keeping this explicit contract avoids two deep copies of large unit records
	# every presentation tick while preserving every player-facing control field.
	var result: Dictionary = compact_render_projector.call(entity).duplicate(true) if compact_render_projector.is_valid() else _compact_render_entity(entity)
	for key in [
		"stance", "attack_damage", "attack_range", "attack_range_min", "attack_period",
		"carry_capacity", "carried_resource_type_id", "resource_id", "gather_stage",
		"worker_role_source_unit_id", "dropoff_id", "diagnostic_reason",
		"construction_progress", "production_progress", "rally_point",
	]:
		if entity.has(key):
			result[key] = entity[key]
	if entity.has("production_queue"):
		result["production_queue"] = entity.get("production_queue", []).duplicate(true)
	var source_components: Dictionary = entity.get("components", {})
	var components: Dictionary = result.get("components", {}).duplicate(true)
	for component_name in ["combat", "conversion", "healing", "resource_carrier"]:
		var component: Dictionary = source_components.get(component_name, {})
		if not component.is_empty():
			components[component_name] = component.duplicate(true)
	var cargo: Dictionary = source_components.get("cargo", {})
	if not cargo.is_empty():
		components["cargo"] = cargo.duplicate(true)
		if observer_team > 0 and int(entity.get("team", 0)) != observer_team:
			components["cargo"].erase("passenger_ids")
	var trade: Dictionary = source_components.get("trade", {})
	if not trade.is_empty():
		components["trade"] = trade.duplicate(true)
		if observer_team > 0 and int(entity.get("team", 0)) != observer_team:
			for private_field in ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]:
				components["trade"].erase(private_field)
	result["components"] = components
	return result


static func _entity_in_bounds(entity: Dictionary, bounds: Rect2) -> bool:
	return bounds.has_point(Vector2(entity.get("pos", entity.get("position", Vector2.ZERO))))


static func _entity_visible_to_observer(
	entity: Dictionary,
	observer_team: int,
	observer_states: PackedByteArray,
	observer_allies: Dictionary,
	fog_map_size: Vector2i,
	allow_explored_static: bool = false
) -> bool:
	if observer_team <= 0:
		return true
	var owner := int(entity.get("team", 0))
	if owner == observer_team:
		return true
	var position := Vector2(entity.get("pos", entity.get("position", Vector2.ZERO)))
	var cell_x := floori(position.x)
	var cell_y := floori(position.y)
	if cell_x < 0 or cell_y < 0 or cell_x >= fog_map_size.x or cell_y >= fog_map_size.y:
		return false
	var state := int(observer_states[cell_y * fog_map_size.x + cell_x])
	return state == 2 or (allow_explored_static and state == 1)


static func _overview_entity(entity: Dictionary) -> Dictionary:
	return {
		"id": int(entity.get("id", -1)),
		"team": int(entity.get("team", 0)),
		"kind": String(entity.get("kind", "")),
		"entity_type": String(entity.get("entity_type", "")),
		"pos": Vector2(entity.get("pos", entity.get("position", Vector2.ZERO))),
		"hp": float(entity.get("hp", 0.0)),
		"max_hp": float(entity.get("max_hp", 0.0)),
		"amount": int(entity.get("amount", 0)),
	}


static func _compact_ai_entity(entity: Dictionary, observer_team: int = 0) -> Dictionary:
	var result: Dictionary = {}
	for key in [
		"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
		"pos", "hp", "max_hp", "state", "task", "target_id", "target_building_id", "diagnostic_reason", "movement_domain", "combat_enabled", "retaliation_target_id", "amount",
		"resource_type_id", "harvestable", "footprint_radius", "rally_point", "attack_range",
		"projectile_id", "blast_range",
		"reachable_builder_ids",
	]:
		if entity.has(key):
			result[key] = entity[key]
	if (observer_team <= 0 or int(entity.get("team", 0)) == observer_team) and entity.has("resource_id"):
		result["resource_id"] = int(entity["resource_id"])
	if entity.has("unit_lineage"):
		result["unit_lineage"] = entity.get("unit_lineage", []).duplicate()
	if entity.has("behavior_tags"):
		result["behavior_tags"] = entity.get("behavior_tags", []).duplicate()
	if entity.has("allowed_gatherer_domains"):
		result["allowed_gatherer_domains"] = entity.get("allowed_gatherer_domains", []).duplicate()
	var worker: Dictionary = entity.get("components", {}).get("worker", {})
	var components := {"worker": {"enabled": bool(worker.get("enabled", false))}}
	if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
		var order: Dictionary = entity.get("components", {}).get("order", {})
		if not order.is_empty():
			components["order"] = {
				"type": String(order.get("type", "none")),
				"target_entity_id": int(order.get("target_entity_id", -1)),
				"completed": bool(order.get("completed", true)),
				"completion_reason": String(order.get("completion_reason", "")),
			}
	var healing: Dictionary = entity.get("components", {}).get("healing", {})
	if bool(healing.get("enabled", false)):
		components["healing"] = {"enabled": true}
	var combat: Dictionary = entity.get("components", {}).get("combat", {})
	if not combat.is_empty():
		components["combat"] = {
			"projectile_id": int(combat.get("projectile_id", entity.get("projectile_id", -1))),
			"blast_range": float(combat.get("blast_range", entity.get("blast_range", 0.0))),
		}
	var cargo: Dictionary = entity.get("components", {}).get("cargo", {})
	if bool(cargo.get("enabled", false)):
		components["cargo"] = {
			"enabled": true,
			"capacity": maxi(0, int(cargo.get("capacity", 0))),
			"allow_allied": bool(cargo.get("allow_allied", true)),
			"allow_artifacts": bool(cargo.get("allow_artifacts", true)),
		}
		if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
			components["cargo"]["passenger_ids"] = cargo.get("passenger_ids", []).duplicate()
	var trade: Dictionary = entity.get("components", {}).get("trade", {})
	if bool(trade.get("enabled", false)):
		components["trade"] = {"enabled": true}
		if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
			for field in ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]:
				if trade.has(field):
					components["trade"][field] = trade[field]
	result["components"] = components
	if entity.has("production_queue") and (observer_team <= 0 or int(entity.get("team", 0)) == observer_team):
		var queue: Array = []
		for order_value in entity.get("production_queue", []):
			var order: Dictionary = order_value
			queue.append({
				"order_type": String(order.get("order_type", "unit")),
				"kind": String(order.get("kind", "")),
				"technology_id": int(order.get("technology_id", -1)),
				"status": String(order.get("status", "queued")),
				"population_cost": int(order.get("population_cost", 0)),
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


static func _presentation_player_state(world, observer_team: int) -> Dictionary:
	if observer_team <= 0:
		return {}
	return {
		"team": observer_team,
		"allies": world.get_allied_teams(observer_team),
		"mutual_allies": world.get_allied_teams(observer_team).filter(func(other_team): return world.are_teams_allied(int(other_team), observer_team)),
		"relations": world.get_team_relations(observer_team),
		"status": world.player_registry.status(observer_team),
		"players": world.player_registry.public_states(),
		"food": int(world.get_resource_amount(observer_team, 0)),
		"wood": int(world.get_resource_amount(observer_team, 1)),
		"stone": int(world.get_resource_amount(observer_team, 2)),
		"gold": int(world.get_resource_amount(observer_team, 3)),
		"population": int(world.get_population(observer_team)),
		"population_points": int(world.economy_system.get_population_points(observer_team)),
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
		"revisions_by_player": fog.revisions_by_player.duplicate(true),
		"states_by_player": states,
		"personally_explored_by_player": fog.personally_explored_by_player.duplicate(true),
		"allies_by_player": fog.allies_by_player.duplicate(true),
		"shared_vision_by_player": fog.shared_vision_by_player.duplicate(true),
	}


static func _victory_state(world) -> Dictionary:
	return {
		"objectives": world.victory_objectives.duplicate(true),
		"scores": world.score_by_team.duplicate(true),
		"rules": world.victory_system.rules.duplicate(true),
		"allied_victory_enabled": bool(world.victory_system.allied_victory_enabled),
		"elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"hold_seconds": world.victory_system.hold_seconds.duplicate(true),
		"result": world.victory_system.result.duplicate(true),
		"scenario": world.scenario_system.canonical_state(),
	}
