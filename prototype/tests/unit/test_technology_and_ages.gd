extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_original_age_contract(catalog)
	test_starting_age_and_post_iron_contract(catalog)
	test_prerequisites_and_research_completion(catalog)
	test_automatic_hidden_technology(catalog)
	test_effects_availability_and_graphics(catalog)
	test_cancel_refund_and_command(catalog)
	if failures.is_empty():
		print("S-010 technology and age tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_automatic_hidden_technology(catalog) -> void:
	var world = original_world(catalog)
	assert_true(not world.is_object_available(1, 347), "Slinger starts disabled")
	world.grant_technology(1, 101)
	assert_true(world.get_researched_technologies(1).has(123), "Tool Age resolves zero-time hidden Slinger technology")
	assert_true(world.is_object_available(1, 347), "automatic technology applies its source unlock")
	assert_true(not world.is_object_available(1, 0), "Academy starts disabled")
	world.grant_technology(1, 67)
	world.grant_technology(1, 102)
	assert_true(world.get_researched_technologies(1).has(92), "generic hidden connector resolves Academy availability")
	assert_true(world.is_object_available(1, 0), "automatic building connector applies its source unlock")


func test_original_age_contract(catalog) -> void:
	var technologies: Dictionary = catalog.object_catalog_data.get("technologies", {})
	assert_equal(int(technologies["100"]["technology_type"]), 12, "Stone Age source technology")
	assert_equal(int(technologies["101"]["research_time"]), 120, "Tool Age research time")
	assert_equal(int(technologies["102"]["research_time"]), 140, "Bronze Age research time")
	assert_equal(int(technologies["103"]["research_time"]), 160, "Iron Age research time")
	assert_equal(int(technologies["103"]["resource_costs"][0]["amount"]), 1000, "Iron Age food cost")
	assert_equal(int(technologies["103"]["resource_costs"][1]["amount"]), 800, "Iron Age gold cost")


func test_starting_age_and_post_iron_contract(catalog) -> void:
	var bronze_world = original_world(catalog)
	bronze_world.set_starting_age(1, 102)
	assert_equal(bronze_world.get_current_age(1), 102, "Bronze starting age reaches Bronze")
	assert_true(bronze_world.get_researched_technologies(1).has(63), "Bronze start completes Tool Age Axeman technology")
	assert_true(not bronze_world.get_researched_technologies(1).has(4), "Bronze start does not complete Bronze Age Wheel technology")

	var post_iron_world = original_world(catalog)
	post_iron_world.apply_scenario_technology_nodes(1, [{"slot": 15, "node": "wonder", "kind": "building", "source_object_id": 276}])
	post_iron_world.set_starting_age(1, 103, true)
	assert_equal(post_iron_world.get_current_age(1), 103, "Post-Iron retains Iron as the authoritative age")
	assert_true(post_iron_world.get_researched_technologies(1).has(34), "Post-Iron completes an allowed Iron technology")
	assert_true(not post_iron_world.get_researched_technologies(1).has(37), "Post-Iron respects the Roman civilization technology tree")
	assert_true(not post_iron_world.is_object_available(1, 276), "classic scenario Wonder node remains disabled after Post-Iron effects")

	var town_center_world = original_world(catalog)
	town_center_world.apply_scenario_technology_nodes(1, [{"slot": 14, "node": "town_center", "kind": "building", "source_object_id": 109}])
	assert_true(not town_center_world.is_object_available(1, 109), "classic Town Center node disables the building")
	assert_equal(town_center_world.technology_system.can_research(1, 101, 109), "technology_disabled", "classic Town Center node disables its age research")


func test_prerequisites_and_research_completion(catalog) -> void:
	var world = original_world(catalog)
	var town_center: Dictionary = world.add_building(800, "town_center", Vector2(10.0, 10.0), 1)
	assert_equal(world.get_current_age(1), 100, "match starts in Stone Age")
	assert_true(world.get_researched_technologies(1).has(100), "initial age is researched")
	assert_equal(world.technology_system.can_research(1, 101, 109), "missing_prerequisites", "Tool Age requires original prerequisite connector")
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	assert_equal(world.technology_system.can_research(1, 101, 109), "", "two-of-four hidden connector unlocks Tool Age")
	world.set_resource_amount(1, 0, 1000)
	var research: Variant = world.enqueue_research(800, 1, 101)
	assert_true(research != null, "valid age research starts in an idle building")
	assert_equal(world.get_food(), 500, "research deducts exact original cost")
	assert_true(world.technology_system.is_researching(1, 101), "active research is tracked authoritatively")
	world.update_production(119.95)
	assert_equal(world.get_current_age(1), 100, "age does not complete early")
	assert_true(float(town_center["production_progress"]) > 0.99, "building exposes active research progress")
	world.update_production(0.05)
	assert_equal(world.get_current_age(1), 101, "Tool Age completes at original duration")
	assert_equal(world.last_completed_research_id, 101, "completion event stores technology id")
	assert_true(not world.technology_system.is_researching(1, 101), "completion clears active research state")


func test_effects_availability_and_graphics(catalog) -> void:
	var world = original_world(catalog)
	var town_center: Dictionary = world.add_building(801, "town_center", Vector2(10.0, 10.0), 1)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(4.0, 4.0), false)
	var original_range := float(archer["attack_range"])
	world.grant_technology(1, 32)
	assert_float(float(archer["attack_range"]), original_range + 1.0, "effect bundle modifies existing unit range")
	var future_archer: Dictionary = world.add_unit(1, "archer", Vector2(5.0, 4.0), false)
	assert_float(float(future_archer["attack_range"]), original_range + 1.0, "effect bundle modifies future unit range")
	assert_true(not world.is_object_available(1, 72), "disabled source object starts unavailable")
	world.grant_technology(1, 11)
	assert_true(world.is_object_available(1, 72), "unit-enable effect changes object availability")
	assert_equal(int(town_center["display_graphic_id"]), 598, "Stone Age Town Center graphic")
	world.grant_technology(1, 102)
	assert_equal(world.get_current_age(1), 102, "granting Bronze Age updates age state")
	assert_equal(int(town_center["source_unit_id"]), 71, "unit-upgrade effect changes Town Center source object")
	assert_equal(int(town_center["display_graphic_id"]), 885, "unit-upgrade effect changes Town Center graphic")


func test_cancel_refund_and_command(catalog) -> void:
	var world = original_world(catalog)
	var town_center: Dictionary = world.add_building(802, "town_center", Vector2(10.0, 10.0), 1)
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	world.set_resource_amount(1, 0, 700)
	var controller = GameController.new(world)
	controller.enqueue_command(Commands.ResearchCommand.new(0, [802], "101"))
	controller.process_commands()
	assert_true(world.technology_system.is_researching(1, 101), "ResearchCommand reaches authoritative research state")
	assert_equal(world.get_food(), 200, "command path deducts research cost")
	assert_true(world.cancel_production(802, 0), "active research can be cancelled")
	assert_equal(world.get_food(), 700, "cancelled research refunds full cost")
	assert_true(not world.technology_system.is_researching(1, 101), "cancel clears researching state")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
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
