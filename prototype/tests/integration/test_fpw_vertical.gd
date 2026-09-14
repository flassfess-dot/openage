extends SceneTree

const FpwVerticalHarness := preload("res://tests/fpw_vertical_harness.gd")


func _initialize() -> void:
	var failures: Array[String] = FpwVerticalHarness.new().run()
	if failures.is_empty():
		print("I12-020N First Punic War bootstrap and outcome vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
