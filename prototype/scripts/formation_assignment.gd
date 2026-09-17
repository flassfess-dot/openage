class_name RoRFormationAssignment

const Roles := preload("res://scripts/formation_roles.gd")

const RETENTION_BONUS: float = 1000000.0
const SIZE_PENALTY: float = 10000.0
const ROLE_WEIGHT: float = 25.0
const EXACT_ASSIGNMENT_LIMIT: int = 64
const ROLE_ORDER := [
	Roles.HEAVY_INFANTRY,
	Roles.LIGHT_INFANTRY,
	Roles.RANGED,
	Roles.PRIEST,
	Roles.SIEGE,
	Roles.CIVILIAN,
]


static func assign(units: Array, slots: Array, previous_assignments: Dictionary = {}) -> Dictionary:
	if units.is_empty() or slots.is_empty():
		return {}
	var ordered := units.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	var count := mini(ordered.size(), slots.size())
	if count > EXACT_ASSIGNMENT_LIMIT:
		return _assign_scalable(ordered, slots, count, previous_assignments)
	var costs: Array = []
	for row in range(count):
		var row_costs: Array[float] = []
		var unit: Dictionary = ordered[row]
		for column in range(count):
			var slot: Dictionary = slots[column]
			var cost: float = unit["pos"].distance_squared_to(slot["world"])
			cost += Roles.slot_cost(String(unit.get("kind", "")), slot, slots) * ROLE_WEIGHT
			var radius := float(unit.get("footprint_radius", 0.3))
			var capacity := float(slot.get("capacity_radius", INF))
			if radius > capacity:
				cost += SIZE_PENALTY * (radius - capacity + 1.0)
			if int(previous_assignments.get(int(unit["id"]), -1)) == int(slot["slot_id"]) and radius <= capacity:
				cost -= RETENTION_BONUS
			row_costs.append(cost)
		costs.append(row_costs)
	var columns := _hungarian(costs)
	var result: Dictionary = {}
	for row in range(columns.size()):
		result[int(ordered[row]["id"])] = int(slots[columns[row]]["slot_id"])
	return result


static func _assign_scalable(ordered_units: Array, slots: Array, count: int, previous_assignments: Dictionary) -> Dictionary:
	# Hungarian assignment is valuable for small tactical groups but cubic work
	# is not acceptable for the 500-member formations supported by the runtime.
	# Large groups retain valid slots, allocate role bands, then pair members and
	# slots in deterministic spatial order (O(N log N)).
	var slots_by_id: Dictionary = {}
	for slot in slots:
		slots_by_id[int(slot["slot_id"])] = slot
	var result: Dictionary = {}
	var used_slots: Dictionary = {}
	var remaining_units: Array = []
	for index in range(count):
		var unit: Dictionary = ordered_units[index]
		var entity_id := int(unit["id"])
		var previous_slot_id := int(previous_assignments.get(entity_id, -1))
		var previous_slot: Variant = slots_by_id.get(previous_slot_id)
		if previous_slot != null and not used_slots.has(previous_slot_id) and float(unit.get("footprint_radius", 0.3)) <= float(previous_slot.get("capacity_radius", INF)):
			result[entity_id] = previous_slot_id
			used_slots[previous_slot_id] = true
		else:
			remaining_units.append(unit)

	var available_slots: Array = []
	for slot in slots:
		if not used_slots.has(int(slot["slot_id"])):
			available_slots.append(slot)
	var role_units: Dictionary = {}
	for role in ROLE_ORDER:
		role_units[role] = []
	for unit in remaining_units:
		var role := Roles.role_for(String(unit.get("kind", "")))
		if not role_units.has(role):
			role_units[role] = []
		role_units[role].append(unit)
	var middle_y := _slot_middle_y(slots)
	for role in ROLE_ORDER:
		var members: Array = role_units.get(role, [])
		if members.is_empty():
			continue
		members.sort_custom(_unit_spatial_less)
		available_slots.sort_custom(func(left, right): return _role_slot_less(role, left, right, middle_y))
		var selected_slots: Array = available_slots.slice(0, members.size())
		available_slots = available_slots.slice(members.size())
		selected_slots.sort_custom(_slot_spatial_less)
		for member_index in range(members.size()):
			result[int(members[member_index]["id"])] = int(selected_slots[member_index]["slot_id"])
	return result


static func _slot_middle_y(slots: Array) -> float:
	var minimum_y := INF
	var maximum_y := -INF
	for slot in slots:
		var local: Vector2 = slot.get("local", slot.get("world", Vector2.ZERO))
		minimum_y = minf(minimum_y, local.y)
		maximum_y = maxf(maximum_y, local.y)
	return (minimum_y + maximum_y) * 0.5 if not slots.is_empty() else 0.0


static func _role_slot_less(role: String, left: Dictionary, right: Dictionary, middle_y: float) -> bool:
	var left_local: Vector2 = left.get("local", left.get("world", Vector2.ZERO))
	var right_local: Vector2 = right.get("local", right.get("world", Vector2.ZERO))
	var left_key := _role_slot_key(role, left_local, middle_y)
	var right_key := _role_slot_key(role, right_local, middle_y)
	if left_key != right_key:
		return _vector3_less(left_key, right_key)
	return int(left["slot_id"]) < int(right["slot_id"])


static func _role_slot_key(role: String, local: Vector2, middle_y: float) -> Vector3:
	match role:
		Roles.HEAVY_INFANTRY:
			return Vector3(-local.y, absf(local.x), local.x)
		Roles.RANGED:
			return Vector3(local.y, absf(local.x), local.x)
		Roles.PRIEST:
			return Vector3(absf(local.x), absf(local.y - middle_y), local.y)
		Roles.SIEGE:
			return Vector3(-absf(local.x), local.y, local.x)
		Roles.CIVILIAN:
			return Vector3(absf(local.y - middle_y), absf(local.x), local.x)
		_:
			return Vector3(absf(local.y - middle_y), absf(local.x), local.x)


static func _vector3_less(left: Vector3, right: Vector3) -> bool:
	if not is_equal_approx(left.x, right.x):
		return left.x < right.x
	if not is_equal_approx(left.y, right.y):
		return left.y < right.y
	return left.z < right.z


static func _unit_spatial_less(left: Dictionary, right: Dictionary) -> bool:
	var left_position: Vector2 = left.get("pos", Vector2.ZERO)
	var right_position: Vector2 = right.get("pos", Vector2.ZERO)
	return left_position.y < right_position.y or (is_equal_approx(left_position.y, right_position.y) and (left_position.x < right_position.x or (is_equal_approx(left_position.x, right_position.x) and int(left["id"]) < int(right["id"]))))


static func _slot_spatial_less(left: Dictionary, right: Dictionary) -> bool:
	var left_position: Vector2 = left.get("world", Vector2.ZERO)
	var right_position: Vector2 = right.get("world", Vector2.ZERO)
	return left_position.y < right_position.y or (is_equal_approx(left_position.y, right_position.y) and (left_position.x < right_position.x or (is_equal_approx(left_position.x, right_position.x) and int(left["slot_id"]) < int(right["slot_id"]))))


static func total_distance_squared(units: Array, slots: Array, assignments: Dictionary) -> float:
	var slots_by_id: Dictionary = {}
	for slot in slots:
		slots_by_id[int(slot["slot_id"])] = slot
	var total := 0.0
	for unit in units:
		var entity_id := int(unit["id"])
		if assignments.has(entity_id):
			total += unit["pos"].distance_squared_to(slots_by_id[int(assignments[entity_id])]["world"])
	return total


static func _hungarian(costs: Array) -> Array[int]:
	var count := costs.size()
	var u: Array[float] = []
	var v: Array[float] = []
	var p: Array[int] = []
	var way: Array[int] = []
	for _index in range(count + 1):
		u.append(0.0)
		v.append(0.0)
		p.append(0)
		way.append(0)
	for row in range(1, count + 1):
		p[0] = row
		var column0 := 0
		var minimum: Array[float] = []
		var used: Array[bool] = []
		for _column in range(count + 1):
			minimum.append(INF)
			used.append(false)
		while true:
			used[column0] = true
			var row0 := p[column0]
			var delta := INF
			var column1 := 0
			for column in range(1, count + 1):
				if used[column]:
					continue
				var current: float = float(costs[row0 - 1][column - 1]) - u[row0] - v[column]
				if current < minimum[column]:
					minimum[column] = current
					way[column] = column0
				if minimum[column] < delta:
					delta = minimum[column]
					column1 = column
			for column in range(count + 1):
				if used[column]:
					u[p[column]] += delta
					v[column] -= delta
				else:
					minimum[column] -= delta
			column0 = column1
			if p[column0] == 0:
				break
		while true:
			var previous_column := way[column0]
			p[column0] = p[previous_column]
			column0 = previous_column
			if column0 == 0:
				break
	var result: Array[int] = []
	for _row in range(count):
		result.append(-1)
	for column in range(1, count + 1):
		if p[column] > 0:
			result[p[column] - 1] = column - 1
	return result
