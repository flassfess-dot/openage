extends SceneTree
const Settings = preload("res://scripts/skirmish_settings.gd")
const Rules = preload("res://scripts/terrain_rules.gd")
var output_directory := "res://qa/random-map-audit/"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			output_directory = arg.trim_prefix("--output-dir=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var rows: Array = []
	for seed_value in [41721, 7919, 104729]:
		for profile in Settings.catalog()["map_types"]:
			rows.append(measure_map(String(profile["id"]), "standard", seed_value))
	for size_id in ["huge", "giant", "supergiant"]:
		rows.append(measure_map("grasslands", size_id, 41721))
	var out = FileAccess.open(output_directory + "measurements.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"date": Time.get_datetime_string_from_system(), "sample_count": rows.size(), "rows": rows}, "\t"))
	quit(0)
func measure_map(profile: String, size_id: String, seed_value: int) -> Dictionary:
	var settings: Dictionary = Settings.default_settings()
	settings["map_type_id"] = profile
	settings["map_size_id"] = size_id
	settings["seed"] = seed_value
	for i in range(8):
		settings["players"][i]["enabled"] = i < 4
	var begin = Time.get_ticks_msec()
	var built: Dictionary = Settings.build(settings)
	var elapsed = Time.get_ticks_msec() - begin
	var data: Dictionary = built.get("map_data", {})
	if data.is_empty():
		return {"profile": profile, "size_id": size_id, "seed": seed_value, "valid": false, "errors": built.get("errors", [])}
	var size: Vector2i = data["size"]
	var terrain: Array = data["terrain_ids"]
	var levels: Array = data["vertex_levels"]
	var counts: Dictionary = {}
	var forest_count = 0
	var tree_cells: Dictionary = {}
	var tree_conditions: Dictionary = {}
	var resource_kinds: Dictionary = {}
	for tid in terrain:
		counts[str(tid)] = int(counts.get(str(tid), 0)) + 1
		if tid in [10, 1003]: forest_count += 1
	for item in data.get("resources", []):
		var kind: String = item["kind"]
		resource_kinds[kind] = int(resource_kinds.get(kind, 0)) + 1
		if kind == "tree":
			tree_cells[Vector2i(Vector2(item["position"]))] = true
			var condition := String(item.get("tree_condition", "green"))
			tree_conditions[condition] = int(tree_conditions.get(condition, 0)) + 1
	var forest_with_tree = 0
	for cell in tree_cells:
		if terrain[cell.y * size.x + cell.x] in [10, 1003]: forest_with_tree += 1
	var detail_count = 0
	var detail_grass_count = 0
	for item in data.get("scenery", []):
		if item.get("feature_family", "") == "ground_detail":
			detail_count += 1
			var cell = Vector2i(Vector2(item["position"]))
			if terrain[cell.y * size.x + cell.x] == 0: detail_grass_count += 1
	var elevated = levels.filter(func(v): return int(v) > 0).size()
	var row = {"profile": profile, "size_id": size_id, "width": size.x, "players": 4, "seed": seed_value, "valid": built.get("valid", false), "errors": built.get("errors", []), "elapsed_ms": elapsed, "generation_diagnostics": built.get("generation_diagnostics", {}), "terrain_counts": counts, "terrain_hash": var_to_bytes(terrain).hex_encode().sha256_text(), "height_hash": var_to_bytes(levels).hex_encode().sha256_text(), "elevated_vertex_fraction": float(elevated) / levels.size(), "forest_cells": forest_count, "forest_cells_with_tree": forest_with_tree, "forest_tree_occupancy": float(forest_with_tree) / maxi(1, forest_count), "tree_conditions": tree_conditions, "tree_sources": data.get("ecology", {}).get("tree_sources", {}), "resource_kinds": resource_kinds, "scenery_count": data.get("scenery", []).size(), "ground_details": detail_count, "ground_details_on_grass": detail_grass_count, "candidate_scope": data.get("generation_candidates", {}).get("scope", ""), "metrics": built.get("map_quality", {}).get("metrics", {})}
	if seed_value == 41721: write_image(profile, size_id, data, built.get("definition", {}))
	print(JSON.stringify({"profile": profile, "size": size.x, "seed": seed_value, "valid": row["valid"], "elapsed_ms": elapsed, "sand_cells": counts.get("6", 0), "forest_occupancy": row["forest_tree_occupancy"], "elevated_fraction": row["elevated_vertex_fraction"], "scenery": row["scenery_count"], "ground_details_on_grass": detail_grass_count}))
	return row
func write_image(profile: String, size_id: String, data: Dictionary, definition: Dictionary) -> void:
	var size: Vector2i = data["size"]
	var image = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var relief = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in range(size.y):
		for x in range(size.x):
			var tid = int(data["terrain_ids"][y * size.x + x])
			var color = Color("739348")
			if tid in [2,6,13]: color = Color("cfb76c")
			elif tid in [1000, 1001, 1002, 1003]: color = [Color("877447"), Color("7e804c"), Color("969253"), Color("52613a")][tid - 1000]
			elif tid == 1: color = Color("3476ab")
			elif tid == 4: color = Color("79c3c9")
			elif tid == 22: color = Color("193d73")
			image.set_pixel(x,y,color)
			var height_value = float(data["vertex_levels"][y*(size.x+1)+x])/3.0
			relief.set_pixel(x,y,Color(height_value,height_value,height_value))
	for item in data.get("resources", []):
		var color = Color("dd8950")
		match item["kind"]:
			"tree": color = Color("163516")
			"berries": color = Color("b62767")
			"gold_mine": color = Color("ffe75c")
			"stone_mine": color = Color("d4d2cb")
			"deep_fish": color = Color("77dcf2")
		image.set_pixelv(Vector2i(Vector2(item["position"])),color)
	for p in definition.get("players", []):
		var cell = Vector2i(Vector2(p["start"]))
		for dx in range(-1,2):
			for dy in range(-1,2): image.set_pixelv(cell+Vector2i(dx,dy),Color("ef65ff"))
	var scale = maxi(1,432/size.x)
	image.resize(size.x*scale,size.y*scale,Image.INTERPOLATE_NEAREST)
	relief.resize(size.x*scale,size.y*scale,Image.INTERPOLATE_NEAREST)
	image.save_png(output_directory+profile+"-"+size_id+".png")
	relief.save_png(output_directory+profile+"-"+size_id+"-relief.png")
