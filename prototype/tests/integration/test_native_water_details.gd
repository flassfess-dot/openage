extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Hydro := preload("res://scripts/random_map_hydrology.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const OUT := "res://qa/native-water-details-20261021"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "updated environment pack is usable")
	var specs: Dictionary = {}
	for spec in Decorations.palette(): specs[spec["key"]] = spec
	var seen: Dictionary = {}
	var rows: Array = []
	for profile in ["grasslands", "mediterranean", "highlands", "coastal"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		settings["map_size_id"] = "large"
		for i in range(settings["players"].size()): settings["players"][i]["enabled"] = i < 2
		var started := Time.get_ticks_msec()
		var built := Settings.build(settings)
		check(built.get("valid", false), profile + ": map quality")
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		if profile in ["grasslands", "highlands"]:
			check(data["scenery"].any(func(item): return item.get("decoration_key", "") == "ror_reeds" and item.get("ecology_role", "") in ["source_silt", "inner_bend", "lake_margin", "quiet_river_margin"]), profile + ": native reeds really appear in fresh water")
		FileAccess.open(OUT.path_join(profile + ".bin"), FileAccess.WRITE).store_var(built)
		var size: Vector2i = data["size"]
		var lake_cells: Dictionary = {}
		for lake in data["lakes"]:
			for index in lake["cells"]: lake_cells[int(index)] = true
		var ids: Dictionary = {}
		var islet_count := 0
		for item in data["scenery"]:
			check(not ids.has(item["id"]), profile + ": unique decoration IDs")
			ids[item["id"]] = true
			if not item.get("water_detail", false): continue
			var key: String = item["decoration_key"]
			seen[key] = true
			check(not catalog.environment_frame_info(item).is_empty(), profile + ": native art resolves: " + key)
			var cell := Vector2i(Vector2(item["position"]).floor())
			if key == "ror_river_islets":
				islet_count += 1
				check(RenderWorld.environment_layer(item)==RenderItem.Layer.DECAL and not item.has("occupied_cells"),profile+": joined islets stay beneath units without navigation obstacles")
				var bounds: Array = catalog.environment_pack.object_definition(key)["ground_bounds"][int(item["source_frame"])]
				for y in range(floori(item["position"].y+bounds[1]),floori(item["position"].y+bounds[3])+1):
					for x in range(floori(item["position"].x+bounds[0]),floori(item["position"].x+bounds[2])+1):
						check(data["terrain_ids"][y*size.x+x] not in [1,22],profile+": native exposed sand does not claim a deep ship-only cell")
						check(data["rivers"]["mouth_mask"][y*size.x+x]==0,profile+": islets do not close an estuary")
			if key == "ror_shallows":
				check(data["terrain_ids"][cell.y * size.x + cell.x] == 4, profile + ": sandy islands anchor to real walkable shallows")
				check(Hydro._ford_detail_fits(data, specs[key], int(item["source_frame"]), item["position"]), profile + ": whole shallow sprite stays on level water outside mouths")
			if key == "ror_beach_articles":
				check(data["terrain_ids"][cell.y * size.x + cell.x] in [2, 6], profile + ": marine shore objects stay on native beach or sand")
				var ocean_nearby := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var at := cell + Vector2i(dx, dy)
						if dx * dx + dy * dy > 5 or at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y: continue
						var index := at.y * size.x + at.x
						if data["terrain_ids"][index] in [1, 4, 22] and not lake_cells.has(index) and data["rivers"]["mask"][index] == 0: ocean_nearby = true
				check(ocean_nearby, profile + ": shells and starfish belong to the sea")
			if key == "ror_waterfall":
				check(item.get("height_drop", 0) >= 2 and item["flow_direction"].dot(Vector2.DOWN) >= 0.90, profile + ": waterfall matches actual relief and source direction")
		if profile in ["grasslands","highlands"]: check(islet_count>40,profile+": coherent native sand and reed bands actually appear")
		rows.append({"profile": profile, "size": str(size), "ms": Time.get_ticks_msec() - started, "water_detail": data["water_detail_summary"], "families": data["decoration_summary"]["families"]})
		print(JSON.stringify(rows[-1]))
		if profile == "grasslands":
			check(Generator.generate(built["definition"]) == data, "all native water detail is deterministic")
			var bare_definition: Dictionary = built["definition"].duplicate(true)
			bare_definition["map"]["generator"]["decoration_density"] = 0.0
			var bare := Generator.generate(bare_definition)
			for key in ["terrain_ids", "vertex_levels", "resources", "rivers", "lakes", "fords", "region_graph", "forest_mask", "marine_resources"]:
				check(bare[key] == data[key], "native water decoration preserves " + key)
			check(bare["scenery"].all(func(item): return bool(item.get("ford_detail", false)) or bool(item.get("waterfall_detail",false)) or bool(item.get("shoreline_detail",false))), "zero density retains only mandatory geographic features")
			check(bare["decoration_summary"]["total"]==bare["scenery"].size(),"zero-density summary includes the mandatory waterline")
	for key in ["ror_shore_wrack", "ror_reeds", "ror_beach_articles"]:
		check(seen.has(key), "actual generated maps use " + key)
	FileAccess.open(OUT.path_join("verification.json"), FileAccess.WRITE).store_string(JSON.stringify({"maps": rows, "families": seen.keys(), "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	print("Native water details: four profiles, determinism, unchanged navigation/economy and marine/freshwater habitats; %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
