extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_hash_covers_authoritative_subsystems()
	test_presentation_snapshot_is_filtered_and_detached()
	if failures.is_empty():
		print("I1-003 canonical snapshot tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_hash_covers_authoritative_subsystems() -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var second: Dictionary = world.add_unit(1, "archer", Vector2(5.0, 4.0), false)
	world.add_unit(2, "clubman", Vector2(20.0, 20.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, [first["id"], second["id"]], Vector2(10.0, 10.0), "LINE", Vector2(1.0, 0.0)), true, 1)
	controller.advance_frame(0.05, 1, 2)
	var replay = ReplaySystem.new()
	var baseline := replay.world_state_hash(world, controller.tick_index, controller)
	first["selected"] = not bool(first.get("selected", false))
	assert_equal(replay.world_state_hash(world, controller.tick_index, controller), baseline, "presentation selection does not affect canonical hash")

	var group = controller.formation_groups[1]
	var previous_state: String = group.state
	group.state = "engaged"
	assert_not_equal(replay.world_state_hash(world, controller.tick_index, controller), baseline, "formation lifecycle affects canonical hash")
	group.state = previous_state

	var reservation_backup: Dictionary = world.destination_reservations.reservations.duplicate(true)
	world.destination_reservations.reservations[999] = {"position": Vector2(1.5, 1.5), "radius": 0.3}
	assert_not_equal(replay.world_state_hash(world, controller.tick_index, controller), baseline, "destination reservations affect canonical hash")
	world.destination_reservations.reservations = reservation_backup

	world.simulation_rng.randi()
	assert_not_equal(replay.world_state_hash(world, controller.tick_index, controller), baseline, "RNG state affects canonical hash")
	var attacker: Dictionary = world.get_units()[2]
	world.record_attack_distress(attacker, first)
	assert_not_equal(replay.world_state_hash(world, controller.tick_index, controller), baseline, "active AI distress signals affect canonical replay state")


func test_presentation_snapshot_is_filtered_and_detached() -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var player: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	player["components"]["vision"] = {"enabled": true, "range": 4.0}
	var hidden_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(28.0, 28.0), false)
	var visible_objective: Dictionary = world.add_victory_object("ruin", Vector2(4.0, 4.0), 1, true)
	world.add_victory_object("ruin", Vector2(28.0, 27.0), 0, true)
	world.set_resource_amount(1, 2, 44)
	world.update_fog_of_war()
	var snapshot := SimulationSnapshot.presentation(world, 7, 1)
	assert_equal(snapshot["tick"], 7, "presentation tick is explicit")
	assert_equal(snapshot["units"].size(), 1, "presentation snapshot excludes unseen enemies")
	assert_equal(snapshot["units"][0]["id"], player["id"], "presentation snapshot retains visible unit")
	assert_equal(snapshot["objectives"].size(), 1, "presentation snapshot excludes unseen objectives")
	assert_equal(snapshot["objectives"][0]["id"], visible_objective["id"], "presentation snapshot retains visible objective")
	var original_hp: float = float(player["hp"])
	snapshot["units"][0]["hp"] = 1.0
	assert_equal(float(player["hp"]), original_hp, "presentation snapshot is detached from simulation state")
	assert_equal(snapshot["player_state"]["stone"], 44, "presentation snapshot includes player economy")
	assert_equal(snapshot["fog"]["cells"].size(), 32 * 32, "presentation snapshot contains observer fog grid")
	assert_true(not snapshot["navigation"].get("frontier", {}).get("land", []).is_empty(), "presentation snapshot exposes compact reachable fog-frontier knowledge")
	assert_true(snapshot["navigation"]["frontier"]["land"].all(func(point): return point in snapshot["navigation"]["land"]), "every land frontier point is part of known reachable navigation")
	snapshot["player_state"]["food"] = 0
	snapshot["fog"]["cells"][0] = 99
	assert_equal(world.get_food(), 180, "player economy snapshot is detached")
	assert_not_equal(world.get_fog_state_at(1, Vector2(0.5, 0.5)), 99, "fog snapshot is detached")
	world.record_attack_distress(hidden_enemy, player)
	var distress_snapshot := SimulationSnapshot.presentation(world, 8, 1, {"compact_entities": true})
	assert_equal(distress_snapshot.get("ai_distress_signals", []).size(), 1, "observer receives only its own recent distress calls")
	assert_equal(int(distress_snapshot.get("ai_distress_signals", [])[0].get("attacker_id", -1)), int(hidden_enemy["id"]), "distress call preserves the authoritative attacker identity")
	distress_snapshot["ai_distress_signals"][0]["attacker_id"] = -1
	assert_equal(int(world.get_attack_distress_signals(1)[0].get("attacker_id", -1)), int(hidden_enemy["id"]), "distress presentation is detached from authoritative state")
	world.ai_distress_system.advance({"delta": 4.0})
	assert_true(world.get_attack_distress_signals(1).is_empty(), "bounded distress calls expire deterministically")


func assert_not_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual == expected:
		failures.append("%s: values unexpectedly match" % context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
