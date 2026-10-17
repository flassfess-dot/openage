extends SceneTree
const Scenario := preload("res://tests/support/control_group_lifecycle_scenario.gd")
func _initialize() -> void:
	var failures: Array[String] = await Scenario.new().run(self)
	for failure in failures: push_error(failure)
	print("Destroyed control group keyboard pipeline: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
