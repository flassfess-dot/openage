extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_death_compacts_slots()
	test_add_and_remove_preserve_compatible_assignments()
	test_compatible_combat_keeps_group_and_new_formation_replaces_it()

	if failures.is_empty():
		print("F-011 formation membership tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_death_compacts_slots() -> void:
	var fixture := formed_group(7)
	var controller: GameController = fixture["controller"]
	var units: Array = fixture["units"]
	var group = controller.formation_groups[1]
	units[0]["hp"] = 0.0
	controller.reconcile_formation_groups()
	assert_equal(group.member_ids.size(), 6, "dead member removed")
	assert_equal(group.slots.size(), 6, "slots compact after death")
	assert_equal(group.assignments.size(), 6, "assignments compact after death")
	assert_equal(units[0]["formation_group_id"], -1, "dead member detached")
	var center := Vector2.ZERO
	for slot in group.slots:
		center += slot["local"]
	assert_vector_close(center / float(group.slots.size()), Vector2.ZERO, "compacted slots remain centered")


func test_add_and_remove_preserve_compatible_assignments() -> void:
	var fixture := formed_group(3)
	var controller: GameController = fixture["controller"]
	var world: SimulationWorld = fixture["world"]
	var units: Array = fixture["units"]
	var group = controller.formation_groups[1]
	var previous: Dictionary = group.assignments.duplicate(true)
	var added: Dictionary = world.add_unit(1, "clubman", Vector2(4, 8), false)
	var expanded_ids: Array[int] = []
	for unit in units:
		expanded_ids.append(int(unit["id"]))
	expanded_ids.append(int(added["id"]))
	controller.update_formation_group_members(1, expanded_ids)
	assert_equal(group.member_ids.size(), 4, "member can be added")
	for unit in units:
		assert_equal(group.assignments[int(unit["id"])], previous[int(unit["id"])], "existing member retains compatible slot")
	controller.update_formation_group_members(1, expanded_ids.slice(0, 3))
	assert_equal(group.member_ids.size(), 3, "member can be removed")
	assert_equal(added["formation_group_id"], -1, "removed member detaches cleanly")


func test_compatible_combat_keeps_group_and_new_formation_replaces_it() -> void:
	var fixture := formed_group(3)
	var controller: GameController = fixture["controller"]
	var world: SimulationWorld = fixture["world"]
	var units: Array = fixture["units"]
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(12, 12), false)
	world.assign_command_attack(units, enemy["id"])
	for unit in units:
		assert_equal(unit["formation_group_id"], 1, "combat preserves formation identity")
	var ids: Array[int] = []
	for unit in units:
		ids.append(int(unit["id"]))
	controller.enqueue_command(Commands.FormationMoveCommand.new(2, ids, Vector2(14, 10), FormationGeometry.WEDGE, Vector2(0, -1)))
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.formation_groups.has(1), false, "incompatible formation order retires old group")
	assert_equal(controller.formation_groups[2].formation_type, FormationGeometry.WEDGE, "new formation replaces old type")


func formed_group(count: int) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(32, 32))
	var units: Array = []
	var ids: Array[int] = []
	for index in range(count):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(5 + index % 4, 5 + index / 4), false)
		units.append(unit)
		ids.append(int(unit["id"]))
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(10, 10), FormationGeometry.BLOCK, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	return {"world": world, "controller": controller, "units": units}


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
