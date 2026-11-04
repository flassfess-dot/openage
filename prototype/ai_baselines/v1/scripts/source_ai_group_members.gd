extends RefCounted

static func index_members(members: Array) -> Dictionary:
	var units_by_id: Dictionary = {}
	for member_value in members:
		var member: Dictionary = member_value
		units_by_id[int(member.get("id", -1))] = member
	return units_by_id


static func select_commander(ids: Array[int], units_by_id: Dictionary, commander_selection_method: int) -> int:
	if commander_selection_method not in [0, 1, 2]:
		return -1
	var candidates: Array = []
	for entity_id in ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and float(unit.get("hp", 0.0)) > 0.0:
			candidates.append(unit)
	if candidates.is_empty():
		return -1
	candidates.sort_custom(func(left, right):
		var left_metric := float(left.get("attack_range", 0.0)) if commander_selection_method == 2 else float(left.get("hp", 0.0))
		var right_metric := float(right.get("attack_range", 0.0)) if commander_selection_method == 2 else float(right.get("hp", 0.0))
		if not is_equal_approx(left_metric, right_metric):
			return left_metric < right_metric if commander_selection_method == 1 else left_metric > right_metric
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	return int(candidates[0].get("id", -1))
