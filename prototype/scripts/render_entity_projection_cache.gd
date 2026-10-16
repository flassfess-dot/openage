class_name RoRRenderEntityProjectionCache
extends RefCounted
const Contract := preload("res://scripts/entity_read_contract.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const GROUP_FIELDS := {
	2: ["pos", "previous_pos", "elevation", "source_elevation", "visual_height", "movement_domain", "footprint_radius", "facing", "formation_forward"],
	4: ["task", "target_id", "target_building_id", "resource_id", "death_phase"],
	8: ["hp", "max_hp", "combat_enabled"],
	16: ["amount", "max_amount", "resource_state", "depletion_stage", "harvestable", "resource_type_id", "carried_amount", "construction_progress", "construction_stage"],
	64: ["preferred_formation", "formation_group_id"]}
var projections_by_id: Dictionary = {}
var categories_by_id: Dictionary = {}
var versions_by_id: Dictionary = {}
var epoch := -1
var native_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
const MAX_PROJECTIONS := 65536

func clear() -> void:
	versions_by_id.clear()
	projections_by_id.clear()
	categories_by_id.clear()
	epoch = -1

func erase(entity_id: int) -> void:
	versions_by_id.erase(entity_id)
	projections_by_id.erase(entity_id)
	categories_by_id.erase(entity_id)

func project_many(entities: Array, journal) -> Array:
	if journal == null or native_kernel == null or not native_kernel.has_method("project_cached_render_entities") or not Contract.native_enabled:
		var result: Array = []
		for entity in entities: result.append(project(entity, journal))
		return result
	journal.flush()
	if epoch != int(journal.epoch):
		clear()
		epoch = int(journal.epoch)
	return native_kernel.project_cached_render_entities(entities, {"journal":journal.versions_by_id,"records":projections_by_id,"versions":versions_by_id,"categories":categories_by_id,"groups":GROUP_FIELDS,"fields":Contract.RENDER_FIELDS,"nested":Contract.NESTED_FIELDS,"schema":Contract.SCHEMA_VERSION,"capacity":MAX_PROJECTIONS})


func project(entity: Dictionary, journal = null) -> Dictionary:
	if Contract.is_render_record(entity): return entity
	var id := int(entity.get("id", -1))
	if journal == null: return Contract.render(entity)
	journal.flush()
	if epoch != int(journal.epoch):
		clear()
		epoch = int(journal.epoch)
	var versions: PackedInt64Array = journal.versions_by_id.get(id, PackedInt64Array())
	var old_versions: PackedInt64Array = versions_by_id.get(id, PackedInt64Array())
	var previous: Dictionary = projections_by_id.get(id, {})
	var mask := 0
	if versions != old_versions:
		for group in range(versions.size()):
			if old_versions.size() <= group or int(old_versions[group]) != int(versions[group]): mask |= 1 << group
	var result: Dictionary
	if previous.is_empty() or mask & (1 | 128) or versions.is_empty():
		result = Contract.render(entity, previous)
	else:
		var animation_changed: bool = float(previous.get("anim", 0.0)) != float(entity.get("anim", 0.0)) or previous.get("previous_pos") != entity.get("previous_pos")
		if mask == 0 and not animation_changed: return previous
		if not (mask & 32) and native_kernel != null and native_kernel.has_method("patch_render"):
			result = native_kernel.patch_render(entity, previous, mask, GROUP_FIELDS)
		elif mask & 32:
			# Appearance changes are rare and include archetype/component changes.
			result = Contract.render(entity, previous).duplicate()
		else:
			result = previous.duplicate()
			for group in GROUP_FIELDS:
				if not (mask & int(group)): continue
				for field in GROUP_FIELDS[group]:
					if entity.has(field): result[field] = Data.copy(entity[field])
					else: result.erase(field)
		if not result.is_read_only():
			result["anim"] = float(entity.get("anim", 0.0))
			if entity.has("previous_pos"): result["previous_pos"] = entity["previous_pos"]
			result.make_read_only()
	if id >= 0 and (projections_by_id.has(id) or projections_by_id.size() < MAX_PROJECTIONS):
		projections_by_id[id] = result
		categories_by_id[id] = Contract.category(result)
		versions_by_id[id] = versions.duplicate()
	return result
