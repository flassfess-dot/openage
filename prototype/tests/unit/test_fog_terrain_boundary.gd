extends SceneTree

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MainScript := preload("res://main.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_flat_elevated_fog_projection_is_exact()
	test_hidden_slope_boundary_does_not_cover_visible_overlap()
	test_fog_chunk_rows_are_chunk_local()

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


func test_fog_chunk_rows_are_chunk_local() -> void:
	var game = MainScript.new()
	game.map_size = Vector2i(8, 4)
	var cells := PackedByteArray()
	cells.resize(game.map_size.x * game.map_size.y)
	cells.fill(FogOfWar.UNKNOWN)
	var left_bounds := Rect2i(Vector2i(0, 0), Vector2i(4, 4))
	var right_bounds := Rect2i(Vector2i(4, 0), Vector2i(4, 4))
	var right_rows := game._fog_rows_for_bounds(cells, right_bounds)
	cells[1 * game.map_size.x + 1] = FogOfWar.VISIBLE
	assert_equal(game._fog_rows_for_bounds(cells, right_bounds), right_rows, "change in left fog chunk leaves right chunk rows unchanged")
	assert_true(game._fog_rows_for_bounds(cells, left_bounds) != right_rows, "left chunk rows are independent from right chunk rows")
	game.free()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, str(expected), str(actual)])
