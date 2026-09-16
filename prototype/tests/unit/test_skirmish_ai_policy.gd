extends SceneTree

const SkirmishAiPolicy := preload("res://scripts/skirmish_ai_policy.gd")
const EVIDENCE_PATH := "res://data/source_ai/aoede_build_97381_ai_evidence.json"

var failures: Array[String] = []


func _initialize() -> void:
	var source_catalog := SkirmishAiPolicy.catalog()
	assert_true(bool(source_catalog.get("valid", false)), "the versioned skirmish AI policy catalog loads")
	assert_equal(String(source_catalog.get("status", "")), "engine_owned_policy_with_secondary_evidence", "the catalog declares engine ownership")
	assert_equal(SkirmishAiPolicy.difficulty_entries().size(), 3, "all public difficulty levels are data-driven")

	var standard := SkirmishAiPolicy.resolve()
	assert_true(bool(standard.get("valid", false)), "the standard policy resolves")
	assert_equal(String(standard.get("profile", "")), "skirmish_policy_v1", "runtime uses an explicit policy profile")
	assert_equal(String(standard.get("difficulty_id", "")), "standard", "standard difficulty remains explicit")
	assert_equal(int(standard.get("economic_interval_ticks", 0)), 20, "standard economic cadence is stable")
	assert_equal(int(standard.get("military_interval_ticks", 0)), 20, "source-backed tactical cadence is converted to ticks")
	assert_equal(int(standard.get("initial_attack_delay_ticks", 0)), 40, "source-backed initial delay is converted to ticks")
	assert_equal(int(standard.get("attack_separation_ticks", 0)), 160, "source-backed attack separation is converted to ticks")
	assert_equal(int(standard.get("minimum_attack_group_size", 0)), 3, "source-backed minimum attack group reaches runtime")
	assert_equal(int(standard.get("maximum_attack_group_size", 0)), 20, "source-backed maximum attack group reaches runtime")
	assert_equal(float(standard.get("enemy_response_distance", 0.0)), 22.0, "source-backed defensive response distance reaches runtime")
	assert_equal(standard.get("construction_priorities", [])[0], "house", "engine-owned economy protects population capacity first")
	assert_equal(int(standard.get("building_limits", {}).get("house", 0)), 4, "engine-owned economy can add multiple houses")
	assert_equal(int(standard.get("land_worker_target", 0)), 8, "engine-owned economy has an explicit land workforce target")
	assert_equal(int(standard.get("water_worker_target", 0)), 2, "engine-owned economy has a separate Fishing Boat target")
	assert_equal(standard.get("age_advance_technology_ids", []).map(func(value): return int(value)), [101, 102, 103], "engine-owned economy names the authoritative age technologies")
	assert_true("dock" in standard.get("age_saving_construction_exceptions", []), "engine-owned economy may add naval food infrastructure while preserving age resources")
	assert_equal(standard.get("age_saving_production_exceptions", []), ["fishing_boat", "scout_ship"], "engine-owned economy can bootstrap naval scouting without spending reserved age resources")
	assert_equal(standard.get("structure_gap_fallback_kinds", []), ["house"], "critical housing can use a legal compact fallback when an island has no spacious site")
	assert_equal(float(standard.get("minimum_structure_gap", -1.0)), 1.0, "engine-owned placement preserves a navigation lane between structures")
	assert_true(not bool(standard.get("use_workers_in_attack_groups", true)), "engine-owned economy keeps workers out of ordinary attack groups")

	var easy := SkirmishAiPolicy.resolve("random_map_balanced", "easy")
	var hard := SkirmishAiPolicy.resolve("random_map_balanced", "hard")
	assert_equal(int(easy.get("military_interval_ticks", 0)), 40, "easy AI thinks less frequently")
	assert_equal(int(easy.get("initial_attack_delay_ticks", 0)), 120, "easy AI attacks later")
	assert_equal(int(hard.get("military_interval_ticks", 0)), 10, "hard AI thinks more frequently")
	assert_equal(int(hard.get("attack_separation_ticks", 0)), 80, "hard AI regroups faster")
	assert_equal(String(hard.get("source_evidence", {}).get("source_role", "")), "secondary_evidence_no_runtime_authority", "difficulty overrides cannot promote DE to runtime authority")

	assert_true(not bool(SkirmishAiPolicy.resolve("missing", "standard").get("valid", true)), "unknown policy IDs are rejected")
	assert_true(not bool(SkirmishAiPolicy.resolve("random_map_balanced", "missing").get("valid", true)), "unknown difficulty IDs are rejected")
	verify_selected_source_evidence(standard)
	_finish("E5-005 skirmish AI policy tests passed")


func verify_selected_source_evidence(policy: Dictionary) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
	assert_true(parsed is Dictionary, "the pinned AoE DE evidence ledger loads")
	if not parsed is Dictionary:
		return
	var evidence: Dictionary = parsed
	var selected: Dictionary = policy.get("source_evidence", {})
	var relative_path := String(selected.get("relative_path", ""))
	var profile: Dictionary = {}
	for profile_value in evidence.get("per_profiles", []):
		if String(profile_value.get("relative_path", "")) == relative_path:
			profile = profile_value
			break
	assert_true(not profile.is_empty(), "selected personality exists in the pinned evidence ledger")
	assert_equal(String(profile.get("sha256", "")), String(selected.get("sha256", "")), "selected personality hash is pinned")
	var evidence_values: Dictionary = {}
	for entry_value in profile.get("entries", []):
		evidence_values[int(entry_value.get("source_id", -1))] = int(entry_value.get("value", -999999))
	for parameter_value in selected.get("selected_parameters", []):
		var parameter: Dictionary = parameter_value
		var source_id := int(parameter.get("source_id", -1))
		assert_equal(int(parameter.get("source_value", -999999)), int(evidence_values.get(source_id, -999998)), "selected source parameter %d matches the evidence ledger" % source_id)


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
