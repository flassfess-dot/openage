extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const CASES := [
	{"map_type_id": "small_islands", "seed": 1},
	{"map_type_id": "coastal", "seed": 7919},
]

var failures: Array[String] = []


func _initialize() -> void:
	for case_value in CASES:
		var case: Dictionary = case_value
		var settings := SkirmishSettings.default_settings()
		settings["map_type_id"] = String(case["map_type_id"])
		settings["map_size_id"] = "large"
		settings["seed"] = int(case["seed"])
		for index in range(settings["players"].size()):
			settings["players"][index]["enabled"] = true
		var built := SkirmishSettings.build(settings)
		if not bool(built.get("valid", false)):
			failures.append("%s/8p/seed%d: %s" % [case["map_type_id"], case["seed"], built.get("errors", [])])
			continue
		var wildlife: Array = built["map_data"].get("resources", []).filter(func(resource): return String(resource.get("category", "")) == "unit")
		if wildlife.is_empty():
			failures.append("%s/8p/seed%d has no source wildlife" % [case["map_type_id"], case["seed"]])
	if failures.is_empty():
		print("Crowded eight-player start-resource regressions passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
