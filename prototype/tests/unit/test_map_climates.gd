extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var settings := Settings.default_settings()
	settings.erase("climate_id")
	var baseline := Settings.build(settings)
	if not baseline.get("valid", false):
		push_error(str(baseline.get("errors")))
		quit(1)
		return
	var original: Dictionary = baseline["map_data"]
	check(original["content_hash"] == "ce20200ae88bb7db406ae72eb58deb93fa32a8fd658bdcb75426e198f4b7fbf8", "legacy seed 41721")
	var original_resources := resource_layout(original)
	var hashes := {}
	for climate in ["nile", "anatolia", "aegean"]:
		settings["climate_id"] = climate
		var result := Settings.build(settings)
		check(result.get("valid", false), climate + " starts")
		if not result.get("valid", false): continue
		var data: Dictionary = result["map_data"]
		for key in ["terrain_ids", "vertex_levels", "forest_mask", "fords", "cliff_cells", "building_clearings", "region_graph", "naval_start_zones"]:
			check(data[key] == original[key], climate + " " + key)
		check(result["definition"]["players"] == baseline["definition"]["players"], climate + " same starts")
		check(resource_layout(data) == original_resources, climate + " same resources and amounts")
		var surfaces: PackedInt32Array = data["climate_surfaces"]
		var counts := {}
		for i in range(surfaces.size()):
			var id := surfaces[i]
			counts[id] = int(counts.get(id, 0)) + 1
			if data["terrain_ids"][i] in [1, 4, 15, 22] and id != data["terrain_ids"][i]:
				failures.append(climate + " water changed")
				break
		check(counts.has(1103) and counts.size() >= 5, climate + " regional surfaces and ford")
		check(not hashes.has(data["content_hash"]) and data["content_hash"] != original["content_hash"], climate + " distinct content")
		hashes[data["content_hash"]] = true
		var reproduced: Dictionary = Generator.generate(result["definition"])
		check(reproduced.get("content_hash") == data["content_hash"], climate + " deterministic recipe replay")
		var elevation := Elevation.new(data["size"], false)
		elevation.configure_climate(data)
		var at := surfaces.find(1103)
		if at >= 0:
			var cell := Vector2i(at % data["size"].x, at / data["size"].x)
			check(elevation.surface_material(cell, data["terrain_ids"][at]) == 1103, climate + " ford presentation")
			check(elevation.surface_material(cell, 22) == 22, climate + " live terrain edit")
		print("CLIMATE ", climate, " seed=", settings["seed"], " materials=", counts, " hash=", data["content_hash"])
	settings["climate_id"] = "unknown"
	check(not Settings.normalize(settings)["valid"], "unknown climate rejected")
	if "--profiles" in OS.get_cmdline_user_args():
		settings["map_size_id"] = "compact"
		settings["seed"] = 7919
		for profile in Settings.catalog()["map_types"]:
			settings["map_type_id"] = profile["id"]
			var reference: Array = []
			for climate in ["nile", "anatolia", "aegean"]:
				settings["climate_id"] = climate
				var sample := Settings.build(settings)
				check(sample.get("valid", false), "%s / %s" % [profile["id"], climate])
				if not sample.get("valid", false): continue
				var data: Dictionary = sample["map_data"]
				var geography := [data["terrain_ids"], data["vertex_levels"], data["fords"], resource_layout(data)]
				check(reference.is_empty() or reference == geography, "%s geography in %s" % [profile["id"], climate])
				reference = geography
				check(data["climate_surfaces"].size() == data["terrain_ids"].size(), "complete surface grid")
			print("CLIMATE_PROFILE ", profile["id"])
	for failure in failures: push_error(failure)
	print("Map climate invariants: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)


func resource_layout(data: Dictionary) -> Array:
	var result := []
	for item in data["resources"]:
		result.append([item.get("kind"), item.get("position"), item.get("amount"), item.get("placement_domain")])
	return result


func check(passed: bool, message: String) -> void:
	if not passed: failures.append(message)
