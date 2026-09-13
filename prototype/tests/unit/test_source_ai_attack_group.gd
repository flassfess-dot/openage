extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const AttackGroup := preload("res://scripts/source_ai_attack_group.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_serialization_round_trip()
	test_group_commander_selection_and_replacement()
	test_group_and_individual_retreat_thresholds()
	test_target_destroyed_policies()
	test_domain_safe_group_creation()
	test_group_fill_methods()
	test_gather_spacing_lifecycle()
	test_attack_coordination_modes()
	test_ai_player_state_round_trip()
	if failures.is_empty():
		print("I12-020L source attack-group lifecycle tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_serialization_round_trip() -> void:
	var group = AttackGroup.new(7, 2, [fighter(3, Vector2(3, 3)), fighter(1, Vector2(2, 2))], Vector2(18, 18), 90, Vector2(2.5, 2.5), "land", "LINE", 40)
	group.wave_id = 4
	group.order_type = "attack"
	group.fill_method = 1
	group.gather_spacing = 3.0
	group.coordination_mode = 2
	group.begin_individual_retreat(1)
	group.transition(AttackGroup.EXTERMINATING, "test_transition", 41)
	var restored = AttackGroup.from_state(group.canonical_state())
	assert_equal(restored.canonical_state(), group.canonical_state(), "attack-group state survives a complete dictionary round trip")


func test_group_commander_selection_and_replacement() -> void:
	var low_hp_long_range := fighter(1, Vector2(2, 2))
	low_hp_long_range["hp"] = 10.0
	low_hp_long_range["attack_range"] = 6.0
	var high_hp_short_range := fighter(2, Vector2(3, 2))
	high_hp_short_range["hp"] = 30.0
	high_hp_short_range["attack_range"] = 1.0
	var middle := fighter(3, Vector2(4, 2))
	middle["hp"] = 20.0
	middle["attack_range"] = 4.0
	var members := [low_hp_long_range, high_hp_short_range, middle]
	var group = AttackGroup.new(1, 2, members, Vector2(12, 12), -1, Vector2(3, 2), "land", "LINE", 1)
	group.configure_commander(members, 0)
	assert_equal(group.commander_id, 2, "commander method 0 selects the living member with most HP")
	group.configure_commander(members, 1)
	assert_equal(group.commander_id, 1, "commander method 1 selects the living member with fewest HP")
	group.configure_commander(members, 2)
	assert_equal(group.commander_id, 1, "commander method 2 selects the living member with most range")
	low_hp_long_range["hp"] = 0.0
	group.sync_members({1: low_hp_long_range, 2: high_hp_short_range, 3: middle}, 2)
	assert_equal(group.commander_id, 3, "commander is selected again by the same method only after the current commander dies")

	var snapshot := snapshot_base()
	snapshot["units"] = members
	low_hp_long_range["hp"] = 10.0
	var contract := contract_with([
		{"source_id": 16, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 26, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 46, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 75, "value": 2, "runtime_semantics": "implemented"},
	])
	contract["target_markers"] = [{"position": Vector2(12, 12)}]
	var plan := Planner.plan_military(snapshot, 3, 2, contract, -1, 0)
	assert_equal(plan.get("groups", [])[0].commander_id, 1, "planner applies SNGroupCommanderSelectionMethod when creating a source group")
	assert_equal(plan.get("groups", [])[0].commander_selection_method, 2, "source commander method enters canonical group state")


func test_group_and_individual_retreat_thresholds() -> void:
	var snapshot := snapshot_base()
	var first := fighter(1, Vector2(4, 4))
	var second := fighter(2, Vector2(5, 4))
	var group = AttackGroup.new(1, 2, [first, second], Vector2(12, 12), 90, Vector2(4.5, 4), "land", "LINE", 1)
	first["hp"] = 18.0
	snapshot["units"] = [first, second]
	snapshot["units"].append(enemy(90, Vector2(12, 12), 40.0))
	var groups := {1: group}
	var contract := contract_with([
		{"source_id": 30, "value": 25, "runtime_semantics": "implemented"},
		{"source_id": 31, "value": 100, "runtime_semantics": "implemented"},
		{"source_id": 91, "value": 100, "runtime_semantics": "implemented"},
		{"source_id": 49, "value": 1, "runtime_semantics": "implemented"},
	])
	var update := Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract, groups)
	assert_equal(update.get("commands", []).size(), 1, "group HP threshold emits one retreat command")
	assert_equal(update.get("commands", [])[0].command_type(), "formation_move", "whole group retreats through the shared formation command")
	assert_equal(group.state, AttackGroup.RETREATING, "group HP threshold enters RETREATING")

	var survivor := fighter(11, Vector2(4, 4))
	var dead := fighter(12, Vector2(5, 4))
	var death_group = AttackGroup.new(2, 2, [survivor, dead], Vector2(12, 12), 90, Vector2(4.5, 4), "land", "LINE", 1)
	snapshot["units"] = [survivor, enemy(90, Vector2(12, 12), 40.0)]
	contract = contract_with([
		{"source_id": 30, "value": 100, "runtime_semantics": "implemented"},
		{"source_id": 31, "value": 50, "runtime_semantics": "implemented"},
	])
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract, {2: death_group})
	assert_equal(death_group.state, AttackGroup.RETREATING, "death percentage is measured against the original roster")

	first = fighter(21, Vector2(4, 4))
	second = fighter(22, Vector2(5, 4))
	var individual_group = AttackGroup.new(3, 2, [first, second], Vector2(12, 12), 90, Vector2(4.5, 4), "land", "LINE", 1)
	first["hp"] = 3.0
	snapshot["units"] = [first, second, enemy(90, Vector2(12, 12), 40.0)]
	contract = contract_with([{"source_id": 91, "value": 90, "runtime_semantics": "implemented"}])
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract, {3: individual_group})
	assert_equal(update.get("commands", []).size(), 1, "individual threshold emits one non-conflicting withdrawal command")
	assert_equal(update.get("commands", [])[0].unit_ids, [21], "only the wounded member leaves the attack group")
	assert_equal(individual_group.active_member_ids, [22], "healthy member remains in the attack group")
	assert_equal(individual_group.retreating_member_ids, [21], "withdrawing member remains tracked until reaching rally")


func test_target_destroyed_policies() -> void:
	var dead_target := enemy(90, Vector2(12, 12), 0.0)
	var member := fighter(1, Vector2(10, 10))
	member["diagnostic_reason"] = "combat_complete:target_unavailable"
	var snapshot := snapshot_base()
	snapshot["units"] = [member, dead_target]

	var recenter = AttackGroup.new(1, 2, [member], Vector2(12, 12), 90, Vector2(2, 2), "land", "LINE", 1)
	var update := Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract_with([{"source_id": 49, "value": 0, "runtime_semantics": "implemented"}]), {1: recenter})
	assert_equal(update.get("commands", [])[0].command_type(), "formation_move", "policy 0 recenters instead of retreating")
	assert_equal(recenter.state, AttackGroup.RECENTERING, "policy 0 owns an explicit RECENTERING state")
	assert_equal(recenter.objective_position, member["pos"], "recenter anchor is the current group center")

	var replacement := enemy(91, Vector2(14, 12), 40.0)
	snapshot["units"] = [member, dead_target, replacement]
	var retarget = AttackGroup.new(2, 2, [member], Vector2(12, 12), 90, Vector2(2, 2), "land", "LINE", 1)
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract_with([{"source_id": 49, "value": 1, "runtime_semantics": "implemented"}]), {2: retarget})
	assert_equal(update.get("commands", [])[0].command_type(), "attack", "policy 1 attacks another visible compatible target")
	assert_equal(retarget.target_id, 91, "policy 1 remembers the replacement target")

	snapshot["units"] = [member, dead_target]
	var conditional_retreat = AttackGroup.new(3, 2, [member], Vector2(12, 12), 90, Vector2(2, 2), "land", "LINE", 1)
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract_with([{"source_id": 49, "value": 1, "runtime_semantics": "implemented"}]), {3: conditional_retreat})
	assert_equal(conditional_retreat.state, AttackGroup.RETREATING, "policy 1 retreats when no compatible visible target remains")

	var always_retreat = AttackGroup.new(4, 2, [member], Vector2(12, 12), 90, Vector2(2, 2), "land", "LINE", 1)
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract_with([{"source_id": 49, "value": 2, "runtime_semantics": "implemented"}]), {4: always_retreat})
	assert_equal(always_retreat.state, AttackGroup.RETREATING, "policy 2 always retreats after target destruction")

	var extermination = AttackGroup.new(5, 2, [member], Vector2(12, 12), 90, Vector2(2, 2), "land", "LINE", 1)
	snapshot["map_size"] = Vector2i(4, 4)
	snapshot["fog"] = {"cells": [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	snapshot["navigation"] = {"land": [Vector2(1.5, 1.5)], "water": []}
	update = Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract_with([{"source_id": 49, "value": 3, "runtime_semantics": "implemented"}]), {5: extermination})
	assert_equal(update.get("commands", [])[0].command_type(), "attack_move", "policy 3 advances toward a deterministic unexplored frontier")
	assert_equal(extermination.state, AttackGroup.EXTERMINATING, "policy 3 owns an explicit EXTERMINATING state")


func test_domain_safe_group_creation() -> void:
	var snapshot := snapshot_base()
	snapshot["units"] = [
		fighter(1, Vector2(2, 2), "land"), fighter(2, Vector2(3, 2), "water"),
		fighter(3, Vector2(4, 2), "land"), fighter(4, Vector2(5, 2), "water"),
	]
	var contract := contract_with([
		{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 26, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 58, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 59, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 60, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 46, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
	])
	contract["target_markers"] = [{"position": Vector2(12, 12)}]
	var plan := Planner.plan_military(snapshot, 1, 2, contract, -1, 0, {}, 10, "WEDGE")
	assert_equal(plan.get("groups", []).size(), 2, "mixed army becomes two persistent domain-safe groups")
	assert_equal(plan.get("groups", [])[0].member_ids, [1, 3], "first group contains only land combatants")
	assert_equal(plan.get("groups", [])[1].member_ids, [2, 4], "second group contains only naval combatants")
	assert_equal(plan.get("groups", [])[0].group_id, 10, "group IDs start at the caller-owned deterministic sequence")
	assert_equal(plan.get("groups", [])[1].group_id, 11, "group IDs advance without depending on object identity")

	var land_only_contract := contract.duplicate(true)
	land_only_contract["strategic_numbers"] = land_only_contract["strategic_numbers"].filter(func(entry): return int(entry.get("source_id", -1)) not in [58, 59, 60])
	plan = Planner.plan_military(snapshot, 1, 2, land_only_contract, -1, 0, {}, 15, "LINE")
	assert_equal(plan.get("groups", []).size(), 1, "land attack settings no longer commandeer idle warboats")
	assert_equal(plan.get("groups", [])[0].movement_domain, "land", "land-only source contract creates only land groups")

	snapshot["units"] = [
		fighter(1, Vector2(2, 2), "water"), fighter(2, Vector2(3, 2), "water"),
		fighter(3, Vector2(4, 2), "land"), fighter(4, Vector2(5, 2), "land"),
		enemy(90, Vector2(8, 2), 40.0),
	]
	contract["target_markers"] = []
	contract["strategic_numbers"] = contract["strategic_numbers"].map(func(entry):
		var copy: Dictionary = entry.duplicate(true)
		if int(copy.get("source_id", -1)) == 36:
			copy["value"] = 1
		return copy
	)
	plan = Planner.plan_military(snapshot, 1, 2, contract, -1, 0, {}, 20, "LINE")
	assert_equal(plan.get("groups", []).size(), 1, "one direct-target slot is not consumed by an incompatible domain")
	assert_equal(plan.get("groups", [])[0].member_ids, [3, 4], "direct attack chooses the first domain that can engage the visible target")


func test_group_fill_methods() -> void:
	var snapshot := snapshot_base()
	for entity_id in range(1, 9):
		snapshot["units"].append(fighter(entity_id, Vector2(entity_id, 2)))
	var base_numbers := [
		{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 26, "value": 4, "runtime_semantics": "implemented"},
		{"source_id": 36, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 46, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
	]
	var sequential_contract := contract_with(base_numbers + [{"source_id": 40, "value": 0, "runtime_semantics": "implemented"}])
	sequential_contract["target_markers"] = [{"position": Vector2(20, 20)}]
	var plan := Planner.plan_military(snapshot, 1, 2, sequential_contract, -1, 0)
	assert_equal(plan.get("groups", [])[0].member_ids, [1, 2, 3, 4], "fill method 0 completes the first group before opening the next")
	assert_equal(plan.get("groups", [])[1].member_ids, [5, 6, 7, 8], "fill method 0 preserves deterministic roster order")

	var level_contract := contract_with(base_numbers + [{"source_id": 40, "value": 1, "runtime_semantics": "implemented"}])
	level_contract["target_markers"] = [{"position": Vector2(20, 20)}]
	plan = Planner.plan_military(snapshot, 1, 2, level_contract, -1, 0)
	assert_equal(plan.get("groups", [])[0].member_ids, [1, 2, 5, 7], "fill method 1 opens minimum groups and then fills them levelly")
	assert_equal(plan.get("groups", [])[1].member_ids, [3, 4, 6, 8], "level fill remains stable and deterministic")


func test_gather_spacing_lifecycle() -> void:
	var snapshot := snapshot_base()
	var first := fighter(1, Vector2(2, 2))
	var second := fighter(2, Vector2(10, 2))
	snapshot["units"] = [first, second]
	var contract := contract_with([
		{"source_id": 16, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 26, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 41, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 46, "value": 1, "runtime_semantics": "implemented"},
		{"source_id": 47, "value": 0, "runtime_semantics": "implemented"},
		{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
	])
	contract["target_markers"] = [{"position": Vector2(20, 20)}]
	var plan := Planner.plan_military(snapshot, 1, 2, contract, -1, 0)
	var group = plan.get("groups", [])[0]
	assert_equal(plan.get("commands", []).size(), 1, "spread group receives only a rally command before attack")
	assert_equal(plan.get("commands", [])[0].command_type(), "move", "gathering uses the public movement command")
	assert_equal(group.state, AttackGroup.ASSEMBLING, "spread group persists in ASSEMBLING")
	first["pos"] = Vector2(5, 2)
	second["pos"] = Vector2(7, 2)
	var update := Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract, {group.group_id: group})
	assert_equal(update.get("commands", []).size(), 1, "gathered group is released in the same deterministic AI tick")
	assert_equal(update.get("commands", [])[0].command_type(), "attack_move", "released marker group resumes its intended attack order")
	assert_equal(group.state, AttackGroup.ATTACKING, "gathered group enters ATTACKING")


func test_attack_coordination_modes() -> void:
	var snapshot := snapshot_base()
	var units: Array = [
		fighter(1, Vector2(2, 2)), fighter(2, Vector2(3, 2)),
		fighter(3, Vector2(2, 4)), fighter(4, Vector2(8, 4)),
	]
	snapshot["units"] = units
	var contract := contract_with([])

	var independent_ready = attack_move_group(1, 1, [units[0], units[1]], Vector2(2.5, 2), AttackGroup.READY, 0)
	var independent_waiting = attack_move_group(2, 1, [units[2], units[3]], Vector2(5, 4), AttackGroup.ASSEMBLING, 0)
	independent_waiting.gather_spacing = 1.0
	var update := Planner.plan_attack_group_lifecycle(snapshot, 2, 2, contract, {1: independent_ready, 2: independent_waiting})
	assert_equal(update.get("commands", []).size(), 1, "coordination 0 releases a ready group without waiting for its neighbour")
	assert_equal(independent_ready.state, AttackGroup.ATTACKING, "coordination 0 launches the ready group")
	assert_equal(independent_waiting.state, AttackGroup.ASSEMBLING, "coordination 0 leaves the spread group gathering")

	var serial_first = attack_move_group(3, 2, [units[0]], units[0]["pos"], AttackGroup.READY, 1)
	var serial_second = attack_move_group(4, 2, [units[1]], units[1]["pos"], AttackGroup.READY, 1)
	var serial_groups := {3: serial_first, 4: serial_second}
	update = Planner.plan_attack_group_lifecycle(snapshot, 3, 2, contract, serial_groups)
	assert_equal(update.get("commands", []).size(), 1, "coordination 1 releases only one group at a time")
	assert_equal(serial_first.state, AttackGroup.ATTACKING, "coordination 1 deterministically starts the lowest group ID")
	assert_equal(serial_second.state, AttackGroup.READY, "coordination 1 holds the next group ready")
	serial_first.transition(AttackGroup.COMPLETE, "test_complete", 4)
	update = Planner.plan_attack_group_lifecycle(snapshot, 4, 2, contract, serial_groups)
	assert_equal(update.get("commands", []).size(), 1, "coordination 1 releases the queued group after the active group completes")
	assert_equal(serial_second.state, AttackGroup.ATTACKING, "serial queue advances without creating a replacement group")

	var wave_first = attack_move_group(5, 3, [units[0]], units[0]["pos"], AttackGroup.READY, 2)
	var wave_second = attack_move_group(6, 3, [units[3]], Vector2(4, 4), AttackGroup.ASSEMBLING, 2)
	wave_second.gather_spacing = 1.0
	var wave_groups := {5: wave_first, 6: wave_second}
	update = Planner.plan_attack_group_lifecycle(snapshot, 5, 2, contract, wave_groups)
	assert_equal(update.get("commands", []).size(), 0, "coordination 2 waits until every live group in the wave is ready")
	units[3]["pos"] = Vector2(4, 4)
	update = Planner.plan_attack_group_lifecycle(snapshot, 6, 2, contract, wave_groups)
	assert_equal(update.get("commands", []).size(), 2, "coordination 2 releases the complete wave together")
	assert_equal(wave_first.state, AttackGroup.ATTACKING, "first synchronized group launches")
	assert_equal(wave_second.state, AttackGroup.ATTACKING, "second synchronized group launches in the same tick")


func attack_move_group(id: int, wave: int, members: Array, rally: Vector2, initial_state: String, coordination: int):
	var group = AttackGroup.new(id, 2, members, Vector2(20, 20), -1, rally, "land", "LINE", 1)
	group.wave_id = wave
	group.order_type = "attack_move"
	group.state = initial_state
	group.coordination_mode = coordination
	return group


func test_ai_player_state_round_trip() -> void:
	var contract := contract_with([])
	var player = AiPlayer.new({"team": 2, "ai": {"profile": "source_campaign_v1"}, "source_ai": contract})
	player.last_attack_tick = 8
	player.next_source_attack_group_id = 3
	player.source_attack_groups[2] = AttackGroup.new(2, 2, [fighter(5, Vector2(2, 2))], Vector2(8, 8), -1, Vector2(2, 2), "land", "LINE", 8)
	var state := player.canonical_state()
	var restored = AiPlayer.new({"team": 2, "ai": {"profile": "source_campaign_v1"}, "source_ai": contract})
	assert_true(restored.restore_state(state), "AI player accepts matching serialized state")
	assert_equal(restored.canonical_state(), state, "AI timers and attack groups survive restore")


func snapshot_base() -> Dictionary:
	return {
		"observer_team": 2,
		"map_size": Vector2i(24, 24),
		"player_state": {"team": 2, "allies": [2]},
		"units": [],
		"buildings": [],
		"resources": [],
		"navigation": {},
		"fog": {"cells": []},
	}


func contract_with(numbers: Array) -> Dictionary:
	return {"strategic_numbers": numbers, "target_markers": [], "build_order": [], "runtime_support": {"military_enabled": true, "attack_enabled": true}}


func fighter(id: int, position: Vector2, domain: String = "land") -> Dictionary:
	return {"id": id, "team": 2, "kind": "clubman", "pos": position, "hp": 40.0, "task": "idle", "target_id": -1, "diagnostic_reason": "", "movement_domain": domain, "combat_enabled": true, "behavior_tags": ["combatant"], "components": {"worker": {"enabled": false}}}


func enemy(id: int, position: Vector2, hp: float) -> Dictionary:
	var result := fighter(id, position)
	result["team"] = 1
	result["hp"] = hp
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
