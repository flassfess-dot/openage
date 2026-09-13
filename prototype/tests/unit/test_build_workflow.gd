extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	test_workflow_is_separated()

	if failures.is_empty():
		print("D-007 build workflow tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_workflow_is_separated() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var tools_root := project_root.path_join("../tools").simplify_path()
	var import_script := read_required(tools_root.path_join("import-assets.ps1"))
	var validation_script := read_required(tools_root.path_join("validate-cache.ps1"))
	var build_script := read_required(tools_root.path_join("build-game.ps1"))
	var run_script := read_required(tools_root.path_join("run-game.ps1"))

	assert_true(import_script.contains("import_assets.js"), "asset import owns SLP conversion")
	assert_true(import_script.contains("extract_graphics_catalog.py"), "asset import owns catalog extraction")
	assert_true(import_script.contains("extract_terrain_catalog.py"), "asset import owns terrain extraction")
	assert_true(validation_script.contains("validate_cache.py"), "validation owns report generation")
	assert_true(build_script.contains("--export-pack"), "build owns package export")
	assert_true(not build_script.contains("import_assets.js"), "build does not convert original assets")
	assert_true(run_script.contains("Start-Process"), "run launches packaged application")
	for forbidden in ["import_assets.js", "extract_", "validate_cache.py", "node ", "py -3", "--import", "--export"]:
		assert_true(not run_script.to_lower().contains(forbidden.to_lower()), "run excludes %s" % forbidden)


func read_required(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "%s exists" % path.get_file())
	return FileAccess.get_file_as_string(path)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
