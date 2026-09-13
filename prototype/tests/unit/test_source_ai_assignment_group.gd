extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const AssignmentGroup := preload("res://scripts/source_ai_assignment_group.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_serialization_round_trip()
	test_defence_assignment_and_lifecycle()
	test_exploration_allocation_and_cap()
	test_ai_player_state_round_trip()
	if failures.is_empty():
		print("I12-020L source strategic assignment-group tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_serialization_round_trip() -> void:
	var first := fighter(3, Vector2(3, 3))
	first["attack_range"] = 1.0
	var second := fighter(1, Vector2(2, 2))
	second["attack_range"] = 4.0
	var group = AssignmentGroup.new(7, 2, AssignmentGroup.ESCORT, [first, second], Vector2(8, 8), 40)
	group.configure_commander([first, second], 2)
	group.anchor_id = 90
	group.anchor_kind = "escort_trade"
	group.objective_position = Vector2(9, 8)
	group.target_id = 100
	group.formation_name = "LINE"
	group.defence_distance = 3.0
	group.influence_radius = 10.0
	group.priority = 1
	group.transition(AssignmentGroup.ENGAGING, "test_transition", 41)
	var restored = AssignmentGroup.from_state(group.canonical_state())
	assert_equal(restored.canonical_state(), group.canonical_state(), "strategic assignment group survives dictionary round trip")
	assert_equal(restored.commander_id, 1, "assignment group persists its range-selected commander")


func test_defence_assignment_and_lifecycle() -> void:
	var snapshot := snapshot_base()
	snapshot["units"] = [
		fighter(1, Vector2(4, 5)), fighter(2, Vector2(5, 5)),
		fighter(3, Vector2(28, 5)), fighter(4, Vector2(29, 5)),
	]
	snapshot["buildings"] = [building(80, "town_center", Vector2(30, 5), 2)]
	snapshot["resources"] = [
		resource(90, "gold_mine", Vector2(5, 5), 3),
		resource(91, "gold_mine", Vector2(6, 5), 3),
	]
	var contract := contract_with([
		{"source_id": 25, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 28, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 38, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 50, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 56, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 57, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 22, "value": 12, "runtime_semantics": "implemented"},
		{"source_id": 92, "value": 10, "runtime_semantics": "implemented"},
	])
	var plan := Planner.plan_strategic_assignments(snapshot, 1, 2, contract, {})
	assert_equal(plan.get("groups", []).size(), 2, "source desired count creates two domain-safe defend groups")
	assert_equal(plan.get("groups", [])[0].anchor_id, 90, "priority 1 gold is selected before the town")
	assert_equal(plan.get("groups", [])[1].anchor_id, 80, "overlapping second gold is skipped before the next priority")
	assert_equal(plan.get("groups", [])[0].defence_distance, 3.0, "non-town anchor uses SNDefenseDistance")
	assert_equal(plan.get("groups", [])[1].defence_distance, 12.0, "town anchor uses SNSentryDefenseDistance")
	assert_true(plan.get("commands", []).is_empty(), "local defenders hold their existing positions without redundant path requests")

	var group = plan.get("groups", [])[0]
	var defended_members: Array = snapshot["units"].filter(func(unit): return int(unit.get("id", -1)) in group.member_ids)
	var first: Dictionary = defended_members[0]
	var second: Dictionary = defended_members[1]
	first["pos"] = Vector2(5, 5)
	second["pos"] = Vector2(5.5, 5)
	var intruder := fighter(100, Vector2(6, 5))
	intruder["team"] = 3
	snapshot["units"].append(intruder)
	var update := Planner.plan_assignment_group_lifecycle(snapshot, 2, 2, {group.group_id: group})
	assert_equal(update.get("commands", []).size(), 1, "defend group engages a visible enemy inside its source radius")
	assert_equal(update.get("commands", [])[0].command_type(), "attack", "defence interception uses the authoritative attack command")
	assert_equal(group.state, AssignmentGroup.ENGAGING, "defend group persists its engagement state")
	assert_equal(group.target_id, 100, "defend group persists the chosen target")
	snapshot["units"].erase(intruder)
	first["pos"] = Vector2(12, 5)
	second["pos"] = Vector2(13, 5)
	first["task"] = "idle"
	second["task"] = "idle"
	update = Planner.plan_assignment_group_lifecycle(snapshot, 3, 2, {group.group_id: group})
	assert_equal(update.get("commands", []).size(), 1, "defenders return to their anchor after the local threat disappears")
	assert_equal(update.get("commands", [])[0].command_type(), "formation_move", "defence return preserves the configured formation")
	assert_equal(group.state, AssignmentGroup.MOVING, "returning defenders remain reserved by their assignment lifecycle")


func test_exploration_allocation_and_cap() -> void:
	var snapshot := snapshot_base()
	snapshot["map_size"] = Vector2i(4, 4)
	snapshot["fog"] = {"cells": [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	snapshot["navigation"] = {"land": [Vector2(1.5, 1.5)], "water": []}
	snapshot["units"] = [
		worker(1, Vector2(0.5, 0.5)),
		worker(2, Vector2(0.5, 1.5)),
		fighter(3, Vector2(0.5, 2.5)),
		fighter(4, Vector2(0.5, 3.0)),
		fighter(5, Vector2(0.5, 3.5)),
	]
	var contract := contract_with([
		{"source_id": 18, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 35, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 42, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 43, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 44, "value": 3, "runtime_semantics": "implemented"},
	])
	var plan := Planner.plan_strategic_assignments(snapshot, 1, 2, contract, {})
	assert_equal(plan.get("groups", []).size(), 2, "total explorer cap counts one civilian and one soldier group")
	assert_equal(plan.get("groups", [])[0].anchor_kind, "civilian", "minimum civilian explorer is allocated first")
	assert_equal(plan.get("groups", [])[0].member_ids, [1], "civilian explorer selection is stable by entity ID")
	assert_equal(plan.get("groups", [])[1].anchor_kind, "soldier_group", "remaining explorer capacity becomes a soldier group")
	assert_equal(plan.get("groups", [])[1].member_ids, [3, 4, 5], "soldier group respects its source maximum")
	assert_equal(plan.get("commands", []).map(func(command): return command.command_type()), ["move", "attack_move"], "civilian and soldier explorers use role-safe public commands")
	var groups: Dictionary = {}
	for group in plan.get("groups", []):
		groups[int(group.group_id)] = group
	for unit in snapshot["units"]:
		if int(unit.get("id", -1)) in plan.get("unit_ids", []):
			unit["pos"] = Vector2(1.5, 1.5)
			unit["task"] = "idle"
	var update := Planner.plan_assignment_group_lifecycle(snapshot, 2, 2, groups)
	assert_true(update.get("completed_group_ids", []).size() == 2, "explorers complete when no different reachable fog frontier remains")
	assert_true(groups.values().all(func(group): return String(group.state) == AssignmentGroup.COMPLETE), "exhausted exploration groups release their members")


func test_ai_player_state_round_trip() -> void:
	var contract := contract_with([])
	var player = AiPlayer.new({"team": 2, "ai": {"profile": "source_campaign_v1"}, "source_ai": contract})
	player.next_source_assignment_group_id = 4
	player.source_assignment_groups[3] = AssignmentGroup.new(3, 2, AssignmentGroup.EXPLORE, [fighter(5, Vector2(2, 2))], Vector2(2, 2), 8)
	var state := player.canonical_state()
	var restored = AiPlayer.new({"team": 2, "ai": {"profile": "source_campaign_v1"}, "source_ai": contract})
	assert_true(restored.restore_state(state), "AI player accepts matching assignment state")
	assert_equal(restored.canonical_state(), state, "AI timers, attack groups and strategic assignments survive restore")


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
	return {"strategic_numbers": numbers, "target_markers": [], "build_order": [], "runtime_support": {"military_enabled": true, "defence_enabled": true, "exploration_enabled": true}}


func fighter(id: int, position: Vector2) -> Dictionary:
	return {"id": id, "team": 2, "kind": "clubman", "pos": position, "hp": 40.0, "task": "idle", "target_id": -1, "movement_domain": "land", "combat_enabled": true, "behavior_tags": ["combatant"], "components": {"worker": {"enabled": false}}}


func worker(id: int, position: Vector2) -> Dictionary:
	return {"id": id, "team": 2, "kind": "villager", "pos": position, "hp": 25.0, "task": "idle", "target_id": -1, "movement_domain": "land", "combat_enabled": false, "behavior_tags": [], "components": {"worker": {"enabled": true}}}


func building(id: int, kind: String, position: Vector2, team: int) -> Dictionary:
	return {"id": id, "team": team, "kind": kind, "pos": position, "hp": 200.0, "movement_domain": "land", "target_domains": ["land"]}


func resource(id: int, kind: String, position: Vector2, type_id: int) -> Dictionary:
	return {"id": id, "team": 0, "kind": kind, "pos": position, "amount": 500, "resource_type_id": type_id}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
