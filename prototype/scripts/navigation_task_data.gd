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
	if input.has("cell_pages"):
		grid.revision = -1
		update_chunked_grid(grid, input)
		return grid
	if input.has("learned"):
		grid.learned = input["learned"]
	for field in FIELDS:
		grid.set(field, input[field])
	return grid


# AI build searches carry immutable 16x16 pages. Updating one known cell copies
# its page, not every known terrain/occupancy entry on a 400x400 map.
const PAGE_SIZE := 16
static func capture_chunked(grid, previous: Dictionary = {}, source_generation: int = 0) -> Dictionary:
	if int(previous.get("source_generation", -1)) == source_generation and int(previous.get("epoch", -1)) == int(grid.cache_epoch) and int(previous.get("revision", -1)) == int(grid.revision):
		return previous
	var changes: Variant = null
	if int(previous.get("source_generation", -1)) == source_generation and previous.get("size") == grid.size and int(previous.get("epoch", -1)) == int(grid.cache_epoch):
		changes = grid.changed_cells_since(int(previous.get("revision", -1)))
	var pages: Dictionary = {}
	for field in CELL_FIELDS:
		pages[field] = _paged_cells(grid.get(field), field, previous.get("cell_pages", {}).get(field, {}), changes)
	var result := {"source_generation": source_generation, "size": grid.size, "epoch": grid.cache_epoch, "revision": grid.revision, "previous_revision": previous.get("revision", -1), "surface_revision": grid.surface_revision, "cell_pages": pages, "changed_cells": changes, "change_log": Data.copy(grid._change_log), "terrain_restrictions": previous["terrain_restrictions"] if changes != null else Data.copy(grid.terrain_restrictions)}
	if grid is KnowledgeGrid: result["learned"] = grid.learned.duplicate()
	return Data.seal(result)

static func _page_key(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / PAGE_SIZE, cell.y / PAGE_SIZE)

static func _empty_page(field: String) -> Dictionary:
	if field == "terrain_cells":
		var strings: Dictionary[Vector2i, String] = {}
		return strings
	if field in ["terrain_ids", "elevation_cells"]:
		var integers: Dictionary[Vector2i, int] = {}
		return integers
	var flags: Dictionary[Vector2i, bool] = {}
	return flags

static func _paged_cells(source: Dictionary, field: String, previous: Dictionary, changes: Variant) -> Dictionary:
	var pages: Dictionary = previous.duplicate() if changes != null else {}
	var copied: Dictionary = {}
	var cells: Array = source.keys() if changes == null else changes
	for cell in cells:
		var key := _page_key(cell)
		var page: Dictionary = pages.get(key, {})
		var present := source.has(cell)
		var value: Variant = true if field == "occupied_cells" else source.get(cell)
		if changes != null and present == page.has(cell) and (not present or page[cell] == value): continue
		if not copied.has(key):
			page = page.duplicate() if pages.has(key) else _empty_page(field)
			pages[key] = page
			copied[key] = true
		if present: page[cell] = value
		else: page.erase(cell)
	for key in copied: pages[key].make_read_only()
	pages.make_read_only()
	return pages

static func update_chunked_grid(grid, input: Dictionary) -> void:
	var changes: Variant = input.get("changed_cells")
	var incremental: bool = changes != null and int(input.get("previous_revision", -1)) == int(grid.revision)
	if int(input["revision"]) != int(grid.revision) or grid.size != input["size"]:
		for field in CELL_FIELDS:
			var target: Dictionary = grid.get(field)
			var pages: Dictionary = input["cell_pages"][field]
			if incremental:
				for cell in changes:
					var page: Dictionary = pages.get(_page_key(cell), {})
					if page.has(cell): target[cell] = page[cell]
					else: target.erase(cell)
			else:
				target.clear()
				for page in pages.values(): target.merge(page, true)
		grid.surface_component_cache.clear()
	grid.size = input["size"]
	grid.cache_epoch = int(input["epoch"])
	grid.revision = int(input["revision"])
	grid.surface_revision = int(input["surface_revision"])
	grid.terrain_restrictions = input["terrain_restrictions"]
	grid._change_log = Data.copy(input["change_log"])
	if input.has("learned"): grid.learned = input["learned"]
