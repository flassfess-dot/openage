extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_command_payloads_are_owned()
	test_controller_assigns_unique_envelopes()
	test_commands_execute_on_scheduled_tick()
	test_train_uses_command_pipeline()

	if failures.is_empty():
		print("A-004 command tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_command_payloads_are_owned() -> void:
	var source_ids: Array[int] = [4, 8]
	var command = Commands.BuildCommand.new(12, source_ids, "storage_pit", Vector2(6.5, 7.25))
	source_ids[0] = 99
	assert_equal(command.tick, 12, "command tick")
	assert_equal(command.unit_ids, [4, 8], "command owns unit ID list")
	assert_equal(command.params["building_type"], "storage_pit", "build parameter")
	assert_equal(command.params["target"], Vector2(6.5, 7.25), "build target")
	var formation = Commands.FormationMoveCommand.new(13, [4, 8], Vector2(9.0, 7.0), "LINE", Vector2(3.0, 0.0))
	assert_equal(formation.forward, Vector2(1.0, 0.0), "formation front is normalized")
	assert_equal(formation.params["forward"], Vector2(1.0, 0.0), "formation front is serialized")
	var policy := {"autonomous": true, "trigger": "stance"}
	var attack = Commands.AttackCommand.new(14, [4], 20, policy)
	policy["trigger"] = "mutated"
	assert_equal(attack.params["trigger"], "stance", "attack policy payload is owned")
	assert_equal(Commands.AttackMoveCommand.new(15, [4], Vector2.ONE).command_type(), "attack_move", "attack-move has an explicit command type")
	assert_equal(Commands.StanceCommand.new(16, [4], "defensive").params["stance"], "defensive", "stance is serializable command data")
	assert_equal(Commands.ReturnResourcesCommand.new(17, [4], 90).params["target_building_id"], 90, "return-resources target is serializable command data")
	assert_equal(Commands.CancelProductionCommand.new(18, [90], 2).params["queue_index"], 2, "production cancellation index is serializable command data")
	assert_equal(Commands.ResignCommand.new(19).command_type(), "resign", "resign is an explicit player command")
	assert_equal(Commands.DeleteEntityCommand.new(19, [4, 8]).command_type(), "delete_entity", "deletion is an explicit serializable entity command")
	var board = Commands.BoardCommand.new(20, [4, 8], 17)
	assert_equal(board.params, {"transport_id": 17}, "boarding target is serializable command data")
	var selected_passengers: Array[int] = [4]
	var unload = Commands.UnloadCommand.new(21, [17], Vector2(6.5, 8.5), selected_passengers)
	selected_passengers[0] = 99
	assert_equal(unload.params["passenger_ids"], [4], "unload owns its passenger selection")
	assert_equal(unload.params["target"], Vector2(6.5, 8.5), "unload landing point is serializable")
	var trade_resource = Commands.SetTradeResourceCommand.new(22, [15, 16], 2)
	assert_equal(trade_resource.params, {"resource_type_id": 2}, "trade input resource is serializable command data")
	var trade = Commands.TradeCommand.new(23, [15, 16], 45)
	assert_equal(trade.params, {"target_dock_id": 45}, "trade route target is serializable command data")
	var diplomacy = Commands.DiplomacyCommand.new(24, 3, "neutral")
	assert_equal(diplomacy.params, {"target_team": 3, "relation": "neutral"}, "directed diplomacy is serializable command data")
	assert_true(Commands.is_valid_diplomacy_relation("ally") and Commands.is_valid_diplomacy_relation("neutral") and Commands.is_valid_diplomacy_relation("enemy"), "all source diplomacy relations are accepted")
	assert_true(not Commands.is_valid_diplomacy_relation("peace"), "unknown diplomacy relation is rejected")


func test_controller_assigns_unique_envelopes() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	var controller = GameController.new(world)
	var stop_command = Commands.StopCommand.new(1, [unit["id"]])
	var move_command = Commands.MoveCommand.new(1, [unit["id"]], Vector2(8.0, 8.0))
	controller.enqueue_command(stop_command, true, 1)
	controller.enqueue_command(move_command, true, 1)
	assert_equal(stop_command.issuer_id, 1, "command envelope stores issuer")
	assert_equal(stop_command.sequence_id, 1, "first command receives first sequence")
	assert_equal(move_command.sequence_id, 2, "second command receives next sequence")
	assert_true(stop_command.command_id != move_command.command_id, "command IDs never collide within controller")


func test_commands_execute_on_scheduled_tick() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.MoveCommand.new(2, [unit["id"]], Vector2(8.0, 8.0)))

	controller.advance_frame(0.05, 1, 2)
	assert_equal(unit["task"], "idle", "future command remains pending")
	assert_equal(controller.command_queue.size(), 1, "future command stays queued")

	controller.advance_frame(0.05, 1, 2)
	assert_equal(unit["task"], "move", "command executes at scheduled tick")
	assert_equal(unit["target"], Vector2(8.0, 8.0), "move target is applied")
	assert_equal(controller.command_queue.size(), 0, "executed command leaves queue")


func test_train_uses_command_pipeline() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec({"units": {"clubman": {"hit_points": 40.0, "speed": 1.0, "creation_time": 26, "resource_cost": [{"type_id": 0, "amount": 50, "enabled": true}, {"type_id": 4, "amount": 1, "enabled": false}]}}})
	var building: Dictionary = world.add_building(90, "town_center", Vector2(8.0, 8.0), 1)
	building["rally_point"] = Vector2(4.0, 5.0)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.TrainCommand.new(1, [], "clubman", 1, Vector2(4.0, 5.0)))
	assert_equal(world.get_units().size(), 0, "train command is deferred")
	assert_equal(world.get_food(), 180, "train cost is deferred")

	controller.advance_frame(0.05, 1, 2)
	assert_equal(world.get_units().size(), 0, "train command enqueues rather than spawning instantly")
	assert_equal(building["production_queue"].size(), 1, "train command enters production queue")
	assert_equal(world.get_food(), 130, "train command reserves cost")
	building["production_queue"][0]["duration"] = 0.05
	world.battle_over = false
	controller.advance_frame(0.05, 1, 2)
	assert_equal(world.get_units().size(), 1, "completed queue creates unit")
	assert_equal(world.get_units()[0]["kind"], "clubman", "trained unit type")
	assert_true(world.get_units()[0]["pos"] != building["pos"], "trained unit uses free spawn slot outside building")
	assert_equal(world.get_units()[0]["destination"], Vector2(4.0, 5.0), "trained unit receives rally point")
	assert_equal(world.get_food(), 130, "completion does not charge twice")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
