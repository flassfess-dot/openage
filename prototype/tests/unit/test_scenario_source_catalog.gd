extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const EXPECTED_STANDALONE_SCENARIOS := 26
const EXPECTED_CAMPAIGNS := 14
const EXPECTED_SOURCE_FILES := 40

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	var scenarios: Dictionary = catalog.scenario_catalog_data
	assert_true(not scenarios.is_empty(), "scenario catalog loads without the original install at runtime")
	assert_equal(int(scenarios.get("format_version", 0)), 1, "scenario catalog schema is explicit")
	assert_equal(String(scenarios.get("validation", {}).get("status", "")), "valid", "source catalog validation passed")
	assert_true(scenarios.get("validation", {}).get("errors", []).is_empty(), "source catalog has no hidden parse errors")

	var summary: Dictionary = scenarios.get("summary", {})
	assert_equal(int(summary.get("standalone_scenario_count", -1)), EXPECTED_STANDALONE_SCENARIOS, "all installed standalone scenarios are inventoried")
	assert_equal(int(summary.get("campaign_count", -1)), EXPECTED_CAMPAIGNS, "all installed campaigns are inventoried")
	assert_equal(int(summary.get("source_file_count", -1)), EXPECTED_SOURCE_FILES, "source file coverage is complete")
	assert_true(int(summary.get("campaign_scenario_count", 0)) > EXPECTED_CAMPAIGNS, "campaign entries are decoded instead of treating archives as opaque files")

	var seen_paths: Dictionary = {}
	for record_value in scenarios.get("standalone_scenarios", []):
		validate_source_record(record_value, seen_paths, true)
	for campaign_value in scenarios.get("campaigns", []):
		var campaign: Dictionary = campaign_value
		validate_source_record(campaign, seen_paths, false)
		assert_equal(campaign.get("scenarios", []).size(), int(campaign.get("scenario_count", -1)), "campaign entry count matches decoded header")
		for entry_value in campaign.get("scenarios", []):
			var entry: Dictionary = entry_value
			assert_sha256(String(entry.get("sha256", "")), "embedded scenario has immutable source identity")
			validate_header(entry.get("header", {}), "embedded scenario header")

	assert_equal(seen_paths.size(), EXPECTED_SOURCE_FILES, "catalog paths are unique")
	assert_true(scenarios.get("campaigns", []).any(func(item): return String(item.get("name", "")).contains("Рим")), "owned Roman campaign content is discoverable by decoded metadata")
	var cache_sources: Dictionary = scenarios.get("cache", {}).get("components", {}).get("source_sha256", {})
	assert_equal(cache_sources.size(), EXPECTED_SOURCE_FILES, "cache key owns every scenario and campaign source hash")

	if failures.is_empty():
		print("I12-020A scenario/campaign source catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func validate_source_record(record_value: Variant, seen_paths: Dictionary, has_header: bool) -> void:
	var record: Dictionary = record_value
	var source_path := String(record.get("source_path", ""))
	assert_true(not source_path.is_empty(), "source record has a portable relative path")
	assert_true(not source_path.contains(":") and not source_path.begins_with("/") and not source_path.contains("\\"), "source path never stores a machine-specific absolute path")
	assert_true(not seen_paths.has(source_path), "source path is unique: %s" % source_path)
	seen_paths[source_path] = true
	assert_true(int(record.get("size", 0)) > 0, "source record has a measured byte size")
	assert_sha256(String(record.get("sha256", "")), "source record has immutable identity")
	if has_header:
		validate_header(record.get("header", {}), "standalone scenario header")


func validate_header(header_value: Variant, context: String) -> void:
	var header: Dictionary = header_value
	assert_true(String(header.get("format_version", "")).begins_with("1."), "%s identifies a classic AoE/RoR format" % context)
	assert_true(int(header.get("header_size", 0)) > 0, "%s has a bounded header" % context)
	var player_count := int(header.get("active_player_count", -1))
	assert_true(player_count >= 0 and player_count <= 16, "%s has a valid player count" % context)


func assert_sha256(value: String, context: String) -> void:
	assert_true(value.length() == 64 and value.is_valid_hex_number(false), context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
