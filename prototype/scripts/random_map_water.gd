class_name RoRRandomMapWater
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")

const COASTAL_WATER_TERRAIN_ID := 1
const WALKABLE_SHALLOW_TERRAIN_ID := 4
const DEEP_WATER_TERRAIN_ID := 22
const ORTHOGONAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func apply(terrain_ids: Array[int], size: Vector2i, seed: int, topology: String = "") -> Dictionary:
	if size.x <= 0 or size.y <= 0 or terrain_ids.size() != size.x * size.y:
		return {}
	var distance_from_land := water_distance_from_land(terrain_ids, size)
	var water_cells := 0
	for index in range(terrain_ids.size()):
		if int(terrain_ids[index]) not in TerrainRules.WATER_TERRAIN_IDS:
			continue
		water_cells += 1
		var distance := int(distance_from_land[index])
		if distance <= 2:
			terrain_ids[index] = COASTAL_WATER_TERRAIN_ID
		elif distance >= 5:
			terrain_ids[index] = DEEP_WATER_TERRAIN_ID
		else:
			var cell := Vector2i(index % size.x, index / size.x)
			var noise := _smooth_noise(Vector2(cell), 11.0, seed ^ 0x2AF51) * 0.72 + _smooth_noise(Vector2(cell), 4.0, seed ^ 0x741C3) * 0.28
			var threshold := 0.30 if distance == 3 else -0.18
			terrain_ids[index] = DEEP_WATER_TERRAIN_ID if noise > threshold else COASTAL_WATER_TERRAIN_ID
	var sandbar_anchors: Array[Vector2i] = []
	if water_cells > 0 and topology in ["coastal", "continental", "mediterranean", "islands"]:
		sandbar_anchors = _paint_sandbars(terrain_ids, size, distance_from_land, seed, water_cells)
	var coastal_cells := 0
	var deep_cells := 0
	var shallow_cells := 0
	for terrain_id in terrain_ids:
		match int(terrain_id):
			COASTAL_WATER_TERRAIN_ID: coastal_cells += 1
			DEEP_WATER_TERRAIN_ID: deep_cells += 1
			WALKABLE_SHALLOW_TERRAIN_ID: shallow_cells += 1
	return {
		"coastal_water_cells": coastal_cells,
		"deep_water_cells": deep_cells,
		"walkable_shallow_cells": shallow_cells,
		"sandbar_count": sandbar_anchors.size(),
		"sandbar_anchors": sandbar_anchors,
	}


static func water_distance_from_land(terrain_ids: Array[int], size: Vector2i) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(size.x * size.y)
	distances.fill(-1)
	var queue := PackedInt32Array()
	for index in range(terrain_ids.size()):
		if int(terrain_ids[index]) not in TerrainRules.WATER_TERRAIN_IDS:
			distances[index] = 0
			queue.append(index)
	var cursor := 0
	while cursor < queue.size():
		var index := int(queue[cursor])
		cursor += 1
		var cell := Vector2i(index % size.x, index / size.x)
		for offset in ORTHOGONAL_DIRECTIONS:
			var neighbor: Vector2i = cell + offset
			if not _in_bounds(neighbor, size):
				continue
			var neighbor_index := neighbor.y * size.x + neighbor.x
			if distances[neighbor_index] >= 0:
				continue
			distances[neighbor_index] = distances[index] + 1
			queue.append(neighbor_index)
	return distances


static func _paint_sandbars(terrain_ids: Array[int], size: Vector2i, distances: PackedInt32Array, seed: int, water_cells: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			var cell := Vector2i(x, y)
			var index := y * size.x + x
			if int(terrain_ids[index]) in TerrainRules.WATER_TERRAIN_IDS and int(distances[index]) == 1 and _land_direction(cell, terrain_ids, size) != Vector2i.ZERO:
				candidates.append(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5A11D8A7
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = value
	var target_count := clampi(roundi(float(water_cells) / 420.0), 1, 24)
	var anchors: Array[Vector2i] = []
	for candidate in candidates:
		if anchors.size() >= target_count:
			break
		if anchors.any(func(other): return Vector2(candidate).distance_to(Vector2(other)) < 12.0):
			continue
		var land_direction := _land_direction(candidate, terrain_ids, size)
		var outward := -land_direction
		if outward == Vector2i.ZERO:
			continue
		var length := rng.randi_range(2, 4)
		var painted := 0
		for step in range(length):
			var cell: Vector2i = candidate + outward * step
			if not _in_bounds(cell, size):
				break
			var index := cell.y * size.x + cell.x
			if int(terrain_ids[index]) not in TerrainRules.WATER_TERRAIN_IDS or int(distances[index]) > 3:
				break
			terrain_ids[index] = WALKABLE_SHALLOW_TERRAIN_ID
			painted += 1
			if step > 0 and rng.randf() < 0.38:
				var side := Vector2i(-outward.y, outward.x) * (-1 if rng.randf() < 0.5 else 1)
				var side_cell: Vector2i = cell + side
				if _in_bounds(side_cell, size):
					var side_index := side_cell.y * size.x + side_cell.x
					if int(terrain_ids[side_index]) in TerrainRules.WATER_TERRAIN_IDS and int(distances[side_index]) <= 3:
						terrain_ids[side_index] = WALKABLE_SHALLOW_TERRAIN_ID
		if painted > 0:
			anchors.append(candidate)
	return anchors


static func _land_direction(cell: Vector2i, terrain_ids: Array[int], size: Vector2i) -> Vector2i:
	var result := Vector2i.ZERO
	for offset in ORTHOGONAL_DIRECTIONS:
		var neighbor: Vector2i = cell + offset
		if _in_bounds(neighbor, size) and int(terrain_ids[neighbor.y * size.x + neighbor.x]) not in TerrainRules.WATER_TERRAIN_IDS:
			result += offset
	if result == Vector2i.ZERO:
		return result
	if absi(result.x) >= absi(result.y):
		return Vector2i(signi(result.x), 0)
	return Vector2i(0, signi(result.y))


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
	var value := (int(cell.x) * 73856093) ^ (int(cell.y) * 19349663) ^ (seed * 83492791)
	value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
	value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return float(value) / 4294967295.0 * 2.0 - 1.0


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y
