extends SceneTree

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MainScript := preload("res://main.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_flat_elevated_fog_projection_is_exact()
	test_hidden_slope_boundary_does_not_cover_visible_overlap()
	test_world_fog_mask_reuses_mesh_and_texture()
	test_world_fog_geometry_cache_tracks_viewport()

	if failures.is_empty():
		print("fog terrain boundary tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_flat_elevated_fog_projection_is_exact() -> void:
	var game = MainScript.new()
	game.map_size = Vector2i(6, 6)
	game.view_zoom = 1.0
	game.simulation_world = SimulationWorld.new(game.map_size)
	game.simulation_world.terrain_elevation.clear(1)
	var world_point := Vector2(3.0, 3.0)
	var expected: Vector2 = game.simulation_world.terrain_elevation.world_to_screen(world_point, game.view_zoom, Vector2.ZERO)
	var actual: Vector2 = game._world_to_fog_mesh(world_point)
	assert_equal(actual, expected, "fog projection preserves exact flat elevated terrain height")
	game.free()


func test_hidden_slope_boundary_does_not_cover_visible_overlap() -> void:
	var game = MainScript.new()
	game.map_size = Vector2i(6, 6)
	game.view_zoom = 1.0
	game.simulation_world = SimulationWorld.new(game.map_size)
	game.simulation_world.terrain_elevation.clear()
	game.simulation_world.terrain_elevation.set_vertex(Vector2i(2, 2), 1)
	var cells := PackedByteArray()
	cells.resize(game.map_size.x * game.map_size.y)
	cells.fill(FogOfWar.UNKNOWN)
	cells[2 * game.map_size.x + 1] = FogOfWar.VISIBLE
	assert_true(not game._fog_cell_should_cover(Vector2i(2, 2), cells), "hidden slope adjacent to visible terrain does not paint black over slope art")
	assert_true(game._fog_cell_should_cover(Vector2i(4, 4), cells), "ordinary hidden terrain remains covered")
	game.free()


func test_world_fog_mask_reuses_mesh_and_texture() -> void:
	var game = MainScript.new()
	game.map_size = Vector2i(8, 8)
	game.local_player_team = 1
	game.simulation_world = SimulationWorld.new(game.map_size)
	game.simulation_world.terrain_elevation.clear()
	var fog = game.simulation_world.get_fog_of_war()
	fog.ensure_player(1)
	var cells: PackedByteArray = fog.snapshot(1)
	var chunk_key := Vector2i.ZERO
	game.cached_world_fog_meshes[chunk_key] = game._build_world_fog_mesh(Rect2i(Vector2i.ZERO, game.map_size))
	game.cached_world_fog_mesh_terrain_revision = game.simulation_world.terrain_revision
	game._sync_world_fog_texture(cells, fog.revision_for_player(1))
	var retained_mesh: ArrayMesh = game.cached_world_fog_meshes[chunk_key]
	var retained_texture: ImageTexture = game.cached_world_fog_texture
	var changed_cell := Vector2i(3, 4)
	fog.reveal_explored_cell(1, changed_cell)
	cells = fog.snapshot(1)
	game._sync_world_fog_texture(cells, fog.revision_for_player(1))
	var alpha_offset: int = (changed_cell.y * game.map_size.x + changed_cell.x) * 4 + 3
	assert_true(is_same(game.cached_world_fog_meshes[chunk_key], retained_mesh), "fog state changes reuse the immutable world mesh")
	assert_true(is_same(game.cached_world_fog_texture, retained_texture), "fog state changes update the retained texture instead of allocating another GPU texture")
	assert_equal(int(game.cached_world_fog_texture_data[alpha_offset]), 122, "explored cell updates only the fog mask alpha")
	assert_equal(fog.consume_presentation_dirty_cells(1), [], "mask update drains the presentation dirty-cell queue")
	game.free()


func test_world_fog_geometry_cache_tracks_viewport() -> void:
	var game = MainScript.new()
	for index in range(80):
		game.cached_world_fog_meshes[Vector2i(index, 0)] = ArrayMesh.new()
	var removed := game._prune_world_fog_geometry_cache(Rect2i(Vector2i(20, 0), Vector2i(5, 1)))
	assert_equal(removed, 75, "camera-bounded fog geometry evicts every historical offscreen chunk")
	assert_equal(game.cached_world_fog_meshes.size(), 5, "fog geometry cache size depends on the retained viewport, not explored territory")
	assert_true(game.cached_world_fog_meshes.has(Vector2i(20, 0)) and game.cached_world_fog_meshes.has(Vector2i(24, 0)), "retained viewport fog geometry is preserved")
	game.free()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, str(expected), str(actual)])
