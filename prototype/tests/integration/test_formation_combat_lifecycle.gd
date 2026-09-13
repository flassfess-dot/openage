extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_formation_releases_combat_and_reforms()
	if failures.is_empty():
		print("I7-002 formation/combat lifecycle integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_formation_releases_combat_and_reforms() -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var units: Array = []
	var ids: Array[int] = []
	for index in range(3):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.0 + index, 6.0), false)
		units.append(unit)
		ids.append(int(unit["id"]))
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(9.0, 6.0), false)
	world.add_unit(2, "clubman", Vector2(28.0, 28.0), false)
	var controller := GameController.new(world)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(7.0, 6.0), FormationGeometry.LINE, Vector2(1, 0)), true, 1)
	controller.advance_frame(0.05, 1, 2)
	var group = controller.formation_groups[1]
	controller.enqueue_command(Commands.AttackCommand.new(2, ids, int(target["id"])), true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(group.state, "ENGAGED", "attack command transitions group to engaged")
	for unit in units:
		assert_equal(unit["formation_slot_mode"], "released", "engaged member is free from travel slot")

	target["hp"] = 0.0
	controller.advance_frame(0.05, 1, 2)
	assert_equal(group.state, "REGROUP", "last target ending transitions group to regroup")
	for unit in units:
		unit["pos"] = unit["formation_home"]
		unit["task"] = "idle"
	controller.reconcile_formation_groups()
	assert_equal(group.state, "REFORM", "returned members enter explicit reform")
	controller.reconcile_formation_groups()
	controller.reconcile_formation_groups()
	assert_equal(group.state, "DEPLOY", "reformed group reaches deployed state")
	var states := controller.events_after().filter(func(event): return String(event["type"]) == "formation_state_changed").map(func(event): return String(event["payload"]["current_state"]))
	assert_true("ENGAGED" in states and "REGROUP" in states and "REFORM" in states and "DEPLOY" in states, "lifecycle transitions are observable events")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
