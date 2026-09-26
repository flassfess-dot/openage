class_name RoRRandomMapQuality
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")


static func inspect(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	var vertex_levels: Array = map_data.get("vertex_levels", [])
	var generator: Dictionary = definition.get("map", {}).get("generator", {})
	var players: Array = definition.get("players", [])
	if terrain_ids.size() != size.x * size.y:
		return {"valid": false, "errors": ["random_map_terrain_size_mismatch"], "metrics": {}}
	var cliff_cells: Array = map_data.get("cliff_cells", [])
	var cliff_lookup: Dictionary = {}
	for value in cliff_cells:
		var cell: Vector2i = value
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or _is_water(cell, size, terrain_ids) or cliff_lookup.has(cell):
			errors.append("random_map_cliff_cell_invalid")
			continue
		cliff_lookup[cell] = true
	if String(generator.get("cliff_profile", "")) != "" and cliff_lookup.is_empty():
		errors.append("random_map_cliffs_missing")
	var starts: Array[Vector2] = []
	for player_value in players:
		var start := Vector2(player_value.get("start", Vector2.ZERO))
		starts.append(start)
		if _is_water(Vector2i(floori(start.x), floori(start.y)), size, terrain_ids):
			errors.append("random_map_start_on_water:%d" % int(player_value.get("team", 0)))
		if not _is_walkable_land(Vector2i(start), size, terrain_ids, cliff_lookup):
			errors.append("random_map_start_not_walkable:%d" % int(player_value.get("team", 0)))
		if cliff_lookup.has(Vector2i(start)):
			errors.append("random_map_start_on_cliff:%d" % int(player_value.get("team", 0)))

	var minimum_distance := INF
	for first_index in range(starts.size()):
		for second_index in range(first_index + 1, starts.size()):
			minimum_distance = minf(minimum_distance, starts[first_index].distance_to(starts[second_index]))
	var quality: Dictionary = generator.get("quality_contract", {})
	var required_distance := maxf(4.0, mini(size.x, size.y) * float(quality.get("minimum_start_distance_fraction", 0.08)))
	if starts.size() > 1 and minimum_distance + 0.0001 < required_distance:
		errors.append("random_map_start_distance_below_minimum")

	var water_cells := terrain_ids.filter(func(value): return int(value) in TerrainRules.WATER_TERRAIN_IDS).size()
	var water_ratio := float(water_cells) / float(maxi(1, terrain_ids.size()))
	var ratio_range: Array = generator.get("water_ratio", [0.0, 1.0])
	if ratio_range.size() >= 2 and (water_ratio + 0.0001 < float(ratio_range[0]) or water_ratio - 0.0001 > float(ratio_range[1])):
		errors.append("random_map_water_ratio_out_of_range")

	var component_sizes: Array[int] = []
	var component_id_by_cell: Dictionary = {}
	var component_size_by_id: Dictionary = {}
	for start in starts:
		var start_cell := Vector2i(floori(start.x), floori(start.y))
		if not component_id_by_cell.has(start_cell):
			var component := _land_component(start_cell, size, terrain_ids, cliff_lookup)
			var component_id := component_size_by_id.size()
			component_size_by_id[component_id] = component.size()
			for cell_value in component.keys():
				component_id_by_cell[cell_value] = component_id
		component_sizes.append(int(component_size_by_id.get(component_id_by_cell.get(start_cell, -1), 0)))
	var minimum_component := int(quality.get("minimum_land_component_cells", 64))
	for index in range(component_sizes.size()):
		if component_sizes[index] < minimum_component:
			errors.append("random_map_start_land_too_small:%d" % int(players[index].get("team", 0)))
	if bool(generator.get("requires_shared_land", false)) and not starts.is_empty():
		var shared_id := int(component_id_by_cell.get(Vector2i(starts[0]), -1))
		for index in range(1, starts.size()):
			if shared_id < 0 or int(component_id_by_cell.get(Vector2i(starts[index]), -2)) != shared_id:
				errors.append("random_map_shared_land_disconnected")
				break

	var naval_zones: Array = map_data.get("naval_start_zones", [])
	if bool(generator.get("requires_naval_starts", false)) and naval_zones.size() != players.size():
		errors.append("random_map_naval_start_missing")
	for zone_value in naval_zones:
		var zone: Dictionary = zone_value
		var land_cell := Vector2i(zone.get("land_staging", Vector2.ZERO))
		var water_cell := Vector2i(zone.get("water_staging", Vector2.ZERO))
		if not _is_walkable_land(land_cell, size, terrain_ids, cliff_lookup) or not _is_water(water_cell, size, terrain_ids):
			errors.append("random_map_naval_staging_invalid:%d" % int(zone.get("team", 0)))
	var resource_errors := _resource_errors(starts, players, map_data.get("resources", []), quality, naval_zones, size, terrain_ids, component_id_by_cell)
	errors.append_array(resource_errors)
	for resource_value in map_data.get("resources", []):
		var resource: Dictionary = resource_value
		var cell := Vector2i(resource.get("position", Vector2.ZERO))
		var domain := String(resource.get("placement_domain", "land"))
		if cliff_lookup.has(cell) or (domain in ["water", "shore_water"] and not _is_water(cell, size, terrain_ids)) or (domain == "shore_water" and not _is_shore_water(cell, size, terrain_ids)) or (domain == "land" and _is_water(cell, size, terrain_ids)) or not _valid_cell_gradient(cell, size, vertex_levels):
			errors.append("random_map_resource_domain_invalid:%s" % String(resource.get("kind", "")))
	for entity_value in definition.get("entities", []):
		var entity: Dictionary = entity_value
		var category := String(entity.get("category", ""))
		if category in ["unit", "building", "objective"] and cliff_lookup.has(Vector2i(entity.get("position", Vector2.ZERO))):
			errors.append("random_map_entity_on_cliff:%s" % category)
	var gate_width := 0
	if String(generator.get("topology", "")) == "narrows":
		var center_x := int(size.x / 2)
		var current_open := 0
		for y in range(size.y):
			if cliff_lookup.has(Vector2i(center_x, y)):
				current_open = 0
			else:
				current_open += 1
				gate_width = maxi(gate_width, current_open)
		if gate_width < int(quality.get("minimum_gate_width_cells", 5)):
			errors.append("random_map_narrows_gate_too_small")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"metrics": {
			"player_count": players.size(),
			"minimum_start_distance": minimum_distance if minimum_distance != INF else 0.0,
			"required_start_distance": required_distance,
			"water_ratio": water_ratio,
			"land_component_cells": component_sizes,
			"land_analysis_cells": component_id_by_cell.size(),
			"naval_start_count": naval_zones.size(),
			"cliff_cell_count": cliff_lookup.size(),
			"narrows_gate_width": gate_width,
		},
	}


static func _resource_errors(starts: Array[Vector2], players: Array, resources: Array, quality: Dictionary, naval_zones: Array, size: Vector2i, terrain_ids: Array, component_id_by_cell: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var radius := float(quality.get("resource_radius", 8.0))
	var required: Dictionary = quality.get("resource_counts", {})
	for index in range(starts.size()):
		var start_component := int(component_id_by_cell.get(Vector2i(starts[index]), -1))
		for kind in required:
			var nearby := resources.filter(func(resource):
				var position := Vector2(resource.get("position", Vector2.ZERO))
				var owner_values: Array = resource.get("owner_start", [])
				var owned := owner_values.is_empty() or (owner_values.size() >= 2 and Vector2(float(owner_values[0]), float(owner_values[1])).is_equal_approx(starts[index]))
				return owned and String(resource.get("kind", "")) == String(kind) and position.distance_to(starts[index]) <= radius and _resource_accessible_from_component(Vector2i(position), start_component, component_id_by_cell)
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


static func _land_component(start: Vector2i, size: Vector2i, terrain_ids: Array, cliff_cells: Dictionary = {}) -> Dictionary:
	var visited: Dictionary = {}
	if not _is_walkable_land(start, size, terrain_ids, cliff_cells):
		return visited
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + Vector2i(offset)
			if visited.has(neighbor) or not _is_walkable_land(neighbor, size, terrain_ids, cliff_cells):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited


static func _is_water(cell: Vector2i, size: Vector2i, terrain_ids: Array) -> bool:
	return cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or int(terrain_ids[cell.y * size.x + cell.x]) in TerrainRules.WATER_TERRAIN_IDS


static func _is_walkable_land(cell: Vector2i, size: Vector2i, terrain_ids: Array, cliff_cells: Dictionary = {}) -> bool:
	if _is_water(cell, size, terrain_ids) or cliff_cells.has(cell):
		return false
	return TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(int(terrain_ids[cell.y * size.x + cell.x])))


static func _resource_accessible_from_component(cell: Vector2i, component_id: int, component_by_cell: Dictionary) -> bool:
	if component_id < 0:
		return false
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if int(component_by_cell.get(cell + offset, -1)) == component_id:
			return true
	return false


static func _is_shore_water(cell: Vector2i, size: Vector2i, terrain_ids: Array) -> bool:
	if not _is_water(cell, size, terrain_ids):
		return false
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = cell + Vector2i(offset)
		if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and not _is_water(neighbor, size, terrain_ids):
			return true
	return false


static func _valid_cell_gradient(cell: Vector2i, size: Vector2i, vertex_levels: Array) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or vertex_levels.size() != (size.x + 1) * (size.y + 1):
		return false
	var width := size.x + 1
	var corners := [int(vertex_levels[cell.y * width + cell.x]), int(vertex_levels[cell.y * width + cell.x + 1]), int(vertex_levels[(cell.y + 1) * width + cell.x]), int(vertex_levels[(cell.y + 1) * width + cell.x + 1])]
	return int(corners.max()) - int(corners.min()) <= 1
