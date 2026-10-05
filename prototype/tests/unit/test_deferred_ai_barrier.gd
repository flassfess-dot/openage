extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const DecisionQueue := preload("res://scripts/ai_decision_queue.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
var failures: Array[String] = []
var capture_count := 0
var pending_capture_count := 0

class BlockedWork extends RefCounted:
	var release := Semaphore.new()
	func run(input: Dictionary) -> Dictionary:
		release.wait()
		return {"value": input["value"]}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := World.new(Vector2i(16, 16))
	world.add_unit(1, "villager", Vector2(4, 4), false)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ready := {"value": false}
	var attempts: Array[int] = []
	controller.set_before_fixed_tick(func(next_tick: int) -> Dictionary:
		attempts.append(next_tick)
		return {"ready": bool(ready["value"])}
	)
	controller.advance_frame(0.16, 1, 2)
	check(controller.tick_index == 0 and is_equal_approx(controller.accumulator_seconds, 0.16), "pending preparation consumes neither tick nor time debt")
	check(attempts == [1], "pending preparation yields instead of repeatedly retrying within one frame")
	ready["value"] = true
	controller.advance_frame(0.0, 1, 2)
	check(controller.tick_index == 3 and is_equal_approx(controller.accumulator_seconds, 0.01), "ready preparation resumes the original ordered fixed steps")

	var coordinator := Coordinator.new()
	var blocked := BlockedWork.new()
	var request := coordinator.submit("test", {"value": 7}, blocked.run, 10, 12, {"map": 1}, true)
	check(coordinator.collect_for_tick(request, 11, {"map": 1})["status"] == "future", "proposal cannot publish before its declared tick")
	check(coordinator.collect_for_tick(request, 12, {"map": 1})["status"] == "pending", "poll returns while the worker is explicitly blocked")
	blocked.release.post()
	while not coordinator.is_ready(request):
		await process_frame
	check(coordinator.collect_for_tick(request, 12, {"map": 1})["result"]["data"]["value"] == 7, "proposal publishes at its predetermined tick")

	var stale := BlockedWork.new()
	request = coordinator.submit("test", {"value": 8}, stale.run, 10, 12, {}, true)
	check(coordinator.collect_for_tick(request, 13)["status"] == "stale", "missed apply tick discards publication without waiting")
	stale.release.post()
	while coordinator.pending.has(request):
		coordinator.reap_abandoned()
		await process_frame
	check(not coordinator.pending.has(request), "abandoned worker releases its bounded slot")

	var players: Array = [Ai.new({"team": 1}), Ai.new({"team": 2})]
	var queue := DecisionQueue.new()
	queue.begin(players, 0, 1, Callable(self, "_capture"))
	queue.poll(coordinator, 0, 100)
	queue.poll(coordinator, 0, 100)
	check(capture_count == 1, "one frame prepares at most one AI observation")
	queue.poll(coordinator, 0, 101)
	check(capture_count == 2, "next frame prepares the second AI without repeating the first capture")
	var frame_id := 102
	var status: Dictionary = queue.poll(coordinator, 0, frame_id)
	while not bool(status["ready"]):
		await process_frame
		frame_id += 1
		status = queue.poll(coordinator, 0, frame_id)
	var decisions := queue.take_ready()
	check(decisions.size() == 2 and int(decisions[0]["ai"].team) == 1 and int(decisions[1]["ai"].team) == 2, "completion order cannot reorder players")
	for decision in decisions:
		var expected: Dictionary = Task.run(decision["input"])
		check(decision["output"] == expected, "deferred planning preserves commands, state, and simulation tick")
	queue.begin([players[0]], 1, 2, Callable(self, "_pending_capture"))
	status = queue.poll(coordinator, 1, queue.last_prepared_frame)
	check(not status["ready"] and pending_capture_count == 0, "adjacent batch preserves the rendered frame's capture budget")
	frame_id += 1
	status = queue.poll(coordinator, 1, frame_id)
	check(not status["ready"] and not status.has("error") and coordinator.pending.is_empty(), "pending navigation is preparation, never a worker input or failure")
	queue.poll(coordinator, 1, frame_id)
	check(pending_capture_count == 1, "same frame cannot repeat a pending slice")
	frame_id += 1
	status = queue.poll(coordinator, 1, frame_id)
	check(not status.has("error") and coordinator.pending.is_empty(), "further preparation slices keep the tick gate pending")
	frame_id += 1
	status = queue.poll(coordinator, 1, frame_id)
	while not bool(status["ready"]):
		await process_frame
		frame_id += 1
		status = queue.poll(coordinator, 1, frame_id)
	check(queue.take_ready().size() == 1 and pending_capture_count == 3, "only completed preparation is captured and submitted once")
	coordinator.shutdown()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _capture(ai, tick: int) -> Dictionary:
	capture_count += 1
	return Task.capture(ai, {"observer_team": ai.team, "map_size": Vector2i(16, 16), "player_state": {"team": ai.team, "allies": [ai.team]}, "units": [], "buildings": [], "resources": []}, tick)

func _pending_capture(ai, tick: int) -> Dictionary:
	pending_capture_count += 1
	if pending_capture_count < 3:
		return {"pending": true}
	return _capture(ai, tick)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
