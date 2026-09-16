extends SceneTree

const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "standard"
	for index in range(8):
		settings["players"][index]["enabled"] = index < 4
		settings["players"][index]["controller"] = "human" if index == 0 else "ai"
		settings["players"][index]["alliance_id"] = 1 if index < 2 else 2
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "four-player allied skirmish builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, built["definition"], built["map_data"])
	assert_true(world.are_teams_allied(1, 2) and world.are_teams_allied(2, 1), "first generated alliance is mutual")
	assert_true(world.are_teams_allied(3, 4) and world.are_teams_allied(4, 3), "second generated alliance is mutual")
	assert_true(not world.are_teams_allied(1, 3), "opposing generated alliances remain enemies")

	for category in [world.get_units(), world.get_buildings()]:
		for entity_value in category:
			var entity: Dictionary = entity_value
			if int(entity.get("team", 0)) in [3, 4]:
				entity["hp"] = 0.0
	world.begin_event_capture()
	world.check_battle_state(2, 3)
	world.end_event_capture()
	var result: Dictionary = world.get_victory_result()
	assert_equal(result.get("winner_team"), 1, "lowest stable ally remains the compatibility winner")
	assert_equal(result.get("winner_teams"), [1, 2], "both surviving generated allies win conquest")
	assert_equal(result.get("loser_teams"), [3, 4], "both eliminated opponents lose conquest")
	assert_equal(world.player_registry.status(1), "victorious", "human ally receives victorious state")
	assert_equal(world.player_registry.status(2), "victorious", "AI ally receives victorious state")
	assert_true(world.get_last_battle_message().begins_with("ПОБЕДА"), "local allied observer receives victory feedback")
	var completion_events := world.drain_domain_events().filter(func(event): return String(event.get("type", "")) == "match_completed")
	assert_equal(completion_events.size(), 1, "allied conquest emits one terminal event")
	if not completion_events.is_empty():
		assert_equal(completion_events[0].get("payload", {}).get("winner_teams"), [1, 2], "terminal event preserves the full winning side")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated alliance victory pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
