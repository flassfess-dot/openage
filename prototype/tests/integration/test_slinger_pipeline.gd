extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_slinger_vertical_slice(catalog)
	if failures.is_empty():
		print("I12-006 Slinger vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_slinger_vertical_slice(catalog) -> void:
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
	world.set_resource_amount(1, 2, 1000)
	var barracks: Dictionary = world.add_building(910, "barracks", Vector2(12.0, 12.0), 1)
	assert_true(not world.is_object_available(1, 347), "Slinger is locked in Stone Age")
	world.grant_technology(1, 101)
	assert_true(world.get_researched_technologies(1).has(123), "Tool Age completes hidden technology 123")
	assert_true(world.is_object_available(1, 347), "hidden technology unlocks Slinger")
	var food_before := world.get_resource_amount(1, 0)
	var stone_before := world.get_resource_amount(1, 2)
	var order: Variant = world.enqueue_unit_production(int(barracks["id"]), 1, "slinger")
	assert_true(order != null, "Barracks accepts Slinger production")
	assert_equal(world.get_resource_amount(1, 0), food_before - 40, "production reserves original food cost")
	assert_equal(world.get_resource_amount(1, 2), stone_before - 10, "production reserves original stone cost")
	world.update_production(25.0)
	var slingers: Array = world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "slinger")
	assert_equal(slingers.size(), 1, "original 24-second production completes")
	if slingers.is_empty():
		return
	var slinger: Dictionary = slingers[0]
	assert_equal(slinger.get("source_unit_id"), 347, "Slinger keeps source identity")
	assert_equal(slinger.get("max_hp"), 25.0, "Slinger uses source health")
	assert_equal(slinger.get("attack_range"), 4.0, "Slinger uses source range")
	assert_equal(slinger.get("projectile_id"), 361, "Slinger uses source stone projectile")
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(slinger, state).get("asset_name"), "slinger_%s" % state, "Slinger %s presentation" % state)
	var enemy_stub := {"kind": "slinger", "source_unit_id": 347, "team": 2, "facing": 0, "anim": 0.0}
	assert_equal(catalog.unit_frame_info(enemy_stub, "attack").get("asset_name"), "enemy_slinger_attack", "enemy Slinger uses recolored attack")

	var target: Dictionary = world.add_unit(2, "clubman", Vector2(slinger["pos"]) + Vector2(3.0, 0.0), false)
	world.assign_command_attack([slinger], int(target["id"]))
	for unused in range(40):
		world.advance(0.05, 1, 2)
		if not world.get_projectiles().is_empty():
			break
	assert_equal(world.get_projectiles().size(), 1, "attack release creates one stone projectile")
	if world.get_projectiles().is_empty():
		return
	var projectile: Dictionary = world.get_projectiles()[0]
	assert_equal(projectile.get("projectile_unit_id"), 361, "projectile keeps original stone source ID")
	assert_equal(catalog.projectile_frame_info(projectile).get("asset_name"), "sling_stone", "stone renders through source-aware projectile registry")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
