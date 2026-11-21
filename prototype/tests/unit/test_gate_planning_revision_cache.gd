extends SceneTree
const Registry := preload("res://scripts/player_registry.gd")
const Gates := preload("res://scripts/gate_system.gd")
class Owner extends RefCounted:
	var player_registry := Registry.new()
	var queries := 0
	func are_teams_allied(owner: int, traveller: int) -> bool:
		queries += 1
		return player_registry.are_allied(owner, traveller)
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var owner := Owner.new()
	var gates := Gates.new(owner)
	gates.gate_ids[10] = true
	var original: int = gates.planning_revision(1)
	var cold_queries := owner.queries
	for index in range(1000): check(gates.planning_revision(1) == original, "warm policy stays equal")
	check(cold_queries > 0 and owner.queries == cold_queries, "warm movement does not rebuild admission lists")
	owner.player_registry.set_relation(1, 2, Registry.ALLY)
	check(gates.planning_revision(1) == original, "traveller cannot grant itself passage")
	owner.player_registry.set_relation(2, 1, Registry.ALLY)
	var allied: int = gates.planning_revision(1)
	check(allied != original, "permission from a gate owner invalidates policy")
	var allied_queries := owner.queries
	owner.player_registry.set_relation(2, 1, Registry.ALLY)
	check(gates.planning_revision(1) == allied and owner.queries == allied_queries, "unchanged relation stays cached")
	owner.player_registry.relations = {1: {1: Registry.ALLY}, 2: {2: Registry.ALLY}}
	check(gates.planning_revision(1) == original, "checkpoint dictionary replacement invalidates policy")
	owner.player_registry.ensure(3)
	owner.player_registry.set_mutual_relation(1, 3, Registry.ALLY)
	check(gates.planning_revision(1) != original, "new allied player invalidates policy")
	owner.player_registry.reset_match()
	check(gates.planning_revision(1) == original, "match relation reset invalidates policy")
	gates.policy_revision += 1
	check(gates.planning_revision(1) != original, "gate lock policy invalidates revision")
	for team in range(100): gates.planning_revision(team)
	check(gates.planning_revisions.size() <= 64, "policy cache remains bounded")
	gates.reset()
	check(gates.planning_revisions.is_empty() and gates.planning_revision(1) == 0, "gate reset releases entries")
	for failure in failures: push_error(failure)
	print("Gate planning revision cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
