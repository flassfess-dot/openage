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
var surface_revision: int = 0
# Bounded journal of the exact cells changed by recent revision bumps. Consumers
# (open movement envelopes, caches) ask change_region_since() whether a change
# far away can affect them; null means the region is no longer bounded and the
# caller must treat the whole grid as changed.
var _change_log: Array = []


func _record_change(cell: Vector2i) -> void:
	# Invariant: the open entry stores the pre-bump revision and the single bump
	# its batch performs, so consecutive entries chain entry.from == prev.to.
	var region := Rect2(Vector2(cell), Vector2.ONE)
	if not _change_log.is_empty():
		var entry: Dictionary = _change_log[_change_log.size() - 1]
		if int(entry["from"]) == revision:
			entry["region"] = entry["region"].merge(region) if bool(entry["has_region"]) else region
			entry["has_region"] = true
			if bool(entry.get("cells_complete", false)):
				var cells: Array = entry["cells"]
				if cells.size() < 512:
					cells.append(cell)
				else:
					cells.clear()
					entry["cells_complete"] = false
			return
	_change_log.append({"from": revision, "to": revision + 1, "region": region, "has_region": true, "cells": [cell], "cells_complete": true})
	if _change_log.size() > 96:
		_change_log = _change_log.slice(_change_log.size() - 48)


func change_region_since(old_revision: int) -> Variant:
	# Rect2 covering every recorded change after old_revision, an empty Rect2
	# when nothing changed, or null when history no longer bounds the region.
	if old_revision == revision:
		return Rect2()
	if old_revision > revision:
		return null
	var covered_to := revision
	var region := Rect2()
	var have_region := false
	for index in range(_change_log.size() - 1, -1, -1):
		var entry: Dictionary = _change_log[index]
		if int(entry["to"]) != covered_to:
			return null
		if bool(entry["has_region"]):
			region = entry["region"].merge(region) if have_region else entry["region"]
			have_region = true
		covered_to = int(entry["from"])
		if covered_to <= old_revision:
			return region
	return null


func changed_cells_since(old_revision: int) -> Variant:
	# Exact local delta for AI knowledge. An expired journal or a large bulk edit
	# returns null so callers safely rebuild once instead of trusting a gap.
	if old_revision == revision:
		return []
	if old_revision > revision:
		return null
	var covered_to := revision
	var changed: Dictionary = {}
	for index in range(_change_log.size() - 1, -1, -1):
		var entry: Dictionary = _change_log[index]
		if int(entry["to"]) != covered_to or not bool(entry.get("cells_complete", false)):
			return null
		for cell in entry["cells"]:
			changed[cell] = true
		covered_to = int(entry["from"])
		if covered_to <= old_revision:
			return changed.keys()
	return null


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
	surface_revision += 1


func configure_terrain_ids(provider: Callable = Callable()) -> void:
	var changed := false
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			var value := int(provider.call(cell)) if provider.is_valid() else TerrainRules.terrain_id_for_logical(terrain(cell))
			if int(terrain_ids.get(cell, -1)) == value:
				continue
			terrain_ids[cell] = value
			_record_change(cell)
			changed = true
	if changed:
		revision += 1


func configure_restrictions(restrictions: Array) -> void:
	terrain_restrictions = restrictions.duplicate(true)
	surface_component_cache.clear()
	revision += 1
	surface_revision += 1


func set_terrain(cell: Vector2i, terrain_kind: String) -> void:
	if not contains(cell) or terrain_cells.get(cell) == terrain_kind:
		return
	terrain_cells[cell] = terrain_kind
	terrain_ids[cell] = TerrainRules.terrain_id_for_logical(terrain_kind)
	surface_component_cache.clear()
	revision += 1
	surface_revision += 1


func set_terrain_id(cell: Vector2i, terrain_id: int) -> void:
	if not contains(cell) or int(terrain_ids.get(cell, -1)) == terrain_id:
		return
	terrain_ids[cell] = terrain_id
	_record_change(cell)
	_invalidate_restricted_surface_components()
	revision += 1


func _invalidate_restricted_surface_components() -> void:
	# Terrain IDs affect source restrictions, but unrestricted land and water
	# components depend only on logical terrain. A felled tree must not rebuild
	# the connectivity of the entire map.
	for key_value in surface_component_cache.keys():
		if not String(key_value).ends_with(":-1"):
			surface_component_cache.erase(key_value)


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
	_record_change(cell)
	revision += 1


func rebuild(resources: Array, buildings: Array, static_obstructions: Array = []) -> void:
	# Full reconcile into a fresh map, then diff against the live one so an
	# unchanged world neither allocates a deep copy nor bumps the revision.
	var desired: Dictionary = {}
	for resource in resources:
		if int(resource.get("amount", 0)) <= 0 or not resource_blocks_navigation(resource):
			continue
		var cells: Array = resource.get("footprint", {}).get("occupied_cells", [Vector2i(floori(resource["pos"].x), floori(resource["pos"].y))])
		_append_occupants(desired, cells, "resource", int(resource.get("id", -1)))
	for building in buildings:
		if float(building.get("hp", 1.0)) <= 0.0:
			continue
		if bool(building.get("passable", false)) or "passable" in building.get("behavior_tags", []):
			continue
		_append_occupants(desired, building.get("occupied_cells", []), "building", int(building.get("id", -1)))
	for obstruction_value in static_obstructions:
		var obstruction: Dictionary = obstruction_value
		_append_occupants(desired, obstruction.get("occupied_cells", []), "static_obstruction", int(obstruction.get("id", -1)))
	var changed := false
	for cell_value in desired.keys():
		if occupied_cells.get(cell_value) != desired[cell_value]:
			_record_change(cell_value)
			changed = true
	for cell_value in occupied_cells.keys():
		if not desired.has(cell_value):
			_record_change(cell_value)
			changed = true
	occupied_cells = desired
	if changed:
		_invalidate_restricted_surface_components()
		revision += 1


func resource_blocks_navigation(resource: Dictionary) -> bool:
	if resource.has("blocks_navigation"):
		return bool(resource["blocks_navigation"])
	return "carcass" not in resource.get("behavior_tags", [])


func _append_occupants(target: Dictionary, cells: Array, category: String, entity_id: int) -> void:
	for cell_value in cells:
		var cell: Vector2i = cell_value
		if not contains(cell):
			continue
		if not target.has(cell):
			target[cell] = []
		target[cell].append({"category": category, "id": entity_id})


func occupy(cells: Array, category: String, entity_id: int) -> void:
	# Idempotent: re-occupying cells that already hold this occupant neither
	# duplicates entries nor bumps the revision.
	var changed := false
	for cell_value in cells:
		var cell: Vector2i = cell_value
		if not contains(cell):
			continue
		var current: Array = occupied_cells.get(cell, [])
		var already_present := false
		for occupant_value in current:
			var occupant: Dictionary = occupant_value
			if int(occupant.get("id", -1)) == entity_id and String(occupant.get("category", "")) == category:
				already_present = true
				break
		if already_present:
			continue
		if occupied_cells.has(cell):
			occupied_cells[cell].append({"category": category, "id": entity_id})
		else:
			occupied_cells[cell] = [{"category": category, "id": entity_id}]
		_record_change(cell)
		changed = true
	if changed:
		revision += 1


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
		_record_change(cell)
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
