extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_movement_faces_actual_displacement()
	test_attack_faces_target()
	test_formation_front_is_preserved_and_restored()

	if failures.is_empty():
		print("R-007 facing tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_movement_faces_actual_displacement() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var mover: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	world.add_unit(1, "clubman", Vector2(4.0, 4.3), false)
	world.assign_command_move([mover], Vector2(8.0, 4.0))
	var origin: Vector2 = mover["pos"]
	world.update_units(0.05, 1, 2)
	var displacement: Vector2 = mover["pos"] - origin
	assert_equal(mover["facing"], world.facing_for_vector(displacement), "movement uses actual velocity")
	assert_equal(mover["movement_facing"], world.facing_for_vector(displacement), "movement facing records actual displacement")
	assert_equal(mover["desired_facing"], world.facing_for_vector(mover["desired_velocity"]), "desired facing records desired velocity")
	assert_true(displacement.length_squared() > 0.0, "movement produces displacement")


func test_attack_faces_target() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(4.5, 5.5), false)
	world.assign_command_attack([attacker], target["id"])
	world.update_units(0.05, 1, 2)
	assert_equal(attacker["facing"], world.facing_for_vector(target["pos"] - attacker["pos"]), "attack faces target")
	assert_equal(attacker["action_facing"], world.facing_for_vector(target["pos"] - attacker["pos"]), "action facing remains owned by target-facing action")


func test_formation_front_is_preserved_and_restored() -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 3.0), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 4.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var forward := Vector2(1.0, 0.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, [first["id"], second["id"]], Vector2(6.0, 6.0), "LINE", forward))
	controller.advance_frame(0.05, 1, 2)
	var formation_facing := world.facing_for_vector(forward)
	assert_vector_close(first["formation_forward"], forward, "formation stores world-space front")
	assert_equal(first["formation_facing"], formation_facing, "formation stores common facing")

	first["pos"] = first["target"]
	world.update_units(0.05, 1, 2)
	assert_equal(first["anim_state"], AnimationController.IDLE, "arrived unit becomes idle")
	assert_equal(first["facing"], formation_facing, "standing unit faces formation front")

	var target: Dictionary = world.add_unit(2, "clubman", first["pos"] + Vector2(-0.4, 0.0), false)
	world.assign_command_attack([first], target["id"])
	world.update_units(0.05, 1, 2)
	assert_equal(first["facing"], world.facing_for_vector(target["pos"] - first["pos"]), "combat temporarily faces target")
	target["hp"] = 0.0
	world.update_units(0.05, 1, 2)
	assert_true(first["task"] in ["move", "idle"], "combat return begins when target dies")
	assert_equal(first["destination"], first["formation_home"], "combat return targets formation slot")
	for _step in range(240):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		if first["task"] == "idle":
			break
	assert_equal(first["task"], "idle", "unit finishes returning to formation (pos=%s target=%s destination=%s reason=%s)" % [first["pos"], first["target"], first["destination"], first["diagnostic_reason"]])
	assert_equal(first["facing"], formation_facing, "unit returns to formation front after combat")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
