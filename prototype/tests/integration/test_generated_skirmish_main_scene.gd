extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["starting_age_id"] = "tool"
	settings["population_limit"] = 75
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated launch definition is valid: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		_finish("E5-002 generated skirmish main scene tests passed")
		return

	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = String(built["identity"])
	game.match_definition_override = built["definition"].duplicate(true)
	game.map_definition_override = built["map_data"].duplicate(true)
	root.add_child(game)
	await process_frame
	await process_frame
	assert_equal(game.match_path, built["identity"], "generated identity becomes the save compatibility key")
	assert_equal(game.match_definition.get("source_path"), built["identity"], "runtime records the synthetic source identity")
	assert_equal(game.map_size, Vector2i(48, 48), "generated map size reaches the main scene")
	assert_equal(game.simulation_world.player_registry.all_teams(), [1, 2], "generated player slots reach the authoritative registry")
	assert_equal(game.simulation_world.technology_system.current_age(1), 101, "selected starting age reaches simulation")
	assert_equal(game.simulation_world.economy_system.get_population_limit(1), 75, "selected population limit reaches simulation")
	assert_equal(game.simulation_world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "town_center").size(), 2, "both generated starting towns bootstrap")
	var archive := GameSaveArchive.create(game.match_path, game.match_definition, 0, "0".repeat(64), game.game_controller.replay_recorder.to_dictionary(), [], {}, {})
	assert_equal(String(archive.get("match_fingerprint", "")), GameSaveArchive.fingerprint(game.match_definition), "generated match participates in ordinary save fingerprinting")
	for index in range(16500):
		game.game_controller.event_stream.emit(index, "presentation_retention_probe")
	game.process_presentation_events()
	assert_true(game.game_controller.event_stream.retained_count() <= 16384, "live presentation prunes only consumed old events")
	var next_sequence: int = game.game_controller.event_stream.latest_sequence() + 1
	game.game_controller.event_stream.emit(16500, "presentation_retention_probe")
	game.process_presentation_events()
	assert_equal(game.command_feedback_router.event_cursor, next_sequence, "event cursor continues after live journal pruning")
	game.free()
	_finish("E5-002 generated skirmish main scene tests passed")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
