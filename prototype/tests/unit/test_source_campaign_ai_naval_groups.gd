extends SceneTree

const AssignmentGroup := preload("res://scripts/source_ai_assignment_group.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_independent_land_and_boat_attack_groups()
	test_boat_exploration_and_dock_defence()
	test_boat_escort_allocation_and_lifecycle()
	if failures.is_empty():
		print("I12-020L source naval group tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_independent_land_and_boat_attack_groups() -> void:
	var snapshot := snapshot_base()
	snapshot["units"] = [
		fighter(1, Vector2(2, 2), "land"), fighter(2, Vector2(3, 2), "land"),
		fighter(10, Vector2(2, 6), "water"), fighter(11, Vector2(3, 6), "water"),
		fighter(12, Vector2(4, 6), "water"), fighter(13, Vector2(5, 6), "water"),
		fighter(14, Vector2(6, 6), "water"),
	]
	snapshot["navigation"] = {
		"land": [Vector2(20.5, 19.5)],
		"water": [Vector2(19.5, 20.5)],
	}
	var contract := contract_with([
		{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 26, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 58, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 59, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 60, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 40, "value": 0, "runtime_semantics": "implemented"},
		{"source_id": 46, "value": 1, "runtime_semantics": "implemented"},
	])
	contract["target_markers"] = [{"position": Vector2(20, 20)}]
	var plan := Planner.plan_military(snapshot, 1, 2, contract, -1, 0)
	var groups: Array = plan.get("groups", [])
	assert_equal(groups.size(), 3, "one land and two source boat attack groups are created independently")
	assert_equal(groups[0].member_ids, [1, 2], "land group uses land min/max/count")
	assert_equal(groups[1].member_ids, [10, 11], "first boat group uses boat maximum")
	assert_equal(groups[2].member_ids, [12, 13], "second boat group preserves deterministic fleet order")
	assert_true(groups.slice(1).all(func(group): return String(group.movement_domain) == "water"), "boat groups retain the water lifecycle domain")
	assert_equal(groups[0].objective_position, Vector2(20.5, 19.5), "land marker snaps to the nearest land navigation point")
	assert_equal(groups[1].objective_position, Vector2(19.5, 20.5), "boat marker snaps to the nearest water navigation point")


func test_boat_exploration_and_dock_defence() -> void:
	var snapshot := snapshot_base()
	snapshot["map_size"] = Vector2i(4, 4)
	snapshot["fog"] = {"cells": [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	snapshot["navigation"] = {"land": [], "water": [Vector2(1.5, 1.5), Vector2(2.5, 1.5)]}
	snapshot["buildings"] = [building(80, "dock", Vector2(1.5, 1.5), 2)]
	snapshot["units"] = [
		fighter(10, Vector2(1.5, 1.5), "water"),
		fighter(11, Vector2(1.8, 1.5), "water"),
		fighter(12, Vector2(0.5, 0.5), "water"),
	]
	var contract := contract_with([
		{"source_id": 18, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 57, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 61, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 62, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 63, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 67, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 68, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 69, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 70, "value": 1, "runtime_semantics": "implemented"},
	])
	var plan := Planner.plan_strategic_assignments(snapshot, 1, 2, contract, {})
	var groups: Array = plan.get("groups", [])
	assert_equal(groups.size(), 2, "dock defence and boat exploration have independent desired counts")
	var defend = groups.filter(func(group): return String(group.role) == AssignmentGroup.DEFEND)[0]
	var explore = groups.filter(func(group): return String(group.role) == AssignmentGroup.EXPLORE)[0]
	assert_equal(defend.member_ids, [10, 11], "nearest warboats form the source-sized dock defence")
	assert_equal(defend.anchor_id, 80, "boat defenders persist the exact Dock anchor")
	assert_equal(defend.movement_domain, "water", "dock defence stays in the water domain")
	assert_equal(explore.member_ids, [12], "remaining warboat forms the source-sized exploration group")
	assert_equal(explore.anchor_kind, "boat_group", "boat exploration is distinct from civilian and soldier exploration")
	assert_equal(explore.movement_domain, "water", "boat exploration advances on the water frontier")
	assert_equal(plan.get("commands", []).map(func(command): return command.command_type()), ["attack_move"], "local dock defenders hold while explorers use the public attack-move command")

	var group_map := {int(defend.group_id): defend}
	snapshot["buildings"][0]["hp"] = 0.0
	var update := Planner.plan_assignment_group_lifecycle(snapshot, 2, 2, group_map)
	assert_equal(defend.state, AssignmentGroup.COMPLETE, "destroyed Dock releases its persistent defence group")
	assert_equal(update.get("completed_group_ids", []), [int(defend.group_id)], "dock lifecycle reports the exact completed assignment")


func test_boat_escort_allocation_and_lifecycle() -> void:
	var snapshot := snapshot_base()
	var trade_boat := economic_ship(100, "trade_boat", Vector2(2, 2), ["trader"])
	var fishing_boat := economic_ship(101, "fishing_boat", Vector2(10, 2), ["worker"], true)
	var transport := economic_ship(102, "transport", Vector2(18, 2), ["transport"])
	snapshot["units"] = [
		trade_boat, fishing_boat, transport,
		fighter(10, Vector2(0, 2), "water"),
		fighter(11, Vector2(1, 2), "water"),
		fighter(12, Vector2(9, 2), "water"),
		fighter(13, Vector2(17, 2), "water"),
		fighter(14, Vector2(30, 2), "water"),
	]
	var contract := contract_with([
		{"source_id": 64, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 65, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 66, "value": 1, "runtime_semantics": "implemented"},
	])
	var plan := Planner.plan_strategic_assignments(snapshot, 1, 2, contract, {})
	var escorts: Array = plan.get("groups", []).filter(func(group): return String(group.role) == AssignmentGroup.ESCORT)
	assert_equal(escorts.size(), 3, "trade, fishing and transport escorts use independent desired member counts")
	assert_equal(escorts.map(func(group): return String(group.anchor_kind)), ["escort_trade", "escort_fish", "escort_transport"], "escort categories remain explicit in canonical assignment state")
	assert_equal(escorts[0].member_ids, [10, 11], "two nearest warboats escort the trade boat")
	assert_equal(escorts[1].member_ids, [12], "fishing escort does not reuse reserved trade escorts")
	assert_equal(escorts[2].member_ids, [13], "transport escort receives the next domain-compatible warboat")
	assert_true(14 not in plan.get("unit_ids", []), "desired counts leave surplus warboats available for other naval duties")
	assert_true(plan.get("commands", []).is_empty(), "escorts already inside the follow envelope do not request redundant paths")

	var trade_group = escorts[0]
	trade_boat["pos"] = Vector2(8, 2)
	var update := Planner.plan_assignment_group_lifecycle(snapshot, 2, 2, {trade_group.group_id: trade_group})
	assert_equal(update.get("commands", []).map(func(command): return command.command_type()), ["attack_move"], "moving economic ship pulls its escort through the public attack-move pipeline")
	assert_equal(update.get("commands", [])[0].target, Vector2(8, 2), "escort follows the current anchor position")
	for unit in snapshot["units"]:
		if int(unit.get("id", -1)) in trade_group.member_ids:
			unit["pos"] = Vector2(8, 2)
			unit["task"] = "idle"
	var enemy := fighter(200, Vector2(9, 2), "water")
	enemy["team"] = 3
	snapshot["units"].append(enemy)
	update = Planner.plan_assignment_group_lifecycle(snapshot, 3, 2, {trade_group.group_id: trade_group})
	assert_equal(update.get("commands", []).map(func(command): return command.command_type()), ["attack"], "escort intercepts a water-compatible threat near its protected ship")
	assert_equal(trade_group.target_id, 200, "escort persists the exact intercepted target")
	enemy["hp"] = 0.0
	for unit in snapshot["units"]:
		if int(unit.get("id", -1)) in trade_group.member_ids:
			unit["task"] = "idle"
			unit["pos"] = Vector2(15, 2)
	update = Planner.plan_assignment_group_lifecycle(snapshot, 4, 2, {trade_group.group_id: trade_group})
	assert_equal(update.get("commands", []).map(func(command): return command.command_type()), ["attack_move"], "escort returns to the moving protected ship after combat")
	trade_boat["hp"] = 0.0
	update = Planner.plan_assignment_group_lifecycle(snapshot, 5, 2, {trade_group.group_id: trade_group})
	assert_equal(trade_group.state, AssignmentGroup.COMPLETE, "destroyed economic ship releases its escort")
	assert_equal(update.get("completed_group_ids", []), [int(trade_group.group_id)], "escort lifecycle reports the released group")


func snapshot_base() -> Dictionary:
	return {
		"observer_team": 2,
		"map_size": Vector2i(40, 40),
		"player_state": {"team": 2, "status": "active", "allies": [2]},
		"units": [],
		"buildings": [],
		"resources": [],
		"objectives": [],
		"navigation": {},
		"fog": {"cells": []},
	}


func contract_with(numbers: Array) -> Dictionary:
	return {"strategic_numbers": numbers, "target_markers": [], "build_order": [], "runtime_support": {"military_enabled": true}}


func fighter(id: int, position: Vector2, domain: String) -> Dictionary:
	return {"id": id, "team": 2, "kind": "war_galley" if domain == "water" else "clubman", "pos": position, "hp": 100.0, "task": "idle", "target_id": -1, "movement_domain": domain, "combat_enabled": true, "behavior_tags": ["combatant"], "components": {"worker": {"enabled": false}}}


func building(id: int, kind: String, position: Vector2, team: int) -> Dictionary:
	return {"id": id, "team": team, "kind": kind, "pos": position, "hp": 200.0, "movement_domain": "land", "target_domains": ["land", "water"]}


func economic_ship(id: int, kind: String, position: Vector2, tags: Array, worker_enabled: bool = false) -> Dictionary:
	return {"id": id, "team": 2, "kind": kind, "pos": position, "hp": 100.0, "task": "idle", "target_id": -1, "movement_domain": "water", "combat_enabled": false, "behavior_tags": tags, "components": {"worker": {"enabled": worker_enabled}}}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
