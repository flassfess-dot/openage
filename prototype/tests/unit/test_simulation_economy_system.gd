extends SceneTree

const SimulationEconomySystem := preload("res://scripts/simulation_economy_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_resources_costs_and_snapshot()
	test_population_reservation_lifecycle()
	if failures.is_empty():
		print("I1-005b simulation economy system tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_resources_costs_and_snapshot() -> void:
	var economy = SimulationEconomySystem.new()
	economy.reset(180, 120)
	var cost := {0: 50, 1: 20}
	assert_true(economy.can_afford(1, cost), "starting stockpile affords mixed cost")
	economy.spend(1, cost)
	assert_equal(economy.get_resource_amount(1, 0), 130, "spend removes food")
	assert_equal(economy.get_resource_amount(1, 1), 100, "spend removes wood")
	economy.refund(1, cost)
	assert_equal(economy.get_resource_amount(1, 0), 180, "refund restores food")
	economy.set_resource_amount(2, 3, -10)
	assert_equal(economy.get_resource_amount(2, 3), 0, "resource amounts are clamped")
	var snapshot: Dictionary = economy.snapshot()
	snapshot["resource_stockpiles"][1][0] = 1
	assert_equal(economy.get_resource_amount(1, 0), 180, "snapshot cannot mutate economy")


func test_population_reservation_lifecycle() -> void:
	var economy = SimulationEconomySystem.new()
	economy.reset()
	economy.set_population_cap(1, 2)
	economy.add_population(1, 1)
	assert_true(economy.can_reserve_population(1, 1), "free cap can be reserved")
	economy.reserve_population(1, 1)
	assert_true(not economy.can_reserve_population(1, 1), "living plus reserved population enforces cap")
	economy.release_reserved_population(1, 1)
	economy.add_population(1, -1)
	assert_equal(economy.get_population(1), 0, "population release cannot go negative")
	assert_equal(economy.get_reserved_population(1), 0, "reservation release cannot go negative")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
