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
	test_selection_preview_shares_one_heading()

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
	controller.enqueue_command(Commands.FormationMoveCommand.new(2, ids, Vector2(8, 8), FormationGeometry.LINE, Vector2.ZERO))
	controller.advance_frame(0.05, 1, 2)
	var short_group = controller.formation_groups[1]
	assert_vector_close(short_group.forward, Vector2(1, 0), "short RMB preserves front")

	controller.enqueue_command(Commands.FormationMoveCommand.new(3, ids, Vector2(16, 12), FormationGeometry.LINE, Vector2(0, -3)))
	controller.advance_frame(0.05, 1, 2)
	var dragged_group = controller.formation_groups[1]
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
		var group = controller.formation_groups[1]
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


func test_selection_preview_shares_one_heading() -> void:
	var destination := Vector2(20, 24)
	var forward := Vector2(3, 4)
	var members: Array = []
	for index in range(3):
		members.append({"id": index + 1, "pos": Vector2(8, 8 + index), "formation_group_id": index + 1, "preferred_formation": FormationGeometry.LINE})
	var preview := FormationPreview.build_selection(members, {}, destination, forward)
	assert_equal(preview["slots"].size(), 3, "three singleton groups still preview exactly three positions")
	for index in range(3):
		assert_vector_close(preview["slots"][index], destination + Vector2(0, index - 1), "individual group offsets are preserved")
	assert_equal(preview["heading"].size(), 4, "entire selection has one arrow shaft and two head points")
	assert_vector_close(preview["heading"][0], destination, "common heading originates at the selection destination")
	assert_vector_close(preview["heading"][1], destination + forward.normalized() * 1.6, "common heading follows the drag")
	for member in members: member["formation_group_id"] = 1
	preview = FormationPreview.build_selection(members, {}, destination, forward)
	assert_equal(preview["slots"], FormationPreview.build(3, FormationGeometry.LINE, destination, forward)["slots"], "one group previews its own shape")
	var extra := {"id": 4, "pos": Vector2(10, 8), "formation_group_id": 2, "preferred_formation": FormationGeometry.COLUMN}
	members.append(extra)
	members.append({"id": 5, "pos": Vector2(10, 10), "formation_group_id": 2, "preferred_formation": FormationGeometry.COLUMN})
	preview = FormationPreview.build_selection(members, {}, destination, forward)
	var expected: Array = FormationPreview.build(3, FormationGeometry.LINE, destination + Vector2(-0.8, 0), forward)["slots"].duplicate()
	expected.append_array(FormationPreview.build(2, FormationGeometry.COLUMN, destination + Vector2(1.2, 0), forward)["slots"])
	assert_equal(preview["slots"].size(), 5, "mixed selection keeps all members")
	for index in range(expected.size()): assert_vector_close(preview["slots"][index], expected[index], "mixed selection preserves each group's shape")
	assert_equal(preview["heading"].size(), 4, "mixed shapes still have one common direction arrow")
	assert_equal(FormationPreview.build_selection([], {}, destination, forward).is_empty(), true, "empty selection has no shared preview")
	assert_equal(FormationPreview.build_selection(members, {}, destination, Vector2.ZERO).is_empty(), true, "zero drag has no shared preview")
