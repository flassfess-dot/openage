class_name RoRRandomMapGenerator
extends RefCounted

const Support := preload("res://scripts/random_map_generation_support.gd")
const V2 := preload("res://scripts/random_map_v2.gd")
const V3 := preload("res://scripts/random_map_v3.gd")
const V4 := preload("res://scripts/random_map_v4.gd")
const V5 := preload("res://scripts/random_map_v5.gd")
const V6 := preload("res://scripts/random_map_v6.gd")

const ProceduralNoise := preload("res://scripts/procedural_noise.gd")
const Recipe := preload("res://scripts/random_map_recipe.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const LandscapeNavigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const NaturalLandscape := preload("res://scripts/random_map_natural_landscape.gd")
const NaturalTopology := preload("res://scripts/random_map_natural_topology.gd")
const Geography := preload("res://scripts/random_map_geography.gd")
const WildIslands := preload("res://scripts/random_map_wild_islands.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
const WatershedWorld := preload("res://scripts/random_map_watershed_world.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const RandomMapZones := preload("res://scripts/random_map_zones.gd")
const RandomMapSampler := preload("res://scripts/random_map_sampler.gd")
const RandomMapWater := preload("res://scripts/random_map_water.gd")
const PALM_TREES := [113, 114, 121, 129, 150, 152, 153]
const TREE_GRAPHICS := {113: 648, 114: 649, 121: 650, 129: 651, 134: 601, 136: 603, 140: 607, 141: 608, 142: 609, 143: 610, 144: 611, 146: 613, 147: 614, 150: 617, 152: 619, 153: 620, 161: 653, 194: 623, 195: 627, 198: 654, 203: 655, 226: 656, 365: 628, 367: 631}

static func generate(match_definition: Dictionary, progress_callback: Callable = Callable(), diagnostics: Dictionary = {}, prepared_geography: Dictionary = {}) -> Dictionary:
	var generator: Dictionary = match_definition.get("map", {}).get("generator", {})
	if String(generator.get("type", "")) == Landscape.TYPE:
		var map: Dictionary = match_definition.get("map", {})
		Support._report_progress(progress_callback, 0.0, "Подготовка ландшафта")
		return _landscape_skirmish_map(match_definition, map.get("size", Vector2i(24, 24)), int(map.get("seed", 1)), generator, progress_callback, diagnostics, prepared_geography)
	return Support.generate(match_definition, progress_callback, diagnostics, prepared_geography)


static func _report_row_progress(progress_callback: Callable, row: int, row_count: int, start_value: float, end_value: float, stage: String) -> void:
	Support._report_row_progress(progress_callback, row, row_count, start_value, end_value, stage)


static func _report_progress(progress_callback: Callable, value: float, stage: String) -> void:
	Support._report_progress(progress_callback, value, stage)


static func _naval_resource_clusters(zones: Array, templates: Array) -> Array:
	return Support._naval_resource_clusters(zones, templates)


static func _neutral_fish_clusters(size: Vector2i, terrain_ids: Array[int], seed: int, blocked_cells: Dictionary = {}, existing_resources: Array = []) -> Array:
	return Support._neutral_fish_clusters(size, terrain_ids, seed, blocked_cells, existing_resources)


static func _shore_fish_approach(cell: Vector2i, size: Vector2i, terrain_ids: Array[int], occupied: Dictionary) -> Variant:
	return Support._shore_fish_approach(cell, size, terrain_ids, occupied)


static func _clear_start_corridors(terrain_ids: Array[int], size: Vector2i, starts: Array[Vector2], source_profile: Dictionary, topology: String) -> Dictionary:
	return Support._clear_start_corridors(terrain_ids, size, starts, source_profile, topology)


static func _neutral_source_resource_clusters(size: Vector2i, terrain_ids: Array[int], starts: Array[Vector2], source_profile: Dictionary, strategic_zones: Dictionary, seed: int) -> Array:
	return Support._neutral_source_resource_clusters(size, terrain_ids, starts, source_profile, strategic_zones, seed)


static func _complete_mineral_expansions(map_data: Dictionary, starts: Array[Vector2], reserved: Dictionary, components: Dictionary, seed: int) -> void:
	Support._complete_mineral_expansions(map_data, starts, reserved, components, seed)


static func _land_component_lookup(size: Vector2i, terrain_ids: Array[int], cliff_cells: Array[Vector2i]) -> Dictionary:
	return Support._land_component_lookup(size, terrain_ids, cliff_cells)


static func _seeded_water_cell(cell: Vector2i, size: Vector2i, starts: Array[Vector2], topology: String, generator: Dictionary, seed: int) -> bool:
	return Support._seeded_water_cell(cell, size, starts, topology, generator, seed)


static func _smooth_water_mask(terrain_ids: Array[int], size: Vector2i) -> void:
	Support._smooth_water_mask(terrain_ids, size)


static func _smooth_noise(point: Vector2, scale: float, seed: int) -> float:
	return Support._smooth_noise(point, scale, seed)


static func _hash_noise(cell: Vector2i, seed: int) -> float:
	return Support._hash_noise(cell, seed)


static func _profile_cliff_cells(size: Vector2i, cliff_profile: String, seed: int) -> Array[Vector2i]:
	return Support._profile_cliff_cells(size, cliff_profile, seed)


static func _apply_cliff_elevation(levels: Array[int], size: Vector2i, cliff_cells: Array[Vector2i]) -> void:
	Support._apply_cliff_elevation(levels, size, cliff_cells)


static func _apply_shore_band(terrain_ids: Array[int], size: Vector2i) -> void:
	Support._apply_shore_band(terrain_ids, size)


static func _fixed_source_map(size: Vector2i, seed: int, generator: Dictionary) -> Dictionary:
	return Support._fixed_source_map(size, seed, generator)


static func _generate_naval_start_zones(players: Array, size: Vector2i, terrain_ids: Array[int], settings: Dictionary = {}) -> Array:
	return Support._generate_naval_start_zones(players, size, terrain_ids, settings)


static func _nearest_dock_anchor(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, allowed_surface_ids: Array, reserved_cells: Dictionary, water_guarantee: Dictionary = {}) -> Variant:
	return Support._nearest_dock_anchor(origin, size, terrain_ids, footprint_radius_cells, allowed_surface_ids, reserved_cells, water_guarantee)


static func _dock_anchor_valid(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, allowed_surface_ids: Array, reserved_cells: Dictionary, water_guarantee: Dictionary = {}) -> bool:
	return Support._dock_anchor_valid(origin, size, terrain_ids, footprint_radius_cells, allowed_surface_ids, reserved_cells, water_guarantee)


static func _dock_water_egress_cells(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, reserved_cells: Dictionary) -> Array:
	return Support._dock_water_egress_cells(origin, size, terrain_ids, footprint_radius_cells, reserved_cells)


static func _array_has_int(values: Array, expected: int) -> bool:
	return Support._array_has_int(values, expected)


static func _nearest_staging_pair(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, water_guarantee: Dictionary = {}, reserved_cells: Dictionary = {}) -> Dictionary:
	return Support._nearest_staging_pair(origin, size, terrain_ids, footprint_radius_cells, water_guarantee, reserved_cells)


static func _perimeter_domain_candidates(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, domain: String, reserved_cells: Dictionary = {}, clearance_cells: int = 0) -> Array:
	return Support._perimeter_domain_candidates(origin, size, terrain_ids, footprint_radius_cells, domain, reserved_cells, clearance_cells)


static func _domain_clearance_cells(size: Vector2i, terrain_ids: Array[int], domain: String, clearance_cells: int) -> Dictionary:
	return Support._domain_clearance_cells(size, terrain_ids, domain, clearance_cells)


static func _cached_domain_candidate_count_near(origin: Vector2, guarantee: Dictionary, size: Vector2i) -> int:
	return Support._cached_domain_candidate_count_near(origin, guarantee, size)


static func _reserved_naval_cells(zones: Array, footprint_radius_cells: int) -> Dictionary:
	return Support._reserved_naval_cells(zones, footprint_radius_cells)


static func _reserve_zone_cells(result: Dictionary, zone_value: Variant, footprint_radius_cells: int) -> void:
	Support._reserve_zone_cells(result, zone_value, footprint_radius_cells)


static func _base_terrain_id(cell: Vector2i, size: Vector2i, border: Dictionary, shore_width: int) -> int:
	return Support._base_terrain_id(cell, size, border, shore_width)


static func _apply_terrain_patches(terrain_ids: Array[int], size: Vector2i, patches: Array, seed: int) -> void:
	Support._apply_terrain_patches(terrain_ids, size, patches, seed)


static func _apply_hill(levels: Array[int], size: Vector2i, hill_value: Variant) -> void:
	Support._apply_hill(levels, size, hill_value)


static func _generate_resource_clusters(clusters: Array, size: Vector2i, seed: int, terrain_ids: Array[int], blocked_cells: Dictionary = {}, land_components: Dictionary = {}) -> Array:
	return Support._generate_resource_clusters(clusters, size, seed, terrain_ids, blocked_cells, land_components)


static func _starting_entity_exclusion_cells(match_definition: Dictionary, size: Vector2i) -> Dictionary:
	return Support._starting_entity_exclusion_cells(match_definition, size)


static func _nearest_land(position: Vector2, size: Vector2i, terrain_ids: Array[int]) -> Vector2:
	return Support._nearest_land(position, size, terrain_ids)


static func _free_land_approach_cell(resource_cell: Vector2i, size: Vector2i, terrain_ids: Array[int], blocked_cells: Dictionary, land_components: Dictionary, required_component: int) -> Variant:
	return Support._free_land_approach_cell(resource_cell, size, terrain_ids, blocked_cells, land_components, required_component)


static func _resource_cell_has_spacing(cell: Vector2i, blocked_cells: Dictionary) -> bool:
	return Support._resource_cell_has_spacing(cell, blocked_cells)


static func _nearest_domain(position: Vector2, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0, land_components: Dictionary = {}, required_component: int = -1, preserve_approach: bool = false, enforce_spacing: bool = false) -> Vector2:
	return Support._nearest_domain(position, size, terrain_ids, placement_domain, blocked_cells, minimum_clearance_cells, land_components, required_component, preserve_approach, enforce_spacing)


static func _nearest_domain_within(position: Vector2, guarantee_origin: Vector2, maximum_distance: float, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0, land_components: Dictionary = {}, required_component: int = -1, preserve_approach: bool = false, enforce_spacing: bool = false) -> Variant:
	return Support._nearest_domain_within(position, guarantee_origin, maximum_distance, size, terrain_ids, placement_domain, blocked_cells, minimum_clearance_cells, land_components, required_component, preserve_approach, enforce_spacing)


static func _cell_matches_domain_with_clearance(cell: Vector2i, size: Vector2i, terrain_ids: Array[int], placement_domain: String, minimum_clearance_cells: int) -> bool:
	return Support._cell_matches_domain_with_clearance(cell, size, terrain_ids, placement_domain, minimum_clearance_cells)


static func _cell_matches_domain(cell: Vector2i, size: Vector2i, terrain_ids: Array[int], placement_domain: String) -> bool:
	return Support._cell_matches_domain(cell, size, terrain_ids, placement_domain)


static func _cell_hash(cell: Vector2i, seed: int) -> int:
	return Support._cell_hash(cell, seed)


static func _vector2(value: Variant) -> Vector2:
	return Support._vector2(value)


static func _landscape_skirmish_map(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, prepared_geography: Dictionary = {}) -> Dictionary:
	match int(generator.get("version", -1)):
		2:
			return V2.generate(definition, size, seed, generator, progress, diagnostics, prepared_geography)
		3:
			return V3.generate(definition, size, seed, generator, progress, diagnostics, prepared_geography)
		4:
			return V4.generate(definition, size, seed, generator, progress, diagnostics, prepared_geography)
		5:
			return V5.generate(definition, size, seed, generator, progress, diagnostics, prepared_geography)
		6:
			return V6.generate(definition, size, seed, generator, progress, diagnostics, prepared_geography)
	return {"generation_error": "random_map_generator_version_unsupported"}


static func _landscape_candidate_map(definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary, progress: Callable, diagnostics: Dictionary, candidate: int = 0, prepared_geography: Dictionary = {}) -> Dictionary:
	match int(generator.get("version", -1)):
		2:
			return V2.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)
		3:
			return V3.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)
		4:
			return V4.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)
		5:
			return V5.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)
		6:
			return V6.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)
	# Historical direct candidate queries use the connected v2 recipe as fallback.
	# generate() still rejects unsupported versions before reaching this helper.
	return V2.candidate(definition, size, seed, generator, progress, diagnostics, candidate, prepared_geography)


static func _landscape_checkpoint(diagnostics: Dictionary, stage: String, started: int) -> int:
	return Support._landscape_checkpoint(diagnostics, stage, started)
