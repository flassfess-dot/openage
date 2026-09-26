class_name RoRAiNavigationKnowledge
extends RefCounted

const OFFSETS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BUCKET_NAMES := ["land", "water", "frontier_land", "frontier_water", "reachable_land", "reachable_water", "reachable_frontier_land", "reachable_frontier_water"]

var entries: Dictionary = {}


func clear() -> void:
	entries.clear()


func snapshot(world, fog, team: int, probe: Variant = null) -> Dictionary:
	var grid = world.navigation_grid
	var size: Vector2i = world.map_size
	var reach: Dictionary = _reachable_components(world, team)
	var entry: Dictionary = entries.get(team, {})
	var full_rebuild: bool = entry.is_empty() or entry.get("size") != size or int(entry.get("surface_revision", -1)) != int(grid.surface_revision) or not fog.navigation_newly_explored_by_player.has(team)
	var changed_cells: Variant = []
	if not full_rebuild and int(entry.get("grid_revision", -1)) != int(grid.revision):
		changed_cells = grid.changed_cells_since(int(entry["grid_revision"]))
		full_rebuild = changed_cells == null
	if full_rebuild:
		entry = _new_entry(size)
		entry["building_full"] = true
		var states: PackedByteArray = fog.states_by_player[team]
		for index in range(states.size()):
			if states[index] != 0:
				_refresh_cell(entry, index, size, states, grid, reach)
		entry.erase("building_full")
		fog.track_navigation_exploration(team)
		if probe != null:
			probe.increment("ai.navigation.full_rebuilds")
	else:
		var dirty: Dictionary = {}
		for changed_cell_value in changed_cells:
			var changed_cell: Vector2i = changed_cell_value
			dirty[changed_cell.y * size.x + changed_cell.x] = true
		for index_value in fog.consume_navigation_exploration(team):
			var index := int(index_value)
			dirty[index] = true
			var cell := Vector2i(index % size.x, index / size.x)
			for offset in OFFSETS:
				var neighbor: Vector2i = cell + offset
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y:
					dirty[neighbor.y * size.x + neighbor.x] = true
		if entry.get("reach_signature") != reach["signature"]:
			for index in entry["known"]:
				dirty[index] = true
		var changed_indices: Array = dirty.keys()
		changed_indices.sort()
		var states: PackedByteArray = fog.states_by_player[team]
		for index_value in changed_indices:
			_refresh_cell(entry, int(index_value), size, states, grid, reach)
		if probe != null:
			probe.increment("ai.navigation.dirty_cells", changed_indices.size())
	entry["grid_revision"] = int(grid.revision)
	entry["surface_revision"] = int(grid.surface_revision)
	entry["exploration_revision"] = int(fog.exploration_revision_for_player(team))
	entry["reach_signature"] = reach["signature"]
	entries[team] = entry
	return entry["result"]


func _new_entry(size: Vector2i) -> Dictionary:
	var buckets: Dictionary = {}
	for bucket_name in BUCKET_NAMES:
		buckets[bucket_name] = []
	return {
		"size": size,
		"known": {},
		"buckets": buckets,
		"result": {
			"land": buckets["land"],
			"water": buckets["water"],
			"frontier": {"land": buckets["frontier_land"], "water": buckets["frontier_water"]},
			"reachable": {"land": buckets["reachable_land"], "water": buckets["reachable_water"]},
			"reachable_frontier": {"land": buckets["reachable_frontier_land"], "water": buckets["reachable_frontier_water"]},
		},
	}


func _refresh_cell(entry: Dictionary, index: int, size: Vector2i, states: PackedByteArray, grid, reach: Dictionary) -> void:
	var cell := Vector2i(index % size.x, index / size.x)
	var known := int(states[index]) != 0
	var point := Vector2(cell) + Vector2(0.5, 0.5)
	if known:
		entry["known"][index] = true
	else:
		entry["known"].erase(index)
	var frontier := false
	if known:
		for offset in OFFSETS:
			var neighbor: Vector2i = cell + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and states[neighbor.y * size.x + neighbor.x] == 0:
				frontier = true
				break
	for domain in ["land", "water"]:
		var walkable: bool = known and grid.is_walkable_for(cell, domain)
		var reachable: bool = walkable and not reach[domain].is_empty() and reach[domain].has(grid.surface_component_id(cell, domain))
		_set_bucket(entry, domain, index, point, walkable)
		_set_bucket(entry, "frontier_" + domain, index, point, walkable and frontier)
		_set_bucket(entry, "reachable_" + domain, index, point, reachable)
		_set_bucket(entry, "reachable_frontier_" + domain, index, point, reachable and frontier)


func _set_bucket(entry: Dictionary, name: String, index: int, point: Vector2, included: bool) -> void:
	var bucket: Array = entry["buckets"][name]
	if bool(entry.get("building_full", false)):
		if included:
			bucket.append(point)
		return
	var slot := _bucket_position(bucket, point)
	if (slot < bucket.size() and bucket[slot] == point) == included:
		return
	if included:
		bucket.insert(slot, point)
		return
	bucket.remove_at(slot)


func _bucket_position(bucket: Array, point: Vector2) -> int:
	# The previous full scan emitted row-major lists. Preserve that order for
	# planners that choose a known fallback by index, while binary insertion
	# touches only changed cells rather than regenerating the complete list.
	var low := 0
	var high := bucket.size()
	while low < high:
		var middle := (low + high) / 2
		var current: Vector2 = bucket[middle]
		if current.y < point.y or (current.y == point.y and current.x < point.x):
			low = middle + 1
		else:
			high = middle
	return low


func _reachable_components(world, team: int) -> Dictionary:
	var components := {"land": {}, "water": {}}
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) != team or float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var domain := String(unit.get("movement_domain", "land"))
		if not components.has(domain):
			continue
		var position := Vector2i(Vector2(unit.get("pos", Vector2.ZERO)))
		var component_id: int = world.navigation_grid.surface_component_id(position, domain)
		if component_id >= 0:
			components[domain][component_id] = true
	if components["land"].is_empty():
		for building_value in world.get_buildings():
			var building: Dictionary = building_value
			if int(building.get("team", 0)) != team or float(building.get("hp", 0.0)) <= 0.0:
				continue
			var position := Vector2i(Vector2(building.get("pos", Vector2.ZERO)))
			var component_id: int = world.navigation_grid.surface_component_id(position, "land")
			if component_id >= 0:
				components["land"][component_id] = true
	var land_keys: Array = components["land"].keys()
	var water_keys: Array = components["water"].keys()
	land_keys.sort()
	water_keys.sort()
	components["signature"] = [land_keys, water_keys]
	return components
