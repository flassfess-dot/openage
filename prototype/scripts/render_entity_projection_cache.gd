class_name RoRRenderEntityProjectionCache
extends RefCounted

# Retained, read-only presentation projections. The simulation owns the source
# records; render snapshots reuse these small dictionaries and refresh only the
# fields that can change during a match. Consumers must treat returned records
# as immutable.

var projections_by_id: Dictionary = {}
var categories_by_id: Dictionary = {}


func clear() -> void:
	projections_by_id.clear()
	categories_by_id.clear()


func project(entity: Dictionary) -> Dictionary:
	var entity_id := int(entity.get("id", -1))
	var result: Dictionary = projections_by_id.get(entity_id, {})
	if result.is_empty():
		result = _create_projection(entity)
		if entity_id >= 0:
			projections_by_id[entity_id] = result
			categories_by_id[entity_id] = _category(entity)
	_update_projection(result, entity, String(categories_by_id.get(entity_id, _category(entity))))
	return result


func _create_projection(entity: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in [
		"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
		"pos", "previous_pos",
		"elevation", "source_elevation", "visual_height", "max_hp", "max_amount",
		"logical_only", "visible_when_depleted", "harvestable", "resource_type_id",
		"building_type", "movement_domain", "footprint_radius", "selection_radius",
		"selection_height", "source_frame", "source_graphic_id", "source_graphic_asset_name",
		"source_requested_graphic_asset_name", "source_asset_fallback_reason",
		"source_depleted_graphic_id", "source_depleted_asset_name", "combat_enabled",
	]:
		if entity.has(key):
			result[key] = entity[key]
	for array_key in ["behavior_tags", "unit_lineage", "allowed_gatherer_domains"]:
		if entity.has(array_key):
			result[array_key] = entity.get(array_key, []).duplicate()
	if entity.has("footprint"):
		result["footprint"] = entity.get("footprint", {}).duplicate(true)
	var source_components: Dictionary = entity.get("components", {})
	var components: Dictionary = {}
	var ownership: Dictionary = source_components.get("ownership", {})
	if not ownership.is_empty():
		components["ownership"] = {"civilization_id": int(ownership.get("civilization_id", 13))}
	for component_name in ["worker", "conversion", "healing"]:
		var component: Dictionary = source_components.get(component_name, {})
		if not component.is_empty():
			components[component_name] = {"enabled": bool(component.get("enabled", false))}
	var cargo: Dictionary = source_components.get("cargo", {})
	if not cargo.is_empty():
		components["cargo"] = {
			"enabled": bool(cargo.get("enabled", false)),
			"capacity": maxi(0, int(cargo.get("capacity", 0))),
		}
	var trade: Dictionary = source_components.get("trade", {})
	if not trade.is_empty():
		components["trade"] = {
			"enabled": bool(trade.get("enabled", false)),
			"target_building_source_id": int(trade.get("target_building_source_id", -1)),
		}
	result["components"] = components
	return result


func _update_projection(result: Dictionary, entity: Dictionary, category: String) -> void:
	var keys: Array
	match category:
		"resource":
			keys = ["amount", "state", "resource_state", "depletion_stage", "display_graphic_id"]
		"building":
			keys = [
				"team", "entity_type", "hp", "state", "resource_state", "amount",
				"construction_stage", "construction_progress", "display_graphic_id",
				"anim", "anim_state", "death_phase", "death_elapsed",
			]
		_:
			keys = [
				"team", "kind", "entity_type", "source_unit_id", "pos", "previous_pos",
				"elevation", "visual_height", "hp", "max_hp", "display_graphic_id",
				"source_graphic_id", "source_graphic_asset_name", "anim", "anim_state",
				"facing", "presentation_facing", "death_phase", "death_elapsed",
				"combat_enabled", "task", "target_id", "target_building_id",
				"formation_forward", "carried_amount",
			]
	for key in keys:
		if entity.has(key):
			result[key] = entity[key]


func _category(entity: Dictionary) -> String:
	var entity_type := String(entity.get("entity_type", ""))
	if entity_type == "resource" or (entity.has("resource_type_id") and not entity.has("team")):
		return "resource"
	if entity_type in ["building", "foundation"] or entity.has("production_queue"):
		return "building"
	return "unit"
