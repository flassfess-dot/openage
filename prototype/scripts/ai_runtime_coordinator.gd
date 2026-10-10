class_name RoRAiRuntimeCoordinator
extends RefCounted
const AiPlayer := preload("res://scripts/ai_player.gd")
const AiDecisionQueue := preload("res://scripts/ai_decision_queue.gd")
const AiPlanningTask := preload("res://scripts/ai_planning_task.gd")
const Preparation := preload("res://scripts/ai_observation_preparation.gd")
var world
var controller
var players: Array = []
var decisions
var store
var coordinator
var preparation := Preparation.new()
var error := ""

func configure(source_world, source_controller, source_players: Array, source_decisions, source_store, source_coordinator) -> void:
	if world != source_world or decisions != source_decisions:
		preparation.clear()
		error = ""
	world = source_world
	controller = source_controller
	players = source_players
	decisions = source_decisions
	store = source_store
	coordinator = source_coordinator

func shutdown() -> void:
	preparation.clear()
	if decisions != null and coordinator != null: decisions.cancel(coordinator)
	if store != null: store.clear()
	world = null
	controller = null
	players = []
	decisions = null
	store = null
	coordinator = null
	error = ""

func capture_ai(ai, target_tick: int) -> Dictionary:
	return preparation.capture(world, store, ai, controller.tick_index, target_tick, controller.performance_probe)

func next_decision_tick(ai, next_tick: int) -> int:
	if not ai.enabled or world.player_registry.status(int(ai.team)) != "active":
		return -1
	if int(ai.last_economic_tick) < 0 and int(ai.last_military_tick) < 0:
		return maxi(next_tick, AiPlayer.initial_decision_tick(ai, players))
	var target := int(ai.last_economic_tick) + maxi(1, int(ai.economic_interval))
	if ai.profile != "source_campaign_v1" or bool(ai.source_contract.get("runtime_support", {}).get("military_enabled", true)):
		target = mini(target, int(ai.last_military_tick) + maxi(1, int(ai.military_interval)))
	return maxi(next_tick, target)
func queue_commands(next_tick: int = -1) -> Variant:
	if next_tick < 0:
		next_tick = controller.tick_index + 1
	if decisions.active:
		return _poll(next_tick)
	var horizon: int = controller.tick_index + AiDecisionQueue.LOOKAHEAD_TICKS
	var target := horizon + 1
	var due: Array = []
	for ai in players:
		var candidate := next_decision_tick(ai, next_tick)
		if candidate < 0 or candidate > horizon:
			continue
		if candidate < target:
			target = candidate
			due = [ai]
		elif candidate == target:
			due.append(ai)
	if due.is_empty():
		return false
	decisions.begin(due, controller.tick_index, target, Callable(self, "capture_ai"))
	return _poll(next_tick)
func _poll(next_tick: int) -> Dictionary:
	var status: Dictionary = decisions.poll(coordinator, controller.tick_index, Engine.get_process_frames(), controller.performance_probe)
	if status.has("error"):
		error = "Ошибка расчёта ИИ: %s" % String(status["error"])

		controller.set_paused(true)
		preparation.clear()
		decisions.cancel(coordinator)
		return {"ready": false}
	var gate: Dictionary = decisions.gate(status, next_tick)
	if not bool(gate["ready"]) or next_tick < decisions.apply_tick:
		return gate
	var batch: Array = decisions.take_ready()
	# Decode and validate every proposal before changing any live player state.
	for decision in batch:
		decision["commands"] = AiPlanningTask.decode_commands(decision["output"])
		if decision["commands"].size() != decision["output"].get("commands", []).size() or decision["ai"].canonical_state() != decision["input"]["state"]:
			error = "Ошибка согласования состояния ИИ"

			controller.set_paused(true)
			return {"ready": false}
	for decision in batch:
		var ai = decision["ai"]
		if not ai.restore_state(decision["output"]["state"]):
			controller.set_paused(true)
			return {"ready": false}
		world.commit_ai_build_site_queries(decision["output"].get("build_site_cache_updates", []), next_tick)
		for command in decision["commands"]:
			controller.enqueue_command(command, true, int(ai.team))
	return {"ready": true, "planned": not batch.is_empty()}
