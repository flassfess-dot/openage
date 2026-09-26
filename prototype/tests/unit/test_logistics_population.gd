extends SceneTree

const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_existing_new_dying_and_converted_units(catalog)
	test_training_uses_half_population_points(catalog)
	test_ai_housing_uses_exact_points()
	if failures.is_empty():
		print("P01 Logistics fixed-point population tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_existing_new_dying_and_converted_units(catalog) -> void:
	var world = original_world(catalog)
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4, 4), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(6, 4), false)
	assert_equal(world.get_population_points(1), 4, "two ordinary Clubmen use four half-population points")
	world.grant_technology(1, 121)
	assert_equal(int(first.get("population_points_cost", -1)), 1, "Logistics reprices the first existing Clubman")
	assert_equal(int(second.get("population_points_cost", -1)), 1, "Logistics reprices the second existing Clubman")
	assert_equal(world.get_population_points(1), 2, "existing Clubmen release exactly two points")
	assert_equal(world.get_population(1), 1, "public population remains a whole number")
	var third: Dictionary = world.add_unit(1, "clubman", Vector2(8, 4), false)
	assert_equal(int(third.get("population_points_cost", -1)), 1, "new Clubman inherits Logistics")
	assert_equal(world.get_population_points(1), 3, "new Clubman adds one point")
	world.begin_death(first)
	assert_equal(world.get_population_points(1), 2, "dying discounted Clubman releases one point")
	world.begin_death(first)
	assert_equal(world.get_population_points(1), 2, "repeated death start does not release population twice")
	assert_true(world.transfer_entity_ownership(second, 2), "discounted Clubman converts to an opponent")
	assert_equal(world.get_population_points(1), 1, "conversion removes old owner's discounted cost")
	assert_equal(world.get_population_points(2), 2, "new owner without Logistics pays full cost")
	world.grant_technology(2, 121)
	assert_equal(world.get_population_points(2), 1, "new owner's Logistics reprices an already converted unit")
	assert_equal(int(second.get("population_points_cost", -1)), 1, "converted unit stores its new authoritative cost")


func test_training_uses_half_population_points(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	var building: Dictionary = world.add_building(720, "town_center", Vector2(10, 10), 1)
	world.set_population_cap(1, 1)
	world.grant_technology(1, 121)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "first discounted unit queues")
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "second discounted unit queues")
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "third discounted unit may queue beyond the cap")
	world.update_production(26.0)
	world.update_production(26.0)
	assert_equal(world.get_population_points(1), 2, "two discounted units exactly fill one population slot")
	assert_equal(world.get_units().size(), 2, "two discounted units complete under a cap of one")
	world.update_production(26.0)
	assert_equal(world.get_units().size(), 2, "third discounted unit waits at the fixed-point cap")
	assert_equal(String(building["production_queue"][0].get("status", "")), "blocked_population", "third unit reports population blocking")


func test_ai_housing_uses_exact_points() -> void:
	var player_state := {"population": 1, "population_points": 1, "population_reserved": 0, "population_cap": 1, "population_limit": 75}
	assert_true(not EconomicPlanner._needs_housing(player_state, 0), "half-used final slot does not trigger premature housing")
	assert_true(EconomicPlanner._needs_housing(player_state, 0, true), "blocked production triggers housing despite spare fractional space")
	player_state["population_points"] = 2
	assert_true(EconomicPlanner._needs_housing(player_state, 0), "full fixed-point cap triggers housing")
	player_state["population_limit"] = 1
	assert_true(not EconomicPlanner._needs_housing(player_state, 0, true), "global match limit prevents a futile House order")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
