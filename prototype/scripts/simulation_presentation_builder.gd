extends RefCounted

# A short-lived builder owns a single projection, never retained across ticks.
const EntityProjection := preload("res://scripts/simulation_presentation_projection.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")

var world: Variant
var tick: int
var observer_team: int
var options: Dictionary
var format_version: int
var native_selected_batch_enabled: bool
var snapshot_probe: Variant
var snapshot_prefix: String
var snapshot_stage_started: int
var fog: Variant
var observer_states: PackedByteArray
var observer_allies: Dictionary
var fog_map_size: Vector2i
var compact_entities: bool
var compact_render_entities: bool
var borrow_visible_render_entities: bool
var borrow_overview_entities: bool
var include_fog_cells: bool
var include_projectiles: bool
var include_scenario: bool
var include_overview: bool
var include_overview_resources: bool
var entity_bounds: Variant
var has_entity_bounds: bool
var always_include_entity_lookup: Dictionary
var command_option_entity_lookup: Dictionary
var restrict_command_options: bool
var compact_render_projector: Callable
var units: Array
var control_units: Array
var overview_units: Array
var resources: Array
var control_resources: Array
var overview_resources: Array
var resources_are_preordered: bool
var borrow_resource_view: bool
var objectives: Array
var buildings: Array
var control_buildings: Array
var overview_buildings: Array
var blocked_population_queues: int
var projectiles: Array
var player_state: Dictionary
var presented_fog: Dictionary
var scenario: Dictionary

func _init(source_world, source_tick: int, team: int, settings: Dictionary, version: int, selected_batch: bool) -> void:
	world = source_world
	tick = source_tick
	observer_team = team
	options = settings
	format_version = version
	native_selected_batch_enabled = selected_batch


func build() -> Dictionary:
	setup()
	project_units()
	project_resources()
	project_objectives()
	project_buildings()
	project_projectiles()
	project_state()
	return compose()


func setup() -> void:
	snapshot_probe = options.get("performance_probe")
	snapshot_prefix = String(options.get("performance_prefix", "presentation.snapshot"))
	snapshot_stage_started = Time.get_ticks_usec() if snapshot_probe != null else 0
	fog = world.get_fog_of_war()
	observer_states = PackedByteArray()
	observer_allies = {}
	if observer_team > 0:
		# Snapshot projection can touch thousands of entities. Resolve the
		# observer's immutable visibility inputs once instead of routing every
		# entity through world -> visibility system -> fog dictionaries.
		fog.ensure_player(observer_team)
		observer_states = fog.states_by_player[observer_team]
		observer_allies = fog.allies_by_player.get(observer_team, {})
	fog_map_size = fog.map_size
	compact_entities = bool(options.get("compact_entities", false))
	compact_render_entities = bool(options.get("compact_render_entities", false))
	borrow_visible_render_entities = bool(options.get("borrow_visible_render_entities", false))
	borrow_overview_entities = bool(options.get("borrow_overview_entities", false))
	include_fog_cells = bool(options.get("include_fog_cells", true))
	include_projectiles = bool(options.get("include_projectiles", true))
	include_scenario = bool(options.get("include_scenario", true))
	include_overview = bool(options.get("include_overview", false))
	include_overview_resources = bool(options.get("include_overview_resources", include_overview))
	entity_bounds = options.get("entity_bounds")
	has_entity_bounds = false
	if entity_bounds is Rect2:
		has_entity_bounds = (entity_bounds as Rect2).has_area()
	var always_include_entity_ids: Array = options.get("always_include_entity_ids", [])
	var command_option_entity_ids: Array = options.get("command_option_entity_ids", [])
	always_include_entity_lookup = {}
	for entity_id_value in always_include_entity_ids:
		always_include_entity_lookup[int(entity_id_value)] = true
	command_option_entity_lookup = {}
	for entity_id_value in command_option_entity_ids:
		command_option_entity_lookup[int(entity_id_value)] = true
	restrict_command_options = options.has("command_option_entity_ids")
	compact_render_projector = Callable(world, "compact_render_projection") if compact_render_entities and world.has_method("compact_render_projection") else Callable()
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".setup", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func project_units() -> void:
	units = []
	control_units = []
	overview_units = []
	var unit_control_projection_microseconds = 0
	var unit_render_projection_microseconds = 0
	var unit_acquisition_microseconds = 0
	var unit_overview_microseconds = 0
	var unit_detail_loop_microseconds = 0
	var unit_worker_options_microseconds = 0
	# The simulation spatial hash uses fine two-tile buckets for collision work.
	# On a sparse campaign viewport, visiting thousands of empty buckets costs
	# more than scanning a few hundred units. Switch to the bounded query only at
	# the population scale where it becomes cheaper and enables future 500-unit
	# players without penalizing today's campaign missions.
	world.entity_read_index.synchronize(world)
	var use_bounded_unit_query: bool = has_entity_bounds
	var unit_substage_started = Time.get_ticks_usec() if snapshot_probe != null else 0
	var detail_units: Array = world.entity_read_index.in_bounds(entity_bounds, "units") if use_bounded_unit_query else world.entity_read_index.legal_entities(world, observer_team, "units")
	if has_entity_bounds and not always_include_entity_lookup.is_empty():
		var detailed_ids: Dictionary = {}
		for unit_value in detail_units:
			detailed_ids[int(unit_value.get("id", -1))] = true
		for entity_id_value in always_include_entity_lookup.keys():
			var entity_id = int(entity_id_value)
			if detailed_ids.has(entity_id):
				continue
			var selected_unit: Variant = world.find_unit(entity_id)
			if selected_unit != null:
				detail_units.append(selected_unit)
	if snapshot_probe != null:
		unit_acquisition_microseconds = Time.get_ticks_usec() - unit_substage_started
		unit_substage_started = Time.get_ticks_usec()
	if include_overview:
		for unit_value in world.entity_read_index.legal_entities(world, observer_team, "units"):
			var overview_unit: Dictionary = unit_value
			if EntityProjection._entity_visible_to_observer(overview_unit, observer_team, observer_states, observer_allies, fog_map_size):
				overview_units.append(EntityProjection._overview_entity(overview_unit))
	if snapshot_probe != null:
		unit_overview_microseconds = Time.get_ticks_usec() - unit_substage_started
		unit_substage_started = Time.get_ticks_usec()
	if compact_render_entities and borrow_visible_render_entities and not compact_entities and (always_include_entity_lookup.is_empty() or native_selected_batch_enabled):
		var kernel: Variant = world.render_entity_projection_cache.native_kernel
		if kernel != null and kernel.has_method("filter_visible_entities"):
			var visible: Array = kernel.filter_visible_entities(detail_units, observer_team, observer_states, fog_map_size)
			units = world.render_entity_projection_cache.project_many(visible, world.entity_changes)
			for index in range(visible.size()):
				if not always_include_entity_lookup.has(int(visible[index].get("id",-1))): continue
				var projection_started = Time.get_ticks_usec() if snapshot_probe != null else 0
				var control = EntityProjection._compact_control_entity(visible[index], observer_team, Callable(), units[index])
				units[index] = control
				control_units.append(control)
				if snapshot_probe != null: unit_control_projection_microseconds += Time.get_ticks_usec()-projection_started
			detail_units = []
	for unit in detail_units:
		if has_entity_bounds and not use_bounded_unit_query and not EntityProjection._entity_in_bounds(unit, entity_bounds) and not always_include_entity_lookup.has(int(unit.get("id", -1))):
			continue
		if EntityProjection._entity_visible_to_observer(unit, observer_team, observer_states, observer_allies, fog_map_size):
			var unit_id = int(unit.get("id", -1))
			var presentation_unit: Dictionary
			if compact_render_entities and always_include_entity_lookup.has(unit_id):
				var projection_started = Time.get_ticks_usec() if snapshot_probe != null else 0
				presentation_unit = EntityProjection._compact_control_entity(unit, observer_team, compact_render_projector)
				if snapshot_probe != null:
					unit_control_projection_microseconds += Time.get_ticks_usec() - projection_started
			elif compact_render_entities and borrow_visible_render_entities:
				# The in-process renderer is a trusted read-only consumer on the same
				# thread. Borrow unchanged visible records rather than copying dozens
				# of fields every fixed tick. Selected/control entities stay detached.
				presentation_unit = compact_render_projector.call(unit) if compact_render_projector.is_valid() else ReadContract.render(unit)
			else:
				var projection_started = Time.get_ticks_usec() if snapshot_probe != null else 0
				presentation_unit = EntityProjection._presentation_entity(
					unit,
					observer_team,
					compact_entities,
					compact_render_entities,
					compact_render_projector
				)
				if snapshot_probe != null:
					unit_render_projection_microseconds += Time.get_ticks_usec() - projection_started
			if compact_entities and observer_team > 0 and int(unit.get("team", 0)) != observer_team and world.are_teams_allied(observer_team, int(unit.get("team", 0))):
				presentation_unit = presentation_unit.duplicate(true)
				var allied_cargo: Dictionary = presentation_unit.get("components", {}).get("cargo", {})
				if bool(allied_cargo.get("enabled", false)):
					allied_cargo["count"] = unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()
			units.append(presentation_unit)
			if always_include_entity_lookup.has(unit_id):
				control_units.append(presentation_unit)
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


func project_resources() -> void:
	resources = []
	control_resources = []
	overview_resources = []
	resources_are_preordered = observer_team > 0 and world.has_method("get_known_resources")
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
	if include_overview_resources:
		var overview_source_resources: Array = world.get_known_resources(observer_team) if resources_are_preordered else world.get_resources()
		if borrow_overview_entities:
			overview_resources = overview_source_resources.duplicate()
		else:
			for resource_value in overview_source_resources:
				overview_resources.append(EntityProjection._overview_entity(resource_value))
	borrow_resource_view = compact_render_entities and borrow_visible_render_entities and resources_are_preordered and has_entity_bounds and known_resources.is_read_only()
	if borrow_resource_view:
		resources = known_resources
		# The legal memory records are already detached render projections. Only
		# selected resources need the larger control projection; selected units
		# must not cause the whole forest to be traversed/copied each tick.
		for selected_id_value in always_include_entity_lookup:
			var selected_id = int(selected_id_value)
			var low = 0
			var high = resources.size()
			while low < high:
				var middle = (low + high) / 2
				if int(resources[middle]["id"]) < selected_id: low = middle + 1
				else: high = middle
			if low >= resources.size() or int(resources[low]["id"]) != selected_id: continue
			var selected_resource = EntityProjection._presentation_entity(resources[low], observer_team, compact_entities, false, compact_render_projector)
			if resources.is_read_only(): resources = resources.duplicate()
			resources[low] = selected_resource
			control_resources.append(selected_resource)
	for resource in ([] if borrow_resource_view else known_resources):
		var resource_id = int(resource.get("id", -1))
		var presentation_resource: Dictionary
		if resources_use_shared_ai_projection:
			presentation_resource = resource
		else:
			presentation_resource = EntityProjection._presentation_entity(
					resource,
					observer_team,
					compact_entities,
					compact_render_entities and not always_include_entity_lookup.has(resource_id),
					compact_render_projector
				)
		resources.append(presentation_resource)
		if always_include_entity_lookup.has(resource_id):
			control_resources.append(presentation_resource)
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".resources", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func project_objectives() -> void:
	objectives = []
	for objective in world.victory_objectives:
		if not bool(objective.get("active", true)):
			continue
		if EntityProjection._entity_visible_to_observer(objective, observer_team, observer_states, observer_allies, fog_map_size):
			objectives.append(EntityProjection._presentation_entity(objective, observer_team, compact_entities))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".objectives", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func project_buildings() -> void:
	buildings = []
	control_buildings = []
	overview_buildings = []
	var remembered_buildings: Dictionary = world.last_known_buildings_by_player.get(observer_team, {}) if observer_team > 0 else {}
	var memory_cursor: Dictionary = world.entity_read_index.memory_cursors.get(observer_team, {})
	var borrow_building_memory: bool = bool(options.get("borrow_sampled_building_memory", false)) and int(memory_cursor.get("entity", -1)) == world.entity_changes.revision and int(memory_cursor.get("fog", -1)) == fog.revision_for_player(observer_team)
	var live_building_ids: Dictionary = {}
	blocked_population_queues = 0
	for building in world.entity_read_index.legal_entities(world, observer_team, "buildings"):
		if observer_team > 0 and int(building.get("team", 0)) == observer_team:
			var own_queue: Array = building.get("production_queue", [])
			if not own_queue.is_empty() and String(own_queue[0].get("status", "")) == "blocked_population":
				blocked_population_queues += 1
		var building_id = int(building.get("id", -1))
		live_building_ids[building_id] = true
		var visible_now = EntityProjection._entity_visible_to_observer(building, observer_team, observer_states, observer_allies, fog_map_size)
		var knowledge: Dictionary = building
		var observed_render: Dictionary = {}
		if visible_now and observer_team > 0:
			# Capture only legal, observed state. A later fogged snapshot never
			# projects the live dictionary again.
			var sampled: Dictionary = remembered_buildings.get(building_id, {})
			if borrow_building_memory and ReadContract.is_render_record(sampled) and sampled.get("anim") == building.get("anim") and sampled.get("previous_pos") == building.get("previous_pos"):
				observed_render = sampled
			else:
				observed_render = compact_render_projector.call(building) if compact_render_projector.is_valid() else EntityProjection._compact_render_entity(building)
			remembered_buildings[building_id] = observed_render
		elif observer_team > 0:
			knowledge = remembered_buildings.get(building_id, {})
			if knowledge.is_empty():
				continue
			var remembered_cell = Vector2i(floori(Vector2(knowledge.get("pos", Vector2.ZERO)).x), floori(Vector2(knowledge.get("pos", Vector2.ZERO)).y))
			if fog.state_at_cell(observer_team, remembered_cell) != 1:
				if fog.state_at_cell(observer_team, remembered_cell) == 2:
					remembered_buildings.erase(building_id)
				continue
		var building_in_detail_bounds = not has_entity_bounds or EntityProjection._entity_in_bounds(knowledge, entity_bounds) or always_include_entity_lookup.has(building_id)
		if not include_overview and not building_in_detail_bounds:
			continue
		if not knowledge.is_empty():
			if include_overview:
				overview_buildings.append(EntityProjection._overview_entity(knowledge))
			if not building_in_detail_bounds:
				continue
			var presentation_building: Dictionary
			if not visible_now:
				presentation_building = EntityProjection._compact_ai_entity(knowledge, observer_team) if compact_entities else EntityProjection._compact_render_entity(knowledge)
				presentation_building = presentation_building.duplicate()
				presentation_building["last_known"] = true
			elif compact_render_entities and always_include_entity_lookup.has(building_id):
				presentation_building = EntityProjection._compact_control_entity(building, observer_team, compact_render_projector, observed_render)
			elif compact_render_entities and not observed_render.is_empty():
				presentation_building = observed_render
			else:
				presentation_building = EntityProjection._presentation_entity(
					building,
					observer_team,
					compact_entities,
					compact_render_entities,
					compact_render_projector
				)
			if visible_now:
				presentation_building = presentation_building.duplicate()
				presentation_building["target_domains"] = world.combat_target_domains(building)
			if visible_now and world.trade_system.is_trade_dock(building):
				presentation_building["trade"] = world.trade_system.presentation_for_dock(building)
			if compact_entities and observer_team > 0 and int(building.get("team", 0)) == observer_team:
				presentation_building["production_queue"] = presentation_building.get("production_queue", []).duplicate(true)
				for order_value in presentation_building.get("production_queue", []):
					var projected_order: Dictionary = order_value
					if String(projected_order.get("order_type", "unit")) == "unit":
						projected_order["population_points_cost"] = world.unit_population_points_cost(String(projected_order.get("kind", "")), observer_team)
			if observer_team > 0 and int(building.get("team", 0)) == observer_team and (not restrict_command_options or command_option_entity_lookup.has(int(building.get("id", -1)))):
				presentation_building["builder_count"] = building.get("builders", {}).size()
			buildings.append(presentation_building)
			if always_include_entity_lookup.has(building_id):
				control_buildings.append(presentation_building)
	if observer_team > 0:
		var missing_ids: Array = remembered_buildings.keys()
		missing_ids.sort()
		for missing_id_value in missing_ids:
			var missing_id = int(missing_id_value)
			if live_building_ids.has(missing_id):
				continue
			var memory: Dictionary = remembered_buildings[missing_id]
			var memory_position = Vector2(memory.get("pos", Vector2.ZERO))
			var memory_state: int = int(fog.state_at_world(observer_team, memory_position))
			if memory_state == 2:
				remembered_buildings.erase(missing_id)
				continue
			if memory_state != 1:
				continue
			if include_overview:
				overview_buildings.append(EntityProjection._overview_entity(memory))
			if not has_entity_bounds or EntityProjection._entity_in_bounds(memory, entity_bounds) or always_include_entity_lookup.has(missing_id):
				var last_known: Dictionary = EntityProjection._compact_ai_entity(memory, observer_team) if compact_entities else EntityProjection._compact_render_entity(memory)
				last_known = last_known.duplicate()
				last_known["last_known"] = true
				buildings.append(last_known)
		world.last_known_buildings_by_player[observer_team] = remembered_buildings
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".buildings", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func project_projectiles() -> void:
	projectiles = []
	if include_projectiles:
		for projectile in world.get_projectiles():
			if EntityProjection._entity_visible_to_observer(projectile, observer_team, observer_states, observer_allies, fog_map_size):
				projectiles.append(EntityProjection._presentation_entity(projectile, observer_team, compact_entities))
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".projectiles", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func project_state() -> void:
	player_state = EntityProjection._presentation_player_state(world, observer_team)
	if observer_team > 0:
		player_state["blocked_population_queues"] = blocked_population_queues
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".player_state", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()
	presented_fog = EntityProjection._presentation_fog(fog, observer_team) if include_fog_cells else {"observer_team": observer_team, "cells": []}
	scenario = world.scenario_system.presentation_state(observer_team) if include_scenario else {}
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".state", Time.get_ticks_usec() - snapshot_stage_started)
		snapshot_stage_started = Time.get_ticks_usec()


func compose() -> Dictionary:
	var sorted_units = EntityProjection._sort_entity_copies(units)
	# get_known_resources maintains its cache in stable entity-ID order. Avoid
	# sorting thousands of copied forest nodes again for every AI decision.
	var sorted_resources = resources if resources_are_preordered else EntityProjection._sort_entity_copies(resources)
	var sorted_objectives = EntityProjection._sort_entity_copies(objectives)
	var sorted_buildings = EntityProjection._sort_entity_copies(buildings)
	var sorted_projectiles = EntityProjection._sort_entity_copies(projectiles)
	var sorted_overview_units = EntityProjection._sort_entity_copies(overview_units)
	var sorted_overview_resources = overview_resources if resources_are_preordered else EntityProjection._sort_entity_copies(overview_resources)
	var sorted_overview_buildings = EntityProjection._sort_entity_copies(overview_buildings)
	if snapshot_probe != null:
		snapshot_probe.observe_microseconds(snapshot_prefix + ".sort", Time.get_ticks_usec() - snapshot_stage_started)
	return {
		"format_version": format_version,
		"tick": tick,
		"observer_team": observer_team,
		"map_size": world.map_size,
		"units": sorted_units,
		"control_units": control_units,
		"resources": sorted_resources,
		"resource_delta": world.known_resource_view_delta(observer_team) if borrow_resource_view and world.has_method("known_resource_view_delta") else {},
		"control_resources": control_resources,
		"objectives": sorted_objectives,
		"buildings": sorted_buildings,
		"control_buildings": control_buildings,
		"production_overview": EntityProjection._production_overview(world, observer_team) if bool(options.get("include_production_overview", false)) else [],
		"projectiles": sorted_projectiles,
		"overview": {
			"units": sorted_overview_units,
			"resources": sorted_overview_resources,
			"buildings": sorted_overview_buildings,
		},
		"ai_distress_signals": world.get_attack_distress_signals(observer_team) if observer_team > 0 else [],
		"navigation": {},
		"build_sites": {},
		# Rendering only depends on this observer's grid. Enemy and neutral fog
		# changes must not invalidate the local player's cached fog mesh.
		"fog_revision": int(fog.revision_for_player(observer_team)),
		"fog_exploration_revision": int(fog.exploration_revision_for_player(observer_team)),
		"resource_memory_revision": int(world.known_resource_revision(observer_team)) if observer_team > 0 and world.has_method("known_resource_revision") else 0,
		"fog": presented_fog,
		"player_state": player_state,
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"match_result": world.get_victory_result(),
		"match_elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"scenario": scenario,
	}
