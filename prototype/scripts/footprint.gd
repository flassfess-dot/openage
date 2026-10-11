class_name RoRFootprint

const DEFAULT_MOBILE_RADIUS: float = 0.3
const DEFAULT_CLEARANCE: float = 0.06


static func mobile(kind: String, stats: Dictionary) -> Dictionary:
	var selection: Array = stats.get("selection_radius", [])
	var radius := DEFAULT_MOBILE_RADIUS
	var height := 1.0
	if selection.size() >= 2:
		radius = maxf(0.1, maxf(float(selection[0]), float(selection[1])))
	if selection.size() >= 3:
		height = maxf(0.1, float(selection[2]))
	return {
		"shape": "circle",
		"movement_radius": radius,
		"selection_radius": Vector2(radius, radius),
		"selection_height": height,
		"minimum_clearance": DEFAULT_CLEARANCE,
		"push_priority": push_priority_for(kind, stats.get("behavior_tags", [])),
	}


static func building(stats: Dictionary, center: Vector2) -> Dictionary:
	var selection: Array = stats.get("selection_radius", [0.5, 0.5, 1.0])
	var obstruction: Array = stats.get("footprint_radius", [])
	var obstruction_values: Array = obstruction if obstruction.size() >= 2 else selection
	var obstruction_half_size := Vector2(maxf(0.5, float(obstruction_values[0])), maxf(0.5, float(obstruction_values[1])))
	var selection_half_size := Vector2(maxf(0.5, float(selection[0])), maxf(0.5, float(selection[1])))
	var half_size := Vector2(maxf(obstruction_half_size.x, selection_half_size.x), maxf(obstruction_half_size.y, selection_half_size.y))
	return {
		"shape": "polygon",
		"half_size": half_size,
		"obstruction_half_size": obstruction_half_size,
		"polygon": PackedVector2Array([
			center + Vector2(-half_size.x, -half_size.y),
			center + Vector2(half_size.x, -half_size.y),
			center + Vector2(half_size.x, half_size.y),
			center + Vector2(-half_size.x, half_size.y),
		]),
		"occupied_cells": occupied_cells(center, obstruction_half_size),
	}


static func resource(kind: String, stats: Dictionary = {}) -> Dictionary:
	var geometry: Dictionary = stats.get("geometry", {})
	var radius_values: Array = geometry.get("radius", [])
	var selection_values: Array = geometry.get("selection", [])
	var radius := 0.2
	var selection_radius := 0.4 if kind == "berries" else radius
	var selection_height := 0.2 if kind == "berries" else 2.0
	if radius_values.size() >= 2:
		radius = maxf(0.05, maxf(float(radius_values[0]), float(radius_values[1])))
	if selection_values.size() >= 2:
		selection_radius = maxf(0.05, maxf(float(selection_values[0]), float(selection_values[1])))
	if selection_values.size() >= 3:
		selection_height = maxf(0.0, float(selection_values[2]))
	return {
		"shape": "circle",
		"movement_radius": radius,
		"selection_radius": selection_radius,
		"selection_height": selection_height,
		"occupied_cells": [],
	}


static func occupied_cells(center: Vector2, half_size: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var minimum := Vector2i(floori(center.x - half_size.x + 0.5), floori(center.y - half_size.y + 0.5))
	var maximum := Vector2i(floori(center.x + half_size.x - 0.5), floori(center.y + half_size.y - 0.5))
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			cells.append(Vector2i(x, y))
	return cells


static func push_priority_for(kind: String, behavior_tags: Array = []) -> int:
	if "ranged" in behavior_tags:
		return 1
	if "worker" in behavior_tags:
		return 2
	if "melee" in behavior_tags:
		return 3
	# Compatibility for the pre-runtime-catalog prototype data.
	match kind:
		"archer": return 1
		"villager": return 2
		"clubman": return 3
		_: return 2


static func separation_distance(left: Dictionary, right: Dictionary) -> float:
	return float(left.get("footprint_radius", DEFAULT_MOBILE_RADIUS)) + float(right.get("footprint_radius", DEFAULT_MOBILE_RADIUS)) + maxf(float(left.get("minimum_clearance", DEFAULT_CLEARANCE)), float(right.get("minimum_clearance", DEFAULT_CLEARANCE)))


static func displacement_share(unit: Dictionary, other: Dictionary) -> float:
	var own_priority := int(unit.get("push_priority", 1))
	var other_priority := int(other.get("push_priority", 1))
	if own_priority == other_priority:
		return 0.5
	return 0.75 if own_priority < other_priority else 0.25


# Squared distance to a cell's closed unit square. Circle tangency is legal;
# only a distance strictly below radius squared means footprint penetration.
static func circle_cell_distance_squared(position: Vector2, cell: Vector2i) -> float:
	var dx := maxf(maxf(float(cell.x) - position.x, 0.0), position.x - float(cell.x + 1))
	var dy := maxf(maxf(float(cell.y) - position.y, 0.0), position.y - float(cell.y + 1))
	return dx * dx + dy * dy


# Exact distance from a segment to the closed square, including corner grazes.
static func segment_cell_distance_squared(start: Vector2, finish: Vector2, cell: Vector2i) -> float:
	var lower := Vector2(cell)
	var upper := lower + Vector2.ONE
	var delta := finish - start
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if is_zero_approx(delta[axis]):
			if start[axis] < lower[axis] or start[axis] > upper[axis]:
				enter = 2.0
				break
		else:
			var first := (lower[axis] - start[axis]) / delta[axis]
			var last := (upper[axis] - start[axis]) / delta[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
	if enter <= leave:
		return 0.0
	var distance := minf(circle_cell_distance_squared(start, cell), circle_cell_distance_squared(finish, cell))
	for corner in [lower, upper, Vector2(lower.x, upper.y), Vector2(upper.x, lower.y)]:
		distance = minf(distance, Vector2(corner).distance_squared_to(Geometry2D.get_closest_point_to_segment(corner, start, finish)))
	return distance
