class_name RoRFormationCorridor

const Geometry := preload("res://scripts/formation_geometry.gd")


static func plan(start_world: Vector2, goal_world: Vector2, formation_type: String, member_count: int, spacing: float, member_radius: float, pathfinder, navigation_grid, movement_domain: String = "land", restriction_id: int = -1) -> Dictionary:
	var empty := {"route": [], "modes": [], "columns": [], "required_width": 1, "has_compression": false}
	var start := Vector2i(start_world.floor())
	var requested_goal := Vector2i(goal_world.floor())
	var goal: Vector2i = pathfinder.nearest_walkable(requested_goal, movement_domain, restriction_id, member_radius)
	if goal.x < 0: return empty
	var cells: Array[Vector2i] = pathfinder.direct_cell_path(start, goal, movement_domain, restriction_id, member_radius)
	var direct := not cells.is_empty()
	if cells.is_empty():
		cells = pathfinder.find_cell_path(start, goal, movement_domain, restriction_id, member_radius)
	if cells.is_empty(): return empty
	var bend_cells: Dictionary = {}
	# A direct route has no bends. For an obstacle detour use the existing native
	# smoother instead of repeatedly tracing long candidate lines in GDScript.
	if not direct:
		var smoothed: Array[Vector2i] = pathfinder.find_smoothed_cell_path(start, goal, movement_domain, restriction_id, member_radius) if pathfinder.uses_native_kernel() else pathfinder.smooth_cells(cells, movement_domain, restriction_id, member_radius)
		for cell in smoothed: bend_cells[cell] = true
	var bends: Dictionary = {}
	for index in range(1, cells.size() - 1):
		if bend_cells.has(cells[index]): bends[index] = true
	var required_width := _required_width(formation_type, member_count, spacing, member_radius)
	var route: Array[Vector2] = []
	var widths: Array[int] = []
	for index in range(cells.size()):
		route.append(Vector2(cells[index]) + Vector2(0.5, 0.5))
		widths.append(_available_lateral_width(navigation_grid, cells[index], _route_direction(cells, index), required_width, movement_domain, restriction_id, member_radius))
	if goal == requested_goal: route[route.size() - 1] = goal_world
	var modes: Array[String] = []
	var columns: Array[int] = []
	var has_compression := false
	var retained_columns := 0
	var clear_distance := 0.0
	for index in range(route.size()):
		# Look ahead before entering a gap; expand only after the tail has room.
		var available := widths[index]
		for ahead in range(index + 1, mini(index + 3, widths.size())):
			available = mini(available, widths[ahead])
		var wanted := 0 if available >= required_width else clampi(floori((float(available) - member_radius * 2.0) / spacing) + 1, 1, member_count)
		if wanted > 0:
			retained_columns = wanted if retained_columns == 0 else mini(retained_columns, wanted)
			clear_distance = 0.0
		elif retained_columns > 0:
			if index > 0: clear_distance += route[index].distance_to(route[index - 1])
			var tail_length := float(ceili(float(member_count) / retained_columns)) * spacing * 0.55
			if clear_distance >= maxf(2.0, tail_length): retained_columns = 0
		columns.append(retained_columns)
		modes.append("compressed" if retained_columns > 0 else "preferred")
		has_compression = has_compression or retained_columns > 0
	return {"route": route, "modes": modes, "columns": columns, "required_width": required_width, "has_compression": has_compression, "bends": bends}


static func member_waypoints(plan_data: Dictionary, member_count: int, formation_type: String, spacing: float, final_forward: Vector2, slot_id: int) -> Array[Vector2]:
	var all_waypoints := member_waypoint_sets(plan_data, member_count, formation_type, spacing, final_forward)
	var result: Array[Vector2] = []
	if slot_id >= 0 and slot_id < all_waypoints.size(): result.assign(all_waypoints[slot_id])
	return result


static func member_waypoint_sets(plan_data: Dictionary, member_count: int, formation_type: String, spacing: float, final_forward: Vector2) -> Array:
	var route: Array = plan_data.get("route", [])
	if route.is_empty() or member_count <= 0: return []
	var result: Array = []
	for _slot_id in range(member_count): result.append([])
	var columns: Array = plan_data.get("columns", [])
	var modes: Array = plan_data.get("modes", [])
	var previous_columns := 0
	for index in range(route.size()):
		var count := int(columns[index]) if index < columns.size() else (1 if modes[index] == "compressed" else 0)
		var is_final := index == route.size() - 1
		var turn := bool(plan_data.get("bends", {}).get(index, false))
		if count != previous_columns or is_final or turn:
			var local := Geometry.ranks(member_count, count, spacing) if count > 0 else Geometry.local_slots(member_count, formation_type, spacing)
			var forward := _world_route_direction(route, index) if count > 0 else final_forward
			if is_final and plan_data.has("deployment_local"):
				local.assign(plan_data["deployment_local"])
				forward = plan_data["deployment_forward"]
			var slots := Geometry.world_slots(local, route[index], forward)
			for slot_id in range(member_count): result[slot_id].append(slots[slot_id])
		previous_columns = count
	return result


static func _required_width(formation_type: String, member_count: int, spacing: float, member_radius: float) -> int:
	var maximum_x := 0.0
	for offset in Geometry.local_slots(member_count, formation_type, spacing):
		maximum_x = maxf(maximum_x, absf(offset.x))
	return maxi(1, ceili(2.0 * (maximum_x + member_radius)))


static func _route_direction(cells: Array[Vector2i], index: int) -> Vector2i:
	if cells.size() <= 1: return Vector2i(1, 0)
	if index == cells.size() - 1: return cells[index] - cells[index - 1]
	return cells[index + 1] - cells[index]


static func _world_route_direction(route: Array, index: int) -> Vector2:
	if route.size() <= 1: return Vector2(0, -1)
	var direction: Vector2 = route[index] - route[index - 1] if index == route.size() - 1 else route[index + 1] - route[index]
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0, -1)


static func _available_lateral_width(navigation_grid, cell: Vector2i, route_direction: Vector2i, maximum: int, movement_domain: String = "land", restriction_id: int = -1, member_radius: float = 0.0) -> int:
	var direction := Vector2(route_direction).normalized()
	var lateral := Vector2(-direction.y, direction.x)
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	var half_width := 0.0
	# Both sides must fit around this center. Free space on only one side does
	# not make a symmetric formation fit next to a wall.
	for step in range(1, maximum + 1):
		var offset := lateral * float(step) * 0.5
		if not navigation_grid.is_position_walkable_for(center + offset, member_radius, movement_domain, restriction_id) or not navigation_grid.is_position_walkable_for(center - offset, member_radius, movement_domain, restriction_id): break
		half_width = float(step) * 0.5
	return maxi(1, mini(maximum, floori(half_width * 2.0 + member_radius * 2.0)))
