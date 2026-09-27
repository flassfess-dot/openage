class_name RoRRandomMapZones
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")

const ZONE_BLOCKED := 0
const ZONE_SANCTUARY := 1
const ZONE_TERRITORY := 2
const ZONE_CONTESTED := 3
const ZONE_FRONTIER := 4

const ZONE_NAMES := {
	ZONE_BLOCKED: "blocked",
	ZONE_SANCTUARY: "sanctuary",
	ZONE_TERRITORY: "territory",
	ZONE_CONTESTED: "contested",
	ZONE_FRONTIER: "frontier",
}


static func build(players: Array, size: Vector2i, terrain_ids: Array, cliff_cells: Array, contract: Dictionary = {}) -> Dictionary:
	if size.x <= 0 or size.y <= 0 or terrain_ids.size() != size.x * size.y:
		return {}
	var walkable_mask := _walkable_land_mask(size, terrain_ids, _cell_lookup(cliff_cells, size))
	var distance_maps := analyze_distances(players, size, walkable_mask)
	var nearest_owner: PackedInt32Array = distance_maps["nearest_start_indices"]
	var nearest_distance: PackedInt32Array = distance_maps["nearest_start_distances"]
	var second_distance: PackedInt32Array = distance_maps["second_start_distances"]
	var zone_ids := PackedInt32Array()
	var coastal_mask := PackedByteArray()
	zone_ids.resize(size.x * size.y)
	coastal_mask.resize(size.x * size.y)
	var sanctuary_radius := clampi(
		int(contract.get("sanctuary_radius_cells", roundi(float(mini(size.x, size.y)) * 0.10))),
		int(contract.get("sanctuary_radius_min_cells", 7)),
		int(contract.get("sanctuary_radius_max_cells", 18))
	)
	var contested_max := float(contract.get("contested_safety_max", 0.12))
	var territory_min := float(contract.get("territory_safety_min", 0.30))
	var frontier_distance := maxi(sanctuary_radius + 3, int(contract.get("frontier_distance_cells", roundi(float(sanctuary_radius) * 2.4))))
	var zone_counts := _empty_zone_counts()
	var sanctuary_by_team: Dictionary = {}
	for player_value in players:
		sanctuary_by_team[String.num_int64(int(player_value.get("team", 0)))] = 0
	var coastal_count := 0
	for index in range(zone_ids.size()):
		if walkable_mask[index] == 0:
			zone_ids[index] = ZONE_BLOCKED
			zone_counts["blocked"] = int(zone_counts["blocked"]) + 1
			continue
		var cell := Vector2i(index % size.x, index / size.x)
		if _is_coastal_land(cell, size, terrain_ids):
			coastal_mask[index] = 1
			coastal_count += 1
		var owner := int(nearest_owner[index])
		var nearest := int(nearest_distance[index])
		var second := int(second_distance[index])
		var zone_id := ZONE_FRONTIER
		if owner >= 0 and nearest <= sanctuary_radius:
			zone_id = ZONE_SANCTUARY
		elif owner >= 0 and second >= 0:
			var safety := float(second - nearest) / float(maxi(1, second + nearest))
			if safety <= contested_max:
				zone_id = ZONE_CONTESTED
			elif nearest >= frontier_distance or safety < territory_min:
				zone_id = ZONE_FRONTIER
			else:
				zone_id = ZONE_TERRITORY
		elif owner >= 0 and nearest < frontier_distance:
			zone_id = ZONE_TERRITORY
		zone_ids[index] = zone_id
		var zone_name := String(ZONE_NAMES[zone_id])
		zone_counts[zone_name] = int(zone_counts[zone_name]) + 1
		if zone_id == ZONE_SANCTUARY and owner >= 0 and owner < players.size():
			var team_key := String.num_int64(int(players[owner].get("team", 0)))
			sanctuary_by_team[team_key] = int(sanctuary_by_team.get(team_key, 0)) + 1
	return {
		"schema_version": 1,
		"profile": String(contract.get("profile", "")),
		"zone_ids": zone_ids,
		"nearest_start_indices": nearest_owner,
		"nearest_start_distances": nearest_distance,
		"second_start_distances": second_distance,
		"coastal_land_mask": coastal_mask,
		"zone_counts": zone_counts,
		"sanctuary_cell_count_by_team": sanctuary_by_team,
		"coastal_land_cells": coastal_count,
		"sanctuary_radius_cells": sanctuary_radius,
		"frontier_distance_cells": frontier_distance,
		"contested_safety_max": contested_max,
		"territory_safety_min": territory_min,
	}


static func analyze_terrain_distances(players: Array, size: Vector2i, terrain_ids: Array, cliff_cells: Array = []) -> Dictionary:
	return analyze_distances(players, size, _walkable_land_mask(size, terrain_ids, _cell_lookup(cliff_cells, size)))


static func analyze_distances(players: Array, size: Vector2i, walkable_mask: PackedByteArray) -> Dictionary:
	var nearest_owner := PackedInt32Array()
	var nearest_distance := PackedInt32Array()
	var second_owner := PackedInt32Array()
	var second_distance := PackedInt32Array()
	nearest_owner.resize(size.x * size.y)
	nearest_owner.fill(-1)
	nearest_distance.resize(size.x * size.y)
	nearest_distance.fill(-1)
	second_owner.resize(size.x * size.y)
	second_owner.fill(-1)
	second_distance.resize(size.x * size.y)
	second_distance.fill(-1)
	var queue_cells := PackedInt32Array()
	var queue_owners := PackedInt32Array()
	var queue_distances := PackedInt32Array()
	for player_index in range(players.size()):
		var start := Vector2i(Vector2(players[player_index].get("start", Vector2.ZERO)))
		if not _mask_has(walkable_mask, size, start):
			continue
		var index := start.y * size.x + start.x
		nearest_owner[index] = player_index
		nearest_distance[index] = 0
		queue_cells.append(index)
		queue_owners.append(player_index)
		queue_distances.append(0)
	var cursor := 0
	while cursor < queue_cells.size():
		var index := int(queue_cells[cursor])
		var owner := int(queue_owners[cursor])
		var distance := int(queue_distances[cursor])
		cursor += 1
		if not ((nearest_owner[index] == owner and nearest_distance[index] == distance) or (second_owner[index] == owner and second_distance[index] == distance)):
			continue
		for neighbor in _neighbor_indices(index % size.x, index / size.x, size):
			if walkable_mask[neighbor] == 0:
				continue
			var candidate_distance := distance + 1
			var accepted := false
			if nearest_owner[neighbor] == owner:
				if candidate_distance < nearest_distance[neighbor]:
					nearest_distance[neighbor] = candidate_distance
					accepted = true
			elif second_owner[neighbor] == owner:
				if candidate_distance < second_distance[neighbor]:
					second_distance[neighbor] = candidate_distance
					accepted = true
			elif nearest_owner[neighbor] < 0 or candidate_distance < nearest_distance[neighbor] or (candidate_distance == nearest_distance[neighbor] and owner < nearest_owner[neighbor]):
				second_owner[neighbor] = nearest_owner[neighbor]
				second_distance[neighbor] = nearest_distance[neighbor]
				nearest_owner[neighbor] = owner
				nearest_distance[neighbor] = candidate_distance
				accepted = true
			elif second_owner[neighbor] < 0 or candidate_distance < second_distance[neighbor] or (candidate_distance == second_distance[neighbor] and owner < second_owner[neighbor]):
				second_owner[neighbor] = owner
				second_distance[neighbor] = candidate_distance
				accepted = true
			if accepted:
				queue_cells.append(neighbor)
				queue_owners.append(owner)
				queue_distances.append(candidate_distance)
	return {
		"nearest_start_indices": nearest_owner,
		"nearest_start_distances": nearest_distance,
		"second_start_indices": second_owner,
		"second_start_distances": second_distance,
	}


static func zone_at(zones: Dictionary, size: Vector2i, cell: Vector2i) -> int:
	var zone_ids: PackedInt32Array = zones.get("zone_ids", PackedInt32Array())
	if not _in_bounds(cell, size) or zone_ids.size() != size.x * size.y:
		return ZONE_BLOCKED
	return int(zone_ids[cell.y * size.x + cell.x])


static func is_coastal_at(zones: Dictionary, size: Vector2i, cell: Vector2i) -> bool:
	var coastal_mask: PackedByteArray = zones.get("coastal_land_mask", PackedByteArray())
	return _in_bounds(cell, size) and coastal_mask.size() == size.x * size.y and coastal_mask[cell.y * size.x + cell.x] != 0


static func _walkable_land_mask(size: Vector2i, terrain_ids: Array, cliff_lookup: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size.x * size.y)
	for index in range(terrain_ids.size()):
		var cell := Vector2i(index % size.x, index / size.x)
		var terrain_id := int(terrain_ids[index])
		if not cliff_lookup.has(cell) and TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(terrain_id)):
			result[index] = 1
	return result


static func _is_coastal_land(cell: Vector2i, size: Vector2i, terrain_ids: Array) -> bool:
	for neighbor in _neighbor_cells(cell, size):
		if int(terrain_ids[neighbor.y * size.x + neighbor.x]) in TerrainRules.WATER_TERRAIN_IDS:
			return true
	return false


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


static func _neighbor_cells(cell: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset_value in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + Vector2i(offset_value)
		if _in_bounds(neighbor, size):
			result.append(neighbor)
	return result


static func _empty_zone_counts() -> Dictionary:
	return {"blocked": 0, "sanctuary": 0, "territory": 0, "contested": 0, "frontier": 0}


static func _mask_has(mask: PackedByteArray, size: Vector2i, cell: Vector2i) -> bool:
	return _in_bounds(cell, size) and mask.size() == size.x * size.y and mask[cell.y * size.x + cell.x] != 0


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y
