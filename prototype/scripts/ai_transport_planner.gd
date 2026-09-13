class_name RoRAiTransportPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")

const BOARDING_MARGIN: float = 1.25
const MAX_UNLOAD_DISTANCE: float = 4.5
const COAST_NEIGHBOR_DISTANCE_SQUARED: float = 2.26


static func plan(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, formation_name: String = "RECTANGLE") -> Array:
	if int(snapshot.get("observer_team", -1)) != team or String(goal.get("type", "wait")) != "attack" or String(goal.get("target_domain", "land")) != "land":
		return []
	var own_units: Array = snapshot.get("units", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0)
	var transports: Array = own_units.filter(func(entity): return bool(entity.get("components", {}).get("cargo", {}).get("enabled", false)) and String(entity.get("task", "idle")) in ["idle", "hold"])
	var passengers: Array = own_units.filter(func(entity):
		return String(entity.get("movement_domain", "land")) == "land" and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) and String(entity.get("task", "idle")) in ["idle", "hold"]
	)
	transports.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var committed_passengers: Dictionary = {}
	var result: Array = []
	for transport_value in transports:
		var transport: Dictionary = transport_value
		var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
		var cargo_ids: Array = cargo.get("passenger_ids", [])
		if cargo_ids.is_empty():
			var capacity := maxi(0, int(cargo.get("capacity", 0)))
			var available: Array = passengers.filter(func(passenger): return not committed_passengers.has(int(passenger.get("id", -1))))
			available.sort_custom(func(left, right):
				var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(transport.get("pos", Vector2.ZERO)))
				var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(transport.get("pos", Vector2.ZERO)))
				return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and int(left.get("id", -1)) < int(right.get("id", -1)))
			)
			var in_range: Array[int] = []
			for passenger_value in available:
				var passenger: Dictionary = passenger_value
				var maximum_distance := float(passenger.get("footprint_radius", 0.3)) + float(transport.get("footprint_radius", 0.75)) + BOARDING_MARGIN
				if Vector2(passenger.get("pos", Vector2.ZERO)).distance_to(Vector2(transport.get("pos", Vector2.ZERO))) <= maximum_distance + 0.0001 and in_range.size() < capacity:
					in_range.append(int(passenger.get("id", -1)))
			if not in_range.is_empty():
				for passenger_id in in_range:
					committed_passengers[passenger_id] = true
				result.append(Commands.BoardCommand.new(tick, in_range, int(transport.get("id", -1))))
				continue
			var staging: Variant = _nearest_coastal_land(Vector2(transport.get("pos", Vector2.ZERO)), snapshot.get("navigation", {}))
			if staging is Vector2 and not available.is_empty():
				var staging_ids: Array[int] = []
				for passenger_value in available.slice(0, mini(capacity, available.size())):
					var passenger_id := int(passenger_value.get("id", -1))
					staging_ids.append(passenger_id)
					committed_passengers[passenger_id] = true
				result.append(Commands.FormationMoveCommand.new(tick, staging_ids, staging, formation_name))
			continue
		var landing: Variant = _landing_near(Vector2(goal.get("position", Vector2.ZERO)), snapshot.get("navigation", {}))
		if not landing is Vector2:
			continue
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(landing) <= MAX_UNLOAD_DISTANCE + 0.0001:
			result.append(Commands.UnloadCommand.new(tick, [int(transport.get("id", -1))], landing))
			continue
		var water_approach: Variant = _nearest_adjacent(Vector2(landing), snapshot.get("navigation", {}).get("water", []))
		if water_approach is Vector2:
			result.append(Commands.MoveCommand.new(tick, [int(transport.get("id", -1))], water_approach))
	return result


static func _nearest_coastal_land(origin: Vector2, navigation: Dictionary) -> Variant:
	var land: Array = navigation.get("land", [])
	var water: Array = navigation.get("water", [])
	var candidates: Array = land.filter(func(point): return _nearest_adjacent(Vector2(point), water) is Vector2)
	return _nearest(origin, candidates)


static func _landing_near(target: Vector2, navigation: Dictionary) -> Variant:
	var land: Array = navigation.get("land", [])
	var water: Array = navigation.get("water", [])
	var coastal: Array = land.filter(func(point): return _nearest_adjacent(Vector2(point), water) is Vector2)
	return _nearest(target, coastal)


static func _nearest_adjacent(origin: Vector2, points: Array) -> Variant:
	var nearby: Array = points.filter(func(point): return origin.distance_squared_to(Vector2(point)) <= COAST_NEIGHBOR_DISTANCE_SQUARED)
	return _nearest(origin, nearby)


static func _nearest(origin: Vector2, points: Array) -> Variant:
	if points.is_empty():
		return null
	var ordered: Array = points.duplicate()
	ordered.sort_custom(func(left, right):
		var left_point := Vector2(left)
		var right_point := Vector2(right)
		var left_distance := origin.distance_squared_to(left_point)
		var right_distance := origin.distance_squared_to(right_point)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left_point.x < right_point.x or (is_equal_approx(left_point.x, right_point.x) and left_point.y < right_point.y)))
	)
	return Vector2(ordered[0])
