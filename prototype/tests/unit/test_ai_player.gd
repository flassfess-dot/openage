extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const StrategicPlanner := preload("res://scripts/ai_strategic_planner.gd")
const TacticalPlanner := preload("res://scripts/ai_tactical_planner.gd")
const TransportPlanner := preload("res://scripts/ai_transport_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var player = AiPlayer.new({"team": 2, "ai": {"economic_interval_ticks": 5, "military_interval_ticks": 5, "formation": "WEDGE"}})
	assert_true(player.needs_decision(1), "new AI requests its initial decision snapshot")
	var hidden_snapshot := snapshot_base()
	hidden_snapshot["units"] = [fighter(20, 2, Vector2(4, 4))]
	var hidden_commands: Array = player.collect_commands(hidden_snapshot, 1)
	assert_true(not player.needs_decision(2), "AI does not request an expensive snapshot between decision ticks")
	assert_true(player.needs_decision(6), "AI requests a new snapshot when its interval elapses")
	var disabled_player = AiPlayer.new({"team": 3, "ai": {"enabled": false}})
	assert_true(not disabled_player.needs_decision(1), "data-driven disabled AI never requests a planning snapshot")
	assert_equal(disabled_player.collect_commands(hidden_snapshot, 1).size(), 0, "data-driven disabled AI never emits guessed commands")
	assert_equal(hidden_commands.size(), 1, "AI explores when no legal enemy is visible")
	assert_equal(hidden_commands[0].command_type(), "attack_move", "exploration uses public attack-move command")
	assert_equal(player.collect_commands(hidden_snapshot, 1).size(), 0, "same simulation tick never emits duplicate AI decisions")
	assert_equal(player.collect_commands({"observer_team": 1}, 6).size(), 0, "AI rejects a foreign observer snapshot")

	var visible_snapshot := snapshot_base()
	visible_snapshot["units"] = [
		fighter(20, 2, Vector2(4, 4)),
		fighter(21, 2, Vector2(4, 5)),
		fighter(30, 3, Vector2(5, 4)),
		fighter(10, 1, Vector2(7, 4)),
	]
	var goal := StrategicPlanner.choose_goal(visible_snapshot, 2, 0)
	assert_equal(goal.get("target_id"), 10, "strategic layer ignores visible ally and targets visible enemy")
	var combat_player = AiPlayer.new({"team": 2})
	var combat_commands: Array = combat_player.collect_commands(visible_snapshot, 1)
	assert_equal(combat_commands[0].command_type(), "attack", "multiple fighters issue an explicit group attack instead of stopping at the target position")
	assert_equal(combat_commands[0].unit_ids, [20, 21], "group attack preserves deterministic fighter order")

	var economy_snapshot := snapshot_base()
	economy_snapshot["units"] = [worker(40, 2, Vector2(3, 3))]
	economy_snapshot["resources"] = [{"id": 80, "kind": "berries", "pos": Vector2(4, 3), "amount": 100}]
	var economy_player = AiPlayer.new({"team": 2})
	var economy_commands: Array = economy_player.collect_commands(economy_snapshot, 1)
	assert_equal(economy_commands.size(), 1, "economic layer assigns visible work without military units")
	assert_equal(economy_commands[0].command_type(), "gather", "economic layer uses public gather command")
	assert_equal(economy_commands[0].resource_id, 80, "economic layer can only choose resource present in snapshot")
	var recovery_economy_snapshot := snapshot_base()
	var blocked_worker := worker(45, 2, Vector2(3, 3))
	blocked_worker["diagnostic_reason"] = "no_path"
	recovery_economy_snapshot["units"] = [blocked_worker, worker(46, 2, Vector2(7, 3))]
	recovery_economy_snapshot["resources"] = [{"id": 81, "kind": "berries", "pos": Vector2(3.5, 3), "amount": 100}]
	var recovery_economy_commands := EconomicPlanner.plan(recovery_economy_snapshot, 2, 2)
	assert_equal(recovery_economy_commands[0].unit_ids, [46], "a failed nearest route cannot starve another healthy idle worker")

	var resume_snapshot := snapshot_base()
	resume_snapshot["units"] = [worker(41, 2, Vector2(3, 3))]
	resume_snapshot["buildings"] = [{"id": 90, "team": 2, "kind": "barracks", "pos": Vector2(5, 3), "hp": 20.0, "state": "foundation", "production_queue": []}]
	var resume_commands := EconomicPlanner.plan(resume_snapshot, 2, 2, {"construction_priorities": ["house", "barracks"]})
	assert_equal(resume_commands.size(), 1, "economic policy resumes an existing foundation before placing another building")
	assert_equal(resume_commands[0].command_type(), "build", "foundation recovery uses the ordinary public build command")
	assert_equal(resume_commands[0].target, Vector2(5, 3), "foundation recovery targets the existing site exactly")
	resume_snapshot["buildings"][0]["builder_count"] = 1
	assert_equal(EconomicPlanner.plan(resume_snapshot, 3, 2, {"construction_priorities": ["house", "barracks"]}).size(), 0, "economic policy does not spam a foundation that already has an active builder")
	var reachable_resume := snapshot_base()
	reachable_resume["units"] = [worker(43, 2, Vector2(3, 3)), worker(44, 2, Vector2(8, 3))]
	reachable_resume["buildings"] = [{"id": 94, "team": 2, "kind": "house", "pos": Vector2(6, 3), "hp": 7.5, "state": "foundation", "builder_count": 0, "reachable_builder_ids": [44], "production_queue": []}]
	var reachable_resume_commands := EconomicPlanner.plan(reachable_resume, 3, 2, {"construction_priorities": ["house"]})
	assert_equal(reachable_resume_commands.size(), 1, "foundation recovery waits for an authoritatively reachable builder")
	assert_equal(reachable_resume_commands[0].unit_ids, [44], "foundation recovery does not repeatedly assign a blocked nearer worker")

	var spaced_snapshot := snapshot_base()
	var spaced_worker := worker(42, 2, Vector2(5, 7))
	spaced_worker["command_options"] = {"build": [{"kind": "house", "accepted": true, "footprint_radius": 1.0}]}
	spaced_snapshot["units"] = [spaced_worker]
	spaced_snapshot["buildings"] = [{"id": 91, "team": 2, "kind": "town_center", "pos": Vector2(5, 5), "hp": 600.0, "state": "complete", "footprint_radius": 1.0, "production_queue": [], "command_options": {"train": [], "research": []}}]
	spaced_snapshot["build_sites"] = {"house": [Vector2(6.5, 5), Vector2(9, 5)]}
	var spaced_commands := EconomicPlanner.plan(spaced_snapshot, 4, 2, {"construction_priorities": ["house"], "building_limits": {"house": 1}, "minimum_structure_gap": 1.0})
	assert_equal(spaced_commands.size(), 1, "economic policy finds a construction site outside the protected navigation lane")
	assert_equal(spaced_commands[0].target, Vector2(9, 5), "economic policy rejects a site that packs structures too tightly")
	spaced_snapshot["build_sites"] = {"house": [Vector2(6.5, 5)]}
	var compact_house_commands := EconomicPlanner.plan(spaced_snapshot, 5, 2, {"construction_priorities": ["house"], "building_limits": {"house": 1}, "minimum_structure_gap": 1.0, "structure_gap_fallback_kinds": ["house"]})
	assert_equal(compact_house_commands.size(), 1, "critical housing uses a legal compact fallback when no gap-preserving site exists")
	assert_equal(compact_house_commands[0].target, Vector2(6.5, 5), "compact housing fallback remains deterministic")

	var saving_snapshot := snapshot_base()
	for worker_id in range(100, 106):
		saving_snapshot["units"].append(worker(worker_id, 2, Vector2(worker_id - 96, 4)))
	saving_snapshot["player_state"]["age"] = 100
	saving_snapshot["buildings"] = [
		{"id": 92, "team": 2, "kind": "town_center", "pos": Vector2(4, 4), "hp": 600.0, "state": "complete", "production_queue": [], "command_options": {"train": [train_option("villager", ["worker"], {0: 50})], "research": [{"technology_id": 101, "accepted": false, "reason": "insufficient_resources", "cost": {0: 500}}]}},
		{"id": 93, "team": 2, "kind": "barracks", "pos": Vector2(8, 4), "hp": 350.0, "state": "complete", "production_queue": [], "command_options": {"train": [train_option("clubman", ["combatant"])], "research": []}},
	]
	var age_policy := {"minimum_workers_before_age_up": 6, "age_advance_technology_ids": [101, 102, 103], "worker_target": 8, "construction_priorities": ["dock"], "building_limits": {"dock": 1}, "age_saving_construction_exceptions": ["dock"], "age_saving_production_exceptions": ["scout_ship"]}
	assert_equal(EconomicPlanner.plan(saving_snapshot, 5, 2, age_policy).size(), 0, "economic policy saves resources instead of continuously training through an age-up target")
	saving_snapshot["units"][0]["command_options"] = {"build": [{"kind": "dock", "accepted": true, "cost": {1: 150}}]}
	saving_snapshot["build_sites"] = {"dock": [Vector2(3.5, 8.5)]}
	var saving_build_commands := EconomicPlanner.plan(saving_snapshot, 6, 2, age_policy)
	assert_equal(saving_build_commands.size(), 1, "age saving permits declared economic infrastructure that avoids the reserved resource")
	assert_equal(saving_build_commands[0].command_type(), "build", "age-saving infrastructure uses the public build pipeline")
	assert_equal(String(saving_build_commands[0].building_type), "dock", "naval economy can bootstrap before the next age")
	saving_snapshot["units"][0].erase("command_options")
	saving_snapshot.erase("build_sites")
	var saving_dock := {"id": 94, "team": 2, "kind": "dock", "pos": Vector2(4, 8), "hp": 350.0, "state": "complete", "production_queue": [], "command_options": {"train": [train_option("fishing_boat", ["worker", "naval"], {1: 50})], "research": []}}
	saving_snapshot["buildings"].append(saving_dock)
	saving_snapshot["resources"] = [{"id": 95, "kind": "deep_fish", "pos": Vector2(4, 10), "amount": 250, "resource_type_id": 0, "allowed_gatherer_domains": ["water"]}]
	var saving_naval_commands := EconomicPlanner.plan(saving_snapshot, 7, 2, age_policy)
	assert_equal(saving_naval_commands.size(), 1, "age saving still permits an economic unit that does not spend the reserved resource")
	assert_equal(saving_naval_commands[0].command_type(), "train", "economic exception remains inside the public production pipeline")
	assert_equal(String(saving_naval_commands[0].unit_type), "fishing_boat", "Dock can bootstrap food income while land economy saves for the next age")
	saving_dock["command_options"]["train"] = [train_option("scout_ship", ["combatant", "naval"], {1: 135})]
	saving_snapshot["resources"].clear()
	var saving_scout_commands := EconomicPlanner.plan(saving_snapshot, 8, 2, age_policy)
	assert_equal(saving_scout_commands.size(), 1, "declared naval scout can launch while food remains reserved for the next age")
	assert_equal(String(saving_scout_commands[0].unit_type), "scout_ship", "age-saving production exception remains kind-specific")
	saving_snapshot["buildings"].pop_back()
	saving_snapshot["buildings"][0]["command_options"]["research"][0] = {"technology_id": 101, "accepted": true, "reason": ""}
	var age_commands := EconomicPlanner.plan(saving_snapshot, 9, 2, age_policy)
	assert_equal(age_commands.size(), 1, "economic policy reserves one decision for the age advance")
	assert_equal(age_commands[0].command_type(), "research", "age advance uses the ordinary public research command")

	var fishing_snapshot := snapshot_base()
	fishing_snapshot["units"] = [worker(50, 2, Vector2(2, 8), "water")]
	fishing_snapshot["resources"] = [
		{"id": 81, "kind": "berries", "pos": Vector2(2.2, 8), "amount": 100, "allowed_gatherer_domains": ["land"]},
		{"id": 82, "kind": "deep_fish", "pos": Vector2(3.5, 8), "amount": 250, "allowed_gatherer_domains": ["water"]},
	]
	var fishing_commands: Array = AiPlayer.new({"team": 2}).collect_commands(fishing_snapshot, 1)
	assert_equal(fishing_commands[0].resource_id, 82, "economic AI assigns Fishing Boat only to a domain-compatible fish resource")

	var naval_snapshot := snapshot_base()
	naval_snapshot["units"] = [
		fighter(60, 2, Vector2(3, 8), "water"),
		fighter(61, 2, Vector2(3, 9), "water"),
		fighter(62, 2, Vector2(8, 8), "land"),
		fighter(9, 1, Vector2(5, 8), "water"),
		fighter(10, 1, Vector2(10, 8), "land"),
	]
	var naval_commands: Array = AiPlayer.new({"team": 2}).collect_commands(naval_snapshot, 1)
	assert_equal(naval_commands.size(), 1, "tactical AI does not mix land and naval groups against one target")
	assert_equal(naval_commands[0].command_type(), "attack", "multiple warships explicitly attack their visible naval target")
	assert_equal(naval_commands[0].unit_ids, [60, 61], "only the movement-domain-compatible naval group receives the order")

	var dock_target_snapshot := snapshot_base()
	dock_target_snapshot["units"] = [fighter(63, 2, Vector2(4, 8), "land"), fighter(64, 2, Vector2(2, 8), "water")]
	dock_target_snapshot["buildings"] = [{"id": 12, "team": 1, "kind": "dock", "entity_type": "building", "pos": Vector2(2.5, 12.5), "hp": 350.0, "target_domains": ["land", "water"]}]
	var dock_goal := StrategicPlanner.choose_goal(dock_target_snapshot, 2, 0)
	assert_equal(dock_goal.get("target_domains"), ["land", "water"], "strategic goal retains every domain from which a shoreline Dock can be attacked")
	var dock_attack_commands := TacticalPlanner.plan(dock_target_snapshot, 1, 2, dock_goal)
	assert_equal(dock_attack_commands.size(), 2, "land and naval groups can attack the same mixed-domain Dock")
	assert_true(dock_attack_commands.all(func(command): return command.command_type() == "attack"), "mixed-domain building assault uses public attack commands")

	var naval_explore := snapshot_base()
	naval_explore["units"] = [fighter(70, 2, Vector2(2, 12), "water")]
	naval_explore["navigation"] = {"land": [], "water": [Vector2(1.5, 12.5), Vector2(2.5, 12.5)]}
	var naval_explore_commands: Array = AiPlayer.new({"team": 2}).collect_commands(naval_explore, 1)
	assert_equal(naval_explore_commands[0].command_type(), "attack_move", "naval exploration uses a public attack-move command")
	assert_true(naval_explore_commands[0].target in naval_explore["navigation"]["water"], "naval exploration target comes only from explored water knowledge")
	var group_explore := snapshot_base()
	group_explore["units"] = [fighter(71, 2, Vector2(4, 4)), fighter(72, 2, Vector2(4, 5)), fighter(73, 2, Vector2(5, 4))]
	group_explore["navigation"] = {"land": [Vector2(8.5, 4.5)], "water": []}
	var group_goal := StrategicPlanner.choose_goal(group_explore, 2, 0)
	var group_explore_commands := TacticalPlanner.plan(group_explore, 1, 2, group_goal, "WEDGE")
	assert_equal(group_explore_commands.size(), 1, "one exploration group receives one shared route")
	assert_equal(group_explore_commands[0].command_type(), "formation_move", "multi-unit exploration uses formation slots instead of crowding one attack-move destination")
	assert_equal(group_explore_commands[0].formation, "WEDGE", "exploration preserves the selected formation")
	var frontier_snapshot := snapshot_base()
	frontier_snapshot["units"] = [fighter(74, 2, Vector2(4, 4))]
	frontier_snapshot["navigation"] = {
		"land": [Vector2(3.5, 3.5), Vector2(4.5, 4.5), Vector2(10.5, 10.5)],
		"water": [],
		"frontier": {"land": [Vector2(10.5, 10.5), Vector2(1.5, 1.5)], "water": []},
	}
	var frontier_goal := StrategicPlanner.choose_goal(frontier_snapshot, 2, 0)
	assert_equal(frontier_goal.get("position"), Vector2(10.5, 10.5), "skirmish exploration advances toward the farthest known fog frontier")
	frontier_snapshot["navigation"]["reachable"] = {"land": [Vector2(3.5, 3.5), Vector2(4.5, 4.5)], "water": []}
	frontier_snapshot["navigation"]["reachable_frontier"] = {"land": [Vector2(3.5, 3.5)], "water": []}
	var island_goal := StrategicPlanner.choose_goal(frontier_snapshot, 2, 0)
	assert_equal(island_goal.get("position"), Vector2(3.5, 3.5), "land exploration never targets a visible but disconnected island")

	var dock_build_snapshot := snapshot_base()
	var dock_worker := worker(75, 2, Vector2(4, 10))
	dock_worker["task"] = "gather"
	dock_worker["command_options"] = {"build": [{"kind": "dock", "accepted": true}]}
	dock_build_snapshot["units"] = [dock_worker]
	dock_build_snapshot["build_sites"] = {"dock": [Vector2(2.5, 10.5)]}
	var dock_commands: Array = AiPlayer.new({"team": 2}).collect_commands(dock_build_snapshot, 1)
	assert_equal(dock_commands.size(), 1, "economic AI can reassign one gathering worker to an authoritative shoreline build order")
	assert_equal(dock_commands[0].command_type(), "build", "economic AI builds Dock through public BuildCommand")
	assert_equal(dock_commands[0].building_type, "dock", "mixed-domain build site selects Dock")
	assert_equal(dock_commands[0].target, Vector2(2.5, 10.5), "AI uses only authoritative explored placement candidate")

	test_fleet_production_and_trade_routes()
	test_transport_planner_phases()
	test_skirmish_policy_attack_control()

	if failures.is_empty():
		print("I11-004 legal-knowledge AI player tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func snapshot_base() -> Dictionary:
	return {
		"observer_team": 2,
		"map_size": Vector2i(24, 24),
		"player_state": {"team": 2, "allies": [2, 3]},
		"units": [],
		"buildings": [],
		"resources": [],
	}


func test_fleet_production_and_trade_routes() -> void:
	var fleet_snapshot := snapshot_base()
	fleet_snapshot["resources"] = [{"id": 180, "kind": "whale", "pos": Vector2(2.5, 12.5), "amount": 250, "resource_type_id": 0, "allowed_gatherer_domains": ["water"]}]
	fleet_snapshot["buildings"] = [{
		"id": 190, "team": 2, "kind": "dock", "pos": Vector2(2.5, 10.5), "hp": 350.0, "state": "complete", "production_queue": [], "trade": {"trade_goods": 20},
		"command_options": {"train": [
			train_option("fishing_boat", ["worker", "naval"]),
			train_option("trade_boat", ["trader", "naval"]),
			train_option("scout_ship", ["combatant", "naval"]),
			train_option("transport", ["transport", "naval"]),
		], "research": []},
	}]
	var commands := EconomicPlanner.plan(fleet_snapshot, 1, 2)
	var train: Variant = first_command_of_type(commands, "train")
	assert_true(train != null and String(train.unit_type) == "fishing_boat", "Dock prioritizes a water worker while known fish is unserved")

	var first_boat := worker(191, 2, Vector2(2.5, 9.5), "water")
	var second_boat := worker(192, 2, Vector2(2.5, 11.5), "water")
	first_boat["task"] = "gather"
	second_boat["task"] = "gather"
	fleet_snapshot["units"] = [first_boat, second_boat]
	var fishing_only := fleet_snapshot.duplicate(true)
	fishing_only["buildings"][0]["command_options"]["train"] = [train_option("fishing_boat", ["worker", "naval"])]
	assert_equal(first_command_of_type(EconomicPlanner.plan(fishing_only, 2, 2), "train"), null, "Dock does not replace an unavailable fleet class with surplus Fishing Boats")
	fleet_snapshot["buildings"].append({"id": 193, "team": 1, "kind": "dock", "pos": Vector2(2.5, 20.5), "hp": 350.0, "state": "complete", "trade": {"trade_goods": 40}})
	commands = EconomicPlanner.plan(fleet_snapshot, 2, 2)
	train = first_command_of_type(commands, "train")
	assert_true(train != null and String(train.unit_type) == "trade_boat", "Dock adds a trader when a foreign Dock is known")

	var trader := {"id": 194, "team": 2, "kind": "trade_boat", "pos": Vector2(2.5, 9.5), "hp": 200.0, "task": "idle", "movement_domain": "water", "components": {"worker": {"enabled": false}, "trade": {"enabled": true, "selected_input_resource_type_id": 1}}}
	fleet_snapshot["units"].append(trader)
	fleet_snapshot["player_state"].merge({"food": 40, "wood": 80, "stone": 200}, true)
	commands = EconomicPlanner.plan(fleet_snapshot, 3, 2)
	assert_true(first_command_of_type(commands, "set_trade_resource") != null, "economic AI selects its richest valid trade input through a public command")
	var route: Variant = first_command_of_type(commands, "trade")
	assert_true(route != null and int(route.target_dock_id) == 193, "economic AI starts a route only to a known foreign Dock")


func test_transport_planner_phases() -> void:
	var goal := {"type": "attack", "target_domain": "land", "position": Vector2(10.5, 10.5), "target_id": 300}
	var boarding := snapshot_base()
	boarding["navigation"] = {"land": [Vector2(3.5, 2.5), Vector2(10.5, 10.5)], "water": [Vector2(2.5, 2.5), Vector2(9.5, 10.5)]}
	boarding["units"] = [transport(200, Vector2(2.5, 2.5), []), fighter(201, 2, Vector2(3.4, 2.5)), fighter(202, 2, Vector2(3.5, 2.8))]
	var commands := TransportPlanner.plan(boarding, 4, 2, goal, "LINE")
	assert_equal(commands.size(), 1, "one transport emits one phase command")
	assert_equal(commands[0].command_type(), "board", "nearby land combatants board through public BoardCommand")
	assert_equal(commands[0].unit_ids, [201, 202], "boarding preserves deterministic passenger order")

	var staging := boarding.duplicate(true)
	staging["units"] = [transport(200, Vector2(2.5, 2.5), []), fighter(203, 2, Vector2(8.5, 8.5))]
	commands = TransportPlanner.plan(staging, 5, 2, goal, "LINE")
	assert_equal(commands[0].command_type(), "formation_move", "distant passengers first stage at a known coast")
	assert_equal(commands[0].target, Vector2(3.5, 2.5), "staging point comes from observer-known land navigation")

	var sailing := boarding.duplicate(true)
	sailing["units"] = [transport(200, Vector2(2.5, 2.5), [201])]
	commands = TransportPlanner.plan(sailing, 6, 2, goal, "LINE")
	assert_equal(commands[0].command_type(), "move", "loaded transport sails before attempting unload")
	assert_equal(commands[0].target, Vector2(9.5, 10.5), "sailing approach comes from known water adjacent to target coast")

	var landing := boarding.duplicate(true)
	landing["units"] = [transport(200, Vector2(9.5, 10.5), [201])]
	commands = TransportPlanner.plan(landing, 7, 2, goal, "LINE")
	assert_equal(commands[0].command_type(), "unload", "transport unloads only after reaching the target coast")
	assert_equal(commands[0].target, Vector2(10.5, 10.5), "landing target stays on known land")


func test_skirmish_policy_attack_control() -> void:
	var policy := {
		"enabled": true,
		"profile": "skirmish_policy_v1",
		"economic_interval_ticks": 1,
		"military_interval_ticks": 1,
		"initial_attack_delay_ticks": 10,
		"attack_separation_ticks": 8,
		"minimum_attack_group_size": 3,
		"maximum_attack_group_size": 3,
		"enemy_response_distance": 2.0,
	}
	var distant := snapshot_base()
	distant["units"] = [
		fighter(20, 2, Vector2(4, 4)),
		fighter(21, 2, Vector2(4, 5)),
		fighter(22, 2, Vector2(5, 4)),
		fighter(10, 1, Vector2(20, 20)),
	]
	var delayed_player = AiPlayer.new({"team": 2, "ai": policy})
	assert_equal(delayed_player.collect_commands(distant, 1).size(), 0, "skirmish AI respects its initial attack delay")
	var released: Array = delayed_player.collect_commands(distant, 10)
	assert_equal(released.size(), 1, "skirmish AI attacks after its initial delay")
	assert_equal(released[0].unit_ids, [20, 21, 22], "eligible attack group is deterministic")
	assert_equal(delayed_player.collect_commands(distant, 11).size(), 0, "skirmish AI respects separation between attack orders")

	var understrength := distant.duplicate(true)
	understrength["units"] = [fighter(20, 2, Vector2(4, 4)), fighter(21, 2, Vector2(4, 5)), fighter(10, 1, Vector2(20, 20))]
	var immediate_policy := policy.duplicate(true)
	immediate_policy["initial_attack_delay_ticks"] = 0
	var understrength_player = AiPlayer.new({"team": 2, "ai": immediate_policy})
	assert_equal(understrength_player.collect_commands(understrength, 1).size(), 0, "undersized groups wait instead of trickling into combat")

	var capped := distant.duplicate(true)
	capped["units"].insert(3, fighter(23, 2, Vector2(5, 5)))
	var capped_policy := immediate_policy.duplicate(true)
	capped_policy["minimum_attack_group_size"] = 1
	capped_policy["maximum_attack_group_size"] = 2
	var capped_commands: Array = AiPlayer.new({"team": 2, "ai": capped_policy}).collect_commands(capped, 1)
	assert_equal(capped_commands[0].unit_ids, [20, 21], "oversized groups are capped by stable unit ID")
	var stranded := fighter(24, 2, Vector2(6, 5))
	stranded["diagnostic_reason"] = "no_path"
	var recovery_snapshot := snapshot_base()
	recovery_snapshot["units"] = [stranded, fighter(25, 2, Vector2(7, 5))]
	recovery_snapshot["navigation"] = {"land": [Vector2(6.25, 5), Vector2(6.5, 5), Vector2(9, 5)], "water": [], "reachable": {"land": [Vector2(6.5, 5), Vector2(9, 5)], "water": []}}
	var recovery_goal := {"type": "explore", "positions_by_domain": {"land": Vector2(9, 5)}}
	var recovery_commands := TacticalPlanner.plan(recovery_snapshot, 12, 2, recovery_goal, "LINE")
	assert_equal(recovery_commands.size(), 2, "tactical planner separates local recovery from the healthy attack group")
	assert_equal(recovery_commands[0].unit_ids, [24], "known unreachable unit receives an individual local recovery order")
	assert_equal(recovery_commands[0].target, Vector2(6.5, 5), "recovery uses the nearest observer-known walkable point")
	assert_equal(recovery_commands[1].unit_ids, [25], "healthy unit keeps the strategic group order")

	var threatened := snapshot_base()
	threatened["units"] = [fighter(20, 2, Vector2(4, 4)), fighter(10, 1, Vector2(5, 4))]
	var response_policy := policy.duplicate(true)
	response_policy["minimum_attack_group_size"] = 1
	response_policy["enemy_response_distance"] = 3.0
	var response_commands: Array = AiPlayer.new({"team": 2, "ai": response_policy}).collect_commands(threatened, 1)
	assert_equal(response_commands.size(), 1, "nearby enemy bypasses the opening delay for defense")
	assert_equal(response_commands[0].command_type(), "attack", "defensive response uses the ordinary authoritative attack command")

	var configured_policy := policy.duplicate(true)
	configured_policy["construction_priorities"] = ["house", "barracks"]
	configured_policy["building_limits"] = {"house": 4, "barracks": 1}
	configured_policy["housing_buffer"] = 2
	configured_policy["worker_target"] = 8
	configured_policy["minimum_workers_before_age_up"] = 6
	configured_policy["age_advance_technology_ids"] = [101, 102, 103]
	configured_policy["age_saving_construction_exceptions"] = ["house", "dock"]
	configured_policy["age_saving_production_exceptions"] = ["scout_ship"]
	configured_policy["structure_gap_fallback_kinds"] = ["house"]
	configured_policy["use_workers_in_attack_groups"] = false
	var configured_player = AiPlayer.new({"team": 2, "ai": configured_policy})
	var options: Dictionary = configured_player.presentation_options()
	assert_equal(options.get("requested_build_site_kinds"), ["house", "barracks"], "skirmish AI requests only policy-owned construction knowledge")
	assert_equal(options.get("planning_technology_ids"), [101, 102, 103], "skirmish AI requests authoritative future age costs without exposing hidden world state")
	assert_equal(configured_player.economic_policy.get("age_saving_construction_exceptions"), ["house", "dock"], "skirmish AI preserves data-driven construction exceptions while saving for an age advance")
	assert_equal(configured_player.economic_policy.get("age_saving_production_exceptions"), ["scout_ship"], "skirmish AI preserves kind-specific production exceptions while saving for an age advance")
	assert_equal(configured_player.economic_policy.get("structure_gap_fallback_kinds"), ["house"], "skirmish AI preserves data-driven compact-site fallbacks")
	assert_equal(float(options.get("minimum_structure_gap", -1.0)), float(configured_policy.get("minimum_structure_gap", 0.0)), "skirmish AI forwards its structure clearance to the bounded site query")
	assert_true(not bool(options.get("include_fog_cells", true)), "skirmish AI does not copy the full fog grid into every decision")
	var worker_only := snapshot_base()
	var armed_worker := worker(40, 2, Vector2(4, 4))
	armed_worker["combat_enabled"] = true
	armed_worker["behavior_tags"] = ["combatant", "worker"]
	worker_only["units"] = [armed_worker, fighter(10, 1, Vector2(6, 4))]
	assert_equal(configured_player.collect_commands(worker_only, 1).size(), 0, "skirmish tactical policy never pulls an economic worker into its attack group")


func train_option(kind: String, tags: Array, cost: Dictionary = {}) -> Dictionary:
	return {"kind": kind, "accepted": true, "behavior_tags": tags, "cost": cost.duplicate(true)}


func transport(id: int, position: Vector2, passenger_ids: Array) -> Dictionary:
	return {"id": id, "team": 2, "kind": "transport", "pos": position, "hp": 150.0, "task": "idle", "movement_domain": "water", "footprint_radius": 0.75, "combat_enabled": false, "components": {"worker": {"enabled": false}, "cargo": {"enabled": true, "capacity": 4, "passenger_ids": passenger_ids}}}


func first_command_of_type(commands: Array, command_type: String) -> Variant:
	for command in commands:
		if String(command.command_type()) == command_type:
			return command
	return null


func fighter(id: int, team: int, position: Vector2, domain: String = "land") -> Dictionary:
	return {"id": id, "team": team, "kind": "clubman", "pos": position, "hp": 40.0, "task": "idle", "movement_domain": domain, "combat_enabled": true, "behavior_tags": ["combatant"], "components": {"worker": {"enabled": false}, "movement": {"domain": domain}}}


func worker(id: int, team: int, position: Vector2, domain: String = "land") -> Dictionary:
	return {"id": id, "team": team, "kind": "villager", "pos": position, "hp": 25.0, "task": "idle", "movement_domain": domain, "components": {"worker": {"enabled": true}, "movement": {"domain": domain}}}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
