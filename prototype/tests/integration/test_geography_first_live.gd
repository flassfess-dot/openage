extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for fixture in [["islands", "large", 7919, 8], ["highlands", "standard", 41721, 4], ["coastal", "standard", 104729, 4], ["islands", "compact", 41721, 2]]:
		var settings := Settings.default_settings()
		settings["landscape_version"] = 4
		settings["map_type_id"] = fixture[0]
		settings["map_size_id"] = fixture[1]
		settings["seed"] = fixture[2]
		for i in range(8): settings["players"][i]["enabled"] = i < int(fixture[3])
		var built := Settings.build(settings)
		check(bool(built.get("valid", false)), "%s builds: %s" % [fixture, built.get("errors", [])])
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		var size: Vector2i = data["size"]
		var world = World.new(size)
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		Bootstrap.apply(world, built["definition"], data)
		var mask := Navigation.mask(data, built["definition"])
		for y in range(size.y):
			for x in range(size.x):
				check((mask[y * size.x + x] != 0) == world.navigation_grid.is_walkable(Vector2i(x, y)), "%s generation and live occupancy agree" % [fixture])
		for player in built["definition"]["players"]:
			var team := int(player["team"])
			var workers: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == team and unit.get("kind", "") == "villager")
			check(not workers.is_empty(), "starting workers exist")
			if workers.is_empty(): continue
			var worker: Dictionary = workers[0]
			for kind in ["tree", "berries", "gold_mine", "stone_mine"]:
				var reachable := false
				for resource in world.get_resources():
					if resource.get("kind", "") != kind or Vector2(resource["pos"]).distance_to(player["start"]) > 20.0: continue
					for approach in world.resource_approach_candidates(worker, resource):
						if not world.navigation_grid.is_position_walkable_for(approach, float(worker.get("footprint_radius", 0.3)), "land", int(worker.get("terrain_restriction", -1))): continue
						if not world.pathfinder.find_path(worker["pos"], approach, "land", int(worker.get("terrain_restriction", -1)), float(worker.get("footprint_radius", 0.3))).is_empty():
							reachable = true
							break
					if reachable: break
				check(reachable, "%s player %d can gather %s through live pathfinding" % [fixture, team, kind])
			for zone in data.get("naval_start_zones", []):
				if int(zone["team"]) != team: continue
				var path: Variant = world.pathfinder.find_path(worker["pos"], zone["land_staging"], "land", int(worker.get("terrain_restriction", -1)), float(worker.get("footprint_radius", 0.3)))
				check(not path.is_empty(), "%s player %d reaches the dock staging point" % [fixture, team])
		world.task_coordinator.shutdown()
		print("Live geography access checked: %s" % [fixture])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Geography-first live navigation and gather access passed")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
