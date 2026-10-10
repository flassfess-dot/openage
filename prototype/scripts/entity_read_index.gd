class_name RoREntityReadIndex
extends RefCounted

# Owner-thread live membership. Published DTOs never contain these dictionaries.
# Independent entity/fog cursors; only overflow, topology reset or a new observer
# requires a complete synchronization. Storage is bounded by current live actors.
const Journal := preload("res://scripts/entity_change_journal.gd")
const BUCKET_SIZE := 4.0
const MAX_OBSERVERS := 8
const MAX_ENTITIES := 65536
var epoch := -1
var cursor := -1
var entities: Dictionary = {}
var categories: Dictionary = {}
var cells: Dictionary = {}
var buckets: Dictionary = {}
var observers: Dictionary = {}
var generation := 0
var overflow := false
var source_world_ref: WeakRef

func clear() -> void:
	epoch = -1
	cursor = -1
	overflow = false
	entities.clear()
	categories.clear()
	cells.clear()
	buckets.clear()
	observers.clear()
	memory_cursors.clear()
	generation += 1

func synchronize(world) -> void:
	source_world_ref = weakref(world)
	var journal = world.entity_changes
	var delta: Dictionary = journal.changes_since(cursor if epoch == journal.epoch else -1)
	if bool(delta["full"]):
		clear()
		for row in world.get_units(): _put(row, "units")
		for row in world.get_buildings(): _put(row, "buildings")
		for row in world.victory_objectives: _put(row, "objectives")
	else:
		for id in delta["ids"]:
			var row: Variant = world.find_unit(int(id))
			var category := "units"
			if row == null:
				row = world.find_building(int(id))
				category = "buildings"
			if row == null:
				# Objectives are rare, and their lookup is needed only on their events.
				for objective in world.victory_objectives:
					if int(objective["id"]) == int(id):
						row = objective
						category = "objectives"
						break
			if row == null: _erase(int(id))
			else: _put(row, category)
	epoch = journal.epoch
	cursor = int(delta["revision"])
	generation += 1 if not delta["ids"].is_empty() or bool(delta["full"]) else 0

func legal_entities(world, team: int, category: String) -> Array:
	synchronize(world)
	var fog = world.get_fog_of_war()
	fog.ensure_player(team)
	if overflow:
		var fallback: Array = world.get_units() if category == "units" else world.get_buildings() if category == "buildings" else world.victory_objectives
		return fallback.filter(func(row): return team <= 0 or int(row.get("team", 0)) == team or fog.state_at_world(team, Vector2(row.get("pos", Vector2.ZERO))) == 2)
	if team <= 0:
		var all: Array = []
		for id in entities:
			if String(categories[id]) == category: all.append(entities[id])
		all.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
		return all
	var observer: Dictionary = observers.get(team, {})
	if observer.is_empty():
		if observers.size() >= MAX_OBSERVERS: observers.erase(observers.keys()[0])
		observer = {"fog": -1, "generation": -1, "members": {}, "arrays": {}, "dirty": true, "member_cells": {}, "sectors": {}, "sector_epoch": 0}
		observers[team] = observer
	var fog_delta: Dictionary = fog.visibility_changes_since(team, int(observer["fog"]))
	var candidates: Dictionary = {}
	var entity_delta: Dictionary = world.entity_changes.changes_since(int(observer.get("entity_cursor", -1)))
	if int(observer["generation"]) < 0 or bool(fog_delta["full"]):
		candidates = entities
	else:
		# Each observer owns its entity cursor: another reader cannot consume it.
		if bool(entity_delta["full"]): candidates = entities
		else:
			for id in entity_delta["ids"]: candidates[id] = true
		if bool(fog_delta["exact"]):
			for cell in fog_delta["cells"]:
				for id in buckets.get(_cell(Vector2(cell)), {}): candidates[id] = true
		elif not bool(fog_delta["full"]):
			for row in in_bounds(fog_delta["region"]): candidates[int(row["id"])] = true
	for id in candidates:
		var row: Dictionary = entities.get(id, {})
		var visible: bool = not row.is_empty() and (team <= 0 or int(row.get("team", 0)) == team or fog.state_at_world(team, Vector2(row.get("pos", Vector2.ZERO))) == 2)
		var previous: bool = observer["members"].has(id)
		var physical_change := int(entity_delta.get("masks", {}).get(id, 0)) & (1 | 2 | 8 | 128)
		if (previous != visible) or ((previous or visible) and physical_change != 0):
			if observer["sectors"].size() >= 65536:
				observer["sectors"].clear()
				observer["sector_epoch"] = int(observer["sector_epoch"]) + 1
			if previous:
				var old_cell: Vector2i = observer["member_cells"][id]
				observer["sectors"][old_cell] = int(observer["sectors"].get(old_cell, 0)) + 1
			if visible:
				var cell: Vector2i = cells[id]
				observer["sectors"][cell] = int(observer["sectors"].get(cell, 0)) + 1
				observer["member_cells"][id] = cell
			else: observer["member_cells"].erase(id)
		if visible:
			if previous and not is_same(observer["members"][id], row): observer["dirty"] = true
			observer["members"][id] = row
		elif previous:
			observer["members"].erase(id)
		if previous != visible: observer["dirty"] = true
	# Removed entries are absent from the cell index, but retained in the cursor.
	if bool(fog_delta["full"]):
		for id in observer["members"].keys():
			if not entities.has(id):
				observer["members"].erase(id)
				observer["member_cells"].erase(id)
				observer["dirty"] = true
	observer["generation"] = generation
	observer["fog"] = int(fog_delta["revision"])
	observer["entity_cursor"] = cursor
	if bool(observer["dirty"]):
		observer["arrays"] = {"units": [], "buildings": [], "objectives": []}
		var ids: Array = observer["members"].keys()
		ids.sort()
		for id in ids: observer["arrays"][categories[id]].append(observer["members"][id])
		observer["dirty"] = false
	return observer["arrays"].get(category, []).duplicate()

func in_bounds(bounds: Rect2, category: String = "") -> Array:
	if overflow and source_world_ref != null:
		var world: Variant = source_world_ref.get_ref()
		var source: Array = world.get_units() if category == "units" else world.get_buildings() if category == "buildings" else world.get_units() + world.get_buildings() + world.victory_objectives
		return source.filter(func(row): return bounds.has_point(Vector2(row.get("pos", Vector2.ZERO))))
	var minimum := _cell(bounds.position)
	var maximum := _cell(bounds.end)
	var result: Array = []
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for id in buckets.get(Vector2i(x, y), {}):
				if (category.is_empty() or String(categories[id]) == category) and bounds.has_point(Vector2(entities[id].get("pos", Vector2.ZERO))): result.append(entities[id])
	result.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return result

func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / BUCKET_SIZE), floori(position.y / BUCKET_SIZE))

func _put(row: Dictionary, category: String) -> void:
	var id := int(row["id"])
	if not entities.has(id) and entities.size() >= MAX_ENTITIES:
		overflow = true
		return
	var cell := _cell(Vector2(row.get("pos", Vector2.ZERO)))
	if cells.has(id) and cells[id] != cell:
		buckets[cells[id]].erase(id)
		if buckets[cells[id]].is_empty(): buckets.erase(cells[id])
	if not buckets.has(cell): buckets[cell] = {}
	buckets[cell][id] = true
	cells[id] = cell
	entities[id] = row
	categories[id] = category

func _erase(id: int) -> void:
	if cells.has(id):
		buckets[cells[id]].erase(id)
		if buckets[cells[id]].is_empty(): buckets.erase(cells[id])
	cells.erase(id)
	entities.erase(id)
	categories.erase(id)

func build_query_scope(world, team: int, radius: int, preferred: Dictionary = {}) -> Dictionary:
	var units: Array = legal_entities(world, team, "units")
	var sectors: Dictionary = {}
	var workers: Array = []
	for row in units:
		if int(row.get("team", 0)) != team or float(row.get("hp", 0.0)) <= 0.0 or not world.entity_is_worker(row) or String(row.get("movement_domain", "land")) != "land": continue
		workers.append([int(row["id"]), world.entity_changes.revision_for(int(row["id"]), 1 | 2 | 128)])
		_add_scope_sectors(sectors, Vector2(row["pos"]), radius + 2)
	for points in preferred.values():
		for point in points: _add_scope_sectors(sectors, Vector2(point), radius + 2)
	var observer: Dictionary = observers.get(team, {"sector_epoch": 0, "sectors": {}})
	var keys: Array = sectors.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var versions: Array = []
	for cell in keys: versions.append([cell, int(observer["sectors"].get(cell, 0))])
	return {"workers": workers, "keys": sectors, "versions": [observer["sector_epoch"], versions, _overflow_versions(world, units) if overflow else []]}

func _add_scope_sectors(sectors: Dictionary, position: Vector2, radius: int) -> void:
	var minimum := _cell(position - Vector2.ONE * radius)
	var maximum := _cell(position + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1): sectors[Vector2i(x, y)] = true

var memory_cursors: Dictionary = {}

func update_building_memory(world, before_visibility: bool) -> void:
	synchronize(world)
	var fog = world.get_fog_of_war()
	for team_value in fog.states_by_player:
		var team := int(team_value)
		if team <= 0: continue
		var state: Dictionary = memory_cursors.get(team, {"entity": -1, "fog": -1})
		var delta: Dictionary = world.entity_changes.changes_since(int(state["entity"]))
		var candidates: Dictionary = {}
		if bool(delta["full"]):
			for row in world.get_buildings(): candidates[int(row["id"])] = true
		else:
			for id in delta["ids"]: candidates[id] = true
		var visibility: Dictionary = fog.visibility_changes_since(team, int(state["fog"]))
		var memories: Dictionary = world.last_known_buildings_by_player.get(team, {})
		if not before_visibility:
			if bool(visibility["full"]) or overflow:
				for row in world.get_buildings(): candidates[int(row["id"])] = true
			elif bool(visibility["exact"]):
				for cell in visibility["cells"]:
					for id in buckets.get(_cell(Vector2(cell)), {}):
						if String(categories[id]) == "buildings": candidates[id] = true
			else:
				for row in in_bounds(visibility["region"], "buildings"): candidates[int(row["id"])] = true
			# Known destroyed buildings need no live spatial entry. Visit only
			# remembered IDs when visibility actually changed.
			if int(state["fog"]) != int(visibility["revision"]):
				for id in memories:
					if not world.buildings_by_id.has(id) and fog.state_at_world(team, Vector2(memories[id]["pos"])) == 2: candidates[id] = true
		for id in candidates:
			var row: Variant = world.find_building(int(id))
			if row != null and (int(row.get("team", 0)) == team or fog.state_at_world(team, Vector2(row["pos"])) == 2):
				memories[id] = world.compact_render_projection(row)
			elif not before_visibility and memories.has(id) and fog.state_at_world(team, Vector2(memories[id]["pos"])) == 2: memories.erase(id)
		world.last_known_buildings_by_player[team] = memories
		if not before_visibility:
			state["entity"] = world.entity_changes.revision
			state["fog"] = int(visibility["revision"])
			memory_cursors[team] = state

func _overflow_versions(world, rows: Array) -> Array:
	var result: Array = []
	for row in rows: result.append([int(row["id"]), world.entity_changes.revision_for(int(row["id"]), 1 | 2 | 8 | 128)])
	return result
