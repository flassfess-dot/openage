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
var native_context: Dictionary = {}
var compare_native_versions := "--compare-native-journal-render" in OS.get_cmdline_user_args()
var native_version_queries := 0
var native_version_comparisons := 0
var native_version_mismatches := 0
const MAX_PROJECTIONS := 65536

func clear() -> void:
	native_context.clear()
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
		for entity in entities: result.append(_project_script(entity, journal))
		return result
	journal.flush()
	if epoch != int(journal.epoch):
		clear()
		epoch = int(journal.epoch)
	var result: Array = _project_native_rows(entities, journal)
	if result.size() == entities.size(): return result
	result = []
	for entity in entities: result.append(_project_script(entity, journal))
	return result


func project(entity: Dictionary, journal = null) -> Dictionary:
	if Contract.is_render_record(entity): return entity
	if journal != null and journal.native_active and journal.native_direct_readers and native_kernel != null and native_kernel.has_method("project_cached_render_entities") and Contract.native_enabled:
		journal.flush()
		if epoch != int(journal.epoch):
			clear()
			epoch = int(journal.epoch)
		var result: Array = _project_native_rows([entity], journal)
		if result.size() == 1: return result[0]
	return _project_script(entity, journal)


func _native_context(journal) -> Dictionary:
	if native_context.is_empty():
		native_context = {"records":projections_by_id,"versions":versions_by_id,"categories":categories_by_id,"groups":GROUP_FIELDS,"fields":Contract.RENDER_FIELDS,"nested":Contract.NESTED_FIELDS,"schema":Contract.SCHEMA_VERSION,"capacity":MAX_PROJECTIONS}
	native_context["journal"] = journal.version_source()
	return native_context


func _project_native_rows(entities: Array, journal) -> Array:
	if compare_native_versions: native_version_queries += 1
	var context := _native_context(journal)
	var reference := {}
	if compare_native_versions and journal.native_active and native_version_comparisons < 64 and (native_version_comparisons < 8 or native_version_queries % 128 == 0):
		reference = context.duplicate()
		for field in ["records", "versions", "categories"]: reference[field] = context[field].duplicate()
		reference["journal"] = journal.versions_by_id
	var result: Array = native_kernel.project_cached_render_entities(entities, context)
	if not reference.is_empty():
		var expected: Array = native_kernel.project_cached_render_entities(entities, reference)
		native_version_comparisons += 1
		if expected != result or reference["records"] != projections_by_id or reference["versions"] != versions_by_id or reference["categories"] != categories_by_id:
			native_version_mismatches += 1
			push_error("Native journal render versions differ from the compatibility index")
	return result


func _project_script(entity: Dictionary, journal = null) -> Dictionary:
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
