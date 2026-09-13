extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")

const MANIFEST_PATH := "res://data/parity/source_ai_random_executable_gate.json"
const EXPECTED_SCENES := [
	"random_rule_directive_selection",
	"random_build_list_resolution",
	"random_restart_and_replay_stability",
]

var failures: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = ParityGate.load_manifest(MANIFEST_PATH)
	assert_true(not manifest.is_empty(), "Random measurement manifest loads")
	assert_true(ParityGate.validation_issues(manifest).is_empty(), "Random measurement contract is structurally valid")
	assert_equal(String(manifest.get("status", "")), "capture_pending", "gate honestly remains pending")
	assert_true(not ParityGate.can_claim_parity(manifest), "unobserved Random behavior cannot claim parity")
	assert_true(FileAccess.file_exists(String(manifest.get("cataloged_baseline", {}).get("path", ""))), "cataloged DEFAULT.VC baseline exists")
	assert_equal(String(manifest.get("cataloged_baseline", {}).get("status", "")), "cataloged_partial_runtime", "catalog status stays distinct from measured behavior")

	var scene_ids: Array[String] = []
	for scene_value in manifest.get("scenes", []):
		scene_ids.append(String(scene_value.get("id", "")))
	assert_equal(scene_ids, EXPECTED_SCENES, "contract covers selection, build-list resolution and replay stability")
	assert_equal(ParityGate.unresolved_requirements(manifest), [
		"original_capture:random_rule_directive_selection",
		"original_capture:random_build_list_resolution",
		"original_capture:random_restart_and_replay_stability",
	], "every missing executable observation remains machine-visible")

	if failures.is_empty():
		print("I12-020L source Random measurement gate tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
