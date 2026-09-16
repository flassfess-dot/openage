extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const MAX_TICKS := 13000
const SEED := 41721

var failures: Array[String] = []


func _initialize() -> void:
	var built := generated_match()
	assert_true(bool(built.get("valid", false)), "deterministic outcome match builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var live := create_runtime(built)
	var world = live["world"]
	var controller = live["controller"]
	var ai = AiPlayer.new(built["definition"]["players"][1])
	var recorder = controller.start_recording(SEED, false)
	var issued := 0
	while int(controller.tick_index) < MAX_TICKS and not world.is_battle_over():
		var next_tick := int(controller.tick_index) + 1
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, int(ai.team))
				issued += 1
		controller.advance_frame(0.5, 1, 2)

	var final_tick := int(controller.tick_index)
	var result: Dictionary = world.get_victory_result()
	var final_hash: String = recorder.world_state_hash(world, final_tick, controller)
	print("E5-006B live tick=%d issued=%d battle_over=%s result=%s hash=%s" % [final_tick, issued, world.is_battle_over(), result, final_hash])
	assert_true(issued > 0, "generated AI records public commands")
	assert_true(world.is_battle_over(), "generated two-player inland match reaches a terminal state")
	assert_equal(int(result.get("winner_team", 0)), 2, "active generated AI defeats the idle human opponent")
	assert_equal(String(result.get("reason", "")), "conquest", "generated match ends through configured conquest")

	if world.is_battle_over():
		var replay := create_runtime(generated_match())
		var replay_world = replay["world"]
		var replay_controller = replay["controller"]
		assert_true(replay_controller.load_replay(recorder.to_json()), "generated command recording loads for deterministic playback")
		assert_true(replay_controller.replay_until_tick(final_tick, 1, 2), "generated command recording reaches the live terminal tick")
		var replay_hash: String = recorder.world_state_hash(replay_world, final_tick, replay_controller)
		assert_equal(replay_hash, final_hash, "generated victory has an identical canonical replay hash")
		assert_equal(replay_world.get_victory_result(), result, "generated replay preserves the exact victory result")
	finish()


func generated_match() -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "grasslands"
	settings["seed"] = SEED
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	return SkirmishSettings.build(settings)


func create_runtime(built: Dictionary) -> Dictionary:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var definition: Dictionary = built["definition"]
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, built["map_data"])
	return {"world": world, "controller": GameController.new(world)}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006B generated skirmish deterministic outcome passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
