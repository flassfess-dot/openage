extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []
var catalog


func run() -> Array[String]:
	catalog = ResourceCatalog.new()
	catalog.load()
	verify_sicily_vertical()
	verify_mylae_vertical()
	verify_tunes_vertical()
	return failures


func bootstrap(path: String) -> Dictionary:
	var definition := MatchDefinition.load_json(path)
	var map_data := MapGenerator.generate(definition)
	var world = SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, map_data)
	return {"definition": definition, "world": world}


func verify_sicily_vertical() -> void:
	var path := "res://assets/generated/matches/struggle-for-sicily.json"
	var loaded := bootstrap(path)
	var world = loaded["world"]
	assert_equal(world.get_units().size(), 22, "Sicily bootstraps all mapped units")
	assert_equal(world.get_buildings().size(), 7, "Sicily bootstraps all mapped buildings")
	assert_equal(world.get_resources().size(), 2659, "Sicily bootstraps all forest resources")
	var target_ids: Dictionary = {}
	for group in loaded["definition"].get("scenario_definition", {}).get("participants", [])[0].get("groups", []):
		for condition in group.get("conditions", []):
			for source_id in condition.get("target_scenario_object_ids", []):
				target_ids[int(source_id)] = true
	for unit in world.get_units():
		if target_ids.has(int(unit.get("scenario_object_id", -1))):
			unit["hp"] = 0.0
	world.check_battle_state(1, 2, 0.05)
	assert_victory(world, "Sicily exact DestroyMultiple set")
	verify_local_defeat(path, "Sicily")


func verify_mylae_vertical() -> void:
	var path := "res://assets/generated/matches/battle-of-mylae.json"
	var loaded := bootstrap(path)
	var world = loaded["world"]
	assert_equal(world.get_units().size(), 60, "Mylae bootstraps regular units and two artifacts")
	var artifacts: Array = world.get_units().filter(func(value): return int(value.get("source_unit_id", -1)) == 159)
	assert_equal(artifacts.size(), 2, "Mylae runtime contains both artifact entities")
	var conditions: Array = loaded["definition"].get("scenario_definition", {}).get("participants", [])[0].get("groups", [])[0].get("conditions", [])
	for condition in conditions:
		var matching: Array = artifacts.filter(func(value): return int(value.get("scenario_object_id", -1)) == int(condition.get("target_scenario_object_id", -1)))
		if matching.is_empty():
			continue
		var area: Array = condition.get("area", [])
		matching[0]["pos"] = Vector2((float(area[0]) + float(area[2])) * 0.5, (float(area[1]) + float(area[3])) * 0.5)
	world.check_battle_state(1, 2, 0.05)
	assert_victory(world, "Mylae exact BringToArea pair")
	verify_local_defeat(path, "Mylae")


func verify_tunes_vertical() -> void:
	var path := "res://assets/generated/matches/battle-of-tunes.json"
	var loaded := bootstrap(path)
	var world = loaded["world"]
	assert_equal(world.get_buildings().size(), 410, "Tunes bootstraps all mapped buildings including Guard Towers")
	assert_equal(world.get_resources().size(), 6338, "Tunes bootstraps the full source forest")
	var wonder: Array = world.get_buildings().filter(func(value): return int(value.get("scenario_object_id", -1)) == 11230)
	assert_equal(wonder.size(), 1, "Tunes retains the exact Carthaginian Wonder target")
	if not wonder.is_empty():
		world.begin_building_destruction(wonder[0])
	world.create_building(1, "wonder", Vector2(110.0, 190.0), true)
	world.check_battle_state(1, 2, 0.05)
	assert_victory(world, "Tunes paired Wonder destruction and construction")
	verify_local_defeat(path, "Tunes")


func verify_local_defeat(path: String, context: String) -> void:
	var loaded := bootstrap(path)
	var world = loaded["world"]
	var controller := GameController.new(world)
	var resign := Commands.ResignCommand.new(1)
	controller.enqueue_command(resign, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(resign.sequence_id).get("accepted", false)), "%s local resignation crosses the public command boundary" % context)
	assert_equal(String(world.player_registry.status(1)), "resigned", "%s records the local player as terminal" % context)
	assert_true(not world.is_battle_over() or int(world.get_victory_result().get("winner_team", -1)) != 1, "%s cannot award victory to the resigned participant" % context)
	assert_true(not controller.events_after().any(func(event): return String(event.get("type", "")) == "scenario_completed" and int(event.get("payload", {}).get("winner_team", -1)) == 1), "%s suppresses completed objectives owned by the resigned participant" % context)


func assert_victory(world, context: String) -> void:
	assert_true(world.is_battle_over(), "%s completes the mission" % context)
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "%s awards player one" % context)
	assert_equal(String(world.get_victory_result().get("reason", "")), "scenario", "%s retains scenario outcome" % context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
