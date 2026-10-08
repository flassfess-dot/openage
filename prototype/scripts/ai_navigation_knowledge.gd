class_name RoRAiNavigationKnowledge
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const DEFAULT_PREPARE_CELLS := 2048
const OFFSETS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BUCKET_NAMES := ["land", "water", "frontier_land", "frontier_water", "reachable_land", "reachable_water", "reachable_frontier_land", "reachable_frontier_water"]

var entries: Dictionary = {}
var pending_preparations: Dictionary = {}
var last_prepared_cells := 0
var last_bucket_merged_points := 0
var last_bucket_patch_count := 0


func clear() -> void:
	entries.clear()
	pending_preparations.clear()
	last_prepared_cells = 0
	last_bucket_merged_points = 0
	last_bucket_patch_count = 0


func snapshot(world, fog, team: int, probe: Variant = null) -> Dictionary:
	last_bucket_merged_points = 0
	last_bucket_patch_count = 0
	var grid = world.navigation_grid
	var size: Vector2i = world.map_size
	var reach: Dictionary = _reachable_components(world, team)
	var entry: Dictionary = entries.get(team, {})
	fog.ensure_player(team)
	var topology := CacheDependency.changes(world, CacheDependency.NAVIGATION_TOPOLOGY, entry.get("topology_stamp", {}))
	var exploration := CacheDependency.changes(world, CacheDependency.FOG_EXPLORATION, entry.get("exploration_stamp", {}), team)
	var full_rebuild: bool = entry.is_empty() or entry.get("size") != size or int(entry.get("surface_revision", -1)) != int(grid.surface_revision) or bool(topology["full"]) or not bool(topology["exact"]) or bool(exploration["full"]) or not bool(exploration["exact"])
	var changed_cells: Array = topology["cells"]
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
		for cell_value in exploration["cells"]:
			var cell := Vector2i(cell_value)
			var index := cell.y * size.x + cell.x
			dirty[index] = true
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
	entry["topology_stamp"] = topology["stamp"]
	entry["exploration_stamp"] = exploration["stamp"]
	# The legacy queue remains bounded; cache correctness uses non-consuming journals.
	fog.consume_navigation_exploration(team)
	_apply_bucket_changes(entry)
	if probe != null:
		probe.increment("ai.navigation.bucket_merged_points", last_bucket_merged_points)
		probe.increment("ai.navigation.bucket_patches", last_bucket_patch_count)
	_refresh_result_buckets(entry)
	_region_targets(world, team, entry)
	_freeze_publication(entry["result"])
	entries[team] = entry
	return entry["result"]


# Cold or widespread invalidations are prepared while the simulation tick is
# held. Camera and UI keep rendering, and every frame scans a bounded slice.
func prepare_snapshot(world, fog, team: int, maximum_cells: int = DEFAULT_PREPARE_CELLS) -> bool:
	last_prepared_cells = 0
	fog.ensure_player(team)
	var grid = world.navigation_grid
	var size: Vector2i = world.map_size
	var entry: Dictionary = entries.get(team, {})
	var topology := CacheDependency.changes(world, CacheDependency.NAVIGATION_TOPOLOGY, entry.get("topology_stamp", {}))
	var exploration := CacheDependency.changes(world, CacheDependency.FOG_EXPLORATION, entry.get("exploration_stamp", {}), team)
	var reach := _reachable_components(world, team)
	var cold: bool = entry.is_empty() or entry.get("size") != size or int(entry.get("surface_revision", -1)) != int(grid.surface_revision) or bool(topology["full"]) or not bool(topology["exact"]) or bool(exploration["full"]) or not bool(exploration["exact"]) or entry.get("reach_signature") != reach["signature"] or topology["cells"].size() + exploration["cells"].size() * 5 > maxi(1, maximum_cells)
	if not cold:
		pending_preparations.erase(team)
		return true
	var signature := [topology["stamp"], CacheDependency.stamp(world, CacheDependency.NAVIGATION_SURFACE), exploration["stamp"], reach["signature"]]
	var pending: Dictionary = pending_preparations.get(team, {})
	if pending.is_empty() or pending.get("signature") != signature:
		entry = _new_entry(size)
		entry["building_full"] = true
		pending = {"signature": signature, "cursor": 0, "entry": entry, "reach": reach}
		pending_preparations[team] = pending
	entry = pending["entry"]
	var states: PackedByteArray = fog.states_by_player[team]
	var start := int(pending["cursor"])
	var finish := mini(states.size(), start + maxi(1, maximum_cells))
	for index in range(start, finish):
		if states[index] != 0:
			_refresh_cell(entry, index, size, states, grid, pending["reach"])
	last_prepared_cells = finish - start
	pending["cursor"] = finish
	if finish < states.size():
		return false
	entry.erase("building_full")
	entry["grid_revision"] = int(grid.revision)
	entry["surface_revision"] = int(grid.surface_revision)
	entry["exploration_revision"] = int(fog.exploration_revision_for_player(team))
	entry["reach_signature"] = reach["signature"]
	entry["topology_stamp"] = topology["stamp"]
	entry["exploration_stamp"] = exploration["stamp"]
	fog.track_navigation_exploration(team)
	_refresh_result_buckets(entry)
	_region_targets(world, team, entry)
	_freeze_publication(entry["result"])
	entries[team] = entry
	pending_preparations.erase(team)
	return true


func _refresh_result_buckets(entry: Dictionary) -> void:
	# Published navigation arrays are immutable. Changed buckets use copy on
	# write, and each publication receives a new root with current references.
	var result: Dictionary = entry["result"].duplicate()
	var buckets: Dictionary = entry["buckets"]
	for bucket_name in BUCKET_NAMES:
		if not Data.freeze_detached(buckets[bucket_name]):
			push_error("AI navigation bucket must contain detached points")
	result["land"] = buckets["land"]
	result["water"] = buckets["water"]
	result["frontier"] = {"land": buckets["frontier_land"], "water": buckets["frontier_water"]}
	result["reachable"] = {"land": buckets["reachable_land"], "water": buckets["reachable_water"]}
	result["reachable_frontier"] = {"land": buckets["reachable_frontier_land"], "water": buckets["reachable_frontier_water"]}
	entry["result"] = result


func _new_entry(size: Vector2i) -> Dictionary:
	var buckets: Dictionary = {}
	for bucket_name in BUCKET_NAMES:
		var points: Array[Vector2] = []
		buckets[bucket_name] = points
	return {
		"size": size,
		"known": {},
		"buckets": buckets,
		"bucket_changes": {},
		"result": {
			"cell_geometry": true,
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
	var present: bool = slot < bucket.size() and bucket[slot] == point
	var changes: Dictionary = entry["bucket_changes"].get(name, {})
	if present == included:
		# Multiple updates to the same cell may cancel before publication.
		changes.erase(index)
		return
	changes[index] = {"slot": slot, "point": point, "included": included, "present": present}
	entry["bucket_changes"][name] = changes


func _apply_bucket_changes(entry: Dictionary) -> void:
	# Per-cell insert/remove shifts the increasingly large explored tail once
	# for every discovery. Merge all patches at once, emitting each retained
	# point once into the replacement. Native array slices avoid a script loop over the map.
	for name in BUCKET_NAMES:
		var changes: Dictionary = entry["bucket_changes"].get(name, {})
		if changes.is_empty():
			continue
		var indices: Array = changes.keys()
		indices.sort()
		var bucket: Array = entry["buckets"][name]
		var merged: Array[Vector2] = []
		var cursor := 0
		for index in indices:
			var patch: Dictionary = changes[index]
			var slot := int(patch["slot"])
			if slot > cursor:
				merged.append_array(bucket.slice(cursor, slot))
				last_bucket_merged_points += slot - cursor
			if bool(patch["included"]):
				merged.append(Vector2(patch["point"]))
				last_bucket_merged_points += 1
			cursor = slot + (1 if bool(patch["present"]) else 0)
			last_bucket_patch_count += 1
		if cursor < bucket.size():
			merged.append_array(bucket.slice(cursor))
			last_bucket_merged_points += bucket.size() - cursor
		entry["buckets"][name] = merged
	entry["bucket_changes"].clear()


func _bucket_position(bucket: Array, point: Vector2) -> int:
	# The previous full scan emitted row-major lists. Preserve that order for
	# planners that choose a known fallback by index. Binary lookup records
	# positions in the unchanged array for the later batch merge.
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


func _region_targets(world, team: int, entry: Dictionary) -> void:
	var planner = world.movement_system.knowledge.planner(world, team)
	var units: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0)) > 0)
	var signatures := {}
	var unit_regions := {}
	for unit in units:
		var domain := String(unit.get("movement_domain", "land"))
		var restriction := int(unit.get("terrain_restriction", -1))
		var radius := float(unit.get("footprint_radius", 0.3))
		var config := "%s:%d:%.8f" % [domain, restriction, radius]
		var region: int = planner.component_id(Vector2i(Vector2(unit["pos"]).floor()), domain, restriction, radius)
		unit_regions[int(unit["id"])] = "%s:%d" % [config, region] if region >= 0 else "unit:%d" % int(unit["id"])
		signatures[config] = [domain, restriction, radius]
	var keys := signatures.keys()
	keys.sort()
	var signature := [planner.grid.revision, entry["exploration_revision"], keys]
	if entry.get("region_signature") != signature:
		var by_region := {}
		for config in keys:
			var values: Array = signatures[config]
			for point in entry["buckets"]["frontier_" + String(values[0])]:
				var region: int = planner.component_id(Vector2i(point), values[0], values[1], values[2])
				if region < 0: continue
				var key := "%s:%d" % [config, region]
				if not by_region.has(key):
					var points: Array[Vector2] = []
					by_region[key] = points
				by_region[key].append(point)
		entry["result"]["frontier_by_region"] = by_region
		entry["region_signature"] = signature
	var recovery := {}
	for unit in units:
		if not preload("res://scripts/ai_navigation_policy.gd").is_failure(String(unit.get("diagnostic_reason", ""))): continue
		var origin := Vector2(unit["pos"])
		var cell := Vector2i(origin.floor())
		var recovery_radius := float(unit.get("footprint_radius", 0.3))
		if not planner.grid.is_position_walkable_for(origin, recovery_radius, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
			recovery_radius = 0.0
		var best: Variant = null
		var best_distance := INF
		for y in range(cell.y - 2, cell.y + 3):
			for x in range(cell.x - 2, cell.x + 3):
				var next := Vector2i(x, y)
				if not planner.grid.contains(next) or not entry["known"].has(y * world.map_size.x + x): continue
				var point := Vector2(next) + Vector2(0.5, 0.5)
				var distance := origin.distance_squared_to(point)
				if distance <= 0.5625 or distance >= best_distance: continue
				if not planner.grid.is_position_walkable_for(point, float(unit.get("footprint_radius", 0.3)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))): continue
				var occupied: bool = world.query_units_near(point, float(unit.get("footprint_radius", 0.3)) + 1.0).any(func(other): return int(other["id"]) != int(unit["id"]) and float(other.get("hp", 0.0)) > 0 and world.is_entity_visible_to(team, other) and point.distance_squared_to(Vector2(other["pos"])) < pow(float(unit.get("footprint_radius", 0.3)) + float(other.get("footprint_radius", 0.3)) + 0.1, 2))
				if occupied: continue
				if planner.cells_connected(cell, next, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), recovery_radius):
					best = point
					best_distance = distance
		if best != null: recovery[int(unit["id"])] = best
	entry["result"]["unit_regions"] = unit_regions
	entry["result"]["recovery_positions"] = recovery


static func _freeze_publication(value: Variant) -> void:
	# Arrays already published by an earlier revision retain their identity.
	# Only changed buckets are validated/frozen; callers share the sealed map.
	if not Data.freeze_detached(value):
		push_error("AI navigation must contain detached values")
