class_name RoRNavigationGrid

const TerrainRules := preload("res://scripts/terrain_rules.gd")

var size: Vector2i
var terrain_cells: Dictionary = {}
var terrain_ids: Dictionary = {}
var occupied_cells: Dictionary = {}
var elevation_cells: Dictionary = {}
var slope_cells: Dictionary = {}
var terrain_restrictions: Array = []
var surface_component_cache: Dictionary = {}
var revision: int = 0


func _init(grid_size: Vector2i = Vector2i.ONE) -> void:
	size = Vector2i(maxi(1, grid_size.x), maxi(1, grid_size.y))
	configure_terrain()
	configure_elevation()


func configure_terrain(provider: Callable = Callable()) -> void:
	terrain_cells.clear()
	terrain_ids.clear()
	surface_component_cache.clear()
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			var terrain_kind := String(provider.call(cell)) if provider.is_valid() else TerrainRules.terrain_at(cell)
			terrain_cells[cell] = terrain_kind
			terrain_ids[cell] = TerrainRules.terrain_id_for_logical(terrain_kind)
	revision += 1


func configure_terrain_ids(provider: Callable = Callable()) -> void:
	surface_component_cache.clear()
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			terrain_ids[cell] = int(provider.call(cell)) if provider.is_valid() else TerrainRules.terrain_id_for_logical(terrain(cell))
	revision += 1


func configure_restrictions(restrictions: Array) -> void:
	terrain_restrictions = restrictions.duplicate(true)
	surface_component_cache.clear()
	revision += 1


func set_terrain(cell: Vector2i, terrain_kind: String) -> void:
	if not contains(cell) or terrain_cells.get(cell) == terrain_kind:
		return
	terrain_cells[cell] = terrain_kind
	terrain_ids[cell] = TerrainRules.terrain_id_for_logical(terrain_kind)
	surface_component_cache.clear()
	revision += 1


func set_terrain_id(cell: Vector2i, terrain_id: int) -> void:
	if not contains(cell) or int(terrain_ids.get(cell, -1)) == terrain_id:
		return
	terrain_ids[cell] = terrain_id
	surface_component_cache.clear()
	revision += 1


func configure_elevation(provider: Callable = Callable()) -> void:
	elevation_cells.clear()
	slope_cells.clear()
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			var value: Variant = provider.call(cell) if provider.is_valid() else 0
			if value is Dictionary:
				elevation_cells[cell] = int(value.get("base_elevation", 0))
				slope_cells[cell] = not bool(value.get("is_flat", true)) or not bool(value.get("is_valid", true))
			else:
				elevation_cells[cell] = int(value)
				slope_cells[cell] = false
	revision += 1


func set_elevation(cell: Vector2i, level: int, slope: bool = false) -> void:
	if not contains(cell):
		return
	if int(elevation_cells.get(cell, 0)) == level and bool(slope_cells.get(cell, false)) == slope:
		return
	elevation_cells[cell] = level
	slope_cells[cell] = slope
	revision += 1


func rebuild(resources: Array, buildings: Array, static_obstructions: Array = []) -> void:
	var previous := occupied_cells.duplicate(true)
	occupied_cells.clear()
	for resource in resources:
		if int(resource.get("amount", 0)) <= 0:
			continue
		var cells: Array = resource.get("footprint", {}).get("occupied_cells", [Vector2i(floori(resource["pos"].x), floori(resource["pos"].y))])
		occupy(cells, "resource", int(resource["id"]))
	for building in buildings:
		if float(building.get("hp", 1.0)) <= 0.0:
			continue
		if bool(building.get("passable", false)) or "passable" in building.get("behavior_tags", []):
			continue
		occupy(building.get("occupied_cells", []), "building", int(building["id"]))
	for obstruction_value in static_obstructions:
		var obstruction: Dictionary = obstruction_value
		occupy(obstruction.get("occupied_cells", []), "static_obstruction", int(obstruction.get("id", -1)))
	if occupied_cells != previous:
		revision += 1


func occupy(cells: Array, category: String, entity_id: int) -> void:
	for cell in cells:
		if not contains(cell):
			continue
		if not occupied_cells.has(cell):
			occupied_cells[cell] = []
		occupied_cells[cell].append({"category": category, "id": entity_id})


func release_occupant(cells: Array, category: String, entity_id: int) -> void:
	var changed := false
	for cell_value in cells:
		var cell: Vector2i = cell_value
		if not occupied_cells.has(cell):
			continue
		var previous: Array = occupied_cells[cell]
		var remaining: Array = previous.filter(func(item):
			return String(item.get("category", "")) != category or int(item.get("id", -1)) != entity_id
		)
		if remaining.size() == previous.size():
			continue
		changed = true
		if remaining.is_empty():
			occupied_cells.erase(cell)
		else:
			occupied_cells[cell] = remaining
	if changed:
		revision += 1


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func terrain(cell: Vector2i) -> String:
	return String(terrain_cells.get(cell, "void"))


func terrain_id(cell: Vector2i) -> int:
	return int(terrain_ids.get(cell, -1))


func elevation(cell: Vector2i) -> int:
	return int(elevation_cells.get(cell, 0))


func is_slope(cell: Vector2i) -> bool:
	return bool(slope_cells.get(cell, false))


func is_walkable(cell: Vector2i) -> bool:
	return is_walkable_for(cell, "land")


func is_walkable_for(cell: Vector2i, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if not contains(cell) or occupied_cells.has(cell):
		return false
	if restriction_id >= 0 and not terrain_restrictions.is_empty():
		return TerrainRules.is_terrain_accessible(terrain_restrictions, restriction_id, terrain_id(cell))
	match movement_domain:
		"water": return TerrainRules.is_water_navigable(terrain(cell))
		"amphibious": return TerrainRules.is_land_walkable(terrain(cell)) or TerrainRules.is_water_navigable(terrain(cell))
		_: return TerrainRules.is_land_walkable(terrain(cell))


func is_position_walkable_for(position: Vector2, radius: float, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if not is_walkable_for(Vector2i(floori(position.x), floori(position.y)), movement_domain, restriction_id):
		return false
	if radius <= 0.0001:
		return true
	return (
		is_walkable_for(Vector2i(floori(position.x + radius), floori(position.y)), movement_domain, restriction_id)
		and is_walkable_for(Vector2i(floori(position.x - radius), floori(position.y)), movement_domain, restriction_id)
		and is_walkable_for(Vector2i(floori(position.x), floori(position.y + radius)), movement_domain, restriction_id)
		and is_walkable_for(Vector2i(floori(position.x), floori(position.y - radius)), movement_domain, restriction_id)
	)


func is_world_rect_walkable_for(minimum: Vector2, maximum: Vector2, margin: float, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	var minimum_cell := Vector2i(floori(minimum.x - margin), floori(minimum.y - margin))
	var maximum_cell := Vector2i(floori(maximum.x + margin), floori(maximum.y + margin))
	if not contains(minimum_cell) or not contains(maximum_cell):
		return false
	for y in range(minimum_cell.y, maximum_cell.y + 1):
		for x in range(minimum_cell.x, maximum_cell.x + 1):
			if not is_walkable_for(Vector2i(x, y), movement_domain, restriction_id):
				return false
	return true


func occupants(cell: Vector2i) -> Array:
	return occupied_cells.get(cell, []).duplicate(true)


func can_build(cells: Array) -> bool:
	return can_build_for(cells, "land", -1)


func can_build_for(cells: Array, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if cells.is_empty():
		return false
	var required_elevation: Variant = null
	for cell_value in cells:
		var cell: Vector2i = cell_value
		if not contains(cell) or not surface_accessible(cell, movement_domain, restriction_id) or occupied_cells.has(cell) or is_slope(cell):
			return false
		if required_elevation == null:
			required_elevation = elevation(cell)
		elif elevation(cell) != int(required_elevation):
			return false
	return true


func surface_accessible(cell: Vector2i, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if not contains(cell):
		return false
	if restriction_id >= 0 and not terrain_restrictions.is_empty():
		return TerrainRules.is_terrain_accessible(terrain_restrictions, restriction_id, terrain_id(cell))
	match movement_domain:
		"water": return TerrainRules.is_water_navigable(terrain(cell))
		"amphibious": return TerrainRules.is_land_walkable(terrain(cell)) or TerrainRules.is_water_navigable(terrain(cell))
		_: return TerrainRules.is_land_walkable(terrain(cell))


func surface_component_id(cell: Vector2i, movement_domain: String = "land", restriction_id: int = -1) -> int:
	if not contains(cell) or not surface_accessible(cell, movement_domain, restriction_id):
		return -1
	var key := "%s:%d" % [movement_domain, restriction_id]
	if not surface_component_cache.has(key):
		surface_component_cache[key] = _build_surface_components(movement_domain, restriction_id)
	return int(surface_component_cache[key].get(cell, -1))


func _build_surface_components(movement_domain: String, restriction_id: int) -> Dictionary:
	var result: Dictionary = {}
	var next_component_id := 0
	for y in range(size.y):
		for x in range(size.x):
			var start := Vector2i(x, y)
			if result.has(start) or not surface_accessible(start, movement_domain, restriction_id):
				continue
			var queue: Array[Vector2i] = [start]
			result[start] = next_component_id
			var cursor := 0
			while cursor < queue.size():
				var cell: Vector2i = queue[cursor]
				cursor += 1
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = cell + offset
					if not contains(neighbor) or result.has(neighbor) or not surface_accessible(neighbor, movement_domain, restriction_id):
						continue
					result[neighbor] = next_component_id
					queue.append(neighbor)
			next_component_id += 1
	return result


func can_place(cells: Array, movement_domain: String, restriction_id: int = -1) -> bool:
	if cells.is_empty():
		return false
	for cell_value in cells:
		var cell: Vector2i = cell_value
		if not is_walkable_for(cell, movement_domain, restriction_id):
			return false
	return true
