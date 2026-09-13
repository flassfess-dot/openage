extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_all_world_directions_reach_real_slp_blocks()
	test_real_attack_clip_never_runs_backwards_between_phases()

	if failures.is_empty():
		print("I5-002 animation/direction integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_all_world_directions_reach_real_slp_blocks() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var descriptor = catalog.get_graphic_descriptor("clubman", "move")
	var frames: Array = catalog.unit_animation_frames("clubman", "move")
	var world = SimulationWorld.new(Vector2i(12, 12))
	var directions := [Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0)]
	var expected_sources := [0, 1, 2, 3, 4, 3, 2, 1]
	for expected_facing in range(8):
		var logical := world.facing_for_vector(directions[expected_facing])
		var resolved: Dictionary = descriptor.resolve(logical, 0.0, frames.size())
		assert_equal(logical, expected_facing, "world direction %d has calibrated logical facing" % expected_facing)
		assert_equal(resolved["source_direction"], expected_sources[expected_facing], "logical %s uses calibrated SLP block" % FacingConvention.label(expected_facing))
		assert_equal(resolved["mirrored"], expected_facing >= 5, "logical %s uses calibrated mirror" % FacingConvention.label(expected_facing))


func test_real_attack_clip_never_runs_backwards_between_phases() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec(catalog.gamespec_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(5.55, 5.0), false)
	world.assign_command_attack([attacker], int(target["id"]))
	var descriptor = catalog.get_graphic_descriptor("clubman", "attack")
	var frames: Array = catalog.unit_animation_frames("clubman", "attack")
	var previous_time := -1.0
	var previous_frame := -1
	var seen_recover := false
	var seen_restart := false
	for _tick in range(80):
		world.update_units(0.05, 1, 99)
		var state := String(attacker["anim_state"])
		if state not in [AnimationController.ATTACK_WINDUP, AnimationController.ATTACK_RECOVER]:
			continue
		var animation_time := float(attacker["anim"])
		var resolved: Dictionary = descriptor.resolve(int(attacker["action_facing"]), animation_time, frames.size())
		if seen_recover and state == AnimationController.ATTACK_WINDUP:
			assert_float(animation_time, 0.0, "new attack cycle explicitly restarts at frame zero")
			seen_restart = true
			break
		if previous_time >= 0.0:
			assert_true(animation_time + 0.000001 >= previous_time, "windup/recover time is monotonic inside one attack cycle")
			assert_true(int(resolved["animation_frame"]) >= previous_frame, "real SLP attack frames never run backwards")
		if state == AnimationController.ATTACK_RECOVER:
			seen_recover = true
		previous_time = animation_time
		previous_frame = int(resolved["animation_frame"])
	assert_true(seen_recover, "real attack entered recovery phase")
	assert_true(seen_restart, "real attack began a second explicit cycle")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %.4f, got %.4f" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
