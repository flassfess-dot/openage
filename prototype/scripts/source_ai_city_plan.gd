class_name RoRSourceAiCityPlan
extends RefCounted

const SCHEMA_VERSION := 1
const WALL_KIND := "wall"

var team: int = 0
var initialized: bool = false
var enabled: bool = false
var anchor_entity_id: int = -1
var center: Vector2 = Vector2.ZERO
var minimum_town_size: int = 0
var maximum_town_size: int = 0
var gate_count: int = 0
var gate_size: int = 0
var perimeter_cells: Array[Vector2i] = []
var wall_cells: Array[Vector2i] = []
var gate_cells: Array[Vector2i] = []
var revision: int = 0


func _init(owner_team: int = 0) -> void:
	team = owner_team


func synchronize(snapshot: Dictionary, own_units: Array, own_buildings: Array, numbers: Dictionary) -> void:
	var requested := numbers.has(73) or numbers.has(74) or numbers.has(84) or numbers.has(85)
	if not requested:
		enabled = false
		return
	enabled = true
	var next_minimum := maxi(0, int(numbers.get(73, minimum_town_size)))
	var next_maximum := maxi(next_minimum, int(numbers.get(74, next_minimum)))
	var next_gate_count := maxi(0, int(numbers.get(84, gate_count)))
	var next_gate_size := maxi(0, int(numbers.get(85, gate_size)))
	var geometry_changed := (
		next_minimum != minimum_town_size
		or next_maximum != maximum_town_size
		or next_gate_count != gate_count
		or next_gate_size != gate_size
	)
	minimum_town_size = next_minimum
	maximum_town_size = next_maximum
	gate_count = next_gate_count
	gate_size = next_gate_size
	if not initialized:
		var anchor := _choose_anchor(snapshot, own_units, own_buildings)
		anchor_entity_id = int(anchor.get("id", -1))
		center = Vector2(anchor.get("position", Vector2.ZERO))
		initialized = true
		geometry_changed = true
	if geometry_changed:
		_rebuild_geometry(Vector2i(snapshot.get("map_size", Vector2i.ZERO)))


func filter_sites(sites: Array, building_alias: String) -> Array:
	if not enabled or not initialized:
		return sites
	if building_alias == WALL_KIND:
		return sites.filter(func(site_value): return wall_cells.has(_site_cell(Vector2(site_value))))
	if not _uses_city_envelope(building_alias) or maximum_town_size <= 0:
		return sites
	return sites.filter(func(site_value):
		return center.distance_to(Vector2(site_value)) <= float(maximum_town_size) + 0.75
	)


func site_rank(site: Vector2, building_alias: String) -> int:
	if not enabled or not initialized:
		return 0
	if building_alias == WALL_KIND:
		var index := wall_cells.find(_site_cell(site))
		return index if index >= 0 else 1_000_000_000
	if not _uses_city_envelope(building_alias):
		return 0
	return roundi(center.distance_squared_to(site) * 1000.0)


func preferred_wall_sites() -> Array:
	var result: Array = []
	for cell in wall_cells:
		result.append(Vector2(cell) + Vector2(0.5, 0.5))
	return result


func recommended_search_radius() -> int:
	return maxi(12, maximum_town_size + 2)


func canonical_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"team": team,
		"initialized": initialized,
		"enabled": enabled,
		"anchor_entity_id": anchor_entity_id,
		"center": center,
		"minimum_town_size": minimum_town_size,
		"maximum_town_size": maximum_town_size,
		"gate_count": gate_count,
		"gate_size": gate_size,
		"perimeter_cells": perimeter_cells.duplicate(),
		"wall_cells": wall_cells.duplicate(),
		"gate_cells": gate_cells.duplicate(),
		"revision": revision,
	}


static func from_state(data: Dictionary):
	var plan = new(int(data.get("team", 0)))
	plan.initialized = bool(data.get("initialized", false))
	plan.enabled = bool(data.get("enabled", false))
	plan.anchor_entity_id = int(data.get("anchor_entity_id", -1))
	plan.center = Vector2(data.get("center", Vector2.ZERO))
	plan.minimum_town_size = maxi(0, int(data.get("minimum_town_size", 0)))
	plan.maximum_town_size = maxi(plan.minimum_town_size, int(data.get("maximum_town_size", plan.minimum_town_size)))
	plan.gate_count = maxi(0, int(data.get("gate_count", 0)))
	plan.gate_size = maxi(0, int(data.get("gate_size", 0)))
	plan.perimeter_cells.assign(_vector2i_array(data.get("perimeter_cells", [])))
	plan.wall_cells.assign(_vector2i_array(data.get("wall_cells", [])))
	plan.gate_cells.assign(_vector2i_array(data.get("gate_cells", [])))
	plan.revision = maxi(0, int(data.get("revision", 0)))
	return plan


func _rebuild_geometry(map_size: Vector2i) -> void:
	perimeter_cells.clear()
	wall_cells.clear()
	gate_cells.clear()
	var radius := maximum_town_size if maximum_town_size > 0 else minimum_town_size
	if radius <= 0:
		revision += 1
		return
	var origin := _site_cell(center)
	for x in range(origin.x - radius, origin.x + radius + 1):
		_append_if_in_bounds(perimeter_cells, Vector2i(x, origin.y - radius), map_size)
	for y in range(origin.y - radius + 1, origin.y + radius + 1):
		_append_if_in_bounds(perimeter_cells, Vector2i(origin.x + radius, y), map_size)
	for x in range(origin.x + radius - 1, origin.x - radius - 1, -1):
		_append_if_in_bounds(perimeter_cells, Vector2i(x, origin.y + radius), map_size)
	for y in range(origin.y + radius - 1, origin.y - radius, -1):
		_append_if_in_bounds(perimeter_cells, Vector2i(origin.x - radius, y), map_size)
	var gate_lookup: Dictionary = {}
	if gate_count > 0 and gate_size > 0 and not perimeter_cells.is_empty():
		for gate_index in range(gate_count):
			var gate_center_index := floori((float(gate_index) + 0.5) * float(perimeter_cells.size()) / float(gate_count)) % perimeter_cells.size()
			var first_offset := -floori(float(gate_size - 1) * 0.5)
			for offset in range(first_offset, first_offset + gate_size):
				var index := posmod(gate_center_index + offset, perimeter_cells.size())
				gate_lookup[perimeter_cells[index]] = true
	for cell in perimeter_cells:
		if gate_lookup.has(cell):
			gate_cells.append(cell)
		else:
			wall_cells.append(cell)
	revision += 1


func _choose_anchor(snapshot: Dictionary, own_units: Array, own_buildings: Array) -> Dictionary:
	var buildings := own_buildings.duplicate()
	buildings.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	for building_value in buildings:
		var building: Dictionary = building_value
		if String(building.get("kind", "")) == "town_center" and float(building.get("hp", 0.0)) > 0.0:
			return {"id": int(building.get("id", -1)), "position": Vector2(building.get("pos", Vector2.ZERO))}
	for building_value in buildings:
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) > 0.0:
			return {"id": int(building.get("id", -1)), "position": Vector2(building.get("pos", Vector2.ZERO))}
	var units := own_units.duplicate()
	units.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	if not units.is_empty():
		return {"id": int(units[0].get("id", -1)), "position": Vector2(units[0].get("pos", Vector2.ZERO))}
	var map_size := Vector2(snapshot.get("map_size", Vector2i.ZERO))
	return {"id": -1, "position": map_size * 0.5}


static func _uses_city_envelope(building_alias: String) -> bool:
	return building_alias not in ["", "dock", "farm", "granary", "storage_pit", WALL_KIND]


static func _site_cell(site: Vector2) -> Vector2i:
	return Vector2i(floori(site.x), floori(site.y))


static func _append_if_in_bounds(target: Array[Vector2i], cell: Vector2i, map_size: Vector2i) -> void:
	if map_size.x > 0 and map_size.y > 0 and (cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y):
		return
	if not target.has(cell):
		target.append(cell)


static func _vector2i_array(source: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in source:
		result.append(Vector2i(value))
	return result
