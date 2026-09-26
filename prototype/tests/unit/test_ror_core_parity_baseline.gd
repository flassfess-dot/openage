extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")

const MATRIX_PATH := "res://data/parity/ror_core_parity_gap_matrix.json"
const BASELINE_PATH := "res://data/parity/ror_core_baseline.json"
const MEASUREMENT_PATH := "res://data/parity/ror_core_executable_gate.json"
const ALLOWED_STATUSES := ["OPEN", "IN_PROGRESS", "INTEGRATED", "PARITY", "HARDENED"]

var failures: Array[String] = []


func _initialize() -> void:
	var matrix := read_json(MATRIX_PATH)
	var baseline := read_json(BASELINE_PATH)
	var measurement := read_json(MEASUREMENT_PATH)
	verify_gap_matrix(matrix)
	verify_baseline(baseline)
	verify_measurement_gate(matrix, measurement)
	var expected_p00_status := "INTEGRATED" if String(baseline.get("status", "")) == "captured" else "IN_PROGRESS"
	var matrix_items: Array = matrix.get("items", [])
	if not matrix_items.is_empty():
		assert_equal(String(matrix_items[0].get("status", "")), expected_p00_status, "P00 status follows the recorded baseline gate")

	if failures.is_empty():
		print("P00 RoR core parity baseline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_gap_matrix(matrix: Dictionary) -> void:
	assert_equal(int(matrix.get("schema_version", 0)), 1, "gap matrix schema is explicit")
	assert_equal(String(matrix.get("matrix_id", "")), "aoe1_ror_core_parity", "gap matrix identity")
	assert_equal(matrix.get("status_vocabulary", []), ALLOWED_STATUSES, "gap matrix owns the plan status vocabulary")
	var items: Array = matrix.get("items", [])
	var expected_ids: Array[String] = []
	for package_index in range(13):
		expected_ids.append("P%02d" % package_index)
	expected_ids.append("P14")
	assert_equal(items.size(), expected_ids.size(), "gap matrix covers active packages and excludes P13")
	var known_ids: Dictionary = {}
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var expected_id: String = expected_ids[index] if index < expected_ids.size() else ""
		var item_id := String(item.get("id", ""))
		assert_equal(item_id, expected_id, "gap matrix preserves package order")
		assert_true(not known_ids.has(item_id), "package ID is unique: %s" % item_id)
		known_ids[item_id] = true

	for item_value in items:
		var item: Dictionary = item_value
		var item_id := String(item.get("id", ""))
		assert_true(String(item.get("owner", "")).length() > 0, "%s has an owner" % item_id)
		assert_true(ALLOWED_STATUSES.has(String(item.get("status", ""))), "%s has an allowed status" % item_id)
		assert_true(not item.get("test_levels", []).is_empty(), "%s has test levels" % item_id)
		assert_true(not item.get("requirements", []).is_empty(), "%s has explicit requirements" % item_id)
		assert_true(item.has("depends_on"), "%s has an explicit dependency list" % item_id)
		for dependency_value in item.get("depends_on", []):
			var dependency := String(dependency_value)
			assert_true(known_ids.has(dependency), "%s dependency exists: %s" % [item_id, dependency])
	assert_true(String(items[0].get("status", "")) in ["IN_PROGRESS", "INTEGRATED"], "P00 status is bounded by its baseline gate")


func verify_baseline(baseline: Dictionary) -> void:
	assert_equal(int(baseline.get("schema_version", 0)), 1, "baseline schema is explicit")
	assert_equal(String(baseline.get("baseline_id", "")), "aoe1_ror_core_p00", "baseline identity")
	assert_equal(String(baseline.get("plan_id", "")), "P00", "baseline names its plan package")
	assert_true(String(baseline.get("simulation_source_commit", "")).length() == 40, "baseline pins the simulation source commit")
	assert_true(String(baseline.get("status", "")) in ["pending_user_run", "captured"], "baseline status is explicit")
	var matches: Array = baseline.get("canonical_matches", [])
	assert_equal(matches.size(), 3, "baseline declares three canonical controls")
	var seen_ids: Dictionary = {}
	for match_value in matches:
		var control: Dictionary = match_value
		var control_id := String(control.get("id", ""))
		assert_true(not control_id.is_empty() and not seen_ids.has(control_id), "canonical control has a unique ID")
		seen_ids[control_id] = true
		assert_true(FileAccess.file_exists(String(control.get("script", ""))), "%s script exists" % control_id)
		var status := String(control.get("status", ""))
		assert_true(status in ["pending", "passed"], "%s status is explicit" % control_id)
		if status == "passed":
			assert_true(String(control.get("canonical_sha256", "")).length() == 64, "%s captured hash is SHA-256 sized" % control_id)
	var performance: Dictionary = baseline.get("performance_smoke", {})
	assert_true(String(performance.get("status", "")) in ["pending", "passed"], "performance baseline status is explicit")
	assert_true(not performance.get("required_cases", {}).is_empty(), "performance baseline declares required cases")
	assert_true(String(performance.get("runner", "")).ends_with("ror-performance-smoke.ps1"), "performance baseline names the standard runner")
	if String(baseline.get("status", "")) == "captured":
		assert_true(matches.all(func(control): return String(control.get("status", "")) == "passed"), "captured baseline has all three canonical controls")
		assert_equal(String(performance.get("status", "")), "passed", "captured baseline includes a passed performance smoke")
		assert_true(not String(performance.get("local_report", "")).is_empty(), "captured performance smoke retains its report path")
		for case_id in ["movement", "mixed", "visible"]:
			var recorded_case: Dictionary = performance.get("cases", {}).get(case_id, {})
			for metric_name in performance.get("required_cases", {}).get(case_id, []):
				assert_true(float(recorded_case.get(metric_name, 0.0)) > 0.0, "%s.%s has a positive captured metric" % [case_id, metric_name])


func verify_measurement_gate(matrix: Dictionary, measurement: Dictionary) -> void:
	assert_equal(int(measurement.get("schema_version", 0)), 1, "measurement schema is explicit")
	assert_true(ParityGate.validation_issues(measurement).is_empty(), "core measurement manifest is structurally valid")
	assert_true(not ParityGate.can_claim_parity(measurement), "pending measurements cannot claim parity")
	var scenes: Array = measurement.get("scenes", [])
	assert_true(not scenes.is_empty(), "core measurement manifest has source scenes")
	assert_equal(ParityGate.unresolved_requirements(measurement).size(), scenes.size(), "every pending scene remains visible")
	var package_ids: Dictionary = {}
	for item_value in matrix.get("items", []):
		package_ids[String(item_value.get("id", ""))] = true
	for scene_value in scenes:
		var scene: Dictionary = scene_value
		assert_true(not scene.get("blocking_packages", []).is_empty(), "%s names blocking packages" % String(scene.get("id", "")))
		for package_value in scene.get("blocking_packages", []):
			assert_true(package_ids.has(String(package_value)), "%s references a matrix package" % String(scene.get("id", "")))


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
