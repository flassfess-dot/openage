extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Replay := preload("res://scripts/replay_system.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var actual := fixture()
	var reference := fixture()
	var controller = actual["controller"]
	var expected = reference["controller"]
	var gate := {"ready": false, "attempts": 0}
	controller.set_before_fixed_tick(func(_next_tick: int) -> Dictionary:
		gate["attempts"] += 1
		return {"ready": gate["ready"]}
	)
	# Repeated barriers used to add 2.5 seconds of debt every cycle, eventually
	# forcing MAX_STEPS_PER_FRAME on every frame even after the worker finished.
	for cycle in range(40):
		gate["ready"] = false
		controller.advance_frame(0.16, 1, 2)
		var held_tick: int = controller.tick_index
		var held_debt: float = controller.accumulator_seconds
		var attempts: int = gate["attempts"]
		for waiting_frame in range(10):
			controller.advance_frame(0.25, 1, 2)
		check(controller.tick_index == held_tick, "waiting cannot execute authoritative ticks")
		check(is_equal_approx(controller.accumulator_seconds, held_debt), "worker waiting cannot accumulate catch-up debt")
		check(gate["attempts"] == attempts + 10, "each rendered frame polls the barrier once")
		gate["ready"] = true
		# The completion frame belongs to the same wait. Its wall time is not
		# simulated; the original pre-barrier debt is resumed in full.
		controller.advance_frame(0.25, 1, 2)
		expected.advance_frame(0.16, 1, 2)
		check(controller.tick_index == expected.tick_index, "resumption consumes exactly the preserved fixed ticks")
		check(is_equal_approx(controller.accumulator_seconds, expected.accumulator_seconds), "resumption preserves the interpolation remainder")
	check(Replay.new().world_state_hash(actual["world"], controller.tick_index, controller) == Replay.new().world_state_hash(reference["world"], expected.tick_index, expected), "long waits preserve authoritative world and command state")
	controller.advance_frame(0.05, 1, 2)
	expected.advance_frame(0.05, 1, 2)
	check(controller.tick_index == expected.tick_index, "normal frame time accrues again after resumption")

	gate["ready"] = false
	controller.advance_frame(0.1, 1, 2)
	check(controller.preparation_waiting, "fixture reaches another barrier")
	controller.reset_timing()
	check(not controller.preparation_waiting and controller.accumulator_seconds == 0.0, "reset clears the waiting clock")
	gate["ready"] = true
	controller.set_speed_multiplier(2.0)
	controller.advance_frame(0.025, 1, 2)
	check(controller.tick_index == 1, "reset retains the selected speed's fixed-step timing")
	gate["ready"] = false
	controller.advance_frame(0.1, 1, 2)
	check(controller.preparation_waiting, "fixture reaches the pre-replay barrier")
	var replay := Replay.new()
	replay.begin(1)
	check(controller.load_replay(replay.to_dictionary()), "an empty recording can replace deferred live planning")
	check(controller.replay_until_tick(controller.tick_index, 1, 2), "replay restores its current boundary")
	check(not controller.preparation_waiting and controller.accumulator_seconds == 0.0, "replay restoration clears the waiting clock")
	var restored_tick: int = controller.tick_index
	controller.advance_frame(0.025, 1, 2)
	check(controller.tick_index == restored_tick + 1, "replay playback advances after a deferred live tick")
	actual["world"].task_coordinator.shutdown()
	reference["world"].task_coordinator.shutdown()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("Preparation wait clock: 400 delayed frames, bounded debt, matching authoritative state")
	quit(0 if failures.is_empty() else 1)

func fixture() -> Dictionary:
	var world := World.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2, 2), false)
	world.add_unit(2, "clubman", Vector2(14, 14), false)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.MoveCommand.new(1, [int(unit["id"])], Vector2(8, 2)), true, 1)
	return {"world": world, "controller": controller}

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
