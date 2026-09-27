class_name RoRRandomMapMetrics
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")
const RandomMapZones := preload("res://scripts/random_map_zones.gd")

const EMPTY_DISTANCE_THRESHOLD_CELLS := 6
const CONTESTED_RESOURCE_SAFETY_MAX := 0.12
const SAFE_RESOURCE_SAFETY_MIN := 0.25


static func measure(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	if size.x <= 0 or size.y <= 0 or terrain_ids.size() != size.x * size.y:
		return {}
	var cliff_lookup := _cell_lookup(map_data.get("cliff_cells", []), size)
	var walkable_mask := _walkable_land_mask(size, terrain_ids, cliff_lookup)
	var walkable_land_cells := _mask_count(walkable_mask)
	var terrain_metrics := _terrain_metrics(size, terrain_ids, walkable_mask)
	var object_cells := _object_cell_lookup(map_data, size)
	var feature_mask := _land_feature_mask(size, terrain_ids, walkable_mask, object_cells, cliff_lookup, int(terrain_metrics.get("dominant_land_terrain_id", 0)))
	var land_object_cells := 0
	for cell_value in object_cells.keys():
		if _mask_has(walkable_mask, size, Vector2i(cell_value)):
			land_object_cells += 1
	var feature_cells := _mask_count(feature_mask)
	var result := {
		"walkable_land_cells": walkable_land_cells,
		"object_cell_count": object_cells.size(),
		"land_object_cell_count": land_object_cells,
		"object_density_per_1000_land_cells": _per_thousand(land_object_cells, walkable_land_cells),
		"land_feature_cell_count": feature_cells,
		"land_feature_density_per_1000_cells": _per_thousand(feature_cells, walkable_land_cells),
	}
	result.merge(terrain_metrics, true)
	var zone_ids: PackedInt32Array = map_data.get("strategic_zones", {}).get("zone_ids", PackedInt32Array())
	result.merge(_empty_space_metrics(size, walkable_mask, feature_mask, zone_ids), true)
	result.merge(_strategic_zone_metrics(definition, map_data), true)
	result.merge(_resource_contestability_metrics(definition, map_data, walkable_mask), true)
	return result


static func measure_occupancy(map_data: Dictionary) -> Dictionary:
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	if size.x <= 0 or size.y <= 0 or terrain_ids.size() != size.x * size.y:
		return {}
	var cliff_lookup := _cell_lookup(map_data.get("cliff_cells", []), size)
	var walkable_mask := _walkable_land_mask(size, terrain_ids, cliff_lookup)
	var land_counts: Dictionary = {}
	for index in range(terrain_ids.size()):
		if walkable_mask[index] != 0:
			var terrain_id := int(terrain_ids[index])
			land_counts[terrain_id] = int(land_counts.get(terrain_id, 0)) + 1
	var dominant_land_terrain_id := _dominant_key(land_counts, 0)
	var object_cells := _object_cell_lookup(map_data, size)
	var feature_mask := _land_feature_mask(size, terrain_ids, walkable_mask, object_cells, cliff_lookup, dominant_land_terrain_id)
	var walkable_land_cells := _mask_count(walkable_mask)
	var land_object_cells := 0
	for cell_value in object_cells.keys():
		if _mask_has(walkable_mask, size, Vector2i(cell_value)):
			land_object_cells += 1
	var result := {
		"walkable_land_cells": walkable_land_cells,
		"land_object_cell_count": land_object_cells,
		"object_density_per_1000_land_cells": _per_thousand(land_object_cells, walkable_land_cells),
		"land_feature_cell_count": _mask_count(feature_mask),
		"land_feature_density_per_1000_cells": _per_thousand(_mask_count(feature_mask), walkable_land_cells),
	}
	var zone_ids: PackedInt32Array = map_data.get("strategic_zones", {}).get("zone_ids", PackedInt32Array())
	result.merge(_empty_space_metrics(size, walkable_mask, feature_mask, zone_ids), true)
	return result


static func _terrain_metrics(size: Vector2i, terrain_ids: Array, walkable_mask: PackedByteArray) -> Dictionary:
	var terrain_counts: Dictionary = {}
	var land_counts: Dictionary = {}
	for index in range(terrain_ids.size()):
		var terrain_id := int(terrain_ids[index])
		terrain_counts[terrain_id] = int(terrain_counts.get(terrain_id, 0)) + 1
		if walkable_mask[index] != 0:
			land_counts[terrain_id] = int(land_counts.get(terrain_id, 0)) + 1
	var patches := _terrain_patch_metrics(size, terrain_ids)
	var coastal_water_cells := int(terrain_counts.get(1, 0))
	var walkable_shallow_cells := int(terrain_counts.get(4, 0))
	var deep_water_cells := int(terrain_counts.get(22, 0))
	var water_cells := coastal_water_cells + walkable_shallow_cells + deep_water_cells
	var water_depth_type_count := int(coastal_water_cells > 0) + int(walkable_shallow_cells > 0) + int(deep_water_cells > 0)
	return {
		"terrain_type_count": terrain_counts.size(),
		"terrain_entropy_bits": _entropy_bits(terrain_counts, terrain_ids.size()),
		"land_terrain_type_count": land_counts.size(),
		"land_terrain_entropy_bits": _entropy_bits(land_counts, _value_sum(land_counts)),
		"dominant_land_terrain_id": _dominant_key(land_counts, 0),
		"terrain_patch_count": int(patches.get("count", 0)),
		"terrain_largest_patch_cells": int(patches.get("largest", 0)),
		"terrain_patch_size_mean": float(patches.get("mean", 0.0)),
		"terrain_patch_size_variation": float(patches.get("variation", 0.0)),
		"water_cells": water_cells,
		"coastal_water_cells": coastal_water_cells,
		"walkable_shallow_cells": walkable_shallow_cells,
		"deep_water_cells": deep_water_cells,
		"water_depth_type_count": water_depth_type_count,
		"walkable_shallow_ratio": float(walkable_shallow_cells) / float(maxi(1, water_cells)),
		"deep_water_ratio": float(deep_water_cells) / float(maxi(1, water_cells)),
	}


static func _terrain_patch_metrics(size: Vector2i, terrain_ids: Array) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(terrain_ids.size())
	var patch_count := 0
	var largest := 0
	var size_sum_squared := 0.0
	for start_index in range(terrain_ids.size()):
		if visited[start_index] != 0:
			continue
		patch_count += 1
		var terrain_id := int(terrain_ids[start_index])
		var queue := PackedInt32Array([start_index])
		visited[start_index] = 1
		var cursor := 0
		while cursor < queue.size():
			var index := int(queue[cursor])
			cursor += 1
			for neighbor in _neighbor_indices(index % size.x, index / size.x, size):
				if visited[neighbor] == 0 and int(terrain_ids[neighbor]) == terrain_id:
					visited[neighbor] = 1
					queue.append(neighbor)
		var patch_size := queue.size()
		largest = maxi(largest, patch_size)
		size_sum_squared += float(patch_size * patch_size)
	var mean := float(terrain_ids.size()) / float(maxi(1, patch_count))
	var variance := maxf(0.0, size_sum_squared / float(maxi(1, patch_count)) - mean * mean)
	return {
		"count": patch_count,
		"largest": largest,
		"mean": mean,
		"variation": sqrt(variance) / mean if mean > 0.0 else 0.0,
	}


static func _empty_space_metrics(size: Vector2i, walkable_mask: PackedByteArray, feature_mask: PackedByteArray, zone_ids: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var distance := PackedInt32Array()
	distance.resize(size.x * size.y)
	distance.fill(-1)
	var queue := PackedInt32Array()
	for index in range(distance.size()):
		var x := index % size.x
		var y := index / size.x
		if walkable_mask[index] == 0 or feature_mask[index] != 0 or x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
			distance[index] = 0
			queue.append(index)
	var cursor := 0
	while cursor < queue.size():
		var index := int(queue[cursor])
		cursor += 1
		for neighbor in _neighbor_indices(index % size.x, index / size.x, size):
			if distance[neighbor] < 0 and walkable_mask[neighbor] != 0:
				distance[neighbor] = distance[index] + 1
				queue.append(neighbor)
	var land_cells := 0
	var empty_cells := 0
	var largest_radius := 0
	for index in range(distance.size()):
		if walkable_mask[index] == 0:
			continue
		land_cells += 1
		largest_radius = maxi(largest_radius, int(distance[index]))
		if distance[index] >= EMPTY_DISTANCE_THRESHOLD_CELLS:
			empty_cells += 1
	var windows := _empty_window_metrics(size, walkable_mask, feature_mask)
	var result := {
		"empty_distance_threshold_cells": EMPTY_DISTANCE_THRESHOLD_CELLS,
		"largest_empty_radius_cells": largest_radius,
		"empty_land_cells": empty_cells,
		"empty_land_ratio": float(empty_cells) / float(maxi(1, land_cells)),
		"empty_window_size_cells": int(windows.get("window_size", 0)),
		"empty_window_count": int(windows.get("empty", 0)),
		"eligible_window_count": int(windows.get("eligible", 0)),
		"empty_window_ratio": float(windows.get("ratio", 0.0)),
	}
	result.merge(_zoned_empty_space_metrics(distance, walkable_mask, feature_mask, zone_ids), true)
	return result


static func _zoned_empty_space_metrics(distance: PackedInt32Array, walkable_mask: PackedByteArray, feature_mask: PackedByteArray, zone_ids: PackedInt32Array) -> Dictionary:
	if zone_ids.size() != distance.size():
		return {}
	var land_counts: Dictionary = {}
	var empty_counts: Dictionary = {}
	var feature_counts: Dictionary = {}
	var largest_radius: Dictionary = {}
	for zone_id in [RandomMapZones.ZONE_TERRITORY, RandomMapZones.ZONE_CONTESTED, RandomMapZones.ZONE_FRONTIER]:
		land_counts[zone_id] = 0
		empty_counts[zone_id] = 0
		feature_counts[zone_id] = 0
		largest_radius[zone_id] = 0
	for index in range(distance.size()):
		var zone_id := int(zone_ids[index])
		if walkable_mask[index] == 0 or not land_counts.has(zone_id):
			continue
		land_counts[zone_id] = int(land_counts[zone_id]) + 1
		feature_counts[zone_id] = int(feature_counts[zone_id]) + int(feature_mask[index])
		largest_radius[zone_id] = maxi(int(largest_radius[zone_id]), int(distance[index]))
		if distance[index] >= EMPTY_DISTANCE_THRESHOLD_CELLS:
			empty_counts[zone_id] = int(empty_counts[zone_id]) + 1
	var empty_ratios: Dictionary = {}
	var radii: Dictionary = {}
	var densities: Dictionary = {}
	var outer_largest_radius := 0
	var outer_empty_ratio_max := 0.0
	var minimum_density := INF
	var maximum_density := 0.0
	for zone_id in [RandomMapZones.ZONE_TERRITORY, RandomMapZones.ZONE_CONTESTED, RandomMapZones.ZONE_FRONTIER]:
		var zone_name := String(RandomMapZones.ZONE_NAMES[zone_id])
		var land_count := int(land_counts[zone_id])
		var empty_ratio := float(empty_counts[zone_id]) / float(maxi(1, land_count))
		var density := _per_thousand(int(feature_counts[zone_id]), land_count)
		empty_ratios[zone_name] = empty_ratio
		radii[zone_name] = int(largest_radius[zone_id])
		densities[zone_name] = density
		if land_count > 0:
			outer_largest_radius = maxi(outer_largest_radius, int(largest_radius[zone_id]))
			outer_empty_ratio_max = maxf(outer_empty_ratio_max, empty_ratio)
			minimum_density = minf(minimum_density, density)
			maximum_density = maxf(maximum_density, density)
	return {
		"empty_land_ratio_by_zone": empty_ratios,
		"largest_empty_radius_cells_by_zone": radii,
		"feature_density_per_1000_by_zone": densities,
		"outer_largest_empty_radius_cells": outer_largest_radius,
		"outer_empty_land_ratio_max": outer_empty_ratio_max,
		"outer_feature_density_spread_per_1000": maximum_density - minimum_density if not is_inf(minimum_density) else 0.0,
	}


static func _empty_window_metrics(size: Vector2i, walkable_mask: PackedByteArray, feature_mask: PackedByteArray) -> Dictionary:
	var window_size := clampi(roundi(float(mini(size.x, size.y)) / 6.0), 6, 16)
	var eligible := 0
	var empty := 0
	for window_y in range(0, size.y, window_size):
		for window_x in range(0, size.x, window_size):
			var cell_count := 0
			var land_count := 0
			var feature_count := 0
			for y in range(window_y, mini(size.y, window_y + window_size)):
				for x in range(window_x, mini(size.x, window_x + window_size)):
					var index := y * size.x + x
					cell_count += 1
					if walkable_mask[index] != 0:
						land_count += 1
						feature_count += int(feature_mask[index])
			if land_count * 2 < cell_count:
				continue
			eligible += 1
			if feature_count == 0:
				empty += 1
	return {
		"window_size": window_size,
		"eligible": eligible,
		"empty": empty,
		"ratio": float(empty) / float(maxi(1, eligible)),
	}


static func _strategic_zone_metrics(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var strategic_zones: Dictionary = map_data.get("strategic_zones", {})
	if strategic_zones.is_empty():
		return {
			"strategic_zone_cell_count": 0,
			"strategic_zone_counts": {},
			"coastal_land_cells": 0,
			"sanctuary_balance_ratio": 0.0,
		}
	var sanctuary_by_team: Dictionary = strategic_zones.get("sanctuary_cell_count_by_team", {})
	var minimum_sanctuary := INF
	var maximum_sanctuary := 0
	for player_value in definition.get("players", []):
		var team_key := String.num_int64(int(player_value.get("team", 0)))
		var count := int(sanctuary_by_team.get(team_key, 0))
		minimum_sanctuary = minf(minimum_sanctuary, count)
		maximum_sanctuary = maxi(maximum_sanctuary, count)
	return {
		"strategic_zone_cell_count": strategic_zones.get("zone_ids", PackedInt32Array()).size(),
		"strategic_zone_counts": strategic_zones.get("zone_counts", {}).duplicate(true),
		"coastal_land_cells": int(strategic_zones.get("coastal_land_cells", 0)),
		"sanctuary_cell_count_by_team": sanctuary_by_team.duplicate(true),
		"sanctuary_balance_ratio": float(minimum_sanctuary) / float(maximum_sanctuary) if minimum_sanctuary != INF and maximum_sanctuary > 0 else 0.0,
	}


static func _resource_contestability_metrics(definition: Dictionary, map_data: Dictionary, walkable_mask: PackedByteArray) -> Dictionary:
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var neutral_resources: Array[Dictionary] = []
	for resource_value in map_data.get("resources", []):
		var resource: Dictionary = resource_value
		if not resource.get("owner_start", []).is_empty() or String(resource.get("placement_domain", "land")) != "land":
			continue
		var cell := Vector2i(Vector2(resource.get("position", Vector2.ZERO)))
		if _mask_has(walkable_mask, size, cell):
			neutral_resources.append(resource)
	var players: Array = definition.get("players", [])
	var distance_analysis: Dictionary = map_data.get("strategic_zones", {})
	var nearest_owner: PackedInt32Array = distance_analysis.get("nearest_start_indices", PackedInt32Array())
	var nearest_distance: PackedInt32Array = distance_analysis.get("nearest_start_distances", PackedInt32Array())
	var second_distance: PackedInt32Array = distance_analysis.get("second_start_distances", PackedInt32Array())
	if nearest_owner.size() != size.x * size.y or nearest_distance.size() != size.x * size.y or second_distance.size() != size.x * size.y:
		distance_analysis = RandomMapZones.analyze_distances(players, size, walkable_mask)
		nearest_owner = distance_analysis["nearest_start_indices"]
		nearest_distance = distance_analysis["nearest_start_distances"]
		second_distance = distance_analysis["second_start_distances"]
	var contested := 0
	var frontier := 0
	var safe := 0
	var accessible := 0
	var safety_sum := 0.0
	var distance_sum := 0.0
	var safe_by_team: Dictionary = {}
	for player_value in players:
		safe_by_team[String.num_int64(int(player_value.get("team", 0)))] = 0
	for resource in neutral_resources:
		var cell := Vector2i(Vector2(resource.get("position", Vector2.ZERO)))
		var index := cell.y * size.x + cell.x
		var player_index := int(nearest_owner[index])
		if player_index < 0:
			continue
		accessible += 1
		var nearest := int(nearest_distance[index])
		var second := int(second_distance[index]) if second_distance[index] >= 0 else nearest + maxi(size.x, size.y)
		var safety := float(second - nearest) / float(maxi(1, second + nearest))
		safety_sum += safety
		distance_sum += nearest
		if safety <= CONTESTED_RESOURCE_SAFETY_MAX:
			contested += 1
		elif safety >= SAFE_RESOURCE_SAFETY_MIN:
			safe += 1
			var team_key := String.num_int64(int(players[player_index].get("team", 0)))
			safe_by_team[team_key] = int(safe_by_team.get(team_key, 0)) + 1
		else:
			frontier += 1
	return {
		"neutral_land_resource_count": neutral_resources.size(),
		"accessible_neutral_land_resource_count": accessible,
		"contested_neutral_resource_count": contested,
		"frontier_neutral_resource_count": frontier,
		"safe_neutral_resource_count": safe,
		"mean_neutral_resource_safety": safety_sum / float(maxi(1, accessible)),
		"mean_neutral_resource_path_distance": distance_sum / float(maxi(1, accessible)),
		"safe_neutral_resource_count_by_team": safe_by_team,
	}


static func _walkable_land_mask(size: Vector2i, terrain_ids: Array, cliff_lookup: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size.x * size.y)
	for index in range(terrain_ids.size()):
		var cell := Vector2i(index % size.x, index / size.x)
		var terrain_id := int(terrain_ids[index])
		if not cliff_lookup.has(cell) and TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(terrain_id)):
			result[index] = 1
	return result


static func _land_feature_mask(size: Vector2i, terrain_ids: Array, walkable_mask: PackedByteArray, object_cells: Dictionary, cliff_lookup: Dictionary, dominant_land_terrain_id: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size.x * size.y)
	for index in range(terrain_ids.size()):
		if walkable_mask[index] != 0 and int(terrain_ids[index]) != dominant_land_terrain_id:
			result[index] = 1
	for cell_value in object_cells.keys():
		var cell := Vector2i(cell_value)
		if _mask_has(walkable_mask, size, cell):
			result[cell.y * size.x + cell.x] = 1
	for cell_value in cliff_lookup.keys():
		var cell := Vector2i(cell_value)
		for offset_value in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + Vector2i(offset_value)
			if _mask_has(walkable_mask, size, neighbor):
				result[neighbor.y * size.x + neighbor.x] = 1
	return result


static func _object_cell_lookup(map_data: Dictionary, size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for value in map_data.get("resources", []) + map_data.get("scenery", []):
		if value is Dictionary:
			var cell := Vector2i(Vector2(value.get("position", Vector2.ZERO)))
			if _in_bounds(cell, size):
				result[cell] = true
	return result


static func _cell_lookup(values: Array, size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		var cell := Vector2i(value)
		if _in_bounds(cell, size):
			result[cell] = true
	return result


static func _neighbor_indices(x: int, y: int, size: Vector2i) -> PackedInt32Array:
	var result := PackedInt32Array()
	if x > 0:
		result.append(y * size.x + x - 1)
	if x + 1 < size.x:
		result.append(y * size.x + x + 1)
	if y > 0:
		result.append((y - 1) * size.x + x)
	if y + 1 < size.y:
		result.append((y + 1) * size.x + x)
	return result


static func _entropy_bits(counts: Dictionary, total: int) -> float:
	if total <= 0:
		return 0.0
	var result := 0.0
	for count_value in counts.values():
		var probability := float(count_value) / float(total)
		if probability > 0.0:
			result -= probability * log(probability) / log(2.0)
	return result


static func _dominant_key(counts: Dictionary, fallback: int) -> int:
	var result := fallback
	var best_count := -1
	var keys: Array = counts.keys()
	keys.sort()
	for key_value in keys:
		var count := int(counts[key_value])
		if count > best_count:
			best_count = count
			result = int(key_value)
	return result


static func _value_sum(values: Dictionary) -> int:
	var result := 0
	for value in values.values():
		result += int(value)
	return result


static func _mask_count(mask: PackedByteArray) -> int:
	var result := 0
	for value in mask:
		result += int(value)
	return result


static func _mask_has(mask: PackedByteArray, size: Vector2i, cell: Vector2i) -> bool:
	return _in_bounds(cell, size) and mask[cell.y * size.x + cell.x] != 0


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _per_thousand(count: int, total: int) -> float:
	return float(count) * 1000.0 / float(maxi(1, total))
