class_name RoRAiNavigationKnowledge
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const DEFAULT_PREPARE_CELLS := 2048
const OFFSETS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BUCKET_NAMES := ["land", "water", "frontier_land", "frontier_water", "reachable_land", "reachable_water", "reachable_frontier_land", "reachable_frontier_water"]

const MAX_RECOVERY_CACHE_ENTRIES := 512
const MAX_RECOVERY_CACHE_BYTES := 512 * 1024
var recovery_cache_enabled := true
var entries: Dictionary = {}
var reach_caches: Dictionary = {}
const MAX_REGION_ACTORS := 8192
var pending_preparations: Dictionary = {}
var last_prepared_cells := 0
var last_bucket_merged_points := 0
var last_bucket_patch_count := 0


func clear() -> void:
	entries.clear()
	reach_caches.clear()
	pending_preparations.clear()
	last_prepared_cells = 0
	last_bucket_merged_points = 0
	last_bucket_patch_count = 0


func snapshot(world, fog, team: int, probe: Variant = null, maximum_region_units: int = 65536) -> Dictionary:
	last_bucket_merged_points = 0
	last_bucket_patch_count = 0
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var grid = world.navigation_grid
	var size: Vector2i = world.map_size
	var reach: Dictionary = _reachable_components(world, team)
	_observe_stage(probe, "reach", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
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
	_observe_stage(probe, "cells", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	_apply_bucket_changes(entry)
	if probe != null:
		probe.increment("ai.navigation.bucket_merged_points", last_bucket_merged_points)
		probe.increment("ai.navigation.bucket_patches", last_bucket_patch_count)
	_refresh_result_buckets(entry)
	_observe_stage(probe, "buckets", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	if not _region_targets(world, team, entry, maximum_region_units):
		entries[team] = entry
		return {}
	_observe_stage(probe, "regions", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	_freeze_publication(entry["result"])
	_observe_stage(probe, "freeze", stage_started)
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
		return not snapshot(world, fog, team, null, 96).is_empty()
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
	if not _region_targets(world, team, entry, 96): return false
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
	var journal = world.entity_changes
	var cached: Dictionary = reach_caches.get(team, {})
	var delta: Dictionary = journal.changes_since(int(cached.get("cursor", -1)) if int(cached.get("epoch", -1)) == int(journal.epoch) else -1)
	var full: bool = cached.is_empty() or bool(delta["full"]) or cached.get("surface", -1) != world.navigation_grid.surface_revision
	if full:
		cached = {"rows": {}, "units": {"land": {}, "water": {}}, "buildings": {"land": {}, "water": {}}}
		var rows: Array = world.entity_read_index.legal_entities(world, team, "units") + world.entity_read_index.legal_entities(world, team, "buildings")
		for row in rows: _update_reach_actor(world, team, cached, row)
	else:
		for id in delta["ids"]:
			if not (int(delta["masks"][id]) & (1 | 2 | 8 | 128)): continue
			if cached["rows"].has(id):
				var old: Array = cached["rows"][id]
				var counts: Dictionary = cached[old[0]][old[1]]
				counts[old[2]] = int(counts[old[2]]) - 1
				if int(counts[old[2]]) <= 0: counts.erase(old[2])
				cached["rows"].erase(id)
			var row: Variant = world.find_unit(int(id))
			if row == null: row = world.find_building(int(id))
			if row != null: _update_reach_actor(world, team, cached, row)
	cached["cursor"] = int(delta["revision"])
	cached["epoch"] = int(journal.epoch)
	cached["surface"] = world.navigation_grid.surface_revision
	reach_caches[team] = cached
	var components := {"land": cached["units"]["land"].duplicate(), "water": cached["units"]["water"].duplicate()}
	if components["land"].is_empty(): components["land"] = cached["buildings"]["land"].duplicate()
	var land_keys: Array = components["land"].keys()
	var water_keys: Array = components["water"].keys()
	land_keys.sort()
	water_keys.sort()
	components["signature"] = [land_keys, water_keys]
	return components

func _update_reach_actor(world, team: int, cached: Dictionary, row: Dictionary) -> void:
	if int(row.get("team", 0)) != team or float(row.get("hp", 0.0)) <= 0.0: return
	var domain := String(row.get("movement_domain", "land"))
	if domain not in ["land", "water"]: domain = "land"
	var category := "buildings" if world.find_building(int(row["id"])) != null else "units"
	var component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(row["pos"])), domain)
	if component < 0: return
	cached[category][domain][component] = int(cached[category][domain].get(component, 0)) + 1
	cached["rows"][int(row["id"])] = [category, domain, component]


func _region_targets(world, team: int, entry: Dictionary, maximum_units: int = 96) -> bool:
	var planner = world.movement_system.knowledge.planner(world, team)
	var source_signature := [world.entity_changes.epoch, world.entity_changes.revision, planner.grid.cache_epoch, planner.grid.revision, entry["exploration_revision"]]
	if entry.get("regions_prepared") == source_signature: return true
	var pending: Dictionary = entry.get("region_pending", {})
	if pending.is_empty() or pending["signature"] != source_signature:
		var actors: Array = world.entity_read_index.legal_entities(world, team, "units").filter(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0)) > 0)
		pending = {"signature": source_signature, "actors": actors, "cursor": 0, "unit_regions": {}, "signatures": {}, "recovery": {}, "live_recovery_ids": {}}
		entry["region_pending"] = pending
	var finish := mini(pending["actors"].size(), int(pending["cursor"]) + maxi(1, maximum_units))
	var units: Array = pending["actors"].slice(int(pending["cursor"]), finish)
	var signatures: Dictionary = pending["signatures"]
	var unit_regions: Dictionary = pending["unit_regions"]
	var region_cache: Dictionary = entry.get("actor_region_cache", {})
	entry["actor_region_cache"] = region_cache
	for unit in units:
		var id := int(unit["id"])
		var domain := String(unit.get("movement_domain", "land"))
		var restriction := int(unit.get("terrain_restriction", -1))
		var radius := float(unit.get("footprint_radius", 0.3))
		var config := "%s:%d:%.8f" % [domain, restriction, radius]
		var dependency := [planner.grid.cache_epoch, planner.grid.revision, world.entity_changes.revision_for(id, 2 | 32 | 128)]
		var cached: Dictionary = region_cache.get(id, {})
		var region: int
		if cached.get("dependency") == dependency: region = int(cached["region"])
		else:
			region = planner.component_id(Vector2i(Vector2(unit["pos"]).floor()), domain, restriction, radius)
			if region_cache.has(id) or region_cache.size() < MAX_REGION_ACTORS: region_cache[id] = {"dependency": dependency, "region": region}
		unit_regions[id] = "%s:%d" % [config, region] if region >= 0 else "unit:%d" % id
		signatures[config] = [domain, restriction, radius]
	var recovery: Dictionary = pending["recovery"]
	var live_recovery_ids: Dictionary = pending["live_recovery_ids"]
	var recovery_cache: Dictionary = entry.get("recovery_cache", {})
	entry["recovery_cache"] = recovery_cache
	for unit in units:
		if not preload("res://scripts/ai_navigation_policy.gd").is_failure(String(unit.get("diagnostic_reason", ""))): continue
		var unit_id := int(unit["id"])
		live_recovery_ids[unit_id] = true
		var dependency: Array = _recovery_dependency(world, team, entry, planner, unit) if recovery_cache_enabled else []
		var cached: Dictionary = recovery_cache.get(unit_id, {})
		if recovery_cache_enabled and not cached.is_empty() and cached["dependency"] == dependency:
			if cached["position"] != null: recovery[unit_id] = cached["position"]
			if world.tick_pipeline.performance_probe != null: world.tick_pipeline.performance_probe.increment("ai.navigation.recovery_reused")
			continue
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
		if best != null: recovery[unit_id] = best
		if recovery_cache_enabled: _remember_recovery(entry, unit_id, dependency, best)
		if world.tick_pipeline.performance_probe != null: world.tick_pipeline.performance_probe.increment("ai.navigation.recovery_built")
	pending["cursor"] = finish
	if finish < pending["actors"].size(): return false
	var keys: Array = signatures.keys()
	keys.sort()
	var signature := [planner.grid.revision, entry["exploration_revision"], keys]
	var result: Dictionary = entry["result"].duplicate()
	if entry.get("region_signature") != signature:
		var by_region := {}
		for config in keys:
			var values: Array = signatures[config]
			var grouped: Dictionary = planner.group_points_by_component(entry["buckets"]["frontier_" + String(values[0])], values[0], values[1], values[2])
			for region in grouped: by_region["%s:%d" % [config, int(region)]] = grouped[region]
		result["frontier_by_region"] = by_region
		entry["region_signature"] = signature
	for unit_id in recovery_cache.keys():
		if not live_recovery_ids.has(unit_id): _erase_recovery(entry, unit_id)
	for unit_id in region_cache.keys():
		if not unit_regions.has(unit_id): region_cache.erase(unit_id)
	result["unit_regions"] = unit_regions
	result["recovery_positions"] = recovery
	entry["result"] = result
	entry["regions_prepared"] = source_signature
	entry.erase("region_pending")
	return true


# Exact inputs of the old local query, using this observer's learned mask.
# A broad query covers every +/-2-cell candidate and its collision neighborhood.
# Only currently visible living units contribute; hidden motion cannot invalidate it.
func _recovery_dependency(world, team: int, entry: Dictionary, planner, unit: Dictionary) -> Array:
	var origin := Vector2(unit["pos"])
	var cell := Vector2i(origin.floor())
	var radius := float(unit.get("footprint_radius", 0.3))
	var known := PackedByteArray()
	for y in range(cell.y - 2, cell.y + 3):
		for x in range(cell.x - 2, cell.x + 3):
			known.append(int(planner.grid.contains(Vector2i(x, y)) and entry["known"].has(y * world.map_size.x + x)))
	var neighbors: Array = []
	for other in world.query_units_near(origin, radius + 5.0):
		if int(other["id"]) != int(unit["id"]) and float(other.get("hp", 0.0)) > 0.0 and world.is_entity_visible_to(team, other):
			neighbors.append([int(other["id"]), Vector2(other["pos"]), float(other.get("footprint_radius", 0.3))])
	neighbors.sort_custom(func(a, b): return a[0] < b[0])
	return [world.cache_epoch, origin, radius, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), planner.connectivity_dependency_stamp(String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))), known, neighbors]

func _erase_recovery(entry: Dictionary, id: int) -> void:
	var cache: Dictionary = entry.get("recovery_cache", {})
	if cache.has(id):
		entry["recovery_cache_bytes"] = int(entry.get("recovery_cache_bytes", 0)) - int(cache[id]["bytes"])
		cache.erase(id)

func _remember_recovery(entry: Dictionary, id: int, dependency: Array, position: Variant) -> void:
	var bytes := var_to_bytes({"dependency": dependency, "position": position, "bytes": 0}).size() + 32
	var cache: Dictionary = entry["recovery_cache"]
	_erase_recovery(entry, id)
	if bytes > MAX_RECOVERY_CACHE_BYTES: return
	while not cache.is_empty() and (cache.size() >= MAX_RECOVERY_CACHE_ENTRIES or int(entry.get("recovery_cache_bytes", 0)) + bytes > MAX_RECOVERY_CACHE_BYTES):
		_erase_recovery(entry, int(cache.keys()[0]))
	cache[id] = {"dependency": dependency, "position": position, "bytes": bytes}
	entry["recovery_cache_bytes"] = int(entry.get("recovery_cache_bytes", 0)) + bytes


static func _freeze_publication(value: Variant) -> void:
	# Arrays already published by an earlier revision retain their identity.
	# Only changed buckets are validated/frozen; callers share the sealed map.
	if not Data.freeze_detached(value):
		push_error("AI navigation must contain detached values")

static func _observe_stage(probe: Variant, stage: String, started: int) -> void:
	if probe != null: probe.observe_microseconds("ai.navigation." + stage, Time.get_ticks_usec() - started)
