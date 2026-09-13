class_name RoRPlayerControlState
extends RefCounted

var player_id: int
var _selected: Dictionary = {}


func _init(owner_player_id: int = 0) -> void:
	player_id = owner_player_id


func clear() -> void:
	_selected.clear()


func apply_selection(eligible_ids: Array[int], hit_ids: Array[int], additive: bool) -> void:
	var eligible: Dictionary = {}
	for entity_id in eligible_ids:
		eligible[int(entity_id)] = true
	if not additive:
		_selected.clear()
	for entity_id_value in hit_ids:
		var entity_id := int(entity_id_value)
		if not eligible.has(entity_id):
			continue
		if additive and _selected.has(entity_id):
			_selected.erase(entity_id)
		else:
			_selected[entity_id] = true
	prune(eligible_ids)


func replace_or_add(entity_ids: Array[int], additive: bool) -> void:
	if not additive:
		_selected.clear()
	for entity_id in entity_ids:
		_selected[int(entity_id)] = true


func prune(available_ids: Array[int]) -> void:
	var available: Dictionary = {}
	for entity_id in available_ids:
		available[int(entity_id)] = true
	for entity_id in _selected.keys():
		if not available.has(int(entity_id)):
			_selected.erase(entity_id)


func is_selected(entity_id: int) -> bool:
	return _selected.has(entity_id)


func selected_ids() -> Array[int]:
	var result: Array[int] = []
	for entity_id in _selected.keys():
		result.append(int(entity_id))
	result.sort()
	return result
