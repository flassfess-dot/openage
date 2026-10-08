extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Queue := preload("res://scripts/ai_decision_queue.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Ai := preload("res://scripts/ai_player.gd")
var failures: Array[String] = []
var captures := 0

class BlockedPlanner extends RefCounted:
	var release := Semaphore.new()
	func run(input: Dictionary) -> Dictionary:
		release.wait()
		return RoRAiPlanningTask.run(input)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := World.new(Vector2i(12, 12))
	var controller := Controller.new(world)
	controller.tick_index = 2
	controller.set_speed_multiplier(1.0)
	var coordinator := Coordinator.new()
	var ai := Ai.new({"team": 2})
	var queue := Queue.new()
	queue.begin([ai], 2, 10, Callable(self, "capture"))
	var input := Data.seal(capture(ai, 10))
	var blocked := BlockedPlanner.new()
	var request := coordinator.submit("ai_planning", input, blocked.run, 2, 10, {"team": 2}, true)
	check(request >= 0, "controlled asynchronous planner dispatches")
	if request < 0:
		coordinator.shutdown()
		finish()
		return
	queue.records[0]["input"] = input
	queue.records[0]["submitted"] = true
	queue.records[0]["request_id"] = request
	controller.set_before_fixed_tick(func(next_tick: int) -> Dictionary:
		return queue.gate(queue.poll(coordinator, controller.tick_index, Engine.get_process_frames()), next_tick)
	)
	controller.advance_frame(0.25, 1, 2)
	controller.advance_frame(0.15, 1, 2)
	check(controller.tick_index == 9, "seven simulation ticks advance while the worker is blocked")
	check(not queue.gate(queue.poll(coordinator, 9, 100), 10)["ready"], "only the predetermined deadline waits for unfinished work")
	check(is_equal_approx(controller.accumulator_seconds, 0.05), "deadline preserves unconsumed simulation time")
	check(queue.records[0]["input"]["snapshot"]["tick"] == 2 and ai.last_economic_tick < 0, "world progress cannot change captured facts or publish AI state")
	blocked.release.post()
	while not coordinator.is_ready(request):
		await process_frame
	var status := queue.poll(coordinator, 9, 101)
	check(status["ready"] and queue.gate(status, 10)["ready"], "completed proposal opens the same deadline")
	check(not queue.gate(status, 9)["planned"], "early completion still does not publish")
	var decisions := queue.take_ready()
	check(decisions.size() == 1 and decisions[0]["output"] == Task.run(input), "asynchronous output matches the reference calculation")
	check(ai.restore_state(decisions[0]["output"]["state"]) and ai.last_economic_tick == 10, "decision state retains its authoritative target tick")
	controller.set_before_fixed_tick(Callable())
	controller.advance_frame(0.0, 1, 2)
	check(controller.tick_index == 10, "deadline resumes without dropping the fixed step")

	coordinator.enabled = false
	queue.begin([ai], 10, 18, Callable(self, "capture"))
	status = queue.poll(coordinator, 10, 102)
	check(status["ready"] and queue.is_prepared(), "reference mode prepares the same isolated decision")
	check(queue.gate(status, 11)["ready"] and not queue.gate(status, 11)["planned"], "reference mode advances before the target without early publication")
	queue.cancel(coordinator)
	queue.begin([ai, Ai.new({"team": 3})], 10, 18, Callable(self, "capture"))
	queue.poll(coordinator, 10, 103)
	check(not queue.is_prepared(), "all peer captures share one fixed source boundary")
	check(queue.poll(coordinator, 11, 104).get("error", "") == "ai_source_tick_changed", "advancing with an uncaptured peer is explicitly rejected")
	queue.cancel(coordinator)
	coordinator.shutdown()
	world.task_coordinator.shutdown()
	finish()

func capture(ai, tick: int) -> Dictionary:
	captures += 1
	return Task.capture(ai, {"tick": 2, "observer_team": ai.team, "map_size": Vector2i(12, 12), "player_state": {"team": ai.team, "allies": [ai.team]}, "units": [], "buildings": [], "resources": []}, tick)

func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
