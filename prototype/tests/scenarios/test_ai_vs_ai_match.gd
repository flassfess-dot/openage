extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.normalize({
		"id": "ai_smoke",
		"map": {"size": [20, 20], "seed": 88021, "generator": {"water_border": {}}},
		"players": [
			{"team": 1, "controller": "ai", "civilization_id": 13, "start": [5, 10], "ai": {"military_interval_ticks": 10, "formation": "WEDGE"}},
			{"team": 2, "controller": "ai", "civilization_id": 13, "start": [9, 10], "ai": {"military_interval_ticks": 10, "formation": "LINE"}},
		],
		"entities": [
			{"category": "unit", "team": 1, "kind": "clubman", "position": [5, 9]},
			{"category": "unit", "team": 1, "kind": "clubman", "position": [5, 10]},
			{"category": "unit", "team": 1, "kind": "clubman", "position": [5, 11]},
			{"category": "unit", "team": 2, "kind": "clubman", "position": [9, 10]},
		],
		"victory_rules": [{"type": "conquest"}],
	})
	assert_true(bool(definition.get("valid", false)), "AI smoke definition validates")
	var map_data := RandomMapGenerator.generate(definition)
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, map_data)
	var controller = GameController.new(world)
	var players := [AiPlayer.new(definition["players"][0]), AiPlayer.new(definition["players"][1])]
	var issued_by_team := {1: 0, 2: 0}

	for _step in range(2400):
		var next_tick: int = int(controller.tick_index) + 1
		for ai in players:
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team))
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, int(ai.team))
				issued_by_team[int(ai.team)] += 1
		controller.advance_frame(0.05, 1, 2)
		if world.is_battle_over():
			break

	assert_true(issued_by_team[1] > 0 and issued_by_team[2] > 0, "both AI players act through public commands")
	assert_true(world.is_battle_over(), "AI versus AI match reaches a terminal state")
	assert_equal(world.get_victory_result().get("winner_team"), 1, "asymmetric deterministic smoke match has stable winner")
	assert_equal(world.get_victory_result().get("reason"), "conquest", "AI match ends through configured RoR victory rule")
	var accepted_teams: Dictionary = {}
	for event in controller.events_after():
		if String(event.get("type", "")) == "command_accepted":
			accepted_teams[int(event.get("payload", {}).get("issuer_id", 0))] = true
	assert_true(accepted_teams.has(1) and accepted_teams.has(2), "event stream proves accepted commands for both AI players")

	if failures.is_empty():
		print("I11-008 full AI versus AI smoke match passed")
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
