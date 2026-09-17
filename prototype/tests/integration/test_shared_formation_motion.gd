extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_shared_march_preserves_spacing_and_restores_individual_avoidance()
	if failures.is_empty():
		print("E6-005 shared formation motion integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_shared_march_preserves_spacing_and_restores_individual_avoidance() -> void:
	var world = SimulationWorld.new(Vector2i(40, 40))
	var local_slots := FormationGeometry.local_slots(4, FormationGeometry.BLOCK, 1.0)
	var starting_positions := FormationGeometry.world_slots(local_slots, Vector2(8, 8), Vector2.DOWN)
	var ids: Array[int] = []
	for position in starting_positions:
		var unit: Dictionary = world.add_unit(1, "clubman", position, false)
		unit["stance"] = "passive"
		unit["attack_autonomous"] = false
		unit["acquisition_range"] = 0.0
		ids.append(int(unit["id"]))
	var initial_distances := pair_distances(members_for_ids(world, ids))
	var outsider: Dictionary = world.add_unit(2, "clubman", Vector2(35.0, 35.0), false)
	outsider["stance"] = "passive"
	outsider["attack_autonomous"] = false
	outsider["acquisition_range"] = 0.0
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(24, 8), FormationGeometry.BLOCK, Vector2.DOWN))
	controller.advance_frame(0.05, 1, 2)
	for unit in members_for_ids(world, ids):
		assert_true(bool(unit["formation_shared_motion"]), "preformed group uses shared translation")
		assert_true(bool(unit["formation_shared_isolated"]), "isolated group skips member avoidance")
	for _tick in range(12):
		controller.advance_frame(0.05, 1, 2)
	var translated_distances := pair_distances(members_for_ids(world, ids))
	assert_equal(translated_distances.size(), initial_distances.size(), "shared march keeps pair count")
	for index in range(initial_distances.size()):
		assert_float_close(translated_distances[index], initial_distances[index], "shared march preserves pair distance %d" % index)
	assert_true(minimum_pair_distance(members_for_ids(world, ids)) > 0.65, "shared march keeps non-overlapping footprints")

	var center := unit_center(members_for_ids(world, ids))
	outsider["pos"] = center + Vector2(0.0, 1.2)
	outsider["previous_pos"] = outsider["pos"]
	world.rebuild_spatial_index(false)
	controller.advance_frame(0.05, 1, 2)
	for unit in world.get_units():
		if int(unit["formation_group_id"]) == 1:
			assert_true(not bool(unit["formation_shared_isolated"]), "nearby outsider restores external avoidance (tick=%d member=%s outsider=%s task=%s)" % [controller.tick_index, unit["pos"], outsider["pos"], unit["task"]])
	assert_true(minimum_pair_distance(world.get_units()) > 0.58, "external correction does not create overlap")

	var cached_member_id := ids[0]
	assert_true(world.open_movement_envelopes_by_id.has(cached_member_id), "open march has a route envelope before map change")
	world.navigation_grid.set_terrain(Vector2i(35, 35), "water")
	controller.advance_frame(0.05, 1, 2)
	assert_true(not world.open_movement_envelopes_by_id.has(cached_member_id), "navigation revision invalidates shared open envelope (tick=%d revision=%d task=%s)" % [controller.tick_index, world.navigation_grid.revision, world.find_unit(cached_member_id)["task"]])
	assert_true(float(outsider["hp"]) > 0.0, "external unit remains part of live collision scenario")


func pair_distances(units: Array) -> Array[float]:
	var result: Array[float] = []
	for left in range(units.size()):
		for right in range(left + 1, units.size()):
			result.append(Vector2(units[left]["pos"]).distance_to(Vector2(units[right]["pos"])))
	return result


func minimum_pair_distance(units: Array) -> float:
	var minimum := INF
	for distance in pair_distances(units):
		minimum = minf(minimum, distance)
	return minimum


func unit_center(units: Array) -> Vector2:
	var result := Vector2.ZERO
	for unit in units:
		result += Vector2(unit["pos"])
	return result / float(units.size())


func members_for_ids(world, ids: Array[int]) -> Array:
	var result: Array = []
	for entity_id in ids:
		result.append(world.find_unit(entity_id))
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_float_close(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
