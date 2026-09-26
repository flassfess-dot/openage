extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "islands"
	settings["map_size_id"] = "large"
	settings["seed"] = 41721
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = true
	var built := SkirmishSettings.build(settings)
	if not bool(built.get("valid", false)):
		var counts: Array = []
		for player_value in built.get("definition", {}).get("players", []):
			var start := Vector2(player_value.get("start", Vector2.ZERO))
			counts.append({"team": player_value.get("team"), "start": start, "berries": built.get("map_data", {}).get("resources", []).filter(func(resource): return String(resource.get("kind", "")) == "berries" and Vector2(resource.get("position", Vector2.ZERO)).distance_to(start) <= 20.0).size()})
		push_error("Eight-player islands seed 41721 invalid: %s metrics=%s nearby=%s" % [built.get("errors", []), built.get("map_quality", {}).get("metrics", {}), counts])
		quit(1)
		return
	print("Eight-player islands seed 41721 generation passed")
	quit(0)
