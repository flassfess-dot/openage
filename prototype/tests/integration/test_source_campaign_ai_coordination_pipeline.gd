extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const AttackGroup := preload("res://scripts/source_ai_attack_group.gd")
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
	var members: Array = [
		world.add_unit(2, "clubman", Vector2(2, 2), false),
		world.add_unit(2, "clubman", Vector2(10, 2), false),
		world.add_unit(2, "clubman", Vector2(2, 6), false),
		world.add_unit(2, "clubman", Vector2(10, 6), false),
	]
	world.add_unit(1, "clubman", Vector2(20, 20), false)
	world.update_fog_of_war()

	var ai = AiPlayer.new({
		"team": 2,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 1, "formation": "LINE"},
		"source_ai": {
			"build_order": [],
			"target_markers": [{"position": Vector2(20, 20)}],
			"runtime_support": {"military_enabled": true, "attack_enabled": true, "defence_response_enabled": false},
			"strategic_numbers": [
				{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 26, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 36, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 40, "value": 0, "runtime_semantics": "implemented"},
				{"source_id": 41, "value": 3, "runtime_semantics": "implemented"},
				{"source_id": 46, "value": 30, "runtime_semantics": "implemented"},
				{"source_id": 47, "value": 1, "runtime_semantics": "implemented"},
				{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
			],
		},
	})
	var controller = GameController.new(world)
	var snapshot := SimulationSnapshot.presentation(world, 0, 2, ai.presentation_options())
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.size(), 2, "two spread groups receive two independent rally commands")
	assert_equal(commands[0].command_type(), "move", "first group enters the authoritative move pipeline")
	assert_equal(commands[1].command_type(), "move", "second group enters the authoritative move pipeline")
	assert_equal(ai.source_attack_groups.size(), 2, "both source groups persist while gathering")
	for command in commands:
		controller.enqueue_command(command, true, 2)
	controller.advance_frame(0.05, 1, 2)
	for group_value in ai.source_attack_groups.values():
		var group = group_value
		for index in range(group.member_ids.size()):
			var entity_id := int(group.member_ids[index])
			for member_value in members:
				if int(member_value.get("id", -1)) == entity_id:
					member_value["pos"] = group.rally_position + Vector2(float(index), 0.0)
	world.sync_all_components()
	world.update_fog_of_war()

	snapshot = SimulationSnapshot.presentation(world, controller.tick_index, 2, ai.presentation_options())
	commands = ai.collect_commands(snapshot, controller.tick_index + 1)
	assert_equal(commands.size(), 1, "coordination mode 1 releases one gathered group")
	var group_ids: Array = ai.source_attack_groups.keys()
	group_ids.sort()
	var first_group = ai.source_attack_groups[group_ids[0]]
	var second_group = ai.source_attack_groups[group_ids[1]]
	if commands.is_empty():
		failures.append("gathered groups produced no release; tick=%d last_military=%d states=%s positions=%s" % [controller.tick_index, ai.last_military_tick, [first_group.state, second_group.state], snapshot.get("units", []).map(func(unit): return unit.get("pos", Vector2.ZERO))])
		finish()
		return
	assert_equal(commands[0].command_type(), "attack_move", "released group re-enters the authoritative attack-move pipeline")
	assert_equal(first_group.state, AttackGroup.ATTACKING, "lowest deterministic group ID attacks first")
	assert_equal(second_group.state, AttackGroup.READY, "second group remains queued rather than duplicating the attack")
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	first_group.transition(AttackGroup.COMPLETE, "integration_first_group_complete", controller.tick_index)

	snapshot = SimulationSnapshot.presentation(world, controller.tick_index, 2, ai.presentation_options())
	commands = ai.collect_commands(snapshot, controller.tick_index + 1)
	assert_equal(commands.size(), 1, "queued group is released after the active group completes")
	if commands.is_empty():
		failures.append("serially queued group produced no release")
		finish()
		return
	assert_equal(commands[0].command_type(), "attack_move", "queued release uses the same public command path")
	assert_equal(second_group.state, AttackGroup.ATTACKING, "serial coordination advances without rebuilding the group")
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	var accepted := controller.get_command_result(int(commands[0].sequence_id))
	assert_true(bool(accepted.get("accepted", false)), "coordinated release is accepted by the authoritative controller")

	finish()


func finish() -> void:
	if failures.is_empty():
		print("I12-020L source attack-group coordination pipeline tests passed")
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
