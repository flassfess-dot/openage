class_name RoRDataRepository
extends RefCounted

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var compatibility_gamespec: Dictionary = {}


func configure_runtime(data: Dictionary) -> void:
	runtime_catalog = data


func configure_objects(data: Dictionary) -> void:
	object_catalog = data


func configure_compatibility_gamespec(data: Dictionary) -> void:
	compatibility_gamespec = data


func is_configured() -> bool:
	return not runtime_catalog.is_empty()


func has_archetype(alias: String) -> bool:
	return runtime_catalog.get("archetypes", {}).has(alias)


func archetype_aliases(category_filter: String = "") -> Array[String]:
	var result: Array[String] = []
	for alias_value in runtime_catalog.get("archetypes", {}).keys():
		var alias := String(alias_value)
		if not category_filter.is_empty() and category(alias) != category_filter:
			continue
		result.append(alias)
	result.sort()
	return result


func archetype(alias: String) -> Dictionary:
	return runtime_catalog.get("archetypes", {}).get(alias, {})


func identifiers(alias: String) -> Dictionary:
	return archetype(alias).get("identifiers", {}).duplicate(true)


func behavior_tags(alias: String) -> Array:
	return archetype(alias).get("behavior_tags", []).duplicate()


func runtime_metadata(alias: String) -> Dictionary:
	return archetype(alias).get("runtime", {}).duplicate(true)


func train_location_unit_id(alias: String, civilization_id: int = -1) -> int:
	var runtime := runtime_metadata(alias)
	if runtime.has("train_location_unit_id"):
		return int(runtime["train_location_unit_id"])
	return int(normalized_record(alias, civilization_id).get("relationships", {}).get("train_location_unit_id", -1))


func completion_technology_id(alias: String, civilization_id: int = -1) -> int:
	return int(normalized_record(alias, civilization_id).get("relationships", {}).get("research_id", -1))


func category(alias: String) -> String:
	return String(archetype(alias).get("category", ""))


func normalized_record(alias: String, civilization_id: int = -1) -> Dictionary:
	var definition := archetype(alias)
	if definition.is_empty():
		return {}
	var records: Dictionary = definition.get("records", {})
	var resolved_civilization := civilization_id
	if String(definition.get("civilization_scope", "team")) == "gaia":
		resolved_civilization = 0
	elif resolved_civilization < 0:
		resolved_civilization = int(definition.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var direct: Dictionary = records.get(String.num_int64(resolved_civilization), {})
	if not direct.is_empty():
		return direct
	var fallback_civilization := int(definition.get("default_civilization_id", 0))
	var fallback: Dictionary = records.get(String.num_int64(fallback_civilization), {})
	if not fallback.is_empty():
		return fallback
	var keys: Array = records.keys()
	keys.sort_custom(func(left, right): return int(left) < int(right))
	return records.get(keys[0], {}) if not keys.is_empty() else {}


func simulation_stats(alias: String, civilization_id: int = -1) -> Dictionary:
	var normalized := normalized_record(alias, civilization_id)
	if not normalized.is_empty():
		var stats: Dictionary = normalized.get("simulation", {}).duplicate(true)
		var source: Dictionary = object_record(alias, civilization_id)
		stats["footprint_radius"] = source.get("geometry", {}).get("radius", [])
		stats["behavior_tags"] = behavior_tags(alias)
		stats["identifiers"] = identifiers(alias)
		stats["runtime"] = runtime_metadata(alias)
		return stats
	return compatibility_gamespec.get("units", {}).get(alias, {}).duplicate(true)


func object_record(alias: String, civilization_id: int = -1) -> Dictionary:
	var normalized := normalized_record(alias, civilization_id)
	var source_key := String(normalized.get("source_key", ""))
	if not source_key.is_empty():
		var source: Dictionary = object_catalog.get("objects", {}).get(source_key, {})
		if not source.is_empty():
			return source
	var source_unit_id := int(identifiers(alias).get("source_unit_id", -1))
	if source_unit_id < 0:
		source_unit_id = int(compatibility_gamespec.get("units", {}).get(alias, {}).get("unit_id", -1))
	if source_unit_id < 0:
		return {}
	var requested_key := "%d:%d" % [maxi(0, civilization_id), source_unit_id]
	var direct: Dictionary = object_catalog.get("objects", {}).get(requested_key, {})
	if not direct.is_empty():
		return direct
	return object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})


func presentation(alias: String, civilization_id: int = -1) -> Dictionary:
	return normalized_record(alias, civilization_id).get("presentation", {}).duplicate(true)
