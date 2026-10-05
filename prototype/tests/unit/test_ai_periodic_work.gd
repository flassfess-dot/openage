extends SceneTree

const Ai := preload("res://scripts/ai_player.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Planner := preload("res://scripts/ai_economic_planner.gd")

class CountingWorld:
	extends "res://scripts/simulation_world.gd"
	var builder_queries := 0
	var train_queries := 0
	var research_queries := 0
	func reachable_builder_ids(building: Dictionary) -> Array[int]:
		builder_queries += 1
		return super.reachable_builder_ids(building)
	func get_unit_production_options(building_id: int, team: int) -> Array:
		train_queries += 1
		return super.get_unit_production_options(building_id, team)
	func get_research_options(building_id: int, team: int) -> Array:
		research_queries += 1
		return super.get_research_options(building_id, team)

var failures: Array[String] = []
var catalog

func _initialize() -> void:
	test_phases_and_restore()
	catalog = Catalog.new()
	catalog.load_generated_data()
	test_foundation_observations()
	test_production_projection()
	for failure in failures:
		push_error(failure)
	print("AI periodic work: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func make_ai(team: int):
	return Ai.new({"team": team, "ai": {"economic_interval_ticks": 20, "military_interval_ticks": 20}})

func test_phases_and_restore() -> void:
	var first = make_ai(2)
	var second = make_ai(3)
	var disabled = make_ai(4)
	disabled.enabled = false
	check(Ai.initial_decision_tick(first, [second, disabled, first]) == 2, "first AI preserves its old startup phase")
	check(Ai.initial_decision_tick(second, [second, disabled, first]) == 12, "two AIs are separated by half their decision interval")
	check(Ai.initial_decision_tick(first, [first]) == 2, "a single AI keeps its startup behavior")
	var counts := {2: 0, 3: 0}
	for tick in range(1, 101):
		var decisions := 0
		for player in [first, second]:
			if tick >= Ai.initial_decision_tick(player, [first, second]) and player.needs_decision(tick):
				player.collect_commands({"observer_team": player.team, "units": [], "buildings": [], "resources": [], "navigation": {}, "player_state": {}}, tick)
				counts[player.team] += 1
				decisions += 1
		check(decisions <= 1, "periodic AI decisions never collide at tick %d" % tick)
	check(counts == {2: 5, 3: 5}, "spreading phases preserves the number of decisions")
	var restored = make_ai(3)
	check(restored.restore_state(second.canonical_state()), "AI schedule state restores")
	for tick in range(101, 151):
		check(restored.needs_decision(tick) == second.needs_decision(tick), "restored decision deadline is unchanged")
	var peers: Array = []
	for team in range(1, 9):
		peers.append(make_ai(team))
	var phases: Dictionary = {}
	for player in peers:
		phases[Ai.initial_decision_tick(player, peers)] = true
	check(phases.size() == 8, "eight AI players have distinct stable phases")

func fixture():
	var world = CountingWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource_type in range(4):
		world.set_resource_amount(2, resource_type, 1000)
	return world

func test_foundation_observations() -> void:
	for retained in [false, true]:
		var world = fixture()
		var worker: Dictionary = world.add_unit(2, "villager", Vector2(6.5, 6.5), false)
		var foundation: Dictionary = world.add_building(500, "house", Vector2(12.5, 12.5), 2)
		foundation["state"] = "foundation"
		foundation["builders"] = {}
		worker["task"] = "build"
		worker["target_building_id"] = 500
		var options: Dictionary = make_ai(2).presentation_options()
		options["include_navigation"] = false
		var store := Store.new()
		var snapshot: Dictionary = store.observe_with_queries(world, 20, 2, options) if retained else Snapshot.with_queries(world, 20, 2, options)
		check(world.builder_queries == 0, "assigned but walking builder needs no reachability search (retained=%s)" % retained)
		check(not snapshot["buildings"][0].has("reachable_builder_ids"), "assigned foundation has no redundant builder list")
		check(world.train_queries == 0 and world.research_queries == 0, "foundation never projects unusable production choices")
		worker["task"] = "idle"
		worker["target_building_id"] = -1
		snapshot = store.observe_with_queries(world, 40, 2, options) if retained else Snapshot.with_queries(world, 40, 2, options)
		check(world.builder_queries == 1 and int(worker["id"]) in snapshot["buildings"][0].get("reachable_builder_ids", []), "abandoned foundation still receives reachable builders")
		foundation["builders"][int(worker["id"])] = true
		snapshot = store.observe_with_queries(world, 60, 2, options) if retained else Snapshot.with_queries(world, 60, 2, options)
		check(world.builder_queries == 1 and not snapshot["buildings"][0].has("reachable_builder_ids"), "active foundation clears the previous recovery projection")

func test_production_projection() -> void:
	var world = fixture()
	var building: Dictionary = world.add_building(600, "town_center", Vector2(10.5, 10.5), 2)
	building["production_queue"] = [{"kind": "villager", "order_type": "unit", "status": "working"}]
	var full := {"train": world.get_unit_production_options(600, 2), "research": world.get_research_options(600, 2)}
	world.train_queries = 0
	world.research_queries = 0
	var reduced := Snapshot.economic_production_options(world, building, 2)
	check(world.train_queries == 0 and world.research_queries == 0 and reduced["train"].size() == 1, "one queued unit evaluates only that kind")
	var base := {"observer_team": 2, "units": [], "resources": [], "navigation": {}, "build_sites": {}, "player_state": {"age": 100}}
	var projected: Dictionary = building.duplicate(true)
	projected["command_options"] = full
	base["buildings"] = [projected]
	var expected := command_records(Planner.plan(base, 30, 2))
	projected["command_options"] = reduced
	check(command_records(Planner.plan(base, 30, 2)) == expected, "reduced production choices preserve planner commands")
	building["production_queue"].append({"kind": "villager", "order_type": "unit"})
	check(Snapshot.economic_production_options(world, building, 2) == {"train": [], "research": []}, "two queued orders require no unused production options")
	building["production_queue"] = [{"order_type": "research"}]
	check(Snapshot.economic_production_options(world, building, 2) == {"train": [], "research": []}, "active research requires no unused production options")

func command_records(commands: Array) -> Array:
	var result: Array = []
	for command in commands:
		result.append([command.command_type(), command.unit_ids, command.params])
	return result

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
