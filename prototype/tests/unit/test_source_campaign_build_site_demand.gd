extends SceneTree

const Ai := preload("res://scripts/ai_player.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")
const CityPlan := preload("res://scripts/source_ai_city_plan.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Observations := preload("res://scripts/ai_observation_store.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")

class CountingWorld:
	extends "res://scripts/simulation_world.gd"
	var queries: Array = []
	func get_cached_local_build_sites(team: int, kinds: Array, tick: int, age: int, maximum: int = 4, radius: int = 12, preferred: Dictionary = {}, strict: Array = [], gap: float = 0.0) -> Dictionary:
		queries.append(kinds.duplicate())
		return super.get_cached_local_build_sites(team, kinds, tick, age, maximum, radius, preferred, strict, gap)

var failures: Array[String] = []

func _initialize() -> void:
	var base := fixture()
	var contract := {"build_order": [entry("building", "barracks", 12, 1), entry("building", "dock", 45, 1)]}
	verify(base, contract, ["barracks"], "ample housing, first unmet building")
	var changed: Dictionary = base.duplicate(true)
	changed["player_state"]["population_points"] = 14
	verify(changed, contract, ["house", "barracks"], "housing has independent priority")
	changed["build_sites"]["house"] = []
	verify(changed, contract, ["house", "barracks"], "failed housing still permits current build order")
	changed = base.duplicate(true)
	changed["player_state"]["population_points"] = 12
	changed["player_state"]["population_reserved"] = 1
	verify(changed, contract, ["house", "barracks"], "reserved production consumes population")
	changed["player_state"]["population_points"] = 11
	verify(changed, contract, ["barracks"], "half population point below housing threshold")
	changed = base.duplicate(true)
	changed["buildings"][0]["production_queue"] = [{"kind": "villager", "status": "blocked_population"}]
	verify(changed, contract, ["house", "barracks"], "blocked production requires housing")
	changed["player_state"]["population_cap"] = 50
	verify(changed, contract, ["barracks"], "population ceiling suppresses housing")
	changed["player_state"]["population_cap"] = 0
	verify(changed, contract, ["barracks"], "zero population cap")
	changed = base.duplicate(true)
	changed["units"][0]["command_options"]["build"][1]["accepted"] = false
	verify(changed, contract, [], "unavailable first building blocks later buildings")
	changed["units"][0]["command_options"]["build"][1]["accepted"] = true
	changed["units"][0]["command_options"]["build"][0]["accepted"] = false
	changed["player_state"]["population_points"] = 14
	verify(changed, contract, ["barracks"], "unavailable housing does not block build order")
	changed = base.duplicate(true)
	changed["build_sites"]["barracks"] = []
	verify(changed, contract, ["barracks"], "unplaceable first building never advances the order")
	changed = base.duplicate(true)
	changed["buildings"].append(building("barracks", 12, "foundation"))
	verify(changed, contract, ["dock"], "foundation satisfies its target count")
	changed["buildings"][1]["hp"] = 0.0
	verify(changed, contract, ["barracks"], "destroyed foundation restores demand")
	changed["buildings"][1]["hp"] = 100.0
	changed["buildings"][1]["team"] = 3
	verify(changed, contract, ["barracks"], "enemy building cannot satisfy own order")
	changed["buildings"][1]["team"] = 2
	changed["buildings"][1]["kind"] = "upgraded_barracks"
	changed["buildings"][1]["source_unit_id"] = 999
	changed["buildings"][1]["unit_lineage"] = [12]
	verify(changed, contract, ["dock"], "source lineage satisfies an upgraded building")
	for task in ["gather", "build", "repair", "move"]:
		changed = base.duplicate(true)
		changed["units"][0]["task"] = task
		verify(changed, contract, [], "busy builder: " + task)
	changed = base.duplicate(true)
	changed["units"][0]["movement_domain"] = "water"
	verify(changed, contract, [], "water worker cannot construct")
	changed = base.duplicate(true)
	changed["units"][0]["hp"] = 0.0
	verify(changed, contract, [], "dead builder cannot construct")
	changed["units"][0]["hp"] = 25.0
	changed["units"][0]["team"] = 3
	verify(changed, contract, [], "enemy builder cannot construct")

	var opening := {"build_order": [entry("unit", "villager", 83, 2), entry("building", "barracks", 12, 1)]}
	verify(base, opening, [], "unfinished unit order blocks later buildings")
	changed = base.duplicate(true)
	changed["buildings"][0]["production_queue"] = [{"kind": "villager", "status": "queued"}]
	verify(changed, opening, ["barracks"], "queued unit satisfies opening target")
	changed["units"][0]["hp"] = 0.0
	verify(changed, opening, [], "no surviving builder")
	changed = base.duplicate(true)
	changed["player_state"]["population_points"] = 14
	verify(changed, opening, ["house"], "housing can precede unfinished production")
	var research := {"build_order": [entry("technology", "", 101, 1), entry("building", "barracks", 12, 1)]}
	verify(base, research, [], "unfinished research blocks later buildings")
	changed = base.duplicate(true)
	changed["player_state"]["researched_technologies"] = [101]
	verify(changed, research, ["barracks"], "completed research unlocks next building")
	verify(base, {"build_order": [entry("building", "barracks", 12, 0), entry("building", "dock", 45, 1)]}, ["dock"], "zero target is already satisfied")
	verify(base, {"build_order": [entry("unknown", "", -1, 1), entry("building", "barracks", 12, 1)]}, ["barracks"], "unknown source entry is skipped")
	verify(base, {"build_order": [entry("building", "house", 70, 1)]}, ["house"], "explicit house order works without population demand")

	changed = base.duplicate(true)
	changed["units"][0]["pos"] = Vector2(20.5, 20.5)
	var geometry := {"build_order": [entry("building", "wall", 72, 1)], "strategic_numbers": [{"source_id": 73, "value": 3}, {"source_id": 74, "value": 5}, {"source_id": 84, "value": 2}, {"source_id": 85, "value": 2}]}
	var city := CityPlan.new(2)
	city.synchronize(changed, changed["units"], changed["buildings"], Planner.strategic_number_values(geometry))
	changed["build_sites"]["wall"] = city.preferred_wall_sites()
	verify(changed, geometry, ["wall"], "planned walls preserve geometry and gates", city)
	changed = base.duplicate(true)
	changed["build_sites"]["storage_pit"] = [Vector2(40, 40), Vector2(15, 10)]
	verify(changed, {"build_order": [entry("building", "storage_pit", 103, 1)], "strategic_numbers": [{"source_id": 86, "value": 15}]}, ["storage_pit"], "source drop-site distance still chooses the same site")
	test_observation_requests()
	for failure in failures:
		push_error(failure)
	print("Source campaign construction demand: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func entry(type: String, alias: String, source_id: int, target: int) -> Dictionary:
	return {"type": type, "runtime_alias": alias, "source_id": source_id, "target_count": target, "producer_source_unit_id": 109}

func building(kind: String, source_id: int, state: String = "complete") -> Dictionary:
	return {"id": 100 + source_id, "team": 2, "kind": kind, "source_unit_id": source_id, "unit_lineage": [source_id], "hp": 100.0, "pos": Vector2(10.5, 10.5), "state": state, "production_queue": [], "command_options": {"train": [{"kind": "villager", "accepted": true}], "research": [{"technology_id": 101, "accepted": true}]}}

func fixture() -> Dictionary:
	var kinds := ["house", "barracks", "dock", "wall", "storage_pit", "granary"]
	var sites: Dictionary = {}
	var options: Array = []
	for index in range(kinds.size()):
		options.append({"kind": kinds[index], "accepted": true})
		sites[kinds[index]] = [Vector2(20.5 + index, 12.5), Vector2(18.5 + index, 14.5)]
	return {"observer_team": 2, "map_size": Vector2i(64, 64), "units": [{"id": 1, "team": 2, "kind": "villager", "source_unit_id": 83, "unit_lineage": [83], "hp": 25.0, "pos": Vector2(4.5, 4.5), "task": "idle", "movement_domain": "land", "components": {"worker": {"enabled": true}}, "command_options": {"build": options}}], "buildings": [building("town_center", 109)], "resources": [{"id": 9, "pos": Vector2(5.5, 4.5), "amount": 100, "resource_type": "wood", "movement_domain": "land"}], "build_sites": sites, "player_state": {"team": 2, "population": 3, "population_points": 6, "population_reserved": 0, "population_cap": 8, "population_limit": 50, "researched_technologies": []}}

func verify(snapshot: Dictionary, contract: Dictionary, expected: Array, label: String, city = null) -> void:
	var ai := Ai.new({"team": 2, "source_ai": contract, "ai": {"profile": "source_campaign_v1"}})
	var filter: Callable = ai.presentation_options().get("build_site_filter", Callable())
	check(filter.is_valid(), label + ": source observation has demand filter")
	if not filter.is_valid():
		return
	var kinds: Array = filter.call(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"])
	check(kinds == expected, label + ": selects only useful kinds, got %s" % str(kinds))
	var filtered: Dictionary = snapshot.duplicate(true)
	for kind in filtered["build_sites"].keys():
		if kind not in kinds:
			filtered["build_sites"].erase(kind)
	var before_city = CityPlan.from_state(city.canonical_state()) if city != null else null
	var after_city = CityPlan.from_state(city.canonical_state()) if city != null else null
	var baseline := commands(Planner.plan_economy(snapshot, 40, 2, contract, before_city))
	var actual := commands(Planner.plan_economy(filtered, 40, 2, contract, after_city))
	check(actual == baseline, label + ": commands, targets and order are identical")
	if city != null:
		check(before_city.canonical_state() == after_city.canonical_state(), label + ": persistent geometry stays identical")

func test_observation_requests() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world := CountingWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource_type in range(4):
		world.set_resource_amount(2, resource_type, 2000)
	world.add_building(100, "town_center", Vector2(23.5, 23.5), 2)
	world.add_building(101, "house", Vector2(23.5, 14.5), 2)
	for index in range(4):
		world.add_unit(2, "villager", Vector2(10.5 + index, 10.5), false)
	world.update_fog_of_war()
	var contract := {"build_order": [entry("unit", "villager", 83, 10), entry("building", "barracks", 12, 1)]}
	var ai := Ai.new({"team": 2, "source_ai": contract, "ai": {"profile": "source_campaign_v1"}})
	var store := Observations.new()
	for tick in [0, 40, 80]:
		Snapshot.with_queries(world, tick, 2, ai.presentation_options())
		store.observe_with_queries(world, tick, 2, ai.presentation_options())
	check(world.queries.is_empty(), "both snapshot paths skip all repeated unused placement requests: %s" % str(world.queries))
	ai.source_contract["build_order"][0]["target_count"] = 4
	var observed := store.observe_with_queries(world, 120, 2, ai.presentation_options())
	check(world.queries == [["barracks"]], "satisfied opening requests exactly the next building: %s" % str(world.queries))
	check(not observed.get("build_sites", {}).get("barracks", []).is_empty(), "demanded building still gets authoritative legal sites")
	world.queries.clear()
	for unit in world.units:
		unit["task"] = "gather"
	store.observe_with_queries(world, 160, 2, ai.presentation_options())
	check(world.queries.is_empty(), "busy workers do not start a placement search")
	world.task_coordinator.shutdown()

func commands(values: Array) -> Array:
	var result: Array = []
	for command in values:
		result.append({"type": command.command_type(), "units": command.unit_ids.duplicate(), "params": command.params.duplicate(true), "tick": command.tick})
	return result

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
