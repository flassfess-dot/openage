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
	# The default map places water at x <= 1 and shore at x == 2. Keep the
	# artifact next to the ship's actual water position so boarding is in range.
	var transport: Dictionary = world.add_unit(1, "transport", Vector2(1.5, 10.5), false)
	var artifact: Dictionary = world.add_unit(0, "artifact", Vector2(2.6, 10.5), false)
	var controller = GameController.new(world)
	var board = Commands.BoardCommand.new(0, [int(artifact["id"])], int(transport["id"]))
	controller.enqueue_command(board, true, 1)
	controller.process_commands()
	var boarding_result: Dictionary = controller.get_command_result(board.sequence_id)
	assert_true(bool(boarding_result.get("accepted", false)), "visible neutral artifact boards through the public command boundary (%s)" % String(boarding_result.get("reason", "")))
	if not bool(boarding_result.get("accepted", false)):
		finish()
		return
	assert_true(world.transport_system.embarked_units.has(int(artifact["id"])), "artifact is present in cargo manifest")
	var objective_id := int(artifact.get("victory_objective_id", -1))
	for objective in world.victory_objectives:
		if int(objective.get("id", -1)) == objective_id:
			assert_true(not bool(objective.get("active", true)), "embarked artifact has no phantom map objective")
	world.transport_system.destroy_cargo(transport)
	assert_true(not world.transport_system.embarked_units.has(int(artifact["id"])), "transport loss resolves artifact cargo")
	assert_equal(float(artifact.get("hp", -1.0)), 0.0, "transport loss destroys embarked artifact")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P04 artifact cargo policy passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
