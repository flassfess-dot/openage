extends SceneTree

const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_water_and_shore_contract()
	test_separate_land_and_water_navigation()
	test_ship_placement_uses_original_restriction()

	if failures.is_empty():
		print("T-004 water and shore tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_water_and_shore_contract() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.terrain_catalog_data
	var water: Dictionary = data.get("terrains", {}).get("1", {})
	var beach: Dictionary = data.get("terrains", {}).get("2", {})
	assert_equal(water.get("elevation_graphics", [])[0].get("frame_count"), 4, "water has four original flat variants")
	assert_equal(water.get("animation", {}).get("animated"), false, "RoR marks water terrain as static rather than frame-animated")
	assert_equal(water.get("terrain_to_draw"), [2.0, 2.0], "water points to original beach terrain")
	assert_equal(beach.get("replacement_terrain_id"), 6, "beach uses desert texture underlay")
	assert_equal(beach.get("borders", [])[1], 2, "beach-water edge uses original border 2")
	var restrictions: Array = data.get("restrictions", [])
	assert_true(TerrainRules.is_terrain_accessible(restrictions, 3, 1), "ship restriction permits water")
	assert_true(TerrainRules.is_terrain_accessible(restrictions, 3, 22), "ship restriction permits dark water")
	assert_true(not TerrainRules.is_terrain_accessible(restrictions, 3, 2), "ship restriction excludes beach")


func test_separate_land_and_water_navigation() -> void:
	var grid = NavigationGrid.new(Vector2i(8, 8))
	grid.configure_terrain(func(cell: Vector2i) -> String:
		if cell.x <= 2: return "water"
		if cell.x == 3: return "shore"
		return "land"
	)
	assert_true(grid.is_walkable_for(Vector2i(1, 4), "water"), "water is navigable by ships")
	assert_true(not grid.is_walkable_for(Vector2i(3, 4), "water"), "shore is not a ship cell")
	assert_true(grid.is_walkable_for(Vector2i(3, 4), "land"), "shore is walkable by land units")
	assert_true(not grid.is_walkable_for(Vector2i(1, 4), "land"), "water blocks land units")
	var finder = Pathfinder.new(grid)
	var ship_path := finder.find_cell_path(Vector2i(0, 1), Vector2i(2, 6), "water")
	assert_true(not ship_path.is_empty(), "ship route exists through water")
	assert_true(ship_path.all(func(cell): return cell.x <= 2), "ship route never enters shore or land")
	assert_true(grid.can_place([Vector2i(1, 3), Vector2i(2, 3)], "water"), "ship footprint fits entirely in water")
	assert_true(not grid.can_place([Vector2i(2, 3), Vector2i(3, 3)], "water"), "ship footprint cannot cross the shore")


func test_ship_placement_uses_original_restriction() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec({"units": {"scout_ship": {"terrain_restriction": 3, "hit_points": 120.0, "speed": 1.75, "selection_radius": [1.0, 1.0, 2.0]}}})
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var ship: Dictionary = world.add_unit(1, "scout_ship", Vector2(8.5, 8.5), false)
	var cell := Vector2i(floori(ship["pos"].x), floori(ship["pos"].y))
	assert_equal(ship["movement_domain"], "water", "terrain restriction 3 selects naval movement")
	assert_true(world.navigation_grid.is_walkable_for(cell, "water", 3), "ship requested on land is placed on nearest legal water cell")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
