extends RefCounted

# Version 4 owns its candidate selection and publication sequence.
const Pipeline := preload("res://scripts/random_map_candidate_pipeline.gd")
const Support := preload("res://scripts/random_map_generation_support.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const NaturalLandscape := preload("res://scripts/random_map_natural_landscape.gd")
const Geography := preload("res://scripts/random_map_geography.gd")

static func generate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, prepared_geography: Dictionary = {}) -> Dictionary:
	if String(generator.get("map_type_id", "")) not in Geography.PROFILES:
		return {"generation_error": "skirmish_geography_profile_not_available"}
	var geography_started := Time.get_ticks_usec()
	var data := candidate(definition, size, seed, generator, progress, diagnostics, 0, prepared_geography)
	var fields: Dictionary = data["_fields"]
	var reserved: Dictionary = data["_reserved"]
	data.erase("_fields")
	data.erase("_reserved")
	data["scenery"] = Landscape.scenery(data, fields, reserved, seed ^ 0x665ACA, float(generator.get("decoration_density", 1.0)), Support._starting_entity_exclusion_cells(definition, size))

	data["ecology"]["composition"] = NaturalLandscape.composition(data)
	data["content_hash"] = ("geography_first_v4:" + Landscape.fingerprint(data)).sha256_text()
	diagnostics["candidate_count"] = 1
	diagnostics["total_ms"] = float(Time.get_ticks_usec() - geography_started) / 1000.0
	return data


static func candidate(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, candidate_index: int = 0, prepared_geography: Dictionary = {}) -> Dictionary:
	var pipeline := Pipeline.new(definition, size, seed, generator, progress, diagnostics, candidate_index, prepared_geography, 4, {"natural": true, "macro": true})
	pipeline.prepare_geography()
	pipeline.shape_coasts()
	pipeline.shape_relief()
	pipeline.reserve_routes()
	pipeline.place_economy()
	pipeline.place_forests()
	return pipeline.finish()
