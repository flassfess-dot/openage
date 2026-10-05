class_name RoRNavigationTaskData
extends RefCounted

const Grid := preload("res://scripts/navigation_grid.gd")
const KnowledgeGrid := preload("res://scripts/navigation_knowledge_grid.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const FIELDS := ["size", "terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells", "terrain_restrictions", "revision", "surface_revision"]

static func capture(grid) -> Dictionary:
	var result: Dictionary = {}
	for field in FIELDS:
		result[field] = Data.copy(grid.get(field))
	if grid is KnowledgeGrid:
		result["learned"] = grid.learned.duplicate()
	return Data.seal(result)

static func create_grid(input: Dictionary):
	# Construct one cell, then install the detached topology. Never initialize
	# the complete default map merely to overwrite it.
	var grid = KnowledgeGrid.new(Vector2i.ONE) if input.has("learned") else Grid.new()
	if input.has("learned"):
		grid.learned = input["learned"]
	for field in FIELDS:
		grid.set(field, input[field])
	return grid
