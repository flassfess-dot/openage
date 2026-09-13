extends SceneTree

const PointerController := preload("res://scripts/pointer_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_primary_click_and_box()
	test_context_and_direction_actions()
	test_panning()

	if failures.is_empty():
		print("C-001 pointer state tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_primary_click_and_box() -> void:
	var pointer = PointerController.new()
	pointer.begin_primary(Vector2(10, 10))
	var click: Dictionary = pointer.end_primary(Vector2(14, 13))
	assert_equal(click["type"], "select_click", "short primary gesture")
	assert_equal(pointer.state, PointerController.State.IDLE, "primary release resets state")

	pointer.begin_primary(Vector2(20, 20))
	pointer.update_position(Vector2(40, 45))
	assert_equal(pointer.state, PointerController.State.PRIMARY_BOX, "long primary gesture state")
	var box: Dictionary = pointer.end_primary(Vector2(45, 50))
	assert_equal(box["type"], "select_box", "long primary gesture action")
	assert_equal(box["from"], Vector2(20, 20), "selection origin")
	assert_equal(box["to"], Vector2(45, 50), "selection end")


func test_context_and_direction_actions() -> void:
	var pointer = PointerController.new()
	pointer.begin_secondary(Vector2(100, 100))
	var context: Dictionary = pointer.end_secondary(Vector2(103, 104))
	assert_equal(context["type"], "context_command", "short secondary gesture")

	pointer.begin_secondary(Vector2(100, 100))
	pointer.update_position(Vector2(113.9, 100))
	assert_equal(pointer.state, PointerController.State.SECONDARY_PENDING, "sub-threshold drag keeps front")
	assert_equal(pointer.is_setting_formation_direction(), false, "no preview below threshold")
	pointer.update_position(Vector2(114, 100))
	assert_equal(pointer.state, PointerController.State.SECONDARY_DIRECTION, "direction drag state")
	assert_equal(pointer.is_setting_formation_direction(), true, "preview above threshold")
	var direction: Dictionary = pointer.end_secondary(Vector2(140, 110))
	assert_equal(direction["type"], "formation_direction", "direction drag action")
	assert_equal(direction["position"], Vector2(100, 100), "formation destination")
	assert_equal(direction["direction_end"], Vector2(140, 110), "formation direction end")


func test_panning() -> void:
	var pointer = PointerController.new()
	pointer.begin_pan(Vector2(4, 6))
	assert_equal(pointer.update_position(Vector2(11, 2)), Vector2(7, -4), "pan delta")
	pointer.end_pan()
	assert_equal(pointer.state, PointerController.State.IDLE, "pan release resets state")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
