class_name RoRNavigationKnowledgeGrid
extends "res://scripts/navigation_grid.gd"

var learned := PackedByteArray()


func _init(world_size: Vector2i) -> void:
	super(Vector2i.ONE)
	size = world_size
	terrain_cells.clear()
	terrain_ids.clear()
	elevation_cells.clear()
	slope_cells.clear()
	learned.resize(world_size.x * world_size.y)


func is_walkable_for(cell: Vector2i, domain: String = "land", restriction_id: int = -1) -> bool:
	if not contains(cell):
		return false
	if learned[cell.y * size.x + cell.x] == 0:
		return true
	return super.is_walkable_for(cell, domain, restriction_id)


func surface_accessible(cell: Vector2i, domain: String = "land", restriction_id: int = -1) -> bool:
	if not contains(cell):
		return false
	if learned[cell.y * size.x + cell.x] == 0:
		return true
	return super.surface_accessible(cell, domain, restriction_id)


func native_walkability_mask(domain: String, restriction_id: int, probe: Variant = null) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	# Unknown terrain is traversable in every domain. Fill it in native code,
	# then evaluate only the sparse cells learned by this observer.
	mask.fill(1)
	for cell_value in terrain_cells:
		var cell: Vector2i = cell_value
		mask[cell.y * size.x + cell.x] = int(is_walkable_for(cell, domain, restriction_id))
	if probe != null:
		probe.increment("navigation.native_mask_evaluated_cells", terrain_cells.size())
	return mask
