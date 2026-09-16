class_name RoRRandomMapQuality
extends RefCounted

const WATER_TERRAINS := [1, 22]


static func inspect(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	var generator: Dictionary = definition.get("map", {}).get("generator", {})
	var players: Array = definition.get("players", [])
	if terrain_ids.size() != size.x * size.y:
		return {"valid": false, "errors": ["random_map_terrain_size_mismatch"], "metrics": {}}
	var starts: Array[Vector2] = []
	for player_value in players:
		var start := Vector2(player_value.get("start", Vector2.ZERO))
		starts.append(start)
		if _is_water(Vector2i(floori(start.x), floori(start.y)), size, terrain_ids):
			errors.append("random_map_start_on_water:%d" % int(player_value.get("team", 0)))

	var minimum_distance := INF
	for first_index in range(starts.size()):
		for second_index in range(first_index + 1, starts.size()):
			minimum_distance = minf(minimum_distance, starts[first_index].distance_to(starts[second_index]))
	var quality: Dictionary = generator.get("quality_contract", {})
	var required_distance := maxf(4.0, mini(size.x, size.y) * float(quality.get("minimum_start_distance_fraction", 0.08)))
	if starts.size() > 1 and minimum_distance + 0.0001 < required_distance:
		errors.append("random_map_start_distance_below_minimum")

	var water_cells := terrain_ids.filter(func(value): return int(value) in WATER_TERRAINS).size()
	var water_ratio := float(water_cells) / float(maxi(1, terrain_ids.size()))
	var ratio_range: Array = generator.get("water_ratio", [0.0, 1.0])
	if ratio_range.size() >= 2 and (water_ratio + 0.0001 < float(ratio_range[0]) or water_ratio - 0.0001 > float(ratio_range[1])):
		errors.append("random_map_water_ratio_out_of_range")

	var component_sizes: Array[int] = []
	for start in starts:
		component_sizes.append(_land_component(Vector2i(floori(start.x), floori(start.y)), size, terrain_ids).size())
	var minimum_component := int(quality.get("minimum_land_component_cells", 64))
	for index in range(component_sizes.size()):
		if component_sizes[index] < minimum_component:
			errors.append("random_map_start_land_too_small:%d" % int(players[index].get("team", 0)))
	if bool(generator.get("requires_shared_land", false)) and not starts.is_empty():
		var shared := _land_component(Vector2i(floori(starts[0].x), floori(starts[0].y)), size, terrain_ids)
		for index in range(1, starts.size()):
			if not shared.has(Vector2i(floori(starts[index].x), floori(starts[index].y))):
				errors.append("random_map_shared_land_disconnected")
				break

	var naval_zones: Array = map_data.get("naval_start_zones", [])
	if bool(generator.get("requires_naval_starts", false)) and naval_zones.size() != players.size():
		errors.append("random_map_naval_start_missing")
	var resource_errors := _resource_errors(starts, players, map_data.get("resources", []), quality, naval_zones, size, terrain_ids)
	errors.append_array(resource_errors)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"metrics": {
			"player_count": players.size(),
			"minimum_start_distance": minimum_distance if minimum_distance != INF else 0.0,
			"required_start_distance": required_distance,
			"water_ratio": water_ratio,
			"land_component_cells": component_sizes,
			"naval_start_count": naval_zones.size(),
		},
	}


static func _resource_errors(starts: Array[Vector2], players: Array, resources: Array, quality: Dictionary, naval_zones: Array, size: Vector2i, terrain_ids: Array) -> Array[String]:
	var errors: Array[String] = []
	var radius := float(quality.get("resource_radius", 8.0))
	var required: Dictionary = quality.get("resource_counts", {})
	for index in range(starts.size()):
		for kind in required:
			var nearby := resources.filter(func(resource):
				return String(resource.get("kind", "")) == String(kind) and Vector2(resource.get("position", Vector2.ZERO)).distance_to(starts[index]) <= radius
			).size()
			if nearby < int(required[kind]):
				errors.append("random_map_resource_guarantee_missing:%d:%s" % [int(players[index].get("team", 0)), String(kind)])
	var naval_radius := float(quality.get("naval_resource_radius", 12.0))
	var naval_required: Dictionary = quality.get("naval_resource_counts", {})
	var minimum_water_clearance := maxi(0, int(quality.get("naval_resource_minimum_water_clearance_cells", 0)))
	for zone_value in naval_zones:
		var zone: Dictionary = zone_value
		var water_staging := Vector2(zone.get("water_staging", Vector2.ZERO))
		for kind in naval_required:
			var nearby := resources.filter(func(resource):
				var resource_cell := Vector2i(Vector2(resource.get("position", Vector2.ZERO)))
				return String(resource.get("kind", "")) == String(kind) and Vector2(resource.get("position", Vector2.ZERO)).distance_to(water_staging) <= naval_radius and _water_clearance(resource_cell, size, terrain_ids, minimum_water_clearance)
			).size()
			if nearby < int(naval_required[kind]):
				errors.append("random_map_naval_resource_guarantee_missing:%d:%s" % [int(zone.get("team", 0)), String(kind)])
	return errors


static func _water_clearance(cell: Vector2i, size: Vector2i, terrain_ids: Array, clearance_cells: int) -> bool:
	for y in range(cell.y - clearance_cells, cell.y + clearance_cells + 1):
		for x in range(cell.x - clearance_cells, cell.x + clearance_cells + 1):
			if x < 0 or y < 0 or x >= size.x or y >= size.y or not _is_water(Vector2i(x, y), size, terrain_ids):
				return false
	return true


static func _land_component(start: Vector2i, size: Vector2i, terrain_ids: Array) -> Dictionary:
	var visited: Dictionary = {}
	if start.x < 0 or start.y < 0 or start.x >= size.x or start.y >= size.y or _is_water(start, size, terrain_ids):
		return visited
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + Vector2i(offset)
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y or visited.has(neighbor) or _is_water(neighbor, size, terrain_ids):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited


static func _is_water(cell: Vector2i, size: Vector2i, terrain_ids: Array) -> bool:
	return cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or int(terrain_ids[cell.y * size.x + cell.x]) in WATER_TERRAINS
