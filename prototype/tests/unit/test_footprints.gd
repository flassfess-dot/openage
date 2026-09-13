extends SceneTree

const Footprint := preload("res://scripts/footprint.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_mobile_footprints_use_original_data()
	test_building_polygon_and_cells()
	test_clearance_and_priority()

	if failures.is_empty():
		print("N-001 footprint tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_mobile_footprints_use_original_data() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec(catalog.gamespec_data)
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var clubman: Dictionary = world.add_unit(1, "clubman", Vector2(4, 3), false)
	assert_float(villager["footprint_radius"], 0.2, "villager movement radius")
	assert_float(clubman["footprint_radius"], 0.3, "clubman movement radius")
	assert_equal(villager["selection_radius"], Vector2(0.2, 0.2), "villager selection radius")
	assert_true(float(villager["selection_height"]) > 1.6, "selection height retained")


func test_building_polygon_and_cells() -> void:
	var footprint := Footprint.building({"selection_radius": [1.5, 1.5, 2.0]}, Vector2(12, 12))
	assert_equal(footprint["shape"], "polygon", "building shape")
	assert_equal(footprint["polygon"].size(), 4, "building polygon corners")
	assert_equal(footprint["occupied_cells"].size(), 9, "3x3 occupied cells")
	assert_true(footprint["occupied_cells"].has(Vector2i(12, 12)), "center cell occupied")


func test_clearance_and_priority() -> void:
	var archer := {"footprint_radius": 0.3, "minimum_clearance": 0.06, "push_priority": 1}
	var clubman := {"footprint_radius": 0.3, "minimum_clearance": 0.08, "push_priority": 3}
	assert_float(Footprint.separation_distance(archer, clubman), 0.68, "combined radius and clearance")
	assert_true(Footprint.displacement_share(archer, clubman) > Footprint.displacement_share(clubman, archer), "lighter unit yields more")


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
