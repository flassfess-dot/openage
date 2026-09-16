extends SceneTree

const EVIDENCE_PATH := "res://data/source_ai/aoede_build_97381_ai_evidence.json"

var failures: Array[String] = []


func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
	assert_true(parsed is Dictionary, "AoE DE evidence is valid JSON")
	if not parsed is Dictionary:
		_finish("E5-004 AoE DE AI evidence tests passed")
		return
	var evidence: Dictionary = parsed
	assert_equal(int(evidence.get("schema_version", 0)), 1, "evidence schema is explicit")
	assert_equal(String(evidence.get("build", "")), "97381", "ledger is pinned to the inspected DE build")
	assert_equal(String(evidence.get("source_role", "")), "secondary_evidence_no_runtime_authority", "DE cannot silently become runtime authority")
	assert_equal(String(evidence.get("source_files", {}).get("empires_orig", {}).get("sha256", "")), "d47c59d9ecaf5b83b467c647a69d28eced6a0dc5b2fa873e930c86136df5eb9d", "classic DAT identity is preserved")
	var summary: Dictionary = evidence.get("summary", {})
	assert_equal(int(summary.get("ai_profile_count", 0)), 146, "all DE build plans are inventoried")
	assert_equal(int(summary.get("per_profile_count", 0)), 23, "all DE personality files are inventoried")
	assert_equal(int(summary.get("ai_entry_count", 0)), 13307, "valid build-plan entries have a stable derived count")
	assert_equal(int(summary.get("per_entry_count", 0)), 2389, "strategic-number evidence has a stable derived count")
	assert_equal(int(summary.get("parse_anomaly_count", 0)), 3, "three source-owned malformed build-plan rows remain explicit")
	assert_true(int(summary.get("per_runtime_semantics_counts", {}).get("implemented", 0)) > 0, "ledger maps supported parameters to existing runtime capabilities")
	assert_true(int(summary.get("per_runtime_semantics_counts", {}).get("pending", 0)) > 0, "unsupported DE parameters remain explicit pending evidence")

	for collection in ["ai_profiles", "per_profiles"]:
		for profile_value in evidence.get(collection, []):
			var relative_path := String(profile_value.get("relative_path", ""))
			assert_true(not relative_path.is_empty() and not relative_path.contains(":") and not relative_path.begins_with("/"), "ledger stores only portable paths: %s" % relative_path)
			assert_equal(String(profile_value.get("sha256", "")).length(), 64, "profile source hash is complete")

	var default_profile: Dictionary = {}
	for profile_value in evidence.get("per_profiles", []):
		if String(profile_value.get("relative_path", "")) == "CP_AI/PER/DEFAULT.PER":
			default_profile = profile_value
			break
	assert_true(not default_profile.is_empty(), "DEFAULT personality is individually traceable")
	assert_equal(_strategic_value(default_profile, 104), 120, "DE initial attack delay is preserved as evidence")
	assert_equal(_strategic_value(default_profile, 36), 3, "DE attack group count is preserved as evidence")
	assert_equal(_strategic_value(default_profile, 58), 5, "DE naval attack group count is preserved as evidence")
	assert_equal(evidence.get("parse_anomalies", []).size(), 3, "source anomalies include hashes without copying malformed rows")
	_finish("E5-004 AoE DE AI evidence tests passed")


func _strategic_value(profile: Dictionary, source_id: int) -> int:
	for entry_value in profile.get("entries", []):
		if int(entry_value.get("source_id", -1)) == source_id:
			return int(entry_value.get("value", -999999))
	return -999999


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
