extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const View := preload("res://scripts/render_terrain_view.gd")
const Dependency := preload("res://scripts/cache_dependency.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var world := World.new(Vector2i(8,8))
	var view := View.new()
	view.synchronize(world)
	var cell := Vector2i(3,3)
	var before: int = view.terrain_id_at_cell(cell)
	var geometry = view.terrain_elevation
	var stamp := Dependency.stamp(view,Dependency.TERRAIN_SURFACE)
	world.map_terrain_ids[cell] = before + 1
	world._record_terrain_change(cell)
	world.terrain_elevation.set_vertex(cell,2)
	world.terrain_elevation.river_shape = {"size":Vector2i(2,2), "resolution":2, "samples":PackedFloat32Array([1,1,0])}
	check(view.terrain_id_at_cell(cell) == before and geometry.vertex_elevation(cell) == 0,"surface and height remain isolated while simulation changes")
	view.synchronize(world)
	check(view.terrain_elevation.river_shape == world.terrain_elevation.river_shape and geometry.river_shape.is_empty(), "river contour publishes with the geometry and preserves the old render view")
	check(view.terrain_id_at_cell(cell) == before+1,"incremental terrain surface reaches the renderer")
	check(view.terrain_elevation.vertex_elevation(cell) == 2 and geometry.vertex_elevation(cell) == 0,"geometry replacement preserves the old render view")
	var changes := Dependency.changes(view,Dependency.TERRAIN_SURFACE,stamp)
	check(changes["exact"] and changes["cells"].has(cell),"terrain canvas receives exact surface invalidation")
	var other := World.new(Vector2i(4,5))
	view.synchronize(other)
	check(view.ids.size() == 20 and view.size == Vector2i(4,5),"match replacement bounds and replaces the terrain view")
	check(Dependency.changes(view,Dependency.TERRAIN_SURFACE,stamp)["full"],"old match stamp cannot reuse terrain")
	world.shutdown_derived_state()
	other.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Render terrain view: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
