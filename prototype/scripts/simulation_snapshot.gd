class_name RoRSimulationSnapshot
extends RefCounted

const PresentationBuilder := preload("res://scripts/simulation_presentation_builder.gd")
const PresentationProjection := preload("res://scripts/simulation_presentation_projection.gd")

const EntityComponents := preload("res://scripts/entity_components.gd")
const ObservationQueries := preload("res://scripts/simulation_observation_queries.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")

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


# Shared legal-projection contract. Presentation and retained AI observations
# use the same field-level privacy rules without making either system depend on
# the other's lifecycle or caches.
static func compact_ai_entity(entity: Dictionary, observer_team: int = 0) -> Dictionary:
	return _compact_ai_entity(entity, observer_team)


static func compact_render_entity(entity: Dictionary) -> Dictionary:
	return _compact_render_entity(entity)


static func requested_production_options(world, building: Dictionary, team: int, requests: Array) -> Dictionary:
	return _requested_production_options(world, building, team, requests)


static func append_planning_research_options(world, projected: Dictionary, source: Dictionary, team: int, technology_ids: Array) -> void:
	_append_planning_research_options(world, projected, source, team, technology_ids)


static func presentation_player_state(world, observer_team: int) -> Dictionary:
	return _presentation_player_state(world, observer_team)


static func presentation_fog(fog, observer_team: int) -> Dictionary:
	return _presentation_fog(fog, observer_team)


# Explicit compatibility entry point for tools and consumers that require
# planning/command queries. The ordinary presentation() entry point only reads.
static func with_queries(world, tick: int, observer_team: int = 0, options: Dictionary = {}) -> Dictionary:
	return ObservationQueries.enrich(world, presentation(world, tick, observer_team, options), options)


static var native_selected_batch_enabled := true
static func presentation(world, tick: int, observer_team: int = 0, options: Dictionary = {}) -> Dictionary:
	return PresentationBuilder.new(world, tick, observer_team, options, FORMAT_VERSION, native_selected_batch_enabled).build()


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
		EntityComponents.project_dynamic(canonical_entity)
		# Selection belongs to player-control/presentation state and must not
		# change deterministic simulation hashes.
		canonical_entity.erase("selected")
		canonical_entity.erase("formation_shared_motion")
		canonical_entity.erase("_formation_path_cache")
		canonical_entity.erase("formation_steering_target")
		canonical_entity.erase("formation_shared_isolated")
		result.append(canonical_entity)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _presentation_entity(entity: Dictionary, observer_team: int = 0, compact: bool = false, compact_render: bool = false, compact_render_projector: Callable = Callable()) -> Dictionary:
	return PresentationProjection._presentation_entity(entity, observer_team, compact, compact_render, compact_render_projector)


static func _compact_render_entity(entity: Dictionary) -> Dictionary:
	return PresentationProjection._compact_render_entity(entity)


static func _compact_control_entity(entity: Dictionary, observer_team: int = 0, compact_render_projector: Callable = Callable(), rendered: Dictionary = {}) -> Dictionary:
	return PresentationProjection._compact_control_entity(entity, observer_team, compact_render_projector, rendered)


static func _entity_in_bounds(entity: Dictionary, bounds: Rect2) -> bool:
	return PresentationProjection._entity_in_bounds(entity, bounds)


static func _entity_visible_to_observer(
	entity: Dictionary,
	observer_team: int,
	observer_states: PackedByteArray,
	observer_allies: Dictionary,
	fog_map_size: Vector2i,
	allow_explored_static: bool = false
) -> bool:
	return PresentationProjection._entity_visible_to_observer(entity, observer_team, observer_states, observer_allies, fog_map_size, allow_explored_static)


static func _overview_entity(entity: Dictionary) -> Dictionary:
	return PresentationProjection._overview_entity(entity)


static func _compact_ai_entity(entity: Dictionary, observer_team: int = 0) -> Dictionary:
	return PresentationProjection._compact_ai_entity(entity, observer_team)


static func _requested_production_options(world, building: Dictionary, team: int, requests: Array) -> Dictionary:
	return ObservationQueries.requested_production_options(world, building, team, requests)


static func _append_planning_research_options(world, presentation_building: Dictionary, source_building: Dictionary, team: int, technology_ids: Array) -> void:
	ObservationQueries.append_planning_research_options(world, presentation_building, source_building, team, technology_ids)


static func _sort_entity_copies(source: Array) -> Array:
	return PresentationProjection._sort_entity_copies(source)


static func _presentation_fog(fog, observer_team: int) -> Dictionary:
	return PresentationProjection._presentation_fog(fog, observer_team)


static func _presentation_player_state(world, observer_team: int) -> Dictionary:
	return PresentationProjection._presentation_player_state(world, observer_team)


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
			"march_anchor": group.march_anchor,
			"march_speed": group.march_speed,
			"order_kind": group.order_kind,
			"deployed_columns": group.deployed_columns,
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


static func _production_overview(world, observer_team: int) -> Array:
	return PresentationProjection._production_overview(world, observer_team)


static func foundation_needs_recovery(building: Dictionary, units: Array) -> bool:
	return ObservationQueries.foundation_needs_recovery(building, units)


static func economic_production_options(world, building: Dictionary, team: int) -> Dictionary:
	return ObservationQueries.economic_production_options(world, building, team)


static func requested_build_sites(world, tick: int, team: int, kinds: Array, options: Dictionary, units: Array = [], buildings: Array = []) -> Dictionary:
	return ObservationQueries.requested_build_sites(world, tick, team, kinds, options, units, buildings)
