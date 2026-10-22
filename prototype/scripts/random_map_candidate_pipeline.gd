extends RefCounted

# Shared stages operate on one candidate. Version drivers choose the recipe.
const Support := preload("res://scripts/random_map_generation_support.gd")
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
const RandomMapZones := preload("res://scripts/random_map_zones.gd")
const RandomMapWater := preload("res://scripts/random_map_water.gd")
const BuildingSpace := preload("res://scripts/random_map_building_space.gd")

var definition: Dictionary
var size: Vector2i
var seed: int
var generator: Dictionary
var progress: Callable
var diagnostics: Dictionary
var candidate: int
var prepared_geography: Dictionary
var version: int
var natural: bool
var macro: bool
var wild: bool
var watershed: bool
var river_network: bool
var started: int
var checkpoint: int
var starts: Array[Vector2]
var geography: Dictionary
var topology: String
var layout: Dictionary
var terrain: Array[int]
var water_features: Dictionary
var cliffs: Array[Vector2i]
var fields: Dictionary
var levels: Array[int]
var rock_ridges: Dictionary
var cliff_flat: Dictionary
var zone_contract: Dictionary
var zones: Dictionary
var naval_settings: Dictionary
var naval_zones: Array
var naval_reserved: Dictionary
var reserved_foundations: Array
var result: Dictionary
var graph: Dictionary
var reserved: Dictionary
var aquatic_reserved: Dictionary
var clusters: Array
var components: Dictionary
var economic_reserved: Dictionary
var marine_clusters: Array
var occupied: Dictionary
var marine_resources: Array
var grove_cells: Dictionary
var tree_sources: Dictionary
var marine_counts: Dictionary

func _init(match_definition: Dictionary, map_size: Vector2i, map_seed: int, settings: Dictionary, callback: Callable, measurements: Dictionary, index: int, prepared: Dictionary, recipe_version: int, capabilities: Dictionary) -> void:
	definition = match_definition
	size = map_size
	seed = map_seed
	generator = settings
	progress = callback
	diagnostics = measurements
	candidate = index
	prepared_geography = prepared
	version = recipe_version
	natural = bool(capabilities.get("natural", false))
	macro = bool(capabilities.get("macro", false))
	wild = bool(capabilities.get("wild", false))
	watershed = bool(capabilities.get("watershed", false))
	river_network = wild and bool(generator.get("river_network", false))


func prepare_geography() -> void:
	started = Time.get_ticks_usec()
	checkpoint = started
	starts = []
	for player in definition.get("players", []): starts.append(Vector2(player["start"]))
	geography = {}
	if watershed and prepared_geography.get("size") == size and int(prepared_geography.get("seed", -1)) == seed and prepared_geography.get("profile") == generator.get("map_type_id"):
		geography = prepared_geography.duplicate(true)
	else:
		geography = Recipe.geography(version, size, generator, seed, starts.size())
	topology = String(generator.get("topology", "inland"))
	layout = Recipe.topology(version, size, starts, generator, seed)


func shape_coasts() -> void:
	terrain = []
	terrain.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var point = Vector2(x + 0.5, y + 0.5)
			var water: bool = int(geography["terrain"][y * size.x + x]) == 1 if macro else NaturalTopology.water_at(point, layout) if natural else Topology.water_at(point, layout)
			terrain[y * size.x + x] = 1 if water else 0
			if river_network: terrain[y * size.x + x] = int(geography["terrain"][y * size.x + x])
		Support._report_row_progress(progress, y, size.y, 0.02, 0.15, "Создание суши и морей")
	if not macro: Support._smooth_water_mask(terrain, size)
	water_features = RandomMapWater.apply(terrain, size, seed, "" if river_network else topology)
	if river_network: Rivers.apply(terrain, geography["rivers"])
	Support._apply_shore_band(terrain, size, geography["rivers"] if watershed else {})
	cliffs = Support._profile_cliff_cells(size, String(generator.get("cliff_profile", "")), seed)
	checkpoint = Support._landscape_checkpoint(diagnostics, "coast", checkpoint)
	Support._report_progress(progress, 0.18, "Выбор рельефа и природных областей")


func shape_relief() -> void:
	fields = Recipe.fields(version, geography, size, terrain, starts, String(generator.get("map_type_id", "grasslands")), seed, candidate)
	if macro:
		fields = geography["fields"]
		Geography.settle(fields, size, starts)
	levels = fields["vertex_levels"]
	rock_ridges = {"cells": geography["ridge_cells"], "scenery": geography["ridge_scenery"]} if macro else Landscape.rock_ridges(size, terrain, starts, fields, cliffs, seed ^ 0xCF67)
	# Geometry preparation happens before shoreline classification. Remove any
	# edge footprint consumed by coast smoothing before publishing obstructions.
	if macro:
		var ridge_cells: Array[Vector2i] = []
		var river_barriers := WatershedWorld.Hydrology.RiverFalls.obstruction_cells(geography.get("rivers",{}))
		for cell in rock_ridges["cells"]:
			if int(terrain[cell.y * size.x + cell.x]) not in Landscape.WATER or river_barriers.has(cell): ridge_cells.append(cell)
		rock_ridges["cells"] = ridge_cells
	cliffs = rock_ridges["cells"]
	var ordinary_cliffs: Array[Vector2i] = []
	var waterfall_cliffs: Dictionary = {}
	for item in rock_ridges["scenery"]:
		if item.get("river_barrier",false):
			for cell in item["occupied_cells"]: waterfall_cliffs[cell] = true
	for cell in cliffs:
		if not waterfall_cliffs.has(cell): ordinary_cliffs.append(cell)
	Support._apply_cliff_elevation(levels, size, ordinary_cliffs)
	cliff_flat = {}
	for cell in ordinary_cliffs: cliff_flat[cell] = true
	Landscape.relax_heights(levels, size, cliff_flat)
	zone_contract = generator.get("strategic_zone_contract", {}).duplicate(true)
	zone_contract["alliance_aware"] = true
	zones = RandomMapZones.build(definition.get("players", []), size, terrain, cliffs, zone_contract)
	naval_settings = generator.get("naval_start", {})
	naval_zones = []
	if bool(generator.get("requires_naval_starts", false)):
		var naval_obstructions: Dictionary = {}
		for cell in cliffs: naval_obstructions[cell]=true
		naval_zones = Support._generate_naval_start_zones(definition.get("players", []), size, terrain, naval_settings,naval_obstructions)
	naval_reserved = Support._reserved_naval_cells(naval_zones, maxi(0, int(naval_settings.get("dock_footprint_radius_cells", 1))))
	reserved_foundations = naval_reserved.keys()
	reserved_foundations.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	result = {"size": size, "seed": seed, "generator_version": NaturalLandscape.VERSION if natural else Landscape.VERSION, "theme": "temperate_v3" if natural else "temperate_v2", "environment_pack": "aoe2_temperate",
		"terrain_ids": terrain, "vertex_levels": levels, "cliff_cells": cliffs, "cliff_obstructions": rock_ridges["scenery"], "strategic_zones": zones, "water_features": water_features,
		"naval_start_zones": naval_zones, "reserved_foundation_cells": reserved_foundations, "resources": [], "scenery": [],
		"generation_candidates": fields.get("generation_candidates", {})}
	if macro:
		result["generator_version"] = WatershedWorld.VERSION if watershed else WildIslands.VERSION if wild else Geography.VERSION
		result["theme"] = "watershed_world_v6" if watershed else "wild_islands_v5" if wild else "geography_first_v4"
		result["geography"] = {"order": ["land_and_sea", "relief_and_woodland", "settlements", "routes", "resources"], "woodland_regions": geography["woodland_regions"], "landmass_seeds": geography["landmass_seeds"]}
	if river_network:
		result["rivers"] = geography["rivers"]
		result["geography"]["order"] = ["islands", "watersheds_and_rivers", "settlements", "resources"]
		water_features["rivers"] = Rivers.inspect(result["rivers"])
	if watershed:
		result["lakes"] = geography["lakes"]
		result["fords"] = geography["fords"]
		result["geography"]["shape_kind"] = geography["shape_kind"]
		result["geography"]["order"] = ["landforms", "relief", "watersheds_lakes_rivers_fords", "settlements", "resources"]
	if natural: NaturalLandscape.paint_ground(result, fields)
	else: Landscape.paint_ground(result, fields)
	checkpoint = Support._landscape_checkpoint(diagnostics, "fields_and_relief", checkpoint)
	Support._report_progress(progress, 0.43, "Резервирование проходов и расширений")


func reserve_routes() -> void:
	graph = {"reserved": {}, "edges": []} if wild else LandscapeNavigation.routes(definition, result, fields if natural else {})
	reserved = graph["reserved"]
	reserved.merge(naval_reserved, true)
	if not macro: reserved.merge(Support._clear_start_corridors(terrain, size, starts, {}, topology), true)
	LandscapeNavigation.reserve_naval_access(definition, result, reserved)
	for cell in cliffs:
		for y in range(maxi(0, cell.y - 1), mini(size.y, cell.y + 2)):
			for x in range(maxi(0, cell.x - 1), mini(size.x, cell.x + 2)): reserved[Vector2i(x, y)] = true
	if watershed:
		reserved.merge(WatershedWorld.Hydrology.RiverFalls.pool_reservations(size,terrain,geography["rivers"]),true)
	# Exclusion from resource placement does not prohibit construction. In
	# particular, a small island may fit its expansion inside the start's
	# resource-free square. Keep real routes, docks and geological reserves.
	var building_exclusions := reserved.duplicate() if watershed else {}
	reserved.merge(Support._starting_entity_exclusion_cells(definition, size), true)
	# Rivers exclude trees and land resources. Fish retain the actual dock,
	# route and obstruction reservations instead of inheriting that blanket ban.
	aquatic_reserved = reserved.duplicate()
	if watershed:
		# Shore fish may inhabit natural Shallows, but must not consume the
		# infantry corridor of a designated ford or its immediate approaches.
		for ford in result.get("fords",[]):
			for cell in ford["cells"]:
				for dy in range(-1,2):
					for dx in range(-1,2):aquatic_reserved[cell+Vector2i(dx,dy)]=true
	if river_network:
		for i in range(terrain.size()):
			if geography["rivers"]["mask"][i] != 0:
				var cell := Vector2i(i % size.x, i / size.x)
				reserved[cell] = true
				if watershed: building_exclusions[cell] = true
	if watershed:
		BuildingSpace.reserve(definition, result, fields, reserved, building_exclusions)
	result["region_graph"] = {"schema_version": 1, "edges": graph["edges"]}
	checkpoint = Support._landscape_checkpoint(diagnostics, "routes", checkpoint)
	Support._report_progress(progress, 0.57, "Размещение стартовых и нейтральных ресурсов")


func place_economy() -> void:
	clusters = generator.get("resource_clusters", []).duplicate(true)
	clusters.append_array(Support._neutral_source_resource_clusters(size, terrain, starts, generator.get("source_profile", {}), zones, seed ^ 0x673CA))
	clusters.append_array(Support._naval_resource_clusters(naval_zones, generator.get("naval_resource_clusters", [])))
	components = Support._land_component_lookup(size, terrain, cliffs)
	economic_reserved = reserved.duplicate() if macro else reserved
	if macro:
		# Preserve the planned woodland interior while distributing economy.
		# Paths and local settlement terraces already have their own reservations.
		for i in range(terrain.size()):
			if int(fields["forest_potential"][i]) != 0 and float(fields["forest_strength"][i]) > 0.72:
				economic_reserved[Vector2i(i % size.x, i / size.x)] = true
	result["resources"] = Support._generate_resource_clusters(clusters, size, seed ^ 0x53AB19, terrain, economic_reserved, components)
	if not wild: Support._complete_mineral_expansions(result, starts, economic_reserved, components, seed ^ 0x346C9)
	# Marine ecology depends on available water, not on the starting-dock flag.
	# Use a separate random stream so changes at sea do not reroll land resources.
	marine_clusters = Support._neutral_fish_clusters(size, terrain, seed ^ 0x26731, aquatic_reserved, result["resources"], geography["rivers"]["mask"] if river_network else PackedByteArray(),geography["rivers"].get("surface",{}) if watershed else {})
	if watershed: Support._populate_lakes(marine_clusters, result["lakes"], size, terrain, aquatic_reserved, result["resources"], seed ^ 0x1A4E)
	occupied = aquatic_reserved.duplicate()
	for resource in result["resources"]: occupied[Vector2i(resource["position"])] = true
	marine_resources = Support._generate_resource_clusters(marine_clusters, size, seed ^ 0x693D2, terrain, occupied)
	result["resources"].append_array(marine_resources)
	for resource in marine_resources:
		if resource["kind"] != "shore_fish": continue
		var approach: Variant = Support._shore_fish_approach(Vector2i(resource["position"]), size, terrain, occupied)
		if approach is Vector2i: reserved[approach] = true
	LandscapeNavigation.protect_economy(definition, result, reserved, fields if macro else {})
	grove_cells = {}
	for resource in result["resources"]:
		if String(resource.get("kind", "")) == "tree": grove_cells[Vector2i(resource["position"])] = true
	grove_cells.merge(cliff_flat, true)
	if watershed:
		for clearing in result.get("building_clearings", []):
			var origin: Vector2i = clearing["origin"]
			for y in range(origin.y, origin.y + clearing["width"]):
				for x in range(origin.x, origin.x + clearing["width"]): grove_cells[Vector2i(x, y)] = true
		for lake in result["lakes"]:
			for i in lake["cells"]: grove_cells[Vector2i(i % size.x, i / size.x)] = true
		for i in range(terrain.size()):
			if terrain[i] == 4: grove_cells[Vector2i(i % size.x, i / size.x)] = true
	Landscape.relax_heights(levels, size, grove_cells)
	if watershed: WatershedWorld.Hydrology.refresh_lake_levels(size, levels, result["lakes"])
	for item in rock_ridges["scenery"]:
		var center = Vector2i(item["position"])
		item["source_elevation"] = float(levels[center.y * (size.x + 1) + center.x])
		if item.get("river_barrier",false):
			var vertex: int = center.y*(size.x+1)+center.x
			var actual: float = (levels[vertex]+levels[vertex+1]+levels[vertex+size.x+1]+levels[vertex+size.x+2])*0.25
			item["cliff_screen_offset"] = Vector2(0,(actual-float(item["river_crest_level"]))*16.0)
	if natural: NaturalLandscape.paint_ground(result, fields)
	else: Landscape.paint_ground(result, fields)
	checkpoint = Support._landscape_checkpoint(diagnostics, "economy", checkpoint)
	Support._report_progress(progress, 0.77, "Создание лесных массивов и опушек")


func place_forests() -> void:
	if natural: NaturalLandscape.forests(result, fields, reserved, seed ^ 0x561332, macro)
	else: Landscape.forests(result, fields, reserved, seed ^ 0x561332)
	Landscape.paint_resource_grounds(result)
	Landscape.paint_cliff_grounds(result)
	if river_network: Rivers.apply(terrain, geography["rivers"])
	if watershed:
		WatershedWorld.Hydrology.RiverFalls.restore_pools(size,terrain,levels,result["rivers"])
		WatershedWorld.Hydrology.RiverFalls.update_presentation(size,levels,rock_ridges["scenery"])
	checkpoint = Support._landscape_checkpoint(diagnostics, "forests", checkpoint)
	Support._report_progress(progress, 0.91, "Размещение камней и лесных деталей")


func finish() -> Dictionary:
	if not natural: result["scenery"] = Landscape.scenery(result, fields, reserved, seed ^ 0x665ACA, float(generator.get("decoration_density", 1.0)), Support._starting_entity_exclusion_cells(definition, size))
	tree_sources = {"ror": 0, "aoe2": 0}
	for resource in result["resources"]:
		if resource.get("kind", "") != "tree": continue
		var source = "aoe2" if resource.has("environment_asset") else "ror"
		tree_sources[source] += 1
	result["ecology"] = {"forest_cells": result["forest_mask"].count(1), "tree_sources": tree_sources, "reserved_route_cells": reserved.size(), "material_policy": "watershed_world_v6" if watershed else "wild_islands_v5" if wild else "geography_first_v4" if macro else "temperate_natural_v3" if natural else "temperate_connected_v2"}
	marine_counts = {"shore_fish": 0, "deep_fish": 0, "whale": 0}
	for resource in result["resources"]:
		var kind = String(resource.get("kind", ""))
		if marine_counts.has(kind): marine_counts[kind] += 1
	result["marine_resources"] = marine_counts
	if natural:
		result["_fields"] = fields
		result["_reserved"] = reserved
	else: result["content_hash"] = Landscape.fingerprint(result)
	Support._landscape_checkpoint(diagnostics, "scenery_and_hash", checkpoint)
	diagnostics["total_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	Support._report_progress(progress, 1.0, "Карта готова")
	return result
