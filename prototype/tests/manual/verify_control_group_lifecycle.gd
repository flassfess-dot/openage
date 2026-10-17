extends Node
const Scenario := preload("res://tests/support/control_group_lifecycle_scenario.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var failures: Array[String] = await Scenario.new().run(get_tree())
	var report := {"passed": failures.is_empty(), "release": not OS.is_debug_build() and not Engine.is_editor_hint(), "failures": failures}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--output="): continue
		var output := argument.trim_prefix("--output=")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null: push_error("Cannot write group verification report"); get_tree().quit(1); return
		file.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print("CONTROL_GROUP_LIFECYCLE ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
