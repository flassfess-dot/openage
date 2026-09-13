extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	test_tool_age_to_mixed_army(catalog)
	if failures.is_empty():
		print("I8-003 Tool Age progression scenario passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_tool_age_to_mixed_army(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var town_center: Dictionary = world.add_building(900, "town_center", Vector2(16.0, 16.0), 1)
	world.set_population_housing(1, 20)
	var workers: Array = []
	# This L2 scenario uses the original high-resource match preset. The separate
	# Stone Age scenario proves that no resources appear during live play without
	# gather/carry/deposit; here the smaller nodes keep the age test fast.
	world.set_resource_amount(1, 0, 600)
	world.set_resource_amount(1, 1, 350)
	var tree: Dictionary = world.add_resource("tree", Vector2(12.0, 10.0), 20)
	var berries: Dictionary = world.add_resource("berries", Vector2(12.0, 22.0), 20)
	for position in [Vector2(9.5, 9.5), Vector2(10.5, 8.5), Vector2(13.5, 8.5), Vector2(14.5, 9.5), Vector2(9.5, 22.5), Vector2(10.5, 23.5), Vector2(13.5, 23.5), Vector2(14.5, 22.5), Vector2(10.0, 20.5), Vector2(14.0, 20.5)]:
		workers.append(world.add_unit(1, "villager", position, false))
	var distant_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(30.0, 30.0), false)
	distant_enemy["stance"] = "passive"
	var controller := GameController.new(world)
	controller.set_speed_multiplier(1.0)

	var wood_ids: Array[int] = entity_ids(workers.slice(0, 4))
	var food_ids: Array[int] = entity_ids(workers.slice(4, 10))
	var gather_wood = Commands.GatherCommand.new(1, wood_ids, int(tree["id"]))
	var gather_food = Commands.GatherCommand.new(1, food_ids, int(berries["id"]))
	controller.enqueue_command(gather_wood, true, 1)
	controller.enqueue_command(gather_food, true, 1)
	advance_until(controller, func(): return int(tree.get("amount", 0)) == 0 and int(berries.get("amount", 0)) == 0 and workers.all(func(worker): return String(worker.get("task", "")) == "idle"), 2400)
	assert_true(command_accepted(controller, gather_wood), "wood gathering command is accepted")
	assert_true(command_accepted(controller, gather_food), "food gathering command is accepted")
	assert_equal(world.get_wood(), 370, "workers deposit all gathered wood (remaining=%d tasks=%s)" % [int(tree.get("amount", -1)), worker_diagnostics(workers.slice(0, 4))])
	assert_equal(world.get_food(), 620, "workers deposit all gathered food (remaining=%d tasks=%s)" % [int(berries.get("amount", -1)), worker_diagnostics(workers.slice(4, 10))])

	var barracks_cost: Dictionary = world.building_cost("barracks", 1)
	var granary_cost: Dictionary = world.building_cost("granary", 1)
	var build_barracks = Commands.BuildCommand.new(controller.tick_index + 1, entity_ids(workers.slice(0, 2)), "barracks", Vector2(9.0, 16.0))
	var build_granary = Commands.BuildCommand.new(controller.tick_index + 1, entity_ids(workers.slice(2, 4)), "granary", Vector2(23.0, 16.0))
	controller.enqueue_command(build_barracks, true, 1)
	controller.enqueue_command(build_granary, true, 1)
	advance_until(controller, func(): return completed_building(world, "barracks") != null and completed_building(world, "granary") != null, 1800)
	var barracks: Variant = completed_building(world, "barracks")
	var granary: Variant = completed_building(world, "granary")
	assert_true(command_accepted(controller, build_barracks) and barracks != null, "Barracks is built through command pipeline")
	assert_true(command_accepted(controller, build_granary) and granary != null, "Granary is built through command pipeline")
	assert_equal(world.get_wood(), 370 - int(barracks_cost.get(1, 0)) - int(granary_cost.get(1, 0)), "both construction costs are reserved exactly once")
	assert_true(world.get_researched_technologies(1).has(62), "Barracks grants hidden Clubman connector")
	assert_true(world.get_researched_technologies(1).has(10), "Granary grants hidden age connector")
	assert_equal(world.technology_system.can_research(1, 101, 109), "", "constructed prerequisites unlock Tool Age")

	var tool_age = Commands.ResearchCommand.new(controller.tick_index + 1, [int(town_center["id"])], "101")
	controller.enqueue_command(tool_age, true, 1)
	advance_until(controller, func(): return world.get_current_age(1) == 101, 2600)
	assert_true(command_accepted(controller, tool_age), "Tool Age research enters Town Center queue")
	assert_equal(world.get_current_age(1), 101, "Tool Age completes after original duration")

	var range_cost: Dictionary = world.building_cost("archery_range", 1)
	var build_range = Commands.BuildCommand.new(controller.tick_index + 1, entity_ids(workers.slice(4, 7)), "archery_range", Vector2(16.0, 24.0))
	controller.enqueue_command(build_range, true, 1)
	advance_until(controller, func(): return completed_building(world, "archery_range") != null, 1600)
	var archery_range: Variant = completed_building(world, "archery_range")
	assert_true(command_accepted(controller, build_range) and archery_range != null, "Tool Age Archery Range is built through commands")
	assert_true(world.is_object_available(1, 4), "completed Archery Range unlocks Bowman")
	assert_equal(world.get_wood(), 370 - int(barracks_cost.get(1, 0)) - int(granary_cost.get(1, 0)) - int(range_cost.get(1, 0)), "Archery Range uses source cost with civilization modifiers")

	if barracks == null or archery_range == null:
		return
	var train_clubman = Commands.TrainCommand.new(controller.tick_index + 1, [int(barracks["id"])], "clubman", 1, Vector2(14.0, 16.0))
	var train_archer = Commands.TrainCommand.new(controller.tick_index + 1, [int(archery_range["id"])], "archer", 1, Vector2(17.0, 20.0))
	controller.enqueue_command(train_clubman, true, 1)
	controller.enqueue_command(train_archer, true, 1)
	advance_until(controller, func(): return count_kind(world, "clubman") == 1 and count_kind(world, "archer") == 1, 800)
	assert_true(command_accepted(controller, train_clubman), "Clubman production command is accepted at Barracks")
	assert_true(command_accepted(controller, train_archer), "Bowman production command is accepted at Archery Range")
	assert_equal(count_kind(world, "clubman"), 1, "mixed army contains Clubman")
	assert_equal(count_kind(world, "archer"), 1, "mixed army contains Bowman")

	var events := controller.events_after()
	assert_true(events.any(func(event): return String(event.get("type", "")) == "research_queued"), "research queue event is observable")
	assert_true(events.any(func(event): return String(event.get("type", "")) == "research_complete" and int(event.get("payload", {}).get("technology_id", -1)) == 101), "Tool Age completion event is observable")
	assert_equal(events.filter(func(event): return String(event.get("type", "")) == "unit_produced").size(), 2, "both military completions are observable")


func advance_until(controller, predicate: Callable, maximum_ticks: int) -> void:
	for _tick in range(maximum_ticks):
		controller.advance_frame(0.05, 1, 2)
		if bool(predicate.call()):
			return


func completed_building(world, kind: String) -> Variant:
	var candidates: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == kind and String(building.get("state", "")) == "complete")
	return candidates[0] if not candidates.is_empty() else null


func count_kind(world, kind: String) -> int:
	return world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == kind).size()


func entity_ids(entities: Array) -> Array[int]:
	var result: Array[int] = []
	for entity in entities:
		result.append(int(entity.get("id", -1)))
	return result


func worker_diagnostics(workers: Array) -> String:
	var parts: Array[String] = []
	for worker in workers:
		parts.append("%d:%s/%s/%s/%.1f@%s->%s" % [int(worker.get("id", -1)), String(worker.get("task", "")), String(worker.get("gather_stage", "")), String(worker.get("diagnostic_reason", "")), float(worker.get("carried_amount", 0.0)), worker.get("pos", Vector2.ZERO), worker.get("dropoff_position", Vector2.ZERO)])
	return ",".join(parts)


func command_accepted(controller, command) -> bool:
	return bool(controller.get_command_result(int(command.sequence_id)).get("accepted", false))


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
