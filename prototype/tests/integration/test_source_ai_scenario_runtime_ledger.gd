extends SceneTree

const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MatchRegistry := preload("res://scripts/match_registry.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const ScenarioLedger := preload("res://scripts/source_ai_scenario_ledger.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const LEDGER_PATH := "res://data/parity/source_ai_scenario_runtime_ledger.json"

var failures: Array[String] = []


func _initialize() -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string(LEDGER_PATH))
	assert_true(expected is Dictionary, "source AI scenario ledger parses")
	if not expected is Dictionary:
		finish_test()
		return
	var catalog := ResourceCatalog.new()
	catalog.load()
	var expected_missions: Array = expected.get("missions", [])
	assert_equal(expected_missions.size(), int(expected.get("mission_count", -1)), "ledger mission count is self-consistent")
	assert_equal(expected_missions.size(), 6, "all published Rise of Rome missions own runtime evidence")
	for expected_value in expected_missions:
		var expected_mission: Dictionary = expected_value
		var match_id := String(expected_mission.get("match_id", ""))
		var entry := MatchRegistry.resolve(match_id)
		assert_true(not entry.is_empty(), "%s resolves through the public match registry" % match_id)
		if entry.is_empty():
			continue
		var definition := MatchDefinition.load_json(String(entry.get("path", "")))
		var map_data := MapGenerator.generate(definition)
		var world = configured_world(catalog, map_data)
		MatchBootstrap.apply(world, definition, map_data)
		var actual := ScenarioLedger.probe(world, GameController.new(world), definition, int(expected.get("tick", 1)))
		var validation_errors := ScenarioLedger.validate_probe(actual)
		assert_equal(validation_errors, [], "%s probe obeys the common command contract" % match_id)
		assert_equal(int(actual.get("rejected_command_count", -1)), 0, "%s initial source commands are all authoritative" % match_id)
		var json_normalized_actual = JSON.parse_string(JSON.stringify(ScenarioLedger.stable_projection(actual)))
		assert_equal(json_normalized_actual, expected_mission, "%s runtime evidence has not drifted" % match_id)
	finish_test()


func configured_world(catalog, map_data: Dictionary):
	var world := SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish_test() -> void:
	if failures.is_empty():
		print("I12 source AI scenario runtime ledger tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
