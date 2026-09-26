extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	var controller = GameController.new(world)
	world.set_resource_amount(1, 1, 100)
	world.set_resource_amount(2, 1, 10)
	var rejected = Commands.TributeCommand.new(0, 2, 1, 40)
	controller.enqueue_command(rejected, true, 1)
	controller.process_commands()
	assert_equal(String(controller.get_command_result(rejected.sequence_id).get("reason", "")), "tribute_requires_ally", "tribute requires diplomacy")
	assert_equal(world.get_resource_amount(1, 1), 100, "rejected transaction leaves sender unchanged")
	assert_equal(world.get_resource_amount(2, 1), 10, "rejected transaction leaves recipient unchanged")
	world.set_alliance(1, 2, true)
	world.begin_event_capture()
	var accepted = Commands.TributeCommand.new(0, 2, 1, 40)
	controller.enqueue_command(accepted, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(accepted.sequence_id).get("accepted", false)), "valid tribute crosses command boundary")
	assert_equal(world.get_resource_amount(1, 1), 60, "sender pays the full amount")
	assert_equal(world.get_resource_amount(2, 1), 40, "recipient receives amount after 25 percent source tax")
	var replay = ReplaySystem.new()
	replay.record_command(accepted)
	var restored = replay.command_from_record(replay.command_records[0])
	assert_equal(restored.command_type(), "tribute", "tribute survives replay command decoding")
	assert_equal(int(restored.amount), 40, "replay retains tribute amount")
	var events: Array = world.drain_domain_events().filter(func(event): return String(event.get("type", "")) == "tribute_paid")
	assert_equal(events.size(), 1, "one fog-neutral domain event records transaction")
	if not events.is_empty():
		assert_equal(int(events[0]["payload"].get("tax_lost", -1)), 10, "event preserves exact tax loss")
	var invalid = Commands.TributeCommand.new(0, 2, 1, 1000)
	controller.enqueue_command(invalid, true, 1)
	controller.process_commands()
	assert_true(not bool(controller.get_command_result(invalid.sequence_id).get("accepted", true)), "insufficient stock rejects whole transaction")
	assert_equal(world.get_resource_amount(2, 1), 40, "failed second transaction does not credit recipient")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P05 tribute pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
