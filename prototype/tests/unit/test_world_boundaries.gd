extends SceneTree

const RenderWorld := preload("res://scripts/render_world.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_render_world_is_read_only()

	if failures.is_empty():
		print("A-003 world boundary tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_render_world_is_read_only() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.reset_game()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3.25, 7.5), true)
	unit["target"] = Vector2(8.0, 9.0)
	unit["task"] = "move"
	world.add_resource("tree", Vector2(5.0, 6.0), 75)

	var units_before: Array = world.get_units().duplicate(true)
	var resources_before: Array = world.get_resources().duplicate(true)
	var buildings_before: Array = world.get_buildings().duplicate(true)
	var food_before: int = world.get_food()
	var wood_before: int = world.get_wood()
	var kills_before: int = world.get_kills()

	var renderer = RenderWorld.new()
	seed(41721)
	var first_random: float = randf()
	var drawables: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position * 10.0)
	var random_after_render: float = randf()

	seed(41721)
	var expected_first_random: float = randf()
	var expected_second_random: float = randf()

	assert_equal(first_random, expected_first_random, "test RNG baseline")
	assert_equal(random_after_render, expected_second_random, "render must not consume RNG")
	assert_equal(world.get_units(), units_before, "render must not mutate units")
	assert_equal(world.get_resources(), resources_before, "render must not mutate resources")
	assert_equal(world.get_buildings(), buildings_before, "render must not mutate buildings")
	assert_equal(world.get_food(), food_before, "render must not mutate food")
	assert_equal(world.get_wood(), wood_before, "render must not mutate wood")
	assert_equal(world.get_kills(), kills_before, "render must not mutate kills")
	assert_equal(drawables.size(), 6, "building, resource, unit, shadow and separate overlays without a frame provider")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
