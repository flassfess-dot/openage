extends RefCounted

const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const GRID_MAPS := ["terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells"]

var epoch := -1
var world_epoch := -1
var resource_revision := -1
var map_data_revision := -1
var elevation_revision := -1
var elevation_epoch := -1
var grid_stamps: Dictionary = {}
var memory_edits: Dictionary = {}
var source_world: WeakRef
var file_kernel: Variant

func configure(world) -> bool:
	if not ClassDB.class_exists("RoRSaveFileKernel"): return false
	file_kernel = ClassDB.instantiate("RoRSaveFileKernel")
	if not file_kernel.has_method("capture_resource_changes"): return false
	world.entity_changes.flush()
	epoch = world.entity_changes.epoch
	world_epoch = world.cache_epoch
	source_world = weakref(world)
	for team in world.known_resources_by_player:
		var edits := {}
		world.known_resources_by_player[team]["checkpoint_edits"] = edits
		memory_edits[team] = edits
	resource_revision = world.entity_changes.revision
	map_data_revision = world.map_data_revision
	elevation_revision = world.terrain_elevation.revision
	elevation_epoch = world.terrain_elevation.cache_epoch
	grid_stamps = {-1:_stamp(world.navigation_grid, true)}
	for team in world.movement_system.knowledge.entries:
		grid_stamps[team] = _stamp(world.movement_system.knowledge.entries[team]["grid"])
	return true

static func _stamp(grid, physical: bool = false) -> Array:
	var dense := {}
	if physical:
		for field in GRID_MAPS:
			if field != "occupied_cells" and grid.get(field).size() == grid.size.x * grid.size.y:
				dense[field] = true
	return [grid.get_instance_id(), grid.cache_epoch, grid.revision, dense, grid.begin_checkpoint_changes(), weakref(grid)]

func release() -> void:
	var world: Variant = source_world.get_ref() if source_world != null else null
	if world != null:
		for team in memory_edits:
			var cache: Dictionary = world.known_resources_by_player.get(team, {})
			if is_same(cache.get("checkpoint_edits"), memory_edits[team]): cache.erase("checkpoint_edits")
	memory_edits.clear()
	source_world = null
	for seed in grid_stamps.values():
		var grid: Variant = seed[5].get_ref()
		if grid != null: grid.end_checkpoint_changes(seed[4])
	grid_stamps.clear()

# These are the only seed values referenced by materialize(). Sending previous
# actor orders, fog and AI projections would serialize them twice on loading.
static func base_state(checkpoint: Dictionary) -> Dictionary:
	return {
		"match_definition":checkpoint["match_definition"], "map_definition":checkpoint["map_definition"],
		"grid":checkpoint["grid"], "knowledge":checkpoint["knowledge"],
		"world":{"resource_nodes":checkpoint["world"]["resource_nodes"], "map_terrain_ids":checkpoint["world"]["map_terrain_ids"]},
		"systems":{"terrain_elevation":checkpoint["systems"]["terrain_elevation"]},
		"remembered_resources":checkpoint["observation_memory"]["resources"],
	}

# Called by the exclusive simulation owner at one completed tick. Only detached
# changes cross the file-writer boundary. Every patch refers to the loading
# checkpoint, so a failed write or a restarted worker needs no previous patch.
func capture(world, controller) -> Dictionary:
	world.entity_changes.flush()
	var same_epoch: bool = epoch == world.entity_changes.epoch and world_epoch == world.cache_epoch
	var view := Checkpoint.capture(world, controller, {}, {}, false)
	var state: Dictionary = view["world"]
	var resource_rows: Array = state["resource_nodes"]
	state["resource_nodes"] = null
	var share_terrain: bool = same_epoch and map_data_revision == world.map_data_revision
	if share_terrain: state["map_terrain_ids"] = null
	var units: Array = state["units"]
	state["units"] = null
	var copies := CaptureCopies.new()
	var world_job := copies.add(Data.copy.bind(state))
	var systems: Dictionary = view["systems"]
	if same_epoch and elevation_epoch == world.terrain_elevation.cache_epoch and elevation_revision == world.terrain_elevation.revision:
		systems["terrain_elevation"] = null
	var system_job := copies.add(Data.copy.bind(systems))
	var grid_jobs := {-1:copies.add(_grid_patch.bind(world.navigation_grid, view["grid"], grid_stamps.get(-1, []) if same_epoch else []))}
	view["grid"] = null
	var knowledge: Dictionary = view["knowledge"]
	for team in knowledge:
		var entry: Dictionary = knowledge[team]
		grid_jobs[team] = copies.add(_grid_patch.bind(world.movement_system.knowledge.entries[team]["grid"], entry["grid"], grid_stamps.get(team, []) if same_epoch else []))
		entry["grid"] = null
	var fog_job := copies.add(Data.copy.bind(view["fog"]))
	copies.begin(units)
	# Keep the entity journal on its owning thread. The workers only read the
	# completed tick, and all their source references expire before it resumes.
	var resources: Dictionary = file_kernel.capture_resource_changes(resource_rows, world.entity_changes.version_source(), resource_revision if same_epoch else -1)
	var memories: Dictionary = view["observation_memory"]
	memories["buildings"] = memories["buildings"].duplicate(true)
	var changed_memories := {}
	for team in memories["resources"]:
		var cache: Dictionary = world.known_resources_by_player[team]
		if same_epoch and memory_edits.has(team) and is_same(cache.get("checkpoint_edits"), memory_edits[team]):
			var changes := {}
			var by_id: Dictionary = cache["ids"]
			for id in memory_edits[team]:
				var row: Variant = by_id.get(id)
				changes[id] = row.duplicate(true) if row is Dictionary and not row.is_read_only() else row
			changed_memories[team] = changes
			memories["resources"][team] = null
			continue
		# A new observer or a rebuilt fog cache has no shared baseline.
		var rows: Array = memories["resources"][team].duplicate(false)
		for index in range(rows.size()):
			if not rows[index].is_read_only(): rows[index] = rows[index].duplicate(true)
		memories["resources"][team] = rows
	view["wildlife_homes"] = view["wildlife_homes"].duplicate(true)
	view["match_definition"] = null
	view["map_definition"] = null
	var captured_units := copies.finish()
	if resources.is_empty(): return {}
	view["world"] = copies.parts[world_job]
	view["world"]["units"] = captured_units
	view["systems"] = copies.parts[system_job]
	view["fog"] = copies.parts[fog_job]
	var grids := {}
	for team in grid_jobs: grids[team] = copies.parts[grid_jobs[team]]
	return {"view":view, "resources":resources, "grids":grids, "changed_memories":changed_memories}

class CaptureCopies extends RefCounted:
	var units: Array
	var parts: Array = []
	var sections: Array[Callable] = []
	var mutex := Mutex.new()
	var task := -1
	const BLOCK := 64

	func add(copy_section: Callable) -> int:
		sections.append(copy_section)
		return sections.size() - 1

	func begin(source: Array) -> void:
		units = source
		var count := sections.size() + ceili(float(units.size()) / BLOCK)
		parts.resize(count)
		task = WorkerThreadPool.add_group_task(copy_part, count, mini(3, count), false, "Capture game state for autosave")

	func copy_part(part: int) -> void:
		var value: Variant
		if part < sections.size():
			value = sections[part].call()
		else:
			var first := (part - sections.size()) * BLOCK
			var rows := []
			for index in range(first, mini(first + BLOCK, units.size())):
				rows.append(units[index].duplicate(true))
			value = rows
		mutex.lock()
		parts[part] = value
		mutex.unlock()

	func finish() -> Array:
		WorkerThreadPool.wait_for_group_task_completion(task)
		var rows := units.duplicate(false)
		for part in range(sections.size(), parts.size()):
			var values: Array = parts[part]
			var first := (part - sections.size()) * BLOCK
			for offset in range(values.size()): rows[first + offset] = values[offset]
		return rows

static func _grid_patch(grid, record: Dictionary, seed: Array) -> Dictionary:
	if seed.size() != 6 or grid.get_instance_id() != seed[0] or grid.cache_epoch != seed[1] or seed[2] < grid.task_full_revision:
		return {"full":record.duplicate(true)}
	var cells: Variant = grid.checkpoint_changes_since(seed[2], seed[4])
	if cells == null: cells = grid.changed_cells_since(seed[2])
	if cells == null:
		var pages: Variant = grid.changed_task_pages_since(seed[2])
		if pages == null or pages.size() * 256 >= grid.size.x * grid.size.y:
			return {"full":record.duplicate(true)}
		cells = []
		for page in pages:
			var first := Vector2i(page) * 16
			for y in range(first.y, mini(first.y + 16, grid.size.y)):
				for x in range(first.x, mini(first.x + 16, grid.size.x)):
					cells.append(Vector2i(x, y))
	var metadata := record.duplicate(false)
	var fields := {}
	for name in GRID_MAPS:
		var source: Dictionary = metadata[name]
		metadata[name] = null
		if cells.is_empty() and name != "occupied_cells": continue
		var values := {}
		for cell in cells:
			if source.has(cell): values[cell] = Data.copy(source[cell])
		# The full physical terrain and elevation maps update existing keys
		# until the next full revision. Sparse occupancy and observer maps
		# can erase/reinsert keys, so carry their exact insertion order.
		var update := {"values":values}
		if not seed[3].has(name) or source.size() != grid.size.x * grid.size.y:
			update["order"] = source.keys()
		fields[name] = update
	return {"meta":metadata.duplicate(true), "fields":fields}

static func index_resources(seed: Dictionary) -> Dictionary:
	var index := {}
	for row in seed["world"]["resource_nodes"]: index[int(row["id"])] = row
	return index

# Observer memory is maintained in ascending resource-ID order, including
# removal and rediscovery. Most explored rows remain in the loading seed.
static func _restore_resource_memory(baseline: Array, changes: Dictionary) -> Array:
	if changes.is_empty(): return baseline
	var ids := changes.keys()
	ids.sort()
	var rows: Array = []
	var cursor := 0
	for row in baseline:
		var id: int = row["id"]
		while cursor < ids.size() and int(ids[cursor]) < id:
			var added: Variant = changes[ids[cursor]]
			if added != null: rows.append(added)
			cursor += 1
		if cursor < ids.size() and int(ids[cursor]) == id:
			var replacement: Variant = changes[id]
			if replacement != null: rows.append(replacement)
			cursor += 1
		else: rows.append(row)
	while cursor < ids.size():
		var added: Variant = changes[ids[cursor]]
		if added != null: rows.append(added)
		cursor += 1
	return rows

# File worker only. Preserve the existing checkpoint and archive schemas.
static func materialize(seed: Dictionary, resource_index: Dictionary, patch: Dictionary) -> Dictionary:
	var view: Dictionary = patch["view"]
	for team in patch.get("changed_memories", {}):
		if not seed.get("remembered_resources", {}).has(team): return {}
		view["observation_memory"]["resources"][team] = _restore_resource_memory(seed["remembered_resources"][team], patch["changed_memories"][team])
	var state: Dictionary = view["world"]
	var resources: Dictionary = patch["resources"]
	var changed: Dictionary = resources["changed"]
	var rows: Array = seed["world"]["resource_nodes"].duplicate(false)
	var ids: PackedInt64Array = resources["ids"]
	rows.resize(ids.size())
	for index in range(ids.size()):
		var id := ids[index]
		var row: Variant = changed.get(id, resource_index.get(id))
		if not row is Dictionary or int(row.get("id", -1)) != id: return {}
		rows[index] = row
	state["resource_nodes"] = rows
	if state["map_terrain_ids"] == null: state["map_terrain_ids"] = seed["world"]["map_terrain_ids"]
	if view["systems"]["terrain_elevation"] == null: view["systems"]["terrain_elevation"] = seed["systems"]["terrain_elevation"]
	for team in patch["grids"]:
		var grid: Dictionary = patch["grids"][team]
		var previous: Dictionary = seed["grid"] if team == -1 else seed["knowledge"].get(team, {}).get("grid", {})
		var result: Dictionary = grid.get("full", {})
		if result.is_empty():
			if previous.is_empty(): return {}
			result = grid["meta"]
			for name in GRID_MAPS:
				var baseline: Dictionary = previous[name]
				if not grid["fields"].has(name):
					result[name] = baseline
					continue
				var update: Dictionary = grid["fields"][name]
				var values: Dictionary = update["values"]
				if not update.has("order"):
					var current := baseline.duplicate(false)
					for cell in values: current[cell] = values[cell]
					result[name] = current
					continue
				# Construct the typed/sparse map directly in the published order.
				# A shallow duplicate followed by clear copied every baseline cell.
				var current := Dictionary({}, baseline.get_typed_key_builtin(), baseline.get_typed_key_class_name(), baseline.get_typed_key_script(), baseline.get_typed_value_builtin(), baseline.get_typed_value_class_name(), baseline.get_typed_value_script())
				for cell in update["order"]:
					if values.has(cell): current[cell] = values[cell]
					elif baseline.has(cell): current[cell] = baseline[cell]
					else: return {}
				result[name] = current
		if team == -1: view["grid"] = result
		else: view["knowledge"][team]["grid"] = result
	view["map_definition"] = seed["map_definition"]
	view["match_definition"] = seed["match_definition"]
	return view
