class_name RoRTransportSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")

const BOARDING_MARGIN: float = 1.25
const MAX_UNLOAD_DISTANCE: float = 4.5

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var embarked_units: Dictionary = {}
var last_failure: String = ""


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	embarked_units.clear()
	last_failure = ""


func is_transport(entity: Dictionary) -> bool:
	return bool(entity.get("components", {}).get("cargo", {}).get("enabled", false))


func passenger_count(transport: Dictionary) -> int:
	return transport.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()


func all_embarked_units() -> Array:
	var ids: Array = embarked_units.keys()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	var result: Array = []
	for id_value in ids:
		result.append(embarked_units[id_value])
	return result


func board(passengers: Array, transport: Dictionary) -> String:
	last_failure = validate_board(passengers, transport)
	if not last_failure.is_empty():
		return last_failure
	var cargo: Dictionary = transport["components"]["cargo"]
	var passenger_ids: Array = cargo.get("passenger_ids", []).duplicate()
	var ordered: Array = passengers.duplicate()
	ordered.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	for passenger_value in ordered:
		var passenger: Dictionary = passenger_value
		world.halt_unit(passenger, "board_transport")
		passenger["selected"] = false
		passenger["transported_by_id"] = int(transport.get("id", -1))
		passenger["cargo_state"] = "embarked"
		var passenger_id := int(passenger.get("id", -1))
		embarked_units[passenger_id] = passenger
		passenger_ids.append(passenger_id)
		_remove_active_unit(passenger_id)
		world.emit_domain_event("unit_boarded", {
			"passenger_id": passenger_id,
			"transport_id": int(transport.get("id", -1)),
			"passenger_team": int(passenger.get("team", 0)),
		})
	cargo["passenger_ids"] = passenger_ids
	cargo["count"] = passenger_ids.size()
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	return ""


func validate_board(passengers: Array, transport: Dictionary) -> String:
	if transport == null or float(transport.get("hp", 0.0)) <= 0.0 or not is_transport(transport):
		return "invalid_transport"
	if passengers.is_empty():
		return "no_eligible_passengers"
	var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
	var existing: Array = cargo.get("passenger_ids", [])
	if existing.size() + passengers.size() > int(cargo.get("capacity", 0)):
		return "transport_full"
	var seen: Dictionary = {}
	for passenger_value in passengers:
		var passenger: Dictionary = passenger_value
		var passenger_id := int(passenger.get("id", -1))
		if passenger_id < 0 or seen.has(passenger_id) or embarked_units.has(passenger_id):
			return "invalid_passenger"
		seen[passenger_id] = true
		if float(passenger.get("hp", 0.0)) <= 0.0 or String(passenger.get("death_phase", "alive")) != "alive":
			return "invalid_passenger"
		if int(passenger.get("team", 0)) != int(transport.get("team", 0)):
			return "passenger_not_owned"
		var allowed_domains: Array = cargo.get("allowed_domains", ["land"])
		if String(passenger.get("movement_domain", "land")) not in allowed_domains:
			return "passenger_domain_forbidden"
		var maximum_distance := float(passenger.get("footprint_radius", 0.3)) + float(transport.get("footprint_radius", 0.75)) + BOARDING_MARGIN
		if Vector2(passenger.get("pos", Vector2.ZERO)).distance_to(Vector2(transport.get("pos", Vector2.ZERO))) > maximum_distance + 0.0001:
			return "passenger_not_in_range"
	return ""


func unload(transports: Array, target: Vector2, requested_passenger_ids: Array = []) -> String:
	last_failure = ""
	if transports.is_empty():
		return "invalid_transport"
	var ordered: Array = transports.duplicate()
	ordered.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var plans: Array = []
	var reserved: Array = []
	for transport_value in ordered:
		var transport: Dictionary = transport_value
		if float(transport.get("hp", 0.0)) <= 0.0 or not is_transport(transport):
			return "invalid_transport"
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(target) > MAX_UNLOAD_DISTANCE + 0.0001:
			return "landing_too_far"
		var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
		var cargo_ids: Array = cargo.get("passenger_ids", [])
		var release_ids: Array = cargo_ids.duplicate()
		if not requested_passenger_ids.is_empty():
			release_ids = cargo_ids.filter(func(id): return int(id) in requested_passenger_ids)
			if release_ids.is_empty():
				return "invalid_cargo_selection"
		if release_ids.is_empty():
			return "transport_empty"
		release_ids.sort_custom(func(left, right): return int(left) < int(right))
		for passenger_id_value in release_ids:
			var passenger_id := int(passenger_id_value)
			if not embarked_units.has(passenger_id):
				return "invalid_cargo_state"
			var passenger: Dictionary = embarked_units[passenger_id]
			var landing: Variant = _landing_position(transport, passenger, target, reserved)
			if not landing is Vector2:
				return "landing_blocked"
			plans.append({"transport": transport, "passenger": passenger, "position": landing})
			reserved.append({"position": landing, "radius": float(passenger.get("footprint_radius", 0.3))})
	for plan_value in plans:
		var plan: Dictionary = plan_value
		_restore_passenger(plan["transport"], plan["passenger"], plan["position"])
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	return ""


func destroy_cargo(transport: Dictionary) -> void:
	if not is_transport(transport):
		return
	var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
	var ids: Array = cargo.get("passenger_ids", []).duplicate()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	for passenger_id_value in ids:
		var passenger_id := int(passenger_id_value)
		var passenger: Variant = embarked_units.get(passenger_id)
		if passenger == null:
			continue
		passenger["hp"] = 0.0
		passenger["death_phase"] = "removed"
		passenger["removed"] = true
		if not bool(passenger.get("population_released", false)):
			world.economy_system.add_population(int(passenger.get("team", 0)), -int(passenger.get("population_cost", 0)))
			passenger["population_released"] = true
		embarked_units.erase(passenger_id)
		world.emit_domain_event("cargo_destroyed", {
			"passenger_id": passenger_id,
			"transport_id": int(transport.get("id", -1)),
			"passenger_team": int(passenger.get("team", 0)),
		})
	cargo["passenger_ids"] = []
	cargo["count"] = 0


func canonical_state() -> Array:
	var result: Array = []
	for passenger_value in all_embarked_units():
		var passenger: Dictionary = passenger_value.duplicate(true)
		passenger.erase("selected")
		result.append(passenger)
	return result


func _landing_position(transport: Dictionary, passenger: Dictionary, target: Vector2, reserved: Array) -> Variant:
	var candidates: Array[Vector2] = [Coordinates.clamp_world(target, world.map_size)]
	for ring in range(1, 10):
		var distance := float(ring) * 0.5
		for offset in [Vector2(distance, 0), Vector2(0, distance), Vector2(-distance, 0), Vector2(0, -distance), Vector2(distance, distance), Vector2(-distance, distance), Vector2(-distance, -distance), Vector2(distance, -distance)]:
			candidates.append(Coordinates.clamp_world(target + offset, world.map_size))
	var radius := float(passenger.get("footprint_radius", 0.3))
	var domain := String(passenger.get("movement_domain", "land"))
	var restriction_id := int(passenger.get("terrain_restriction", -1))
	for candidate in candidates:
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(candidate) > MAX_UNLOAD_DISTANCE + 0.0001:
			continue
		if not world.navigation_grid.is_position_walkable_for(candidate, radius, domain, restriction_id):
			continue
		if _overlaps_active_unit(candidate, radius) or _overlaps_reserved(candidate, radius, reserved):
			continue
		return candidate
	return null


func _overlaps_active_unit(position: Vector2, radius: float) -> bool:
	for unit_value in world.units:
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var separation := radius + float(unit.get("footprint_radius", 0.3)) + 0.02
		if position.distance_squared_to(Vector2(unit.get("pos", Vector2.ZERO))) < separation * separation:
			return true
	return false


func _overlaps_reserved(position: Vector2, radius: float, reserved: Array) -> bool:
	for item_value in reserved:
		var item: Dictionary = item_value
		var separation := radius + float(item.get("radius", 0.3)) + 0.02
		if position.distance_squared_to(Vector2(item.get("position", Vector2.ZERO))) < separation * separation:
			return true
	return false


func _restore_passenger(transport: Dictionary, passenger: Dictionary, position: Vector2) -> void:
	var passenger_id := int(passenger.get("id", -1))
	var cargo: Dictionary = transport["components"]["cargo"]
	var ids: Array = cargo.get("passenger_ids", []).duplicate()
	ids.erase(passenger_id)
	cargo["passenger_ids"] = ids
	cargo["count"] = ids.size()
	embarked_units.erase(passenger_id)
	passenger["transported_by_id"] = -1
	passenger["cargo_state"] = "deployed"
	passenger["pos"] = position
	passenger["previous_pos"] = position
	passenger["target"] = position
	passenger["destination"] = position
	passenger["path"] = []
	passenger["path_index"] = 0
	passenger["path_status"] = "idle"
	passenger["reserved_destination"] = null
	passenger["actual_velocity"] = Vector2.ZERO
	passenger["desired_velocity"] = Vector2.ZERO
	passenger["task"] = "idle"
	passenger["selected"] = false
	passenger["elevation"] = world.elevation_at(position)
	world.restore_unit_from_transport(passenger)
	EntityComponents.sync_dynamic(passenger)
	world.emit_domain_event("unit_unloaded", {
		"passenger_id": passenger_id,
		"transport_id": int(transport.get("id", -1)),
		"passenger_team": int(passenger.get("team", 0)),
		"position": position,
	})


func _remove_active_unit(passenger_id: int) -> void:
	world.detach_unit_for_transport(passenger_id)
