extends SceneTree

const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "grasslands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	var built := SkirmishSettings.build(settings)
	if not bool(built.get("valid", false)):
		push_error("Generated inland attack-access map invalid: %s" % [built.get("errors", [])])
		quit(1)
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
	var target: Dictionary = world.get_buildings().filter(func(building): return int(building.get("team", 0)) == 1 and String(building.get("kind", "")) == "town_center")[0]
	var origin: Dictionary = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 2 and String(unit.get("kind", "")) == "villager")[0]
	var center := Vector2(target["pos"])
	var near_resources: Array = world.get_resources().filter(func(resource): return Vector2(resource.get("pos", Vector2.ZERO)).distance_to(center) <= 7.0)
	var reachable := 0
	var clear := 0
	var results: Array = []
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		var slot := center + Vector2(cos(angle), sin(angle)) * 2.2
		var walkable: bool = world.navigation_grid.is_position_walkable_for(slot, 0.3, "land")
		if walkable:
			clear += 1
		var path: Array = world.pathfinder.find_path(Vector2(origin["pos"]), slot, "land", -1, 0.3) if walkable else []
		if not path.is_empty():
			reachable += 1
		results.append({"slot": slot, "walkable": walkable, "route": path.size()})
	if reachable < 4:
		print("Generated inland TC approach center=%s attacker=%s clear=%d reachable=%d resources=%s slots=%s" % [center, origin["pos"], clear, reachable, near_resources.map(func(resource): return {"kind": resource.get("kind"), "pos": resource.get("pos")}), results])
		push_error("Generated inland enemy Town Center lacks four attack approaches")
		quit(1)
		return
	print("Generated inland attack-access test passed: %d reachable approach slots" % reachable)
	quit(0)
