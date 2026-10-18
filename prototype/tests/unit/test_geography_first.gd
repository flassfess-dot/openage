extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Geography := preload("res://scripts/random_map_geography.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var rows: Array = []
	var fixtures := [["islands", "standard", 41721, 4], ["coastal", "standard", 104729, 4],
		["highlands", "standard", 41721, 4], ["grasslands", "huge", 7919, 4], ["islands", "large", 7919, 8]]
	for profile in Geography.PROFILES:
		for seed in [41721, 7919, 104729]:
			var fixture := [profile, "standard", seed, 4]
			if fixture not in fixtures: fixtures.append(fixture)
		fixtures.append([profile, "compact", 41721, 2])
	fixtures.append(["islands", "large", 41721, 8])
	fixtures.append(["grasslands", "supergiant", 41721, 4])
	if "--islands-only" in OS.get_cmdline_user_args():
		fixtures = fixtures.filter(func(fixture): return fixture[0] == "islands")
	for fixture in fixtures:
		var settings := Settings.default_settings()
		settings["landscape_version"] = Geography.VERSION
		settings["map_type_id"] = fixture[0]
		settings["map_size_id"] = fixture[1]
		settings["seed"] = fixture[2]
		for i in range(8): settings["players"][i]["enabled"] = i < int(fixture[3])
		var started := Time.get_ticks_usec()
		var built := Settings.build(settings)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		var data: Dictionary = built.get("map_data", {})
		var row := {"fixture": fixture, "valid": built.get("valid", false), "errors": built.get("errors", []), "elapsed_ms": elapsed}
		if data.has("forest_mask"): row["composition"] = Natural.composition(data)
		check(bool(built.get("valid", false)), "%s: %s" % [fixture, built.get("errors", [])])
		if built.get("valid", false):
			var composition := Natural.composition(data)
			row["composition"] = composition
			row["quality"] = built["map_quality"]["metrics"]
			check(float(composition["forest_fraction"]) >= 0.12, "%s has substantial forest coverage" % [fixture])
			check(float(composition["largest_grove_cells"]) >= float(composition["land_cells"]) * 0.015, "%s retains a regional woodland after resources and paths" % [fixture])
			if fixture[0] == "islands":
				var components := _land_components(data)
				row["land_components"] = components
				check(components.size() > int(fixture[3]), "%s includes additional islands" % [fixture])
			if fixture == fixtures[0]:
				var codec := Replay.new()
				var restored: Dictionary = codec.decode_variant(JSON.parse_string(JSON.stringify(codec.encode_variant(built["definition"])) ))
				var regenerated := Generator.generate(restored)
				check(regenerated.get("content_hash") == data.get("content_hash"), "saved definition regenerates the same geography, resources and decoration")
		rows.append(row)
		print(JSON.stringify({"fixture": fixture, "valid": row["valid"], "errors": row["errors"], "composition": row.get("composition", {}), "elapsed_ms": elapsed}))
	DirAccess.make_dir_recursive_absolute("res://qa/geography-first-20261018")
	var report_name := "islands-measurements.json" if "--islands-only" in OS.get_cmdline_user_args() else "measurements.json"
	var report := FileAccess.open("res://qa/geography-first-20261018/" + report_name, FileAccess.WRITE)
	report.store_string(JSON.stringify({"rows": rows, "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Geography-first playability, composition and determinism passed")
	quit(0 if failures.is_empty() else 1)

func _land_components(data: Dictionary) -> Array[int]:
	var size: Vector2i = data["size"]
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for i in range(mask.size()): mask[i] = int(data["terrain_ids"][i] not in [1, 2, 4, 22])
	var sizes: Array[int] = []
	for i in range(mask.size()):
		if mask[i] == 0: continue
		var queue := PackedInt32Array([i])
		mask[i] = 0
		var cursor := 0
		while cursor < queue.size():
			var at := queue[cursor]
			cursor += 1
			for next in Navigation.neighbors(at, size):
				if mask[next] != 0:
					mask[next] = 0
					queue.append(next)
		if queue.size() >= 6: sizes.append(queue.size())
	return sizes

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
