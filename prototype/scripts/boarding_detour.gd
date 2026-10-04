extends RefCounted

const Collision := preload("res://scripts/mobile_collision.gd")
const SCALE: float = 16.0
const SEARCH_RADIUS: float = 4.0

# Only a stalled boarding approach uses this bounded, fine local search.
# Known terrain stays unchanged and unseen animals never become obstacles.
class ObstacleGrid:
	extends RefCounted
	var source
	var size: Vector2i
	var bounds: Rect2i
	var revision: int = 0
	var animals: Array = []

	func contains(cell: Vector2i) -> bool:
		return bounds.has_point(cell) and source.contains(Vector2i((Vector2(cell) / SCALE).floor()))

	func is_walkable_for(cell: Vector2i, domain: String, restriction: int) -> bool:
		return is_position_walkable_for(Vector2(cell) + Vector2(0.5, 0.5), 0.0, domain, restriction)

	func is_position_walkable_for(position: Vector2, radius: float, domain: String, restriction: int) -> bool:
		if not contains(Vector2i(position.floor())):
			return false
		var actual_position := position / SCALE
		var actual_radius := radius / SCALE
		if not source.is_position_walkable_for(actual_position, actual_radius, domain, restriction):
			return false
		for animal in animals:
			var separation := actual_radius + float(animal["footprint_radius"]) + 0.03
			if actual_position.distance_squared_to(Vector2(animal["pos"])) < separation * separation:
				return false
		return true

	func segment_clear(start: Vector2, finish: Vector2, radius: float, domain: String, restriction: int) -> bool:
		var actual_start := start / SCALE
		var actual_step := (finish - start) / SCALE
		for animal in animals:
			if Collision._crosses(actual_start - Vector2(animal["pos"]), actual_step, radius / SCALE + float(animal["footprint_radius"]) + 0.03):
				return false
		var steps := maxi(1, ceili(actual_step.length() * 8.0))
		for index in range(1, steps + 1):
			if not is_position_walkable_for(start.lerp(finish, float(index) / steps), radius, domain, restriction):
				return false
		return true

class DetourPlanner:
	extends "res://scripts/pathfinder.gd"
	var origin: Vector2
	var origin_cell: Vector2i

	func nearest_walkable(requested: Vector2i, domain: String = "land", restriction: int = -1, radius: float = 0.0) -> Vector2i:
		# The exact endpoint is already valid; only its fine cell centre may
		# need adjusting. Never expand this local correction to the full map.
		for reach in range(5):
			var candidates: Array[Vector2i] = []
			for y in range(requested.y - reach, requested.y + reach + 1):
				for x in range(requested.x - reach, requested.x + reach + 1):
					if maxi(absi(x - requested.x), absi(y - requested.y)) != reach:
						continue
					var cell := Vector2i(x, y)
					if grid.contains(cell) and _cell_walkable(cell, domain, restriction, radius):
						candidates.append(cell)
			if not candidates.is_empty():
				candidates.sort_custom(func(left, right):
					var left_distance: int = left.distance_squared_to(requested)
					var right_distance: int = right.distance_squared_to(requested)
					return left_distance < right_distance or (left_distance == right_distance and (left.y < right.y or (left.y == right.y and left.x < right.x)))
				)
				return candidates[0]
		return Vector2i(-1, -1)

	func _can_step(current: Vector2i, next: Vector2i, domain: String = "land", restriction: int = -1, radius: float = 0.0) -> bool:
		if not super._can_step(current, next, domain, restriction, radius):
			return false
		return grid.segment_clear(_position(current), Vector2(next) + Vector2(0.5, 0.5), radius, domain, restriction)

	func line_walkable(start: Vector2i, goal: Vector2i, domain: String = "land", restriction: int = -1, radius: float = 0.0) -> bool:
		return grid.segment_clear(_position(start), Vector2(goal) + Vector2(0.5, 0.5), radius, domain, restriction)

	func _position(cell: Vector2i) -> Vector2:
		return origin if cell == origin_cell else Vector2(cell) + Vector2(0.5, 0.5)


static func find(world, passenger: Dictionary, goal: Vector2) -> Array[Vector2]:
	var origin := Vector2(passenger["pos"])
	var team := int(passenger["team"])
	var animals: Array = world.query_units_near(origin, SEARCH_RADIUS + 2.0).filter(func(unit): return float(unit.get("hp", 0.0)) > 0.0 and Collision.is_solid_animal(unit) and world.is_entity_visible_to(team, unit))
	if animals.is_empty():
		return []
	var known = world.movement_system.knowledge.planner(world, team)
	var obstacle_grid := ObstacleGrid.new()
	obstacle_grid.source = known.grid
	obstacle_grid.size = world.map_size * int(SCALE)
	var cell := Vector2i((origin * SCALE).floor())
	var reach := int(SEARCH_RADIUS * SCALE)
	obstacle_grid.bounds = Rect2i(cell - Vector2i(reach, reach), Vector2i(reach * 2 + 1, reach * 2 + 1))
	obstacle_grid.animals = animals
	var radius := float(passenger["footprint_radius"]) * SCALE
	var domain := String(passenger["movement_domain"])
	var restriction := int(passenger["terrain_restriction"])
	var endpoint := goal * SCALE
	if not obstacle_grid.contains(Vector2i(endpoint.floor())):
		var inset := obstacle_grid.bounds.grow(-1)
		endpoint = Vector2(clampi(floori(endpoint.x), inset.position.x, inset.end.x - 1), clampi(floori(endpoint.y), inset.position.y, inset.end.y - 1)) + Vector2(0.5, 0.5)
	if not obstacle_grid.is_position_walkable_for(endpoint, radius, domain, restriction):
		return []
	var planner := DetourPlanner.new(obstacle_grid)
	planner.origin = origin * SCALE
	planner.origin_cell = cell
	planner.set_native_enabled(false)
	planner.performance_probe = known.performance_probe
	var route := planner.find_path(planner.origin, endpoint, domain, restriction, radius)
	if route.is_empty() or route.back().distance_squared_to(endpoint) > 0.0144:
		return []
	var result: Array[Vector2] = []
	var previous := origin * SCALE
	for point in route:
		if not obstacle_grid.segment_clear(previous, point, radius, domain, restriction):
			return []
		result.append(point / SCALE)
		previous = point
	return result
