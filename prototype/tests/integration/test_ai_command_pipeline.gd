extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.reset_game(false)
	var first: Dictionary = world.add_unit(2, "clubman", Vector2(5, 5), false)
	var second: Dictionary = world.add_unit(2, "clubman", Vector2(5, 6), false)
	world.add_unit(1, "clubman", Vector2(8, 5), false)
	world.update_fog_of_war()

	var controller = GameController.new(world)
	var ai = AiPlayer.new({"team": 2, "ai": {"formation": "WEDGE"}})
	var legal_snapshot := SimulationSnapshot.presentation(world, 0, 2)
	var commands: Array = ai.collect_commands(legal_snapshot, 1)
	assert_equal(commands.size(), 1, "AI produces one non-conflicting tactical command")
	for command in commands:
		controller.enqueue_command(command, true, 2)
	controller.advance_frame(0.05, 1, 2)

	var accepted := controller.events_after().filter(func(event): return String(event.get("type", "")) == "command_accepted" and int(event.get("payload", {}).get("issuer_id", 0)) == 2)
	assert_true(not accepted.is_empty(), "AI command receives authoritative accepted event")
	assert_equal(commands[0].command_type(), "attack", "integration command commits the visible target instead of stopping at its position")
	assert_equal(first.get("target_id"), second.get("target_id"), "group attack assigns the same authoritative target to every fighter")
	assert_equal(first.get("task"), "attack", "first fighter enters the common combat order pipeline")
	assert_equal(second.get("task"), "attack", "second fighter enters the common combat order pipeline")
	assert_equal(first.get("combat_slot_count"), 2, "group attack allocates source-independent combat approach slots")
	assert_true(int(first.get("combat_slot_index", -1)) != int(second.get("combat_slot_index", -1)), "fighters receive distinct combat approach slots")

	if failures.is_empty():
		print("I11-005 AI command pipeline integration tests passed")
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
