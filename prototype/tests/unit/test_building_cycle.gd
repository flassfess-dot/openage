extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	test_original_building_contract(catalog)
	test_placement_reservation_and_cancel(catalog)
	test_mixed_selection_assigns_every_worker(catalog)
	test_multiple_builders_and_repair(catalog)

	if failures.is_empty():
		print("S-008 building and repair tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_building_contract(catalog) -> void:
	var town_center: Dictionary = catalog.object_catalog_data.get("objects", {}).get("13:109", {})
	assert_equal(int(town_center.get("production", {}).get("creation_time", 0)), 60, "original Town Center construction time")
	assert_equal(int(town_center.get("resources", {}).get("cost", [])[0].get("amount", 0)), 200, "original Town Center wood cost")
	assert_equal(catalog.town_center_construction_textures.size(), 4, "original construction stages loaded")


func test_placement_reservation_and_cancel(catalog) -> void:
	var world = original_world(catalog)
	world.wood = 500
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 7.0), false)
	var foundation: Variant = world.place_foundation(1, "town_center", Vector2(7.0, 7.0), [worker])
	assert_true(foundation != null, "explored flat free terrain accepts foundation (%s)" % world.last_build_failure)
	if foundation == null:
		return
	assert_equal(world.get_wood(), 330, "civilization-adjusted construction cost is reserved at placement")
	assert_equal(foundation["state"], "foundation", "placed building starts as foundation")
	assert_equal(foundation["construction_stage"], 0, "foundation starts at first stage")
	assert_true(not world.navigation_grid.is_walkable(Vector2i(7, 7)), "foundation reserves navigation footprint immediately")
	assert_equal(worker["task"], "build", "assigned worker receives build order")
	assert_true(worker["building_approach_slot"] is Vector2, "builder receives approach slot")
	var blocked: Variant = world.place_foundation(1, "town_center", Vector2(7.0, 7.0))
	assert_equal(blocked, null, "overlapping placement is rejected")
	assert_equal(world.last_build_failure, "blocked_or_sloped", "invalid placement exposes stable reason")
	assert_true(world.cancel_foundation(int(foundation["id"])), "foundation can be cancelled")
	assert_equal(world.get_wood(), 500, "cancel refunds reserved construction resources")
	assert_equal(world.find_building(int(foundation["id"])), null, "cancel removes foundation")
	assert_equal(worker["building_approach_slot"], null, "cancel releases builder slot")


func test_mixed_selection_assigns_every_worker(catalog) -> void:
	var world = original_world(catalog)
	world.wood = 500
	var first: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 6.5), false)
	var soldier: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 5.0), false)
	var second: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 7.5), false)
	var controller = GameController.new(world)
	var command = Commands.BuildCommand.new(0, [int(first["id"]), int(soldier["id"]), int(second["id"])], "town_center", Vector2(7.0, 7.0))
	controller.enqueue_command(command, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "mixed selection accepts construction through its workers")
	assert_equal(first["task"], "build", "first worker in a mixed selection joins construction")
	assert_equal(second["task"], "build", "every other worker in a mixed selection joins construction")
	assert_equal(soldier["task"], "idle", "non-worker in a mixed selection is not assigned worker labor")


func test_multiple_builders_and_repair(catalog) -> void:
	var world = original_world(catalog)
	world.wood = 500
	var first: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 6.5), false)
	var second: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 7.5), false)
	var foundation: Variant = world.place_foundation(1, "town_center", Vector2(7.0, 7.0), [first, second])
	assert_true(foundation != null, "foundation created for multiple builders (%s)" % world.last_build_failure)
	if foundation == null:
		return
	assert_true(Vector2(first["building_approach_slot"]).distance_squared_to(second["building_approach_slot"]) >= 0.09, "builders receive unique approach slots")
	assert_true(Vector2(first["building_approach_slot"]).x < Vector2(foundation["pos"]).x, "first builder receives a nearest-side slot instead of walking around the foundation")
	assert_true(Vector2(second["building_approach_slot"]).x < Vector2(foundation["pos"]).x, "joint builder also receives a nearest-side free slot")
	assert_true(not first.get("path", []).is_empty() and not second.get("path", []).is_empty(), "joint construction routes are ready when the order is accepted")
	first["pos"] = first["building_approach_slot"]
	second["pos"] = second["building_approach_slot"]
	for unused in range(20):
		world.update_units(0.05, 1, 2)
	assert_float(float(foundation["construction_progress"]), 2.0 / 60.0, "two builders contribute additive original work rates")
	assert_equal(foundation["construction_stage"], 0, "early progress remains in first visual stage")
	assert_equal(first["anim_state"], AnimationController.BUILD, "builder uses build animation state")

	foundation["construction_required"] = 1.0
	foundation["construction_progress"] = 0.95
	for unused in range(4):
		world.update_units(0.05, 1, 2)
		if foundation["state"] == "complete":
			break
	assert_equal(foundation["state"], "complete", "construction reaches completed building")
	assert_equal(foundation["construction_stage"], 3, "completion selects final stage")
	assert_float(float(foundation["hp"]), float(foundation["max_hp"]), "completed building reaches full health")
	assert_equal(first["task"], "idle", "all builders finish on completion")
	assert_equal(second["task"], "idle", "second builder also finishes")

	foundation["hp"] = float(foundation["max_hp"]) - 20.0
	world.assign_command_repair([first, second], int(foundation["id"]))
	first["pos"] = first["building_approach_slot"]
	second["pos"] = second["building_approach_slot"]
	var wood_before_repair: int = world.get_wood()
	world.update_units(0.1, 1, 2)
	assert_float(float(foundation["hp"]), float(foundation["max_hp"]) - 18.0, "two repairers contribute their work in the same tick")
	assert_equal(first["anim_state"], AnimationController.REPAIR, "repair uses work animation state")
	for unused in range(100):
		world.update_units(0.1, 1, 2)
		if first["task"] == "idle":
			break
	assert_float(float(foundation["hp"]), float(foundation["max_hp"]), "repair stops exactly at maximum health")
	assert_true(world.get_wood() < wood_before_repair, "repair consumes wood")
	assert_equal(first["building_approach_slot"], null, "repair completion releases approach slot")
	assert_equal(second["building_approach_slot"], null, "repair completion releases every worker approach slot")


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
