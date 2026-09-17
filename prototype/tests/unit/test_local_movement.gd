extends SceneTree

const Footprint := preload("res://scripts/footprint.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_velocity_and_neighbor_avoidance()
	test_obstacle_fallback_and_speed_limit()
	test_runtime_fast_path_matches_generic()

	if failures.is_empty():
		print("N-005 local movement tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_velocity_and_neighbor_avoidance() -> void:
	var grid = open_grid()
	var left := unit(1, Vector2(4.0, 5.0), Vector2(9.0, 5.0))
	var right := unit(2, Vector2(4.65, 5.0), Vector2(1.0, 5.0))
	var left_result := LocalMovement.calculate(left, left["target"], [right], grid, 0.05)
	var right_result := LocalMovement.calculate(right, right["target"], [left], grid, 0.05)
	assert_true(left_result["actual_velocity"].y > 0.0, "left unit steers to its right")
	assert_true(right_result["actual_velocity"].y < 0.0, "opposite unit steers to its right")
	assert_true(left_result["actual_velocity"].length() <= left["speed"] + 0.0001, "left speed capped")
	assert_true(right_result["actual_velocity"].length() <= right["speed"] + 0.0001, "right speed capped")


func test_obstacle_fallback_and_speed_limit() -> void:
	var grid = open_grid()
	grid.set_terrain(Vector2i(5, 5), "water")
	var moving := unit(3, Vector2(4.95, 5.5), Vector2(8.0, 5.5))
	var result := LocalMovement.calculate(moving, moving["target"], [], grid, 0.5)
	assert_true(result["reason"] in ["local_obstacle", "local_blocked"], "blocked proposal reports reason")
	assert_true(result["actual_velocity"].length() <= moving["speed"] + 0.0001, "fallback speed capped")
	var next: Vector2 = moving["pos"] + result["actual_velocity"] * 0.5
	if result["actual_velocity"] != Vector2.ZERO:
		assert_true(Vector2i(floori(next.x), floori(next.y)) != Vector2i(5, 5), "fallback does not enter obstacle")


func test_runtime_fast_path_matches_generic() -> void:
	var grid = open_grid()
	var moving := runtime_unit(10, Vector2(4.0, 5.0), Vector2(9.0, 5.0))
	var neighbor := runtime_unit(11, Vector2(4.65, 5.0), Vector2(1.0, 5.0))
	var generic_unit: Dictionary = moving.duplicate(true)
	var runtime_unit_copy: Dictionary = moving.duplicate(true)
	var generic_reason := LocalMovement.calculate_into(generic_unit, generic_unit["target"], [neighbor], grid, 0.05)
	var runtime_reason := LocalMovement.calculate_runtime_unit_into(runtime_unit_copy, runtime_unit_copy["target"], [neighbor], grid, 0.05)
	assert_true(runtime_reason == generic_reason, "runtime fast path preserves diagnostic reason")
	assert_true(runtime_unit_copy["desired_velocity"] == generic_unit["desired_velocity"], "runtime fast path preserves desired velocity")
	assert_true(runtime_unit_copy["actual_velocity"] == generic_unit["actual_velocity"], "runtime fast path preserves actual velocity")
	var enveloped_unit: Dictionary = moving.duplicate(true)
	var envelope := {"open": true, "minimum": Vector2(0.0, 0.0), "maximum": Vector2(12.0, 12.0)}
	var enveloped_reason := LocalMovement.calculate_runtime_unit_into(enveloped_unit, enveloped_unit["target"], [neighbor], grid, 0.05, envelope)
	assert_true(enveloped_reason == generic_reason, "open envelope preserves diagnostic reason")
	assert_true(enveloped_unit["actual_velocity"] == generic_unit["actual_velocity"], "open envelope preserves movement result")
	var shared_unit: Dictionary = moving.duplicate(true)
	var empty_generic: Dictionary = moving.duplicate(true)
	LocalMovement.calculate_runtime_unit_into(empty_generic, empty_generic["target"], [], grid, 0.05, envelope)
	LocalMovement.calculate_shared_translation_into(shared_unit, shared_unit["target"])
	assert_true(shared_unit["desired_velocity"] == empty_generic["desired_velocity"], "shared translation preserves desired velocity")
	assert_true(shared_unit["actual_velocity"] == empty_generic["actual_velocity"], "shared translation matches isolated local movement")


func unit(id: int, position: Vector2, target: Vector2) -> Dictionary:
	return {
		"id": id,
		"pos": position,
		"previous_pos": position,
		"target": target,
		"speed": 1.2,
		"hp": 20.0,
		"footprint_radius": 0.3,
		"minimum_clearance": Footprint.DEFAULT_CLEARANCE,
		"push_priority": 2,
	}


func runtime_unit(id: int, position: Vector2, target: Vector2) -> Dictionary:
	var result := unit(id, position, target)
	result["cohesion_speed_scale"] = 1.0
	result["movement_domain"] = "land"
	result["terrain_restriction"] = -1
	return result


func open_grid():
	var grid = NavigationGrid.new(Vector2i(12, 12))
	grid.configure_terrain(func(_cell: Vector2i) -> String: return "land")
	return grid


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
