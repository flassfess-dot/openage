class_name RoRSkirmishAiPolicy
extends RefCounted

const CATALOG_PATH := "res://data/ai/skirmish_policies.json"


static func catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"valid": false, "errors": ["skirmish_ai_policy_catalog_missing"]}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		return {"valid": false, "errors": ["skirmish_ai_policy_catalog_invalid"]}
	var result: Dictionary = parsed
	var errors: Array[String] = []
	if int(result.get("schema_version", 0)) != 1:
		errors.append("skirmish_ai_policy_schema_unsupported")
	if result.get("profiles", []).is_empty():
		errors.append("skirmish_ai_policy_profiles_missing")
	if result.get("difficulties", []).is_empty():
		errors.append("skirmish_ai_policy_difficulties_missing")
	result["valid"] = errors.is_empty()
	result["errors"] = errors
	return result


static func resolve(policy_id: String = "random_map_balanced", difficulty_id: String = "standard") -> Dictionary:
	var source := catalog()
	if not bool(source.get("valid", false)):
		return {"valid": false, "errors": source.get("errors", [])}
	var profile := _entry(source.get("profiles", []), policy_id)
	var difficulty := _entry(source.get("difficulties", []), difficulty_id)
	var errors: Array[String] = []
	if profile.is_empty():
		errors.append("skirmish_ai_policy_unknown:%s" % policy_id)
	if difficulty.is_empty():
		errors.append("skirmish_ai_difficulty_unknown:%s" % difficulty_id)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	var runtime: Dictionary = profile.get("runtime", {}).duplicate(true)
	for key in difficulty.get("overrides", {}):
		runtime[key] = difficulty["overrides"][key]
	runtime.merge({
		"enabled": true,
		"profile": "skirmish_policy_v1",
		"policy_id": policy_id,
		"difficulty_id": difficulty_id,
		"source_evidence": profile.get("source_evidence", {}).duplicate(true),
	}, true)
	_validate_runtime(runtime, errors)
	runtime["valid"] = errors.is_empty()
	runtime["errors"] = errors
	return runtime


static func difficulty_entries() -> Array:
	return catalog().get("difficulties", []).duplicate(true)


static func _entry(entries: Array, identifier: String) -> Dictionary:
	for value in entries:
		if value is Dictionary and String(value.get("id", "")) == identifier:
			return value
	return {}


static func _validate_runtime(runtime: Dictionary, errors: Array[String]) -> void:
	for key in ["economic_interval_ticks", "military_interval_ticks", "initial_attack_delay_ticks", "attack_separation_ticks", "minimum_attack_group_size", "maximum_attack_group_size"]:
		if int(runtime.get(key, 0)) <= 0:
			errors.append("skirmish_ai_policy_field_invalid:%s" % key)
	if int(runtime.get("minimum_attack_group_size", 0)) > int(runtime.get("maximum_attack_group_size", 0)):
		errors.append("skirmish_ai_policy_group_range_invalid")
	if float(runtime.get("enemy_response_distance", 0.0)) <= 0.0:
		errors.append("skirmish_ai_policy_field_invalid:enemy_response_distance")
