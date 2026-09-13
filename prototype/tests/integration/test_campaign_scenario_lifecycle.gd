extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	var first := run_campaign_goal(catalog)
	var second := run_campaign_goal(catalog)
	assert_equal(first.get("hash"), second.get("hash"), "campaign scenario progress is replay-deterministic")
	assert_equal(first.get("winner_team"), 1, "all twelve source areas give victory to the Roman player")
	assert_equal(first.get("condition_events"), 12, "each source condition emits one authoritative completion event")
	assert_equal(first.get("group_events"), 1, "the source victory group emits one completion event")
	assert_equal(first.get("scenario_events"), 1, "scenario lifecycle emits one completion event")
	assert_equal(first.get("match_events"), 1, "generic match lifecycle emits one completion event")
	assert_equal(first.get("snapshot_conditions"), 18, "canonical snapshot owns all Roman and opponent condition states")
	assert_true(not bool(first.get("presentation_active", true)), "presentation snapshot exposes completed scenario state")
	if failures.is_empty():
		print("I12-020C campaign scenario lifecycle and replay tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func run_campaign_goal(catalog) -> Dictionary:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var scenario_definition: Dictionary = definition.get("scenario_definition", {}).duplicate(true)
	var roman: Dictionary = scenario_definition.get("participants", [])[0]
	var conditions: Array = roman.get("groups", [])[0].get("conditions", [])
	for index in range(conditions.size()):
		conditions[index]["area"] = [2.0 + index * 2.0, 2.0, 3.0 + index * 2.0, 3.0]
	var world := SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.configure_players(definition.get("players", []))
	world.reset_game(false)
	world.configure_scenario_definition(scenario_definition)
	world.configure_victory_rules([{"type": "scenario_definition"}])
	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		world.add_unit(int(player.get("team", 0)), "clubman", Vector2(10.0 + int(player.get("team", 0)), 20.0), false)

	world.begin_event_capture()
	world.check_battle_state(1, 2, 0.05)
	for index in range(conditions.size()):
		var condition: Dictionary = conditions[index]
		var area: Array = condition.get("area", [])
		var position := Vector2((float(area[0]) + float(area[2])) * 0.5, (float(area[1]) + float(area[3])) * 0.5)
		var tower: Dictionary = world.add_building(9000 + index, "tower", position, 1, true)
		world.apply_unit_upgrade_to_entity(tower, 199)
		world.check_battle_state(1, 2, 0.05)
		if index + 1 < conditions.size():
			assert_true(not world.is_battle_over(), "mission remains active until every source area is satisfied")
	world.end_event_capture()

	var events: Array = world.drain_domain_events()
	var canonical: Dictionary = SimulationSnapshot.canonical(world, 12)
	var presentation: Dictionary = SimulationSnapshot.presentation(world, 12, 1)
	var replay := ReplaySystem.new()
	return {
		"hash": replay.world_state_hash(world, 12),
		"winner_team": int(world.get_victory_result().get("winner_team", -1)),
		"condition_events": events.filter(func(event): return String(event.get("type", "")) == "scenario_condition_changed" and bool(event.get("payload", {}).get("achieved", false))).size(),
		"group_events": events.filter(func(event): return String(event.get("type", "")) == "scenario_group_changed" and bool(event.get("payload", {}).get("achieved", false))).size(),
		"scenario_events": events.filter(func(event): return String(event.get("type", "")) == "scenario_completed").size(),
		"match_events": events.filter(func(event): return String(event.get("type", "")) == "match_completed").size(),
		"snapshot_conditions": canonical.get("world", {}).get("victory", {}).get("scenario", {}).get("condition_states", {}).size(),
		"presentation_active": presentation.get("scenario", {}).get("active", true),
	}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
