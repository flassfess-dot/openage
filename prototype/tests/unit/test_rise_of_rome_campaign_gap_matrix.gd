extends SceneTree

const MANIFEST_PATH := "res://data/campaigns/rise_of_rome.json"
const MATRIX_PATH := "res://data/content_waves/rise_of_rome_campaign.json"
const RUNTIME_CATALOG_PATH := "res://assets/generated/runtime-catalog.json"

var failures: Array[String] = []


func _initialize() -> void:
	var manifest := read_json(MANIFEST_PATH)
	var matrix := read_json(MATRIX_PATH)
	var runtime_catalog := read_json(RUNTIME_CATALOG_PATH)
	assert_equal(int(manifest.get("schema_version", 0)), 1, "campaign manifest schema is explicit")
	assert_equal(int(matrix.get("schema_version", 0)), 1, "campaign gap matrix schema is explicit")
	assert_equal(String(matrix.get("campaign_id", "")), "rise_of_rome", "matrix identifies the source campaign")
	assert_equal(String(matrix.get("manifest_sha256", "")), FileAccess.get_sha256(MANIFEST_PATH), "matrix is fresh for the declarative mission manifest")
	assert_equal(String(matrix.get("runtime_catalog_cache_key", "")), String(runtime_catalog.get("cache", {}).get("key", "")), "matrix is fresh for the runtime catalog")

	var declarations: Array = manifest.get("missions", [])
	var missions: Array = matrix.get("missions", [])
	assert_equal(declarations.size(), 6, "manifest owns all six Rise of Rome missions")
	assert_equal(missions.size(), declarations.size(), "matrix audits every declared mission")
	assert_equal(int(matrix.get("summary", {}).get("published_count", -1)), 6, "all six proven campaign verticals are published")
	assert_equal(int(matrix.get("summary", {}).get("launcher_ready_count", -1)), 6, "every Rise of Rome campaign mission clears the import launch gate")
	assert_equal(int(matrix.get("summary", {}).get("blocked_count", -1)), 0, "no mission remains blocked from the launcher")
	assert_equal(int(matrix.get("summary", {}).get("parity_ready_count", -1)), 0, "source-AI parity gaps remain explicit")
	assert_equal(int(matrix.get("summary", {}).get("source_ai_profile_count", -1)), 17, "matrix counts every source AI profile")
	assert_equal(int(matrix.get("summary", {}).get("source_ai_gap_profile_count", -1)), 17, "matrix keeps a parity verdict for every incomplete source AI profile")
	assert_equal(int(matrix.get("summary", {}).get("unclassified_strategic_number_count", -1)), 0, "no strategic number remains without a capability owner")
	assert_true(not matrix.get("summary", {}).get("ai_capability_gap_profile_counts", {}).is_empty(), "summary exposes prioritized capability gap counts")
	assert_true(not matrix.get("summary", {}).get("ai_capability_gap_profile_counts", {}).has("exploration"), "confirmed exploration parameters leave the campaign capability ledger")
	assert_equal(int(matrix.get("summary", {}).get("ai_capability_gap_profile_counts", {}).get("defence", -1)), 11, "only profiles with the ambiguous defence-variation parameter retain a defence gap")
	assert_true(not matrix.get("summary", {}).get("ai_capability_gap_profile_counts", {}).has("naval_transport"), "implemented naval groups and escort lifecycle leave no naval/transport capability gap")
	var ai_gap_count := 0
	for mission_value in missions:
		var mission: Dictionary = mission_value
		ai_gap_count += mission.get("ai_gaps", []).size()
		for gap_value in mission.get("ai_gaps", []):
			var gap: Dictionary = gap_value
			assert_true(gap.has("pending_rule_directives") and gap.has("strategic_capabilities"), "AI parity gap exposes directives and capability coverage")
			assert_true(gap.get("unclassified_strategic_number_ids", []).is_empty(), "every encountered strategic number has a machine capability")
	assert_equal(ai_gap_count, 17, "all seventeen source AI profiles retain an explicit parity verdict")

	var seen_indexes: Dictionary = {}
	var seen_ids: Dictionary = {}
	for index in range(declarations.size()):
		var declaration: Dictionary = declarations[index]
		var mission: Dictionary = missions[index]
		var scenario_index := int(declaration.get("scenario_index", -1))
		var match_id := String(declaration.get("match_id", ""))
		assert_true(not seen_indexes.has(scenario_index), "scenario index is unique")
		assert_true(not seen_ids.has(match_id), "runtime match id is unique")
		seen_indexes[scenario_index] = true
		seen_ids[match_id] = true
		assert_equal(int(mission.get("scenario_index", -2)), scenario_index, "matrix preserves manifest order and source index")
		assert_equal(String(mission.get("match_id", "")), match_id, "matrix preserves stable runtime id")
		assert_true(String(mission.get("scenario_sha256", "")).length() == 64, "mission keeps immutable source identity")
		assert_true(int(mission.get("source_object_count", 0)) > 0, "mission audit owns every source object")
		assert_true(mission.has("launcher_ready") and mission.has("parity_ready"), "mission reports both launch and parity gates")

	var first: Dictionary = missions[0]
	assert_true(bool(first.get("published", false)), "existing Birth of Rome vertical remains explicitly published")
	assert_true(bool(first.get("launcher_ready", false)), "first mission clears the source import launch gate")
	assert_true(not bool(first.get("parity_ready", true)), "first mission does not overclaim source-AI parity")
	assert_equal(int(first.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "first mission has no object gaps")
	assert_equal(int(first.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "first mission has no condition gaps")
	assert_equal(int(first.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "first mission has no asset gaps")
	assert_true(first.get("gap_ids", []).has("ai_semantics_gap"), "remaining source-AI semantics stay visible")

	var pyrrhus: Dictionary = missions[1]
	assert_equal(String(pyrrhus.get("title", "")), "Пирр Эпирский", "second campaign mission retains source identity")
	assert_true(bool(pyrrhus.get("published", false)), "proven Pyrrhus vertical is explicitly published")
	assert_true(bool(pyrrhus.get("launcher_ready", false)), "Pyrrhus clears the mechanical import gate")
	assert_equal(int(pyrrhus.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "Pyrrhus maps all source objects")
	assert_equal(int(pyrrhus.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "Pyrrhus implements both exact Town Center conditions")
	assert_equal(int(pyrrhus.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "Pyrrhus has every required source asset")
	assert_equal(int(pyrrhus.get("parity_gaps", {}).get("source_settings_gap_count", -1)), 0, "Pyrrhus represents Post-Iron and the disabled Wonder node")
	assert_true(not bool(pyrrhus.get("parity_ready", true)), "Pyrrhus retains explicit source-AI semantics work")

	var syracuse: Dictionary = missions[2]
	assert_equal(String(syracuse.get("title", "")), "Сиракузцы", "third campaign mission retains source identity")
	assert_true(bool(syracuse.get("published", false)), "proven Syracuse vertical is explicitly published")
	assert_true(bool(syracuse.get("launcher_ready", false)), "Syracuse clears the mechanical import gate")
	assert_equal(int(syracuse.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "Syracuse maps all source objects")
	assert_equal(int(syracuse.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "Syracuse implements Legion-area and Archimedes conditions")
	assert_equal(int(syracuse.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "Syracuse has every required source asset")
	assert_equal(int(syracuse.get("parity_gaps", {}).get("source_settings_gap_count", -1)), 0, "Syracuse represents all source scenario settings")
	assert_true(not bool(syracuse.get("parity_ready", true)), "Syracuse retains explicit source-AI semantics work")

	var metaurus: Dictionary = missions[3]
	assert_equal(String(metaurus.get("title", "")), "Метавр", "lowest-object-gap vertical is source identified")
	assert_equal(int(metaurus.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "Metaurus maps all source objects")
	assert_equal(int(metaurus.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "Metaurus has no hidden legacy condition gap")
	assert_equal(int(metaurus.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "Metaurus has every required source asset")
	assert_true(bool(metaurus.get("published", false)), "proven Metaurus vertical is explicitly published")
	assert_true(bool(metaurus.get("launcher_ready", false)), "Metaurus clears the mechanical import gate")
	assert_true(not bool(metaurus.get("parity_ready", true)), "Metaurus retains explicit source-AI parity gaps")
	assert_equal(int(metaurus.get("source_settings", {}).get("multiplayer_victory_type", -1)), 0, "Metaurus retains Standard source victory mode")

	var zama: Dictionary = missions[4]
	assert_equal(String(zama.get("title", "")), "Зама", "fifth campaign mission retains source identity")
	assert_true(bool(zama.get("published", false)), "proven Zama vertical is explicitly published")
	assert_true(bool(zama.get("launcher_ready", false)), "Zama clears the mechanical import gate")
	assert_equal(int(zama.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "Zama maps all source objects")
	assert_equal(int(zama.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "Zama has no hidden legacy condition gap")
	assert_equal(int(zama.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "Zama has both source flag palettes")
	assert_equal(int(zama.get("parity_gaps", {}).get("source_settings_gap_count", -1)), 0, "Zama represents source victory and starting-age settings")
	assert_true(not bool(zama.get("parity_ready", true)), "Zama retains explicit source-AI parity gaps")

	var mithridates: Dictionary = missions[5]
	assert_equal(String(mithridates.get("title", "")), "Митридат", "sixth campaign mission retains source identity")
	assert_true(bool(mithridates.get("published", false)), "proven Mithridates vertical is explicitly published")
	assert_true(bool(mithridates.get("launcher_ready", false)), "Mithridates clears the mechanical import gate")
	assert_equal(int(mithridates.get("blocking_gaps", {}).get("object_gap_count", -1)), 0, "Mithridates maps all source objects")
	assert_equal(int(mithridates.get("blocking_gaps", {}).get("condition_gap_count", -1)), 0, "Mithridates implements the exact enemy Wonder objective")
	assert_equal(int(mithridates.get("blocking_gaps", {}).get("ai_normalization_gap_count", -1)), 0, "all source AI profiles have an executable supported subset")
	assert_equal(int(mithridates.get("blocking_gaps", {}).get("asset_gap_count", -1)), 0, "Mithridates has every required source asset")
	assert_equal(int(mithridates.get("parity_gaps", {}).get("source_settings_gap_count", -1)), 0, "Mithridates represents source technology and starting-age settings")
	assert_true(not bool(mithridates.get("parity_ready", true)), "Mithridates retains explicit source-AI semantics work")

	if failures.is_empty():
		print("I12-020F Rise of Rome campaign gap matrix tests passed")
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
