extends SceneTree
const Registry := preload("res://scripts/player_registry.gd")
const Gates := preload("res://scripts/gate_system.gd")
class Owner extends RefCounted:
	var player_registry := Registry.new()
	var queries := 0
	func get_allied_teams(team: int) -> Array[int]:
		queries += 1
		return player_registry.allied_teams(team)
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var owner := Owner.new()
	var gates := Gates.new(owner)
	gates.gate_ids[10] = true
	var original: int = gates.planning_revision(1)
	for index in range(1000): check(gates.planning_revision(1) == original, "warm policy stays equal")
	check(owner.queries == 1, "warm movement does not rebuild the alliance array")
	owner.player_registry.set_relation(1, 2, Registry.ALLY)
	var allied: int = gates.planning_revision(1)
	check(allied != original, "new alliance invalidates policy")
	owner.player_registry.set_relation(1, 2, Registry.ALLY)
	check(gates.planning_revision(1) == allied and owner.queries == 2, "unchanged relation stays cached")
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
