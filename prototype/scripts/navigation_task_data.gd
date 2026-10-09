class_name RoRNavigationTaskData
extends RefCounted

const Grid := preload("res://scripts/navigation_grid.gd")
const KnowledgeGrid := preload("res://scripts/navigation_knowledge_grid.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const FIELDS := ["size", "terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells", "terrain_restrictions", "revision", "surface_revision"]
const CELL_FIELDS := ["terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells"]

# The caller owns the source identity check. A retained publication is immutable;
# update only changed fields/cells and never mutate data still read by a worker.
static func capture(grid, previous: Dictionary = {}) -> Dictionary:
	var changed: Variant = null
	if previous.get("size") == grid.size and int(previous.get("epoch", -1)) == int(grid.cache_epoch):
		changed = grid.changed_cells_since(int(previous.get("revision", -1)))
	var result := {"size": grid.size, "epoch": grid.cache_epoch, "revision": grid.revision, "surface_revision": grid.surface_revision}
	for field in CELL_FIELDS:
		result[field] = _cell_snapshot(grid.get(field), field, previous.get(field, {}), changed)
	# Restrictions change only on a full topology reset, which has no exact delta.
	result["terrain_restrictions"] = previous["terrain_restrictions"] if changed != null else Data.copy(grid.terrain_restrictions)
	if grid is KnowledgeGrid:
		result["learned"] = grid.learned.duplicate()
	return Data.seal(result)

static func _cell_snapshot(source: Dictionary, field: String, previous: Dictionary, changed: Variant) -> Dictionary:
	var result: Dictionary = previous
	if changed == null:
		if field == "terrain_cells":
			var strings: Dictionary[Vector2i, String] = {}
			strings.assign(source)
			result = strings
		elif field in ["terrain_ids", "elevation_cells"]:
			var integers: Dictionary[Vector2i, int] = {}
			integers.assign(source)
			result = integers
		else:
			var flags: Dictionary[Vector2i, bool] = {}
			if field == "occupied_cells":
				# Search/placement workers need blocked-cell membership, not entity
				# records. Do not deep-copy every tree's occupant dictionaries.
				for cell in source: flags[cell] = true
			else:
				flags.assign(source)
			result = flags
	else:
		var copied := false
		for cell in changed:
			var present := source.has(cell)
			var value: Variant = true if field == "occupied_cells" else source.get(cell)
			if present == previous.has(cell) and (not present or previous[cell] == value):
				continue
			if not copied:
				result = previous.duplicate()
				copied = true
			if present: result[cell] = value
			else: result.erase(cell)
	result.make_read_only()
	return result

static func create_grid(input: Dictionary):
	# Construct one cell, then install the detached topology. Never initialize
	# the complete default map merely to overwrite it. Worker grids are read-only.
	var grid = KnowledgeGrid.new(Vector2i.ONE) if input.has("learned") else Grid.new()
	if input.has("learned"):
		grid.learned = input["learned"]
	for field in FIELDS:
		grid.set(field, input[field])
	return grid
