class_name RoRNavigationKnowledgeGrid
extends "res://scripts/navigation_grid.gd"

const Fog := preload("res://scripts/fog_of_war.gd")

var learned := PackedByteArray()


func _init(world_size: Vector2i) -> void:
	super(Vector2i.ONE)
	size = world_size
	terrain_cells.clear()
	terrain_ids.clear()
	elevation_cells.clear()
	slope_cells.clear()
	learned.resize(world_size.x * world_size.y)


func discard_unexplored_cells(states: PackedByteArray) -> void:
	var forgotten: Array[Vector2i] = []
	for cell: Vector2i in terrain_cells:
		if states[cell.y * size.x + cell.x] == Fog.UNKNOWN:
			forgotten.append(cell)
	if forgotten.is_empty():
		return
	# Older checkpoints could store gate cells that were still under black fog.
	# Copy the restored tables before removing this knowledge.
	terrain_cells = terrain_cells.duplicate()
	terrain_ids = terrain_ids.duplicate()
	elevation_cells = elevation_cells.duplicate()
	slope_cells = slope_cells.duplicate()
	occupied_cells = occupied_cells.duplicate()
	_change_log = _change_log.duplicate(true)
	for cell in forgotten:
		learned[cell.y * size.x + cell.x] = 0
		terrain_cells.erase(cell)
		terrain_ids.erase(cell)
		elevation_cells.erase(cell)
		slope_cells.erase(cell)
		occupied_cells.erase(cell)
		_record_change(cell)
	revision += 1
	surface_revision += 1


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


func _native_surface_components(domain: String, restriction_id: int) -> Variant:
	if native_masks_enabled and mask_kernel != null and mask_kernel.has_method("surface_components"):
		return mask_kernel.surface_components(size, terrain_cells, terrain_ids, terrain_restrictions, learned, true, domain, restriction_id)
	return null


func native_walkability_mask(domain: String, restriction_id: int, probe: Variant = null) -> PackedByteArray:
	if native_masks_enabled and mask_kernel != null and mask_kernel.has_method("walkability_mask"):
		if probe != null: probe.increment("navigation.native_mask_evaluated_cells", terrain_cells.size())
		return mask_kernel.walkability_mask(size,terrain_cells,terrain_ids,occupied_cells,terrain_restrictions,learned,true,domain,restriction_id)
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


func _native_surface_component_labels(domain: String, restriction_id: int) -> Variant:
	if native_masks_enabled and mask_kernel != null and mask_kernel.has_method("surface_component_labels"):
		return mask_kernel.surface_component_labels(size, terrain_cells, terrain_ids, terrain_restrictions, learned, true, domain, restriction_id)
	return null
