extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	# The default map has water at x <= 1 and shore at x == 2. A ship spawned
	# inland is relocated to the nearest water cell, outside boarding range.
	var transport: Dictionary = world.add_unit(1, "transport", Vector2(1.5, 10.5), false)
	var passenger: Dictionary = world.add_unit(2, "villager", Vector2(2.6, 10.5), false)
	assert_equal(world.board_units([passenger], transport), "passenger_not_owned", "foreign passenger is rejected")
	world.set_alliance(1, 2, true)
	var controller = GameController.new(world)
	var board = Commands.BoardCommand.new(0, [int(passenger["id"])], int(transport["id"]))
	controller.enqueue_command(board, true, 2)
	controller.process_commands()
	var board_result: Dictionary = controller.get_command_result(board.sequence_id)
	assert_true(bool(board_result.get("accepted", false)), "ally BoardCommand crosses the command boundary (%s)" % String(board_result.get("reason", "")))
	assert_true(world.find_unit(int(passenger["id"])) == null, "ally passenger is removed from active units")
	world.set_alliance(1, 2, false)
	assert_true(world.find_unit(int(passenger["id"])) != null or world.transport_system.embarked_units.has(int(passenger["id"])), "broken diplomacy never silently loses cargo")
	if world.find_unit(int(passenger["id"])) != null:
		assert_equal(int(passenger.get("team", -1)), 2, "ejection retains passenger ownership")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P04 allied cargo policy passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
