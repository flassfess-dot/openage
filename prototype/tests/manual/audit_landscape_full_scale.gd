extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
var rows: Array = []
var failures: Array[String] = []

func _initialize() -> void:
	var directory := "res://qa/landscape-20261003"
	for profile in ["mediterranean", "islands", "small_islands"]:
		var settings := Settings.default_settings()
		settings["map_size_id"] = "supergiant"
		settings["map_type_id"] = profile
		settings["seed"] = 41689
		for i in range(settings["players"].size()): settings["players"][i]["enabled"] = i < 4
		var began := Time.get_ticks_msec()
		var built := Settings.build(settings)
		var data: Dictionary = built.get("map_data", {})
		if not built.get("valid", false): failures.append("%s: %s" % [profile, built.get("errors", [])])
		if data.is_empty(): continue
		var terrain: Array = data["terrain_ids"]
		var land := 0
		for id in terrain:
			if id not in [1, 4, 22]: land += 1
		var trees: Array = data["resources"].filter(func(r): return r["kind"] == "tree")
		var accents: Array = trees.filter(func(r): return r.has("tree_condition"))
		var stones: Array = data["scenery"].filter(func(r): return r["decoration_key"] in ["ror_grass_rocks", "ror_dry_rocks", "ror_mud_rocks"])
		var row := {"profile": profile, "size": 400, "valid": built.get("valid", false), "errors": built.get("errors", []),
			"seconds": (Time.get_ticks_msec() - began) / 1000.0, "land_cells": land, "water_ratio": 1.0 - float(land) / terrain.size(),
			"trees": trees.size(), "rare_trees": accents.size(), "small_stones": stones.size(), "water": data["water_features"],
			"content_hash": data["content_hash"]}
		row["water"].erase("sandbar_anchors")
		rows.append(row)
		var image := Image.create(400, 400, false, Image.FORMAT_RGB8)
		var colors := {0: Color("#5d803b"), 1: Color("#548da1"), 2: Color("#b5a66c"), 4: Color("#7aafb2"), 22: Color("#2e566f"),
			10: Color("#376038"), 1000: Color("#877447"), 1001: Color("#7e804c"), 1002: Color("#969253"), 1003: Color("#405b36")}
		for y in range(400):
			for x in range(400): image.set_pixel(x, y, colors.get(terrain[y * 400 + x], Color("#5d803b")))
		for player in built["definition"]["players"]:
			var point := Vector2i(player["start"])
			for dy in range(-2, 3):
				for dx in range(-2, 3): image.set_pixel(point.x + dx, point.y + dy, Color.WHITE)
		image.resize(800, 800, Image.INTERPOLATE_NEAREST)
		image.save_png(directory.path_join(profile + "-400-terrain.png"))
		var file := FileAccess.open(directory.path_join("full-scale-metrics.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"maps": rows, "failures": failures}, "\t"))
		print("FULL SCALE " + JSON.stringify(row))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
