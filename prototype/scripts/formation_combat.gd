class_name RoRFormationCombat

const MELEE_RANGE_THRESHOLD: float = 1.0
const CONTACT_ARC_STEP: float = PI / 4.0
const RANGED_LATERAL_SPACING: float = 0.75


static func role_for(unit: Dictionary) -> String:
	return "ranged" if float(unit.get("attack_range", 0.0)) > MELEE_RANGE_THRESHOLD else "melee"


static func destination(unit: Dictionary, target: Dictionary) -> Vector2:
	var approach: Vector2 = unit.get("combat_approach", unit["pos"] - target["pos"])
	if approach.length_squared() <= 0.0001:
		approach = Vector2(-1, 0)
	approach = approach.normalized()
	var lateral := Vector2(-approach.y, approach.x)
	var index := int(unit.get("combat_slot_index", 0))
	if role_for(unit) == "ranged":
		var count := maxi(1, int(unit.get("combat_slot_count", 1)))
		var offset := (float(index) - float(count - 1) * 0.5) * RANGED_LATERAL_SPACING
		var minimum_range := float(unit.get("components", {}).get("combat", {}).get("range_min", 0.0))
		var occupied_radius := float(target.get("footprint_radius", 0.3)) + float(unit.get("footprint_radius", 0.3))
		var stand_off := maxf(maxf(1.2, float(unit.get("attack_range", 1.2)) * 0.82), minimum_range + occupied_radius + 0.15)
		if _is_polygon_target(target):
			var angular_offset := clampf(offset * 0.12, -PI * 0.28, PI * 0.28)
			var direction := approach.rotated(angular_offset).normalized()
			var desired_edge_distance := maxf(0.0, stand_off - occupied_radius)
			return _polygon_destination(unit, target, direction, desired_edge_distance)
		return target["pos"] + approach * stand_off + lateral * offset
	var ring := index / 8
	var position_in_ring := index % 8
	var signed_step := 0
	if position_in_ring > 0:
		signed_step = (position_in_ring + 1) / 2
		if position_in_ring % 2 == 0:
			signed_step = -signed_step
	var angle := float(signed_step) * CONTACT_ARC_STEP
	var target_radius := float(target.get("footprint_radius", 0.3))
	var unit_radius := float(unit.get("footprint_radius", 0.3))
	var ring_offset := float(ring) * (unit_radius * 2.0 + 0.12)
	var direction := approach.rotated(angle).normalized()
	if _is_polygon_target(target):
		return _polygon_destination(unit, target, direction, 0.08 + ring_offset)
	var contact_radius := target_radius + unit_radius + 0.08 + ring_offset
	return target["pos"] + direction * contact_radius


static func _is_polygon_target(target: Dictionary) -> bool:
	return String(target.get("footprint", {}).get("shape", "")) == "polygon"


static func _polygon_destination(unit: Dictionary, target: Dictionary, direction: Vector2, desired_edge_distance: float) -> Vector2:
	var center := Vector2(target.get("pos", Vector2.ZERO))
	var half_size := Vector2(target.get("footprint", {}).get("half_size", Vector2.ONE * float(target.get("footprint_radius", 0.5))))
	var unit_radius := maxf(0.0, float(unit.get("footprint_radius", 0.3)))
	# The occupied cells, rather than the art-selection rectangle, are the shared
	# physical boundary for movement and combat. Imported building centers are not
	# necessarily half-cell aligned, so mixing both representations creates a gap
	# where a unit can neither walk nor attack.
	var occupied_bounds := _occupied_world_bounds(target.get("occupied_cells", []), center - half_size, center + half_size)
	var combat_padding := unit_radius + maxf(0.0, desired_edge_distance)
	var combat_minimum: Vector2 = occupied_bounds[0] - Vector2.ONE * combat_padding
	var combat_maximum: Vector2 = occupied_bounds[1] + Vector2.ONE * combat_padding
	var combat_exit := _ray_exit_distance(center, direction, combat_minimum, combat_maximum)
	var navigation_padding := unit_radius + 0.02
	var navigation_minimum: Vector2 = occupied_bounds[0] - Vector2.ONE * navigation_padding
	var navigation_maximum: Vector2 = occupied_bounds[1] + Vector2.ONE * navigation_padding
	var navigation_exit := _ray_exit_distance(center, direction, navigation_minimum, navigation_maximum)
	return center + direction * maxf(combat_exit, navigation_exit)


static func _occupied_world_bounds(cells: Array, fallback_minimum: Vector2, fallback_maximum: Vector2) -> Array[Vector2]:
	if cells.is_empty():
		return [fallback_minimum, fallback_maximum]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for cell_value in cells:
		var cell := Vector2(Vector2i(cell_value))
		minimum.x = minf(minimum.x, cell.x)
		minimum.y = minf(minimum.y, cell.y)
		maximum.x = maxf(maximum.x, cell.x + 1.0)
		maximum.y = maxf(maximum.y, cell.y + 1.0)
	return [minimum, maximum]


static func _ray_exit_distance(center: Vector2, direction: Vector2, minimum: Vector2, maximum: Vector2) -> float:
	var x_exit := INF
	var y_exit := INF
	if direction.x > 0.000001:
		x_exit = (maximum.x - center.x) / direction.x
	elif direction.x < -0.000001:
		x_exit = (minimum.x - center.x) / direction.x
	if direction.y > 0.000001:
		y_exit = (maximum.y - center.y) / direction.y
	elif direction.y < -0.000001:
		y_exit = (minimum.y - center.y) / direction.y
	return maxf(0.0, minf(x_exit, y_exit))


static func assign_slots(units: Array, target: Dictionary) -> void:
	var melee: Array = []
	var ranged: Array = []
	var ordered := units.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	for unit in ordered:
		if role_for(unit) == "ranged":
			ranged.append(unit)
		else:
			melee.append(unit)
	_assign_role_slots(melee, target, "melee")
	_assign_role_slots(ranged, target, "ranged")


static func _assign_role_slots(units: Array, target: Dictionary, role: String) -> void:
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var approach: Vector2 = unit["pos"] - target["pos"]
		if approach.length_squared() <= 0.0001:
			var formation_forward: Vector2 = unit.get("formation_forward", Vector2(1, 0))
			approach = -formation_forward if formation_forward.length_squared() > 0.0001 else Vector2(-1, 0)
		unit["combat_role"] = role
		unit["combat_slot_index"] = index
		unit["combat_slot_count"] = units.size()
		unit["combat_approach"] = approach.normalized()
		unit["combat_destination"] = destination(unit, target)
