extends RefCounted
## Main-thread terrain owned independently from the running simulation.
const Elevation := preload("res://scripts/terrain_elevation.gd")
const Dependency := preload("res://scripts/cache_dependency.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
var terrain_elevation
var cache_epoch := 0
var terrain_revision := -1
var terrain_change_history: Array = []
var source_id := 0
var source_epoch := -1
var surface_stamp: Dictionary = {}
var geometry_stamp: Dictionary = {}
var size := Vector2i.ZERO
var ids := PackedInt32Array()
var surface_revision := -1

func synchronize(world) -> void:
	var replaced: bool = source_id != world.get_instance_id() or source_epoch != world.cache_epoch
	if replaced:
		cache_epoch += 1
		source_id = world.get_instance_id()
		source_epoch = world.cache_epoch
		size = world.map_size
		surface_stamp = {}
		geometry_stamp = {}
	var surface := Dependency.changes(world, Dependency.TERRAIN_SURFACE, surface_stamp)
	if replaced or bool(surface["full"]) or not bool(surface["exact"]):
		ids.resize(size.x * size.y)
		for y in range(size.y):
			for x in range(size.x): ids[y * size.x + x] = world.terrain_id_at_cell(Vector2i(x, y))
	else:
		for cell in surface["cells"]:
			if Rect2i(Vector2i.ZERO,size).has_point(cell): ids[cell.y * size.x + cell.x] = world.terrain_id_at_cell(cell)
	if replaced or terrain_revision != world.terrain_revision:
		terrain_change_history = world.terrain_change_history.duplicate(true)
	terrain_revision = world.terrain_revision
	surface_revision = world.navigation_grid.surface_revision
	surface_stamp = surface["stamp"]
	var geometry := Dependency.stamp(world, Dependency.TERRAIN_GEOMETRY)
	if geometry != geometry_stamp:
		terrain_elevation = Elevation.new(size, false)
		var original = world.terrain_elevation
		terrain_elevation.vertex_levels = original.vertex_levels.duplicate()
		terrain_elevation.river_shape = original.river_shape.duplicate()
		terrain_elevation.nonzero_vertex_count = original.nonzero_vertex_count
		terrain_elevation.maximum_vertex_level = original.maximum_vertex_level
		terrain_elevation.maximum_vertex_level_dirty = original.maximum_vertex_level_dirty
		terrain_elevation.revision = original.revision
		terrain_elevation.cache_epoch = original.cache_epoch
		geometry_stamp = geometry

func terrain_id_at_cell(cell: Vector2i) -> int:
	return ids[cell.y * size.x + cell.x] if Rect2i(Vector2i.ZERO,size).has_point(cell) else Rules.terrain_id_for_logical(Rules.terrain_at(cell))

func cache_changes(domain: String, previous: Variant, observer: int = 0) -> Dictionary:
	return Dependency.changes(self, domain, previous, observer)
