extends SceneTree

const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(3.5, 3.5), false)
	var building: Dictionary = world.add_building(90, "house", Vector2(10.5, 10.5), 1, true)
	assert_same(world.find_unit(int(unit["id"])), unit, "unit lookup returns the authoritative dictionary")
	assert_same(world.find_building(90), building, "building lookup returns the authoritative dictionary")
	assert_same(world.find_combat_target(90), building, "combat target lookup shares the building index")

	unit["removed"] = true
	building["removed"] = true
	# Purge is flag-gated (E6-019 active registries); the authoritative removal
	# paths raise these flags, so a direct removal test must raise them too.
	world.unit_removal_pending = true
	world.building_removal_pending = true
	world.purge_removed_units()
	assert_true(world.find_unit(int(unit["id"])) == null, "purged unit leaves the index")
	assert_true(world.find_building(90) == null, "purged building leaves the index")

	world.reset_game(false)
	assert_true(world.units_by_id.is_empty(), "reset clears the unit index")
	assert_true(world.buildings_by_id.is_empty(), "reset clears the building index")
	if failures.is_empty():
		print("E6-001 entity lookup index tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_same(actual: Variant, expected: Variant, context: String) -> void:
	if not is_same(actual, expected):
		failures.append("%s: expected the same dictionary instance" % context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
