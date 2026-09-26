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


static func same_type_visible_ids(units: Array, clicked: Dictionary, player_team: int, viewport: Rect2, project_position: Callable) -> Array[int]:
	var result: Array[int] = []
	if int(clicked.get("team", 0)) != player_team or String(clicked.get("entity_type", "unit")) != "unit":
		return result
	var source_id := int(clicked.get("source_unit_id", -1))
	var kind := String(clicked.get("kind", ""))
	for value in units:
		var unit: Dictionary = value
		if int(unit.get("team", 0)) != player_team or float(unit.get("hp", 0.0)) <= 0.0:
			continue
		if String(unit.get("entity_type", "unit")) != "unit":
			continue
		if source_id >= 0:
			if int(unit.get("source_unit_id", -1)) != source_id:
				continue
		elif String(unit.get("kind", "")) != kind:
			continue
		var position_value: Variant = unit.get("pos")
		if not position_value is Vector2 or not viewport.has_point(project_position.call(position_value)):
			continue
		result.append(int(unit.get("id", -1)))
	result.sort()
	return result
