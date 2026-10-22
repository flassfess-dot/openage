extends RefCounted

# Version 2 owns its candidate selection and publication sequence.
const Pipeline := preload("res://scripts/random_map_candidate_pipeline.gd")
const Support := preload("res://scripts/random_map_generation_support.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const NaturalLandscape := preload("res://scripts/random_map_natural_landscape.gd")

static func generate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, prepared_geography: Dictionary = {}) -> Dictionary:
	return candidate(definition, size, seed, generator, progress, diagnostics)


static func candidate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, candidate_index: int = 0, prepared_geography: Dictionary = {}) -> Dictionary:
	var pipeline := Pipeline.new(definition, size, seed, generator, progress, diagnostics, candidate_index, prepared_geography, 2, {})
	pipeline.prepare_geography()
	pipeline.shape_coasts()
	pipeline.shape_relief()
	pipeline.reserve_routes()
	pipeline.place_economy()
	pipeline.place_forests()
	return pipeline.finish()
