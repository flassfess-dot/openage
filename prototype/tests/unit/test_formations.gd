extends SceneTree

const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const FormationGroup := preload("res://scripts/formation_group.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_aoe_layout_spacing_and_protection()
	test_group_contract()
	test_all_geometry_is_unique_centered_and_deterministic()
	test_world_space_basis_and_controller()

	if failures.is_empty():
		print("F-001/F-002/F-003 formation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_group_contract() -> void:
	var group = FormationGroup.new(7, [9, 3, 5], Vector2(12, 8), Vector2(3, 4), FormationGeometry.WEDGE, 1.2)
	assert_equal(group.group_id, 7, "group ID")
	assert_equal(group.member_ids, [3, 5, 9], "members sorted by EntityId")
	assert_vector_close(group.anchor, Vector2(12, 8), "anchor")
	assert_vector_close(group.forward, Vector2(0.6, 0.8), "normalized front")
	assert_equal(group.formation_type, FormationGeometry.WEDGE, "formation type")
	assert_equal(group.spacing, 1.2, "spacing")
	assert_equal(group.slots.size(), 3, "slot count")
	assert_equal(group.assignments.size(), 3, "assignment count")
	assert_equal(group.state, "ASSEMBLE", "initial lifecycle state")
	assert_true(group.route is Array, "route is stored")


func test_all_geometry_is_unique_centered_and_deterministic() -> void:
	for formation_type in FormationGeometry.ALL:
		for count in range(1, 25):
			var first := FormationGeometry.local_slots(count, formation_type, 1.0)
			var second := FormationGeometry.local_slots(count, formation_type, 1.0)
			assert_equal(first, second, "%s/%d deterministic" % [formation_type, count])
			assert_equal(first.size(), count, "%s/%d slot count" % [formation_type, count])
			var unique: Dictionary = {}
			var center := Vector2.ZERO
			for slot in first:
				unique["%.4f:%.4f" % [slot.x, slot.y]] = true
				center += slot
			assert_equal(unique.size(), count, "%s/%d unique" % [formation_type, count])
			assert_vector_close(center / float(count), Vector2.ZERO, "%s/%d centered" % [formation_type, count])


func test_world_space_basis_and_controller() -> void:
	var local: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0)]
	var east_front := FormationGeometry.world_slots(local, Vector2(10, 10), Vector2(1, 0))
	assert_vector_close(east_front[0], Vector2(10, 11), "world right basis first slot")
	assert_vector_close(east_front[1], Vector2(10, 9), "world right basis second slot")

	var world = SimulationWorld.new(Vector2i(24, 24))
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4, 4), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(5, 4), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, [second["id"], first["id"]], Vector2(10, 10), FormationGeometry.LINE, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.formation_groups.size(), 1, "controller stores formation group")
	var group = controller.formation_groups.values()[0]
	assert_equal(group.member_ids, [first["id"], second["id"]], "controller group members stable")
	assert_equal(first["formation_group_id"], group.group_id, "unit stores group ID")
	assert_equal(first["formation_slot_id"], group.assignments[first["id"]], "unit stores slot ID")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func test_aoe_layout_spacing_and_protection() -> void:
	var line := FormationGeometry.local_slots(20, FormationGeometry.LINE)
	var rows: Dictionary = {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point in line:
		rows[point.y] = true
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	assert_true(rows.size() > 1, "large line has several ranks")
	assert_true(maximum.x - minimum.x > maximum.y - minimum.y, "battle line is wider than it is deep")
	var stagger := FormationGeometry.local_slots(20, FormationGeometry.STAGGER)
	var minimum_gap := INF
	for i in range(stagger.size()):
		for j in range(i): minimum_gap = minf(minimum_gap, stagger[i].distance_to(stagger[j]))
	assert_true(minimum_gap >= 1.5, "staggered formation genuinely increases separation")
	var flank := FormationGeometry.local_slots(20, FormationGeometry.FLANK)
	assert_true(flank.all(func(point): return absf(point.x) >= 1.0), "split formation leaves a central gap")
	var ids: Array[int] = []
	var units: Array = []
	for i in range(20):
		ids.append(i + 1)
		units.append({"id": i + 1, "kind": "priest" if i == 0 else ("stone_thrower" if i == 1 else "clubman"), "pos": Vector2.ZERO, "footprint_radius": 0.3})
	var box := FormationGroup.new(1, ids, Vector2.ZERO, Vector2.DOWN, FormationGeometry.BLOCK)
	box.assign_units(units)
	for id in [1, 2]:
		var support: Vector2 = box.slot_for(id)["local"]
		assert_true(support.length() < 1.5, "box protects priests and siege in its inner ranks")
