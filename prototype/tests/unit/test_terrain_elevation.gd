extends SceneTree

const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_slope_mapping()
	test_hill_and_interpolated_height()
	test_build_restrictions()
	test_entity_elevation_propagation()

	if failures.is_empty():
		print("T-003 terrain elevation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_slope_mapping() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var terrain: Dictionary = catalog.terrain_catalog_data.get("terrains", {}).get("0", {})
	var graphics: Array = terrain.get("elevation_graphics", [])
	assert_equal(graphics.size(), 19, "RoR exports all elevation graphics entries")
	assert_equal(catalog.terrain_catalog_data.get("geometry", {}).get("elevation_height"), 16, "original elevation is 16 pixels")
	var elevation = TerrainElevation.new(Vector2i(2, 2))
	var cases := {
		TerrainElevation.CORNER_BOTTOM: 1,
		TerrainElevation.CORNER_TOP: 2,
		TerrainElevation.CORNER_LEFT: 3,
		TerrainElevation.CORNER_RIGHT: 4,
		TerrainElevation.CORNER_BOTTOM | TerrainElevation.CORNER_LEFT: 5,
		TerrainElevation.CORNER_TOP | TerrainElevation.CORNER_LEFT: 6,
		TerrainElevation.CORNER_RIGHT | TerrainElevation.CORNER_BOTTOM: 7,
		TerrainElevation.CORNER_TOP | TerrainElevation.CORNER_RIGHT: 8,
		14: 13,
		11: 14,
		13: 15,
		7: 16,
	}
	for mask_value in cases:
		set_profile_mask(elevation, int(mask_value))
		var profile: Dictionary = elevation.cell_profile(Vector2i.ZERO)
		var slope_index := int(cases[mask_value])
		assert_equal(profile["slope_index"], slope_index, "corner mask %d maps to Genie slope" % mask_value)
		assert_equal(elevation.terrain_frame(terrain, profile, Vector2i.ZERO, 41721), int(graphics[slope_index]["shape_id"]), "slope uses original shape frame")
	set_profile_mask(elevation, 5)
	assert_equal(elevation.cell_profile(Vector2i.ZERO)["is_valid"], false, "opposite-corner saddle is rejected")


func set_profile_mask(elevation, mask: int) -> void:
	elevation.clear()
	var vertices := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for index in range(vertices.size()):
		elevation.set_vertex(vertices[index], 1 if mask & (1 << index) else 0)


func test_hill_and_interpolated_height() -> void:
	var elevation = TerrainElevation.new(Vector2i(12, 12))
	elevation.generate_radial_hill(Vector2i(6, 6), 4, 2)
	assert_equal(elevation.vertex_elevation(Vector2i(6, 6)), 2, "hill plateau reaches requested elevation")
	assert_equal(elevation.vertex_elevation(Vector2i(2, 6)), 0, "hill returns to base at radius")
	for y in range(12):
		for x in range(12):
			var here := elevation.vertex_elevation(Vector2i(x, y))
			assert_true(absi(here - elevation.vertex_elevation(Vector2i(x + 1, y))) <= 1, "horizontal vertex gradient stays valid")
			assert_true(absi(here - elevation.vertex_elevation(Vector2i(x, y + 1))) <= 1, "vertical vertex gradient stays valid")
	elevation.clear()
	elevation.set_vertex(Vector2i(1, 1), 1)
	assert_approx(elevation.elevation_at_world(Vector2(0.5, 0.5)), 0.25, "bilinear center elevation")
	assert_equal(TerrainElevation.screen_offset(2.0), Vector2(0, -32), "two levels move screen anchor by 32 pixels")
	elevation.generate_radial_hill(Vector2i(6, 6), 4, 2)
	for world in [Vector2(6, 6), Vector2(4.5, 5.25), Vector2(8.75, 7.5)]:
		var screen := elevation.world_to_screen(world, 2.0, Vector2(320, 180))
		var recovered := elevation.screen_to_world(screen, 2.0, Vector2(320, 180))
		assert_true(recovered.distance_to(world) < 0.001, "elevated screen projection round-trips at %s" % world)


func test_build_restrictions() -> void:
	var grid = NavigationGrid.new(Vector2i(8, 8))
	grid.set_elevation(Vector2i(4, 4), 1)
	grid.set_elevation(Vector2i(5, 4), 1)
	assert_true(grid.can_build([Vector2i(4, 4), Vector2i(5, 4)]), "flat cells at equal elevation allow building")
	grid.set_elevation(Vector2i(5, 4), 2)
	assert_true(not grid.can_build([Vector2i(4, 4), Vector2i(5, 4)]), "mixed elevation blocks building")
	grid.set_elevation(Vector2i(5, 4), 1, true)
	assert_true(not grid.can_build([Vector2i(4, 4), Vector2i(5, 4)]), "slope blocks building")


func test_entity_elevation_propagation() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.configure_demo_elevation(Vector2i(8, 8), 3, 2)
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(8, 8), false)
	var building: Dictionary = world.add_building(50, "town_center", Vector2(8, 8))
	world.add_resource("tree", Vector2(8, 8), 75)
	assert_approx(float(unit["elevation"]), 2.0, "unit receives terrain elevation")
	assert_approx(float(building["elevation"]), 2.0, "building receives terrain elevation")
	assert_approx(float(world.get_resources()[0]["elevation"]), 2.0, "resource receives terrain elevation")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_approx(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %.4f, got %.4f" % [context, expected, actual])
