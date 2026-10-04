extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Contract := preload("res://scripts/random_map_contract.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
var failures: Array[String] = []


func _initialize() -> void:
	test_source_group_multiplicity()
	for profile in ["grasslands", "highlands", "hill_country", "narrows", "coastal", "mediterranean", "continental", "islands", "small_islands"]:
		check_generated_mines(profile, "standard", 2, 41721)
	check_generated_mines("grasslands", "compact", 4, 7919)
	check_generated_mines("small_islands", "compact", 2, 7919)
	check_generated_mines("coastal", "compact", 4, 41721)
	check_generated_mines("grasslands", "large", 2, 1)
	for failure in failures:
		push_error(failure)
	print("Map mineral distribution: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func test_source_group_multiplicity() -> void:
	var profile: Dictionary = Settings.catalog()["map_types"].filter(func(value): return value["id"] == "islands")[0]
	var starts: Array[Vector2] = [Vector2(18.5, 18.5), Vector2(53.5, 53.5)]
	var contract := Contract.build(profile, Vector2i(72, 72), starts)
	var clusters: Array = contract["resource_clusters"]
	for start in starts:
		var stone: Array = clusters.filter(func(cluster): return cluster["kind"] == "stone_mine" and Vector2(cluster["owner_start"][0], cluster["owner_start"][1]) == start)
		check(stone.size() == 2, "each island player receives both source-defined stone groups")


func check_generated_mines(profile: String, size_id: String, players: int, seed: int) -> void:
	var settings := Settings.default_settings()
	settings["map_type_id"] = profile
	settings["map_size_id"] = size_id
	settings["seed"] = seed
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < players
	var built := Settings.build(settings)
	var context := "%s/%s/%d players/seed%d" % [profile, size_id, players, seed]
	check(bool(built.get("valid", false)), "%s generates a playable map: %s" % [context, built.get("errors", [])])
	if not bool(built.get("valid", false)):
		return
	var map: Dictionary = built["map_data"]
	var size: Vector2i = map["size"]
	var resources: Array = map["resources"]
	var starts: Array = built["definition"]["players"].map(func(player): return player["start"])
	var walkable := Navigation.mask(map, built["definition"])
	var reachability: Array = []
	for start in starts:
		reachability.append(Navigation.flood(size, walkable, Vector2i(start))["distances"])
	var occupied: Dictionary = {}
	for resource in resources:
		var cell := Vector2i(Vector2(resource["position"]))
		check(not occupied.has(cell), "%s keeps every resource in a separate cell" % context)
		occupied[cell] = true
	for kind in ["gold_mine", "stone_mine"]:
		var neutral: Array = resources.filter(func(resource): return resource["kind"] == kind and resource.get("owner_start", []).is_empty())
		check(neutral.size() >= players * 4, "%s has substantial independent %s deposits (%d)" % [context, kind, neutral.size()])
		for index in range(players):
			var accessible := 0
			for resource in neutral:
				if Navigation.adjacent_reachable(size, reachability[index], Vector2i(Vector2(resource["position"]))) >= 0:
					accessible += 1
			check(accessible >= 4, "%s gives player %d access to independent %s deposits (%d)" % [context, index + 1, kind, accessible])
			var owned: Array = resources.filter(func(resource): return resource["kind"] == kind and not resource.get("owner_start", []).is_empty() and Vector2(resource["owner_start"][0], resource["owner_start"][1]) == Vector2(starts[index]))
			check(owned.size() >= 7, "%s preserves the starting %s supply for player %d" % [context, kind, index + 1])
		print("%s: %d neutral %s nodes" % [context, neutral.size(), kind])
	# Clusters belong to a separate deterministic stream and may not reroll between builds.
	if profile == "grasslands" and size_id == "compact":
		var repeat := Settings.build(settings)
		check(repeat["map_data"]["resources"] == resources, "mineral distribution remains deterministic for the same seed")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
