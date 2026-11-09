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
var native_enabled := OS.get_environment("ROR_DIAGNOSTIC_NATIVE_READ_INDEX") != "0"
var native_index: Variant = ClassDB.instantiate("RoREntityReadIndexKernel") if ClassDB.class_exists("RoREntityReadIndexKernel") else null
var compare_native := "--compare-native-read-index" in OS.get_cmdline_user_args()
var native_sync_sequence := 0
var native_query_sequence := 0
var native_sync_comparisons := 0
var native_query_comparisons := 0
var native_bounds_comparisons := 0
var native_mismatches := 0

func uses_native() -> bool:
	return native_enabled and native_index != null

func _native_reference() -> Variant:
	var reference = get_script().new()
	reference.native_enabled = false
	var view: Dictionary = native_index.debug_view()
	reference.entities = view["entities"]
	reference.categories = view["categories"]
	reference.cells = view["cells"]
	reference.buckets = view["buckets"]
	reference.epoch = epoch
	reference.cursor = cursor
	reference.generation = generation
	reference.overflow = overflow
	reference.source_world_ref = source_world_ref
	return reference

func clear() -> void:
	if native_index != null: native_index.clear()
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
	var same_world: bool = source_world_ref != null and source_world_ref.get_ref() == world
	if not same_world: source_world_ref = weakref(world)
	var journal = world.entity_changes
	if uses_native() and same_world and epoch == journal.epoch and cursor == journal.revision and not journal.is_dirty(): return
	var delta: Dictionary = journal.read_changes_since(cursor if same_world and epoch == journal.epoch else -1)
	if uses_native():
		native_sync_sequence += 1
		var compare_now := compare_native and native_sync_comparisons < 32 and (native_sync_comparisons < 4 or native_sync_sequence % 16 == 0)
		var reference: Variant = _native_reference() if compare_now else null
		if compare_now: reference.synchronize(world)
		var full := bool(delta["full"])
		var stamp: Dictionary = native_index.synchronize({"delta":delta,"epoch":journal.epoch,"units":world.units_by_id,"buildings":world.buildings_by_id,"unit_rows":world.get_units() if full else [],"building_rows":world.get_buildings() if full else [],"objectives":world.victory_objectives})
		epoch = int(stamp["epoch"])
		cursor = int(stamp["cursor"])
		generation = int(stamp["generation"])
		overflow = bool(stamp["overflow"])
		if full:
			observers.clear()
			memory_cursors.clear()
		if compare_now:
			native_sync_comparisons += 1
			var actual: Dictionary = native_index.debug_view()
			if generation != reference.generation or actual["entities"] != reference.entities or actual["categories"] != reference.categories or actual["cells"] != reference.cells or actual["buckets"] != reference.buckets:
				native_mismatches += 1
				push_error("Persistent entity index synchronization mismatch at revision %d" % cursor)
		return
	if bool(delta["full"]):
		clear()
		for row in world.get_units(): _put(row, "units")
		for row in world.get_buildings(): _put(row, "buildings")
		for row in world.victory_objectives: _put(row, "objectives")
	else:
		for id in delta["ids"]:
			# Existing live dictionaries already expose activity/health changes.
			# Only membership, replacement and spatial changes need a bucket write.
			if entities.has(id) and not (int(delta["masks"][id]) & (1 | 2 | 128)): continue
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
	if uses_native():
		if team <= 0: return native_index.all(category)
		var cached: Variant = native_index.cached_legal(team, category, fog.revision_for_player(team))
		if cached is Array: return cached
		native_query_sequence += 1
		var compare_now := compare_native and native_query_comparisons < 32 and (native_query_comparisons < 4 or native_query_sequence % 16 == 0)
		var reference: Variant = _native_reference() if compare_now else null
		var expected: Array = []
		if compare_now:
			var observer: Dictionary = native_index.debug_observer(team)
			if not observer.is_empty(): reference.observers[team] = observer
			expected = reference.legal_entities(world, team, category)
		var entity_delta: Dictionary = world.entity_changes.read_changes_since(int(native_index.observer_entity_cursor(team)))
		var fog_delta: Dictionary = fog.visibility_changes_since(team, int(native_index.observer_fog_cursor(team)))
		var result: Array = native_index.legal_entities(team, category, fog.states_by_player[team], world.map_size, fog_delta, entity_delta)
		if compare_now:
			native_query_comparisons += 1
			if result != expected or native_index.debug_observer(team) != reference.observers[team]:
				native_mismatches += 1
				push_error("Persistent entity index legal projection mismatch for team %d" % team)
		return result
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
	# Units/buildings/objectives are commonly requested consecutively by one
	# snapshot. Membership is already complete for all three categories; rows
	# remain owner-thread references, so no second delta/fog pass is needed.
	if int(observer["generation"]) == generation and int(observer["fog"]) == fog.revision_for_player(team) and int(observer.get("entity_cursor", -1)) == cursor:
		return observer["arrays"].get(category, []).duplicate()
	var fog_delta: Dictionary = fog.visibility_changes_since(team, int(observer["fog"]))
	var candidates: Dictionary = {}
	var entity_delta: Dictionary = world.entity_changes.read_changes_since(int(observer.get("entity_cursor", -1)))
	if int(observer["generation"]) < 0 or bool(fog_delta["full"]):
		for id in entities: candidates[id] = true
	else:
		# Each observer owns its entity cursor: another reader cannot consume it.
		if bool(entity_delta["full"]):
			for id in entities: candidates[id] = true
		else:
			for id in entity_delta["ids"]:
				# Private task/animation/economy edits retain the same row reference
				# and cannot change its visibility, category or spatial membership.
				if int(entity_delta["masks"][id]) & (Journal.LIFECYCLE | Journal.POSITION | Journal.COMBAT | Journal.OWNERSHIP): candidates[id] = true
		if bool(fog_delta["exact"]):
			var visited_buckets: Dictionary = {}
			for cell in fog_delta["cells"]:
				var bucket := _cell(Vector2(cell))
				if visited_buckets.has(bucket): continue
				visited_buckets[bucket] = true
				for id in buckets.get(bucket, {}): candidates[id] = true
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
	if uses_native():
		var result: Array = native_index.in_bounds(bounds, category)
		if compare_native and native_bounds_comparisons < 32:
			var reference: Variant = _native_reference()
			native_bounds_comparisons += 1
			if result != reference.in_bounds(bounds, category):
				native_mismatches += 1
				push_error("Persistent entity index bounds query mismatch")
		return result
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

func build_query_scope(world, team: int, radius: int, preferred: Dictionary = {}, changed_cells: Array = []) -> Dictionary:
	var units: Array = legal_entities(world, team, "units")
	var centers := PackedVector2Array()
	var workers: Array = []
	for row in units:
		if int(row.get("team", 0)) != team or float(row.get("hp", 0.0)) <= 0.0 or not world.entity_is_worker(row) or String(row.get("movement_domain", "land")) != "land": continue
		workers.append([int(row["id"]), world.entity_changes.revision_for(int(row["id"]), 1 | 2 | 128)])
		centers.append(row["pos"])
	for points in preferred.values():
		for point in points: centers.append(point)
	if uses_native() and not overflow:
		var scope: Dictionary = native_index.build_query_scope(team, centers, radius + 2, changed_cells)
		scope["workers"] = workers
		return scope
	var sectors: Dictionary = {}
	for center in centers: _add_scope_sectors(sectors, center, radius + 2)
	var observer: Dictionary = observers.get(team, {"sector_epoch": 0, "sectors": {}})
	var keys: Array = sectors.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var versions: Array = []
	for cell in keys: versions.append([cell, int(observer["sectors"].get(cell, 0))])
	var grid_changed := false
	for cell in changed_cells:
		if sectors.has(_cell(Vector2(cell))):
			grid_changed = true
			break
	return {"workers": workers, "grid_changed": grid_changed, "versions": [observer["sector_epoch"], versions, _overflow_versions(world, units) if overflow else []]}

func _add_scope_sectors(sectors: Dictionary, position: Vector2, radius: int) -> void:
	var minimum := _cell(position - Vector2.ONE * radius)
	var maximum := _cell(position + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1): sectors[Vector2i(x, y)] = true

var memory_cursors: Dictionary = {}

func update_building_memory(world, before_visibility: bool, sample: Dictionary = {}) -> Dictionary:
	var probe: Variant = world.tick_pipeline.performance_probe if world.tick_pipeline.performance_probe != null else world.tick_pipeline.stage_observer
	var phase_started := Time.get_ticks_usec() if probe != null else 0
	synchronize(world)
	if probe != null:
		probe.observe_microseconds("simulation.fog.building_index.before" if before_visibility else "simulation.fog.building_index.after", Time.get_ticks_usec() - phase_started)
		phase_started = Time.get_ticks_usec()
	var fog = world.get_fog_of_war()
	# Entity state is normally identical on the two sides of the fog update.
	# Share the immutable render data while evaluating sight for each observer
	# on its own side of the transition. A mutation between passes starts a
	# fresh sample. The caller discards it at the end of this fog update.
	if sample.get("revision", -1) != world.entity_changes.revision or sample.get("epoch", -1) != world.entity_changes.epoch:
		sample = {"revision":world.entity_changes.revision, "epoch":world.entity_changes.epoch, "changes":{}, "rows":{}, "before":{}}
	var building_changes: Dictionary = sample["changes"]
	var rows: Dictionary = sample["rows"]
	for team_value in fog.states_by_player:
		var team := int(team_value)
		if team <= 0: continue
		var state: Dictionary = memory_cursors.get(team, {"entity": -1, "fog": -1})
		var source_revision := int(state["entity"])
		if not building_changes.has(source_revision):
			var source_delta: Dictionary = world.entity_changes.read_changes_since(source_revision)
			var changed_buildings: Array = []
			if not bool(source_delta["full"]):
				if uses_native() and not overflow:
					changed_buildings = native_index.changed_buildings(source_delta["ids"])
				else:
					for id in source_delta["ids"]:
						if world.buildings_by_id.has(id): changed_buildings.append(id)
			building_changes[source_revision] = {"delta": source_delta, "buildings": changed_buildings}
		var change: Dictionary = building_changes[source_revision]
		var delta: Dictionary = change["delta"]
		var memories: Dictionary = world.last_known_buildings_by_player.get(team, {})
		var candidates: Dictionary = {}
		var observed_before: bool = not before_visibility and sample["before"].get(team) == source_revision
		if observed_before:
			# Changed, visible buildings were recorded before sight moved.
			# New visibility below supplies any that were previously hidden.
			for id in delta["removed_ids"]:
				if memories.has(id): candidates[id] = true
		elif bool(delta["full"]):
			for row in world.get_buildings(): candidates[int(row["id"])] = true
		else:
			var changed_ids: Array = change["buildings"].duplicate()
			for id in memories:
				if not world.buildings_by_id.has(id) and delta["masks"].has(id): changed_ids.append(id)
			# Preserve the original sorted delta order before visibility candidates.
			changed_ids.sort()
			for id in changed_ids: candidates[id] = true
		var visibility: Dictionary = {}
		if not before_visibility:
			visibility = fog.visibility_changes_since(team, int(state["fog"]))
			if bool(visibility["full"]) or overflow:
				for row in world.get_buildings(): candidates[int(row["id"])] = true
			elif bool(visibility["exact"]):
				if uses_native():
					for id in native_index.buildings_in_cells(visibility["cells"]): candidates[id] = true
				else:
					var visited_buckets: Dictionary = {}
					for cell in visibility["cells"]:
						var bucket := _cell(Vector2(cell))
						if visited_buckets.has(bucket): continue
						visited_buckets[bucket] = true
						for id in buckets.get(bucket, {}):
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
				if not rows.has(id): rows[id] = world.compact_render_projection(row)
				memories[id] = rows[id]
			elif not before_visibility and memories.has(id) and fog.state_at_world(team, Vector2(memories[id]["pos"])) == 2: memories.erase(id)
		world.last_known_buildings_by_player[team] = memories
		if before_visibility:
			sample["before"][team] = source_revision
		else:
			state["entity"] = world.entity_changes.revision
			state["fog"] = int(visibility["revision"])
			memory_cursors[team] = state
	if probe != null:
		probe.observe_microseconds("simulation.fog.building_memory.before" if before_visibility else "simulation.fog.building_memory.after", Time.get_ticks_usec() - phase_started)
	return sample

func _overflow_versions(world, rows: Array) -> Array:
	var result: Array = []
	for row in rows: result.append([int(row["id"]), world.entity_changes.revision_for(int(row["id"]), 1 | 2 | 8 | 128)])
	return result
