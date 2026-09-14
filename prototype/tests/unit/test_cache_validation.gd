extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	test_validation_report_contract()

	if failures.is_empty():
		print("D-004 cache validation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_validation_report_contract() -> void:
	var report_path := "res://assets/generated/validation-report.json"
	assert_true(FileAccess.file_exists(report_path), "JSON report exists")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	assert_true(parsed is Dictionary, "JSON report parses")
	if not parsed is Dictionary:
		return
	var report: Dictionary = parsed
	assert_equal(report.get("format_version"), 3, "validation report schema")
	assert_equal(String(report.get("cache", {}).get("key", "")).length(), 64, "validation cache key")
	assert_equal(report.get("inputs", {}).get("graphics"), 941, "all graphics validated")
	assert_equal(report.get("inputs", {}).get("sounds"), 234, "all logical sounds validated")
	assert_equal(report.get("inputs", {}).get("languages"), 10, "all languages included")
	assert_equal(report.get("inputs", {}).get("runtime_archetypes"), 66, "all runtime archetypes, including the published campaign roster, are validated")
	var required_categories := [
		"missing_slp",
		"missing_audio",
		"unknown_ids",
		"broken_deltas",
		"dependency_cycles",
		"missing_name_or_icon",
		"suspicious_values",
		"runtime_catalog",
	]
	for category in required_categories:
		assert_true(report.get("issues", {}).has(category), "%s category exists" % category)
		var section: Dictionary = report.get("issues", {}).get(category, {})
		assert_equal(section.get("count"), section.get("items", []).size(), "%s count matches items" % category)
	assert_equal(report.get("issues", {}).get("broken_deltas", {}).get("count"), 0, "no broken graphic deltas")
	assert_equal(report.get("summary", {}).get("errors"), 0, "no malformed cache references or dependency cycles")
	var coverage: Dictionary = report.get("coverage", {})
	assert_equal(coverage.get("runtime_candidate_unit_ids"), 322, "technology and lifecycle reachable object IDs are measured")
	assert_equal(int(coverage.get("player_facing_objects", 0)) - int(coverage.get("player_facing_objects_with_name", 0)), 68, "player-facing localization source gaps are explicit")
	assert_equal(int(coverage.get("objects_requiring_icon", 0)) - int(coverage.get("objects_with_required_icon", 0)), 17, "required icon source gaps are explicit")
	assert_equal(coverage.get("reachable_resource_graphics"), 647, "resource-backed graphics are measured")
	assert_equal(coverage.get("reachable_resource_graphics_with_slp"), 610, "owned source graphic coverage")
	assert_equal(coverage.get("active_resource_sounds"), 90, "active resource-backed sounds are measured")
	assert_equal(coverage.get("active_resource_sounds_with_audio"), 86, "owned source audio coverage")
	var reachable_missing_slp := 0
	for missing in report.get("issues", {}).get("missing_slp", {}).get("items", []):
		assert_equal(missing.get("classification"), "owned_source_gap", "SLP issue classification")
		if bool(missing.get("reachable", false)):
			reachable_missing_slp += 1
	assert_equal(reachable_missing_slp, 37, "runtime-candidate SLP source gaps are explicit")
	var active_audio_gaps := 0
	var active_audio_fallbacks := 0
	for missing in report.get("issues", {}).get("missing_audio", {}).get("items", []):
		assert_true(int(missing.get("resource_id", -1)) >= 0, "audio sentinel IDs are ignored")
		assert_equal(missing.get("classification"), "owned_source_gap", "audio issue classification")
		match String(missing.get("impact", "")):
			"active_binding_without_audio":
				active_audio_gaps += 1
			"active_binding_with_fallback":
				active_audio_fallbacks += 1
	assert_equal(active_audio_gaps, 4, "active source audio gaps are explicit")
	assert_equal(active_audio_fallbacks, 2, "active sounds with a valid alternative are explicit")
	var project_root := ProjectSettings.globalize_path("res://")
	var markdown_path := project_root.path_join("../doc/ror-modern/CACHE_VALIDATION_REPORT.md").simplify_path()
	assert_true(FileAccess.file_exists(markdown_path), "Markdown report exists")
	var markdown := FileAccess.get_file_as_string(markdown_path)
	assert_true(markdown.contains("| Category | Severity | Count |"), "Markdown summary table exists")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
