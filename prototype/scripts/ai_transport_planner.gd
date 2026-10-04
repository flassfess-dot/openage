class_name RoRAiTransportPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")

const BOARDING_MARGIN: float = 1.25
const MAX_UNLOAD_DISTANCE: float = 4.5
const COAST_NEIGHBOR_DISTANCE_SQUARED: float = 2.26


static func plan(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, formation_name: String = "RECTANGLE", reserved_unit_ids: Dictionary = {}) -> Array:
	if int(snapshot.get("observer_team", -1)) != team or String(goal.get("type", "wait")) != "attack" or String(goal.get("target_domain", "land")) != "land":
		return []
	var allies: Array = snapshot.get("player_state", {}).get("mutual_allies", snapshot.get("player_state", {}).get("allies", [team]))
	var own_units: Array = snapshot.get("units", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0)
	var transports: Array = snapshot.get("units", []).filter(func(entity): return int(entity.get("team", 0)) in allies and float(entity.get("hp", 0.0)) > 0.0 and bool(entity.get("components", {}).get("cargo", {}).get("enabled", false)) and String(entity.get("task", "idle")) in ["idle", "hold"] and (int(entity.get("team", 0)) == team or bool(entity.get("components", {}).get("cargo", {}).get("allow_allied", true))))
	if transports.is_empty():
		return []
	var navigation: Dictionary = snapshot.get("navigation", {})
	var target_land := _known_land_component(Vector2(goal.get("position", Vector2.ZERO)), navigation)
	var has_off_target_assault := own_units.any(func(entity): return String(entity.get("movement_domain", "land")) == "land" and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) and not target_land.has(Vector2i(Vector2(entity.get("pos", Vector2.ZERO)))))
	var passengers: Array = own_units.filter(func(entity):
		return not reserved_unit_ids.has(int(entity.get("id", -1))) and String(entity.get("movement_domain", "land")) == "land" and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", []) or int(entity.get("scenario_object_id", -1)) >= 0) and String(entity.get("task", "idle")) in ["idle", "hold"] and (not has_off_target_assault or not target_land.has(Vector2i(Vector2(entity.get("pos", Vector2.ZERO)))))
	)
	passengers.append_array(snapshot.get("units", []).filter(func(entity): return int(entity.get("team", -1)) == 0 and float(entity.get("hp", 0.0)) > 0.0 and String(entity.get("movement_domain", "land")) == "land" and "capturable" in entity.get("behavior_tags", []) and not reserved_unit_ids.has(int(entity.get("id", -1)))))
	transports.sort_custom(func(left, right):
		var left_own := int(left.get("team", 0)) == team
		var right_own := int(right.get("team", 0)) == team
		return left_own if left_own != right_own else int(left.get("id", -1)) < int(right.get("id", -1))
	)
	var committed_passengers: Dictionary = {}
	var result: Array = []
	var landing_computed := false
	var target_landing: Variant = null
	for transport_value in transports:
		var transport: Dictionary = transport_value
		# Let accepted boarding approaches complete before sailing or restaging.
		if own_units.any(func(unit): return String(unit.get("task", "")) == "board" and int(unit.get("target_id", -1)) == int(transport["id"])):
			continue
		var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
		var cargo_ids: Array = cargo.get("passenger_ids", [])
		var own_transport := int(transport.get("team", 0)) == team
		var occupied := cargo_ids.size() if own_transport else int(cargo.get("count", -1))
		if occupied < 0:
			continue
		if occupied == 0 or not own_transport:
			var capacity := maxi(0, int(cargo.get("capacity", 0)) - occupied)
			if capacity <= 0:
				continue
			var available: Array = passengers.filter(func(passenger): return not committed_passengers.has(int(passenger.get("id", -1))) and (int(passenger.get("team", -1)) != 0 or bool(cargo.get("allow_artifacts", true))))
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
				# Nearby troops can walk the last metres along a diagonal beach.
				if own_transport:
					for passenger in available:
						var passenger_id := int(passenger["id"])
						if in_range.size() < capacity and passenger_id not in in_range and Vector2(passenger["pos"]).distance_to(Vector2(transport["pos"])) <= MAX_UNLOAD_DISTANCE:
							in_range.append(passenger_id)
				for passenger_id in in_range:
					committed_passengers[passenger_id] = true
				result.append(Commands.BoardCommand.new(tick, in_range, int(transport.get("id", -1))))
				continue
			if not own_transport:
				continue
			var staging: Variant = _nearest_coastal_land(Vector2(transport.get("pos", Vector2.ZERO)), snapshot.get("navigation", {}))
			var movable: Array = available.filter(func(passenger): return int(passenger.get("team", -1)) == team)
			if staging is Vector2 and not movable.is_empty():
				var staging_ids: Array[int] = []
				for passenger_value in movable.slice(0, mini(capacity, movable.size())):
					var passenger_id := int(passenger_value.get("id", -1))
					staging_ids.append(passenger_id)
					committed_passengers[passenger_id] = true
				result.append(Commands.FormationMoveCommand.new(tick, staging_ids, staging, formation_name))
			continue
		var capacity_left := maxi(0, int(cargo.get("capacity", 0)) - occupied)
		if capacity_left > 0:
			var waiting: Array = passengers.filter(func(passenger): return int(passenger.get("team", -1)) == team and not committed_passengers.has(int(passenger.get("id", -1))) and Vector2(passenger.get("pos", Vector2.ZERO)).distance_to(Vector2(transport.get("pos", Vector2.ZERO))) <= 4.5)
			waiting.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
			if not waiting.is_empty():
				var in_range: Array[int] = []
				for passenger_value in waiting:
					var passenger: Dictionary = passenger_value
					var maximum_distance := float(passenger.get("footprint_radius", 0.3)) + float(transport.get("footprint_radius", 0.75)) + BOARDING_MARGIN
					if Vector2(passenger.get("pos", Vector2.ZERO)).distance_to(Vector2(transport.get("pos", Vector2.ZERO))) <= maximum_distance + 0.0001 and in_range.size() < capacity_left:
						in_range.append(int(passenger.get("id", -1)))
				if not in_range.is_empty():
					result.append(Commands.BoardCommand.new(tick, in_range, int(transport.get("id", -1))))
					continue
				var boarding_ids: Array[int] = []
				for passenger in waiting.slice(0, mini(capacity_left, waiting.size())):
					boarding_ids.append(int(passenger["id"]))
				result.append(Commands.BoardCommand.new(tick, boarding_ids, int(transport["id"])))
				continue
		if not landing_computed:
			target_landing = _landing_near(Vector2(goal.get("position", Vector2.ZERO)), navigation, target_land)
			landing_computed = true
		var landing: Variant = target_landing
		if not landing is Vector2:
			continue
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(landing) <= MAX_UNLOAD_DISTANCE + 0.0001:
			result.append(Commands.UnloadCommand.new(tick, [int(transport.get("id", -1))], landing))
			continue
		var water_approach: Variant = _water_approach(Vector2(landing), transport, navigation)
		if water_approach is Vector2:
			result.append(Commands.MoveCommand.new(tick, [int(transport.get("id", -1))], water_approach))
	return result


static func _nearest_coastal_land(origin: Vector2, navigation: Dictionary, probe: Variant = null) -> Variant:
	var land: Array = navigation.get("land", [])
	var water: Array = navigation.get("water", [])
	if land.is_empty() or water.is_empty():
		return null
	var water_buckets: Dictionary = {}
	for point_value in water:
		var point := Vector2(point_value)
		var cell := Vector2i(floori(point.x), floori(point.y))
		if not water_buckets.has(cell):
			water_buckets[cell] = []
		water_buckets[cell].append(point)
	var candidates: Array = []
	var comparisons := 0
	for point_value in land:
		var point := Vector2(point_value)
		var cell := Vector2i(floori(point.x), floori(point.y))
		var coastal := false
		# ceil(sqrt(2.26)) also covers arbitrary points near cell boundaries.
		for y in range(cell.y - 2, cell.y + 3):
			for x in range(cell.x - 2, cell.x + 3):
				for neighbor in water_buckets.get(Vector2i(x, y), []):
					comparisons += 1
					if point.distance_squared_to(neighbor) <= COAST_NEIGHBOR_DISTANCE_SQUARED:
						coastal = true
						break
				if coastal:
					break
			if coastal:
				break
		if coastal:
			candidates.append(point)
	if probe != null:
		probe.increment("ai.coast_water_indexed", water.size())
		probe.increment("ai.coast_neighbor_comparisons", comparisons)
	return _nearest(origin, candidates)


static func _landing_near(target: Vector2, navigation: Dictionary, target_land: Dictionary = {}) -> Variant:
	var component := target_land if not target_land.is_empty() else _known_land_component(target, navigation)
	var water: Array = navigation.get("water", [])
	if component.is_empty() or water.is_empty():
		return null
	var water_cells: Dictionary = {}
	for point_value in water:
		water_cells[Vector2i(Vector2(point_value))] = true
	var best: Variant = null
	var best_distance := INF
	for cell_value in component:
		var cell: Vector2i = cell_value
		var coastal := false
		for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			if water_cells.has(cell + offset):
				coastal = true
				break
		if coastal:
			var point := Vector2(cell) + Vector2(0.5, 0.5)
			var distance := target.distance_squared_to(point)
			if distance < best_distance or (is_equal_approx(distance, best_distance) and (best == null or point.x < Vector2(best).x or (point.x == Vector2(best).x and point.y < Vector2(best).y))):
				best = point
				best_distance = distance
	return best


static func _known_land_component(target: Vector2, navigation: Dictionary) -> Dictionary:
	var land: Array = navigation.get("land", [])
	if land.is_empty():
		return {}
	var land_cells: Dictionary = {}
	for point_value in land:
		land_cells[Vector2i(Vector2(point_value))] = true
	var nearest_land: Variant = _nearest(target, land)
	if not nearest_land is Vector2:
		return {}
	var queue: Array[Vector2i] = [Vector2i(nearest_land)]
	var visited: Dictionary = {queue[0]: true}
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if land_cells.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited


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


static func _water_approach(landing: Vector2, transport: Dictionary, navigation: Dictionary) -> Variant:
	var water: Array = navigation.get("water", [])
	if not bool(navigation.get("cell_geometry", false)):
		return _nearest_adjacent(landing, water)
	var radius := maxf(0.0, float(transport.get("footprint_radius", 0.75)))
	var known_water: Dictionary = {}
	for point in water:
		known_water[Vector2i(Vector2(point).floor())] = true
	var center := Vector2i(landing.floor())
	var candidates: Array = []
	var reach := ceili(MAX_UNLOAD_DISTANCE)
	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			var cell := Vector2i(x, y)
			if not known_water.has(cell):
				continue
			var point := Vector2(cell) + Vector2(0.5, 0.5)
			if point.distance_squared_to(landing) > MAX_UNLOAD_DISTANCE * MAX_UNLOAD_DISTANCE:
				continue
			# Match NavigationGrid's footprint probes. A coastal point alone is not
			# a usable endpoint for a wide Transport; it may overlap land or a dock.
			var clear := true
			for offset in [Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
				if not known_water.has(Vector2i((point + offset).floor())):
					clear = false
					break
			if clear:
				candidates.append(point)
	return _nearest(landing, candidates)
