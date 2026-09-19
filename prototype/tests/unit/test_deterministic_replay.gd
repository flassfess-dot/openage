extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_round_trip_and_identical_state(catalog)
	test_same_tick_command_order(catalog)
	test_issue_tick_preserves_autonomous_sequence(catalog)
	test_incremental_recording_preserves_both_orders()
	test_legacy_replay_envelope_migration(catalog)
	test_cancel_production_round_trip()
	test_resign_round_trip()
	test_diplomacy_round_trip()
	test_transport_commands_round_trip()
	test_trade_commands_round_trip()
	test_mismatch_detection(catalog)
	if failures.is_empty():
		print("S-013 deterministic replay tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_round_trip_and_identical_state(catalog) -> void:
	var first := setup_match(catalog, 24681357)
	var first_world = first["world"]
	var first_controller = first["controller"]
	var recorder = first_controller.start_recording(24681357)
	var player_ids := typed_ids(first["player_ids"])
	first_controller.enqueue_command(Commands.FormationMoveCommand.new(1, player_ids, Vector2(12.0, 8.0), "LINE", Vector2(1.0, 0.0)))
	first_controller.enqueue_command(Commands.AttackCommand.new(7, [player_ids[0]], first["enemy_id"]))
	first_controller.advance_frame(0.5, 1, 2)
	var first_hash: String = recorder.world_state_hash(first_world, first_controller.tick_index)
	var serialized: String = recorder.to_json()
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(serialized), "replay JSON round-trip")
	assert_equal(loaded.simulation_seed, 24681357, "replay preserves seed")
	assert_equal(loaded.command_records.size(), 2, "replay preserves commands")

	var second := setup_match(catalog, 24681357)
	var second_world = second["world"]
	var second_controller = second["controller"]
	assert_true(second_controller.load_replay(serialized), "controller accepts serialized replay")
	second_controller.advance_frame(0.5, 1, 2)
	var second_hash: String = loaded.world_state_hash(second_world, second_controller.tick_index)
	assert_equal(second_hash, first_hash, "same seed and commands produce identical state hash")
	assert_equal(second_controller.last_replay_mismatch, "", "recorded per-tick hashes match playback")


func test_mismatch_detection(catalog) -> void:
	var first := setup_match(catalog, 77)
	var recorder = first["controller"].start_recording(77)
	first["controller"].enqueue_command(Commands.MoveCommand.new(1, typed_ids(first["player_ids"]), Vector2(10.0, 10.0)))
	first["controller"].advance_frame(0.05, 1, 2)
	var tampered: Dictionary = recorder.to_dictionary().duplicate(true)
	tampered["state_hashes"][0]["sha256"] = "0000"
	var replay := setup_match(catalog, 77)
	assert_true(replay["controller"].load_replay(tampered), "tampered replay still has valid format")
	replay["controller"].advance_frame(0.05, 1, 2)
	assert_true(not String(replay["controller"].last_replay_mismatch).is_empty(), "state divergence reports exact replay mismatch")


func test_same_tick_command_order(catalog) -> void:
	var first := setup_match(catalog, 991)
	var unit_id := int(first["player_ids"][0])
	var recorder = first["controller"].start_recording(991)
	# Different command types used to be reordered alphabetically by replay.
	first["controller"].enqueue_command(Commands.StopCommand.new(1, [unit_id]), true, 1)
	first["controller"].enqueue_command(Commands.MoveCommand.new(1, [unit_id], Vector2(11.0, 9.0)), true, 1)
	first["controller"].advance_frame(0.05, 1, 2)
	var serialized: String = recorder.to_json()
	var records: Array = recorder.command_records
	assert_equal(int(records[0]["sequence_id"]), 1, "first same-tick command keeps sequence")
	assert_equal(int(records[1]["sequence_id"]), 2, "second same-tick command keeps sequence")
	assert_equal(String(records[0]["type"]), "stop", "same-tick recorder keeps insertion order")
	assert_equal(String(records[1]["type"]), "move", "same-tick recorder does not sort by type")

	var second := setup_match(catalog, 991)
	assert_true(second["controller"].load_replay(serialized), "same-tick replay loads")
	second["controller"].advance_frame(0.05, 1, 2)
	assert_equal(second["world"].find_unit(unit_id)["task"], first["world"].find_unit(unit_id)["task"], "same-tick final task matches live order")
	assert_equal(second["world"].find_unit(unit_id)["target"], first["world"].find_unit(unit_id)["target"], "same-tick target matches live order")
	assert_equal(second["controller"].last_replay_mismatch, "", "same-tick state hash matches playback")


func test_issue_tick_preserves_autonomous_sequence(catalog) -> void:
	var first := setup_match(catalog, 992)
	var controller = first["controller"]
	var recorder = controller.start_recording(992)
	controller.next_command_sequence = 5
	controller.tick_index = 4
	var command = Commands.StopCommand.new(6, [int(first["player_ids"][0])])
	controller.enqueue_command(command, true, 1)
	assert_equal(int(recorder.command_records[0].get("issued_tick", -1)), 4, "recorder distinguishes issue tick from execution tick")
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_dictionary(recorder.to_dictionary()), "issue-timed replay loads")
	assert_equal(loaded.commands_issued_through_tick(3).size(), 0, "future issuance is not injected early")
	var issued: Array = loaded.commands_issued_through_tick(4)
	assert_equal(issued.size(), 1, "command appears on its original issue tick")
	assert_equal(int(issued[0].sequence_id), 5, "issue-timed command preserves its envelope")


func test_incremental_recording_preserves_both_orders() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(993)
	var late_execution = Commands.StopCommand.new(9, [1])
	late_execution.assign_envelope(2, 1)
	var early_execution = Commands.MoveCommand.new(4, [1], Vector2(3.0, 3.0))
	early_execution.assign_envelope(2, 2)
	recorder.record_command(late_execution, 1)
	recorder.record_command(early_execution, 2)
	assert_equal(recorder.command_records.map(func(record): return int(record["tick"])), [4, 9], "incremental replay index remains ordered by execution tick")
	assert_equal(recorder.issuance_records.map(func(record): return int(record["issued_tick"])), [1, 2], "incremental replay index remains ordered by issuance tick")


func test_legacy_replay_envelope_migration(catalog) -> void:
	var source := setup_match(catalog, 551)
	var recorder = source["controller"].start_recording(551)
	var unit_id := int(source["player_ids"][0])
	source["controller"].enqueue_command(Commands.StopCommand.new(1, [unit_id]), true, 1)
	source["controller"].enqueue_command(Commands.MoveCommand.new(1, [unit_id], Vector2(9.0, 7.0)), true, 1)
	var legacy: Dictionary = recorder.to_dictionary().duplicate(true)
	legacy["format_version"] = 1
	for record in legacy["commands"]:
		record.erase("issuer_id")
		record.erase("sequence_id")
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_dictionary(legacy), "legacy replay remains readable")
	assert_equal(int(loaded.command_records[0]["sequence_id"]), 1, "legacy first record receives file-order sequence")
	assert_equal(int(loaded.command_records[1]["sequence_id"]), 2, "legacy second record receives file-order sequence")
	assert_equal(int(loaded.command_records[0]["issuer_id"]), 0, "legacy issuer uses neutral default")


func test_cancel_production_round_trip() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(912)
	var command = Commands.CancelProductionCommand.new(4, [80], 2)
	command.assign_envelope(1, 7)
	recorder.record_command(command)
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "cancel-production replay loads")
	var restored = loaded.commands_through_tick(4)[0]
	assert_equal(restored.command_type(), "cancel_production", "cancel-production command type round-trips")
	assert_equal(restored.unit_ids, [80], "cancel-production building ID round-trips")
	assert_equal(restored.queue_index, 2, "cancel-production queue index round-trips")
	assert_equal(restored.sequence_id, 7, "cancel-production envelope round-trips")


func test_resign_round_trip() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(913)
	var command = Commands.ResignCommand.new(5)
	command.assign_envelope(2, 8)
	recorder.record_command(command)
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "resign replay loads")
	var restored = loaded.commands_through_tick(5)[0]
	assert_equal(restored.command_type(), "resign", "resign command type round-trips")
	assert_equal(restored.issuer_id, 2, "resign issuer round-trips")
	assert_equal(restored.sequence_id, 8, "resign envelope round-trips")


func test_diplomacy_round_trip() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(916)
	var command = Commands.DiplomacyCommand.new(5, 3, "neutral")
	command.assign_envelope(1, 13)
	recorder.record_command(command)
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "diplomacy replay loads")
	var restored = loaded.commands_through_tick(5)[0]
	assert_equal(restored.command_type(), "diplomacy", "diplomacy command type round-trips")
	assert_equal(restored.target_team, 3, "diplomacy target team round-trips")
	assert_equal(restored.relation, "neutral", "diplomacy relation round-trips")
	assert_equal(restored.issuer_id, 1, "diplomacy issuer round-trips")


func test_transport_commands_round_trip() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(914)
	var board = Commands.BoardCommand.new(6, [41, 42], 17)
	board.assign_envelope(1, 9)
	var unload = Commands.UnloadCommand.new(7, [17], Vector2(8.5, 9.5), [41])
	unload.assign_envelope(1, 10)
	recorder.record_command(board)
	recorder.record_command(unload)
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "transport command replay loads")
	var restored_board = loaded.commands_through_tick(6)[0]
	assert_equal(restored_board.command_type(), "board", "BoardCommand round-trips")
	assert_equal(restored_board.unit_ids, [41, 42], "boarding passenger IDs round-trip")
	assert_equal(restored_board.transport_id, 17, "boarding transport ID round-trips")
	var restored_unload = loaded.commands_through_tick(7)[0]
	assert_equal(restored_unload.command_type(), "unload", "UnloadCommand round-trips")
	assert_equal(restored_unload.target, Vector2(8.5, 9.5), "unload landing point round-trips")
	assert_equal(restored_unload.passenger_ids, [41], "partial unload selection round-trips")


func test_trade_commands_round_trip() -> void:
	var recorder := ReplaySystem.new()
	recorder.begin(915)
	var resource = Commands.SetTradeResourceCommand.new(8, [51], 2)
	resource.assign_envelope(1, 11)
	var route = Commands.TradeCommand.new(9, [51], 145)
	route.assign_envelope(1, 12)
	recorder.record_command(resource)
	recorder.record_command(route)
	var loaded := ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "trade command replay loads")
	var restored_resource = loaded.commands_through_tick(8)[0]
	assert_equal(restored_resource.command_type(), "set_trade_resource", "trade resource command round-trips")
	assert_equal(restored_resource.resource_type_id, 2, "trade resource ID round-trips")
	var restored_route = loaded.commands_through_tick(9)[0]
	assert_equal(restored_route.command_type(), "trade", "TradeCommand round-trips")
	assert_equal(restored_route.target_dock_id, 145, "trade Dock ID round-trips")


func setup_match(catalog, seed_value: int) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_simulation_seed(seed_value)
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 8.0), false)
	var second: Dictionary = world.add_unit(1, "archer", Vector2(4.0, 9.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(18.0, 8.0), false)
	return {
		"world": world,
		"controller": GameController.new(world),
		"player_ids": [int(first["id"]), int(second["id"])],
		"enemy_id": int(enemy["id"]),
	}


func typed_ids(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
