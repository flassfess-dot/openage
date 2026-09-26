extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const SupportPlanner := preload("res://scripts/ai_support_planner.gd")
const TacticalPlanner := preload("res://scripts/ai_tactical_planner.gd")
const TransportPlanner := preload("res://scripts/ai_transport_planner.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

var failures: Array[String] = []


func _initialize() -> void:
	verify_legal_snapshot_projection()
	verify_production_and_housing()
	verify_wartime_reinforcement()
	verify_repair_and_heal()
	verify_tribute_cadence()
	verify_attack_ground_safety()
	verify_stalled_attack_refresh()
	verify_allied_transport_and_objective()
	if failures.is_empty():
		print("P10 RoR AI rule-adaptation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_legal_snapshot_projection() -> void:
	var building := {"id": 20, "team": 2, "kind": "barracks", "pos": Vector2(4, 4), "hp": 200.0, "max_hp": 300.0, "production_queue": [{"order_type": "unit", "kind": "clubman", "population_cost": 1, "status": "blocked_population"}]}
	var own: Dictionary = SimulationSnapshot._compact_ai_entity(building, 2)
	var own_queue: Array = own.get("production_queue", [])
	assert_true(not own_queue.is_empty(), "AI sees its own production queue")
	if not own_queue.is_empty():
		assert_equal(String(own_queue[0].get("status", "")), "blocked_population", "AI sees its own population-blocked production status")
	assert_equal(float(own.get("max_hp", 0.0)), 300.0, "AI sees legal service-target health")
	var enemy: Dictionary = SimulationSnapshot._compact_ai_entity(building, 1)
	assert_true(not enemy.has("production_queue"), "enemy production queue remains private")


func verify_production_and_housing() -> void:
	var snapshot := base_snapshot()
	snapshot["buildings"] = [{
		"id": 20, "team": 2, "kind": "barracks", "pos": Vector2(4, 4), "hp": 300.0, "max_hp": 300.0, "state": "complete",
		"production_queue": [{"order_type": "unit", "kind": "clubman", "status": "queued", "population_points_cost": 2}],
		"command_options": {"train": [{"kind": "clubman", "accepted": true, "behavior_tags": ["combatant"]}, {"kind": "swordsman", "accepted": true, "behavior_tags": ["combatant"]}], "research": [{"technology_id": 123, "accepted": true}]},
	}]
	var commands := EconomicPlanner.plan(snapshot, 1, 2)
	assert_equal(commands.size(), 1, "occupied producer adds at most one homogeneous order")
	if not commands.is_empty():
		assert_equal(String(commands[0].command_type()), "train", "occupied producer does not start a competing research")
		assert_equal(String(commands[0].unit_type), "clubman", "occupied producer keeps its unit line")
	assert_true(EconomicPlanner._needs_housing({"population_points": 8, "population_cap": 5, "population_limit": 50}, 0, false, 2), "active two-point order triggers a House before it blocks")
	assert_true(not EconomicPlanner._needs_housing({"population_points": 8, "population_cap": 5, "population_limit": 50}, 0, false, 1), "Logistics one-point order does not request housing early")
	snapshot["player_state"].merge({"population_points": 8, "population_cap": 5, "population_limit": 50, "blocked_population_queues": 1}, true)
	snapshot["buildings"][0]["production_queue"][0]["status"] = "blocked_population"
	snapshot["units"] = [{"id": 10, "team": 2, "kind": "villager", "pos": Vector2(3, 3), "hp": 25.0, "max_hp": 25.0, "task": "idle", "movement_domain": "land", "components": {"worker": {"enabled": true}}, "command_options": {"build": [{"kind": "house", "accepted": true}]}}]
	snapshot["build_sites"] = {"house": [Vector2(6.5, 6.5)]}
	commands = EconomicPlanner.plan(snapshot, 2, 2, {"construction_priorities": ["house"], "building_limits": {"house": 2}})
	assert_true(not commands.is_empty() and String(commands[0].command_type()) == "build" and String(commands[0].building_type) == "house", "blocked population causes a legal House order")


func verify_wartime_reinforcement() -> void:
	var snapshot := base_snapshot()
	snapshot["player_state"].merge({"age": 100, "food": 100}, true)
	for worker_id in range(6):
		snapshot["units"].append({"id": worker_id + 1, "team": 2, "kind": "villager", "hp": 25.0, "task": "gather", "movement_domain": "land", "components": {"worker": {"enabled": true}}})
	for fighter_id in range(3):
		snapshot["units"].append({"id": fighter_id + 20, "team": 2, "kind": "clubman", "hp": 40.0, "task": "attack", "movement_domain": "land", "combat_enabled": true, "components": {"worker": {"enabled": false}}})
	snapshot["buildings"] = [
		{"id": 40, "team": 2, "kind": "town_center", "hp": 600.0, "state": "complete", "production_queue": [], "command_options": {"train": [], "research": [{"technology_id": 101, "accepted": false, "reason": "insufficient_resources", "cost": {0: 500}}]}},
		{"id": 41, "team": 2, "kind": "barracks", "hp": 300.0, "state": "complete", "production_queue": [], "command_options": {"train": [{"kind": "clubman", "accepted": true, "behavior_tags": ["combatant"], "cost": {0: 50}}], "research": []}},
	]
	var policy := {"minimum_workers_before_age_up": 6, "age_advance_technology_ids": [101]}
	assert_equal(EconomicPlanner.plan(snapshot, 1, 2, policy).size(), 0, "peaceful age saving still holds military production")
	policy["wartime_combatant_target"] = 6
	var commands := EconomicPlanner.plan(snapshot, 2, 2, policy)
	assert_true(not commands.is_empty() and String(commands[0].command_type()) == "train" and String(commands[0].unit_type) == "clubman", "age saving replenishes a depleted fighting group")


func verify_repair_and_heal() -> void:
	var snapshot := base_snapshot()
	snapshot["units"] = [
		{"id": 10, "team": 2, "kind": "villager", "pos": Vector2(2, 2), "hp": 25.0, "max_hp": 25.0, "task": "idle", "components": {"worker": {"enabled": true}}},
		{"id": 11, "team": 2, "kind": "priest", "pos": Vector2(3, 2), "hp": 25.0, "max_hp": 25.0, "task": "idle", "components": {"healing": {"enabled": true}}},
		{"id": 21, "team": 3, "kind": "clubman", "pos": Vector2(4, 2), "hp": 20.0, "max_hp": 40.0, "task": "idle"},
	]
	snapshot["buildings"] = [
		{"id": 20, "team": 3, "kind": "house", "pos": Vector2(3, 3), "hp": 40.0, "max_hp": 100.0, "state": "complete"},
		{"id": 99, "team": 4, "kind": "tower", "pos": Vector2(2, 3), "hp": 1.0, "max_hp": 100.0, "last_known": true},
	]
	var commands := SupportPlanner.plan(snapshot, 1, 2)
	assert_equal(commands.size(), 2, "support cadence emits one repair and one heal")
	if commands.size() == 2:
		assert_equal(String(commands[0].command_type()), "repair", "worker repairs an allied structure through a public command")
		assert_equal(int(commands[0].target_building_id), 20, "repair never targets hidden enemy state")
		assert_equal(String(commands[1].command_type()), "heal", "priest heals a damaged ally through a public command")
		assert_equal(int(commands[1].target_entity_id), 21, "healing chooses the visible injured ally")
	snapshot["resources"] = [{"id": 80, "kind": "berries", "pos": Vector2(2.5, 2), "amount": 100}]
	var coordinated: Array = AiPlayer.new({"team": 2}).collect_commands(snapshot, 1)
	assert_equal(coordinated.filter(func(command): return not command.unit_ids.is_empty() and int(command.unit_ids[0]) == 10).size(), 1, "repairing worker is not simultaneously reassigned to gathering")
	assert_equal(SupportPlanner.plan({"observer_team": 1}, 2, 2).size(), 0, "support planner rejects foreign knowledge")


func verify_tribute_cadence() -> void:
	var snapshot := base_snapshot()
	snapshot["player_state"].merge({"wood": 100, "food": 0, "stone": 0, "gold": 0}, true)
	var ai = AiPlayer.new({"team": 2, "ai": {"economic_interval_ticks": 1, "military_interval_ticks": 1000, "tribute_target_team": 3, "tribute_resource_type_id": 1, "tribute_amount": 20, "tribute_reserve": 50, "tribute_cooldown_ticks": 10}})
	var first: Array = ai.collect_commands(snapshot, 1)
	assert_equal(first.size(), 1, "explicit allied tribute policy issues one bounded command")
	if not first.is_empty():
		assert_equal(String(first[0].command_type()), "tribute", "tribute crosses the ordinary command pipeline")
		assert_equal(int(first[0].amount), 20, "tribute preserves the sender reserve")
	assert_equal(ai.collect_commands(snapshot, 2).size(), 0, "tribute cooldown prevents cadence spam")
	assert_equal(int(ai.canonical_state().get("last_tribute_tick", -1)), 1, "tribute cadence is saved canonically")
	var restored = AiPlayer.new({"team": 2, "ai": {"tribute_target_team": 3, "tribute_amount": 20}})
	assert_true(restored.restore_state(ai.canonical_state()), "tribute cadence restores from canonical AI state")
	assert_equal(int(restored.last_tribute_tick), 1, "restored AI keeps the tribute cooldown boundary")
	snapshot["player_state"]["allies"] = [2]
	assert_equal(ai.collect_commands(snapshot, 11).size(), 0, "AI never sends tribute after alliance ends")


func verify_attack_ground_safety() -> void:
	var snapshot := base_snapshot()
	snapshot["units"] = [
		{"id": 40, "team": 2, "kind": "catapult", "pos": Vector2(1, 1), "hp": 50.0, "task": "idle", "movement_domain": "land", "combat_enabled": true, "components": {"combat": {"projectile_id": 8, "blast_range": 2.0}}},
		{"id": 41, "team": 2, "kind": "clubman", "pos": Vector2(2, 1), "hp": 40.0, "task": "idle", "movement_domain": "land", "combat_enabled": true},
		{"id": 50, "team": 4, "kind": "clubman", "pos": Vector2(6, 6), "hp": 40.0},
		{"id": 51, "team": 4, "kind": "clubman", "pos": Vector2(6.5, 6), "hp": 40.0},
	]
	var goal := {"type": "attack", "target_id": 50, "position": Vector2(6, 6), "target_domain": "land", "target_domains": ["land"]}
	var commands := TacticalPlanner.plan(snapshot, 1, 2, goal)
	assert_equal(commands.size(), 2, "clustered visible enemies allow one artillery ground attack and one direct attack")
	if commands.size() == 2:
		assert_equal(String(commands[0].command_type()), "attack_ground", "splash unit uses public AttackGroundCommand")
		assert_equal(commands[0].unit_ids, [40], "only eligible artillery is assigned to ground fire")
		assert_equal(commands[1].unit_ids, [41], "other fighter keeps an ordinary attack order")
	snapshot["units"].append({"id": 52, "team": 3, "kind": "clubman", "pos": Vector2(6.2, 6), "hp": 40.0})
	commands = TacticalPlanner.plan(snapshot, 2, 2, goal)
	assert_equal(commands.size(), 1, "friendly unit near blast zone suppresses ground fire")
	if not commands.is_empty():
		assert_equal(String(commands[0].command_type()), "attack", "unsafe blast falls back to direct attack")
	snapshot["units"].pop_back()
	snapshot["units"][3]["last_known"] = true
	commands = TacticalPlanner.plan(snapshot, 3, 2, goal)
	assert_equal(commands.size(), 1, "remembered enemy never supplies splash-cluster evidence")


func verify_stalled_attack_refresh() -> void:
	var snapshot := base_snapshot()
	snapshot["units"] = [{"id": 40, "team": 2, "kind": "clubman", "pos": Vector2(4, 4), "hp": 40.0, "task": "attack", "target_id": 50, "diagnostic_reason": "local_obstacle", "movement_domain": "land", "combat_enabled": true, "components": {"worker": {"enabled": false}}}]
	snapshot["buildings"] = [{"id": 50, "team": 4, "kind": "town_center", "pos": Vector2(6, 6), "hp": 100.0}]
	var goal := {"type": "attack", "target_id": 50, "position": Vector2(6, 6), "target_domain": "land", "target_domains": ["land"]}
	assert_equal(TacticalPlanner.plan(snapshot, 1, 2, goal).size(), 0, "ordinary cadence does not repeatedly reissue active attacks")
	var commands := TacticalPlanner.plan(snapshot, 401, 2, goal, "RECTANGLE", 1, 10, false, {}, true)
	assert_true(commands.size() == 1 and String(commands[0].command_type()) == "attack" and commands[0].unit_ids == [40], "bounded refresh reissues a stalled public attack command")
	snapshot["buildings"][0]["last_known"] = true
	assert_equal(TacticalPlanner.plan(snapshot, 801, 2, goal, "RECTANGLE", 1, 10, false, {}, true).size(), 0, "stalled recovery never attacks a fogged target")


func verify_allied_transport_and_objective() -> void:
	var snapshot := base_snapshot()
	snapshot["units"] = [
		{"id": 60, "team": 2, "kind": "mission_unit", "scenario_object_id": 7, "pos": Vector2(3.2, 2.5), "hp": 20.0, "task": "idle", "movement_domain": "land", "footprint_radius": 0.3},
		{"id": 70, "team": 3, "kind": "transport", "pos": Vector2(2.5, 2.5), "hp": 100.0, "task": "idle", "movement_domain": "water", "footprint_radius": 0.75, "components": {"cargo": {"enabled": true, "capacity": 4, "count": 0, "allow_allied": true}}},
	]
	var goal := {"type": "attack", "target_domain": "land", "position": Vector2(12, 12)}
	var commands := TransportPlanner.plan(snapshot, 1, 2, goal)
	assert_equal(commands.size(), 1, "AI can board an owned objective into a visible allied transport")
	if not commands.is_empty():
		assert_equal(String(commands[0].command_type()), "board", "allied boarding uses public BoardCommand")
		assert_equal(commands[0].unit_ids, [60], "AI commands only its own passenger")
	snapshot["units"][1]["components"]["cargo"]["count"] = 4
	assert_equal(TransportPlanner.plan(snapshot, 2, 2, goal).size(), 0, "full allied cargo does not attract rejected board orders")
	snapshot["units"][1]["components"]["cargo"]["count"] = 0
	snapshot["player_state"]["mutual_allies"] = [2]
	assert_equal(TransportPlanner.plan(snapshot, 3, 2, goal).size(), 0, "one-way diplomacy cannot board a foreign transport")
	snapshot["player_state"]["mutual_allies"] = [2, 3]
	snapshot["units"][0] = {"id": 61, "team": 0, "kind": "artifact", "pos": Vector2(3.2, 2.5), "hp": 1.0, "movement_domain": "land", "footprint_radius": 0.3, "behavior_tags": ["capturable"]}
	commands = TransportPlanner.plan(snapshot, 4, 2, goal)
	assert_true(not commands.is_empty() and commands[0].unit_ids == [61], "visible capturable artifact can use a cargo-permitted transport")
	snapshot["units"][1]["components"]["cargo"]["allow_artifacts"] = false
	assert_equal(TransportPlanner.plan(snapshot, 5, 2, goal).size(), 0, "artifact policy forbids an otherwise legal boarding order")


func base_snapshot() -> Dictionary:
	return {"observer_team": 2, "map_size": Vector2i(24, 24), "player_state": {"team": 2, "allies": [2, 3], "mutual_allies": [2, 3], "relations": {3: "ally", 4: "enemy"}}, "units": [], "buildings": [], "resources": [], "navigation": {"land": [], "water": []}}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
