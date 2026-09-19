extends SceneTree

const NodeRuntime := preload("res://tests/test_support/node_runtime.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var output: Array = []
	var node_binary := NodeRuntime.resolve()
	if node_binary.is_empty():
		failures.append(NodeRuntime.unavailable_message())
	else:
		var importer := ProjectSettings.globalize_path("res://../tools/ror_import/import_assets.js")
		var exit_code := OS.execute(node_binary, [importer, "--self-test-slp"], output, true)
		if exit_code != 0:
			failures.append("SLP semantic self-test exited with %d: %s" % [exit_code, "\n".join(output)])
		elif output.is_empty() or not String(output[0]).contains("G-004 SLP semantic self-test passed"):
			failures.append("SLP semantic self-test did not report success: %s" % "\n".join(output))

	if failures.is_empty():
		print("G-004 SLP command tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
