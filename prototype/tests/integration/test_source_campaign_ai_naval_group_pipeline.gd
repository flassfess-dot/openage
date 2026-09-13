extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var terrain_ids: Array[int] = []
	terrain_ids.resize(16 * 16)
	terrain_ids.fill(1)
	var vertex_levels: Array[int] = []
	vertex_levels.resize(17 * 17)
	vertex_levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain_ids, "vertex_levels": vertex_levels})
	var first: Dictionary = world.add_unit(2, "scout_ship", Vector2(2.5, 2.5), false)
	var second: Dictionary = world.add_unit(2, "scout_ship", Vector2(3.5, 2.5), false)
	world.update_fog_of_war()

	var ai = AiPlayer.new({
		"team": 2,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 1, "formation": "LINE"},
		"source_ai": {
			"build_order": [],
			"target_markers": [{"position": Vector2(12.5, 12.5)}],
			"runtime_support": {"military_enabled": true, "attack_enabled": true, "naval_attack_enabled": true},
			"strategic_numbers": [
				{"source_id": 36, "value": 0, "runtime_semantics": "implemented"},
				{"source_id": 58, "value": 1, "runtime_semantics": "implemented"},
				{"source_id": 59, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 60, "value": 2, "runtime_semantics": "implemented"},
				{"source_id": 40, "value": 0, "runtime_semantics": "implemented"},
				{"source_id": 46, "value": 30, "runtime_semantics": "implemented"},
			],
		},
	})
	var options := ai.presentation_options()
	assert_true(bool(options.get("include_navigation", false)), "naval attack requests the domain projection required to legalize source markers")
	var snapshot := SimulationSnapshot.presentation(world, 0, 2, options)
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.size(), 1, "one source-sized boat group emits one command")
	assert_equal(commands[0].command_type(), "attack_move", "boat group uses the shared authoritative attack-move path")
	assert_equal(commands[0].unit_ids, [int(first.get("id", -1)), int(second.get("id", -1))], "the exact deterministic boat roster enters the command")
	assert_equal(ai.source_attack_groups.size(), 1, "naval attack group persists in AI canonical state")
	assert_equal(ai.source_attack_groups.values()[0].movement_domain, "water", "persisted source group owns the water domain")

	var controller = GameController.new(world)
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	var accepted := controller.get_command_result(int(commands[0].sequence_id))
	assert_true(bool(accepted.get("accepted", false)), "naval source command is accepted by the common game controller: %s" % [accepted])
	assert_equal(first.get("task"), "attack_move", "first ship enters the common combat/navigation pipeline")
	assert_equal(second.get("task"), "attack_move", "second ship enters the common combat/navigation pipeline")

	if failures.is_empty():
		print("I12-020L source naval group pipeline tests passed")
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
