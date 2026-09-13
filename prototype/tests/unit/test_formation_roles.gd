extends SceneTree

const Assignment := preload("res://scripts/formation_assignment.gd")
const Roles := preload("res://scripts/formation_roles.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_role_classification()
	test_mixed_group_uses_front_center_back_and_wide_slots()

	if failures.is_empty():
		print("F-005 formation role tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_role_classification() -> void:
	assert_equal(Roles.role_for("clubman"), Roles.HEAVY_INFANTRY, "clubman role")
	assert_equal(Roles.role_for("archer"), Roles.RANGED, "archer role")
	assert_equal(Roles.role_for("priest"), Roles.PRIEST, "priest role")
	assert_equal(Roles.role_for("stone_thrower"), Roles.SIEGE, "siege role")
	assert_equal(Roles.role_for("villager"), Roles.CIVILIAN, "villager role")


func test_mixed_group_uses_front_center_back_and_wide_slots() -> void:
	var slots := [
		slot(0, Vector2(0, 2)), slot(1, Vector2(-2, 2)), slot(2, Vector2(2, 2)),
		slot(3, Vector2(0, 0)),
		slot(4, Vector2(-2, -2)), slot(5, Vector2(2, -2)), slot(6, Vector2(0, -2)),
	]
	var units := [
		unit(1, "clubman"), unit(2, "hoplite"), unit(3, "archer"),
		unit(4, "priest"), unit(5, "stone_thrower"), unit(6, "villager"), unit(7, "scout"),
	]
	var assignments := Assignment.assign(units, slots)
	var by_id: Dictionary = {}
	for candidate in slots:
		by_id[candidate["slot_id"]] = candidate["local"]
	assert_true(by_id[assignments[1]].y > by_id[assignments[3]].y, "heavy infantry stands ahead of ranged")
	assert_true(by_id[assignments[2]].y > by_id[assignments[3]].y, "second heavy infantry stands ahead of ranged")
	assert_equal(absf(by_id[assignments[4]].x), 0.0, "priest receives protected center")
	assert_equal(absf(by_id[assignments[5]].x), 2.0, "siege receives a wide slot")


func unit(id: int, kind: String) -> Dictionary:
	return {"id": id, "kind": kind, "pos": Vector2.ZERO, "footprint_radius": 0.3}


func slot(id: int, position: Vector2) -> Dictionary:
	return {"slot_id": id, "world": position, "local": position, "capacity_radius": 0.5}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
