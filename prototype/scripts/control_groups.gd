class_name RoRControlGroups

var groups: Dictionary = {}
var last_recalled_group: int = -1


func clear() -> void:
	groups.clear()
	last_recalled_group = -1

func assign(group_number: int, entity_ids: Array[int]) -> void:
	var normalized := normalize_ids(entity_ids)
	groups[group_number] = normalized
	last_recalled_group = -1

func recall(group_number: int, available_ids: Array[int], current_ids: Array[int], additive: bool) -> Dictionary:
	var available_lookup: Dictionary = {}
	for entity_id in available_ids:
		available_lookup[entity_id] = true

	var stored: Array[int] = groups.get(group_number, [])
	var valid: Array[int] = []
	for entity_id in stored:
		if available_lookup.has(entity_id):
			valid.append(entity_id)
	groups[group_number] = valid

	var normalized_current := normalize_ids(current_ids)
	var center_requested := not additive and not valid.is_empty() and last_recalled_group == group_number and normalized_current == valid
	var recalled: Array[int] = []
	if additive:
		recalled = normalize_ids(current_ids)
	for entity_id in valid:
		if not recalled.has(entity_id):
			recalled.append(entity_id)
	recalled.sort()
	last_recalled_group = group_number
	return {"ids": recalled, "center": center_requested}

func normalize_ids(entity_ids: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for entity_id in entity_ids:
		if entity_id > 0 and not result.has(entity_id):
			result.append(entity_id)
	result.sort()
	return result
