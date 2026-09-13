extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_academy_infantry_line(catalog)
	if failures.is_empty():
		print("I12-009 Academy infantry vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_academy_infantry_line(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)

	assert_true(not world.is_object_available(1, 0), "Academy starts behind its original hidden connector")
	world.grant_technology(1, 67)
	world.grant_technology(1, 102)
	assert_true(world.get_researched_technologies(1).has(92), "Bronze Age prerequisites automatically resolve Academy connector 92")
	assert_true(world.is_object_available(1, 0), "Academy becomes available through original technology effect")

	var academy: Dictionary = world.add_building(930, "academy", Vector2(14.0, 14.0), 1)
	assert_equal(academy.get("source_unit_id"), 0, "Academy keeps source identity")
	assert_equal(academy.get("max_hp"), 350.0, "Academy uses original health")
	assert_equal(catalog.building_frame_info(academy).get("graphic_id"), 855, "Academy resolves original Roman graphic")
	assert_true(catalog.building_frame_info(academy).get("texture") != null, "Academy graphic is loadable")
	assert_true(world.get_researched_technologies(1).has(72), "completed Academy applies original hidden Hoplite unlock")
	assert_true(world.is_object_available(1, 93), "Hoplite becomes available after Academy completion")
	var option_kinds: Array = world.get_unit_production_options(int(academy["id"]), 1).map(func(option): return String(option.get("kind", "")))
	assert_true(option_kinds.has("hoplite"), "Academy production palette exposes Hoplite")

	var food_before := world.get_resource_amount(1, 0)
	var gold_before := world.get_resource_amount(1, 3)
	var order: Variant = world.enqueue_unit_production(int(academy["id"]), 1, "hoplite")
	assert_true(order != null, "Hoplite enters normal Academy production queue")
	assert_equal(world.get_resource_amount(1, 0), food_before - 60, "Hoplite reserves original food cost")
	assert_equal(world.get_resource_amount(1, 3), gold_before - 40, "Hoplite reserves original gold cost")
	world.update_production(36.0)
	var produced: Array = world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "hoplite")
	assert_equal(produced.size(), 1, "Academy completes Hoplite after original creation time")
	if produced.is_empty():
		return
	var existing: Dictionary = produced[0]
	assert_unit_variant(catalog, existing, 93, "hoplite", 120.0, 17.0, "Hoplite")

	world.grant_technology(1, 103)
	complete_queued(world, academy, 73, 90.0, "Phalanx")
	assert_unit_variant(catalog, existing, 94, "phalanx", 120.0, 20.0, "Phalanx")

	world.grant_technology(1, 113)
	complete_queued(world, academy, 79, 150.0, "Centurion")
	assert_unit_variant(catalog, existing, 291, "phalanx", 160.0, 30.0, "Centurion")
	var future: Dictionary = world.add_unit(1, "hoplite", Vector2(9.0, 9.0), false)
	assert_equal(future.get("source_unit_id"), 291, "future Academy infantry inherits Centurion upgrade")
	var enemy := {"kind": "hoplite", "source_unit_id": 291, "team": 2, "facing": 0, "anim": 0.0}
	assert_equal(catalog.unit_frame_info(enemy, "attack").get("asset_name"), "enemy_phalanx_attack", "enemy Centurion uses recolored source attack")


func complete_queued(world, academy: Dictionary, technology_id: int, elapsed: float, name: String) -> void:
	var research: Variant = world.enqueue_research(int(academy["id"]), 1, technology_id)
	assert_true(research != null, "%s enters the normal Academy research queue" % name)
	if research != null:
		world.update_production(elapsed)


func assert_unit_variant(catalog, unit: Dictionary, source_id: int, asset_prefix: String, hp: float, damage: float, context: String) -> void:
	assert_equal(unit.get("source_unit_id"), source_id, "%s source identity" % context)
	assert_equal(unit.get("max_hp"), hp, "%s source health" % context)
	assert_equal(unit.get("attack_damage"), damage, "%s source attack" % context)
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(unit, state).get("asset_name"), "%s_%s" % [asset_prefix, state], "%s %s presentation" % [context, state])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
