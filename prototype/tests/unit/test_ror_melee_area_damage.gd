extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_source_sweep(catalog, "armored_elephant", -1, "Armored Elephant")
	test_source_sweep(catalog, "chariot", 339, "Scythe Chariot")
	if failures.is_empty():
		print("P03 source melee area damage tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_source_sweep(catalog, kind: String, upgrade_source_id: int, label: String) -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var attacker: Dictionary = world.add_unit(1, kind, Vector2(6.5, 7), false)
	if upgrade_source_id >= 0:
		world.apply_unit_upgrade_to_entity(attacker, upgrade_source_id, false)
	assert_true(int(attacker.get("projectile_id", -2)) < 0, "%s uses melee impact" % label)
	assert_true(float(attacker.get("components", {}).get("combat", {}).get("blast_range", 0.0)) > 0.0, "%s retains source area range" % label)
	attacker["components"]["combat"]["friendly_fire"] = false
	var primary: Dictionary = world.add_unit(2, "clubman", Vector2(7.0, 7), false)
	var adjacent: Dictionary = world.add_unit(2, "clubman", Vector2(8.2, 7), false)
	var far: Dictionary = world.add_unit(2, "clubman", Vector2(13, 7), false)
	var ally: Dictionary = world.add_unit(1, "clubman", Vector2(7, 8.2), false)
	var primary_hp := float(primary["hp"])
	var adjacent_hp := float(adjacent["hp"])
	var far_hp := float(far["hp"])
	var ally_hp := float(ally["hp"])
	world.assign_command_attack([attacker], int(primary["id"]))
	for _step in range(80):
		world.advance(0.05, 1, 2)
		if float(adjacent["hp"]) < adjacent_hp:
			break
	assert_true(float(primary["hp"]) < primary_hp, "%s damages its primary target" % label)
	assert_true(float(adjacent["hp"]) < adjacent_hp, "%s sweep damages a neighbouring enemy" % label)
	assert_equal(float(far["hp"]), far_hp, "%s sweep has a bounded radius" % label)
	assert_equal(float(ally["hp"]), ally_hp, "%s respects friendly-fire policy" % label)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
