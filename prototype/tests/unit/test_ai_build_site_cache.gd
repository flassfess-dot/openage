extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Ai := preload("res://scripts/ai_player.gd")

class CountingWorld:
	extends "res://scripts/simulation_world.gd"
	var queries: Array = []
	func get_local_build_sites(team: int, kinds: Array, maximum: int = 4, radius: int = 12, preferred: Dictionary = {}, strict: Array = [], gap: float = 0.0) -> Dictionary:
		queries.append(kinds.duplicate())
		return super.get_local_build_sites(team, kinds, maximum, radius, preferred, strict, gap)

var failures: Array[String] = []
var catalog

func _initialize() -> void:
	catalog = Catalog.new()
	catalog.load_generated_data()
	test_negative_cache_and_terrain()
	test_mobile_affordability_and_exploration()
	test_priority_search()
	for failure in failures:
		push_error(failure)
	print("AI build-site cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func fixture():
	var world = CountingWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 1000)
	world.add_unit(1, "villager", Vector2(10.5, 10.5), false)
	for y in range(32):
		for x in range(32):
			world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	return world

func test_negative_cache_and_terrain() -> void:
	var world = fixture()
	var probe := Probe.new()
	world.set_performance_probe(probe)
	check(world.get_cached_local_build_sites(1, ["dock"], 20, 1200, 1).is_empty(), "land-only search has no dock sites")
	var initial_evaluations: int = int(probe.counters.get("ai.build_site_static_evaluations", 0))
	world.get_cached_local_build_sites(1, ["house", "dock"], 40, 1200, 1)
	check(world.queries == [["dock"], ["house"]], "changing other priorities retains the failed dock search")
	world.get_cached_local_build_sites(1, ["dock"], 60, 1200, 1)
	check(world.queries.size() == 2, "empty searches are cached")
	world.units[0]["pos"] += Vector2(0.1, 0.0)
	world.get_cached_local_build_sites(1, ["dock"], 80, 1200, 1)
	check(world.queries.size() == 3, "worker movement invalidates query results")
	check(int(probe.counters.get("ai.build_site_static_evaluations", 0)) < initial_evaluations + 40, "movement inside one cell reuses static terrain audits")
	world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 16 else "grass")
	var sites: Dictionary = world.get_cached_local_build_sites(1, ["dock"], 100, 1200, 1)
	check(not sites.get("dock", []).is_empty(), "new coast invalidates a failed search immediately")
	for site in sites.get("dock", []):
		check(world.can_place_foundation(1, "dock", Vector2(site)), "new dock sites pass authoritative placement")

func test_mobile_affordability_and_exploration() -> void:
	var world = fixture()
	var target := Vector2(18.5, 10.5)
	var preferred := {"house": [target]}
	var first: Dictionary = world.get_cached_local_build_sites(1, ["house"], 20, 1200, 1, 12, preferred, ["house"])
	check(first.get("house", []) == [target], "strict preferred site is initially usable")
	first["house"].clear()
	check(world.get_cached_local_build_sites(1, ["house"], 40, 1200, 1, 12, preferred, ["house"]).get("house", []) == [target], "published site arrays cannot corrupt cached results")
	var blocker: Dictionary = world.add_unit(2, "clubman", target, false)
	check(world.get_cached_local_build_sites(1, ["house"], 60, 1200, 1, 12, preferred, ["house"]).is_empty(), "moving unit occupancy invalidates a positive result")
	blocker["pos"] = Vector2(27.5, 27.5)
	check(not world.get_cached_local_build_sites(1, ["house"], 80, 1200, 1, 12, preferred, ["house"]).is_empty(), "vacating a site invalidates a negative result")
	world.set_resource_amount(1, 1, 0)
	check(world.get_cached_local_build_sites(1, ["house"], 100, 1200, 1, 12, preferred, ["house"]).is_empty(), "loss of affordability invalidates a positive result")
	world.set_resource_amount(1, 1, 1000)
	check(not world.get_cached_local_build_sites(1, ["house"], 120, 1200, 1, 12, preferred, ["house"]).is_empty(), "new resources immediately restore a site")
	var queries_before: int = world.queries.size()
	world.set_resource_amount(1, 0, 999)
	world.get_cached_local_build_sites(1, ["house"], 140, 1200, 1, 12, preferred, ["house"])
	check(world.queries.size() == queries_before, "unrelated stockpile changes do not discard placement work")
	world.technology_system.set_object_enabled(1, 10001, false)
	world.get_cached_local_build_sites(1, ["house"], 160, 1200, 1, 12, preferred, ["house"])
	check(world.queries.size() == queries_before + 1, "technology changes invalidate cached results")
	world.fog_of_war.reset()
	check(world.get_cached_local_build_sites(1, ["house"], 180, 1200, 1, 12, preferred, ["house"]).is_empty(), "unexplored sites cannot be exposed from a cache")
	world.fog_of_war.reveal_explored_cell(1, Vector2i(target))
	check(not world.get_cached_local_build_sites(1, ["house"], 200, 1200, 1, 12, preferred, ["house"]).is_empty(), "new exploration immediately invalidates a failed search")
	world.get_cached_local_build_sites(1, ["house"], 1401, 1200, 1, 12, preferred, ["house"])
	check(world.local_build_site_cache.size() <= world.MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES, "query retention stays bounded")

func test_priority_search() -> void:
	var world = fixture()
	var ai = Ai.new({"team": 1, "ai": {"construction_priorities": ["house", "barracks", "dock"], "building_limits": {"house": 5, "barracks": 1, "dock": 1}}})
	var options: Dictionary = ai.presentation_options()
	var workers: Array = [Snapshot.compact_ai_entity(world.units[0], 1).duplicate()]
	workers[0]["command_options"] = {"build": world.get_build_options_for_kinds(1, ["house", "barracks", "dock"])}
	var sites := Snapshot.requested_build_sites(world, 20, 1, ["house", "barracks", "dock"], options, workers, [])
	check(sites.keys() == ["house"] and world.queries == [["house"]], "first usable priority avoids preparing unused lower priorities")
	world.queries.clear()
	options["preferred_build_sites"] = {"house": [Vector2(10.5, 10.5)]}
	options["strict_preferred_build_site_kinds"] = ["house"]
	sites = Snapshot.requested_build_sites(world, 40, 1, ["house", "barracks"], options, workers, [])
	check(sites.has("barracks"), "failed high-priority placement still tries the next useful kind")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
