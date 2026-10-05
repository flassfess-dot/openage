class_name RoRRenderEntityProjectionCache
extends RefCounted
const Contract := preload("res://scripts/entity_read_contract.gd")
var projections_by_id: Dictionary = {}
var categories_by_id: Dictionary = {}

func clear() -> void:
	projections_by_id.clear()
	categories_by_id.clear()

func erase(entity_id: int) -> void:
	projections_by_id.erase(entity_id)
	categories_by_id.erase(entity_id)

func project(entity: Dictionary) -> Dictionary:
	var entity_id := int(entity.get("id", -1))
	var result: Dictionary = Contract.render(entity, projections_by_id.get(entity_id, {}))
	if entity_id >= 0:
		projections_by_id[entity_id] = result
		categories_by_id[entity_id] = Contract.category(result)
	return result

func _category(entity: Dictionary) -> String:
	return Contract.category(entity)
