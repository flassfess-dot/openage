extends SceneTree

const Suite := preload("res://tests/test_suite.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var log_directory := ProjectSettings.globalize_path("res://qa/test-runner-fixtures")
	DirAccess.make_dir_recursive_absolute(log_directory)
	for mode in ["success", "failure", "error", "hang"]:
		var log_path := log_directory.path_join("%s.log" % mode)
		var arguments := PackedStringArray(["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/support/runner_process_fixture.gd", "--", mode])
		var result := Suite.run_test_process(OS.get_executable_path(), arguments, log_path, 1000 if mode == "hang" else 30_000)
		var exit_code := int(result["exit_code"])
		var engine_error := Suite.contains_actionable_engine_error(String(result["output"]))
		match mode:
			"success":
				check(exit_code == 0 and not engine_error and not result["timed_out"], "successful child is reported as passed")
			"failure":
				check(exit_code == 7 and not result["timed_out"], "nonzero child exit code is preserved")
			"error":
				check(exit_code == 0 and engine_error, "engine errors fail a child even when it exits zero")
			"hang":
				check(result["timed_out"] and engine_error, "a child that never quits is terminated and reported as failed")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)