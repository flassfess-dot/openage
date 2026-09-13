extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_frame_rate_independence()
	test_pause_and_speed()
	test_render_interpolation()

	if failures.is_empty():
		print("A-005 fixed timestep tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_frame_rate_independence() -> void:
	var setup_a: Dictionary = moving_world()
	var setup_b: Dictionary = moving_world()
	var controller_a = setup_a["controller"]
	var controller_b = setup_b["controller"]

	for frame in range(10):
		controller_a.advance_frame(0.02, 1, 2)
	for frame in range(4):
		controller_b.advance_frame(0.05, 1, 2)

	assert_equal(controller_a.tick_index, 4, "irregular frame tick count")
	assert_equal(controller_b.tick_index, 4, "fixed frame tick count")
	assert_vector_close(setup_a["unit"]["pos"], setup_b["unit"]["pos"], "equal simulated position")
	assert_equal(setup_a["unit"]["anim_state"], setup_b["unit"]["anim_state"], "equal animation state")


func test_pause_and_speed() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	world.add_unit(2, "clubman", Vector2(14.0, 14.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.set_paused(true)
	controller.advance_frame(0.25, 1, 2)
	assert_equal(controller.tick_index, 0, "pause freezes simulation")

	controller.set_paused(false)
	controller.set_speed_multiplier(2.0)
	controller.advance_frame(0.025, 1, 2)
	assert_equal(controller.tick_index, 1, "2x speed advances fixed tick")
	assert_equal(controller.get_speed_multiplier(), 2.0, "fast speed multiplier")


func test_render_interpolation() -> void:
	var setup: Dictionary = moving_world()
	var controller = setup["controller"]
	var unit: Dictionary = setup["unit"]
	controller.advance_frame(0.05, 1, 2)
	controller.advance_frame(0.025, 1, 2)

	var renderer = RenderWorld.new()
	var drawables: Array = renderer.create_world_drawables(setup["world"], func(position: Vector2) -> Vector2: return position, controller.get_interpolation_alpha())
	var rendered_position := Vector2.ZERO
	for drawable in drawables:
		if drawable["kind"] == "unit" and drawable["stable_id"] == unit["id"]:
			rendered_position = drawable["world_anchor"]
			break
	var expected: Vector2 = unit["previous_pos"].lerp(unit["pos"], 0.5)
	assert_vector_close(rendered_position, expected, "half-tick render interpolation")


func moving_world() -> Dictionary:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	world.add_unit(2, "clubman", Vector2(14.0, 14.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.MoveCommand.new(1, [unit["id"]], Vector2(10.0, 2.0)))
	return {"world": world, "controller": controller, "unit": unit}


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
