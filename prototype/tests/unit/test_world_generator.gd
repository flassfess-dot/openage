extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const WorldGeography := preload("res://scripts/random_map_watershed_world.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Replay := preload("res://scripts/replay_system.gd")
const DIRECTORY := "res://qa/world-generator-20261018"
var failures: Array[String] = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var mode := "supergiant" if "--supergiant" in OS.get_cmdline_user_args() else "boundaries" if "--boundaries" in OS.get_cmdline_user_args() else "smoke"
	var rows: Array = []
	var shallows: Dictionary = Decorations.palette().filter(func(spec): return spec["key"] == "ror_shallows")[0]
	check(Settings.default_settings()["landscape_version"] == WorldGeography.VERSION, "Normal new-game settings enable the shared world generator")
	check(Settings.catalog()["map_types"].size() == WorldGeography.PROFILES.size(), "All nine menu profiles have geographic recipes")
	var fixtures: Array = []
	var selected_profiles := PackedStringArray()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profiles="): selected_profiles = argument.trim_prefix("--profiles=").split(",",false)
	for profile in WorldGeography.PROFILES:
		if not selected_profiles.is_empty() and profile not in selected_profiles: continue
		if mode == "boundaries":
			for item in [["compact", 7919, 4], ["large", 41721, 8], ["standard", 104729, 6]]: fixtures.append([profile] + item)
		else: fixtures.append([profile, "supergiant" if mode == "supergiant" else "standard", 41721, 4])
	if mode == "smoke" and (selected_profiles.is_empty() or "highlands" in selected_profiles): fixtures.append(["highlands", "standard", 41689, 4])
	check(not fixtures.is_empty(),"profile filter selects at least one fixture")
	var report_name := mode if selected_profiles.is_empty() else mode+"-"+"_".join(selected_profiles)
	var output := FileAccess.open(DIRECTORY.path_join(report_name + ".jsonl"), FileAccess.WRITE)
	for fixture in fixtures:
		var settings := Settings.default_settings()
		settings["map_type_id"] = fixture[0]
		settings["map_size_id"] = fixture[1]
		settings["seed"] = fixture[2]
		for i in range(8): settings["players"][i]["enabled"] = i < int(fixture[3])
		var started := Time.get_ticks_usec()
		var built := Settings.build(settings)
		var row := {"fixture": fixture, "valid": built.get("valid", false), "errors": built.get("errors", []), "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0}
		check(bool(row["valid"]), "%s builds: %s" % [fixture, row["errors"]])
		if bool(row["valid"]):
			var data: Dictionary = built["map_data"]
			row["clearings"] = data.get("building_clearings",[]).size()
			check(data["generator_version"] == WorldGeography.VERSION, "%s uses shared hydrology in ordinary settings" % [fixture])
			check(data.get("building_clearings", []).size() == built["definition"]["players"].size(), "%s preserves an accessible expansion clearing for every settlement" % [fixture])
			check(built["definition"]["map"]["generator"]["wild_geography"], "%s retains unequal geography and economy" % [fixture])
			check(Rivers.inspect(data["rivers"])["valid"], "%s has a connected, non-uphill drainage graph" % [fixture])
			check(not data.has("_fields") and not data.has("_reserved") and not data["rivers"].has("drainage"), "%s leaves no generation scratch in saved map data" % [fixture])
			var size: Vector2i = data["size"]
			var mouth_mask: PackedByteArray = data["rivers"]["mouth_mask"]
			for i in range(mouth_mask.size()):
				if mouth_mask[i] != 0 and data["rivers"]["terrain_types"][i] >= 0:
					check(int(data["terrain_ids"][i]) in [1, 22], "%s keeps river mouths free of fords, shoals and dry bars" % [fixture])
			for ford in data["fords"]:
				if data["rivers"]["surface"].get("model_version", 0) >= 1:
					var field := preload("res://scripts/random_map_river_surface.gd").sample(data["rivers"]["surface"],(ford["bank_a"]+ford["bank_b"])*0.5)
					check(field.z <= 0.25,"%s shows a continuous shallow gravel ridge on every ford" % [fixture])
				else:
					check(data["scenery"].any(func(item): return bool(item.get("ford_detail", false)) and Vector2i(Vector2(item["position"]).floor()) in ford["cells"]), "%s shows source sandy islets on every ford" % [fixture])
				for cell in ford["cells"]:
					check(int(data["terrain_ids"][cell.y * size.x + cell.x]) == 4, "%s preserves shared infantry/ship ford terrain" % [fixture])
					check(mouth_mask[cell.y * size.x + cell.x] == 0, "%s excludes every crossing cell from estuaries" % [fixture])
					var vertex: int = cell.y * (size.x + 1) + cell.x
					for offset in [1, size.x + 1, size.x + 2]:
						check(data["vertex_levels"][vertex] == data["vertex_levels"][vertex + offset], "%s keeps the ford surface level after settlement and forestry" % [fixture])
			var scenery_ids: Dictionary = {}
			for item in data["scenery"]:
				check(not scenery_ids.has(item["id"]), "%s publishes unique scenery IDs after excluding mouth artwork" % [fixture])
				scenery_ids[item["id"]] = true
				if item.get("asset_name", "") != "aoe2_temperate:ror_shallows": continue
				for covered in Decorations.footprint_cells(shallows, int(item["source_frame"]), item["position"]):
					check(int(data["terrain_ids"][covered.y * size.x + covered.x]) in [1, 4, 22] and mouth_mask[covered.y * size.x + covered.x] == 0, "%s keeps the entire ford graphic on water outside estuaries" % [fixture])
			for lake in data["lakes"]:
				for i in lake["cells"]:
					check(int(data["terrain_ids"][i]) in [1, 22], "%s preserves lake water" % [fixture])
					var vertex: int = (i / size.x) * (size.x + 1) + i % size.x
					for corner in [vertex, vertex + 1, vertex + size.x + 1, vertex + size.x + 2]:
						check(data["vertex_levels"][corner] == lake["surface_level"], "%s keeps a level lake surface at its recorded altitude" % [fixture])
			if fixture[0] == "highlands" and fixture[1] == "supergiant":
				check(data["lakes"].any(func(lake): return int(lake["surface_level"]) > 0), "Highland 400 fixture retains elevated lakes instead of sea-level trenches")
			for resource in data["resources"]:
				var cell := Vector2i(resource["position"])
				if resource.get("placement_domain", "land") == "land":
					check(data["rivers"]["mask"][cell.y * size.x + cell.x] == 0, "%s leaves rivers, lakes and crossing approaches clear of land resources" % [fixture])
			row.merge({"water_ratio": built["map_quality"]["metrics"]["water_ratio"], "lakes": data["lakes"].size(), "fords": data["fords"].size(),
				"rivers": Rivers.inspect(data["rivers"]), "composition": data["ecology"]["composition"], "shape_kind": data["geography"]["shape_kind"], "hash": data["content_hash"]})
			if mode == "smoke":
				var codec := Replay.new()
				var definition: Dictionary = codec.decode_variant(JSON.parse_string(JSON.stringify(codec.encode_variant(built["definition"]))))
				var regenerated := Generator.generate(definition)
				check(regenerated.get("content_hash") == data["content_hash"], "%s regenerates identically from its serialized definition without prepared geography" % [fixture])
			var cache := FileAccess.open(DIRECTORY.path_join("%s-%s.bin" % [fixture[0], fixture[1]]), FileAccess.WRITE)
			cache.store_var(built)
		rows.append(row)
		output.store_line(JSON.stringify(row))
		output.flush()
		print(JSON.stringify({"fixture": fixture, "valid": row["valid"], "errors": row["errors"], "elapsed_ms": row["elapsed_ms"], "lakes": row.get("lakes", 0), "fords": row.get("fords", 0)}))
	FileAccess.open(DIRECTORY.path_join(report_name + ".json"), FileAccess.WRITE).store_string(JSON.stringify({"valid": failures.is_empty(), "rows": rows, "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
