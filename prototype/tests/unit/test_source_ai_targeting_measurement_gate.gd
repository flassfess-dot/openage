extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")

const MANIFEST_PATH := "res://data/parity/source_ai_targeting_executable_gate.json"
const MATCH_PATH := "res://assets/generated/matches/mithridates.json"
const EXPECTED_IDS := [34, 77, 78, 79, 80, 81, 82, 83, 89, 90]

var failures: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = ParityGate.load_manifest(MANIFEST_PATH)
	assert_true(not manifest.is_empty(), "targeting measurement manifest loads")
	assert_true(ParityGate.validation_issues(manifest).is_empty(), "targeting measurement contract is structurally valid")
	assert_equal(String(manifest.get("status", "")), "capture_pending", "gate honestly remains pending")
	assert_true(not ParityGate.can_claim_parity(manifest), "unknown original rating formula cannot claim parity")
	var unresolved: Array[String] = ParityGate.unresolved_requirements(manifest)
	assert_equal(unresolved, [
		"original_capture:target_distance_hp_damage_sweep",
		"original_capture:target_zero_weight_controls",
		"original_capture:zero_priority_distance_order_scope",
	], "every missing executable observation remains machine-visible")

	var declared_ids: Array[int] = []
	for entry_value in manifest.get("strategic_numbers", []):
		declared_ids.append(int(entry_value.get("source_id", -1)))
	declared_ids.sort()
	assert_equal(declared_ids, EXPECTED_IDS, "contract covers every targeting strategic number in the campaign corpus")

	var match_definition := read_json(MATCH_PATH)
	var tactical_ai: Dictionary = match_definition.get("players", [])[4].get("source_ai", {})
	for source_id in EXPECTED_IDS:
		var source_entries: Array = tactical_ai.get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == source_id)
		assert_equal(source_entries.size(), 1, "Mithridates preserves targeting source ID %d exactly once" % source_id)
		assert_true(source_entries.size() == 1 and String(source_entries[0].get("runtime_semantics", "")) == "pending", "targeting source ID %d cannot execute before measurement" % source_id)

	if failures.is_empty():
		print("I12-020L source AI targeting measurement gate tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("missing JSON: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		failures.append("invalid JSON: %s" % path)
		return {}
	return parsed


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
