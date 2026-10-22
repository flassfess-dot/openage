extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog = Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "mixed pack is installed")
	var specs: Dictionary = {}
	for spec in Decorations.palette(): specs[spec["key"]] = spec
	var seen: Dictionary = {}
	var rows: Array = []
	for profile in Settings.catalog()["map_types"]:
		for seed_value in [41689, 7919]:
			var settings := Settings.default_settings()
			settings["map_type_id"] = profile["id"]
			settings["seed"] = seed_value
			for i in range(8): settings["players"][i]["enabled"] = i < 4
			var built := Settings.build(settings)
			var label := "%s/%d" % [profile["id"], seed_value]
			check(built.get("valid", false), label + ": gameplay quality " + str(built.get("errors",[])))
			if not built.get("valid", false): continue
			var data: Dictionary = built["map_data"]
			var starts: Array[Vector2] = []
			for player in built["definition"]["players"]: starts.append(Vector2(player["start"]))
			# Habitat checks need the actual version's selected fields, not a
			# fresh v2 climate sampled over the already painted v6 terrain.
			var candidate := Generator._landscape_candidate_map(built["definition"], data["size"], seed_value, built["definition"]["map"]["generator"], Callable(), {})
			var fields: Dictionary = candidate["_fields"]
			var ctx := Decorations.context(data, fields, candidate["_reserved"], Generator._starting_entity_exclusion_cells(built["definition"], data["size"]))
			var water_ctx := Decorations.context(data, fields, {}, Generator._starting_entity_exclusion_cells(built["definition"], data["size"]))
			var ids: Dictionary = {}
			for item in data["scenery"]:
				var excluded_road: bool = item["decoration_key"] in ["ror_stone_dirt_trail", "ror_stone_grass_trail", "overgrown_trail"]
				check(not excluded_road, label + ": no paving or dark overgrown roads")
				if excluded_road: continue
				if item.get("waterfall_detail",false) or item.get("shoreline_detail",false):
					check(not catalog.environment_frame_info(item).is_empty(),label+": mandatory geographic feature resolves native art")
					continue
				if item["decoration_key"] == "ror_river_islets":
					check(not catalog.environment_frame_info(item).is_empty() and not item.has("occupied_cells"),label+": native sand bands resolve without navigation obstacles")
					continue
				var spec: Dictionary = specs[item["decoration_key"]]
				check(not ids.has(item["id"]), label + ": unique IDs")
				ids[item["id"]] = true
				if bool(item.get("ford_detail", false)):
					for cell in Decorations.footprint_cells(spec, item["source_frame"], item["position"]):
						var index: int = cell.y * data["size"].x + cell.x
						check(int(data["terrain_ids"][index]) in Landscape.WATER and data["rivers"]["mouth_mask"][index] == 0, label + ": ford artwork stays on water outside estuaries")
				else:
					check(Decorations.fits(spec, item["source_frame"], item["position"], water_ctx if item.get("water_detail", false) else ctx), label + ": ecological footprint " + String(item["decoration_key"]))
				check(not catalog.environment_frame_info(item).is_empty(), label + ": resolves real art")
				seen["%s/%d" % [item["decoration_key"], item["source_frame"]]] = true
			var summary: Dictionary = data["decoration_summary"]
			check(summary["decals"] >= 8, label + ": visible ground detail budget")
			check(summary["families"].size() >= 4, label + ": diverse habitats")
			check(summary["sources"]["ror"] > 0, label + ": native decorations present")
			rows.append({"profile": profile["id"], "seed": seed_value, "decoration": summary})
			print(label + " " + JSON.stringify(summary))
			if profile["id"] == "mediterranean" and seed_value == 41689:
				check(Generator.generate(built["definition"]) == data, "full generated content is reproducible")
				var bare_definition: Dictionary = built["definition"].duplicate(true)
				bare_definition["map"]["generator"]["decoration_density"] = 0.0
				var bare := Generator.generate(bare_definition)
				for key in ["resources", "terrain_ids", "vertex_levels", "region_graph", "forest_mask", "marine_resources"]:
					check(bare[key] == data[key], "decorations preserve " + key)
				check(bare["scenery"].all(func(item): return bool(item.get("ford_detail", false)) or bool(item.get("waterfall_detail",false)) or bool(item.get("shoreline_detail",false))), "density zero removes optional decoration while retaining geographic features")
	check(seen.size() >= 60, "natural 18-map sample uses at least 60 distinct variants")
	var directory := "res://qa/generated-decorations"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output := FileAccess.open(directory + "/generation-report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"maps": rows, "distinct_variants": seen.size(), "failures": failures}, "  "))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Generated decorations passed: 18 maps, habitats, art, variety, determinism and unchanged gameplay")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)
