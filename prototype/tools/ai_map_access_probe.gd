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
	var Navigation=load("res://scripts/random_map_navigation.gd")
	for include_resources in [false,true]:
		var field: Dictionary=Navigation.flood(world.map_size,Navigation.mask(built["map_data"],built["definition"],include_resources),Vector2i(origin["pos"]))
		var target_index:=0
		for index in range(16):
			var point:=center+Vector2.from_angle(TAU*index/16.0)*2.2
			var cell:=Vector2i(point)
			if int(field["distances"][cell.y*world.map_size.x+cell.x])>=0: target_index+=1
		print("ACCESS_DIAGNOSTIC resources=",include_resources," terrain_component_access=",target_index," generator=",built["definition"]["map"].get("generator",{}).get("algorithm","")," topology=",built["map_data"].get("generation_revision",-1))
	world.pathfinder.set_native_enabled(false)
	print("REFERENCE_APPROACH ",world.pathfinder.find_path(Vector2(origin["pos"]),center+Vector2(0,2.2),"land",-1,0.3))
	quit(0)
