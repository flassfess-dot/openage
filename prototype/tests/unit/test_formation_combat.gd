extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationCombat := preload("res://scripts/formation_combat.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_unique_melee_contact_slots()
	test_ranged_units_keep_distance_and_rear_line()
	test_group_returns_home_after_combat()

	if failures.is_empty():
		print("F-010 formation combat tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_unique_melee_contact_slots() -> void:
	var target := combat_target(Vector2(10, 10))
	var attackers: Array = []
	for index in range(12):
		attackers.append(combat_unit(index + 1, Vector2(5, 7 + index * 0.1), 0.0))
	FormationCombat.assign_slots(attackers, target)
	var unique: Dictionary = {}
	for unit in attackers:
		var destination: Vector2 = unit["combat_destination"]
		unique["%.4f:%.4f" % [destination.x, destination.y]] = true
		assert_equal(unit["combat_role"], "melee", "melee role")
	assert_equal(unique.size(), attackers.size(), "melee reserves different contact slots")


func test_ranged_units_keep_distance_and_rear_line() -> void:
	var target := combat_target(Vector2(10, 10))
	var archers := [
		combat_unit(1, Vector2(4, 9), 5.0),
		combat_unit(2, Vector2(4, 10), 5.0),
		combat_unit(3, Vector2(4, 11), 5.0),
	]
	FormationCombat.assign_slots(archers, target)
	var unique: Dictionary = {}
	for archer in archers:
		var destination: Vector2 = archer["combat_destination"]
		unique["%.4f:%.4f" % [destination.x, destination.y]] = true
		assert_equal(archer["combat_role"], "ranged", "ranged role")
		assert_true(destination.x < target["pos"].x, "ranged destination stays behind target-facing line")
		assert_true(destination.distance_to(target["pos"]) <= archer["attack_range"] + 0.0001, "ranged destination remains in range")
	assert_equal(unique.size(), archers.size(), "ranged positions are unique")


func test_group_returns_home_after_combat() -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(5, 5), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(6, 5), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(12, 5), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [first["id"], second["id"]]
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(7, 7), FormationGeometry.LINE, Vector2(1, 0)))
	controller.advance_frame(0.05, 1, 2)
	var first_home: Vector2 = first["formation_home"]
	var second_home: Vector2 = second["formation_home"]
	world.assign_command_attack([first, second], enemy["id"])
	assert_true(first["combat_destination"] != second["combat_destination"], "integration assigns unique melee contacts")
	enemy["hp"] = 0.0
	world.update_units(0.05, 1, 2)
	assert_equal(first["destination"], first_home, "first member returns to formation slot")
	assert_equal(second["destination"], second_home, "second member returns to formation slot")
	assert_equal(first["formation_forward"], Vector2(1, 0), "front survives combat")
	assert_true(first["task"] in ["move", "idle"], "return begins immediately")


func combat_unit(id: int, position: Vector2, attack_range: float) -> Dictionary:
	return {
		"id": id,
		"pos": position,
		"attack_range": attack_range,
		"footprint_radius": 0.3,
		"formation_forward": Vector2(1, 0),
	}


func combat_target(position: Vector2) -> Dictionary:
	return {"id": 90, "pos": position, "hp": 30.0, "footprint_radius": 0.3}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
