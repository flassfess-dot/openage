extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 5)

	var existing: Dictionary = world.add_unit(1, "improved_bowman", Vector2(8.0, 8.0), false)
	assert_equal(int(existing.get("source_unit_id", -1)), 5, "Minoan Improved Bowman starts at source 5")
	assert_near(float(existing.get("attack_range", 0.0)), 6.0, "source 5 has no source-6-only civilization bonus")

	world.grant_technology(1, 57)
	assert_equal(int(existing.get("source_unit_id", -1)), 6, "existing Improved Bowman upgrades to Composite Bowman")
	assert_near(float(existing.get("attack_range", 0.0)), 9.0, "existing Composite Bowman receives the Minoan +2 range exactly once")
	assert_near(float(existing.get("components", {}).get("vision", {}).get("range", 0.0)), 11.0, "existing Composite Bowman receives the Minoan +2 vision exactly once")

	var produced_after_upgrade: Dictionary = world.add_unit(1, "improved_bowman", Vector2(10.0, 8.0), false)
	assert_equal(int(produced_after_upgrade.get("source_unit_id", -1)), 6, "new Improved Bowman resolves to Composite Bowman")
	assert_near(float(produced_after_upgrade.get("attack_range", 0.0)), float(existing.get("attack_range", 0.0)), "pre-existing and newly created upgraded units have equal range")
	assert_near(float(produced_after_upgrade.get("components", {}).get("vision", {}).get("range", 0.0)), float(existing.get("components", {}).get("vision", {}).get("range", 0.0)), "pre-existing and newly created upgraded units have equal vision")

	if failures.is_empty():
		print("E4 civilization upgrade effect persistence tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
