extends SceneTree

const TEST_DIRECTORIES := [
	"tests/unit",
	"tests/integration",
	"tests/scenarios",
	"tests/golden",
]


func _initialize() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var executable := OS.get_executable_path()
	var test_scripts: Array[String] = discover_tests(project_root)
	var failed := 0
	var log_directory := project_root.path_join("qa/test-logs")
	DirAccess.make_dir_recursive_absolute(log_directory)

	if test_scripts.is_empty():
		push_error("A-006 test runner found no tests")
		quit(1)
		return

	for script in test_scripts:
		var output: Array = []
		var log_name := script.replace("/", "_").replace(".gd", ".log")
		var arguments := PackedStringArray([
			"--headless",
			"--log-file",
			log_directory.path_join(log_name),
			"--path",
			project_root,
			"--script",
			"res://%s" % script,
		])
		var exit_code := OS.execute(executable, arguments, output, true, false)
		var output_text := ""
		for line in output:
			var text := String(line).strip_edges()
			output_text += text + "\n"
			print(text)
		var has_engine_error := contains_actionable_engine_error(output_text)
		if exit_code != 0 or has_engine_error:
			failed += 1
			push_error("FAILED %s (exit code %d, engine error %s)" % [script, exit_code, has_engine_error])
		else:
			print("PASSED %s" % script)

	print("A-006 suite: %d passed, %d failed" % [test_scripts.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func contains_actionable_engine_error(output_text: String) -> bool:
	if output_text.contains("SCRIPT ERROR:"):
		return true
	for line_value in output_text.split("\n"):
		var line := String(line_value).strip_edges()
		if line.begins_with("ERROR:") and not line.contains("Failed to read the root certificate store"):
			return true
	return false


func discover_tests(project_root: String) -> Array[String]:
	var result: Array[String] = []
	for relative_directory in TEST_DIRECTORIES:
		var absolute_directory := project_root.path_join(relative_directory)
		if not DirAccess.dir_exists_absolute(absolute_directory):
			continue
		for filename in DirAccess.get_files_at(absolute_directory):
			if filename.begins_with("test_") and filename.ends_with(".gd"):
				result.append(relative_directory.path_join(filename).replace("\\", "/"))
	result.sort()
	return result
