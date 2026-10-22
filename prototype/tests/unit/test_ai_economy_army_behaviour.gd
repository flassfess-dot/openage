extends SceneTree

const Ai := preload("res://scripts/ai_player.gd")
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
const State := preload("res://scripts/ai_strategy_state.gd")
const Budget := preload("res://scripts/ai_plan_budget.gd")
const Operations := preload("res://scripts/ai_operations.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Commands := preload("res://scripts/commands.gd")
const Result := preload("res://scripts/command_result.gd")
var failures: Array[String] = []

class FeedbackController:
	extends RefCounted
	var results: Dictionary = {}
	func get_command_result(sequence: int) -> Dictionary:
		return results.get(sequence, {})

func _initialize() -> void:
	verify_economy()
	verify_site_feedback()
	verify_reinforcements()
	verify_coastal_target()
	verify_worker_safety()
	verify_target_alternative()
	for failure in failures: push_error(failure)
	print("AI economy and army behaviour: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func fighter(id: int, position: Vector2, owner: int = 1) -> Dictionary:
	return {"id": id, "team": owner, "hp": 40.0, "max_hp": 40.0, "pos": position, "kind": "clubman", "task": "idle", "movement_domain": "land", "combat_enabled": true, "behavior_tags": ["combatant"], "components": {}, "ai_profile": {"enabled": true, "max_hp": 40.0, "damage": 6.0, "period": 1.0, "range": 1.0}}

func snapshot() -> Dictionary:
	var result := {"tick": 40, "observer_team": 1, "map_size": Vector2i(48, 48), "player_state": {"team": 1, "age": 100, "allies": [1], "food": 300, "wood": 200, "population": 12, "population_cap": 50, "population_limit": 50}, "units": [], "buildings": [], "resources": [], "navigation": {"land": [Vector2(4, 4), Vector2(5, 4), Vector2(14, 4), Vector2(42, 42)], "reachable": {"land": [Vector2(4, 4), Vector2(5, 4), Vector2(14, 4), Vector2(42, 42)]}}, "build_sites": {}}
	for id in range(100, 112):
		result["units"].append({"id": id, "team": 1, "hp": 25.0, "pos": Vector2(4, 4), "kind": "villager", "task": "idle", "movement_domain": "land", "behavior_tags": ["worker"], "components": {"worker": {"enabled": true}}})
	result["buildings"] = [{"id": 10, "team": 1, "hp": 600.0, "pos": Vector2(4, 4), "kind": "town_center", "state": "complete", "entity_type": "building", "production_queue": [], "command_options": {"train": [{"kind": "villager", "accepted": true, "cost": {0: 50}, "behavior_tags": ["worker"], "population_cost": 1}], "research": [{"technology_id": 101, "accepted": false, "reason": "insufficient_resources", "cost": {0: 500}}]}}, {"id": 11, "team": 1, "hp": 300.0, "pos": Vector2(7, 4), "kind": "barracks", "state": "complete", "production_queue": [], "command_options": {"train": [{"kind": "clubman", "accepted": true, "cost": {0: 50}, "behavior_tags": ["combatant"], "population_cost": 1, "ai_profile": {"enabled": true, "max_hp": 40.0, "damage": 6.0, "period": 1.0}}]}}]
	return result

func plan_economy(input: Dictionary, defending: bool = false) -> Array:
	var state := State.new()
	state.goal = {"type": "defend" if defending else "explore"}
	return Economy.plan(input, int(input["tick"]) + 1, 1, Policy.resolve(), state, Budget.new(input["player_state"], input["buildings"]), {})

func verify_economy() -> void:
	var input := snapshot()
	var commands := plan_economy(input)
	check(not commands.any(func(c): return c.command_type() == "train" and 10 in c.unit_ids), "an age-ready workforce saves food instead of continually growing its worker target")
	check(commands.any(func(c): return c.command_type() == "train" and 11 in c.unit_ids), "age saving retains the minimum army")
	input["player_state"]["food"] = 500
	input["buildings"][0]["command_options"]["research"][0]["accepted"] = true
	commands = plan_economy(input, true)
	check(not commands.any(func(c): return c.command_type() == "research"), "base defence precedes an affordable age")
	input["player_state"]["food"] = 700
	input["units"].append_array([fighter(200, Vector2(4, 4)), fighter(201, Vector2(5, 4)), fighter(202, Vector2(6, 4))])
	commands = plan_economy(input)
	check(commands.any(func(c): return c.command_type() == "research"), "a funded sustainable economy advances age")
	input["player_state"]["food"] = 560
	input["buildings"][0]["command_options"]["train"][0]["cost"] = {0: 75}
	commands = plan_economy(input)
	check(commands.any(func(c): return c.command_type() == "research") and not commands.any(func(c): return c.command_type() == "train" and 10 in c.unit_ids), "an age-ready workforce does not reserve the price of an unnecessary worker")
	var recovering := input.duplicate(true)
	recovering["units"] = recovering["units"].slice(0, 5)
	recovering["player_state"]["food"] = 74
	check(not plan_economy(recovering).any(func(c): return c.command_type() == "train" and 10 in c.unit_ids), "essential worker recovery cannot spend less than the civilization's actual price")
	recovering["player_state"]["food"] = 75
	check(plan_economy(recovering).any(func(c): return c.command_type() == "train" and 10 in c.unit_ids), "essential worker recovery retains a worker at its exact civilization price")
	input["player_state"]["food"] = 700
	input["buildings"][0]["command_options"]["train"][0]["cost"] = {0: 50}
	input["units"][0]["ai_profile"] = {"carried_amount": 10.0, "gather_stage": "none"}
	commands = plan_economy(input)
	check(commands.any(func(c): return c.command_type() == "return_resources" and 100 in c.unit_ids), "idle cargo is explicitly returned")
	input["units"][0]["task"] = "gather"
	input["units"][0]["ai_profile"]["gather_stage"] = "returning"
	commands = plan_economy(input)
	check(not commands.any(func(c): return 100 in c.unit_ids), "an active delivery keeps its route")
	input["buildings"][1]["production_queue"] = [{"kind": "clubman"}, {"kind": "clubman"}, {"kind": "clubman"}]
	commands = plan_economy(input)
	check(not commands.any(func(c): return c.command_type() == "train" and 11 in c.unit_ids), "deep queues cannot prepay further reinforcements")
	input = snapshot()
	input["units"] = input["units"].slice(0, 6)
	input["units"].append_array([fighter(200, Vector2(4, 4)), fighter(201, Vector2(5, 4)), fighter(202, Vector2(6, 4))])
	input["buildings"][0]["command_options"]["research"] = []
	input["buildings"][1]["command_options"]["research"] = [{"technology_id": 9, "accepted": true, "cost": {0: 300}, "ai_relevance": 1000.0}]
	commands = plan_economy(input)
	check(commands.any(func(c): return c.command_type() == "train" and 11 in c.unit_ids), "unfunded preferred research falls back to an affordable fighter")
	input["player_state"]["population_limit"] = 200
	input["player_state"]["age"] = 103
	input["buildings"].append({"id": 12, "team": 1, "hp": 100.0, "kind": "archery_range"})
	input["buildings"].append({"id": 13, "team": 1, "hp": 100.0, "kind": "stable"})
	check(Economy.policy_for(input, 1, Policy.resolve(), State.new())["land_worker_target"] > 40, "large late economies scale beyond forty workers")

func verify_site_feedback() -> void:
	var state := State.new()
	var controller := FeedbackController.new()
	var command := Commands.BuildCommand.new(41, [100], "barracks", Vector2(10, 10))
	command.assign_envelope(1, 1)
	state.register(command, {"key": "build:first", "site_key": Economy._site_key("barracks", Vector2(10, 10)), "cost": {1: 125}})
	controller.results[1] = Result.rejected(command, 41, "blocked_or_sloped")
	state.feedback(controller, 1, 41, Policy.resolve())
	check(state.cooldowns.has(Economy._site_key("barracks", Vector2(10, 10))), "rejected site is excluded across different builders")
	var input := snapshot()
	input["units"][0]["command_options"] = {"build": [{"kind": "barracks", "accepted": true, "cost": {1: 125}, "footprint_radius": 1.5}]}
	input["buildings"] = input["buildings"].slice(0, 1)
	input["build_sites"] = {"barracks": [Vector2(10, 10), Vector2(14, 14)]}
	state.goal = {"type": "explore"}
	var commands := Economy.plan(input, 42, 1, Policy.resolve(), state, Budget.new(input["player_state"], input["buildings"]), {})
	check(commands.any(func(c): return c.command_type() == "build" and c.params["target"] == Vector2(14, 14)), "a rejected best site does not hide a valid alternative")

func verify_reinforcements() -> void:
	var input := snapshot()
	input["units"] = [fighter(20, Vector2(7, 4), 2), fighter(200, Vector2(4, 4)), fighter(201, Vector2(5, 4)), fighter(202, Vector2(6, 4))]
	var state := State.new()
	var policy := Policy.resolve()
	state.observe(input, 1, policy)
	var goal := state.choose_goal(input, 1, policy, 0)
	var operations := Operations.new()
	operations.plan(input, 41, 1, goal, policy, state, {}, "RECTANGLE", true)
	input["units"].append_array([fighter(203, Vector2(4, 4)), fighter(204, Vector2(5, 4)), fighter(205, Vector2(6, 4))])
	input["tick"] = 120
	state.observe(input, 1, policy)
	goal = state.choose_goal(input, 1, policy, 1)
	operations.plan(input, 121, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(operations.groups.values()[0]["group"].member_ids.size() == 6, "nearby replacements join an active operation")
	input["units"][1]["task"] = "attack"
	input["tick"] = 220
	state.observe(input, 1, policy)
	var commands := operations.plan(input, 221, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(commands.any(func(c): return c.command_type() == "attack_move" and 201 in c.unit_ids and 200 not in c.unit_ids), "idle members receive orders while an active fighter keeps combat")
	for unit in input["units"]:
		if unit["team"] == 1: unit["pos"] = Vector2(38, 38)
	input["units"][0]["pos"] = Vector2(42, 42)
	input["units"].append_array([fighter(206, Vector2(4, 4)), fighter(207, Vector2(5, 4)), fighter(208, Vector2(6, 4)), fighter(209, Vector2(4, 5)), fighter(210, Vector2(5, 5))])
	input["tick"] = 320
	state.observe(input, 1, policy)
	goal = state.choose_goal(input, 1, policy, 2)
	operations.plan(input, 321, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(operations.groups.size() == 2, "distant reinforcements form a second wave while home guards remain")

func verify_coastal_target() -> void:
	var input := snapshot()
	input["units"] = []
	for id in range(200, 204):
		var ship := fighter(id, Vector2(4, 4))
		ship["kind"] = "scout_ship"
		ship["movement_domain"] = "water"
		ship["ai_profile"]["range"] = 6.0
		input["units"].append(ship)
	input["buildings"].append({"id": 20, "team": 2, "hp": 600.0, "pos": Vector2(25, 25), "kind": "dock", "entity_type": "building", "movement_domain": "static", "target_domains": ["land", "water"], "combat_enabled": false})
	input["navigation"]["water"] = [Vector2(4, 4), Vector2(24, 25)]
	input["navigation"]["reachable"]["water"] = input["navigation"]["water"]
	var state := State.new()
	var policy := Policy.resolve()
	state.observe(input, 1, policy)
	var goal := state.choose_goal(input, 1, policy, 0)
	check(goal["goals_by_domain"].has("water"), "coastal structures retain a naval objective")
	var commands := Operations.new().plan(input, 41, 1, goal, policy, state, {}, "RECTANGLE", true)
	check(commands.any(func(c): return c.command_type() == "attack_move" and c.params["target"] == Vector2(24, 25)), "fleet approaches a coastal target on navigable water")

func verify_worker_safety() -> void:
	var input := snapshot()
	input["units"] = [input["units"][0], fighter(20, Vector2(4, 5), 2)]
	input["units"][0]["task"] = "gather"
	input["units"][0]["resource_id"] = 300
	input["resources"] = [{"id": 300, "amount": 500, "resource_type_id": 0, "pos": Vector2(4, 4)}]
	var state := State.new()
	var policy := Policy.resolve()
	state.observe(input, 1, policy)
	state.choose_goal(input, 1, policy, 0)
	var commands := Economy.plan(input, 41, 1, policy, state, Budget.new(input["player_state"], input["buildings"]), {})
	check(commands.any(func(c): return c.command_type() == "move" and 100 in c.unit_ids), "danger overrides a productive worker's gather quota")
	check(not commands.any(func(c): return c.command_type() == "gather" and 100 in c.unit_ids), "economic allocation cannot overwrite evacuation")

func verify_target_alternative() -> void:
	var input := snapshot()
	input["units"] = [fighter(200, Vector2(4, 4)), fighter(201, Vector2(5, 4)), fighter(202, Vector2(6, 4))]
	input["buildings"].append({"id": 20, "team": 2, "hp": 600.0, "pos": Vector2(42, 42), "kind": "town_center", "entity_type": "building", "movement_domain": "static"})
	for id in range(300, 312): input["units"].append(fighter(id, Vector2(42, 41), 2))
	input["units"].append({"id": 400, "team": 2, "hp": 25.0, "pos": Vector2(22, 12), "kind": "villager", "movement_domain": "land", "components": {"worker": {"enabled": true}}})
	var state := State.new()
	state.observe(input, 1, Policy.resolve())
	check(state.choose_goal(input, 1, Policy.resolve(), 0).get("target_id") == 400, "a weak army can raid exposed economy instead of waiting at a guarded town")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
