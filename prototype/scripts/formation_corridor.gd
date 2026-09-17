class_name RoRFormationCorridor

const Geometry := preload("res://scripts/formation_geometry.gd")


static func plan(start_world: Vector2, goal_world: Vector2, formation_type: String, member_count: int, spacing: float, member_radius: float, pathfinder, navigation_grid) -> Dictionary:
	var start := Vector2i(floori(start_world.x), floori(start_world.y))
	var requested_goal := Vector2i(floori(goal_world.x), floori(goal_world.y))
	var goal: Vector2i = pathfinder.nearest_walkable(requested_goal)
	if goal.x < 0:
		return {"route": [], "modes": [], "required_width": 1, "has_compression": false}
	# An unobstructed march uses the same rasterized group corridor directly.
	# A* remains the fallback when the straight corridor is blocked.
	var cells: Array[Vector2i] = pathfinder.direct_cell_path(start, goal)
	if cells.is_empty():
		cells = pathfinder.find_cell_path(start, goal)
	if cells.is_empty():
		return {"route": [], "modes": [], "required_width": 1, "has_compression": false}
	var required_width := _required_width(formation_type, member_count, spacing, member_radius)
	var route: Array[Vector2] = []
	var modes: Array[String] = []
	var has_compression := false
	for index in range(cells.size()):
		var cell: Vector2i = cells[index]
		var direction := _route_direction(cells, index)
		var available := _available_lateral_width(navigation_grid, cell, direction, required_width)
		var mode := "compressed" if available < required_width else "preferred"
		route.append(Vector2(cell) + Vector2(0.5, 0.5))
		modes.append(mode)
		has_compression = has_compression or mode == "compressed"
	if goal == requested_goal:
		route[route.size() - 1] = goal_world
	return {
		"route": route,
		"modes": modes,
		"required_width": required_width,
		"has_compression": has_compression,
	}


static func member_waypoints(plan_data: Dictionary, member_count: int, formation_type: String, spacing: float, final_forward: Vector2, slot_id: int) -> Array[Vector2]:
	var all_waypoints := member_waypoint_sets(plan_data, member_count, formation_type, spacing, final_forward)
	if slot_id < 0 or slot_id >= all_waypoints.size():
		return []
	var selected: Array[Vector2] = []
	selected.assign(all_waypoints[slot_id])
	return selected


static func member_waypoint_sets(plan_data: Dictionary, member_count: int, formation_type: String, spacing: float, final_forward: Vector2) -> Array:
	var route: Array = plan_data.get("route", [])
	var modes: Array = plan_data.get("modes", [])
	if route.is_empty() or member_count <= 0:
		return []
	var result: Array = []
	for _slot_id in range(member_count):
		result.append([])
	var previous_mode := "preferred"
	for index in range(1, route.size()):
		var mode: String = modes[index]
		var is_transition := mode != previous_mode
		var is_final := index == route.size() - 1
		if is_transition or is_final:
			var active_type := Geometry.COLUMN if mode == "compressed" and not is_final else formation_type
			var active_forward := final_forward
			if active_type == Geometry.COLUMN:
				active_forward = _world_route_direction(route, index)
			var local := Geometry.local_slots(member_count, active_type, spacing)
			var slots := Geometry.world_slots(local, route[index], active_forward)
			for slot_id in range(member_count):
				result[slot_id].append(slots[slot_id])
		previous_mode = mode
	return result


static func _required_width(formation_type: String, member_count: int, spacing: float, member_radius: float) -> int:
	var local := Geometry.local_slots(member_count, formation_type, spacing)
	var minimum_x := 0.0
	var maximum_x := 0.0
	for offset in local:
		minimum_x = minf(minimum_x, offset.x)
		maximum_x = maxf(maximum_x, offset.x)
	return maxi(1, ceili(maximum_x - minimum_x + member_radius * 2.0))


static func _route_direction(cells: Array[Vector2i], index: int) -> Vector2i:
	if cells.size() <= 1:
		return Vector2i(1, 0)
	if index == 0:
		return cells[1] - cells[0]
	if index == cells.size() - 1:
		return cells[index] - cells[index - 1]
	return cells[index + 1] - cells[index - 1]


static func _world_route_direction(route: Array, index: int) -> Vector2:
	if route.size() <= 1:
		return Vector2(0, -1)
	var direction: Vector2
	if index <= 0:
		direction = route[1] - route[0]
	elif index >= route.size() - 1:
		direction = route[index] - route[index - 1]
	else:
		direction = route[index + 1] - route[index - 1]
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0, -1)


static func _available_lateral_width(navigation_grid, cell: Vector2i, route_direction: Vector2i, maximum: int) -> int:
	var lateral := Vector2i(0, 1) if absi(route_direction.x) >= absi(route_direction.y) else Vector2i(1, 0)
	var width := 1
	for sign_value in [-1, 1]:
		for distance in range(1, maximum + 1):
			var probe: Vector2i = cell + lateral * int(distance) * int(sign_value)
			if not navigation_grid.is_walkable(probe):
				break
			width += 1
			if width >= maximum:
				return width
	return width
