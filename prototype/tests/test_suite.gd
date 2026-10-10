extends SceneTree

const TEST_TIMEOUT_MSEC := 300_000

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
	var start_at := ""
	var name_filter := ""
	for argument_value in OS.get_cmdline_user_args():
		var argument := String(argument_value)
		if argument.begins_with("--filter="):
			name_filter = argument.trim_prefix("--filter=")
		if argument.begins_with("--start-at="):
			start_at = argument.trim_prefix("--start-at=").trim_prefix("res://").replace("\\", "/")
	if not name_filter.is_empty():
		var filtered: Array[String] = []
		for script in test_scripts:
			if script.get_file().begins_with(name_filter): filtered.append(script)
		test_scripts = filtered
		if test_scripts.is_empty():
			push_error("A-006 test runner found no scripts for filter: %s" % name_filter)
			quit(1)
			return
	if not start_at.is_empty():
		var start_index := test_scripts.find(start_at)
		if start_index < 0:
			push_error("A-006 test runner cannot resume: test not found: %s" % start_at)
			quit(1)
			return
		var remaining_scripts: Array[String] = []
		for index in range(start_index, test_scripts.size()):
			remaining_scripts.append(test_scripts[index])
		test_scripts = remaining_scripts
		print("A-006 suite resuming at %s (%d tests remaining)" % [start_at, test_scripts.size()])

	for script in test_scripts:
		var log_name := script.replace("/", "_").replace(".gd", ".log")
		var log_path := log_directory.path_join(log_name)
		var arguments := PackedStringArray([
			"--headless",
			"--log-file",
			log_path,
			"--path",
			project_root,
			"--script",
			"res://%s" % script,
		])
		var result := run_test_process(executable, arguments, log_path, TEST_TIMEOUT_MSEC)
		var exit_code := int(result["exit_code"])
		var output_text := String(result["output"])
		print(output_text.strip_edges())
		var has_engine_error := contains_actionable_engine_error(output_text)
		if exit_code != 0 or has_engine_error or bool(result["timed_out"]):
			failed += 1
			push_error("FAILED %s (exit code %d, engine error %s)" % [script, exit_code, has_engine_error])
		else:
			print("PASSED %s" % script)

	print("A-006 suite: %d passed, %d failed" % [test_scripts.size() - failed, failed])
	quit(1 if failed > 0 else 0)


static func run_test_process(executable: String, arguments: PackedStringArray, log_path: String, timeout_msec: int) -> Dictionary:
	# Each child owns its log; an old successful log must never mask a failed launch.
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var pid := OS.create_process(executable, arguments)
	if pid < 0:
		return {"exit_code": -1, "timed_out": false, "output": "ERROR: Could not start test process"}
	var deadline := Time.get_ticks_msec() + timeout_msec
	var timed_out := false
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() >= deadline:
			timed_out = true
			OS.kill(pid)
			break
		OS.delay_msec(20)
	var exit_code := OS.get_process_exit_code(pid)
	var output_text := FileAccess.get_file_as_string(log_path) if FileAccess.file_exists(log_path) else "ERROR: Test process produced no engine log"
	if timed_out:
		output_text += "\nERROR: Test exceeded its time limit (%d ms)\n" % timeout_msec
	return {"exit_code": exit_code, "timed_out": timed_out, "output": output_text}


static func contains_actionable_engine_error(output_text: String) -> bool:
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
