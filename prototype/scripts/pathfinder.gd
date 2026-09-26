class_name RoRPathfinder

const CARDINAL_COST: float = 1.0
const DIAGONAL_COST: float = 1.41421356237
const MAX_ROUTE_CACHE_ENTRIES: int = 2048
const DIRECTIONS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                         Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]

var grid
var cache: Dictionary = {}
var cache_hits: int = 0
var route_cache_revision: int = -1
var performance_probe: Variant = null
var native_enabled: bool = true
var native_available: bool = false
var native_kernels: Dictionary = {}
var native_movement_kernels_by_unit_id: Dictionary = {}
var native_shared_movement_kernel: Variant = null
var native_movement_ids := PackedInt32Array()
var native_movement_positions := PackedVector2Array()
var native_movement_radii := PackedFloat32Array()
var native_movement_clearances := PackedFloat32Array()
var native_movement_priorities := PackedInt32Array()
var native_movement_health := PackedFloat32Array()
var observed_path_query_microseconds: int = 0


func _init(navigation_grid = null) -> void:
	grid = navigation_grid
	native_available = ClassDB.class_exists("RoRPathKernel")


func set_performance_probe(probe: Variant) -> void:
	performance_probe = probe


func reset_path_query_tick_observation() -> void:
	observed_path_query_microseconds = 0


func path_query_tick_microseconds() -> int:
	return observed_path_query_microseconds


func clear_cache() -> void:
	clear_route_cache()
	native_kernels.clear()
	native_movement_kernels_by_unit_id.clear()
	native_shared_movement_kernel = null


func clear_route_cache() -> void:
	# Stuck recovery needs a fresh route for one changed start/destination pair,
	# but the revisioned walkability mask remains valid. Topology changes call
	# clear_cache(), which additionally invalidates native kernels.
	cache.clear()
	cache_hits = 0


func set_native_enabled(enabled: bool) -> void:
	native_enabled = enabled


func uses_native_kernel() -> bool:
	return native_enabled and native_available


func prepare_native_kernels_for_units(units: Array) -> void:
	if not uses_native_kernel():
		return
	var configurations: Dictionary = {}
	for unit in units:
		var movement_domain := String(unit.get("movement_domain", "land"))
		var restriction_id := int(unit.get("terrain_restriction", -1))
		configurations["%s:%d" % [movement_domain, restriction_id]] = [movement_domain, restriction_id]
	var keys := configurations.keys()
	keys.sort()
	for key in keys:
		var configuration: Array = configurations[key]
		_native_kernel_for(String(configuration[0]), int(configuration[1]))


func prepare_native_movement_snapshot(units: Array) -> void:
	native_movement_kernels_by_unit_id.clear()
	native_shared_movement_kernel = null
	if not uses_native_kernel() or units.is_empty():
		return
	native_movement_ids.resize(units.size())
	native_movement_positions.resize(units.size())
	native_movement_radii.resize(units.size())
	native_movement_clearances.resize(units.size())
	native_movement_priorities.resize(units.size())
	native_movement_health.resize(units.size())
	var first_unit: Dictionary = units[0]
	var shared_domain := String(first_unit["movement_domain"])
	var shared_restriction := int(first_unit["terrain_restriction"])
	var homogeneous_configuration := true
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var movement_domain := String(unit["movement_domain"])
		var restriction_id := int(unit["terrain_restriction"])
		if movement_domain != shared_domain or restriction_id != shared_restriction:
			homogeneous_configuration = false
		native_movement_ids[index] = int(unit["id"])
		native_movement_positions[index] = Vector2(unit["pos"])
		native_movement_radii[index] = float(unit["footprint_radius"])
		native_movement_clearances[index] = float(unit["minimum_clearance"])
		native_movement_priorities[index] = int(unit["push_priority"])
		native_movement_health[index] = float(unit["hp"])
	if homogeneous_configuration:
		native_shared_movement_kernel = _native_kernel_for(shared_domain, shared_restriction)
		native_shared_movement_kernel.configure_movement_snapshot(
			native_movement_ids,
			native_movement_positions,
			native_movement_radii,
			native_movement_clearances,
			native_movement_priorities,
			native_movement_health
		)
		return
	var configurations: Dictionary = {}
	var configuration_by_unit_id: Dictionary = {}
	for unit in units:
		var unit_id := int(unit["id"])
		var movement_domain := String(unit["movement_domain"])
		var restriction_id := int(unit["terrain_restriction"])
		var configuration_key := "%s:%d" % [movement_domain, restriction_id]
		configurations[configuration_key] = [movement_domain, restriction_id]
		configuration_by_unit_id[unit_id] = configuration_key
	var kernels_by_configuration: Dictionary = {}
	var configuration_keys := configurations.keys()
	configuration_keys.sort()
	for configuration_key in configuration_keys:
		var configuration: Array = configurations[configuration_key]
		var kernel = _native_kernel_for(String(configuration[0]), int(configuration[1]))
		kernel.configure_movement_snapshot(
			native_movement_ids,
			native_movement_positions,
			native_movement_radii,
			native_movement_clearances,
			native_movement_priorities,
			native_movement_health
		)
		kernels_by_configuration[configuration_key] = kernel
	for unit_id in configuration_by_unit_id:
		native_movement_kernels_by_unit_id[unit_id] = kernels_by_configuration[configuration_by_unit_id[unit_id]]


func has_native_movement_for(unit_id: int) -> bool:
	# Snapshot preparation clears both stores whenever native execution is
	# unavailable, so the hot per-unit query needs no repeated capability checks.
	return native_shared_movement_kernel != null or native_movement_kernels_by_unit_id.has(unit_id)


func calculate_native_movement(unit: Dictionary, target: Vector2, delta: float) -> Vector4:
	var kernel = native_shared_movement_kernel
	if kernel == null:
		kernel = native_movement_kernels_by_unit_id.get(int(unit["id"]))
	if kernel == null:
		return Vector4(0.0, 0.0, -1.0, 0.0)
	return kernel.calculate_movement(
		int(unit["id"]),
		target,
		float(unit["speed"]),
		float(unit["cohesion_speed_scale"]),
		delta
	)


func find_path(start_world: Vector2, goal_world: Vector2, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2]:
	var started := Time.get_ticks_usec() if performance_probe != null else 0
	if performance_probe != null:
		performance_probe.increment("navigation.path_queries")
	# Cache keys embed the revision, so entries from older revisions can never
	# hit again; dropping them on the first post-change request bounds memory
	# instead of accumulating every historical route.
	if grid.revision != route_cache_revision:
		cache.clear()
		route_cache_revision = grid.revision
	var start := Vector2i(floori(start_world.x), floori(start_world.y))
	var requested_goal := Vector2i(floori(goal_world.x), floori(goal_world.y))
	var goal := nearest_walkable(requested_goal, movement_domain, restriction_id, clearance_radius)
	if goal.x < 0:
		return _finish_path_observation(started, [], false)
	# Exact endpoints matter even when both requests fall into the same cell.
	# Without them a return-to-slot request can reuse an earlier contact point.
	var key := "%d:%s:%d:%.4f:%d:%d:%d:%d:%.4f:%.4f:%.4f:%.4f" % [grid.revision, movement_domain, restriction_id, clearance_radius, start.x, start.y, goal.x, goal.y, start_world.x, start_world.y, goal_world.x, goal_world.y]
	if cache.has(key):
		cache_hits += 1
		var cached_path: Array[Vector2] = []
		cached_path.assign(cache[key])
		return _finish_path_observation(started, cached_path, true)
	# Keys include exact world-space endpoints. In a long, otherwise static
	# match most routes are unique; topology revision alone cannot bound them.
	# Keep the last full cache until after its final possible hit.
	if cache.size() >= MAX_ROUTE_CACHE_ENTRIES:
		cache.clear()
	var smoothed: Array[Vector2i]
	var direct_path := false
	if uses_native_kernel():
		var native_result := _find_native_smoothed_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
		smoothed = native_result["path"]
		direct_path = bool(native_result["direct"])
	else:
		var cells := direct_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
		direct_path = not cells.is_empty()
		if not direct_path:
			cells = find_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
		if direct_path and cells.size() > 1:
			smoothed = [cells[0], cells[cells.size() - 1]]
		else:
			smoothed = smooth_cells(cells, movement_domain, restriction_id, clearance_radius)
	if smoothed.is_empty():
		cache[key] = []
		return _finish_path_observation(started, [], false)
	if direct_path and performance_probe != null:
		performance_probe.increment("navigation.direct_path_hits")
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
	return _finish_path_observation(started, result, false)


func _finish_path_observation(started: int, path: Array[Vector2], cache_hit: bool) -> Array[Vector2]:
	if performance_probe != null:
		var elapsed := Time.get_ticks_usec() - started
		observed_path_query_microseconds += elapsed
		performance_probe.observe_microseconds("navigation.path_query", elapsed)
		if cache_hit:
			performance_probe.increment("navigation.path_cache_hits")
		if path.is_empty():
			performance_probe.increment("navigation.path_unreachable")
	return path


func find_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	if grid == null or not grid.contains(start) or not grid.contains(goal) or not _cell_walkable(goal, movement_domain, restriction_id, clearance_radius):
		return []
	if uses_native_kernel():
		return _find_native_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
	var expanded_nodes := 0
	var frontier: Array = []
	_frontier_push(frontier, {"cell": start, "score": 0.0, "cost": 0.0})
	var came_from: Dictionary = {start: start}
	var cost_so_far: Dictionary = {start: 0.0}
	while not frontier.is_empty():
		var current_entry: Dictionary = _frontier_pop(frontier)
		expanded_nodes += 1
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
		if performance_probe != null:
			performance_probe.increment("navigation.expanded_nodes", expanded_nodes)
		return []
	var reversed: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		current = came_from[current]
		reversed.append(current)
	reversed.reverse()
	if performance_probe != null:
		performance_probe.increment("navigation.expanded_nodes", expanded_nodes)
	return reversed


func _find_native_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String, restriction_id: int, clearance_radius: float) -> Array[Vector2i]:
	var kernel = _native_kernel_for(movement_domain, restriction_id)
	var packed: PackedInt32Array = kernel.find_cell_path(start, goal, clearance_radius)
	if performance_probe != null:
		performance_probe.increment("navigation.native_path_queries")
		performance_probe.increment("navigation.expanded_nodes", int(kernel.get_last_expanded_nodes()))
	var result: Array[Vector2i] = []
	result.resize(packed.size() / 2)
	var result_index := 0
	for packed_index in range(0, packed.size(), 2):
		result[result_index] = Vector2i(packed[packed_index], packed[packed_index + 1])
		result_index += 1
	return result


func _find_native_smoothed_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String, restriction_id: int, clearance_radius: float) -> Dictionary:
	var kernel = _native_kernel_for(movement_domain, restriction_id)
	var packed: PackedInt32Array = kernel.find_smoothed_cell_path(start, goal, clearance_radius)
	if performance_probe != null:
		performance_probe.increment("navigation.native_path_queries")
		performance_probe.increment("navigation.expanded_nodes", int(kernel.get_last_expanded_nodes()))
	var result: Array[Vector2i] = []
	result.resize(packed.size() / 2)
	var result_index := 0
	for packed_index in range(0, packed.size(), 2):
		result[result_index] = Vector2i(packed[packed_index], packed[packed_index + 1])
		result_index += 1
	return {"path": result, "direct": bool(kernel.get_last_path_was_direct())}


func _native_kernel_for(movement_domain: String, restriction_id: int):
	var key := "%s:%d" % [movement_domain, restriction_id]
	var kernel = native_kernels.get(key)
	if kernel == null:
		kernel = ClassDB.instantiate("RoRPathKernel")
		native_kernels[key] = kernel
	if int(kernel.get_revision()) == int(grid.revision) and bool(kernel.is_configured()):
		return kernel
	var started := Time.get_ticks_usec() if performance_probe != null else 0
	var mask := PackedByteArray()
	mask.resize(grid.size.x * grid.size.y)
	var index := 0
	for y in range(grid.size.y):
		for x in range(grid.size.x):
			mask[index] = 1 if grid.is_walkable_for(Vector2i(x, y), movement_domain, restriction_id) else 0
			index += 1
	kernel.configure(grid.size.x, grid.size.y, grid.revision, mask)
	if performance_probe != null:
		performance_probe.increment("navigation.native_mask_rebuilds")
		performance_probe.observe_microseconds("navigation.native_mask_rebuild", Time.get_ticks_usec() - started)
	return kernel


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
	return not direct_cell_path(start, goal, movement_domain, restriction_id, clearance_radius).is_empty()


func direct_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	if grid == null or not grid.contains(start) or not grid.contains(goal):
		return []
	if not _cell_walkable(start, movement_domain, restriction_id, clearance_radius) or not _cell_walkable(goal, movement_domain, restriction_id, clearance_radius):
		return []
	var result: Array[Vector2i] = [start]
	if start == goal:
		return result
	var difference := goal - start
	var steps := maxi(absi(difference.x), absi(difference.y))
	var previous := start
	for index in range(1, steps + 1):
		var ratio := float(index) / float(steps)
		var current := Vector2i(roundi(lerpf(start.x, goal.x, ratio)), roundi(lerpf(start.y, goal.y, ratio)))
		if current == previous:
			continue
		if not _can_step(previous, current, movement_domain, restriction_id, clearance_radius):
			return []
		result.append(current)
		previous = current
	return result


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
