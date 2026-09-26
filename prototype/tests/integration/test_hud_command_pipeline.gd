extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const HudViewModel := preload("res://scripts/hud_view_model.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var barracks: Dictionary = world.add_building(80, "barracks", Vector2(10.0, 10.0), 1)
	world.add_unit(2, "clubman", Vector2(18.0, 18.0), false)
	var controller = GameController.new(world)
	var view_model = HudViewModel.new()
	view_model.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)

	var before: Dictionary = view_model.build(SimulationSnapshot.presentation(world, 0, 1), [80], "RECTANGLE", "ru")
	var action: Dictionary = find_action(before, "train", "clubman")
	assert_true(bool(action.get("enabled", false)), "HUD action is enabled by authoritative snapshot query")
	var command = Commands.TrainCommand.new(1, [int(action["building_id"])], String(action["id"]), 1, Vector2.ZERO)
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)

	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "HUD command passes through normal controller boundary")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "production_queued"), "simulation publishes production event")
	assert_equal(barracks["production_queue"].size(), 1, "accepted command mutates only authoritative production system")
	var second = Commands.TrainCommand.new(controller.tick_index + 1, [int(barracks["id"])], "clubman", 1, Vector2.ZERO)
	controller.enqueue_command(second, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(second.sequence_id).get("accepted", false)), "same-line waiting order uses the public command path")
	assert_equal(barracks["production_queue"].size(), 2, "selected producer now has one active and one waiting order")
	var after: Dictionary = view_model.build(SimulationSnapshot.presentation(world, controller.tick_index, 1), [80], "RECTANGLE", "ru")
	assert_equal(after["queue"].size(), 2, "next snapshot updates the HUD queue")
	assert_true(float(after["queue"][0]["progress"]) > 0.0, "queue progress comes back from fixed simulation tick")
	assert_equal(int(find_action(after, "train", "clubman").get("queue_count", 0)), 2, "train action receives the authoritative queue count")
	var cancel_action: Dictionary = find_action(after, "cancel_production", "cancel_0")
	assert_true(bool(cancel_action.get("enabled", false)), "non-empty queue exposes cancellation command")
	assert_equal(int(cancel_action.get("queue_index", -1)), 1, "HUD cancellation targets the last waiting instance")
	var cancel = Commands.CancelProductionCommand.new(controller.tick_index + 1, [int(cancel_action["building_id"])], int(cancel_action["queue_index"]))
	controller.enqueue_command(cancel, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(cancel.sequence_id).get("accepted", false)), "cancel command uses normal controller boundary")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "production_cancelled"), "cancellation publishes simulation event")
	assert_equal(barracks["production_queue"].size(), 1, "one-item cancel preserves the active operation")
	assert_equal(world.get_resource_amount(1, 0), 130, "waiting-item cancellation refunds only one authoritative cost")
	var cancelled: Dictionary = view_model.build(SimulationSnapshot.presentation(world, controller.tick_index, 1), [80], "RECTANGLE", "ru")
	assert_equal(cancelled["queue"].size(), 1, "following snapshot retains the active queue item")
	var cancel_active_action: Dictionary = find_action(cancelled, "cancel_production", "cancel_0")
	var cancel_active = Commands.CancelProductionCommand.new(controller.tick_index + 1, [int(cancel_active_action["building_id"])], int(cancel_active_action["queue_index"]))
	controller.enqueue_command(cancel_active, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_equal(barracks["production_queue"].size(), 0, "last single-item cancel clears the active operation")
	assert_equal(world.get_resource_amount(1, 0), 180, "both explicit cancellations refund their own cost")

	if failures.is_empty():
		print("I10-002 HUD command integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func find_action(model: Dictionary, action_type: String, action_id: String) -> Dictionary:
	for action_value in model.get("commands", []):
		var action: Dictionary = action_value
		if String(action.get("type", "")) == action_type and String(action.get("id", "")) == action_id:
			return action
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
