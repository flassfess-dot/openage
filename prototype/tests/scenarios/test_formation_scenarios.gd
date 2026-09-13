extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationAssignment := preload("res://scripts/formation_assignment.gd")
const FormationCorridor := preload("res://scripts/formation_corridor.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const FormationGroup := preload("res://scripts/formation_group.gd")
const GameController := preload("res://scripts/game_controller.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_required_group_sizes_and_rotations()
	test_mixed_group_changes_shape_while_moving()
	test_narrow_passage_combat_recovery_and_front_loss()

	if failures.is_empty():
		print("F-012 formation scenario matrix passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_required_group_sizes_and_rotations() -> void:
	var anchor := Vector2(20, 20)
	for count in [2, 3, 7, 20, 100]:
		var members: Array[int] = []
		var units: Array = []
		for index in range(count):
			members.append(index + 1)
			var kind := "archer" if index % 5 == 0 else ("villager" if index % 7 == 0 else "clubman")
			units.append({"id": index + 1, "kind": kind, "pos": Vector2(index % 10, index / 10), "footprint_radius": 0.3})
		for formation_type in FormationGeometry.ALL:
			var group = FormationGroup.new(count, members, anchor, Vector2(1, 0), formation_type, 1.0)
			group.assign_units(units)
			assert_equal(group.slots.size(), count, "%s size %d slot count" % [formation_type, count])
			assert_equal(group.assignments.size(), count, "%s size %d assignment count" % [formation_type, count])
	for degrees in [45.0, 90.0, 180.0]:
		var forward := Vector2(1, 0).rotated(deg_to_rad(degrees))
		var local := FormationGeometry.local_slots(7, FormationGeometry.WEDGE, 1.0)
		var first := FormationGeometry.world_slots(local, anchor, forward)
		var second := FormationGeometry.world_slots(local, anchor, forward)
		assert_equal(first, second, "%d degree turn is deterministic" % int(degrees))
		assert_vector_close(centroid(first), anchor, "%d degree turn keeps anchor" % int(degrees))


func test_mixed_group_changes_shape_while_moving() -> void:
	var world = SimulationWorld.new(Vector2i(40, 40))
	var ids: Array[int] = []
	for index in range(20):
		var kind := "archer" if index % 4 == 0 else ("villager" if index % 6 == 0 else "clubman")
		var unit: Dictionary = world.add_unit(1, kind, Vector2(5 + index % 5, 6 + index / 5), false)
		ids.append(int(unit["id"]))
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(26, 22), FormationGeometry.LINE, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.formation_groups[1].formation_type, FormationGeometry.LINE, "group starts moving as line")
	var center := centroid(world.get_units().map(func(unit): return unit["pos"]))
	controller.enqueue_command(Commands.FormationMoveCommand.new(2, ids, center, FormationGeometry.WEDGE, Vector2(0, -1)))
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.formation_groups.has(1), false, "shape change while moving retires old geometry")
	assert_equal(controller.formation_groups[2].formation_type, FormationGeometry.WEDGE, "shape changes while moving")
	assert_equal(controller.formation_groups[2].member_ids, ids, "mixed composition survives moving reform")


func test_narrow_passage_combat_recovery_and_front_loss() -> void:
	var grid = NavigationGrid.new(Vector2i(20, 13))
	grid.configure_terrain(func(_cell): return "grass")
	var wall: Array = []
	for y in range(13):
		if y != 6:
			wall.append(Vector2i(10, y))
	grid.occupy(wall, "building", 100)
	var finder = Pathfinder.new(grid)
	var corridor := FormationCorridor.plan(Vector2(3.5, 6.5), Vector2(16.5, 6.5), FormationGeometry.LINE, 7, 1.0, 0.3, finder, grid)
	assert_true(corridor["has_compression"], "scenario compresses in narrow passage")
	assert_equal(corridor["modes"][corridor["modes"].size() - 1], "preferred", "scenario restores after passage")

	var world = SimulationWorld.new(Vector2i(32, 32))
	var members: Array = []
	var ids: Array[int] = []
	for index in range(7):
		var unit: Dictionary = world.add_unit(1, "clubman" if index < 4 else "archer", Vector2(5 + index % 4, 6 + index / 4), false)
		if unit["kind"] == "archer":
			unit["attack_range"] = 5.0
		members.append(unit)
		ids.append(int(unit["id"]))
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(15, 10), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(11, 10), FormationGeometry.BLOCK, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	var group = controller.formation_groups[1]
	world.assign_command_attack(members, enemy["id"])
	for unit in members:
		assert_equal(unit["formation_group_id"], 1, "combat preserves group in scenario")
	enemy["hp"] = 0.0
	world.update_units(0.05, 1, 2)
	for unit in members:
		assert_equal(unit["destination"], unit["formation_home"], "survivor restores slot after combat")
	var front_unit: Dictionary = members[0]
	var maximum_front := -INF
	for unit in members:
		var slot_id := int(group.assignments[int(unit["id"])])
		var local: Vector2 = group.slots[slot_id]["local"]
		if local.y > maximum_front:
			maximum_front = local.y
			front_unit = unit
	front_unit["hp"] = 0.0
	controller.reconcile_formation_groups()
	assert_equal(group.member_ids.size(), 6, "front-rank death compacts group")
	assert_equal(group.formation_type, FormationGeometry.BLOCK, "loss preserves selected formation")
	assert_equal(group.forward, Vector2(1, 0), "loss preserves group front")


func centroid(points: Array) -> Vector2:
	var result := Vector2.ZERO
	for point in points:
		result += point
	return result / float(points.size())


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
