extends SceneTree

const Planner := preload("res://scripts/ai_economic_planner.gd")
const AiPlayer := preload("res://scripts/ai_player.gd")

var failures: Array[String] = []
var policy := {"construction_priorities": ["house", "barracks"], "building_limits": {"house": 4, "barracks": 1}, "housing_buffer": 2}

func _initialize() -> void:
	var base := {
		"observer_team": 2,
		"units": [{"id": 1, "team": 2, "hp": 25.0, "pos": Vector2(4, 4), "kind": "villager", "task": "idle", "movement_domain": "land", "components": {"worker": {"enabled": true}}, "command_options": {"build": [{"kind": "house", "accepted": true}, {"kind": "barracks", "accepted": true}]}}],
		"buildings": [], "resources": [], "navigation": {},
		"build_sites": {"house": [Vector2(7, 7)], "barracks": [Vector2(9, 9)]},
		"player_state": {"population": 3, "population_cap": 8, "population_limit": 50, "food": 400, "wood": 400, "stone": 400, "gold": 400},
	}
	_verify(base, ["barracks"], "ample housing")
	var changed: Dictionary = base.duplicate(true)
	changed["player_state"]["population"] = 7
	_verify(changed, ["house", "barracks"], "housing becomes necessary")
	changed = base.duplicate(true)
	changed["player_state"]["blocked_population_queues"] = 1
	_verify(changed, ["house", "barracks"], "blocked production requires housing")
	changed = base.duplicate(true)
	changed["player_state"]["population"] = 49
	changed["player_state"]["population_cap"] = 50
	_verify(changed, ["barracks"], "match population ceiling")
	changed = base.duplicate(true)
	changed["buildings"] = [_building("house", "foundation")]
	_verify(changed, [], "finish current foundation first")
	changed = base.duplicate(true)
	changed["buildings"] = [_building("barracks", "complete")]
	_verify(changed, [], "existing building satisfies policy limit")
	changed["buildings"][0]["hp"] = 0.0
	_verify(changed, ["barracks"], "destroyed building restores demand")
	changed = base.duplicate(true)
	changed["units"][0]["task"] = "repair"
	_verify(changed, [], "no worker available for new construction")
	changed = base.duplicate(true)
	changed["buildings"] = [_building("house", "foundation")]
	changed["buildings"][0]["team"] = 1
	_verify(changed, ["barracks"], "enemy foundation does not block planning")
	changed = base.duplicate(true)
	changed["buildings"] = [_building("town_center", "complete")]
	changed["buildings"][0]["production_queue"] = [{"status": "blocked_population", "order_type": "unit"}]
	_verify(changed, ["house", "barracks"], "queue demand is evaluated live")
	_test_spending_and_naval_filters(base)
	if failures.is_empty():
		print("AI construction demand preserves planner commands")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _building(kind: String, state: String) -> Dictionary:
	return {"id": 90, "team": 2, "kind": kind, "hp": 100.0, "pos": Vector2(10, 4), "state": state, "builder_count": 1, "production_queue": [], "command_options": {"train": [], "research": []}}

func _verify(snapshot: Dictionary, expected: Array, label: String) -> void:
	var definition: Dictionary = policy.duplicate(true)
	definition["profile"] = "skirmish_policy_v1"
	var ai := AiPlayer.new({"team": 2, "ai": definition})
	var filter: Callable = ai.presentation_options()["build_site_filter"]
	var kinds: Array = filter.call(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"])
	_check(kinds == expected, label + " selects only potentially useful sites")
	var filtered: Dictionary = snapshot.duplicate(true)
	for kind in filtered["build_sites"].keys():
		if kind not in kinds:
			filtered["build_sites"].erase(kind)
	var baseline := _commands(Planner.plan(snapshot, 1, 2, policy))
	var actual := _commands(Planner.plan(filtered, 1, 2, policy))
	_check(actual == baseline, label + " preserves commands and their order")

func _commands(commands: Array) -> Array:
	var result: Array = []
	for command in commands:
		result.append({"type": command.command_type(), "units": command.unit_ids, "params": command.params, "tick": command.tick})
	return result

func _check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)


func _test_spending_and_naval_filters(base: Dictionary) -> void:
	var snapshot: Dictionary = base.duplicate(true)
	var age_policy: Dictionary = policy.duplicate(true)
	age_policy["minimum_workers_before_age_up"] = 1
	age_policy["age_advance_technology_ids"] = [101]
	age_policy["age_saving_construction_exceptions"] = ["barracks"]
	snapshot["units"][0]["command_options"]["build"][1]["cost"] = {1: 125}
	var center := _building("town_center", "complete")
	center["command_options"]["research"] = [{"technology_id": 101, "accepted": false, "reason": "insufficient_resources", "cost": {0: 500}}]
	snapshot["buildings"] = [center]
	snapshot["player_state"]["population"] = 7
	var kinds := Planner.construction_site_kinds(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"], 2, age_policy)
	_check(kinds == ["barracks"], "age saving prepares only allowed buildings that avoid the reserved resources")
	var filtered: Dictionary = snapshot.duplicate(true)
	filtered["build_sites"].erase("house")
	_check(_commands(Planner.plan(filtered, 1, 2, age_policy)) == _commands(Planner.plan(snapshot, 1, 2, age_policy)), "age-saving filtering preserves planner commands")
	center["command_options"]["research"][0]["accepted"] = true
	_check(Planner.construction_site_kinds(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"], 2, age_policy).is_empty(), "accepted age-up avoids all unused construction searches")
	snapshot = base.duplicate(true)
	snapshot["buildings"] = [_building("dock", "complete")]
	snapshot["navigation"] = {"reachable_frontier": {"water": [Vector2(5, 5)]}}
	var fishing_boat: Dictionary = snapshot["units"][0].duplicate(true)
	fishing_boat["id"] = 2
	fishing_boat["movement_domain"] = "water"
	snapshot["units"].append(fishing_boat)
	_check(Planner.construction_site_kinds(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"], 2, policy, snapshot["navigation"]).is_empty(), "pending naval scout avoids unused land construction searches")
	fishing_boat["combat_enabled"] = true
	_check(Planner.construction_site_kinds(snapshot["build_sites"].keys(), snapshot["units"], snapshot["buildings"], snapshot["player_state"], 2, policy, snapshot["navigation"]) == ["barracks"], "a completed naval scout immediately restores construction demand")
