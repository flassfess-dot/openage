extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_complete_sword_line(catalog)
	if failures.is_empty():
		print("I12-005 Roman sword infantry line tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_complete_sword_line(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
	var barracks: Dictionary = world.add_building(900, "barracks", Vector2(12.0, 12.0), 1)
	assert_true(not world.is_object_available(1, 75), "Short Swordsman starts locked")
	complete_direct(world, 63)
	complete_direct(world, 102)
	complete_queued(world, barracks, 64, 51.0, "Short Sword")
	assert_true(world.is_object_available(1, 75), "Short Sword technology unlocks the line")
	var existing: Dictionary = world.add_unit(1, "swordsman", Vector2(8.0, 8.0), false)
	assert_source_and_asset(catalog, existing, 75, "short_swordsman", "Short Swordsman")
	assert_equal(existing.get("max_hp"), 60.0, "Short Swordsman uses source health")

	complete_queued(world, barracks, 65, 81.0, "Broad Sword")
	assert_source_and_asset(catalog, existing, 76, "broad_swordsman", "Broad Swordsman")
	assert_equal(existing.get("max_hp"), 70.0, "Broad Swordsman refreshes source health")

	complete_direct(world, 103)
	complete_queued(world, barracks, 66, 91.0, "Long Sword")
	assert_source_and_asset(catalog, existing, 77, "long_swordsman", "Long Swordsman")
	assert_equal(existing.get("max_hp"), 80.0, "Long Swordsman refreshes source health")

	complete_direct(world, 20)
	complete_queued(world, barracks, 77, 151.0, "Legion")
	assert_source_and_asset(catalog, existing, 282, "long_swordsman", "Legion")
	assert_equal(existing.get("max_hp"), 160.0, "Legion refreshes source health")
	var future: Dictionary = world.add_unit(1, "swordsman", Vector2(9.0, 8.0), false)
	assert_equal(future.get("source_unit_id"), 282, "future line members inherit Legion upgrade")
	var enemy := {"kind": "swordsman", "source_unit_id": 282, "team": 2, "facing": 0, "anim": 0.0}
	assert_equal(catalog.unit_frame_info(enemy, "death").get("asset_name"), "enemy_long_swordsman_death", "enemy Legion uses recolored death sequence")


func complete_direct(world, technology_id: int) -> void:
	world.apply_technology_commands(1, world.technology_system.complete_research(1, technology_id))


func complete_queued(world, barracks: Dictionary, technology_id: int, elapsed: float, name: String) -> void:
	var order: Variant = world.enqueue_research(int(barracks["id"]), 1, technology_id)
	assert_true(order != null, "%s enters the normal research queue" % name)
	world.update_production(elapsed)


func assert_source_and_asset(catalog, unit: Dictionary, source_id: int, asset_prefix: String, context: String) -> void:
	assert_equal(unit.get("source_unit_id"), source_id, "%s source identity" % context)
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(unit, state).get("asset_name"), "%s_%s" % [asset_prefix, state], "%s %s presentation" % [context, state])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
