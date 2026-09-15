extends SceneTree

const MANIFEST_PATH := "res://data/campaigns/source_campaign_portfolio.json"
const MATRIX_PATH := "res://data/content_waves/source_campaign_portfolio.json"
const SOURCE_CATALOG_PATH := "res://assets/generated/scenario-catalog.json"
const RUNTIME_CATALOG_PATH := "res://assets/generated/runtime-catalog.json"

var failures: Array[String] = []


func _initialize() -> void:
	var manifest := read_json(MANIFEST_PATH)
	var matrix := read_json(MATRIX_PATH)
	var source_catalog := read_json(SOURCE_CATALOG_PATH)
	var runtime_catalog := read_json(RUNTIME_CATALOG_PATH)
	assert_equal(int(manifest.get("schema_version", 0)), 1, "portfolio manifest schema is explicit")
	assert_equal(int(matrix.get("schema_version", 0)), 1, "portfolio matrix schema is explicit")
	assert_equal(String(manifest.get("source_catalog_sha256", "")), FileAccess.get_sha256(SOURCE_CATALOG_PATH), "manifest is fresh for the validated source catalog")
	assert_equal(String(matrix.get("manifest_sha256", "")), FileAccess.get_sha256(MANIFEST_PATH), "matrix is fresh for the portfolio manifest")
	assert_equal(String(matrix.get("source_catalog_cache_key", "")), String(source_catalog.get("cache", {}).get("key", "")), "matrix preserves source catalog identity")
	assert_equal(String(matrix.get("runtime_catalog_cache_key", "")), String(runtime_catalog.get("cache", {}).get("key", "")), "matrix is fresh for the runtime catalog")
	assert_equal(int(manifest.get("summary", {}).get("campaign_count", -1)), 14, "manifest covers every installed campaign")
	assert_equal(int(manifest.get("summary", {}).get("mission_count", -1)), 95, "manifest covers every installed campaign mission")
	assert_equal(int(matrix.get("summary", {}).get("campaign_count", -1)), 14, "matrix audits every campaign")
	assert_equal(int(matrix.get("summary", {}).get("mission_count", -1)), 95, "matrix audits every campaign mission")
	assert_equal(int(matrix.get("summary", {}).get("launcher_ready_mission_count", -1)), 18, "portfolio baseline includes published verticals and the completed common roster")
	assert_equal(int(matrix.get("summary", {}).get("blocked_mission_count", -1)), 77, "portfolio baseline keeps exact blocked count")
	assert_equal(int(matrix.get("summary", {}).get("parity_ready_mission_count", -1)), 0, "portfolio does not overclaim parity")
	assert_equal(matrix.get("published_campaign_filenames", []), ["first punic war.cpx", "расцвет рима.cpx"], "published campaign manifests drive ranking exclusions")
	assert_equal(String(matrix.get("summary", {}).get("recommended_next_campaign_id", "")), "source_campaign_05", "lowest-scope unpublished campaign is selected deterministically")

	var matrix_by_id: Dictionary = {}
	for campaign_value in matrix.get("campaigns", []):
		var campaign: Dictionary = campaign_value
		matrix_by_id[String(campaign.get("portfolio_id", ""))] = campaign
	var seen_campaign_hashes: Dictionary = {}
	var seen_scenario_hashes: Dictionary = {}
	var seen_match_ids: Dictionary = {}
	var audited_missions := 0
	for declaration_value in manifest.get("campaigns", []):
		var declaration: Dictionary = declaration_value
		var portfolio_id := String(declaration.get("portfolio_id", ""))
		assert_true(matrix_by_id.has(portfolio_id), "%s exists in the generated matrix" % portfolio_id)
		var campaign_hash := String(declaration.get("sha256", ""))
		assert_true(campaign_hash.length() == 64 and not seen_campaign_hashes.has(campaign_hash), "%s owns a unique campaign hash" % portfolio_id)
		seen_campaign_hashes[campaign_hash] = true
		var mission_declarations: Array = declaration.get("missions", [])
		audited_missions += mission_declarations.size()
		if not matrix_by_id.has(portfolio_id):
			continue
		var audited: Dictionary = matrix_by_id[portfolio_id]
		assert_equal(int(audited.get("mission_count", -1)), mission_declarations.size(), "%s audits every declared mission" % portfolio_id)
		var audited_by_index: Dictionary = {}
		for mission_value in audited.get("missions", []):
			var mission: Dictionary = mission_value
			audited_by_index[int(mission.get("scenario_index", -1))] = mission
			assert_true(mission.has("launcher_ready") and mission.has("parity_ready"), "every mission has explicit launch and parity verdicts")
		for mission_declaration_value in mission_declarations:
			var mission_declaration: Dictionary = mission_declaration_value
			var scenario_index := int(mission_declaration.get("scenario_index", -1))
			var match_id := String(mission_declaration.get("audit_match_id", ""))
			var scenario_hash := String(mission_declaration.get("sha256", ""))
			assert_true(not seen_match_ids.has(match_id), "%s is globally unique" % match_id)
			assert_true(scenario_hash.length() == 64 and not seen_scenario_hashes.has(scenario_hash), "%s owns a unique scenario hash" % match_id)
			seen_match_ids[match_id] = true
			seen_scenario_hashes[scenario_hash] = true
			assert_true(audited_by_index.has(scenario_index), "%s includes mission %d" % [portfolio_id, scenario_index])
			if audited_by_index.has(scenario_index):
				assert_equal(String(audited_by_index[scenario_index].get("scenario_sha256", "")), scenario_hash, "%s preserves source scenario identity" % match_id)
	assert_equal(audited_missions, 95, "manifest traversal reaches every mission")

	var rise_of_rome: Dictionary = matrix_by_id.get("source_campaign_11", {})
	assert_equal(int(rise_of_rome.get("launcher_ready_mission_count", -1)), 6, "existing Rise of Rome vertical remains fully launchable")
	assert_equal(int(rise_of_rome.get("blocking_gap_total", -1)), 0, "portfolio audit agrees with the dedicated Rise of Rome gate")
	assert_equal(int(rise_of_rome.get("parity_gap_total", -1)), 17, "all source AI profiles remain explicit parity gaps")

	var first_punic_war: Dictionary = matrix_by_id.get("source_campaign_04", {})
	assert_equal(int(first_punic_war.get("launcher_ready_mission_count", -1)), 3, "First Punic War vertical is fully launchable")
	assert_equal(int(first_punic_war.get("blocking_gap_total", -1)), 0, "First Punic War has no publication blockers")
	assert_true(not matrix.get("ranked_unpublished_campaign_ids", []).has("source_campaign_04"), "published First Punic War is excluded from package ranking")

	var next_campaign: Dictionary = matrix_by_id.get("source_campaign_05", {})
	assert_equal(String(next_campaign.get("name", "")), "Reign of the Hittites", "next content package keeps source identity")
	assert_equal(int(next_campaign.get("mission_count", -1)), 5, "next package is a complete five-mission campaign")
	assert_equal(next_campaign.get("selection_score", []), [3.0, 4.0, 5.0, 5.0], "campaign selection score remains evidence-driven")
	assert_equal(next_campaign.get("unsupported_condition_command_counts", {}).keys(), ["0"], "next package exposes its shared capture condition")
	assert_equal(next_campaign.get("missing_asset_names", []), ["graphic_602"], "next package exposes its only missing graphic")

	var import_failure_count := 0
	for campaign_value in matrix.get("campaigns", []):
		for mission_value in campaign_value.get("missions", []):
			var mission: Dictionary = mission_value
			if mission.has("import_failure"):
				import_failure_count += 1
				assert_equal(String(mission.get("import_failure", {}).get("stage", "")), "runtime_normalization", "source anomaly is captured at a stable pipeline stage")
				assert_true(String(mission.get("import_failure", {}).get("reason", "")).contains("at least two active players"), "source anomaly keeps an actionable stable reason")
	assert_equal(import_failure_count, 4, "portfolio baseline captures all source single-player-slot anomalies without aborting")

	finish_test()


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


func finish_test() -> void:
	if failures.is_empty():
		print("I12-020M source campaign portfolio tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
