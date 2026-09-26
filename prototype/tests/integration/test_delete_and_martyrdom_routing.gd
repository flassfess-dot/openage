extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"

var failures: Array[String] = []


func _initialize() -> void:
	test_delete_command_is_authoritative()
	test_foreign_entity_rejects_atomic_batch()
	test_delete_replay_round_trip()
	await test_delete_key_routes_by_live_conversion()
	if failures.is_empty():
		print("P02 Delete and Martyrdom routing tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_delete_command_is_authoritative() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(4, 4), false)
	var building: Dictionary = world.add_building(80, "house", Vector2(10, 10), 1)
	var population_before: int = world.get_population_points(1)
	var controller = GameController.new(world)
	var ids: Array[int] = [int(worker["id"]), int(building["id"])]
	var deletion = Commands.DeleteEntityCommand.new(1, ids)
	controller.enqueue_command(deletion, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(deletion.sequence_id).get("accepted", false)), "own unit and building delete through the public controller")
	assert_equal(float(worker.get("hp", -1.0)), 0.0, "deleted worker enters the death lifecycle")
	assert_equal(float(building.get("hp", -1.0)), 0.0, "deleted building enters the destruction lifecycle")
	assert_true(world.get_population_points(1) < population_before, "unit deletion releases exact population points")


func test_foreign_entity_rejects_atomic_batch() -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	var own: Dictionary = world.add_unit(1, "villager", Vector2(4, 4), false)
	var enemy: Dictionary = world.add_unit(2, "villager", Vector2(12, 12), false)
	var controller = GameController.new(world)
	var ids: Array[int] = [int(own["id"]), int(enemy["id"])]
	var deletion = Commands.DeleteEntityCommand.new(1, ids)
	controller.enqueue_command(deletion, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_equal(String(controller.get_command_result(deletion.sequence_id).get("reason", "")), "issuer_team_mismatch", "foreign entity rejects the entire deletion batch")
	assert_true(float(own.get("hp", 0.0)) > 0.0, "rejected mixed batch does not delete the own unit")
	assert_true(float(enemy.get("hp", 0.0)) > 0.0, "rejected mixed batch cannot delete the enemy")


func test_delete_replay_round_trip() -> void:
	var ids: Array[int] = [4, 80]
	var deletion = Commands.DeleteEntityCommand.new(7, ids)
	assert_true(deletion.assign_envelope(1, 3), "deletion receives a replay envelope")
	var replay = ReplaySystem.new()
	replay.begin(24681357)
	replay.record_command(deletion)
	var loaded = ReplaySystem.new()
	assert_true(loaded.load_json(replay.to_json()), "deletion replay loads from JSON")
	var restored = loaded.command_from_record(loaded.command_records[0])
	assert_equal(String(restored.command_type()), "delete_entity", "replay reconstructs DeleteEntityCommand")
	assert_equal(restored.unit_ids, ids, "replay preserves deleted entity IDs")


func test_delete_key_routes_by_live_conversion() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var priest: Dictionary = game.simulation_world.add_unit(1, "priest", Vector2(10, 10), false)
	var enemy: Dictionary = game.simulation_world.add_unit(2, "clubman", Vector2(10.2, 10), false)
	var building: Dictionary = game.simulation_world.add_building(980, "house", Vector2(15, 15), 1)
	game.simulation_world.set_resource_amount(1, 57, 1)
	priest["task"] = "convert"
	priest["components"]["conversion"]["active"] = true
	priest["components"]["conversion"]["target_id"] = int(enemy["id"])
	OrderPipeline.begin(priest, "convert", int(enemy["id"]), Vector2(enemy["pos"]), true)
	OrderPipeline.transition(priest, OrderPipeline.PERFORM_ACTION)
	assert_equal(game.simulation_world.conversion_system.validate_martyrdom(priest), "", "active Priest fixture is eligible for Martyrdom")
	var selected_ids: Array[int] = [int(priest["id"]), int(building["id"])]
	game.player_control_state.replace_or_add(selected_ids, false)
	game.sync_world_state()
	var expected_selected_ids: Array[int] = selected_ids.duplicate()
	expected_selected_ids.sort()
	assert_equal(game.player_control_state.selected_ids(), expected_selected_ids, "current snapshot preserves selected entities before overview refresh")
	var record_count: int = game.game_controller.replay_recorder.command_records.size()
	game.handle_input_action({"type": "delete_context"})
	var new_records: Array = game.game_controller.replay_recorder.command_records.slice(record_count)
	assert_equal(new_records.size(), 2, "Delete produces separate Martyrdom and deletion commands for mixed selection")
	if new_records.size() == 2:
		assert_equal(String(new_records[0].get("type", "")), "martyrdom", "eligible converting Priest routes to Martyrdom")
		assert_equal(String(new_records[1].get("type", "")), "delete_entity", "other own entity routes to deletion")
	game.free()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
