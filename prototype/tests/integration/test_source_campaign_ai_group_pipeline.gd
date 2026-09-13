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
	var first: Dictionary = world.add_unit(2, "clubman", Vector2(9, 10), false)
	var second: Dictionary = world.add_unit(2, "clubman", Vector2(10, 10), false)
	var target: Dictionary = world.add_unit(1, "clubman", Vector2(12, 10), false)
	world.update_fog_of_war()

	var ai = AiPlayer.new({
		"team": 2,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 1, "formation": "LINE"},
		"source_ai": {
			"build_order": [], "target_markers": [],
			"runtime_support": {"military_enabled": true, "attack_enabled": true, "defence_response_enabled": false},
			"strategic_numbers": [
				{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 26, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 30, "value": 25, "runtime_semantics": "implemented"},
				{"source_id": 31, "value": 100, "runtime_semantics": "implemented"},
				{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
				{"source_id": 46, "value": 30, "runtime_semantics": "implemented"},
				{"source_id": 49, "value": 1, "runtime_semantics": "implemented"},
				{"source_id": 91, "value": 100, "runtime_semantics": "implemented"},
				{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
			],
		},
	})
	var controller = GameController.new(world)
	var snapshot := SimulationSnapshot.presentation(world, 0, 2, ai.presentation_options())
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.size(), 1, "source AI creates one initial attack-group command")
	assert_equal(commands[0].command_type(), "attack", "initial group enters the public attack pipeline")
	assert_equal(ai.source_attack_groups.size(), 1, "AI retains the attack group after command emission")
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)

	first["hp"] = 15.0
	world.sync_all_components()
	snapshot = SimulationSnapshot.presentation(world, controller.tick_index, 2, ai.presentation_options())
	commands = ai.collect_commands(snapshot, controller.tick_index + 1)
	assert_equal(commands.size(), 1, "group health loss emits one retreat without a conflicting replacement attack")
	assert_equal(commands[0].command_type(), "formation_move", "retreat uses the authoritative formation movement command")
	var group = ai.source_attack_groups[1]
	assert_equal(group.state, AttackGroup.RETREATING, "persistent group records the retreat transition")
	assert_equal(group.last_transition_reason, "group_health_threshold", "retreat records its exact deterministic cause")
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	var accepted := controller.get_command_result(int(commands[0].sequence_id))
	assert_true(bool(accepted.get("accepted", false)), "retreat command is accepted by the authoritative controller")
	assert_true(int(target.get("id", -1)) > 0 and int(second.get("id", -1)) > 0, "pipeline keeps source target and surviving member identities stable")

	if failures.is_empty():
		print("I12-020L source attack-group pipeline tests passed")
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
