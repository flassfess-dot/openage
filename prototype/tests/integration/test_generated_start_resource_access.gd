extends SceneTree

const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const CASES := [
	{"map_type_id": "coastal", "map_size_id": "standard", "players": 4, "seed": 41721},
	{"map_type_id": "grasslands", "map_size_id": "standard", "players": 4, "seed": 7919},
	{"map_type_id": "highlands", "map_size_id": "standard", "players": 4, "seed": 7919},
	{"map_type_id": "mediterranean", "map_size_id": "standard", "players": 4, "seed": 7919},
	{"map_type_id": "islands", "map_size_id": "large", "players": 8, "seed": 41721},
	{"map_type_id": "continental", "map_size_id": "large", "players": 8, "seed": 7919},
]

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	for map_type_value in SkirmishSettings.catalog().get("map_types", []):
		var map_type: Dictionary = map_type_value
		for seed in [41721, 7919]:
			verify_case({"map_type_id": String(map_type.get("id", "")), "map_size_id": "compact", "players": 2, "seed": seed}, catalog)
	for case_value in CASES:
		verify_case(case_value, catalog)
	if failures.is_empty():
		print("Generated start resource access tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_case(case_value: Dictionary, catalog) -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = String(case_value["map_type_id"])
	settings["map_size_id"] = String(case_value["map_size_id"])
	settings["seed"] = int(case_value["seed"])
	settings["resource_preset_id"] = "very_high"
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < int(case_value["players"])
	var built := SkirmishSettings.build(settings)
	var context := "%s %dp seed %d" % [case_value["map_type_id"], case_value["players"], case_value["seed"]]
	if not bool(built.get("valid", false)):
		failures.append("%s does not build: %s" % [context, built.get("errors", [])])
		return
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, built["definition"], built["map_data"])
	for player_value in built["definition"]["players"]:
		var player: Dictionary = player_value
		var team := int(player["team"])
		var start := Vector2(player["start"])
		var workers: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == team and String(unit.get("kind", "")) == "villager")
		if workers.is_empty():
			failures.append("%s team %d has no starting worker" % [context, team])
			continue
		var worker: Dictionary = workers[0]
		for kind in ["berries", "tree", "gold_mine", "stone_mine"]:
			var candidates: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == kind and int(resource.get("amount", 0)) > 0 and Vector2(resource.get("pos", Vector2.ZERO)).distance_to(start) <= 20.0)
			var reachable := false
			for resource_value in candidates:
				var resource: Dictionary = resource_value
				for slot in world.resource_approach_candidates(worker, resource):
					if not world.navigation_grid.is_position_walkable_for(slot, float(worker.get("footprint_radius", 0.3)), "land", int(worker.get("terrain_restriction", -1))):
						continue
					if not world.pathfinder.find_path(Vector2(worker["pos"]), slot, "land", int(worker.get("terrain_restriction", -1)), float(worker.get("footprint_radius", 0.3))).is_empty():
						reachable = true
						break
				if reachable:
					break
			if not reachable:
				failures.append("%s team %d cannot reach nearby %s (objects=%d)" % [context, team, kind, candidates.size()])
