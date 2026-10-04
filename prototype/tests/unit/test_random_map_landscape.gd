extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Quality := preload("res://scripts/random_map_quality.gd")
const Zones := preload("res://scripts/random_map_zones.gd")
const Replay := preload("res://scripts/replay_system.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var settings := Settings.default_settings()
	var built := Settings.build(settings)
	check(bool(built.get("valid", false)), "v2 builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return
	var data: Dictionary = built["map_data"]
	var definition: Dictionary = built["definition"]
	var size: Vector2i = data["size"]
	check(definition["map"]["generator"]["type"] == Landscape.TYPE, "new matches opt into version two")
	check(data["generator_version"] == 2 and String(data["content_hash"]).length() == 64, "version and hash are explicit")
	check(definition["map"]["content_hash"] == data["content_hash"], "save identity includes generated content")
	var codec := Replay.new()
	var round_trip: Dictionary = codec.decode_variant(JSON.parse_string(JSON.stringify(codec.encode_variant(definition))))
	check(Generator.generate(round_trip)["content_hash"] == data["content_hash"], "serialized definition regenerates identical content")
	check(not data["terrain_ids"].has(6), "temperate inland maps contain no desert patches")
	for item in data["scenery"]:
		if item.get("decoration_key", "") != "ror_cracks": continue
		var at := Vector2i(item["position"])
		check(data["terrain_ids"][at.y * size.x + at.x] in [1000, 6], "cracks require exposed soil, never grass")
	var trees := 0
	for resource in data["resources"]:
		if String(resource.get("kind", "")) != "tree": continue
		trees += 1
		var cell := Vector2i(resource["position"])
		check(data["forest_mask"][cell.y * size.x + cell.x] == 1, "forest mask describes actual trees")
		check(data["terrain_ids"][cell.y * size.x + cell.x] in [10, 1003], "trees have coherent native or imported forest ground")
		check(resource.get("environment_asset", "native") in ["native", "oak", "pine"], "mixed tree palette remains temperate")
		check(Landscape.flat_cell(cell, size, data["vertex_levels"]), "adapted tree is on a flat terrace")
	var accents: Array = data["resources"].filter(func(r): return r.has("tree_condition"))
	check(not accents.is_empty() and accents.size() < trees * 0.025, "autumn and dry accents remain rare among green woods")
	for accent in accents:
		check(not accent.has("environment_asset") and accent["source_graphic_id"] in [607, 613, 627, 630], "rare conditions resolve to the selected native art")
		for other in accents:
			if other != accent: check(Vector2(accent["position"]).distance_to(other["position"]) >= 6.0, "rare specimens never form yellow or dry clumps")
		if accent.get("ecology_role", "") == "solitary_tree":
			for other in data["resources"]:
				if other != accent: check(Vector2(accent["position"]).distance_to(other["position"]) > 2.0, "solitary accents remain separate from forest and other resources")
	var sources: Dictionary = data["ecology"]["tree_sources"]
	check(sources["ror"] > trees / 5 and sources["aoe2"] > trees / 5, "both games contribute substantial tree populations on the same map")
	check(data["terrain_ids"].has(0) and data["terrain_ids"].has(10) and data["terrain_ids"].has(1003), "native meadow and light forest share a map with imported forest ground")
	check(trees == data["forest_mask"].count(1), "there are no ghost forest centres or overlapping trees")
	for i in range(size.x * size.y):
		check(Quality._valid_cell_gradient(Vector2i(i % size.x, i / size.x), size, data["vertex_levels"]), "all slopes have renderable one-level gradients")
	var nav := Navigation.inspect(definition, data)
	check(nav["valid"], "actual static occupancy preserves all starting resource guarantees")
	var sabotage := data.duplicate(true)
	for resource in data["resources"]:
		if resource.get("kind", "") != "berries": continue
		var cell := Vector2i(resource["position"])
		for neighbor in Navigation.neighbors(cell.y * size.x + cell.x, size):
			sabotage["resources"].append({"kind": "tree", "category": "resource", "position": Vector2(neighbor % size.x + 0.5, neighbor / size.x + 0.5)})
	check(not Navigation.inspect(definition, sabotage)["valid"], "quality catches berries sealed behind static objects")
	var unsupported := definition.duplicate(true)
	unsupported["map"]["generator"]["version"] = 999
	check(Generator.generate(unsupported).has("generation_error"), "unsupported versions fail explicitly")
	unsupported["map"]["generator"]["type"] = "seeded_skirmish_v1"
	check(Generator.generate(unsupported).get("generation_error") == "random_map_generator_type_unsupported", "retired matches cannot silently fall through to a flat test scene")
	settings["map_type_id"] = "highlands"
	var highlands := Settings.build(settings)
	check(bool(highlands.get("valid", false)), "highlands build")
	check(highlands["map_data"]["terrain_ids"] != data["terrain_ids"], "grasslands and highlands have distinct surface composition")
	check(highlands["map_data"]["vertex_levels"] != data["vertex_levels"], "profile affects shared relief")
	_test_solitary_accents()
	_test_tree_palettes()
	_test_alliances()
	finish()

func _test_solitary_accents() -> void:
	var size := Vector2i(64, 64)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(0)
	var starts: Array[Vector2] = []
	var fields := Landscape.select_fields(size, terrain, starts, "grasslands", 1234)
	fields["vertex_levels"].fill(0)
	fields["forest_potential"].fill(0)
	var zones := PackedInt32Array()
	zones.resize(terrain.size())
	zones.fill(2)
	var data := {"size": size, "terrain_ids": terrain, "vertex_levels": fields["vertex_levels"], "resources": [], "strategic_zones": {"zone_ids": zones}}
	var reserved: Dictionary = {}
	for y in range(size.y):
		for x in range(27, 36): reserved[Vector2i(x, y)] = true
	Landscape.forest_accents(data, fields, reserved.duplicate(), 1234)
	check(data["resources"].size() == 2, "open landscape receives only two isolated accents per 4096 cells")
	for tree in data["resources"]:
		check(tree.get("ecology_role") == "solitary_tree" and tree.has("tree_condition"), "isolated specimens retain their role and condition")
		check(not reserved.has(Vector2i(tree["position"])), "isolated trees preserve open travel corridors")
		check(not tree.has("environment_asset"), "rare trees use native autumn or dry art")

func _test_tree_palettes() -> void:
	var size := Vector2i(24, 24)
	for pine in [false, true]:
		var fields := {"moisture": [], "geology": [], "vertex_levels": []}
		fields["moisture"].resize(size.x * size.y)
		fields["moisture"].fill(0.3 if pine else 0.7)
		fields["geology"].resize(size.x * size.y)
		fields["geology"].fill(0.5)
		fields["vertex_levels"].resize((size.x + 1) * (size.y + 1))
		fields["vertex_levels"].fill(0)
		var native_count := 0
		var imported_count := 0
		var native_graphics: Dictionary = {}
		for i in range(size.x * size.y):
			var tree := {"kind": "tree", "position": Vector2(i % size.x + 0.5, i / size.x + 0.5), "amount": 75}
			Landscape.bind_tree(tree, fields, size, 7919)
			var same := tree.duplicate(true)
			Landscape.bind_tree(same, fields, size, 7919)
			check(same == tree, "presentation and jitter remain deterministic when rebound")
			check(tree["amount"] == 75 and tree["source_frame"] == 0, "mixing retains wood amount and never uses a felled native frame")
			if tree.has("environment_asset"):
				imported_count += 1
				check(tree["environment_asset"] == ("pine" if pine else "oak"), "imported species follows habitat")
			else:
				native_count += 1
				native_graphics[tree["source_graphic_id"]] = true
				check(tree["source_graphic_id"] in ([603, 623, 655] if pine else [601, 603, 609, 611, 614]), "native species follows the same habitat")
		check(native_count > 100 and imported_count > 100 and native_graphics.size() >= 3, "both sources provide varied trees in each habitat")

func _test_alliances() -> void:
	var size := Vector2i(40, 20)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(0)
	var players := [{"team": 1, "alliance_id": 1, "start": Vector2(5, 10)}, {"team": 2, "alliance_id": 1, "start": Vector2(15, 10)}, {"team": 3, "alliance_id": 2, "start": Vector2(35, 10)}]
	var zones := Zones.build(players, size, terrain, [], {"alliance_aware": true, "sanctuary_radius_cells": 2, "sanctuary_radius_min_cells": 2})
	check(int(zones["second_start_distances"][10 * size.x + 10]) == 25, "contested distance measures enemies, not the nearest ally")

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Landscape v2 ecology, navigation and reproducibility tests passed")
	quit(0 if failures.is_empty() else 1)
