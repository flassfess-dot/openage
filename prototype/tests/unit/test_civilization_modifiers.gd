extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_declarative_cost_bonus(catalog)
	test_class_modifier_and_tech_tree(catalog)
	test_starting_resources(catalog)
	if failures.is_empty():
		print("S-011 civilization modifier tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_declarative_cost_bonus(catalog) -> void:
	var world = original_world(catalog, 13)
	var raw_cost := int(catalog.object_catalog_data["objects"]["13:109"]["resources"]["cost"][0]["amount"])
	assert_equal(raw_cost, 200, "source Town Center wood cost")
	assert_equal(int(world.building_cost("town_center", 1)[1]), 170, "civilization bundle applies 15 percent building discount")


func test_class_modifier_and_tech_tree(catalog) -> void:
	var world = original_world(catalog, 16)
	var source_vision := float(catalog.object_catalog_data["objects"]["16:83"]["line_of_sight"])
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 5.0), false)
	assert_float(float(villager["components"]["vision"]["range"]), source_vision + 2.0, "class-scoped civilization LOS modifier")
	var civilization: Dictionary = world.civilization_record(1)
	assert_equal(int(civilization["tech_tree_id"]), 206, "civilization selects source effect bundle")
	var disabled_id := -1
	for command in catalog.object_catalog_data["effect_bundles"]["206"]["commands"]:
		if int(command.get("type_id", -1)) == 102:
			disabled_id = int(command.get("attr_d", -1))
			break
	assert_true(disabled_id >= 0, "source civilization bundle contains tech availability rules")
	assert_equal(world.technology_system.can_research(1, disabled_id), "technology_disabled", "tech tree toggle is enforced")


func test_starting_resources(catalog) -> void:
	var world = original_world(catalog, 13)
	world.reset_game()
	assert_equal(world.get_resource_amount(1, 0), 200, "civilization starting food")
	assert_equal(world.get_resource_amount(1, 1), 200, "civilization starting wood")
	assert_equal(world.get_resource_amount(1, 2), 150, "civilization starting stone")
	assert_equal(world.get_resource_amount(1, 3), 0, "civilization starting gold")


func original_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_team_civilization(1, civilization_id)
	return world


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
