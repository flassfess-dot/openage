extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")
const TradeProfitPolicy := preload("res://scripts/trade_profit_policy.gd")

const MANIFEST_PATH := "res://data/parity/naval_executable_gate.json"
const EXPECTED_SHIPS := [13, 14, 15, 16, 17, 18, 19, 20, 21, 250, 277]
const EXPECTED_COMBAT_SHIPS := [19, 20, 21, 250, 277]
const MODERN_GOLDEN_FILE_SHA256 := "e99b47a29954b21600951b0e56acf7dd073d38a84c8681367b402665af1694d3"

var failures: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = ParityGate.load_manifest(MANIFEST_PATH)
	assert_true(not manifest.is_empty(), "measurement manifest loads")
	assert_true(ParityGate.validation_issues(manifest).is_empty(), "pending measurement contract is structurally valid")
	assert_equal(String(manifest.get("status", "")), "capture_pending", "gate honestly remains pending")
	assert_true(not ParityGate.can_claim_parity(manifest), "pending executable observations cannot claim parity")
	var unresolved: Array[String] = ParityGate.unresolved_requirements(manifest)
	assert_true(unresolved.has("original_capture:naval_direction_composite_palette"), "original visual capture is explicit")
	assert_true(unresolved.has("original_capture:naval_attack_release_audio"), "original attack/audio capture is explicit")
	assert_true(unresolved.has("original_capture:naval_damage_death_impact"), "original damage/effect capture is explicit")
	assert_true(unresolved.has("trade_profit_measurement"), "trade calibration remains explicit")

	var covered_ships: Array[int] = []
	var attack_ships: Array[int] = []
	for scene_value in manifest.get("scenes", []):
		var scene: Dictionary = scene_value
		for source_value in scene.get("source_unit_ids", []):
			var source_id := int(source_value)
			if source_id not in covered_ships:
				covered_ships.append(source_id)
		if String(scene.get("id", "")) == "naval_attack_release_audio":
			for source_value in scene.get("source_unit_ids", []):
				attack_ships.append(int(source_value))
	covered_ships.sort()
	attack_ships.sort()
	assert_equal(covered_ships, EXPECTED_SHIPS, "all Roman naval source variants are measured")
	assert_equal(attack_ships, EXPECTED_COMBAT_SHIPS, "every combat ship has attack timing evidence")

	var trade: Dictionary = manifest.get("trade_profit", {})
	assert_equal(String(trade.get("policy_id", "")), String(TradeProfitPolicy.metadata().get("id", "")), "measurement targets the active isolated policy")
	assert_true(int(trade.get("required_map_count", 0)) >= 3, "trade protocol covers map-size dependence")
	assert_true(trade.get("distance_samples", []).size() >= 4, "trade protocol samples the distance curve")
	assert_equal(file_sha256("res://qa/golden/naval-presentations.png"), MODERN_GOLDEN_FILE_SHA256, "modern comparison artifact is immutable")

	if failures.is_empty():
		print("I12-019G naval executable measurement gate tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
