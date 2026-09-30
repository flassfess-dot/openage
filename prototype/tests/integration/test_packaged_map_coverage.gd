extends SceneTree
# Run through --main-pack as well as the source project: a source-only pass
# does not prove that the user's exported game contains the current generator.
const Settings := preload("res://scripts/skirmish_settings.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Pack := preload("res://scripts/environment_pack.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var pack := Pack.new()
	check(pack.enable(), "export includes the current mixed environment definition, manifest and textures")
	check(Decorations.palette().size() == 23, "export includes all current decoration families")
	var fixtures := [
		["compact", "grasslands", 1],
		["standard", "mediterranean", 41721],
		["large", "grasslands", 2147483647],
		["huge", "highlands", 7919],
		["giant", "grasslands", 1],
		["supergiant", "grasslands", 41721],
		["supergiant", "mediterranean", 1790800800],
		["supergiant", "coastal", 2147483647],
	]
	for fixture in fixtures:
		var settings := Settings.default_settings()
		settings["map_size_id"] = fixture[0]
		settings["map_type_id"] = fixture[1]
		settings["seed"] = fixture[2]
		var label := "%s/%s/%d" % fixture
		print("Coverage start: " + label)
		var built := Settings.build(settings)
		check(built.get("valid", false), label + ": playable match " + str(built.get("errors", [])))
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		check(data.get("generator_version", -1) == Landscape.VERSION, label + ": current generator")
		check(data.get("ecology", {}).get("tree_sources", {}).get("ror", 0) > 0, label + ": native trees")
		check(data.get("ecology", {}).get("tree_sources", {}).get("aoe2", 0) > 0, label + ": imported trees")
		var coverage := measure_woodland(data)
		check(coverage["tree_land_ratio"] >= 0.04, label + ": woodland scales with land area")
		check(coverage["land_farther_than_24_cells_from_tree_ratio"] <= 0.12, label + ": no widespread barren interiors")
		check(coverage["maximum_distance_to_tree"] <= 64, label + ": no map-sized empty woodland gaps")
		var metrics: Dictionary = built["map_quality"]["metrics"]
		rows.append({"case": label, "size": str(data["size"]), "coverage": coverage,
			"trees": data["ecology"]["tree_sources"], "resources": data["resources"].size(),
			"marine": data["marine_resources"], "largest_empty_radius_cells": metrics.get("largest_empty_radius_cells"),
			"content_hash": data["content_hash"], "generation_ms": built["generation_diagnostics"]["total_ms"]})
		print(JSON.stringify(rows.back()))
		await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			output.store_string(JSON.stringify({"maps": rows, "failures": failures}, "  "))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Packaged map coverage passed: 8 maps, all six sizes, low/high/time-like seeds and mixed resources")
	quit(0 if failures.is_empty() else 1)

func measure_woodland(data: Dictionary) -> Dictionary:
	var size: Vector2i = data["size"]
	var forest: PackedByteArray = data["forest_mask"]
	var distances := PackedInt32Array()
	distances.resize(forest.size())
	distances.fill(999999)
	var queue := PackedInt32Array()
	for i in range(forest.size()):
		if forest[i] != 0:
			distances[i] = 0
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(i, size):
			if distances[next] > distances[i] + 1:
				distances[next] = distances[i] + 1
				queue.append(next)
	var land := 0
	var far := 0
	var maximum := 0
	for i in range(forest.size()):
		if data["terrain_ids"][i] in Landscape.WATER: continue
		land += 1
		if distances[i] > 24: far += 1
		maximum = maxi(maximum, distances[i])
	return {"tree_land_ratio": float(forest.count(1)) / maxi(1, land),
		"land_farther_than_24_cells_from_tree_ratio": float(far) / maxi(1, land),
		"maximum_distance_to_tree": maximum}

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
