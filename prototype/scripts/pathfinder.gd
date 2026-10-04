class_name RoRPathfinder

const MobileCollision := preload("res://scripts/mobile_collision.gd")

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
var cell_cache: Dictionary = {}
var smoothed_cell_cache: Dictionary = {}
var geometry_metadata: Dictionary = {"world": {}, "cells": {}, "smooth": {}}
var fallback_components: Dictionary = {}
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
var native_movement_solid_animals := PackedByteArray()
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
	fallback_components.clear()
	route_cache_revision = -1
	native_kernels.clear()
	native_movement_kernels_by_unit_id.clear()
	native_shared_movement_kernel = null


func clear_route_cache() -> void:
	# Stuck recovery needs a fresh route for one changed start/destination pair,
	# but the revisioned walkability mask remains valid. Topology changes call
	# clear_cache(), which additionally invalidates native kernels.
	cache.clear()
	cell_cache.clear()
	smoothed_cell_cache.clear()
	geometry_metadata = {"world": {}, "cells": {}, "smooth": {}}
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
	native_movement_solid_animals.resize(units.size())
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
		native_movement_solid_animals[index] = int(MobileCollision.is_solid_animal(unit))
	if homogeneous_configuration:
		native_shared_movement_kernel = _native_kernel_for(shared_domain, shared_restriction)
		native_shared_movement_kernel.configure_movement_snapshot(
			native_movement_ids,
			native_movement_positions,
			native_movement_radii,
			native_movement_clearances,
			native_movement_priorities,
			native_movement_health,
			native_movement_solid_animals
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
			native_movement_health,
			native_movement_solid_animals
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
	# Keep valid geometry across unrelated map edits; failed routes depend on
	# global connectivity and are invalidated on every topology change.
	_sync_route_revision()
	var start := Vector2i(floori(start_world.x), floori(start_world.y))
	var requested_goal := Vector2i(floori(goal_world.x), floori(goal_world.y))
	# Resolving a blocked endpoint can visit the entire map. The requested
	# endpoint and topology already determine that result, including failure.
	var key := "%s:%d:%.8f:%d:%d:%d:%d:%.4f:%.4f:%.4f:%.4f" % [movement_domain, restriction_id, clearance_radius, start.x, start.y, requested_goal.x, requested_goal.y, start_world.x, start_world.y, goal_world.x, goal_world.y]
	if cache.has(key):
		cache_hits += 1
		var cached_path: Array[Vector2] = []
		cached_path.assign(cache[key])
		return _finish_path_observation(started, cached_path, true)
	# Keys include exact world-space endpoints. In a long, otherwise static
	# match most routes are unique; topology revision alone cannot bound them.
	# Keep the last full cache until after its final possible hit.
	_trim_geometry_cache("world")
	var goal := nearest_walkable(requested_goal, movement_domain, restriction_id, clearance_radius)
	if goal.x < 0:
		cache[key] = []
		_record_geometry("world", key, [], start, requested_goal, clearance_radius)
		return _finish_path_observation(started, [], false)
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
		_record_geometry("world", key, [], start, requested_goal, clearance_radius)
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
	_record_geometry("world", key, result, start, requested_goal, clearance_radius)
	# Opening a closer endpoint can occur outside the previous route bounds.
	geometry_metadata["world"][key]["global"] = goal != requested_goal
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


func _geometry_bucket(name: String) -> Dictionary:
	return cache if name == "world" else (cell_cache if name == "cells" else smoothed_cell_cache)


func _sync_route_revision() -> void:
	if grid.revision == route_cache_revision:
		return
	var changed: Variant = grid.changed_cells_since(route_cache_revision) if route_cache_revision >= 0 and grid.has_method("changed_cells_since") else null
	for name in ["world", "cells", "smooth"]:
		var bucket := _geometry_bucket(name)
		var metadata: Dictionary = geometry_metadata[name]
		for key in bucket.keys():
			var record: Dictionary = metadata.get(key, {})
			var invalid: bool = changed == null or record.is_empty() or bool(record.get("empty", true)) or bool(record.get("global", false))
			if not invalid:
				var bounds: Rect2i = record["bounds"]
				for cell in changed:
					if bounds.has_point(cell):
						invalid = true
						break
			if invalid:
				bucket.erase(key)
				metadata.erase(key)
	fallback_components.clear()
	route_cache_revision = grid.revision


func _trim_geometry_cache(name: String) -> void:
	var bucket := _geometry_bucket(name)
	if bucket.size() >= MAX_ROUTE_CACHE_ENTRIES:
		var oldest: Variant = bucket.keys()[0]
		bucket.erase(oldest)
		geometry_metadata[name].erase(oldest)


func _record_geometry(name: String, key: String, path: Array, start: Vector2i, goal: Vector2i, radius: float) -> void:
	var minimum := Vector2i(mini(start.x, goal.x), mini(start.y, goal.y))
	var maximum := Vector2i(maxi(start.x, goal.x), maxi(start.y, goal.y))
	for point in path:
		var cell := Vector2i(point)
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var margin := Vector2i.ONE * (ceili(radius) + 1)
	geometry_metadata[name][key] = {"bounds": Rect2i(minimum - margin, maximum - minimum + Vector2i.ONE + margin * 2), "empty": path.is_empty()}


func _cell_key(start: Vector2i, goal: Vector2i, domain: String, restriction: int, radius: float) -> String:
	return "%s:%d:%.8f:%d:%d:%d:%d" % [domain, restriction, radius, start.x, start.y, goal.x, goal.y]


func find_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	_sync_route_revision()
	var key := _cell_key(start, goal, movement_domain, restriction_id, clearance_radius)
	if cell_cache.has(key):
		if performance_probe != null: performance_probe.increment("navigation.cell_cache_hits")
		var cached: Array[Vector2i] = []
		cached.assign(cell_cache[key])
		return cached
	var path := _search_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
	_trim_geometry_cache("cells")
	cell_cache[key] = path.duplicate()
	_record_geometry("cells", key, path, start, goal, clearance_radius)
	return path


func component_id(cell: Vector2i, domain: String = "land", restriction: int = -1, radius: float = 0.0) -> int:
	if grid == null or not grid.contains(cell): return -1
	if uses_native_kernel(): return int(_native_kernel_for(domain, restriction).component_id(cell, radius))
	_sync_route_revision()
	var key := "%s:%d:%.8f" % [domain, restriction, radius]
	if not fallback_components.has(key):
		if fallback_components.size() >= 16: fallback_components.clear()
		var labels := PackedInt32Array()
		labels.resize(grid.size.x * grid.size.y)
		labels.fill(-1)
		for index in range(labels.size()):
			var origin := Vector2i(index % grid.size.x, index / grid.size.x)
			if labels[index] >= 0 or not _cell_walkable(origin, domain, restriction, radius): continue
			var queue: Array[Vector2i] = [origin]
			labels[index] = index
			var cursor := 0
			while cursor < queue.size():
				var current := queue[cursor]
				cursor += 1
				for direction in DIRECTIONS:
					var next: Vector2i = current + direction
					if not grid.contains(next): continue
					var next_index: int = next.y * grid.size.x + next.x
					if labels[next_index] >= 0 or not _can_step(current, next, domain, restriction, radius): continue
					labels[next_index] = index
					queue.append(next)
		fallback_components[key] = labels
	return int(fallback_components[key][cell.y * grid.size.x + cell.x])


func cells_connected(start: Vector2i, goal: Vector2i, domain: String = "land", restriction: int = -1, radius: float = 0.0) -> bool:
	if grid == null or not grid.contains(start) or not grid.contains(goal): return false
	if uses_native_kernel(): return bool(_native_kernel_for(domain, restriction).cells_connected(start, goal, radius))
	var target := component_id(goal, domain, restriction, radius)
	if target < 0: return false
	var origin := component_id(start, domain, restriction, radius)
	if origin >= 0: return origin == target
	for direction in DIRECTIONS:
		var next: Vector2i = start + direction
		if _can_step(start, next, domain, restriction, radius) and component_id(next, domain, restriction, radius) == target: return true
	return false


func _search_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String = "land", restriction_id: int = -1, clearance_radius: float = 0.0) -> Array[Vector2i]:
	if grid == null or not grid.contains(start) or not grid.contains(goal) or not _cell_walkable(goal, movement_domain, restriction_id, clearance_radius):
		return []
	if uses_native_kernel():
		return _find_native_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
	# Without the native module, a cold full-map component scan costs more
	# than A* for a short reachable request. Reuse an existing region index,
	# otherwise let the reference search resolve the local query directly.
	var configuration := "%s:%d:%.8f" % [movement_domain, restriction_id, clearance_radius]
	if fallback_components.has(configuration) and not cells_connected(start, goal, movement_domain, restriction_id, clearance_radius):
		return []
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
	_sync_route_revision()
	var key := _cell_key(start, goal, movement_domain, restriction_id, clearance_radius)
	if smoothed_cell_cache.has(key):
		if performance_probe != null: performance_probe.increment("navigation.cell_cache_hits")
		return smoothed_cell_cache[key].duplicate(true)
	var result := _search_native_smoothed_cell_path(start, goal, movement_domain, restriction_id, clearance_radius)
	_trim_geometry_cache("smooth")
	smoothed_cell_cache[key] = result.duplicate(true)
	_record_geometry("smooth", key, result["path"], start, goal, clearance_radius)
	return result


func _search_native_smoothed_cell_path(start: Vector2i, goal: Vector2i, movement_domain: String, restriction_id: int, clearance_radius: float) -> Dictionary:
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
	if bool(kernel.is_configured()) and kernel.has_method("update_walkable"):
		var changed: Variant = grid.changed_cells_since(int(kernel.get_revision()))
		if changed != null:
			var indices := PackedInt32Array()
			var values := PackedByteArray()
			for cell_value in changed:
				var cell: Vector2i = cell_value
				indices.append(cell.y * grid.size.x + cell.x)
				values.append(1 if grid.is_walkable_for(cell, movement_domain, restriction_id) else 0)
			if bool(kernel.update_walkable(grid.revision, indices, values)):
				if performance_probe != null:
					performance_probe.increment("navigation.native_mask_updates")
					performance_probe.increment("navigation.native_mask_updated_cells", indices.size())
					performance_probe.observe_microseconds("navigation.native_mask_update", Time.get_ticks_usec() - started)
				return kernel
	var mask: PackedByteArray = grid.native_walkability_mask(movement_domain, restriction_id, performance_probe)
	kernel.configure(grid.size.x, grid.size.y, grid.revision, mask)
	if performance_probe != null:
		performance_probe.increment("navigation.native_mask_rebuilds")
		performance_probe.observe_microseconds("navigation.native_mask_rebuild", Time.get_ticks_usec() - started)
	return kernel


func patch_native_masks(changed_cells: Array[Vector2i]) -> void:
	# Exploration can reveal thousands of cells at once, exceeding the bounded
	# grid journal. Apply that exact batch directly instead of rebuilding a map.
	if changed_cells.is_empty():
		return
	for key in native_kernels:
		var kernel = native_kernels[key]
		if not bool(kernel.is_configured()) or int(kernel.get_revision()) != grid.revision - 1:
			continue
		var configuration := String(key).split(":")
		var domain := String(configuration[0])
		var restriction := int(configuration[1])
		var started := Time.get_ticks_usec() if performance_probe != null else 0
		var indices := PackedInt32Array()
		var values := PackedByteArray()
		indices.resize(changed_cells.size())
		values.resize(changed_cells.size())
		for index in range(changed_cells.size()):
			var cell: Vector2i = changed_cells[index]
			indices[index] = cell.y * grid.size.x + cell.x
			values[index] = 1 if grid.is_walkable_for(cell, domain, restriction) else 0
		if bool(kernel.update_walkable(grid.revision, indices, values)) and performance_probe != null:
			performance_probe.increment("navigation.native_mask_updates")
			performance_probe.increment("navigation.native_mask_updated_cells", indices.size())
			performance_probe.observe_microseconds("navigation.native_mask_update", Time.get_ticks_usec() - started)


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
			var columns: Array = range(requested.x - radius, requested.x + radius + 1) if absi(y - requested.y) == radius else [requested.x - radius, requested.x + radius]
			for x in columns:
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
