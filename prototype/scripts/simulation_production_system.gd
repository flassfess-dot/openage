class_name RoRSimulationProductionSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const Footprint := preload("res://scripts/footprint.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var next_order_id: int = 1
var last_production_failure: String = ""
var last_research_failure: String = ""
var last_research_message: String = ""
var last_completed_research_id: int = -1


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	next_order_id = 1
	last_production_failure = ""
	last_research_failure = ""
	last_research_message = ""
	last_completed_research_id = -1


func advance(context: Dictionary) -> void:
	update(float(context.get("delta", 0.0)))


func train_unit(team: int, kind: String, near: Vector2) -> bool:
	var building: Variant = production_building_for(team, kind)
	var enforce_runtime_rules := true
	# The current prototype HUD has no building-selection/production panel yet.
	# Keep its no-building command operational through one explicit adapter; all
	# commands naming a producer use the authoritative RoR location contract.
	if building == null and world.data_repository.is_configured():
		building = production_building_for(team)
		enforce_runtime_rules = false
	if building == null:
		last_production_failure = "no_production_building"
		return false
	set_rally_point(int(building["id"]), near)
	return enqueue_unit(int(building["id"]), team, kind, enforce_runtime_rules) != null


func production_building_for(team: int, kind: String = "") -> Variant:
	var candidates: Array = world.get_buildings().filter(func(building): return int(building.get("team", 0)) == team and float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "complete")) == "complete")
	if not kind.is_empty():
		candidates = candidates.filter(func(building): return _production_target_failure(building, team, kind) == "")
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	return candidates[0]


func enqueue_unit(building_id: int, team: int, kind: String, enforce_runtime_rules: bool = true) -> Variant:
	last_production_failure = ""
	var building: Variant = world.find_building(building_id)
	var availability := _unit_availability(building, team, kind, enforce_runtime_rules)
	last_production_failure = String(availability.get("reason", ""))
	if not bool(availability.get("accepted", false)):
		return null
	var queue: Array = building.get("production_queue", [])
	var cost: Dictionary = availability.get("cost", {})
	var population_cost := int(availability.get("population_cost", 0))
	world.economy_system.spend(team, cost)
	world.economy_system.reserve_population(team, population_cost)
	var duration := float(availability.get("duration", 0.05))
	var order := {
		"id": next_order_id,
		"order_type": "unit",
		"kind": kind,
		"team": team,
		"cost": cost.duplicate(true),
		"population_cost": population_cost,
		"duration": duration,
		"progress": 0.0,
		"status": "queued",
	}
	next_order_id += 1
	queue.append(order)
	_sync_queue(building, queue)
	world.emit_domain_event("production_queued", {
		"order_id": int(order["id"]),
		"building_id": building_id,
		"team": team,
		"unit_kind": kind,
		"cost": cost.duplicate(true),
		"population_reserved": population_cost,
	})
	return order


func unit_availability(building_id: int, team: int, kind: String) -> Dictionary:
	return _unit_availability(world.find_building(building_id), team, kind, true)


func unit_options(building_id: int, team: int) -> Array:
	var building: Variant = world.find_building(building_id)
	if building == null or not world.data_repository.is_configured():
		return []
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	var civilization_id := int(world.civilization_by_team.get(team, 13))
	var result: Array = []
	for alias in world.data_repository.archetype_aliases("unit"):
		var expected_location: int = world.data_repository.train_location_unit_id(alias, civilization_id)
		if expected_location < 0 or not lineage.has(expected_location):
			continue
		var option := _unit_availability(building, team, alias, true)
		if String(option.get("reason", "")) == "unit_replaced":
			continue
		result.append(option)
	result.sort_custom(func(left, right): return String(left.get("kind", "")) < String(right.get("kind", "")))
	return result


func _unit_availability(building: Variant, team: int, kind: String, enforce_runtime_rules: bool) -> Dictionary:
	var result := {
		"kind": kind,
		"source_unit_id": -1,
		"icon_id": -1,
		"button_id": -1,
		"accepted": false,
		"reason": "",
		"cost": {},
		"population_cost": 0,
		"duration": 0.0,
		"behavior_tags": [],
	}
	if world.data_repository.has_archetype(kind):
		result["behavior_tags"] = world.data_repository.behavior_tags(kind)
		var base_source_id := int(world.data_repository.identifiers(kind).get("source_unit_id", -1))
		var resolved_source_id: int = int(world.technology_system.resolved_unit_id(team, base_source_id))
		var source: Dictionary = world.object_record_by_id(resolved_source_id, team)
		result["source_unit_id"] = resolved_source_id
		result["icon_id"] = int(source.get("interface", {}).get("icon_id", -1))
		result["button_id"] = int(source.get("interface", {}).get("button_id", -1))
	if building == null or int(building.get("team", 0)) != team or String(building.get("state", "complete")) != "complete" or float(building.get("hp", 0.0)) <= 0.0:
		result["reason"] = "invalid_production_building"
		return result
	if enforce_runtime_rules:
		var target_failure := _production_target_failure(building, team, kind)
		if not target_failure.is_empty():
			result["reason"] = target_failure
			return result
	var cost: Dictionary = world.unit_resource_cost(kind, team)
	var population_cost: int = world.unit_population_cost(kind, team)
	var duration := maxf(0.05, float(world.unit_stats(kind).get("creation_time", world.object_record_for(kind, team).get("production", {}).get("creation_time", 1.0))))
	result["cost"] = cost.duplicate(true)
	result["population_cost"] = population_cost
	result["duration"] = duration
	if building.get("production_queue", []).size() >= 15:
		result["reason"] = "queue_full"
		return result
	if not world.economy_system.can_afford(team, cost):
		result["reason"] = "insufficient_resources"
		return result
	if not world.economy_system.can_reserve_population(team, population_cost):
		result["reason"] = "population_cap"
		return result
	result["accepted"] = true
	return result


func _production_target_failure(building: Dictionary, team: int, kind: String) -> String:
	var repository = world.data_repository
	if not repository.is_configured():
		return ""
	if not repository.has_archetype(kind) or repository.category(kind) != "unit":
		return "unknown_unit_type"
	var civilization_id := int(world.civilization_by_team.get(team, 13))
	var expected_location: int = repository.train_location_unit_id(kind, civilization_id)
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	if expected_location >= 0 and not lineage.has(expected_location):
		return "wrong_production_location"
	var source_unit_id := int(repository.identifiers(kind).get("source_unit_id", -1))
	if source_unit_id >= 0 and not world.is_object_available(team, source_unit_id):
		return "unit_unavailable"
	var replacement_alias := String(repository.runtime_metadata(kind).get("production_replaced_by", ""))
	if not replacement_alias.is_empty():
		var replacement_source_id := int(repository.identifiers(replacement_alias).get("source_unit_id", -1))
		if replacement_source_id >= 0 and world.is_object_available(team, replacement_source_id):
			return "unit_replaced"
	return ""


func enqueue_research(building_id: int, team: int, technology_id: int) -> Variant:
	last_research_failure = ""
	var building: Variant = world.find_building(building_id)
	var availability := _research_availability(building, team, technology_id)
	last_research_failure = String(availability.get("reason", ""))
	if not bool(availability.get("accepted", false)):
		return null
	var queue: Array = building.get("production_queue", [])
	var cost: Dictionary = availability.get("cost", {})
	world.economy_system.spend(team, cost)
	world.technology_system.mark_researching(team, technology_id)
	var order := {
		"id": next_order_id,
		"order_type": "research",
		"technology_id": technology_id,
		"team": team,
		"cost": cost.duplicate(true),
		"population_cost": 0,
		"duration": float(availability.get("duration", 0.05)),
		"progress": 0.0,
		"status": "queued",
	}
	next_order_id += 1
	queue.append(order)
	_sync_queue(building, queue)
	building["components"]["technology"]["active_research_id"] = technology_id
	world.emit_domain_event("research_queued", {
		"order_id": int(order["id"]),
		"building_id": building_id,
		"team": team,
		"technology_id": technology_id,
		"cost": cost.duplicate(true),
	})
	return order


func research_availability(building_id: int, team: int, technology_id: int) -> Dictionary:
	return _research_availability(world.find_building(building_id), team, technology_id)


func research_options(building_id: int, team: int) -> Array:
	var building: Variant = world.find_building(building_id)
	if building == null:
		return []
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	var ids: Array = world.object_catalog_data.get("technologies", {}).keys()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	var result: Array = []
	for id_value in ids:
		var technology_id := int(id_value)
		var record: Dictionary = world.technology_system.technology(technology_id)
		if not lineage.has(int(record.get("research_location_id", -1))):
			continue
		if int(record.get("language", {}).get("name_id", 0)) <= 0 or float(record.get("research_time", 0.0)) <= 0.0:
			continue
		var rule_reason: String = world.technology_system.can_research(team, technology_id, int(record.get("research_location_id", -1)))
		if rule_reason in ["already_researched", "already_researching", "technology_disabled", "missing_prerequisites"]:
			continue
		result.append(_research_availability(building, team, technology_id))
	return result


func _research_availability(building: Variant, team: int, technology_id: int) -> Dictionary:
	var result := {
		"technology_id": technology_id,
		"accepted": false,
		"reason": "",
		"cost": {},
		"duration": 0.0,
	}
	if building == null or int(building.get("team", 0)) != team or String(building.get("state", "complete")) != "complete" or float(building.get("hp", 0.0)) <= 0.0:
		result["reason"] = "invalid_research_building"
		return result
	var record: Dictionary = world.technology_system.technology(technology_id)
	var expected_location := int(record.get("research_location_id", -1))
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	if expected_location >= 0 and not lineage.has(expected_location):
		result["reason"] = "wrong_research_location"
		return result
	var cost: Dictionary = world.technology_system.research_cost(team, technology_id)
	result["cost"] = cost.duplicate(true)
	result["duration"] = world.technology_system.research_time(team, technology_id)
	var rule_reason: String = world.technology_system.can_research(team, technology_id, expected_location)
	if not rule_reason.is_empty():
		result["reason"] = rule_reason
		return result
	if building.get("production_queue", []).size() >= 15:
		result["reason"] = "queue_full"
		return result
	if not world.economy_system.can_afford(team, cost):
		result["reason"] = "insufficient_resources"
		return result
	result["accepted"] = true
	return result


func update(delta: float) -> void:
	for building in world.get_buildings():
		if float(building.get("hp", 0.0)) <= 0.0 or String(building.get("state", "complete")) != "complete":
			continue
		var queue: Array = building.get("production_queue", [])
		if queue.is_empty():
			building["production_progress"] = 0.0
			continue
		var order: Dictionary = queue[0]
		order["status"] = "training"
		order["progress"] = minf(float(order["duration"]), float(order.get("progress", 0.0)) + maxf(0.0, delta))
		queue[0] = order
		building["production_progress"] = float(order["progress"]) / maxf(0.05, float(order["duration"]))
		if float(order["progress"]) + 0.000001 < float(order["duration"]):
			building["production_queue"] = queue
			continue
		if String(order.get("order_type", "unit")) == "research":
			_complete_research(building, queue, order)
			continue
		_complete_unit(building, queue, order)


func _complete_research(building: Dictionary, queue: Array, order: Dictionary) -> void:
	queue.pop_front()
	var team := int(order["team"])
	var technology_id := int(order["technology_id"])
	world.apply_technology_commands(team, world.technology_system.complete_research(team, technology_id))
	last_completed_research_id = technology_id
	last_research_message = "research_complete:%d" % technology_id
	world.emit_domain_event("research_complete", {
		"technology_id": technology_id,
		"team": team,
		"building_id": int(building.get("id", -1)),
	})
	_sync_queue(building, queue)
	building["components"]["technology"]["active_research_id"] = -1
	building["components"]["technology"]["researched_ids"] = world.technology_system.researched_ids(team)


func _complete_unit(building: Dictionary, queue: Array, order: Dictionary) -> void:
	var team := int(order["team"])
	if world.economy_system.get_population(team) + int(order["population_cost"]) > world.economy_system.get_population_cap(team):
		order["status"] = "blocked_population"
		queue[0] = order
		building["production_queue"] = queue
		return
	var spawn: Variant = free_spawn_position(building, String(order["kind"]))
	if not spawn is Vector2:
		order["status"] = "blocked_spawn"
		queue[0] = order
		building["production_queue"] = queue
		return
	queue.pop_front()
	world.economy_system.release_reserved_population(team, int(order["population_cost"]))
	var trained: Dictionary = world.add_unit(team, String(order["kind"]), spawn, false)
	trained["production_order_id"] = int(order["id"])
	world.emit_domain_event("unit_produced", {
		"order_id": int(order["id"]),
		"building_id": int(building.get("id", -1)),
		"entity_id": int(trained.get("id", -1)),
		"team": team,
		"unit_kind": String(order["kind"]),
	})
	var rally: Vector2 = building.get("rally_point", building["pos"])
	# The source game leaves a newly trained unit at its valid exit slot until
	# the player sets a rally point. A building's own (blocked) center is our
	# sentinel for that default and must never become a movement destination.
	if rally.distance_squared_to(Vector2(building["pos"])) > 0.04 and trained["pos"].distance_squared_to(rally) > 0.04:
		world.assign_command_move([trained], rally)
	_sync_queue(building, queue)


func cancel(building_id: int, queue_index: int = 0) -> bool:
	var building: Variant = world.find_building(building_id)
	if building == null:
		return false
	var queue: Array = building.get("production_queue", [])
	if queue_index < 0 or queue_index >= queue.size():
		return false
	var order: Dictionary = queue[queue_index]
	var team := int(order.get("team", 0))
	world.economy_system.refund(team, order.get("cost", {}))
	if String(order.get("order_type", "unit")) == "research":
		world.technology_system.cancel_research(team, int(order.get("technology_id", -1)))
	world.economy_system.release_reserved_population(team, int(order.get("population_cost", 0)))
	queue.remove_at(queue_index)
	_sync_queue(building, queue)
	building["components"]["technology"]["active_research_id"] = -1 if queue.is_empty() or String(queue[0].get("order_type", "unit")) != "research" else int(queue[0].get("technology_id", -1))
	world.emit_domain_event("production_cancelled", {
		"order_id": int(order.get("id", -1)),
		"building_id": building_id,
		"team": team,
		"order_type": String(order.get("order_type", "unit")),
		"refunded_cost": order.get("cost", {}).duplicate(true),
	})
	return true


func set_rally_point(building_id: int, target: Vector2) -> bool:
	var building: Variant = world.find_building(building_id)
	if building == null:
		return false
	building["rally_point"] = Coordinates.clamp_world(target, world.get_map_size())
	return true


func free_spawn_position(building: Dictionary, kind: String) -> Variant:
	var unit_footprint := Footprint.mobile(kind, world.unit_stats(kind))
	var unit_radius := float(unit_footprint.get("movement_radius", 0.3))
	var source: Dictionary = world.object_record_for(kind, int(building.get("team", 0)))
	var terrain_restriction := int(source.get("links", {}).get("terrain_restriction", world.unit_stats(kind).get("terrain_restriction", -1)))
	var movement_domain := "water" if terrain_restriction == 3 else "land"
	var half_size: Vector2 = building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
	for slot_index in range(24):
		var angle := TAU * float(slot_index) / 24.0
		var candidate := Coordinates.clamp_world(Vector2(building["pos"]) + Vector2(cos(angle) * (half_size.x + unit_radius + 0.35), sin(angle) * (half_size.y + unit_radius + 0.35)), world.get_map_size())
		if not world.get_navigation_grid().is_position_walkable_for(candidate, unit_radius, movement_domain, terrain_restriction):
			continue
		var neighbors: Array = world.query_units_near(candidate, unit_radius + 0.7)
		if neighbors.any(func(unit): return float(unit.get("hp", 0.0)) > 0.0 and Vector2(unit["pos"]).distance_to(candidate) < float(unit.get("footprint_radius", 0.3)) + unit_radius + 0.06):
			continue
		return candidate
	return null


func _sync_queue(building: Dictionary, queue: Array) -> void:
	building["production_queue"] = queue
	building["components"]["production"]["queue"] = queue
	building["production_progress"] = 0.0 if queue.is_empty() else float(queue[0].get("progress", 0.0)) / maxf(0.05, float(queue[0]["duration"]))
