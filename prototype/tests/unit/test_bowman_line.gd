extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_bowman_replacement_line(catalog)
	if failures.is_empty():
		print("I12-007 Bowman replacement line tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_bowman_replacement_line(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)
	world.set_resource_amount(1, 0, 1000)
	world.set_resource_amount(1, 1, 1000)
	world.set_resource_amount(1, 3, 1000)
	var range: Dictionary = world.add_building(920, "archery_range", Vector2(12.0, 12.0), 1)
	assert_true(world.is_object_available(1, 4), "Archery Range unlocks Bowman 4")
	assert_true(not world.is_object_available(1, 5), "Improved Bowman starts locked")
	var existing: Dictionary = world.add_unit(1, "archer", Vector2(8.0, 8.0), false)
	world.grant_technology(1, 102)
	var research: Variant = world.enqueue_research(int(range["id"]), 1, 56)
	assert_true(research != null, "Improved Bowman enters normal Archery Range research queue")
	world.update_production(61.0)
	assert_true(world.is_object_available(1, 5), "technology 56 unlocks Improved Bowman")
	assert_equal(existing.get("source_unit_id"), 4, "unlock does not rewrite existing Bowman")
	assert_equal(world.get_unit_production_availability(int(range["id"]), 1, "archer").get("reason"), "unit_replaced", "obsolete Bowman order is explicitly rejected")
	var option_kinds: Array = world.get_unit_production_options(int(range["id"]), 1).map(func(option): return String(option.get("kind", "")))
	assert_true(option_kinds.has("improved_bowman"), "production palette exposes Improved Bowman")
	assert_true(not option_kinds.has("archer"), "production palette hides replaced Bowman")
	var food_before := world.get_resource_amount(1, 0)
	var gold_before := world.get_resource_amount(1, 3)
	var order: Variant = world.enqueue_unit_production(int(range["id"]), 1, "improved_bowman")
	assert_true(order != null, "Archery Range accepts Improved Bowman")
	assert_equal(world.get_resource_amount(1, 0), food_before - 40, "production reserves original food cost")
	assert_equal(world.get_resource_amount(1, 3), gold_before - 20, "production reserves original gold cost")
	world.update_production(31.0)
	var improved: Array = world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "improved_bowman")
	assert_equal(improved.size(), 1, "Improved Bowman production completes")
	if improved.is_empty():
		return
	var unit: Dictionary = improved[0]
	assert_equal(unit.get("source_unit_id"), 5, "Improved Bowman keeps source identity")
	assert_equal(unit.get("max_hp"), 40.0, "Improved Bowman uses source health")
	assert_equal(unit.get("attack_range"), 6.0, "Improved Bowman uses source range")
	assert_equal(unit.get("projectile_id"), 9, "Improved Bowman uses original arrow")
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(unit, state).get("asset_name"), "improved_bowman_%s" % state, "Improved Bowman %s presentation" % state)
	var enemy_stub := {"kind": "improved_bowman", "source_unit_id": 5, "team": 2, "facing": 0, "anim": 0.0}
	assert_equal(catalog.unit_frame_info(enemy_stub, "attack").get("asset_name"), "enemy_improved_bowman_attack", "enemy Improved Bowman uses recolored attack")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
