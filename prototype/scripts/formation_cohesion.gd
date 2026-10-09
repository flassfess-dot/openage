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
		_update_group(members)
		_mark_shared_motion(members)
	_mark_isolated_shared_groups(groups, ungrouped_units, maximum_unit_radius, maximum_unit_clearance)


static func update_active_groups(
	group_records: Dictionary,
	units_by_id: Dictionary,
	has_external_unit_in_bounds: Callable,
	maximum_unit_radius: float,
	maximum_unit_clearance: float,
	delta: float = 0.05,
	open_envelopes: Dictionary = {},
	grid_revision: int = -1
) -> void:
	# The controller already owns the authoritative, ordered member lists. Use
	# those instead of rebuilding groups by scanning every world unit. External
	# isolation is resolved through the spatial hash below, avoiding the former
	# group-pair and group-versus-all-units passes.
	var groups: Dictionary = {}
	var group_ids: Array = group_records.keys()
	group_ids.sort()
	for group_id_value in group_ids:
		var group_id := int(group_id_value)
		var group = group_records[group_id_value]
		var members: Array = []
		for member_id_value in group.member_ids:
			var unit = units_by_id.get(int(member_id_value))
			if unit == null or float(unit.get("hp", 0.0)) <= 0.0:
				continue
			if int(unit.get("formation_group_id", -1)) != group_id:
				continue
			unit.erase("formation_steering_target")
			unit["cohesion_speed_scale"] = 1.0
			unit["formation_shared_motion"] = false
			unit["formation_shared_isolated"] = false
			members.append(unit)
		if not members.is_empty():
			groups[group_id] = members
	for members_value in groups.values():
		var members: Array = members_value
		var march_speed := _update_group(members)
		var group = group_records[int(members[0]["formation_group_id"])]
		group.march_speed = march_speed
		_steer_open_group(group, members, delta, open_envelopes, grid_revision)
		_mark_shared_motion(members)
	_mark_isolated_shared_groups_spatial(groups, has_external_unit_in_bounds, maximum_unit_radius, maximum_unit_clearance)


static func remaining_distance(unit: Dictionary) -> float:
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	if path.is_empty() or path_index >= path.size():
		return unit["pos"].distance_to(unit.get("destination", unit["pos"]))
	# Published paths are immutable; only the cursor advances. Identity also
	# invalidates a replacement path with the same number of waypoints.
	var cache: Dictionary = unit.get("_formation_path_cache", {})
	if not is_same(cache.get("path"), path):
		var suffix := PackedFloat64Array()
		suffix.resize(path.size())
		for index in range(path.size() - 2, -1, -1):
			suffix[index] = suffix[index + 1] + path[index].distance_to(path[index + 1])
		cache = {"path": path, "suffix": suffix}
		unit["_formation_path_cache"] = cache
	return unit["pos"].distance_to(path[path_index]) + float(cache["suffix"][path_index])


static func _update_group(members: Array) -> float:
	var active: Array = []
	var distances := PackedFloat64Array()
	var march_speed := INF
	var minimum := INF
	var maximum := 0.0
	for unit in members:
		if String(unit.get("task", "")) not in ["move", "attack_move"] or int(unit.get("stuck_ticks", 0)) >= DETACH_STUCK_TICKS: continue
		var speed := float(unit.get("speed", 0.0))
		if speed <= 0.0: continue
		var remaining := remaining_distance(unit)
		active.append(unit)
		distances.append(remaining)
		march_speed = minf(march_speed, speed)
		minimum = minf(minimum, remaining)
		maximum = maxf(maximum, remaining)
	if active.is_empty(): return 0.0
	var pressure := clampf((maximum - minimum - COHESION_TOLERANCE) / 3.0, 0.0, 1.0)
	for index in range(active.size()):
		var unit: Dictionary = active[index]
		var requested := march_speed
		if distances[index] <= minimum + FRONT_BAND:
			requested *= lerpf(1.0, MIN_FRONT_SCALE, pressure)
		elif distances[index] >= maximum - REAR_BAND:
			# Catch-up uses spare speed, never accelerates a siege engine beyond
			# its actual unit stats simply because cavalry joined the selection.
			requested *= lerpf(1.0, MAX_CATCHUP_SCALE, pressure)
		unit["cohesion_speed_scale"] = minf(1.0, requested / float(unit["speed"]))
	return march_speed


static func _steer_open_group(group, members: Array, delta: float, envelopes: Dictionary, grid_revision: int) -> void:
	# A moving reference frame is safe only inside the already validated open
	# envelope. Chokepoints retain their common corridor waypoints and collision
	# resolution; no per-tick path queries are introduced by this steering.
	if group.march_speed <= 0.0 or group.has_compression: return
	var moving: Array = []
	var observed_center := Vector2.ZERO
	for unit in members:
		if String(unit.get("task", "")) not in ["move", "attack_move"]: continue
		var envelope: Dictionary = envelopes.get(int(unit["id"]), {})
		if envelope.is_empty() or int(envelope.get("grid_revision", -1)) != grid_revision: return
		if int(unit.get("stuck_ticks", 0)) >= DETACH_STUCK_TICKS: continue
		var slot: Dictionary = group.slot_for(int(unit["id"]))
		if slot.is_empty(): return
		observed_center += Vector2(unit["pos"]) - (Vector2(slot["world"]) - group.anchor)
		moving.append(unit)
	if moving.is_empty(): return
	observed_center /= float(moving.size())
	var direction: Vector2 = (group.anchor - group.march_anchor).normalized()
	var candidate: Vector2 = group.march_anchor.move_toward(group.anchor, group.march_speed * delta)
	if (candidate - observed_center).dot(direction) > COHESION_TOLERANCE:
		candidate = group.march_anchor
	group.march_anchor = candidate
	var lead: Vector2 = candidate.move_toward(group.anchor, maxf(0.75, group.march_speed * 0.4))
	for unit in moving:
		var slot: Dictionary = group.slot_for(int(unit["id"]))
		var target: Vector2 = lead + Vector2(slot["world"]) - group.anchor
		var final_direction: Vector2 = Vector2(unit["destination"]) - Vector2(unit["pos"])
		# Short retreat commands start immediately. Never ask a front unit to
		# walk backwards just to join the moving reference frame.
		if (target - Vector2(unit["pos"])).dot(final_direction) > 0.0 and candidate.distance_to(group.anchor) > 1.0:
			unit["formation_steering_target"] = target


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
		String(unit["task"]) in ["move", "attack_move"]
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


static func _mark_isolated_shared_groups_spatial(
	groups: Dictionary,
	has_external_unit_in_bounds: Callable,
	maximum_unit_radius: float,
	maximum_unit_clearance: float
) -> void:
	for group_id_value in groups.keys():
		var group_id := int(group_id_value)
		var members: Array = groups[group_id_value]
		if members.is_empty() or not bool(members[0]["formation_shared_motion"]):
			continue
		var maximum_member_radius := 0.0
		for member in members:
			maximum_member_radius = maxf(maximum_member_radius, float(member["footprint_radius"]))
		var margin := 1.6 * (maximum_member_radius + maximum_unit_radius + maximum_unit_clearance)
		var nearby_bounds := _member_bounds(members).grow(margin)
		var isolated := not bool(has_external_unit_in_bounds.call(nearby_bounds, group_id))
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
