extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const AssignmentGroup := preload("res://scripts/source_ai_assignment_group.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.reset_game(false)
	var first: Dictionary = world.add_unit(2, "clubman", Vector2(8, 8), false)
	var second: Dictionary = world.add_unit(2, "clubman", Vector2(9, 8), false)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(5, 3), false)
	var enemy: Dictionary = world.add_unit(1, "clubman", Vector2(21, 20), false)
	var town: Dictionary = world.create_building(2, "town_center", Vector2(12, 12), true)
	world.add_resource("berry_bush", Vector2(7, 4), 200)
	world.update_fog_of_war()

	var ai = AiPlayer.new({
		"team": 2,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 1, "formation": "LINE"},
		"source_ai": {
			"build_order": [], "target_markers": [],
			"runtime_support": {"military_enabled": true, "attack_enabled": false, "defence_response_enabled": false, "defence_enabled": true, "exploration_enabled": false},
			"strategic_numbers": [
				{"source_id": 22, "value": 10, "runtime_semantics": "implemented"},
				{"source_id": 25, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 28, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 38, "value": 1, "runtime_semantics": "implemented"},
				{"source_id": 56, "value": 1, "runtime_semantics": "implemented"},
			],
		},
	})
	var controller = GameController.new(world)
	var snapshot := SimulationSnapshot.presentation(world, 0, 2, ai.presentation_options())
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.map(func(command): return command.command_type()), ["build"], "local defend assignment does not add a redundant route beside the economy command")
	assert_true(commands[0].unit_ids == [int(worker.get("id", -1))], "economy keeps ownership of its worker")
	assert_equal(ai.source_assignment_groups.size(), 1, "defend group persists after its rally command")
	for command in commands:
		controller.enqueue_command(command, true, 2)
	controller.advance_frame(0.05, 1, 2)
	first["pos"] = Vector2(town.get("pos", Vector2.ZERO)) + Vector2(-3.0, -3.0)
	second["pos"] = Vector2(town.get("pos", Vector2.ZERO)) + Vector2(-2.5, -3.0)
	enemy["pos"] = Vector2(town.get("pos", Vector2.ZERO)) + Vector2(3.0, 3.0)
	world.sync_all_components()
	world.update_fog_of_war()

	snapshot = SimulationSnapshot.presentation(world, controller.tick_index, 2, ai.presentation_options())
	commands = ai.collect_commands(snapshot, controller.tick_index + 1)
	assert_equal(commands.size(), 1, "persistent defend group intercepts a newly visible local threat")
	assert_equal(commands[0].command_type(), "attack", "defence interception enters the authoritative combat pipeline")
	assert_equal(commands[0].unit_ids, [int(first.get("id", -1)), int(second.get("id", -1))], "the exact reserved defend roster receives the interception")
	var group = ai.source_assignment_groups.values()[0]
	assert_equal(group.state, AssignmentGroup.ENGAGING, "AI state records the live defensive engagement")
	assert_equal(group.target_id, int(enemy.get("id", -1)), "AI state records the exact local threat")
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	var accepted := controller.get_command_result(int(commands[0].sequence_id))
	assert_true(bool(accepted.get("accepted", false)), "defence command is accepted by the shared game controller: %s" % [accepted])

	if failures.is_empty():
		print("I12-020L source defence assignment pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
