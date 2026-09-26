extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var ordinary = configured_world(catalog, 13)
	var palmyran = configured_world(catalog, 15)
	assert_near(ordinary.technology_system.tribute_tax(1), 0.25, "ordinary source tribute tax")
	assert_near(palmyran.technology_system.tribute_tax(1), 0.0, "Palmyran source tribute exemption")
	assert_near(ordinary.technology_system.trade_profit_multiplier(1), 1.0, "ordinary distance profit multiplier")
	assert_near(palmyran.technology_system.trade_profit_multiplier(1), 2.0, "Palmyran trade profit doubles after distance policy")
	var ordinary_worker: Dictionary = ordinary.add_unit(1, "villager", Vector2(7, 7), false)
	var palmyran_worker: Dictionary = palmyran.add_unit(1, "villager", Vector2(7, 7), false)
	assert_equal(int(palmyran.unit_resource_cost("villager", 1).get(0, -1)), 75, "Palmyran villager costs 75 food")
	# The imported +0.2 work-rate commands target task-source IDs (including
	# Lumberjack 123), not the idle Villager's source ID 83.
	var ordinary_lumber: Dictionary = ordinary.worker_role_system.profile_for_resource_type(ordinary_worker, 1)
	var palmyran_lumber: Dictionary = palmyran.worker_role_system.profile_for_resource_type(palmyran_worker, 1)
	assert_equal(int(palmyran_lumber.get("role_source_unit_id", -1)), 123, "wood-gathering profile resolves Lumberjack source ID")
	ordinary.worker_role_system.apply(ordinary_worker, ordinary_lumber)
	palmyran.worker_role_system.apply(palmyran_worker, palmyran_lumber)
	assert_true(float(palmyran_worker.get("components", {}).get("worker", {}).get("work_rate", 0.0)) > float(ordinary_worker.get("components", {}).get("worker", {}).get("work_rate", 0.0)), "Palmyran Lumberjack source modifier changes runtime work rate")
	palmyran.set_alliance(1, 2, true)
	palmyran.set_resource_amount(1, 0, 40)
	palmyran.set_resource_amount(2, 0, 0)
	assert_equal(palmyran.pay_tribute(1, 2, 0, 40), "", "Palmyran tribute is accepted")
	assert_equal(palmyran.get_resource_amount(2, 0), 40, "Palmyran recipient receives the entire tribute")
	finish()


func configured_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, context: String) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P05 Palmyran economy bonuses passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
