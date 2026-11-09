class_name RoRSimulationSnapshot
extends RefCounted

const PresentationBuilder := preload("res://scripts/simulation_presentation_builder.gd")
const PresentationProjection := preload("res://scripts/simulation_presentation_projection.gd")

const EntityComponents := preload("res://scripts/entity_components.gd")
const ObservationQueries := preload("res://scripts/simulation_observation_queries.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")

const FORMAT_VERSION: int = 1
static var autosave_digest_kernel: Variant = null


# detached=false is a synchronous owner-only view. Its borrowed nested values
# must be consumed before the next simulation mutation, never queued as a DTO.
static func canonical(world, tick: int, controller = null, detached: bool = true) -> Dictionary:
	var snapshot := {
		"format_version": FORMAT_VERSION,
		"tick": tick,
		"world": _world_state(world, detached),
	}
	if controller != null:
		snapshot["controller"] = _controller_state(controller)
	return snapshot


# Synchronous owner-only comparison. Each complete entity and each remaining
# canonical section contributes its engine value digest. Hashing the compact
# digest list avoids JSON projection and serializing every static capability
# record in a large forest on the render thread. Archive bytes retain their
# separate cryptographic checkpoint checksum.
static func autosave_checksum(world, controller) -> String:
	return finish_autosave_checksum(autosave_checksum_state(world, controller))


static func autosave_checksum_state(world, controller, defer_resources: bool = false) -> Dictionary:
	var trace_enabled := "--profile-autosave-capture" in OS.get_cmdline_user_args()
	var trace := {}
	var trace_started := Time.get_ticks_usec() if trace_enabled else 0
	var state := canonical(world, controller.tick_index, controller, false)
	if trace_enabled: trace["view_us"] = Time.get_ticks_usec() - trace_started
	var world_state: Dictionary = state["world"]
	for field in world_state:
		var field_started := Time.get_ticks_usec() if trace_enabled else 0
		if defer_resources and field == "resources":
			world_state[field] = PackedInt64Array()
		elif field in ["units", "embarked_units", "resources", "buildings", "projectiles", "resolved_projectiles", "static_obstructions"]:
			world_state[field] = _autosave_entity_digests(world_state[field])
		else:
			world_state[field] = hash(world_state[field])
		if trace_enabled: trace[field] = Time.get_ticks_usec() - field_started
	for field in state["controller"]:
		state["controller"][field] = hash(state["controller"][field])
	if trace_enabled: print("AUTOSAVE_DIGEST ", JSON.stringify(trace))
	return state


static func finish_autosave_checksum(state: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(state))
	return hashing.finish().hex_encode()


static func _autosave_entity_digests(source: Array) -> PackedInt64Array:
	if ClassDB.class_exists("RoRReadModelKernel"):
		if autosave_digest_kernel == null: autosave_digest_kernel = ClassDB.instantiate("RoRReadModelKernel")
		if autosave_digest_kernel.has_method("autosave_entity_digests"):
			var native: PackedInt64Array = autosave_digest_kernel.autosave_entity_digests(source)
			if native.size() == source.size() * 2: return native
	var entities := source.duplicate()
	entities.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var digests := PackedInt64Array()
	digests.resize(entities.size() * 2)
	for index in range(entities.size()):
		var entity: Dictionary = entities[index]
		var record: Dictionary = entity
		for transient in ["selected", "formation_shared_motion", "_formation_path_cache", "formation_steering_target", "formation_shared_isolated"]:
			if record.has(transient):
				if is_same(record, entity): record = entity.duplicate()
				record.erase(transient)
		digests[index * 2] = int(record.get("id", -1))
		digests[index * 2 + 1] = hash(record)
	return digests


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


static func _world_state(world, detached: bool = true) -> Dictionary:
	var fog = world.get_fog_of_war()
	var economy: Dictionary = world.get_economy_snapshot()
	return {
		"map_size": world.map_size,
		"map_terrain_ids": world.map_terrain_ids.duplicate() if detached else world.map_terrain_ids,
		"map_reserved_foundation_cells": world.map_reserved_foundation_cells.duplicate() if detached else world.map_reserved_foundation_cells,
		"terrain_river_shape": world.terrain_elevation.river_shape.duplicate(true) if detached else world.terrain_elevation.river_shape,
		"simulation_rules": world.data_repository.rule_fingerprints.duplicate(),
		"terrain_restrictions": world.navigation_grid.terrain_restrictions.duplicate(true) if detached else world.navigation_grid.terrain_restrictions,
		"full_tech_tree": world.full_tech_tree_enabled,
		"simulation_seed": int(world.simulation_seed),
		"rng_state": int(world.simulation_rng.state),
		"next_entity_id": int(world.entity_id_sequence.peek()),
		"next_production_order_id": int(world.next_production_order_id),
		"units": _sorted_entities(world.get_units(), detached),
		"embarked_units": _sorted_entities(world.get_embarked_units(), detached),
		"farm_reseed_queues": world.economy_system.farm_reseed_queues_by_team.duplicate(true) if detached else world.economy_system.farm_reseed_queues_by_team,
		"resources": _sorted_entities(world.get_resources(), detached),
		"buildings": _sorted_entities(world.get_buildings(), detached),
		"projectiles": _sorted_entities(world.get_projectiles(), detached),
		"resolved_projectiles": _sorted_entities(world.get_resolved_projectiles(), detached),
		"ai_distress": world.ai_distress_system.canonical_state(),
		"static_obstructions": _sorted_entities(world.get_static_obstructions(), detached),
		"civilizations": world.civilization_by_team.duplicate(true) if detached else world.civilization_by_team,
		"players": world.player_registry.canonical_state(),
		"population": economy["population"],
		"population_points": economy["population_points"],
		"population_reserved": economy["population_reserved"],
		"population_cap": economy["population_cap"],
		"population_limit": economy["population_limit"],
		"population_housing": economy["population_housing"],
		"population_housing_enabled": economy["population_housing_enabled"],
		"resource_stockpiles": economy["resource_stockpiles"],
		"resource_ledger": economy["resource_ledger"],
		"trade": world.trade_system.canonical_state(),
		"resource_approach_slots": world.resource_approach_slots.duplicate(true) if detached else world.resource_approach_slots,
		"building_approach_slots": world.building_approach_slots.duplicate(true) if detached else world.building_approach_slots,
		"destination_reservations": world.destination_reservations.reservations.duplicate(true) if detached else world.destination_reservations.reservations,
		"terrain_vertex_levels": world.terrain_elevation.vertex_levels.duplicate(true) if detached else world.terrain_elevation.vertex_levels,
		"fog": _fog_state(fog, detached),
		"technology_team_states": world.technology_system.team_states.duplicate(true) if detached else world.technology_system.team_states,
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


static func _sorted_entities(source: Array, detached: bool = true) -> Array:
	if not detached: return source
	var result: Array = []
	for entity in source:
		var canonical_entity: Dictionary = entity.duplicate(detached)
		if detached:
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


static func _fog_state(fog, detached: bool = true) -> Dictionary:
	var players: Array = fog.states_by_player.keys()
	players.sort()
	var states: Dictionary = {}
	for player in players:
		if not detached:
			states[int(player)] = fog.states_by_player[player]
			continue
		var cells: Array = []
		for value in fog.states_by_player[player]:
			cells.append(int(value))
		states[int(player)] = cells
	return {
		"revision": int(fog.revision),
		"revisions_by_player": fog.revisions_by_player.duplicate(true) if detached else fog.revisions_by_player,
		"states_by_player": states,
		"personally_explored_by_player": fog.personally_explored_by_player.duplicate(true) if detached else fog.personally_explored_by_player,
		"allies_by_player": fog.allies_by_player.duplicate(true) if detached else fog.allies_by_player,
		"shared_vision_by_player": fog.shared_vision_by_player.duplicate(true) if detached else fog.shared_vision_by_player,
		"transient_visible_by_player": fog.transient_visible_by_player.duplicate(true) if detached else fog.transient_visible_by_player,
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
