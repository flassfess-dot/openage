extends SceneTree

const FormationGroup := preload("res://scripts/formation_group.gd")
const FormationLifecycle := preload("res://scripts/formation_lifecycle.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_complete_lifecycle_and_slot_modes()
	if failures.is_empty():
		print("I7-001 formation lifecycle tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_complete_lifecycle_and_slot_modes() -> void:
	var group = FormationGroup.new(4, [1, 2], Vector2(8, 8), Vector2(1, 0), "LINE", 1.0)
	var members := [unit_at(1, group.slots[0]["world"] + Vector2(2, 0)), unit_at(2, group.slots[1]["world"] + Vector2(2, 0))]
	assert_equal(FormationLifecycle.evaluate(group, members)["current"], FormationLifecycle.TRAVEL, "assemble begins travel")
	members[0]["task"] = "attack"
	members[0]["target_id"] = 90
	assert_equal(FormationLifecycle.evaluate(group, members)["current"], FormationLifecycle.ENGAGED, "combat releases formation")
	assert_equal(group.slot_constraint_mode, "released", "engaged has no hard slot constraint")
	members[0]["task"] = "move"
	assert_equal(FormationLifecycle.evaluate(group, members)["current"], FormationLifecycle.REGROUP, "contact end enters regroup")
	for index in range(members.size()):
		members[index]["pos"] = group.slots[index]["world"]
		members[index]["task"] = "idle"
	assert_equal(FormationLifecycle.evaluate(group, members)["current"], FormationLifecycle.REFORM, "members at home enter reform")
	assert_equal(group.slot_constraint_mode, "hard", "reform briefly locks final geometry")
	FormationLifecycle.evaluate(group, members)
	assert_equal(FormationLifecycle.evaluate(group, members)["current"], FormationLifecycle.DEPLOY, "stable reform becomes deployed")
	assert_equal(FormationLifecycle.evaluate(group, [])["current"], FormationLifecycle.DISBAND, "empty group disbands")


func unit_at(id: int, position: Vector2) -> Dictionary:
	return {"id": id, "pos": position, "task": "move", "target_id": -1}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
