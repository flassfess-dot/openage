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

	var dock_build_snapshot := snapshot_base()
	var dock_worker := worker(75, 2, Vector2(4, 10))
	dock_worker["command_options"] = {"build": [{"kind": "dock", "accepted": true}]}
	dock_build_snapshot["units"] = [dock_worker]
	dock_build_snapshot["build_sites"] = {"dock": [Vector2(2.5, 10.5)]}
	var dock_commands: Array = AiPlayer.new({"team": 2}).collect_commands(dock_build_snapshot, 1)
	assert_equal(dock_commands.size(), 1, "economic AI emits one authoritative shoreline build order")
	assert_equal(dock_commands[0].command_type(), "build", "economic AI builds Dock through public BuildCommand")
	assert_equal(dock_commands[0].building_type, "dock", "mixed-domain build site selects Dock")
	assert_equal(dock_commands[0].target, Vector2(2.5, 10.5), "AI uses only authoritative explored placement candidate")

	test_fleet_production_and_trade_routes()
	test_transport_planner_phases()

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


func train_option(kind: String, tags: Array) -> Dictionary:
	return {"kind": kind, "accepted": true, "behavior_tags": tags}


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
