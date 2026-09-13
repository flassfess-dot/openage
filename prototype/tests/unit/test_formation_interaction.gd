extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const FormationPreview := preload("res://scripts/formation_preview.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_short_move_preserves_front_and_drag_replaces_it()
	test_shape_change_keeps_composition_and_reforms_at_center()
	test_preview_matches_committed_geometry()

	if failures.is_empty():
		print("F-006/F-007 formation interaction tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_short_move_preserves_front_and_drag_replaces_it() -> void:
	var fixture := make_group(3)
	var world: SimulationWorld = fixture["world"]
	var controller: GameController = fixture["controller"]
	var ids: Array[int] = fixture["ids"]
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(10, 10), FormationGeometry.LINE, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	controller.enqueue_command(Commands.FormationMoveCommand.new(2, ids, Vector2(14, 14), FormationGeometry.LINE, Vector2.ZERO))
	controller.advance_frame(0.05, 1, 2)
	var short_group = controller.formation_groups[2]
	assert_vector_close(short_group.forward, Vector2(1, 0), "short RMB preserves front")

	controller.enqueue_command(Commands.FormationMoveCommand.new(3, ids, Vector2(16, 12), FormationGeometry.LINE, Vector2(0, -3)))
	controller.advance_frame(0.05, 1, 2)
	var dragged_group = controller.formation_groups[3]
	assert_vector_close(dragged_group.forward, Vector2(0, -1), "dragged RMB sets explicit front")
	assert_equal(world.get_units().size(), 3, "direction changes do not alter composition")


func test_shape_change_keeps_composition_and_reforms_at_center() -> void:
	var fixture := make_group(7)
	var world: SimulationWorld = fixture["world"]
	var controller: GameController = fixture["controller"]
	var ids: Array[int] = fixture["ids"]
	var expected_members := ids.duplicate()
	expected_members.sort()
	var fingerprints: Dictionary = {}
	var tick := 1
	for formation_type in FormationGeometry.ALL:
		var center := unit_center(world.get_units())
		controller.enqueue_command(Commands.FormationMoveCommand.new(tick, ids, center, formation_type, Vector2(0, -1)))
		controller.advance_frame(0.05, 1, 2)
		var group = controller.formation_groups[tick]
		assert_equal(group.member_ids, expected_members, "%s keeps members" % formation_type)
		assert_vector_close(group.anchor, center, "%s reforms around current center" % formation_type)
		assert_equal(group.state, "TRAVEL", "%s starts travelling immediately" % formation_type)
		fingerprints[slot_fingerprint(group.slots)] = true
		tick += 1
	assert_equal(fingerprints.size(), FormationGeometry.ALL.size(), "every formation has visibly distinct destinations")


func test_preview_matches_committed_geometry() -> void:
	var destination := Vector2(11.5, 8.25)
	var forward := Vector2(4, 3)
	var preview := FormationPreview.build(7, FormationGeometry.WEDGE, destination, forward)
	var local := FormationGeometry.local_slots(7, FormationGeometry.WEDGE, 1.0)
	var committed := FormationGeometry.world_slots(local, destination, forward)
	assert_equal(preview["slots"], committed, "ghost slots equal committed slots")
	assert_vector_close(preview["forward"], forward.normalized(), "ghost shows normalized world front")
	assert_equal(FormationPreview.build(0, FormationGeometry.LINE, destination, forward).is_empty(), true, "empty selection has no preview")
	assert_equal(FormationPreview.build(4, FormationGeometry.LINE, destination, Vector2.ZERO).is_empty(), true, "zero drag has no preview")


func make_group(count: int) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(32, 32))
	var ids: Array[int] = []
	for index in range(count):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(3 + index % 4, 4 + index / 4), false)
		ids.append(int(unit["id"]))
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	return {"world": world, "controller": controller, "ids": ids}


func unit_center(units: Array) -> Vector2:
	var center := Vector2.ZERO
	for unit in units:
		center += unit["pos"]
	return center / float(units.size())


func slot_fingerprint(slots: Array) -> String:
	var values: Array[String] = []
	for slot in slots:
		var local: Vector2 = slot["local"]
		values.append("%.3f:%.3f" % [local.x, local.y])
	return ",".join(values)


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
