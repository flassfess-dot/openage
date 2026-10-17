extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var world := World.new(Vector2i(16,16))
	var reference := World.new(Vector2i(16,16))
	var unit: Dictionary = world.add_unit(1,"villager",Vector2(3,3),false)
	reference.add_unit(1,"villager",Vector2(3,3),false)
	var controller := Controller.new(world)
	var expected := Controller.new(reference)
	controller.set_speed_multiplier(1.0)
	expected.set_speed_multiplier(1.0)
	var first := {"value":true}
	controller.set_before_fixed_tick(func(_tick):
		if first["value"]:
			first["value"] = false
			controller.enqueue_command(Commands.MoveCommand.new(1,[int(unit["id"])],Vector2(8,3)),true,1)
			OS.delay_usec(Controller.FRAME_SIMULATION_BUDGET_USEC + 3000)
		return {"ready":true,"can_defer":true}
	)
	expected.enqueue_command(Commands.MoveCommand.new(1,[int(unit["id"])],Vector2(8,3)),true,1)
	controller.advance_frame(0.05,1,2)
	check(controller.tick_index == 0 and controller.command_queue.size() == 1, "expensive preparation yields before consuming the queued command or tick")
	check(Vector2(unit["pos"]) == Vector2(3,3), "preparation cannot partially advance movement")
	var saved := Checkpoint.capture(world,controller,{}, {"size":Vector2i(16,16)})
	var restored := World.new(Vector2i(16,16))
	var resumed := Controller.new(restored)
	check(Checkpoint.restore(saved,restored,resumed), "a prepared but deferred boundary remains a complete checkpoint")
	controller.advance_frame(0.0,1,2)
	expected.advance_frame(0.05,1,2)
	resumed.advance_frame(0.05,1,2)
	check(controller.tick_index == 1 and resumed.tick_index == 1, "the next frame and restored boundary execute exactly one tick")
	var hash := Replay.new().world_state_hash(reference,1,expected)
	check(Replay.new().world_state_hash(world,1,controller) == hash, "deferring preparation preserves exact state and command order")
	check(Replay.new().world_state_hash(restored,1,resumed) == hash, "saved preparation reproduces the reference state")
	controller.set_before_fixed_tick(func(_tick):
		OS.delay_usec(Controller.FRAME_SIMULATION_BUDGET_USEC + 3000)
		return {"ready":true,"can_defer":true}
	)
	controller.advance_frame(0.05,1,2)
	var held: int = controller.tick_index
	controller.advance_frame(0.0,1,2)
	check(controller.tick_index == held + 1, "a repeatedly slow ready callback cannot starve the same tick")
	var commits := {"count":0}
	controller.set_before_fixed_tick(func(_tick):
		commits["count"] += 1
		OS.delay_usec(Controller.FRAME_SIMULATION_BUDGET_USEC + 3000)
		return {"ready":true}
	)
	var before_commit: int = controller.tick_index
	controller.advance_frame(0.05,1,2)
	check(controller.tick_index == before_commit + 1 and commits["count"] == 1, "a committing callback executes its target tick without a second readiness call")
	controller.advance_frame(0.0,1,2)
	check(commits["count"] == 1, "a committed callback is not repeated in the next rendered frame")
	for value in [world,reference,restored]: value.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Frame preparation budget: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
