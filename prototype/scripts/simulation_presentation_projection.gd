extends RefCounted

# Legal field projections shared by all presentation stages.
const EntityComponents := preload("res://scripts/entity_components.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")

static func _presentation_entity(entity: Dictionary, observer_team: int = 0, compact: bool = false, compact_render: bool = false, compact_render_projector: Callable = Callable()) -> Dictionary:
	if compact:
		return _compact_ai_entity(entity, observer_team)
	if compact_render:
		if compact_render_projector.is_valid():
			return compact_render_projector.call(entity)
		return _compact_render_entity(entity)
	var result: Dictionary = entity.duplicate(true)
	EntityComponents.project_dynamic(result)
	result.erase("selected")
	result.erase("formation_shared_motion")
	result.erase("_formation_path_cache")
	result.erase("formation_steering_target")
	result.erase("formation_shared_isolated")
	if observer_team > 0 and int(entity.get("team", 0)) != observer_team:
		for private_key in ["production_queue", "production_progress", "command_options", "rally_point", "rally_point_set"]:
			result.erase(private_key)
		result.get("components", {}).erase("production")
		result.get("components", {}).erase("order")
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
	return ReadContract.render(entity)


static func _compact_control_entity(entity: Dictionary, observer_team: int = 0, compact_render_projector: Callable = Callable(), rendered: Dictionary = {}) -> Dictionary:
	# Selected objects need gameplay/HUD data, but not authoritative paths,
	# destination reservations, AI bookkeeping or the full technology payload.
	# Keeping this explicit contract avoids two deep copies of large unit records
	# every presentation tick while preserving every player-facing control field.
	var base: Dictionary = rendered if not rendered.is_empty() else (compact_render_projector.call(entity) if compact_render_projector.is_valid() else _compact_render_entity(entity))
	if ReadContract.native_enabled and ClassDB.class_exists("RoRReadModelKernel"):
		if ReadContract.native_kernel == null: ReadContract.native_kernel = ClassDB.instantiate("RoRReadModelKernel")
		if ReadContract.native_kernel.has_method("project_control"):
			return ReadContract.native_kernel.project_control(entity, base, observer_team, ReadContract.CONTROL_FIELDS, ReadContract.PRIVATE_TRADE_FIELDS)
	var result: Dictionary = base.duplicate(true)
	for key in ReadContract.CONTROL_FIELDS:
		if entity.has(key):
			result[key] = entity[key]
	if entity.has("production_queue") and (observer_team <= 0 or int(entity.get("team", 0)) == observer_team):
		result["production_queue"] = entity.get("production_queue", []).duplicate(true)
	var source_components: Dictionary = entity.get("components", {})
	var components: Dictionary = result.get("components", {}).duplicate(true)
	for component_name in ["combat", "conversion", "healing", "resource_carrier"]:
		var component: Dictionary = EntityComponents.component_view(entity, component_name)
		if not component.is_empty():
			# component_view already owns a detached result.
			components[component_name] = component
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
	if observer_team > 0 and int(entity.get("team", 0)) != observer_team:
		for private_key in ["production_progress", "rally_point", "rally_point_set", "resource_id", "dropoff_id", "worker_role_source_unit_id", "diagnostic_reason"]:
			result.erase(private_key)
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
	return ReadContract.ai(entity, observer_team)


static func _sort_entity_copies(source: Array) -> Array:
	var last_id := -9223372036854775807
	for entity_value in source:
		var entity_id := int(entity_value.get("id", -1))
		if entity_id < last_id:
			var sorted: Array = source.duplicate()
			sorted.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
			return sorted
		last_id = entity_id
	# These arrays are local snapshot projections. Returning their existing
	# container is safe and avoids an allocation when the authoritative stores
	# have already supplied stable ID order.
	return source


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


static func _production_overview(world, observer_team: int) -> Array:
	var result: Array = []
	if observer_team <= 0:
		return result
	# Use the existing active producer index, never scan units/resources or idle buildings.
	for id_value in world.production_system.active_building_ids:
		var building: Variant = world.find_building(int(id_value))
		if building == null or int(building.get("team", 0)) != observer_team or float(building.get("hp", 0)) <= 0:
			continue
		var queue: Array = building.get("production_queue", [])
		if queue.is_empty():
			continue
		var order: Dictionary = queue[0]
		var kind := String(order.get("kind", ""))
		var source_id := -1
		if String(order.get("order_type", "unit")) == "unit":
			var base_id := int(world.data_repository.identifiers(kind).get("source_unit_id", -1))
			source_id = int(world.technology_system.resolved_unit_id(observer_team, base_id))
		result.append({
			"id": int(building["id"]),
			"team": observer_team,
			"kind": String(building.get("kind", "")),
			"components": {"ownership": {"civilization_id": int(world.civilization_by_team.get(observer_team, 13))}},
			"production_queue": [{"id": int(order.get("id", -1)), "order_type": String(order.get("order_type", "unit")), "kind": kind, "source_unit_id": source_id, "technology_id": int(order.get("technology_id", -1)), "status": String(order.get("status", "queued")), "duration": float(order.get("duration", 0.05)), "progress": float(order.get("progress", 0))}],
		})
	return result
