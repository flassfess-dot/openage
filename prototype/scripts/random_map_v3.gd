extends RefCounted

# Version 3 owns its candidate selection and publication sequence.
const Pipeline := preload("res://scripts/random_map_candidate_pipeline.gd")
const Support := preload("res://scripts/random_map_generation_support.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const NaturalLandscape := preload("res://scripts/random_map_natural_landscape.gd")

static func generate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, prepared_geography: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	var selected: Dictionary = {}
	var selected_diagnostics: Dictionary = {}
	var scores: Array = []
	var best := -INF
	var winner := 0
	var count := Landscape.candidate_count(size)
	for candidate_index in range(count):
		var candidate_diagnostics: Dictionary = {}
		var candidate_progress := func(value: float, stage: String): Support._report_progress(progress, (candidate_index + value * 0.95) / float(count), "%s · вариант %d/%d" % [stage, candidate_index + 1, count])
		var data := candidate(definition, size, seed, generator, candidate_progress, candidate_diagnostics, candidate_index)
		var evaluation := NaturalLandscape.evaluate(definition, data)
		evaluation["index"] = candidate_index
		evaluation["seed"] = seed ^ (0x2A63B91 + candidate_index * 104729)
		scores.append(evaluation)
		if selected.is_empty() or float(evaluation["score"]) > best:
			best = float(evaluation["score"])
			selected = data
			selected_diagnostics = candidate_diagnostics
			winner = candidate_index
	var selected_fields: Dictionary = selected["_fields"]
	var reserved: Dictionary = selected["_reserved"]
	selected.erase("_fields")
	selected.erase("_reserved")
	selected["generation_candidates"] = {"scope": "final_landscape", "candidate_count": count, "scores": scores,
		"selected_candidate_index": winner, "selected_candidate_seed": int(scores[winner]["seed"])}
	selected["ecology"]["composition"] = scores[winner]["composition"]
	Support._report_progress(progress, 0.99, "Размещение природных деталей")
	selected["scenery"] = Landscape.scenery(selected, selected_fields, reserved, seed ^ 0x665ACA, float(generator.get("decoration_density", 1.0)), Support._starting_entity_exclusion_cells(definition, size))
	selected["content_hash"] = NaturalLandscape.fingerprint(selected)
	diagnostics.merge(selected_diagnostics, true)
	diagnostics["candidate_count"] = count
	diagnostics["total_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	Support._report_progress(progress, 1.0, "Карта готова")
	return selected


static func candidate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, candidate_index: int = 0, prepared_geography: Dictionary = {}) -> Dictionary:
	var pipeline := Pipeline.new(definition, size, seed, generator, progress, diagnostics, candidate_index, prepared_geography, 3, {"natural": true})
	pipeline.prepare_geography()
	pipeline.shape_coasts()
	pipeline.shape_relief()
	pipeline.reserve_routes()
	pipeline.place_economy()
	pipeline.place_forests()
	return pipeline.finish()
