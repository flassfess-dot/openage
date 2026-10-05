extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Canvas := preload("res://scripts/terrain_canvas.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Main := preload("res://main.gd")
const Probe := preload("res://scripts/performance_probe.gd")

class CountingElevation:
	extends "res://scripts/terrain_elevation.gd"
	var profile_calls := 0
	func cell_profile(cell: Vector2i) -> Dictionary:
		profile_calls += 1
		return super.cell_profile(cell)

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	test_canvas_changes(catalog)
	test_fog_changes()
	test_native_samples(catalog)
	test_history_bounds()
	for failure in failures:
		push_error(failure)
	print("Local terrain and fog invalidation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func fixture():
	var world := World.new(Vector2i(64, 64))
	for y in range(64):
		for x in range(64):
			world.map_terrain_ids[Vector2i(x, y)] = 0
	world._record_terrain_change()
	return world

func test_canvas_changes(catalog) -> void:
	var world = fixture()
	var state := {"bounds": Rect2i(4, 4, 6, 6)}
	var canvas := Canvas.new()
	canvas.native_enabled = false
	canvas.configure(world.map_size, 42, catalog, world, world.terrain_id_at_cell, func(): return state["bounds"])
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	var mesh: ArrayMesh = canvas.terrain_mesh
	var generation: int = canvas.mesh_generation
	var before: int = world.terrain_revision
	var far_tree := {"kind": "tree", "pos": Vector2(56.5, 56.5)}
	world.register_forest_resource(far_tree)
	check(world.terrain_changed_cells_since(before) == [Vector2i(56, 56)], "tree insertion records its exact surface delta")
	check(world.terrain_changed_cells_since(before) == [Vector2i(56, 56)], "deltas are available to independent consumers")
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(canvas.terrain_mesh == mesh and canvas.mesh_generation == generation, "offscreen tree change retains visible terrain")
	world.unregister_forest_resource(far_tree)
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(canvas.terrain_mesh == mesh, "offscreen tree removal retains visible terrain")
	var near_tree := {"kind": "tree", "pos": Vector2(6.5, 6.5)}
	world.register_forest_resource(near_tree)
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(canvas.mesh_generation > generation, "visible material change rebuilds terrain")
	check(int(canvas.last_mesh_build_metrics.get("legacy_tiles_built", -1)) == 9, "only changed tile and its eight neighbors are recomputed")
	check(int(canvas.last_mesh_build_metrics.get("legacy_cached_tiles", 0)) > 0, "unchanged legacy drawables are reused")
	var incremental: Array = canvas.terrain_mesh.surface_get_arrays(0)
	canvas.terrain_drawable_cache.clear()
	canvas._rebuild_terrain_mesh()
	check(canvas.terrain_mesh.surface_get_arrays(0) == incremental, "incremental mesh is identical to a fresh full build")
	generation = canvas.mesh_generation
	world.terrain_elevation.set_vertex(Vector2i(6, 6), 1)
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(canvas.mesh_generation > generation, "elevation change invalidates geometry independently of material revision")
	state["bounds"] = Rect2i(48, 48, 6, 6)
	canvas.set_view_state(1.0, Vector2(-500, 0), Vector2(640, 480), world.terrain_revision)
	check(canvas.terrain_drawable_cache.size() <= canvas.terrain_mesh_bounds.size.x * canvas.terrain_mesh_bounds.size.y, "legacy cache remains bounded by the current view")
	canvas.free()
	world.task_coordinator.shutdown()

func test_fog_changes() -> void:
	var game = Main.new()
	game.map_size = Vector2i(64, 64)
	game.local_player_team = 1
	game.simulation_world = fixture()
	game.simulation_world.terrain_elevation = CountingElevation.new(game.map_size)
	var fog = game.simulation_world.fog_of_war
	fog.ensure_player(1)
	game._sync_fog_geometry_revision()
	game._sync_world_fog_texture(fog.snapshot(1), fog.revision_for_player(1))
	var calls: int = game.simulation_world.terrain_elevation.profile_calls
	var texture = game.cached_world_fog_texture
	var mesh := ArrayMesh.new()
	game.cached_world_fog_meshes[Vector2i.ZERO] = mesh
	var tree := {"kind": "tree", "pos": Vector2(56.5, 56.5)}
	game.simulation_world.register_forest_resource(tree)
	fog.reveal_explored_cell(1, Vector2i(6, 6))
	game._sync_fog_geometry_revision()
	var probe := Probe.new()
	game._sync_world_fog_texture(fog.snapshot(1), fog.revision_for_player(1), probe)
	check(game.simulation_world.terrain_elevation.profile_calls == calls, "material changes never rescan full-map slope profiles")
	check(game.cached_world_fog_meshes.get(Vector2i.ZERO) == mesh and game.cached_world_fog_texture == texture, "material changes retain fog geometry and texture")
	check(int(probe.counters.get("presentation.fog.mask_cells_updated", 0)) == 9, "fog updates only changed visibility and its neighbors")
	game.simulation_world.terrain_elevation.set_vertex(Vector2i(6, 6), 1)
	game._sync_fog_geometry_revision()
	check(game.cached_world_fog_meshes.is_empty() and game.cached_world_fog_texture_revision < 0, "actual height change invalidates fog geometry and mask")
	game.free()

func test_native_samples(catalog) -> void:
	check(catalog.enable_environment_pack(), "native mixed-terrain materials load")
	var world = fixture()
	var state := {"bounds": Rect2i(4, 4, 6, 6), "calls": 0}
	var provider := func(cell):
		state["calls"] += 1
		return world.terrain_id_at_cell(cell)
	var canvas := Canvas.new()
	canvas.async_rebuilds = false
	canvas.configure(world.map_size, 42, catalog, world, provider, func(): return state["bounds"])
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	var calls: int = int(state["calls"])
	var mesh = canvas.terrain_mesh
	world.register_forest_resource({"kind": "tree", "pos": Vector2(56.5, 56.5)})
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(canvas.terrain_mesh == mesh and int(state["calls"]) == calls, "native terrain ignores offscreen changes")
	world.register_forest_resource({"kind": "tree", "pos": Vector2(6.5, 6.5)})
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), world.terrain_revision)
	check(int(state["calls"]) - calls == 1, "native capture samples only the changed material cell")
	var actual: Array = canvas.terrain_mesh.surface_get_arrays(0)
	canvas.invalidate_content()
	check(canvas.terrain_mesh.surface_get_arrays(0) == actual, "native incremental materials match full-quality fresh geometry")
	canvas.free()
	world.task_coordinator.shutdown()


func test_history_bounds() -> void:
	var world = fixture()
	var original: int = world.terrain_revision
	for index in range(world.MAX_TERRAIN_CHANGE_HISTORY + 1):
		world._record_terrain_change(Vector2i(index % 64, index / 64))
	check(world.terrain_change_history.size() == world.MAX_TERRAIN_CHANGE_HISTORY, "terrain delta history is bounded")
	check(world.terrain_changed_cells_since(original) == null, "overflow requests a full refresh")
	check(world.terrain_changed_cells_since(world.terrain_revision - 1).size() == 1, "recent deltas remain available")
	world._record_terrain_change()
	check(world.terrain_changed_cells_since(world.terrain_revision - 1) == null, "map configuration requests a full refresh")
	world.terrain_revision = 2
	check(world.terrain_changed_cells_since(1) == null, "restored revision cannot consume future deltas")
	world.task_coordinator.shutdown()

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
