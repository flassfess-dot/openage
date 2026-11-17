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
var render_frame_override := -1
var capture_budget_override := -1

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
	if decisions.active: decisions.prepare = Callable(self, "capture_ai")
	decisions.prepare_navigation = Callable(self, "capture_navigation")
	decisions.prepare_sites = Callable(self, "capture_sites")

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
	var record: Dictionary = decisions.record_for(ai)
	if bool(record.get("split", false)):
		return preparation.capture_facts(world, store, ai, controller.tick_index, target_tick, record["navigation"], controller.performance_probe)
	return preparation.capture(world, store, ai, controller.tick_index, target_tick, controller.performance_probe, mini(capture_budget_override if capture_budget_override > 0 else Preparation.CAPTURE_BUDGET_USEC, decisions.preparation_usec_left))

func capture_sites(ai, input: Dictionary, tick: int) -> Dictionary:
	return preparation.capture_sites(world, ai, input, tick)

func capture_navigation(ai, target_tick: int) -> Dictionary:
	var options: Dictionary = ai.decision_options(target_tick) if ai.has_method("decision_options") else ai.presentation_options()
	if not bool(options.get("include_navigation", true)):
		return {"navigation":{}}
	return world.ai_navigation_knowledge.capture_publication(world, world.get_fog_of_war(), int(ai.team))

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
	# Other teams may still be planning. Each observer retains its own input
	# and drains feedback only when starting its next deterministic decision.
	var horizon: int = controller.tick_index + AiDecisionQueue.LOOKAHEAD_TICKS
	for ai in players:
		if not decisions.record_for(ai).is_empty(): continue
		ai.collect_feedback(controller, controller.tick_index)
		var candidate := next_decision_tick(ai, next_tick)
		if candidate < 0 or candidate > horizon:
			continue
		decisions.schedule(ai, controller.tick_index, candidate, Callable(self, "capture_ai"), true)
	if not decisions.active:
		return false
	return _poll(next_tick)
func _poll(next_tick: int) -> Dictionary:
	var status: Dictionary = decisions.poll(coordinator, controller.tick_index, render_frame_override if render_frame_override >= 0 else Engine.get_process_frames(), controller.performance_probe)
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
			# Planner metadata belongs to AI state, not replayed gameplay params.
			# Strip it before recording/queueing so save and replay hashes agree.
			var metadata: Dictionary = command.params.get("_ai_feedback", {})
			command.params.erase("_ai_feedback")
			controller.enqueue_command(command, true, int(ai.team))
			ai.register_proposal(command, metadata)
	return {"ready": true, "planned": not batch.is_empty()}
