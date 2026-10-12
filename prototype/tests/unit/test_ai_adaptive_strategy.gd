extends SceneTree
const Ai := preload("res://scripts/ai_player.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
const State := preload("res://scripts/ai_strategy_state.gd")
const Budget := preload("res://scripts/ai_plan_budget.gd")
const Operations := preload("res://scripts/ai_operations.gd")
const Group := preload("res://scripts/source_ai_attack_group.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Commands := preload("res://scripts/commands.gd")
const Result := preload("res://scripts/command_result.gd")
var failures: Array[String] = []

class FeedbackController:
	extends RefCounted
	var results: Dictionary = {}
	func get_command_result(sequence: int) -> Dictionary:
		return results.get(sequence, {}).duplicate(true)

func _initialize() -> void:
	verify_budget()
	verify_knowledge_and_exact_json()
	verify_group_lifecycle()
	verify_scout_mission()
	verify_gather_retry()
	verify_gather_allocation()
	verify_adaptive_threading()
	for failure in failures: push_error(failure)
	print("Adaptive AI regressions: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func verify_budget() -> void:
	var budget := Budget.new({"food": 100, "wood": 50, "population_points": 2, "population_cap": 3, "population_limit": 50}, [{"production_queue": [{"order_type": "unit", "population_points_cost": 2}, {"order_type": "unit", "population_points_cost": 1}]}])
	check(budget.population_points == 1, "queued full and half population costs consume one common pool")
	check(budget.reserve({0: 80}, 1, 10), "first producer can spend legal common funds")
	check(not budget.reserve({0: 30}, 0, 11), "second producer cannot reuse spent food")
	check(not budget.reserve({}, 0, 10), "one producer receives at most one spending proposal")
	check(budget.remaining[0] == 20 and budget.population_points == 0, "rejected proposals do not mutate remaining budget")

func verify_knowledge_and_exact_json() -> void:
	var policy := Policy.resolve()
	var state := State.new()
	var snapshot := base_snapshot()
	state.observe(snapshot, 1, policy)
	var goal := state.choose_goal(snapshot, 1, policy, 0)
	check(goal.get("type") == "defend" and goal.get("target_id") == 20, "nearby threat wins over a distant low-ID building")
	check(Data.is_detached(state.canonical_state()), "domain objectives and the primary goal never form a dictionary cycle")
	var seen_tick := int(state.memory[20]["seen_tick"])
	snapshot["tick"] = 100
	snapshot["units"][0]["last_known"] = true
	state.observe(snapshot, 1, policy)
	check(int(state.memory[20]["seen_tick"]) == seen_tick, "fog rows do not refresh an observation")
	var controller := FeedbackController.new()
	var train = Commands.TrainCommand.new(101, [10], "clubman", 1, Vector2(4, 4))
	train.assign_envelope(1, 11)
	state.register(train, {"key": "train:10", "cost": {0: 50, 1: 30}})
	controller.results[11] = Result.accepted(train, 101)
	var codec := Replay.new()
	var encoded := codec.encode_exact_variant(state.canonical_state())
	var restored := State.new()
	check(restored.restore_state(codec.decode_variant(JSON.parse_string(JSON.stringify(encoded)))), "nested adaptive knowledge and pending feedback survive JSON")
	check(restored.canonical_state() == state.canonical_state(), "exact archive encoding preserves integer values, typed dictionary keys and floats")
	restored.feedback(controller, 1, 101, policy)
	check(restored.spent.get(0) == 50 and restored.spent.get(1) == 30 and restored.pending.is_empty(), "restored own result credits accepted spending once")
	restored.feedback(controller, 1, 102, policy)
	check(restored.metrics["commands_accepted"] == 1, "feedback replay cannot double-count spending")
	snapshot["tick"] = 110
	snapshot["units"] = []
	snapshot["ai_visible_memory_locations"] = {20: true}
	state.observe(snapshot, 1, policy)
	check(not state.memory.has(20), "visible empty locations invalidate a remembered opponent")

func verify_group_lifecycle() -> void:
	var policy := Policy.resolve()
	var snapshot := base_snapshot()
	snapshot["units"].append_array([fighter(100, Vector2(4, 4)), fighter(101, Vector2(5, 4)), fighter(102, Vector2(6, 4))])
	var state := State.new()
	state.observe(snapshot, 1, policy)
	var goal := state.choose_goal(snapshot, 1, policy, 0)
	var operations := Operations.new()
	var commands := operations.plan(snapshot, 41, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(commands.any(func(command): return command.command_type() == "attack_move"), "assembled defenders enter combat through normal attack-move commands")
	check(operations.scouts.is_empty(), "base defence retains fighters rather than detaching a scout")
	check(operations.groups.size() == 1, "one stable region owns one persistent force")
	for unit in snapshot["units"]:
		if int(unit.get("team", 0)) == 1: unit["hp"] = 5.0
	snapshot["tick"] = 60
	state.observe(snapshot, 1, policy)
	commands = operations.plan(snapshot, 61, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(commands.any(func(command): return command.command_type() == "formation_move"), "casualties trigger a retreat to a rally position")
	var group = operations.groups.values()[0]["group"]
	check(group.state in [Group.RETREATING, Group.RECENTERING], "damaged defence cannot override the retreat state")
	var restored := Operations.new()
	check(restored.restore_state(operations.canonical_state(), 1) and restored.canonical_state() == operations.canonical_state(), "group membership, losses and phase survive restoration")

func verify_scout_mission() -> void:
	var snapshot := base_snapshot()
	var scout := fighter(100, Vector2(4, 4))
	scout["ai_profile"]["speed"] = 0.5
	snapshot["units"] = [scout]
	snapshot["buildings"] = snapshot["buildings"].filter(func(b): return b.get("team") == 1)
	snapshot["navigation"]["reachable_frontier"] = {"land": [Vector2(20, 4)]}
	snapshot["navigation"]["frontier_by_region"] = {"land:0": [Vector2(20, 4)]}
	var state := State.new()
	state.observe(snapshot, 1, Policy.resolve())
	var goal := {"type": "explore", "home": Vector2(4, 4), "position": Vector2(20, 4)}
	state.goal = goal.duplicate()
	var operations := Operations.new()
	var commands := operations.plan(snapshot, 41, 1, goal, Policy.resolve(), state, {}, "RECTANGLE", true)
	check(commands.size() == 1 and commands[0].command_type() == "move", "an explicit scout receives an exploration mission")
	scout["pos"] = Vector2(9, 4)
	scout["task"] = "move"
	snapshot["tick"] = 240
	snapshot["navigation"]["frontier_by_region"]["land:0"] = [Vector2(6, 4), Vector2(20, 4)]
	state.observe(snapshot, 1, Policy.resolve())
	commands = operations.plan(snapshot, 241, 1, goal, Policy.resolve(), state, {}, "RECTANGLE", true)
	check(commands.is_empty() and operations.scouts["land"]["target"] == Vector2(20, 4), "a moving scout completes a reachable mission before chasing a new frontier")

func verify_gather_retry() -> void:
	var policy := Policy.resolve()
	policy["economic_interval_ticks"] = 1
	policy["gather_retry_ticks"] = 40
	var ai := Ai.new({"team": 1, "ai": policy})
	var snapshot := {"tick": 10, "observer_team": 1, "map_size": Vector2i(24, 24), "player_state": {"team": 1, "allies": [1], "population_cap": 4, "population_limit": 50}, "units": [{"id": 100, "team": 1, "hp": 25.0, "pos": Vector2(4, 4), "movement_domain": "land", "task": "idle", "path_request_id": 1, "components": {"worker": {"enabled": true}, "order": {"type": "gather", "target_entity_id": 300, "completed": true, "completion_reason": "no_path"}}}], "buildings": [], "resources": [{"id": 300, "pos": Vector2(5, 4), "amount": 100, "resource_type_id": 0, "allowed_gatherer_domains": ["land"]}], "navigation": {"land": [Vector2(4, 4), Vector2(5, 4)], "reachable": {"land": [Vector2(4, 4), Vector2(5, 4)]}}}
	var commands := ai.collect_commands(snapshot, 11)
	check(not commands.any(func(c): return c.command_type() == "gather"), "a newly failed resource is temporarily excluded")
	snapshot["tick"] = 55
	commands = ai.collect_commands(snapshot, 56)
	check(commands.any(func(c): return c.command_type() == "gather"), "the same completed order cannot renew an expired blacklist")
	snapshot["tick"] = 10
	snapshot["resources"] = []
	snapshot["buildings"] = [{"id": 300, "team": 1, "hp": 50.0, "pos": Vector2(5, 4), "kind": "farm", "state": "complete", "harvestable": true, "amount": 100, "resource_type_id": 0}]
	ai = Ai.new({"team": 1, "ai": policy})
	ai.collect_commands(snapshot, 11)
	snapshot["tick"] = 20
	commands = ai.collect_commands(snapshot, 21)
	check(not commands.any(func(c): return c.command_type() == "gather"), "a living farm keeps its failure cooldown before expiry")
	snapshot["tick"] = 55
	commands = ai.collect_commands(snapshot, 56)
	check(commands.any(func(c): return c.command_type() == "gather"), "a farm becomes eligible again after failure expiry")

func verify_gather_allocation() -> void:
	var snapshot := base_snapshot()
	snapshot["units"] = []
	for id in range(100, 106):
		snapshot["units"].append({"id": id, "team": 1, "hp": 25.0, "pos": Vector2(4, 4), "task": "idle", "movement_domain": "land", "components": {"worker": {"enabled": true}}})
	snapshot["units"].append({"id": 190, "team": 1, "hp": 25.0, "pos": Vector2(4, 4), "task": "gather", "movement_domain": "land", "resource_id": 300, "components": {"worker": {"enabled": true}}, "ai_profile": {"carried_amount": 15.0, "gather_stage": "returning"}})
	snapshot["resources"] = [{"id": 300, "pos": Vector2(5, 4), "amount": 500, "resource_type_id": 0}, {"id": 400, "pos": Vector2(6, 4), "amount": 500, "resource_type_id": 1}]
	var policy := Policy.resolve()
	policy["desired_stock"] = {0: 500.0, 1: 500.0}
	var commands: Array = Economy._gather(snapshot, 41, 1, policy, State.new(), {})
	check(commands.size() == 6, "idle workers receive a bounded batch of economic assignments")
	check(not commands.any(func(c): return 190 in c.unit_ids), "returning cargo completes its delivery before a new gather assignment")
	check(commands.any(func(c): return int(c.params["resource_id"]) == 300) and commands.any(func(c): return int(c.params["resource_id"]) == 400), "worker quotas retain income in both needed resource types")

func verify_adaptive_threading() -> void:
	var policy := Policy.resolve()
	var ai := Ai.new({"team": 1, "ai": policy})
	var snapshot := base_snapshot()
	snapshot["units"].append_array([fighter(100, Vector2(4, 4)), fighter(101, Vector2(5, 4)), fighter(102, Vector2(6, 4))])
	var input := Task.capture(ai, snapshot, 41)
	var sequential := Task.run(input)
	var coordinator := Coordinator.new()
	var threaded: Array = coordinator.run_ordered("ai_planning", [input], Task.run, 40)
	check(not threaded.is_empty() and threaded[0] == sequential, "adaptive commands and complete state match across sequential and threaded planning")
	check(not Task.decode_commands(sequential).is_empty(), "adaptive proposals decode into ordinary commands")
	coordinator.shutdown()

func fighter(id: int, position: Vector2) -> Dictionary:
	return {"id": id, "team": 1, "hp": 40.0, "max_hp": 40.0, "pos": position, "kind": "clubman", "task": "idle", "movement_domain": "land", "combat_enabled": true, "components": {}, "ai_profile": {"enabled": true, "damage": 6.0, "period": 1.0, "range": 1.0}}

func base_snapshot() -> Dictionary:
	return {"tick": 40, "observer_team": 1, "map_size": Vector2i(24, 24), "player_state": {"team": 1, "allies": [1], "population_cap": 10, "population_limit": 50}, "units": [{"id": 20, "team": 2, "hp": 20.0, "pos": Vector2(7, 4), "movement_domain": "land", "combat_enabled": true, "ai_profile": {"enabled": true, "damage": 1.0, "period": 2.0, "range": 1.0}}], "buildings": [{"id": 10, "team": 1, "hp": 600.0, "kind": "town_center", "pos": Vector2(4, 4), "entity_type": "building", "state": "complete"}, {"id": 2, "team": 2, "hp": 600.0, "kind": "town_center", "pos": Vector2(22, 22), "entity_type": "building", "movement_domain": "static"}], "resources": [], "navigation": {"land": [Vector2(4, 4), Vector2(5, 4), Vector2(6, 4), Vector2(7, 4)], "reachable": {"land": [Vector2(4, 4), Vector2(5, 4), Vector2(6, 4), Vector2(7, 4)]}, "unit_regions": {100: "land:0", 101: "land:0", 102: "land:0"}}}

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
