class_name RoRFormationCohesion

const COHESION_TOLERANCE: float = 1.35
const FRONT_BAND: float = 0.35
const REAR_BAND: float = 0.35
const MIN_FRONT_SCALE: float = 0.58
const MAX_CATCHUP_SCALE: float = 1.32
const DETACH_STUCK_TICKS: int = 18


static func update(units: Array) -> void:
	var groups: Dictionary = {}
	for unit in units:
		unit["cohesion_speed_scale"] = 1.0
		var group_id := int(unit.get("formation_group_id", -1))
		if group_id < 0 or float(unit.get("hp", 0.0)) <= 0.0 or String(unit.get("task", "")) != "move":
			continue
		if not groups.has(group_id):
			groups[group_id] = []
		groups[group_id].append(unit)
	for members in groups.values():
		_update_group(members)


static func remaining_distance(unit: Dictionary) -> float:
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	if path.is_empty() or path_index >= path.size():
		return unit["pos"].distance_to(unit.get("destination", unit["pos"]))
	var total: float = unit["pos"].distance_to(path[path_index])
	for index in range(path_index + 1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


static func _update_group(members: Array) -> void:
	var active_units: Array = []
	var remaining_distances := PackedFloat64Array()
	for unit in members:
		if int(unit.get("stuck_ticks", 0)) < DETACH_STUCK_TICKS:
			active_units.append(unit)
			remaining_distances.append(remaining_distance(unit))
	if active_units.size() < 2:
		return
	var minimum_remaining := INF
	var maximum_remaining := 0.0
	for remaining in remaining_distances:
		minimum_remaining = minf(minimum_remaining, remaining)
		maximum_remaining = maxf(maximum_remaining, remaining)
	var spread := maximum_remaining - minimum_remaining
	if spread <= COHESION_TOLERANCE:
		return
	var pressure := clampf((spread - COHESION_TOLERANCE) / 3.0, 0.0, 1.0)
	for index in range(active_units.size()):
		var remaining := remaining_distances[index]
		var unit: Dictionary = active_units[index]
		if remaining <= minimum_remaining + FRONT_BAND:
			unit["cohesion_speed_scale"] = lerpf(1.0, MIN_FRONT_SCALE, pressure)
		elif remaining >= maximum_remaining - REAR_BAND:
			unit["cohesion_speed_scale"] = lerpf(1.0, MAX_CATCHUP_SCALE, pressure)
