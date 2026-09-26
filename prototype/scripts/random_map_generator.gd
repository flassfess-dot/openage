class_name RoRRandomMapGenerator
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")
const BROADLEAF_TREES := [134, 140, 141, 142, 143, 144, 146, 147, 195, 365, 367]
const CONIFER_TREES := [136, 161, 194, 198, 203, 226]
const PALM_TREES := [113, 114, 121, 129, 150, 152, 153]
const TREE_GRAPHICS := {113: 648, 114: 649, 121: 650, 129: 651, 134: 601, 136: 603, 140: 607, 141: 608, 142: 609, 143: 610, 144: 611, 146: 613, 147: 614, 150: 617, 152: 619, 153: 620, 161: 653, 194: 623, 195: 627, 198: 654, 203: 655, 226: 656, 365: 628, 367: 631}


static func generate(match_definition: Dictionary) -> Dictionary:
	var map: Dictionary = match_definition.get("map", {})
	var size: Vector2i = map.get("size", Vector2i(24, 24))
	var seed := int(map.get("seed", 1))
	var generator: Dictionary = map.get("generator", {})
	if String(generator.get("type", "")) == "fixed_source":
		return _fixed_source_map(size, seed, generator)
	if String(generator.get("type", "")) == "seeded_skirmish_v1":
		return _seeded_skirmish_map(match_definition, size, seed, generator)
	var water_border: Dictionary = generator.get("water_border", {})
	var shore_width := maxi(0, int(water_border.get("shore_width", 1)))
	var terrain_ids: Array[int] = []
	terrain_ids.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			terrain_ids[y * size.x + x] = _base_terrain_id(Vector2i(x, y), size, water_border, shore_width)
	_apply_terrain_patches(terrain_ids, size, generator.get("terrain_patches", []), seed)
	var naval_start_settings: Dictionary = generator.get("naval_start", {})
	var naval_start_zones := _generate_naval_start_zones(match_definition.get("players", []), size, terrain_ids, naval_start_settings)
	var reserved_naval_cells := _reserved_naval_cells(naval_start_zones, maxi(0, int(naval_start_settings.get("dock_footprint_radius_cells", 1))))
	var resource_exclusion_cells := reserved_naval_cells.duplicate()
	resource_exclusion_cells.merge(_starting_entity_exclusion_cells(match_definition, size), true)
	var reserved_foundation_cells: Array = reserved_naval_cells.keys()
	reserved_foundation_cells.sort_custom(func(left, right):
		var left_cell := Vector2i(left)
		var right_cell := Vector2i(right)
		return left_cell.y < right_cell.y or (left_cell.y == right_cell.y and left_cell.x < right_cell.x)
	)

	var vertex_levels: Array[int] = []
	vertex_levels.resize((size.x + 1) * (size.y + 1))
	vertex_levels.fill(0)
	for hill_value in generator.get("hills", []):
		_apply_hill(vertex_levels, size, hill_value)

	return {
		"size": size,
		"seed": seed,
		"terrain_ids": terrain_ids,
		"vertex_levels": vertex_levels,
		"resources": _generate_resource_clusters(generator.get("resource_clusters", []), size, seed, terrain_ids, resource_exclusion_cells),
		"naval_start_zones": naval_start_zones,
		"reserved_foundation_cells": reserved_foundation_cells,
	}


static func _seeded_skirmish_map(match_definition: Dictionary, size: Vector2i, seed: int, generator: Dictionary) -> Dictionary:
	var starts: Array[Vector2] = []
	for player_value in match_definition.get("players", []):
		starts.append(_vector2(player_value.get("start", [])))
	var terrain_ids: Array[int] = []
	terrain_ids.resize(size.x * size.y)
	var topology := String(generator.get("topology", "inland"))
	for y in range(size.y):
		for x in range(size.x):
			terrain_ids[y * size.x + x] = 1 if _seeded_water_cell(Vector2i(x, y), size, starts, topology, generator, seed) else 0
	_smooth_water_mask(terrain_ids, size)
	_apply_source_terrain_groups(terrain_ids, size, starts, generator.get("source_profile", {}), seed)
	var start_corridors := _clear_start_corridors(terrain_ids, size, starts, generator.get("source_profile", {}), topology)
	_apply_shore_band(terrain_ids, size)
	_apply_water_detail(terrain_ids, size, seed)
	var cliff_cells: Array[Vector2i] = _profile_cliff_cells(size, String(generator.get("cliff_profile", "")), seed)
	var naval_start_settings: Dictionary = generator.get("naval_start", {})
	var naval_start_zones: Array = []
	if bool(generator.get("requires_naval_starts", false)):
		naval_start_zones = _generate_naval_start_zones(match_definition.get("players", []), size, terrain_ids, naval_start_settings)
	var reserved_naval_cells := _reserved_naval_cells(naval_start_zones, maxi(0, int(naval_start_settings.get("dock_footprint_radius_cells", 1))))
	var resource_exclusion_cells := reserved_naval_cells.duplicate()
	resource_exclusion_cells.merge(_starting_entity_exclusion_cells(match_definition, size), true)
	resource_exclusion_cells.merge(start_corridors, true)
	for cliff_cell in cliff_cells:
		for y in range(maxi(0, cliff_cell.y - 1), mini(size.y, cliff_cell.y + 2)):
			for x in range(maxi(0, cliff_cell.x - 1), mini(size.x, cliff_cell.x + 2)):
				resource_exclusion_cells[Vector2i(x, y)] = true
	var reserved_foundation_cells: Array = reserved_naval_cells.keys()
	reserved_foundation_cells.sort_custom(func(left, right):
		var left_cell := Vector2i(left)
		var right_cell := Vector2i(right)
		return left_cell.y < right_cell.y or (left_cell.y == right_cell.y and left_cell.x < right_cell.x)
	)
	var vertex_levels: Array[int] = []
	vertex_levels.resize((size.x + 1) * (size.y + 1))
	vertex_levels.fill(0)
	for hill_value in generator.get("hills", []):
		_apply_hill(vertex_levels, size, hill_value)
	for relief_value in _seeded_relief_hills(size, starts, terrain_ids, seed):
		_apply_relief_hill(vertex_levels, size, terrain_ids, relief_value)
	_apply_cliff_elevation(vertex_levels, size, cliff_cells)
	var resource_clusters: Array = generator.get("resource_clusters", []).duplicate(true)
	resource_clusters.append_array(_neutral_source_resource_clusters(size, terrain_ids, starts, generator.get("source_profile", {}), seed))
	resource_clusters.append_array(_neutral_forest_clusters(size, terrain_ids, starts, generator.get("source_profile", {}), seed))
	resource_clusters.append_array(_naval_resource_clusters(naval_start_zones, generator.get("naval_resource_clusters", [])))
	if not naval_start_zones.is_empty():
		resource_clusters.append_array(_neutral_fish_clusters(size, terrain_ids, seed))
	var land_components := _land_component_lookup(size, terrain_ids, cliff_cells)
	var generated_resources := _generate_resource_clusters(resource_clusters, size, seed, terrain_ids, resource_exclusion_cells, land_components)
	return {
		"size": size,
		"seed": seed,
		"terrain_ids": terrain_ids,
		"vertex_levels": vertex_levels,
		"cliff_cells": cliff_cells,
		"scenery": _seeded_rock_scenery(size, terrain_ids, starts, generated_resources, seed),
		"resources": generated_resources,
		"naval_start_zones": naval_start_zones,
		"reserved_foundation_cells": reserved_foundation_cells,
	}


static func _naval_resource_clusters(zones: Array, templates: Array) -> Array:
	var result: Array = []
	var maximum_count := 0
	for template_value in templates:
		maximum_count = maxi(maximum_count, int(template_value.get("count", 0)))
	# Allocate one guaranteed resource per player per pass. This prevents an early
	# naval start from consuming every valid open-water cell shared with a later one.
	for resource_index in range(maximum_count):
		for zone_value in zones:
			var zone: Dictionary = zone_value
			var dock_position := Vector2(zone.get("dock_position", Vector2.ZERO))
			var water_staging := Vector2(zone.get("water_staging", dock_position))
			var outward := (water_staging - dock_position).normalized()
			if outward.length_squared() <= 0.000001:
				outward = Vector2.LEFT
			for template_value in templates:
				var template: Dictionary = template_value
				if resource_index >= int(template.get("count", 0)):
					continue
				var cluster := template.duplicate(true)
				var center := water_staging + outward * maxf(0.0, float(template.get("water_offset", 0.0)))
				cluster["center"] = [center.x, center.y]
				cluster["count"] = 1
				cluster["guarantee_team"] = int(zone.get("team", 0))
				cluster["guarantee_origin"] = [water_staging.x, water_staging.y]
				cluster.erase("water_offset")
				result.append(cluster)
	return result


static func _neutral_fish_clusters(size: Vector2i, terrain_ids: Array[int], seed: int) -> Array:
	var open_cells: Array[Vector2i] = []
	var shore_cells: Array[Vector2i] = []
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			var terrain_id := int(terrain_ids[y * size.x + x])
			if terrain_id in TerrainRules.OPEN_WATER_TERRAIN_IDS:
				var coastal := false
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = Vector2i(x, y) + Vector2i(offset)
					if int(terrain_ids[neighbor.y * size.x + neighbor.x]) not in TerrainRules.OPEN_WATER_TERRAIN_IDS:
						coastal = true
						break
				if coastal:
					shore_cells.append(Vector2i(x, y))
				else:
					open_cells.append(Vector2i(x, y))
			elif terrain_id == 4:
				shore_cells.append(Vector2i(x, y))
	var school_count := mini(120, open_cells.size() / 145)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x46A451
	var result: Array = []
	for index in range(school_count):
		var cell := open_cells[rng.randi_range(0, open_cells.size() - 1)]
		var center := Vector2(cell) + Vector2(0.5, 0.5)
		result.append({"kind": "deep_fish", "placement_domain": "water", "minimum_domain_clearance_cells": 2, "center": [center.x, center.y], "count": rng.randi_range(2, 3), "radius": 1.5, "amount": 200})
	for index in range(mini(90, shore_cells.size() / 70)):
		var cell := shore_cells[rng.randi_range(0, shore_cells.size() - 1)]
		var center := Vector2(cell) + Vector2(0.5, 0.5)
		result.append({"kind": "shore_fish", "placement_domain": "water", "center": [center.x, center.y], "guarantee_origin": [center.x, center.y], "placement_radius": 3.0, "count": rng.randi_range(1, 2), "radius": 1.0, "amount": 100})
	return result


static func _clear_start_corridors(terrain_ids: Array[int], size: Vector2i, starts: Array[Vector2], source_profile: Dictionary, topology: String) -> Dictionary:
	var reserved: Dictionary = {}
	var base_terrain := int(source_profile.get("base_terrain", 0))
	if not TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(base_terrain)):
		base_terrain = 0
	# Clear a short exit from each town center, not four map-spanning roads
	# through every forest. The latter made all generated woods look sparse.
	var reach := 9
	var half_width := 1
	for start in starts:
		var center := Vector2i(start)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for distance in range(reach + 1):
				for side in range(-half_width, half_width + 1):
					var cell: Vector2i = center + direction * distance + Vector2i(-direction.y, direction.x) * side
					if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
						continue
					var index := cell.y * size.x + cell.x
					if int(terrain_ids[index]) in TerrainRules.WATER_TERRAIN_IDS:
						continue
					if int(terrain_ids[index]) in TerrainRules.SOURCE_FOREST_TERRAIN_IDS:
						terrain_ids[index] = base_terrain
					reserved[cell] = true
	return reserved


static func _neutral_forest_clusters(size: Vector2i, terrain_ids: Array[int], starts: Array[Vector2], source_profile: Dictionary, seed: int) -> Array:
	var clumps_by_terrain: Dictionary = {}
	for value in source_profile.get("terrain_groups", []):
		var group: Dictionary = value
		var terrain_id := int(group.get("terrain_id", -1))
		if terrain_id in TerrainRules.SOURCE_FOREST_TERRAIN_IDS:
			clumps_by_terrain[terrain_id] = int(clumps_by_terrain.get(terrain_id, 0)) + maxi(0, int(group.get("number_of_clumps", 0)))
	if clumps_by_terrain.is_empty():
		return []
	var cells_by_terrain: Dictionary = {}
	for y in range(size.y):
		for x in range(size.x):
			var terrain_id := int(terrain_ids[y * size.x + x])
			if terrain_id in TerrainRules.SOURCE_FOREST_TERRAIN_IDS:
				if not cells_by_terrain.has(terrain_id):
					cells_by_terrain[terrain_id] = []
				cells_by_terrain[terrain_id].append(Vector2i(x, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x50AEF321
	var result: Array = []
	var terrain_keys: Array = clumps_by_terrain.keys()
	terrain_keys.sort()
	for terrain_id_value in terrain_keys:
		var terrain_id := int(terrain_id_value)
		var forest_cells: Array = cells_by_terrain.get(terrain_id, [])
		if forest_cells.is_empty():
			continue
		var count := maxi(1, roundi(float(clumps_by_terrain[terrain_id]) * float(size.x * size.y) / (72.0 * 72.0)))
		for index in range(count):
			for attempt in range(30):
				var cell: Vector2i = forest_cells[rng.randi_range(0, forest_cells.size() - 1)]
				var center := Vector2(cell) + Vector2(0.5, 0.5)
				if starts.any(func(start: Vector2): return center.distance_to(start) < 6.0):
					continue
				var cluster := {"kind": "tree", "center": [center.x, center.y], "count": rng.randi_range(18, 28), "radius": 3.2, "amount": 75, "source_terrain_id": terrain_id, "tree_palette": _forest_palette(terrain_id, rng), "guarantee_origin": [center.x, center.y], "placement_radius": 4.5, "dense_forest": true}
				result.append(cluster)
				break
	return result


static func _neutral_source_resource_clusters(size: Vector2i, terrain_ids: Array[int], starts: Array[Vector2], source_profile: Dictionary, seed: int) -> Array:
	var rules := {
		59: {"kind": "berries", "amount": 150},
		66: {"kind": "gold_mine", "amount": 400},
		102: {"kind": "stone_mine", "amount": 250},
	}
	var land_cells: Array[Vector2i] = []
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			if int(terrain_ids[y * size.x + x]) not in TerrainRules.WATER_TERRAIN_IDS:
				land_cells.append(Vector2i(x, y))
	if land_cells.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x51DAA921
	var result: Array = []
	var used_centers: Array[Vector2] = []
	var size_factor := clampf(sqrt(float(size.x * size.y) / (96.0 * 96.0)), 0.5, 1.6)
	for group_value in source_profile.get("unit_groups", []):
		var group: Dictionary = group_value
		var source_id := int(group.get("unit_id", -1))
		if not rules.has(source_id) or int(group.get("set_place_for_all_players", 0)) != -2:
			continue
		var rule: Dictionary = rules[source_id]
		var group_count := clampi(int(round(float(group.get("groups_per_player", 0)) * float(starts.size()) * size_factor)), 0, 80)
		var minimum_distance := minf(32.0, maxf(10.0, float(group.get("min_distance_to_players", 10)) * minf(1.0, mini(size.x, size.y) / 96.0)))
		for cluster_index in range(group_count):
			var chosen := Vector2.ZERO
			var best_score := -INF
			for attempt in range(48):
				var cell: Vector2i = land_cells[rng.randi_range(0, land_cells.size() - 1)]
				var candidate := Vector2(cell) + Vector2(0.5, 0.5)
				var nearest_start := INF
				for start in starts:
					nearest_start = minf(nearest_start, candidate.distance_to(start))
				var nearest_cluster := INF
				for used_center in used_centers:
					nearest_cluster = minf(nearest_cluster, candidate.distance_to(used_center))
				var score := minf(nearest_start, minimum_distance) + minf(nearest_cluster, 7.0)
				if score > best_score:
					best_score = score
					chosen = candidate
				if nearest_start >= minimum_distance and nearest_cluster >= 5.0:
					break
			used_centers.append(chosen)
			result.append({"kind": String(rule["kind"]), "center": [chosen.x, chosen.y], "count": maxi(1, int(group.get("objects_per_group", 1))), "radius": maxf(1.0, float(group.get("group_radius", 2))), "amount": int(rule["amount"]), "source_unit_id": source_id, "source_global": true})
	return result


static func _land_component_lookup(size: Vector2i, terrain_ids: Array[int], cliff_cells: Array[Vector2i]) -> Dictionary:
	var cliffs: Dictionary = {}
	for cell in cliff_cells:
		cliffs[cell] = true
	var components: Dictionary = {}
	var next_id := 0
	for y in range(size.y):
		for x in range(size.x):
			var origin := Vector2i(x, y)
			if components.has(origin) or cliffs.has(origin) or not TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(int(terrain_ids[y * size.x + x]))):
				continue
			var queue: Array[Vector2i] = [origin]
			components[origin] = next_id
			var cursor := 0
			while cursor < queue.size():
				var cell: Vector2i = queue[cursor]
				cursor += 1
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = cell + offset
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y or components.has(neighbor) or cliffs.has(neighbor) or not TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(int(terrain_ids[neighbor.y * size.x + neighbor.x]))):
						continue
					components[neighbor] = next_id
					queue.append(neighbor)
			next_id += 1
	return components


static func _seeded_water_cell(cell: Vector2i, size: Vector2i, starts: Array[Vector2], topology: String, generator: Dictionary, seed: int) -> bool:
	if topology in ["inland", "highlands", "hill_country", "narrows"]:
		return false
	var point := Vector2(cell) + Vector2(0.5, 0.5)
	var jitter := (_smooth_noise(point, 22.0, seed ^ 0x341AF) * 0.50 + _smooth_noise(point, 9.0, seed) * 0.40 + _smooth_noise(point, 3.0, seed ^ 0x317AC) * 0.10) * mini(size.x, size.y) * 0.075
	if topology == "coastal":
		var width := mini(size.x, size.y) * float(generator.get("coast_fraction", 0.21))
		return point.x < width + jitter or point.y < width - jitter * 0.5
	if topology == "continental":
		var border_width := mini(size.x, size.y) * float(generator.get("coast_fraction", 0.16))
		return point.x < border_width + jitter or point.y < border_width - jitter or point.x >= size.x - border_width + jitter or point.y >= size.y - border_width - jitter
	if topology == "mediterranean":
		var half_sea_width := size.y * float(generator.get("sea_fraction", 0.23)) * 0.5
		var sea_center := size.y * 0.5 + _smooth_noise(Vector2(point.x, 0.0), 12.0, seed ^ 0x4E017) * size.y * 0.055
		return absf(point.y - sea_center) < half_sea_width + jitter * 0.2
	if topology == "islands":
		var source_profile: Dictionary = generator.get("source_profile", {})
		var target_land_fraction := clampf(float(source_profile.get("land_coverage", 40)) / 100.0, 0.2, 0.65)
		var radius := sqrt(target_land_fraction * float(size.x * size.y) / (PI * float(maxi(1, starts.size())))) * 0.95
		var minimum_start_distance := INF
		for left in range(starts.size()):
			for right in range(left + 1, starts.size()):
				minimum_start_distance = minf(minimum_start_distance, starts[left].distance_to(starts[right]))
		if minimum_start_distance < INF:
			# Preserve a channel wide enough for large ship footprints between
			# neighboring islands, including the noisy shoreline band.
			radius = minf(radius, minimum_start_distance * 0.43)
		for start in starts:
			if point.distance_to(start) <= radius + jitter * 0.35:
				return false
		return true
	return false


static func _smooth_water_mask(terrain_ids: Array[int], size: Vector2i) -> void:
	# Remove isolated one-cell water spikes and land pinholes before assigning
	# the beach band. This keeps wide source islands/channels intact while giving
	# the transition sprites coherent coast corners to join.
	var original := terrain_ids.duplicate()
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			var index := y * size.x + x
			var water_neighbors := 0
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					if int(original[(y + offset_y) * size.x + x + offset_x]) in TerrainRules.WATER_TERRAIN_IDS:
						water_neighbors += 1
			if int(original[index]) in TerrainRules.WATER_TERRAIN_IDS and water_neighbors <= 2:
				terrain_ids[index] = 0
			elif int(original[index]) not in TerrainRules.WATER_TERRAIN_IDS and water_neighbors >= 6:
				terrain_ids[index] = 1


static func _smooth_noise(point: Vector2, scale: float, seed: int) -> float:
	var sample := point / maxf(1.0, scale)
	var origin := Vector2i(floori(sample.x), floori(sample.y))
	var fraction := sample - Vector2(origin)
	var smooth_x := fraction.x * fraction.x * (3.0 - 2.0 * fraction.x)
	var smooth_y := fraction.y * fraction.y * (3.0 - 2.0 * fraction.y)
	var top := lerpf(_hash_noise(origin, seed), _hash_noise(origin + Vector2i.RIGHT, seed), smooth_x)
	var bottom := lerpf(_hash_noise(origin + Vector2i.DOWN, seed), _hash_noise(origin + Vector2i.ONE, seed), smooth_x)
	return lerpf(top, bottom, smooth_y)


static func _hash_noise(cell: Vector2i, seed: int) -> float:
	# The placement hash below deliberately preserves old resource seeds, but
	# its neighboring values correlate too strongly for visible terrain noise.
	var value := (int(cell.x) * 73856093) ^ (int(cell.y) * 19349663) ^ (seed * 83492791)
	value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
	value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return float(value) / 4294967295.0 * 2.0 - 1.0


static func _profile_cliff_cells(size: Vector2i, cliff_profile: String, seed: int) -> Array[Vector2i]:
	var unique: Dictionary = {}
	if cliff_profile == "central_gate_v1":
		var center_x := int(size.x / 2)
		var gate_half_width := maxi(3, int(size.y * 0.055))
		for y in range(size.y):
			if absi(y - int(size.y / 2)) <= gate_half_width:
				continue
			for x in range(center_x - 1, center_x + 1):
				unique[Vector2i(x, y)] = true
	elif cliff_profile == "broken_ridges_v1":
		for ridge_index in range(3):
			var ridge_y := int(size.y * (0.36 + ridge_index * 0.14))
			for x in range(int(size.x * 0.30), int(size.x * 0.70)):
				if absi(x - int(size.x * 0.5)) < maxi(3, int(size.x * 0.055)):
					continue
				var offset := posmod(_cell_hash(Vector2i(x, ridge_index), seed), 3) - 1
				unique[Vector2i(x, ridge_y + offset)] = true
	var result: Array[Vector2i] = []
	for cell_value in unique.keys():
		var cell: Vector2i = cell_value
		if cell.x >= 1 and cell.x < size.x - 1 and cell.y >= 0 and cell.y < size.y:
			result.append(cell)
	result.sort_custom(func(left: Vector2i, right: Vector2i): return left.y < right.y or (left.y == right.y and left.x < right.x))
	return result


static func _apply_cliff_elevation(levels: Array[int], size: Vector2i, cliff_cells: Array[Vector2i]) -> void:
	var vertex_width := size.x + 1
	for cell in cliff_cells:
		for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			var vertex: Vector2i = cell + offset
			var index := vertex.y * vertex_width + vertex.x
			levels[index] = maxi(levels[index], 2)


static func _apply_shore_band(terrain_ids: Array[int], size: Vector2i) -> void:
	var water_mask := terrain_ids.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var index := y * size.x + x
			if int(water_mask[index]) in TerrainRules.WATER_TERRAIN_IDS:
				continue
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + Vector2i(offset)
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and int(water_mask[neighbor.y * size.x + neighbor.x]) in TerrainRules.WATER_TERRAIN_IDS:
					terrain_ids[index] = 2
					break


static func _apply_water_detail(terrain_ids: Array[int], size: Vector2i, seed: int) -> void:
	# Dark-water patches stay offshore so the surf transition and docking strip
	# retain their original terrain IDs and navigation guarantees.
	var original := terrain_ids.duplicate()
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			var index := y * size.x + x
			if original[index] != 1:
				continue
			var offshore := true
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + offset * 2
				if int(original[neighbor.y * size.x + neighbor.x]) not in TerrainRules.WATER_TERRAIN_IDS:
					offshore = false
					break
			if offshore and _smooth_noise(Vector2(x, y), 13.0, seed ^ 0x2AF51) > 0.28:
				terrain_ids[index] = 22


static func _forest_palette(terrain_id: int, rng: RandomNumberGenerator) -> Array:
	if terrain_id in [13, 20]:
		return PALM_TREES
	# Conifer-dominant patches exist, but are rare. Even the source's pine
	# terrain normally blends needles with several broadleaf silhouettes.
	if rng.randf() < 0.04:
		return CONIFER_TREES
	var palette: Array = BROADLEAF_TREES.duplicate()
	if rng.randf() < (0.82 if terrain_id == 19 else 0.65):
		palette.append_array(CONIFER_TREES)
		if terrain_id == 19:
			palette.append_array(CONIFER_TREES)
	return palette


static func _seeded_relief_hills(size: Vector2i, starts: Array[Vector2], terrain_ids: Array[int], seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x64E71A
	var count := clampi(int(float(size.x * size.y) / 1250.0), 5, 52)
	var result: Array = []
	for index in range(count):
		for attempt in range(32):
			var radius := rng.randi_range(4, 9)
			if size.x <= radius * 2 + 4 or size.y <= radius * 2 + 4:
				continue
			var center := Vector2i(rng.randi_range(radius + 2, size.x - radius - 3), rng.randi_range(radius + 2, size.y - radius - 3))
			if starts.any(func(start: Vector2): return Vector2(center).distance_to(start) < 9.0):
				continue
			var land_disk_clear := true
			for y in range(maxi(0, center.y - radius - 1), mini(size.y, center.y + radius + 2)):
				for x in range(maxi(0, center.x - radius - 1), mini(size.x, center.x + radius + 2)):
					if int(terrain_ids[y * size.x + x]) in TerrainRules.WATER_TERRAIN_IDS:
						land_disk_clear = false
						break
				if not land_disk_clear:
					break
			if not land_disk_clear:
				continue
			result.append({"center": center, "radius": radius, "maximum_elevation": rng.randi_range(1, 3)})
			break
	return result


static func _apply_relief_hill(levels: Array[int], size: Vector2i, terrain_ids: Array[int], hill: Dictionary) -> void:
	var center: Vector2i = hill["center"]
	var radius := int(hill["radius"])
	var maximum := int(hill["maximum_elevation"])
	for y in range(maxi(0, center.y - radius), mini(size.y, center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(size.x, center.x + radius + 1)):
			if int(terrain_ids[y * size.x + x]) in TerrainRules.WATER_TERRAIN_IDS:
				continue
			var distance := Vector2(x - center.x, y - center.y).length()
			if distance >= float(radius):
				continue
			# A diagonal changes distance by at most sqrt(2), keeping the four
			# corners of each terrain cell within the one-level placement contract.
			var level := clampi(ceili((float(radius) - distance) / 1.41421356), 0, maximum)
			var vertex_index := y * (size.x + 1) + x
			levels[vertex_index] = maxi(levels[vertex_index], level)


static func _seeded_rock_scenery(size: Vector2i, terrain_ids: Array[int], starts: Array[Vector2], resources: Array, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x4B0C3A
	var result: Array = []
	var occupied: Dictionary = {}
	for resource_value in resources:
		occupied[Vector2i(Vector2(resource_value.get("position", Vector2.ZERO)))] = true
	var count := clampi(int(float(size.x * size.y) / 520.0), 5, 120)
	var graphics := [572, 573, 575, 576]
	for index in range(count):
		for attempt in range(24):
			var cell := Vector2i(rng.randi_range(2, size.x - 3), rng.randi_range(2, size.y - 3))
			var terrain_id := int(terrain_ids[cell.y * size.x + cell.x])
			if occupied.has(cell) or terrain_id in TerrainRules.WATER_TERRAIN_IDS or terrain_id in TerrainRules.SOURCE_FOREST_TERRAIN_IDS:
				continue
			if starts.any(func(start: Vector2): return Vector2(cell).distance_to(start) < 8.0):
				continue
			var graphic_id := int(graphics[rng.randi_range(0, graphics.size() - 1)])
			result.append({"id": -600000 - index, "kind": "terrain_feature", "presentation_layer": "scenery", "position": Vector2(cell) + Vector2(0.5, 0.5), "graphic_id": graphic_id, "asset_name": "graphic_%d" % graphic_id})
			break
	return result


static func _apply_source_terrain_groups(terrain_ids: Array[int], size: Vector2i, starts: Array[Vector2], source_profile: Dictionary, seed: int) -> void:
	if source_profile.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x34A8F51
	for group_value in source_profile.get("terrain_groups", []):
		var group: Dictionary = group_value
		var terrain_id := int(group.get("terrain_id", -1))
		if terrain_id not in [6, 10, 13, 19, 20, 22]:
			continue
		var clumps := maxi(0, int(group.get("number_of_clumps", 0)))
		if clumps == 0:
			continue
		var land_group := terrain_id != 22
		var proportion := clampf(float(group.get("proportion", 0)), 0.0, 100.0) / 100.0
		var radius := clampf(sqrt(proportion * float(size.x * size.y) / (PI * float(clumps))), 1.2, float(mini(size.x, size.y)) * 0.16)
		for clump_index in range(clumps):
			var center := Vector2i(-1, -1)
			for attempt in range(24):
				var candidate := Vector2i(rng.randi_range(2, size.x - 3), rng.randi_range(2, size.y - 3))
				var source_is_water := int(terrain_ids[candidate.y * size.x + candidate.x]) in TerrainRules.WATER_TERRAIN_IDS
				if source_is_water != land_group:
					center = candidate
					break
			if center.x < 0:
				continue
			for y in range(maxi(0, floori(center.y - radius - 1.0)), mini(size.y, ceili(center.y + radius + 2.0))):
				for x in range(maxi(0, floori(center.x - radius - 1.0)), mini(size.x, ceili(center.x + radius + 2.0))):
					var index := y * size.x + x
					var is_water := int(terrain_ids[index]) in TerrainRules.WATER_TERRAIN_IDS
					if is_water == land_group:
						continue
					var cell := Vector2i(x, y)
					if terrain_id in TerrainRules.SOURCE_FOREST_TERRAIN_IDS and starts.any(func(start: Vector2): return (Vector2(cell) + Vector2.ONE * 0.5).distance_to(start) < 6.0):
						continue
					var edge_noise := (float(_cell_hash(cell, seed + clump_index * 101)) / 2147483647.0 - 0.5) * 1.4
					if Vector2(cell).distance_to(Vector2(center)) <= radius + edge_noise:
						terrain_ids[index] = terrain_id


static func _fixed_source_map(size: Vector2i, seed: int, generator: Dictionary) -> Dictionary:
	var terrain_ids: Array[int] = []
	for value in generator.get("terrain_ids", []):
		terrain_ids.append(int(value))
	var vertex_levels: Array[int] = []
	for value in generator.get("vertex_levels", []):
		vertex_levels.append(maxi(0, int(value)))
	return {
		"size": size,
		"seed": seed,
		"terrain_ids": terrain_ids,
		"vertex_levels": vertex_levels,
		"resources": [],
		"naval_start_zones": [],
		"reserved_foundation_cells": [],
	}


static func _generate_naval_start_zones(players: Array, size: Vector2i, terrain_ids: Array[int], settings: Dictionary = {}) -> Array:
	var result: Array = []
	var reserved_cells: Dictionary = {}
	var footprint_radius_cells := maxi(0, int(settings.get("dock_footprint_radius_cells", 1)))
	var allowed_surface_ids: Array = settings.get("dock_surface_terrain_ids", [1, 2, 4, 22])
	var water_guarantee := {
		"radius": maxf(0.0, float(settings.get("resource_search_radius", 0.0))),
		"clearance_cells": maxi(0, int(settings.get("resource_minimum_clearance_cells", 0))),
		"staging_clearance_cells": maxi(0, int(settings.get("water_staging_clearance_cells", 0))),
		"required_cells": maxi(0, int(settings.get("resource_required_cells", 0))),
	}
	if int(water_guarantee["required_cells"]) > 0:
		water_guarantee["valid_cells"] = _domain_clearance_cells(size, terrain_ids, "water", int(water_guarantee["clearance_cells"]))
		water_guarantee["capacity_cache"] = {}
	for player_value in players:
		var player: Dictionary = player_value
		if int(player.get("team", 0)) <= 0:
			continue
		var start := _vector2(player.get("start", []))
		var dock_position: Variant = _nearest_dock_anchor(start, size, terrain_ids, footprint_radius_cells, allowed_surface_ids, reserved_cells, water_guarantee)
		if not dock_position is Vector2:
			continue
		var staging_pair := _nearest_staging_pair(dock_position, size, terrain_ids, footprint_radius_cells, water_guarantee, reserved_cells)
		if staging_pair.is_empty():
			continue
		var zone := {
			"team": int(player.get("team", 0)),
			"dock_position": dock_position,
			"land_staging": staging_pair["land"],
			"water_staging": staging_pair["water"],
		}
		result.append(zone)
		_reserve_zone_cells(reserved_cells, zone, footprint_radius_cells)
	result.sort_custom(func(left, right): return int(left.get("team", 0)) < int(right.get("team", 0)))
	return result


static func _nearest_dock_anchor(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, allowed_surface_ids: Array, reserved_cells: Dictionary, water_guarantee: Dictionary = {}) -> Variant:
	var best_position: Variant = null
	var best_distance := INF
	for y in range(footprint_radius_cells, size.y - footprint_radius_cells):
		for x in range(footprint_radius_cells, size.x - footprint_radius_cells):
			var position := Vector2(x + 0.5, y + 0.5)
			var distance := origin.distance_squared_to(position)
			if distance > best_distance and not is_equal_approx(distance, best_distance):
				continue
			if not _dock_anchor_valid(position, size, terrain_ids, footprint_radius_cells, allowed_surface_ids, reserved_cells, water_guarantee):
				continue
			if best_position == null or distance < best_distance or (is_equal_approx(distance, best_distance) and (position.x < best_position.x or (is_equal_approx(position.x, best_position.x) and position.y < best_position.y))):
				best_position = position
				best_distance = distance
	return best_position


static func _dock_anchor_valid(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, allowed_surface_ids: Array, reserved_cells: Dictionary, water_guarantee: Dictionary = {}) -> bool:
	var cell := Vector2i(floori(origin.x), floori(origin.y))
	for y in range(cell.y - footprint_radius_cells, cell.y + footprint_radius_cells + 1):
		for x in range(cell.x - footprint_radius_cells, cell.x + footprint_radius_cells + 1):
			var footprint_cell := Vector2i(x, y)
			if footprint_cell.x < 0 or footprint_cell.y < 0 or footprint_cell.x >= size.x or footprint_cell.y >= size.y:
				return false
			if reserved_cells.has(footprint_cell):
				return false
			if not _array_has_int(allowed_surface_ids, int(terrain_ids[footprint_cell.y * size.x + footprint_cell.x])):
				return false
	return not _nearest_staging_pair(origin, size, terrain_ids, footprint_radius_cells, water_guarantee, reserved_cells).is_empty()


static func _array_has_int(values: Array, expected: int) -> bool:
	for value in values:
		if int(value) == expected:
			return true
	return false


static func _nearest_staging_pair(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, water_guarantee: Dictionary = {}, reserved_cells: Dictionary = {}) -> Dictionary:
	var land_candidates := _perimeter_domain_candidates(origin, size, terrain_ids, footprint_radius_cells, "land", reserved_cells)
	var water_candidates := _perimeter_domain_candidates(origin, size, terrain_ids, footprint_radius_cells, "water", reserved_cells, maxi(0, int(water_guarantee.get("staging_clearance_cells", 0))))
	var required_cells := maxi(0, int(water_guarantee.get("required_cells", 0)))
	if required_cells > 0:
		water_candidates = water_candidates.filter(func(candidate):
			return _cached_domain_candidate_count_near(Vector2(candidate), water_guarantee, size) >= required_cells
		)
	if land_candidates.is_empty() or water_candidates.is_empty():
		return {}
	var pairs: Array = []
	for land_value in land_candidates:
		for water_value in water_candidates:
			var land := Vector2(land_value)
			var water := Vector2(water_value)
			pairs.append({"land": land, "water": water, "distance": land.distance_squared_to(water)})
	pairs.sort_custom(func(left, right):
		var left_distance := float(left.get("distance", 0.0))
		var right_distance := float(right.get("distance", 0.0))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		var left_land := Vector2(left.get("land", Vector2.ZERO))
		var right_land := Vector2(right.get("land", Vector2.ZERO))
		if left_land != right_land:
			return left_land.x < right_land.x or (is_equal_approx(left_land.x, right_land.x) and left_land.y < right_land.y)
		var left_water := Vector2(left.get("water", Vector2.ZERO))
		var right_water := Vector2(right.get("water", Vector2.ZERO))
		return left_water.x < right_water.x or (is_equal_approx(left_water.x, right_water.x) and left_water.y < right_water.y)
	)
	return {"land": pairs[0]["land"], "water": pairs[0]["water"]}


static func _perimeter_domain_candidates(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, domain: String, reserved_cells: Dictionary = {}, clearance_cells: int = 0) -> Array:
	var center := Vector2i(floori(origin.x), floori(origin.y))
	var perimeter_radius := footprint_radius_cells + 1
	var maximum_radius := perimeter_radius + 3 if clearance_cells > 0 else perimeter_radius
	var candidates: Array = []
	for y in range(center.y - maximum_radius, center.y + maximum_radius + 1):
		for x in range(center.x - maximum_radius, center.x + maximum_radius + 1):
			var distance := maxi(absi(x - center.x), absi(y - center.y))
			if distance < perimeter_radius or distance > maximum_radius:
				continue
			var cell := Vector2i(x, y)
			if not reserved_cells.has(cell) and _cell_matches_domain_with_clearance(cell, size, terrain_ids, domain, clearance_cells):
				candidates.append(Vector2(x + 0.5, y + 0.5))
	return candidates


static func _domain_clearance_cells(size: Vector2i, terrain_ids: Array[int], domain: String, clearance_cells: int) -> Dictionary:
	var result: Dictionary = {}
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if _cell_matches_domain_with_clearance(cell, size, terrain_ids, domain, clearance_cells):
				result[cell] = true
	return result


static func _cached_domain_candidate_count_near(origin: Vector2, guarantee: Dictionary, size: Vector2i) -> int:
	var origin_cell := Vector2i(origin)
	var cache: Dictionary = guarantee.get("capacity_cache", {})
	if cache.has(origin_cell):
		return int(cache[origin_cell])
	var radius := maxf(0.0, float(guarantee.get("radius", 0.0)))
	var valid_cells: Dictionary = guarantee.get("valid_cells", {})
	var count := 0
	for y in range(maxi(0, floori(origin.y - radius)), mini(size.y, ceili(origin.y + radius) + 1)):
		for x in range(maxi(0, floori(origin.x - radius)), mini(size.x, ceili(origin.x + radius) + 1)):
			var cell := Vector2i(x, y)
			if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(origin) > radius + 0.0001:
				continue
			if valid_cells.has(cell):
				count += 1
	cache[origin_cell] = count
	guarantee["capacity_cache"] = cache
	return count


static func _reserved_naval_cells(zones: Array, footprint_radius_cells: int) -> Dictionary:
	var result: Dictionary = {}
	for zone_value in zones:
		_reserve_zone_cells(result, zone_value, footprint_radius_cells)
	return result


static func _reserve_zone_cells(result: Dictionary, zone_value: Variant, footprint_radius_cells: int) -> void:
	var zone: Dictionary = zone_value
	var center := Vector2i(Vector2(zone.get("dock_position", Vector2.ZERO)))
	for y in range(center.y - footprint_radius_cells, center.y + footprint_radius_cells + 1):
		for x in range(center.x - footprint_radius_cells, center.x + footprint_radius_cells + 1):
			result[Vector2i(x, y)] = true
	for key in ["land_staging", "water_staging"]:
		result[Vector2i(Vector2(zone.get(key, Vector2.ZERO)))] = true


static func _base_terrain_id(cell: Vector2i, size: Vector2i, border: Dictionary, shore_width: int) -> int:
	var left := maxi(0, int(border.get("left", 0)))
	var top := maxi(0, int(border.get("top", 0)))
	var right := maxi(0, int(border.get("right", 0)))
	var bottom := maxi(0, int(border.get("bottom", 0)))
	if cell.x < left or cell.y < top or cell.x >= size.x - right or cell.y >= size.y - bottom:
		return 1
	if (left > 0 and cell.x < left + shore_width) or (top > 0 and cell.y < top + shore_width) or (right > 0 and cell.x >= size.x - right - shore_width) or (bottom > 0 and cell.y >= size.y - bottom - shore_width):
		return 2
	return int(border.get("land_terrain_id", 0))


static func _apply_terrain_patches(terrain_ids: Array[int], size: Vector2i, patches: Array, seed: int) -> void:
	for patch_value in patches:
		var patch: Dictionary = patch_value
		var center := _vector2(patch.get("center", []))
		var radius := maxf(0.0, float(patch.get("radius", 0.0)))
		var terrain_id := int(patch.get("terrain_id", 0))
		var variance := maxf(0.0, float(patch.get("variance", 0.0)))
		for y in range(size.y):
			for x in range(size.x):
				var cell := Vector2i(x, y)
				var noise := float(_cell_hash(cell, seed)) / 2147483647.0 * variance
				if Vector2(cell).distance_to(center) <= radius + noise:
					terrain_ids[y * size.x + x] = terrain_id


static func _apply_hill(levels: Array[int], size: Vector2i, hill_value: Variant) -> void:
	var hill: Dictionary = hill_value
	var center := Vector2i(_vector2(hill.get("center", [])))
	var radius := maxi(1, int(hill.get("radius", 1)))
	var maximum := clampi(int(hill.get("maximum_elevation", 1)), 0, radius)
	var width := size.x + 1
	for y in range(maxi(0, center.y - radius), mini(size.y, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(size.x, center.x + radius) + 1):
			var distance := maxi(absi(x - center.x), absi(y - center.y))
			var level := clampi(radius - distance, 0, maximum)
			var index := y * width + x
			levels[index] = maxi(levels[index], level)


static func _generate_resource_clusters(clusters: Array, size: Vector2i, seed: int, terrain_ids: Array[int], blocked_cells: Dictionary = {}, land_components: Dictionary = {}) -> Array:
	var resources: Array = []
	var occupied_cells := blocked_cells.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for cluster_value in clusters:
		var cluster: Dictionary = cluster_value
		var center := _vector2(cluster.get("center", []))
		var owner_component := -1
		if cluster.has("owner_start"):
			var owner_start := _vector2(cluster["owner_start"])
			owner_component = int(land_components.get(Vector2i(owner_start), -1))
			var minimum_distance := maxf(0.0, float(cluster.get("minimum_distance", 0.0)))
			var maximum_distance := maxf(minimum_distance, float(cluster.get("maximum_distance", minimum_distance)))
			var bearing := rng.randf_range(0.0, TAU)
			center = owner_start + Vector2(cos(bearing), sin(bearing)) * rng.randf_range(minimum_distance, maximum_distance)
		var count := maxi(0, int(cluster.get("count", 0)))
		var radius := maxf(0.0, float(cluster.get("radius", 0.0)))
		for index in range(count):
			var angle := TAU * float(index) / maxf(1.0, float(count)) + rng.randf_range(-0.3, 0.3)
			var distance := radius * (0.35 + 0.65 * rng.randf())
			var position := center + Vector2(cos(angle), sin(angle)) * distance
			position.x = clampf(position.x, 1.5, float(size.x) - 1.5)
			position.y = clampf(position.y, 1.5, float(size.y) - 1.5)
			var placement_domain := String(cluster.get("placement_domain", "land"))
			var preserve_approach := placement_domain == "land" and not land_components.is_empty() and not bool(cluster.get("dense_forest", false))
			var enforce_spacing := false
			var minimum_domain_clearance := maxi(0, int(cluster.get("minimum_domain_clearance_cells", 0)))
			var guarantee_origin_values: Array = cluster.get("guarantee_origin", cluster.get("owner_start", []))
			var guarantee_radius := maxf(0.0, float(cluster.get("guarantee_radius", 0.0)))
			var placement_radius := maxf(guarantee_radius, float(cluster.get("placement_radius", 0.0)))
			if guarantee_origin_values.size() >= 2 and placement_radius > 0.0:
				var bounded_position: Variant = _nearest_domain_within(position, _vector2(guarantee_origin_values), placement_radius, size, terrain_ids, placement_domain, occupied_cells, minimum_domain_clearance, land_components, owner_component, preserve_approach, enforce_spacing)
				if not bounded_position is Vector2:
					continue
				position = bounded_position
			else:
				position = _nearest_domain(position, size, terrain_ids, placement_domain, occupied_cells, minimum_domain_clearance, land_components, owner_component, preserve_approach, enforce_spacing)
			if placement_domain == "land":
				position = Vector2(Vector2i(position)) + Vector2(0.5, 0.5)
			if occupied_cells.has(Vector2i(position)) or not _cell_matches_domain(Vector2i(position), size, terrain_ids, placement_domain):
				continue
			if bool(cluster.get("dense_forest", false)) and int(terrain_ids[Vector2i(position).y * size.x + Vector2i(position).x]) != int(cluster.get("source_terrain_id", -1)):
				continue
			if preserve_approach:
				var approach_cell: Variant = _free_land_approach_cell(Vector2i(position), size, terrain_ids, occupied_cells, land_components, owner_component)
				if not approach_cell is Vector2i:
					continue
				occupied_cells[approach_cell] = true
			occupied_cells[Vector2i(floori(position.x), floori(position.y))] = true
			var generated := {
				"category": String(cluster.get("category", "resource")),
				"kind": String(cluster.get("kind", "tree")),
				"position": position,
				"amount": maxi(0, int(cluster.get("amount", 0))),
				"placement_domain": placement_domain,
				"guarantee_team": int(cluster.get("guarantee_team", 0)),
				"owner_start": cluster.get("owner_start", []),
			}
			var tree_palette: Array = cluster.get("tree_palette", [])
			if not tree_palette.is_empty() and not cluster.has("source_terrain_id") and int(terrain_ids[Vector2i(position).y * size.x + Vector2i(position).x]) in [6, 13, 20]:
				tree_palette = PALM_TREES
			if not tree_palette.is_empty():
				var tree_id := int(tree_palette[rng.randi_range(0, tree_palette.size() - 1)])
				generated["source_unit_id"] = tree_id
				generated["source_graphic_id"] = int(TREE_GRAPHICS[tree_id])
				generated["source_graphic_asset_name"] = "graphic_%d" % int(TREE_GRAPHICS[tree_id])
			elif cluster.has("source_unit_id"):
				generated["source_unit_id"] = int(cluster["source_unit_id"])
			if cluster.has("source_graphic_asset_name"):
				generated["source_graphic_asset_name"] = String(cluster["source_graphic_asset_name"])
			if cluster.has("source_terrain_id"):
				generated["source_terrain_id"] = int(cluster["source_terrain_id"])
			resources.append(generated)
	return resources


static func _starting_entity_exclusion_cells(match_definition: Dictionary, size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for entity_value in match_definition.get("entities", []):
		var entity: Dictionary = entity_value
		var radius := maxi(0, int(entity.get("resource_exclusion_radius_cells", 0)))
		if radius <= 0:
			continue
		var center := Vector2i(Vector2(entity.get("position", Vector2.ZERO)))
		for y in range(maxi(0, center.y - radius), mini(size.y, center.y + radius + 1)):
			for x in range(maxi(0, center.x - radius), mini(size.x, center.x + radius + 1)):
				result[Vector2i(x, y)] = true
	return result


static func _nearest_land(position: Vector2, size: Vector2i, terrain_ids: Array[int]) -> Vector2:
	return _nearest_domain(position, size, terrain_ids, "land", {})


static func _free_land_approach_cell(resource_cell: Vector2i, size: Vector2i, terrain_ids: Array[int], blocked_cells: Dictionary, land_components: Dictionary, required_component: int) -> Variant:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var cell: Vector2i = resource_cell + offset
		if blocked_cells.has(cell) or cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		if required_component >= 0 and int(land_components.get(cell, -2)) != required_component:
			continue
		if TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(int(terrain_ids[cell.y * size.x + cell.x]))):
			return cell
	return null


static func _resource_cell_has_spacing(cell: Vector2i, blocked_cells: Dictionary) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if blocked_cells.has(cell + Vector2i(offset_x, offset_y)):
				return false
	return true


static func _nearest_domain(position: Vector2, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0, land_components: Dictionary = {}, required_component: int = -1, preserve_approach: bool = false, enforce_spacing: bool = false) -> Vector2:
	var cell := Vector2i(floori(position.x), floori(position.y))
	if not blocked_cells.has(cell) and _cell_matches_domain_with_clearance(cell, size, terrain_ids, placement_domain, minimum_clearance_cells) and (required_component < 0 or int(land_components.get(cell, -2)) == required_component) and (not enforce_spacing or _resource_cell_has_spacing(cell, blocked_cells)) and (not preserve_approach or _free_land_approach_cell(cell, size, terrain_ids, blocked_cells, land_components, required_component) is Vector2i):
		return Vector2(cell) + Vector2(0.5, 0.5) if minimum_clearance_cells > 0 else position
	for radius in range(1, maxi(size.x, size.y)):
		var candidates: Array[Vector2] = []
		for y in range(maxi(0, cell.y - radius), mini(size.y, cell.y + radius + 1)):
			for x in range(maxi(0, cell.x - radius), mini(size.x, cell.x + radius + 1)):
				var candidate_cell := Vector2i(x, y)
				if not blocked_cells.has(candidate_cell) and _cell_matches_domain_with_clearance(candidate_cell, size, terrain_ids, placement_domain, minimum_clearance_cells) and (required_component < 0 or int(land_components.get(candidate_cell, -2)) == required_component) and (not enforce_spacing or _resource_cell_has_spacing(candidate_cell, blocked_cells)) and (not preserve_approach or _free_land_approach_cell(candidate_cell, size, terrain_ids, blocked_cells, land_components, required_component) is Vector2i):
					candidates.append(Vector2(candidate_cell) + Vector2(0.5, 0.5))
		if not candidates.is_empty():
			candidates.sort_custom(func(left, right):
				var left_distance := position.distance_squared_to(left)
				var right_distance := position.distance_squared_to(right)
				if not is_equal_approx(left_distance, right_distance):
					return left_distance < right_distance
				return left.y < right.y or (is_equal_approx(left.y, right.y) and left.x < right.x)
			)
			return candidates[0]
	return position


static func _nearest_domain_within(position: Vector2, guarantee_origin: Vector2, maximum_distance: float, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0, land_components: Dictionary = {}, required_component: int = -1, preserve_approach: bool = false, enforce_spacing: bool = false) -> Variant:
	var preferred_cell := Vector2i(position)
	var preferred := Vector2(preferred_cell) + Vector2(0.5, 0.5)
	if not is_equal_approx(position.x, floorf(position.x)) and not is_equal_approx(position.y, floorf(position.y)) and preferred.distance_to(guarantee_origin) <= maximum_distance + 0.0001 and not blocked_cells.has(preferred_cell) and _cell_matches_domain_with_clearance(preferred_cell, size, terrain_ids, placement_domain, minimum_clearance_cells) and (required_component < 0 or int(land_components.get(preferred_cell, -2)) == required_component) and (not enforce_spacing or _resource_cell_has_spacing(preferred_cell, blocked_cells)) and (not preserve_approach or _free_land_approach_cell(preferred_cell, size, terrain_ids, blocked_cells, land_components, required_component) is Vector2i):
		return preferred
	var best: Variant = null
	var best_distance := INF
	for y in range(maxi(0, floori(guarantee_origin.y - maximum_distance)), mini(size.y, ceili(guarantee_origin.y + maximum_distance) + 1)):
		for x in range(maxi(0, floori(guarantee_origin.x - maximum_distance)), mini(size.x, ceili(guarantee_origin.x + maximum_distance) + 1)):
			var cell := Vector2i(x, y)
			var candidate := Vector2(cell) + Vector2(0.5, 0.5)
			if candidate.distance_to(guarantee_origin) > maximum_distance + 0.0001 or blocked_cells.has(cell):
				continue
			if _cell_matches_domain_with_clearance(cell, size, terrain_ids, placement_domain, minimum_clearance_cells) and (required_component < 0 or int(land_components.get(cell, -2)) == required_component) and (not enforce_spacing or _resource_cell_has_spacing(cell, blocked_cells)) and (not preserve_approach or _free_land_approach_cell(cell, size, terrain_ids, blocked_cells, land_components, required_component) is Vector2i):
				var distance := position.distance_squared_to(candidate)
				if distance < best_distance and not is_equal_approx(distance, best_distance):
					best = candidate
					best_distance = distance
				elif is_equal_approx(distance, best_distance) and (best == null or candidate.y < Vector2(best).y or (is_equal_approx(candidate.y, Vector2(best).y) and candidate.x < Vector2(best).x)):
					best = candidate
					best_distance = distance
	return best


static func _cell_matches_domain_with_clearance(cell: Vector2i, size: Vector2i, terrain_ids: Array[int], placement_domain: String, minimum_clearance_cells: int) -> bool:
	if not _cell_matches_domain(cell, size, terrain_ids, placement_domain):
		return false
	if minimum_clearance_cells <= 0:
		return true
	for y in range(cell.y - minimum_clearance_cells, cell.y + minimum_clearance_cells + 1):
		for x in range(cell.x - minimum_clearance_cells, cell.x + minimum_clearance_cells + 1):
			if not _cell_matches_domain(Vector2i(x, y), size, terrain_ids, placement_domain):
				return false
	return true


static func _cell_matches_domain(cell: Vector2i, size: Vector2i, terrain_ids: Array[int], placement_domain: String) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	var is_water := int(terrain_ids[cell.y * size.x + cell.x]) in TerrainRules.WATER_TERRAIN_IDS
	if placement_domain == "water":
		return is_water
	if placement_domain == "shore_water":
		if not is_water:
			return false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and int(terrain_ids[neighbor.y * size.x + neighbor.x]) not in TerrainRules.WATER_TERRAIN_IDS:
				return true
		return false
	return not is_water


static func _cell_hash(cell: Vector2i, seed: int) -> int:
	var value := int(cell.x) * 73856093 ^ int(cell.y) * 19349663 ^ seed * 83492791
	value = value ^ (value >> 13)
	return absi(value & 0x7fffffff)


static func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
