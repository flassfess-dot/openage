class_name RoRFormationAssignment

const Roles := preload("res://scripts/formation_roles.gd")

const RETENTION_BONUS: float = 1000000.0
const SIZE_PENALTY: float = 10000.0
const ROLE_WEIGHT: float = 25.0


static func assign(units: Array, slots: Array, previous_assignments: Dictionary = {}) -> Dictionary:
	if units.is_empty() or slots.is_empty():
		return {}
	var ordered := units.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	var count := mini(ordered.size(), slots.size())
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
