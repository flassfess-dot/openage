extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Quality := preload("res://scripts/random_map_quality.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "huge"
	settings["map_type_id"] = "highlands"
	var catalog = Catalog.new()
	catalog.load()
	for seed_value in [41721, 41689, 918273]:
		settings["seed"] = seed_value
		var built := Settings.build(settings)
		check(built.get("valid", false), "raised highlands remain valid: %s" % [built.get("errors", [])])
		if not built.get("valid", false): continue
		var map_data: Dictionary = built["map_data"]
		var size: Vector2i = map_data["size"]
		check(map_data["vertex_levels"].max() >= 4, "highlands contain genuinely high hills, seed %d" % seed_value)
		var cliffs: Array = map_data.get("cliff_obstructions", [])
		check(not cliffs.is_empty(), "brown native cliff strips appear in highlands")
		for item in cliffs:
			var info: Dictionary = catalog.environment_frame_info(item)
			check(info.get("texture") != null and info["texture"].get_width() > 100, "cliff uses a real populated original frame, not a blank direction")
			var center := Vector2i(item["position"])
			for dy in range(-1, 2):
				for dx in range(-1, 2): check(map_data["cliff_cells"].has(center + Vector2i(dx, dy)), "cliff's complete native footprint blocks navigation")
		for y in range(size.y):
			for x in range(size.x): check(Quality._valid_cell_gradient(Vector2i(x, y), size, map_data["vertex_levels"]), "all highland slopes remain renderable")
		check(Navigation.inspect(built["definition"], map_data)["valid"], "cliff chains preserve routes to starting economy")
		var regenerated := Settings.build(settings)
		check(regenerated.get("map_data", {}).get("content_hash") == map_data["content_hash"], "relief and cliffs remain deterministic")
	for failure in failures: push_error(failure)
	print("High relief and native cliff generation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
