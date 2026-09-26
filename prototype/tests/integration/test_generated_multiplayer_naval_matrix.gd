extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const RandomMapQuality := preload("res://scripts/random_map_quality.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const CASES := [
	{"players": 4, "map_size_id": "standard", "map_type_id": "coastal", "seed": 41721},
	{"players": 4, "map_size_id": "standard", "map_type_id": "islands", "seed": 41721},
	{"players": 8, "map_size_id": "large", "map_type_id": "coastal", "seed": 41721},
	{"players": 8, "map_size_id": "large", "map_type_id": "islands", "seed": 41721},
]

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	for case_value in CASES:
		verify_case(case_value, catalog)
	finish()


func verify_case(case_value: Dictionary, catalog) -> void:
	var player_count := int(case_value["players"])
	var map_type := String(case_value["map_type_id"])
	var context := "%dp %s" % [player_count, map_type]
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = String(case_value["map_size_id"])
	settings["map_type_id"] = map_type
	settings["seed"] = int(case_value["seed"])
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	for index in range(8):
		settings["players"][index]["enabled"] = index < player_count
		settings["players"][index]["controller"] = "human" if index == 0 else "ai"
		settings["players"][index]["alliance_id"] = index + 1
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "%s builds: %s diagnostics=%s" % [context, built.get("errors", []), naval_diagnostics(built.get("map_data", {}))])
	if not bool(built.get("valid", false)):
		return

	var definition: Dictionary = built["definition"]
	var map_data: Dictionary = built["map_data"]
	var quality: Dictionary = RandomMapQuality.inspect(definition, map_data)
	assert_true(bool(quality.get("valid", false)), "%s passes the independent map quality gate: %s" % [context, quality.get("errors", [])])
	assert_equal(int(quality.get("metrics", {}).get("player_count", -1)), player_count, "%s quality audits every player" % context)
	assert_equal(int(quality.get("metrics", {}).get("naval_start_count", -1)), player_count, "%s exposes one naval start per player" % context)
	var zones: Array = map_data.get("naval_start_zones", [])
	assert_equal(zones.size(), player_count, "%s retains every Dock/staging zone" % context)
	var deep_fish: Array = map_data.get("resources", []).filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
	assert_true(deep_fish.size() >= player_count * 3, "%s retains three guaranteed Deep Fish per start plus neutral schools" % context)

	var world = SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var bootstrap: Dictionary = MatchBootstrap.apply(world, definition, map_data)
	assert_true(bool(bootstrap.get("naval_start_guarantees_met", false)), "%s bootstrap preserves every naval guarantee" % context)
	assert_equal(world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "town_center").size(), player_count, "%s bootstraps one Town Center per player" % context)
	assert_equal(world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "villager").size(), player_count * 3, "%s bootstraps three Villagers per player" % context)

	var land_components: Dictionary = {}
	var water_components: Dictionary = {}
	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		var team := int(player["team"])
		var start := Vector2(player["start"])
		var zone: Dictionary = zones.filter(func(candidate): return int(candidate.get("team", 0)) == team)[0]
		var land_component: int = world.navigation_grid.surface_component_id(Vector2i(start), "land")
		var water_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(zone["water_staging"])), "water")
		land_components[land_component] = true
		water_components[water_component] = true
		assert_true(land_component >= 0, "%s team %d starts on legal land (cell=%s terrain=%d kind=%s)" % [context, team, Vector2i(start), world.navigation_grid.terrain_id(Vector2i(start)), world.navigation_grid.terrain(Vector2i(start))])
		assert_true(water_component >= 0, "%s team %d has legal water staging" % [context, team])
		assert_true(deep_fish.filter(func(resource): return Vector2(resource.get("position", Vector2.ZERO)).distance_to(Vector2(zone["water_staging"])) <= 12.0).size() >= 2, "%s team %d has nearby reachable water food" % [context, team])
		assert_equal(world.get_team_relations(team).values().filter(func(relation): return String(relation) == "enemy").size(), player_count - 1, "%s team %d sees every other participant as an enemy" % [context, team])
	assert_equal(water_components.size(), 1, "%s gives all fleets access to the same ocean component" % context)
	if map_type == "islands":
		assert_true(land_components.size() > 1, "%s retains disconnected islands without requiring one private island per player" % context)
	else:
		assert_equal(land_components.size(), 1, "%s keeps every player on the shared coastal mainland" % context)

	world.update_fog_of_war()
	var controller = GameController.new(world)
	var submitted: Array = []
	var issued_by_team: Dictionary = {}
	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		if String(player.get("controller", "ai")) != "ai":
			continue
		var ai = AiPlayer.new(player)
		var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
		var commands: Array = ai.collect_commands(knowledge, 1)
		issued_by_team[int(ai.team)] = commands.size()
		for command in commands:
			controller.enqueue_command(command, true, int(ai.team))
			submitted.append({"team": int(ai.team), "command": command})
	controller.advance_frame(0.25, 1, 2)
	var accepted_by_team: Dictionary = {}
	var rejected: Array = []
	for entry_value in submitted:
		var entry: Dictionary = entry_value
		var command = entry["command"]
		var result: Dictionary = controller.get_command_result(int(command.sequence_id))
		if bool(result.get("accepted", false)):
			accepted_by_team[int(entry["team"])] = int(accepted_by_team.get(int(entry["team"]), 0)) + 1
		else:
			rejected.append({"team": entry["team"], "type": command.command_type(), "reason": result.get("reason")})
	for team in range(2, player_count + 1):
		assert_true(int(issued_by_team.get(team, 0)) > 0, "%s AI team %d issues an opening through legal knowledge" % [context, team])
		assert_true(int(accepted_by_team.get(team, 0)) > 0, "%s AI team %d reaches the public command pipeline (rejected=%s)" % [context, team, rejected])
	assert_true(not world.is_battle_over(), "%s remains active after the multiplayer opening tick" % context)
	print("E5-006C multiplayer matrix %s passed: commands=%d accepted_teams=%d" % [context, submitted.size(), accepted_by_team.size()])


func naval_diagnostics(map_data: Dictionary) -> Array:
	var fish: Array = map_data.get("resources", []).filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
	var result: Array = []
	for zone_value in map_data.get("naval_start_zones", []):
		var zone: Dictionary = zone_value
		var staging := Vector2(zone.get("water_staging", Vector2.ZERO))
		var nearby: Array = fish.filter(func(resource): return Vector2(resource.get("position", Vector2.ZERO)).distance_to(staging) <= 12.0)
		result.append({"team": zone.get("team"), "dock": zone.get("dock_position"), "water": staging, "nearby": nearby.map(func(resource): return resource.get("position"))})
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated 4/8-player coastal/islands matrix passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
