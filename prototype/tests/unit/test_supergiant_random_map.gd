extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var sizes: Array = SkirmishSettings.catalog().get("map_sizes", [])
	var giant: Dictionary = sizes.filter(func(entry): return String(entry.get("id", "")) == "giant")[0]
	var supergiant: Dictionary = sizes.filter(func(entry): return String(entry.get("id", "")) == "supergiant")[0]
	var old_side := int(giant["size"][0])
	var new_side := int(supergiant["size"][0])
	assert_equal(new_side, old_side * 2, "new map doubles each side of the previous maximum")
	assert_equal(new_side * new_side, 4 * old_side * old_side, "new map has four times the playable area")
	assert_equal(int(supergiant.get("max_players", 0)), 8, "new size retains eight-player capacity")
	for map_type in ["grasslands", "coastal"]:
		var settings := SkirmishSettings.default_settings()
		settings["map_size_id"] = "supergiant"
		settings["map_type_id"] = map_type
		settings["seed"] = 41721
		if map_type == "grasslands":
			for index in range(settings["players"].size()):
				settings["players"][index]["enabled"] = true
				settings["players"][index]["controller"] = "human" if index == 0 else "ai"
		var result := SkirmishSettings.build(settings)
		assert_true(bool(result.get("valid", false)), "%s supergiant map passes all generator quality gates: %s" % [map_type, result.get("errors", [])])
		if bool(result.get("valid", false)):
			assert_equal(result["map_data"]["size"], Vector2i(400, 400), "%s reaches the full 400x400 terrain" % map_type)
			assert_equal(result["definition"]["map"]["size"], Vector2i(400, 400), "%s reaches the playable match" % map_type)
			if map_type == "grasslands":
				var catalog := ResourceCatalog.new()
				catalog.load()
				var world := SimulationWorld.new(result["map_data"]["size"])
				world.set_gamespec(catalog.gamespec_data)
				world.set_terrain_catalog(catalog.terrain_catalog_data)
				world.set_object_catalog(catalog.object_catalog_data)
				world.set_graphics_catalog(catalog.graphics_catalog_data)
				world.set_runtime_catalog(catalog.runtime_catalog_data)
				MatchBootstrap.apply(world, result["definition"], result["map_data"])
				assert_equal(world.get_buildings().size(), 8, "all eight starting towns load into the simulation")
				assert_equal(world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "villager").size(), 24, "all eight worker groups load into the simulation")
				assert_equal(world.get_resources().size(), result["map_data"].get("resources", []).filter(func(entity): return String(entity.get("category", "")) == "resource").size(), "generated resource nodes survive runtime bootstrap")
	if failures.is_empty():
		print("Supergiant random map tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
