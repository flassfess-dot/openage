extends SceneTree

const EntityIds := preload("res://scripts/entity_id.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_sequence_never_reuses_active_id()
	test_world_uses_one_id_space()

	if failures.is_empty():
		print("A-002 entity ID tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_sequence_never_reuses_active_id() -> void:
	var sequence = EntityIds.new()
	var first: int = sequence.next()
	var second: int = sequence.next()
	var third: int = sequence.next()
	assert_equal([first, second, third], [1, 2, 3], "monotonic sequence")
	assert_equal(sequence.peek(), 4, "next active ID")


func test_world_uses_one_id_space() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	var first_unit: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	world.add_resource("tree", Vector2(4.0, 4.0), 75)
	var resource: Dictionary = world.get_resources()[0]
	var second_unit: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 3.0), false)

	assert_equal(first_unit["id"], 1, "first unit ID")
	assert_equal(resource["id"], 2, "resource shares global ID sequence")
	assert_equal(second_unit["id"], 3, "second unit follows resource ID")

	world.units.erase(first_unit)
	var replacement: Dictionary = world.add_unit(1, "archer", Vector2(5.0, 5.0), false)
	assert_equal(second_unit["id"], 3, "removing an entity preserves remaining IDs")
	assert_equal(replacement["id"], 4, "removed active ID is not reused")

	world.reset_game()
	var new_game_unit: Dictionary = world.add_unit(1, "villager", Vector2.ONE, false)
	assert_equal(new_game_unit["id"], 1, "a new world session restarts the sequence")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
