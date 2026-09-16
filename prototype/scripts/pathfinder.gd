class_name RoRPathfinder

const CARDINAL_COST: float = 1.0
const DIAGONAL_COST: float = 1.41421356237
const DIRECTIONS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                         Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]

var grid
var cache: Dictionary = {}
var cache_hits: int = 0


func _init(navigation_grid = null) -> void:
	grid = navigation_grid


func clear_cache() -> void:
	cache.clear()
	cache_hits = 0


func find_path(start_world: Vector2, goal_world: Vector2, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2]:
	var start := Vector2i(floori(start_world.x), floori(start_world.y))
	var requested_goal := Vector2i(floori(goal_world.x), floori(goal_world.y))
	var goal := nearest_walkable(requested_goal, movement_domain, restriction_id, clearance_radius)
	if goal.x < 0:
		return []
	# Exact endpoints matter even when both requests fall into the same cell.
	# Without them a return-to-slot request can reuse an earlier contact point.
	var key := "%d:%s:%d:%.4f:%d:%d:%d:%d:%.4f:%.4f:%.4f:%.4f" % [grid.revision, movement_domain, restriction_id, clearance_radius, start.x, start.y, goal.x, goal.y, start_world.x, start_world.y, goal_world.x, goal_world.y]
	if cache.has(key):
		cache_hits += 1
		var cached_path: Array[Vector2] = []
		cached_path.assign(cache[key])
		return cached_path
	var cells := find_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
	if cells.is_empty():
		cache[key] = []
		return []
	var smoothed := smooth_cells(cells, movement_domain, restriction_id, clearance_radius)
	var result: Array[Vector2] = []
	for index in range(1, smoothed.size()):
		var cell: Vector2i = smoothed[index]
		result.append(Vector2(cell) + Vector2(0.5, 0.5))
	if result.is_empty():
		var same_cell_destination := goal_world if goal == requested_goal else Vector2(goal) + Vector2(0.5, 0.5)
		if start_world.distance_squared_to(same_cell_destination) > 0.0001:
			result.append(same_cell_destination)
	if goal == requested_goal and not result.is_empty() and grid.is_position_walkable_for(goal_world, clearance_radius, movement_domain, restriction_id):
		result[result.size() - 1] = goal_world
	cache[key] = result.duplicate()
	return result


func find_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	if grid == null or not grid.contains(start) or not grid.contains(goal) or not _cell_walkable(goal, movement_domain, restriction_id, clearance_radius):
		return []
	var frontier: Array = []
	_frontier_push(frontier, {"cell": start, "score": 0.0, "cost": 0.0})
	var came_from: Dictionary = {start: start}
	var cost_so_far: Dictionary = {start: 0.0}
	while not frontier.is_empty():
		var current_entry: Dictionary = _frontier_pop(frontier)
		var current: Vector2i = current_entry["cell"]
		if float(current_entry["cost"]) > float(cost_so_far.get(current, INF)) + 0.000001:
			continue
		if current == goal:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not _can_step(current, next, movement_domain, restriction_id, clearance_radius):
				continue
			var step_cost := DIAGONAL_COST if direction.x != 0 and direction.y != 0 else CARDINAL_COST
			var next_cost: float = float(cost_so_far[current]) + step_cost
			if not cost_so_far.has(next) or next_cost < float(cost_so_far[next]):
				cost_so_far[next] = next_cost
				came_from[next] = current
				_frontier_push(frontier, {"cell": next, "score": next_cost + _heuristic(next, goal), "cost": next_cost})
	if not came_from.has(goal):
		return []
	var reversed: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		current = came_from[current]
		reversed.append(current)
	reversed.reverse()
	return reversed


func _frontier_push(frontier: Array, entry: Dictionary) -> void:
	frontier.append(entry)
	var index := frontier.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _frontier_less(frontier[index], frontier[parent]):
			break
		var temporary: Variant = frontier[parent]
		frontier[parent] = frontier[index]
		frontier[index] = temporary
		index = parent


func _frontier_pop(frontier: Array) -> Dictionary:
	var first: Dictionary = frontier[0]
	var last: Dictionary = frontier.pop_back()
	if frontier.is_empty():
		return first
	frontier[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= frontier.size():
			break
		var right := left + 1
		var best := left
		if right < frontier.size() and _frontier_less(frontier[right], frontier[left]):
			best = right
		if not _frontier_less(frontier[best], frontier[index]):
			break
		var temporary: Variant = frontier[index]
		frontier[index] = frontier[best]
		frontier[best] = temporary
		index = best
	return first


func _frontier_less(left: Dictionary, right: Dictionary) -> bool:
	var left_score := float(left["score"])
	var right_score := float(right["score"])
	if not is_equal_approx(left_score, right_score):
		return left_score < right_score
	var left_cell: Vector2i = left["cell"]
	var right_cell: Vector2i = right["cell"]
	return left_cell.y < right_cell.y or (left_cell.y == right_cell.y and left_cell.x < right_cell.x)


func smooth_cells(path: Array[Vector2i], movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	if path.size() <= 2:
		return path.duplicate()
	var result: Array[Vector2i] = [path[0]]
	var anchor := 0
	while anchor < path.size() - 1:
		var furthest := anchor + 1
		for candidate in range(path.size() - 1, anchor, -1):
			if line_walkable(path[anchor], path[candidate], movement_domain, restriction_id, clearance_radius):
				furthest = candidate
				break
		result.append(path[furthest])
		anchor = furthest
	return result


func line_walkable(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> bool:
	var difference := goal - start
	var steps := maxi(absi(difference.x), absi(difference.y))
	var previous := start
	for index in range(1, steps + 1):
		var ratio := float(index) / float(steps)
		var current := Vector2i(roundi(lerpf(start.x, goal.x, ratio)), roundi(lerpf(start.y, goal.y, ratio)))
		if not _can_step(previous, current, movement_domain, restriction_id, clearance_radius):
			return false
		previous = current
	return true


func nearest_walkable(requested: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Vector2i:
	if grid.contains(requested) and _cell_walkable(requested, movement_domain, restriction_id, clearance_radius):
		return requested
	var maximum_radius := maxi(grid.size.x, grid.size.y)
	for radius in range(1, maximum_radius + 1):
		var candidates: Array[Vector2i] = []
		for y in range(requested.y - radius, requested.y + radius + 1):
			for x in range(requested.x - radius, requested.x + radius + 1):
				if absi(x - requested.x) != radius and absi(y - requested.y) != radius:
					continue
				var cell := Vector2i(x, y)
				if grid.contains(cell) and _cell_walkable(cell, movement_domain, restriction_id, clearance_radius):
					candidates.append(cell)
		if not candidates.is_empty():
			candidates.sort_custom(func(left, right):
				var left_distance: int = left.distance_squared_to(requested)
				var right_distance: int = right.distance_squared_to(requested)
				return left_distance < right_distance or (left_distance == right_distance and (left.y < right.y or (left.y == right.y and left.x < right.x))))
			return candidates[0]
	return Vector2i(-1, -1)


func _can_step(current: Vector2i, next: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> bool:
	if next == current:
		return true
	if not grid.contains(next) or not _cell_walkable(next, movement_domain, restriction_id, clearance_radius):
		return false
	var direction := next - current
	if direction.x != 0 and direction.y != 0:
		return _cell_walkable(current + Vector2i(direction.x, 0), movement_domain, restriction_id, clearance_radius) and _cell_walkable(current + Vector2i(0, direction.y), movement_domain, restriction_id, clearance_radius)
	return true


func _cell_walkable(cell: Vector2i, movement_domain: String, restriction_id: int, clearance_radius: float) -> bool:
	if clearance_radius <= 0.0001:
		return grid.is_walkable_for(cell, movement_domain, restriction_id)
	return grid.is_position_walkable_for(Vector2(cell) + Vector2(0.5, 0.5), clearance_radius, movement_domain, restriction_id)


func _heuristic(left: Vector2i, right: Vector2i) -> float:
	var dx := absi(left.x - right.x)
	var dy := absi(left.y - right.y)
	return float(maxi(dx, dy)) + (DIAGONAL_COST - 1.0) * float(mini(dx, dy))
