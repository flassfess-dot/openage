extends SceneTree

const Generator := preload("res://scripts/random_map_generator.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var first := Settings.build(Settings.default_settings())
	check(bool(first.get("valid", false)), "fixture builds: %s" % [first.get("errors", [])])
	if not bool(first.get("valid", false)):
		finish()
		return
	var data: Dictionary = first["map_data"]
	var metadata: Dictionary = data["generation_candidates"]
	check(metadata["scope"] == "relief_and_ecology", "candidates select structural fields")
	check(metadata["candidate_count"] == 3, "standard map evaluates three bounded candidates")
	var scores: Array = metadata["scores"]
	var winning: Dictionary = scores[int(metadata["selected_candidate_index"])]
	for score in scores: check(float(score["score"]) <= float(winning["score"]), "selected opportunity score is maximal")
	check(int(metadata["selected_candidate_seed"]) == int(winning["seed"]), "published winning seed is reproducible")
	check(Generator.generate(first["definition"]) == data, "regeneration is exactly deterministic, including metadata")
	var changed: Dictionary = first["definition"].duplicate(true)
	changed["map"]["generator"]["decoration_density"] = 0.0
	var bare := Generator.generate(changed)
	for key in ["terrain_ids", "vertex_levels", "resources", "region_graph", "forest_mask"]:
		check(bare[key] == data[key], "decoration stream cannot change %s" % key)
	check(bare["scenery"].is_empty(), "zero decoration density is honored")
	check(not data.has("total_ms"), "wall-clock diagnostics never enter deterministic map data")
	check(first["generation_diagnostics"].has("total_ms"), "timing diagnostics are published separately")
	check(Landscape.candidate_count(Vector2i(72, 72)) == 3, "standard budget")
	check(Landscape.candidate_count(Vector2i(200, 200)) == 2, "giant budget")
	check(Landscape.candidate_count(Vector2i(400, 400)) == 1, "supergiant bounded budget")
	finish()

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Random map structural candidate tests passed")
	quit(0 if failures.is_empty() else 1)
