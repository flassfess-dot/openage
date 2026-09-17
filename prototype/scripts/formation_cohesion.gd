class_name RoRFormationCohesion

const COHESION_TOLERANCE: float = 1.35
const FRONT_BAND: float = 0.35
const REAR_BAND: float = 0.35
const MIN_FRONT_SCALE: float = 0.58
const MAX_CATCHUP_SCALE: float = 1.32
const DETACH_STUCK_TICKS: int = 18
const SHARED_DISPLACEMENT_TOLERANCE: float = 0.04
const SHARED_SPEED_TOLERANCE: float = 0.0001


static func update(units: Array) -> void:
	var groups: Dictionary = {}
	var ungrouped_units: Array = []
	var maximum_unit_radius := 0.0
	var maximum_unit_clearance := 0.0
	for unit in units:
		unit["cohesion_speed_scale"] = 1.0
		unit["formation_shared_motion"] = false
		unit["formation_shared_isolated"] = false
		if float(unit.get("hp", 0.0)) > 0.0:
			maximum_unit_radius = maxf(maximum_unit_radius, float(unit.get("footprint_radius", 0.0)))
			maximum_unit_clearance = maxf(maximum_unit_clearance, float(unit.get("minimum_clearance", 0.0)))
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var group_id := int(unit.get("formation_group_id", -1))
		if group_id < 0:
			ungrouped_units.append(unit)
			continue
		if not groups.has(group_id):
			groups[group_id] = []
		groups[group_id].append(unit)
	for members in groups.values():
		if members.any(func(member): return String(member.get("task", "")) != "move"):
			continue
		_mark_shared_motion(members)
		if not bool(members[0]["formation_shared_motion"]):
			_update_group(members)
	_mark_isolated_shared_groups(groups, ungrouped_units, maximum_unit_radius, maximum_unit_clearance)


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


static func _mark_shared_motion(members: Array) -> void:
	# When every member has the same remaining displacement, speed and safe slot
	# spacing, the group can translate rigidly. Pairwise distances are invariant,
	# so members of this group cannot collide with one another during this tick.
	# Any deformation, recovery, target change or slower member disables the fast
	# path on the next tick and restores complete individual avoidance.
	if members.size() < 2:
		return
	var first: Dictionary = members[0]
	if not _eligible_for_shared_motion(first):
		return
	var shared_displacement: Vector2 = first["target"] - first["pos"]
	if shared_displacement.length_squared() <= SHARED_DISPLACEMENT_TOLERANCE * SHARED_DISPLACEMENT_TOLERANCE:
		return
	var shared_speed := float(first["speed"]) * float(first["cohesion_speed_scale"])
	var maximum_radius := float(first["footprint_radius"])
	var maximum_clearance := float(first["minimum_clearance"])
	var minimum_slot_distance := float(first.get("formation_slot_capacity", 0.45)) * 2.0
	for index in range(1, members.size()):
		var unit: Dictionary = members[index]
		if not _eligible_for_shared_motion(unit):
			return
		var displacement: Vector2 = unit["target"] - unit["pos"]
		if displacement.distance_squared_to(shared_displacement) > SHARED_DISPLACEMENT_TOLERANCE * SHARED_DISPLACEMENT_TOLERANCE:
			return
		var effective_speed := float(unit["speed"]) * float(unit["cohesion_speed_scale"])
		if absf(effective_speed - shared_speed) > SHARED_SPEED_TOLERANCE:
			return
		maximum_radius = maxf(maximum_radius, float(unit["footprint_radius"]))
		maximum_clearance = maxf(maximum_clearance, float(unit["minimum_clearance"]))
		minimum_slot_distance = minf(minimum_slot_distance, float(unit.get("formation_slot_capacity", 0.45)) * 2.0)
	if maximum_radius * 2.0 + maximum_clearance > minimum_slot_distance:
		return
	for unit in members:
		unit["formation_shared_motion"] = true


static func _eligible_for_shared_motion(unit: Dictionary) -> bool:
	return (
		String(unit["task"]) == "move"
		and String(unit.get("formation_slot_mode", "soft")) == "soft"
		and int(unit["stuck_ticks"]) == 0
		and not unit["path"].is_empty()
	)


static func _mark_isolated_shared_groups(groups: Dictionary, ungrouped_units: Array, maximum_unit_radius: float, maximum_unit_clearance: float) -> void:
	# A group-level broad phase replaces hundreds of equivalent member queries
	# while formations are far apart. The grown AABB is conservative relative to
	# LocalMovement's exact 1.6 * (both radii + clearance) interaction threshold.
	var bounds_by_group: Dictionary = {}
	for group_id_value in groups.keys():
		bounds_by_group[int(group_id_value)] = _member_bounds(groups[group_id_value])
	for group_id_value in groups.keys():
		var group_id := int(group_id_value)
		var members: Array = groups[group_id]
		if members.is_empty() or not bool(members[0]["formation_shared_motion"]):
			continue
		var maximum_member_radius := 0.0
		for member in members:
			maximum_member_radius = maxf(maximum_member_radius, float(member["footprint_radius"]))
		var margin := 1.6 * (maximum_member_radius + maximum_unit_radius + maximum_unit_clearance)
		var nearby_bounds: Rect2 = bounds_by_group[group_id].grow(margin)
		var isolated := true
		for other_group_id_value in bounds_by_group.keys():
			var other_group_id := int(other_group_id_value)
			if other_group_id == group_id:
				continue
			if nearby_bounds.intersects(bounds_by_group[other_group_id], true):
				isolated = false
				break
		if isolated:
			for candidate in ungrouped_units:
				if nearby_bounds.has_point(Vector2(candidate["pos"])):
					isolated = false
					break
		if isolated:
			for member in members:
				member["formation_shared_isolated"] = true


static func _member_bounds(members: Array) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for member in members:
		var position: Vector2 = member["pos"]
		minimum = Vector2(minf(minimum.x, position.x), minf(minimum.y, position.y))
		maximum = Vector2(maxf(maximum.x, position.x), maxf(maximum.y, position.y))
	return Rect2(minimum, maximum - minimum)
