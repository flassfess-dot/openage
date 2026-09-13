extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")

const MANIFEST_PATH := "res://data/parity/source_ai_workforce_executable_gate.json"
const EXPECTED_IDS := [0, 1, 2, 3, 4, 5]

var failures: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = ParityGate.load_manifest(MANIFEST_PATH)
	assert_true(not manifest.is_empty(), "workforce measurement manifest loads")
	assert_true(ParityGate.validation_issues(manifest).is_empty(), "workforce measurement contract is structurally valid")
	assert_equal(String(manifest.get("status", "")), "capture_pending", "formula gate honestly remains pending")
	assert_true(not ParityGate.can_claim_parity(manifest), "unknown source allocation formula cannot claim parity")
	var declared_ids: Array[int] = []
	for entry_value in manifest.get("strategic_numbers", []):
		declared_ids.append(int(entry_value.get("source_id", -1)))
	declared_ids.sort()
	assert_equal(declared_ids, EXPECTED_IDS, "contract covers all percentage and cap IDs")
	assert_equal(ParityGate.unresolved_requirements(manifest), [
		"original_capture:workforce_percentage_base_and_rounding",
		"original_capture:workforce_caps_after_percentages",
		"original_capture:workforce_reservation_and_rebalance",
	], "every missing executable observation remains machine-visible")

	var encountered: Dictionary = {}
	for path in [
		"res://assets/generated/matches/syracuse.json",
		"res://assets/generated/matches/mithridates.json",
	]:
		var match_definition := read_json(path)
		for player_value in match_definition.get("players", []):
			for entry_value in player_value.get("source_ai", {}).get("strategic_numbers", []):
				var source_id := int(entry_value.get("source_id", -1))
				if source_id not in EXPECTED_IDS:
					continue
				encountered[source_id] = true
				assert_equal(String(entry_value.get("runtime_semantics", "")), "pending", "workforce ID %d remains evidence-gated" % source_id)
	var encountered_ids: Array = encountered.keys()
	encountered_ids.sort()
	assert_equal(encountered_ids, EXPECTED_IDS, "campaign corpus exercises all workforce IDs")

	if failures.is_empty():
		print("I12-020L source workforce measurement gate tests passed")
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
