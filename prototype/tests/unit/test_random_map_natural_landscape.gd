extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Contract := preload("res://scripts/random_map_contract.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Topology := preload("res://scripts/random_map_natural_topology.gd")
const Quality := preload("res://scripts/random_map_quality.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_test_soil_profiles()
	_test_coastal_orientation()
	_test_completed_landscape_and_legacy()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Natural landscape composition, geography and legacy identity passed")
	quit(0 if failures.is_empty() else 1)

func _test_soil_profiles() -> void:
	var size := Vector2i(8, 8)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(0)
	var geology := PackedFloat32Array()
	geology.resize(terrain.size())
	geology.fill(0.70)
	var moisture := geology.duplicate()
	moisture.fill(0.30)
	var fields := {"geology": geology, "moisture": moisture, "recipe": Natural.theme()["profiles"]["grasslands"]}
	var meadow := {"terrain_ids": terrain.duplicate()}
	Natural.paint_ground(meadow, fields)
	fields["recipe"] = Natural.theme()["profiles"]["highlands"]
	var highlands := {"terrain_ids": terrain.duplicate()}
	Natural.paint_ground(highlands, fields)
	check(meadow["terrain_ids"] != highlands["terrain_ids"], "identical weather and geology expose different soils under different profile thresholds")
	check(highlands["terrain_ids"].count(1000) == terrain.size(), "highland exposed-soil threshold is effective below 0.86")

func _test_coastal_orientation() -> void:
	var size := Vector2i(72, 72)
	var starts: Array[Vector2] = []
	var sides: Dictionary = {}
	for seed in range(1, 17):
		var layout := Topology.prepare(size, starts, "coastal", {"coast_fraction": 0.21}, seed)
		var counts := [0, 0, 0, 0]
		for i in range(6, 67, 6):
			var points := [Vector2(1, i), Vector2(71, i), Vector2(i, 1), Vector2(i, 71)]
			for side in range(4):
				if Topology.water_at(points[side], layout): counts[side] += 1
		sides[counts.find(counts.max())] = true
	check(sides.size() >= 3, "different seeds move the ocean between at least three map edges")

func _test_completed_landscape_and_legacy() -> void:
	var settings := Settings.default_settings()
	settings["seed"] = 41721
	settings["map_size_id"] = "standard"
	settings["map_type_id"] = "grasslands"
	for i in range(8): settings["players"][i]["enabled"] = i < 4
	var built := Settings.build(settings)
	check(bool(built.get("valid", false)), "natural fixture is playable: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)): return
	var data: Dictionary = built["map_data"]
	var definition: Dictionary = built["definition"]
	check(data["generator_version"] == 3, "new games select revision three")
	var selection: Dictionary = data["generation_candidates"]
	check(selection["scope"] == "final_landscape", "selection evaluates the landscape after paths, economy and tree placement")
	var chosen: Dictionary = selection["scores"][selection["selected_candidate_index"]]
	var measured := Natural.composition(data)
	for key in measured: check(measured[key] == chosen["composition"][key], "published candidate %s describes the actual final map" % key)
	check(not data.has("_fields") and not data.has("_reserved"), "scratch fields and reservation dictionaries never enter saved map data")
	var damaged := data.duplicate(true)
	damaged["forest_mask"].fill(0)
	damaged["resources"] = damaged["resources"].filter(func(r): return r.get("kind", "") != "tree")
	var rejected := Quality.inspect(definition, damaged)
	check(rejected["errors"].has("random_map_landscape_woodland_missing"), "quality rejects missing woodlands even when stale ecology metadata claims success")
	# Frozen terrain/height hashes were measured before revision three. Old
	# definitions contain explicit starts, so they must bypass new placement.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41721 ^ 0x726F5231
	var starts: Array[Vector2] = []
	var phase := rng.randf_range(-PI / 4.0, PI / 4.0)
	for i in range(4):
		var angle := -PI * 0.5 + phase + TAU * i / 4.0 + rng.randf_range(-0.035, 0.035)
		starts.append(Vector2(36, 36) + Vector2(cos(angle), sin(angle)) * 72.0 * 0.28 * rng.randf_range(0.96, 1.04))
	var old := definition.duplicate(true)
	old["map"].erase("content_hash")
	var profile: Dictionary = Settings.catalog()["map_types"].filter(func(p): return p["id"] == "grasslands")[0]
	old["map"]["generator"] = Contract.build(profile, Vector2i(72, 72), starts)
	old["map"]["generator"]["version"] = 2
	old["map"]["generator"]["theme"] = "temperate_v2"
	old["entities"] = []
	for i in range(4):
		old["players"][i]["start"] = starts[i]
		old["entities"].append({"category": "building", "team": i + 1, "kind": "town_center", "position": starts[i], "resource_exclusion_radius_cells": 2})
		for position in Settings._starting_villager_positions(starts[i], Vector2i(72, 72)):
			old["entities"].append({"category": "unit", "team": i + 1, "kind": "villager", "position": position, "selected": i == 0, "resource_exclusion_radius_cells": 1})
	var legacy := Generator.generate(old)
	check(var_to_bytes(legacy["terrain_ids"]).hex_encode().sha256_text() == "635f63416f6b95535dede66f1951569e48ec457c37ab10656d23ad1840080c1f", "revision two retains the pre-change surface hash")
	check(var_to_bytes(legacy["vertex_levels"]).hex_encode().sha256_text() == "15fb22296e24b6e2358677b3fb7563317dbc5767de75d0bcca6cae64642f01a8", "revision two retains the pre-change height hash")

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)
