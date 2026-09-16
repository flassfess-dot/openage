class_name RoRRandomMapGenerator
extends RefCounted


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
	_apply_shore_band(terrain_ids, size)
	var naval_start_settings: Dictionary = generator.get("naval_start", {})
	var naval_start_zones: Array = []
	if bool(generator.get("requires_naval_starts", false)):
		naval_start_zones = _generate_naval_start_zones(match_definition.get("players", []), size, terrain_ids, naval_start_settings)
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
	var resource_clusters: Array = generator.get("resource_clusters", []).duplicate(true)
	resource_clusters.append_array(_naval_resource_clusters(naval_start_zones, generator.get("naval_resource_clusters", [])))
	return {
		"size": size,
		"seed": seed,
		"terrain_ids": terrain_ids,
		"vertex_levels": vertex_levels,
		"resources": _generate_resource_clusters(resource_clusters, size, seed, terrain_ids, resource_exclusion_cells),
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


static func _seeded_water_cell(cell: Vector2i, size: Vector2i, starts: Array[Vector2], topology: String, generator: Dictionary, seed: int) -> bool:
	if topology in ["inland", "highlands"]:
		return false
	var jitter := (float(_cell_hash(cell, seed)) / 2147483647.0 - 0.5) * 4.0
	if topology == "coastal":
		var width := mini(size.x, size.y) * float(generator.get("coast_fraction", 0.12))
		return float(cell.x) < width + jitter or float(cell.y) < width - jitter * 0.5
	if topology == "islands":
		var radius := maxf(7.0, mini(size.x, size.y) * float(generator.get("island_radius_fraction", 0.12)))
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		for start in starts:
			if point.distance_to(start) <= radius + jitter * 0.35:
				return false
		var center := Vector2(size) * 0.5
		return point.distance_to(center) > radius * 0.65 + jitter * 0.2
	return false


static func _apply_shore_band(terrain_ids: Array[int], size: Vector2i) -> void:
	var water_mask := terrain_ids.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var index := y * size.x + x
			if int(water_mask[index]) in [1, 22]:
				continue
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + Vector2i(offset)
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and int(water_mask[neighbor.y * size.x + neighbor.x]) in [1, 22]:
					terrain_ids[index] = 2
					break


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
	var candidates: Array = []
	for y in range(footprint_radius_cells, size.y - footprint_radius_cells):
		for x in range(footprint_radius_cells, size.x - footprint_radius_cells):
			var cell := Vector2i(x, y)
			var position := Vector2(x + 0.5, y + 0.5)
			if _dock_anchor_valid(position, size, terrain_ids, footprint_radius_cells, allowed_surface_ids, reserved_cells, water_guarantee):
				candidates.append(position)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right):
		var left_point := Vector2(left)
		var right_point := Vector2(right)
		var left_distance := origin.distance_squared_to(left_point)
		var right_distance := origin.distance_squared_to(right_point)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left_point.x < right_point.x or (is_equal_approx(left_point.x, right_point.x) and left_point.y < right_point.y)))
	)
	return Vector2(candidates[0])


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
	var water_candidates := _perimeter_domain_candidates(origin, size, terrain_ids, footprint_radius_cells, "water", reserved_cells)
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


static func _perimeter_domain_candidates(origin: Vector2, size: Vector2i, terrain_ids: Array[int], footprint_radius_cells: int, domain: String, reserved_cells: Dictionary = {}) -> Array:
	var center := Vector2i(floori(origin.x), floori(origin.y))
	var perimeter_radius := footprint_radius_cells + 1
	var candidates: Array = []
	for y in range(center.y - perimeter_radius, center.y + perimeter_radius + 1):
		for x in range(center.x - perimeter_radius, center.x + perimeter_radius + 1):
			if absi(x - center.x) != perimeter_radius and absi(y - center.y) != perimeter_radius:
				continue
			var cell := Vector2i(x, y)
			if not reserved_cells.has(cell) and _cell_matches_domain(cell, size, terrain_ids, domain):
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
	for y in range(size.y + 1):
		for x in range(size.x + 1):
			var distance := maxi(absi(x - center.x), absi(y - center.y))
			var level := clampi(radius - distance, 0, maximum)
			var index := y * width + x
			levels[index] = maxi(levels[index], level)


static func _generate_resource_clusters(clusters: Array, size: Vector2i, seed: int, terrain_ids: Array[int], blocked_cells: Dictionary = {}) -> Array:
	var resources: Array = []
	var occupied_cells := blocked_cells.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for cluster_value in clusters:
		var cluster: Dictionary = cluster_value
		var center := _vector2(cluster.get("center", []))
		var count := maxi(0, int(cluster.get("count", 0)))
		var radius := maxf(0.0, float(cluster.get("radius", 0.0)))
		for index in range(count):
			var angle := TAU * float(index) / maxf(1.0, float(count)) + rng.randf_range(-0.3, 0.3)
			var distance := radius * (0.35 + 0.65 * rng.randf())
			var position := center + Vector2(cos(angle), sin(angle)) * distance
			position.x = clampf(position.x, 1.5, float(size.x) - 1.5)
			position.y = clampf(position.y, 1.5, float(size.y) - 1.5)
			var placement_domain := String(cluster.get("placement_domain", "land"))
			var minimum_domain_clearance := maxi(0, int(cluster.get("minimum_domain_clearance_cells", 0)))
			var guarantee_origin_values: Array = cluster.get("guarantee_origin", [])
			var guarantee_radius := maxf(0.0, float(cluster.get("guarantee_radius", 0.0)))
			if guarantee_origin_values.size() >= 2 and guarantee_radius > 0.0:
				var bounded_position: Variant = _nearest_domain_within(position, _vector2(guarantee_origin_values), guarantee_radius, size, terrain_ids, placement_domain, occupied_cells, minimum_domain_clearance)
				if not bounded_position is Vector2:
					continue
				position = bounded_position
			else:
				position = _nearest_domain(position, size, terrain_ids, placement_domain, occupied_cells, minimum_domain_clearance)
			occupied_cells[Vector2i(floori(position.x), floori(position.y))] = true
			resources.append({
				"category": "resource",
				"kind": String(cluster.get("kind", "tree")),
				"position": position,
				"amount": maxi(0, int(cluster.get("amount", 0))),
				"placement_domain": placement_domain,
			})
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


static func _nearest_domain(position: Vector2, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0) -> Vector2:
	var cell := Vector2i(floori(position.x), floori(position.y))
	if not blocked_cells.has(cell) and _cell_matches_domain_with_clearance(cell, size, terrain_ids, placement_domain, minimum_clearance_cells):
		return Vector2(cell) + Vector2(0.5, 0.5) if minimum_clearance_cells > 0 else position
	for radius in range(1, maxi(size.x, size.y)):
		var candidates: Array[Vector2] = []
		for y in range(maxi(0, cell.y - radius), mini(size.y, cell.y + radius + 1)):
			for x in range(maxi(0, cell.x - radius), mini(size.x, cell.x + radius + 1)):
				var candidate_cell := Vector2i(x, y)
				if not blocked_cells.has(candidate_cell) and _cell_matches_domain_with_clearance(candidate_cell, size, terrain_ids, placement_domain, minimum_clearance_cells):
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


static func _nearest_domain_within(position: Vector2, guarantee_origin: Vector2, maximum_distance: float, size: Vector2i, terrain_ids: Array[int], placement_domain: String, blocked_cells: Dictionary = {}, minimum_clearance_cells: int = 0) -> Variant:
	var candidates: Array[Vector2] = []
	for y in range(maxi(0, floori(guarantee_origin.y - maximum_distance)), mini(size.y, ceili(guarantee_origin.y + maximum_distance) + 1)):
		for x in range(maxi(0, floori(guarantee_origin.x - maximum_distance)), mini(size.x, ceili(guarantee_origin.x + maximum_distance) + 1)):
			var cell := Vector2i(x, y)
			var candidate := Vector2(cell) + Vector2(0.5, 0.5)
			if candidate.distance_to(guarantee_origin) > maximum_distance + 0.0001 or blocked_cells.has(cell):
				continue
			if _cell_matches_domain_with_clearance(cell, size, terrain_ids, placement_domain, minimum_clearance_cells):
				candidates.append(candidate)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left: Vector2, right: Vector2):
		var left_distance := position.distance_squared_to(left)
		var right_distance := position.distance_squared_to(right)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.y < right.y or (is_equal_approx(left.y, right.y) and left.x < right.x)))
	)
	return candidates[0]


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
	var is_water := int(terrain_ids[cell.y * size.x + cell.x]) in [1, 22]
	if placement_domain == "water":
		return is_water
	if placement_domain == "shore_water":
		if not is_water:
			return false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and int(terrain_ids[neighbor.y * size.x + neighbor.x]) not in [1, 22]:
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
