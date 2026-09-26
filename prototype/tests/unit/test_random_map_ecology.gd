extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "islands"
	settings["map_size_id"] = "compact"
	settings["seed"] = 41721
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < 2
	var built := SkirmishSettings.build(settings)
	if not bool(built.get("valid", false)):
		push_error("Ecology fixture did not build: %s" % [built.get("errors", [])])
		quit(1)
		return
	var map_data: Dictionary = built["map_data"]
	var size: Vector2i = map_data["size"]
	var terrain_ids: Array = map_data["terrain_ids"]
	var resources: Array = map_data["resources"]
	var trees: Array = resources.filter(func(resource): return String(resource.get("kind", "")) == "tree")
	var palms: Array = trees.filter(func(resource): return int(resource.get("source_unit_id", -1)) in RandomMapGenerator.PALM_TREES)
	var deep_fish: Array = resources.filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
	var close_tree_pairs := 0
	var occupied_tree_cells: Dictionary = {}
	for tree in trees:
		var cell := Vector2i(Vector2(tree["position"]))
		if occupied_tree_cells.has(cell + Vector2i.LEFT) or occupied_tree_cells.has(cell + Vector2i.UP):
			close_tree_pairs += 1
		occupied_tree_cells[cell] = true
	var valid := trees.size() >= 30 and close_tree_pairs > 0 and palms.size() > 0 and deep_fish.size() > 6
	for palm in palms:
		var cell := Vector2i(Vector2(palm["position"]))
		valid = valid and int(terrain_ids[cell.y * size.x + cell.x]) in [6, 13, 20]
	for fish in deep_fish:
		var cell := Vector2i(Vector2(fish["position"]))
		valid = valid and int(terrain_ids[cell.y * size.x + cell.x]) in TerrainRules.OPEN_WATER_TERRAIN_IDS
	if not valid:
		push_error("Generated ecology lacks dense biome-matched woods or open-water fish: trees=%d close_pairs=%d palms=%d deep_fish=%d" % [trees.size(), close_tree_pairs, palms.size(), deep_fish.size()])
		quit(1)
		return
	print("Generated dense forest, palm biome and fish-school tests passed")
	quit(0)
