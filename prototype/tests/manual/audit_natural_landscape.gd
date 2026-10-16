extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")

func _initialize() -> void:
	var directory := "res://qa/natural-landscape-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var fixtures: Array = []
	for profile in Settings.catalog()["map_types"]: fixtures.append([profile["id"], "standard", 41721])
	for seed in [7919, 104729]: fixtures.append(["small_islands", "standard", seed])
	for size_id in ["huge", "giant", "supergiant"]: fixtures.append(["grasslands", size_id, 41721])
	var rows: Array = []
	var failed := 0
	for fixture in fixtures:
		var settings := Settings.default_settings()
		settings["map_type_id"] = fixture[0]
		settings["map_size_id"] = fixture[1]
		settings["seed"] = fixture[2]
		for i in range(8): settings["players"][i]["enabled"] = i < 4
		var started := Time.get_ticks_usec()
		var built := Settings.build(settings)
		var data: Dictionary = built.get("map_data", {})
		var row := {"profile": fixture[0], "size_id": fixture[1], "seed": fixture[2], "valid": built.get("valid", false),
			"errors": built.get("errors", []), "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"size": str(data.get("size")), "generator_version": data.get("generator_version"),
			"composition": data.get("ecology", {}).get("composition", {}), "diagnostics": built.get("generation_diagnostics", {}),
			"metrics": built.get("map_quality", {}).get("metrics", {}), "content_hash": data.get("content_hash", "")}
		rows.append(row)
		if not row["valid"]: failed += 1
		print(JSON.stringify({"profile":fixture[0], "size":fixture[1], "seed":fixture[2], "valid":row["valid"],
			"elapsed_ms":row["elapsed_ms"], "composition":row["composition"], "errors":row["errors"]}))
	var report := FileAccess.open(directory.path_join("measurements.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"sample_count": rows.size(), "failed": failed, "rows": rows}, "\t"))
	quit(0 if failed == 0 else 1)
