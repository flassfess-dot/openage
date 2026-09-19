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
	test_known_resource_cache_tracks_incremental_exploration()
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
	player["components"]["cargo"] = {"enabled": true, "capacity": 5, "passenger_ids": [101, 102]}
	player["components"]["trade"] = {"enabled": true, "selected_input_resource_type_id": 2, "cargo_gold": 7.0}
	var visible_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(6.0, 4.0), false)
	visible_enemy["components"]["cargo"] = {"enabled": true, "capacity": 5, "passenger_ids": [201, 202]}
	var hidden_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(28.0, 28.0), false)
	var visible_objective: Dictionary = world.add_victory_object("ruin", Vector2(4.0, 4.0), 1, true)
	world.add_victory_object("ruin", Vector2(28.0, 27.0), 0, true)
	world.set_resource_amount(1, 2, 44)
	world.update_fog_of_war()
	var snapshot := SimulationSnapshot.presentation(world, 7, 1)
	assert_equal(snapshot["tick"], 7, "presentation tick is explicit")
	assert_equal(snapshot["units"].size(), 2, "presentation snapshot excludes unseen enemies while retaining visible contacts")
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
	assert_true(snapshot["navigation"]["reachable_frontier"]["land"].all(func(point): return point in snapshot["navigation"]["reachable"]["land"]), "reachable frontier never crosses the observer's land component")
	var bounded := SimulationSnapshot.presentation(world, 7, 1, {
		"include_navigation": false,
		"include_build_sites": false,
		"include_overview": true,
		"entity_bounds": Rect2(Vector2(3.0, 3.0), Vector2(2.0, 2.0)),
		"command_option_entity_ids": [],
	})
	assert_equal(bounded["units"].map(func(unit): return int(unit["id"])), [int(player["id"])], "bounded presentation keeps only detailed viewport units")
	assert_equal(bounded["overview"]["units"].size(), 2, "bounded presentation retains compact minimap knowledge")
	var selected_outside := SimulationSnapshot.presentation(world, 7, 1, {
		"include_navigation": false,
		"include_build_sites": false,
		"entity_bounds": Rect2(Vector2(3.0, 3.0), Vector2(2.0, 2.0)),
		"always_include_entity_ids": [int(visible_enemy["id"])],
	})
	assert_equal(selected_outside["units"].size(), 2, "selected entity remains detailed outside viewport bounds")
	var compact_render := SimulationSnapshot.presentation(world, 7, 1, {
		"include_navigation": false,
		"include_build_sites": false,
		"compact_render_entities": true,
		"entity_bounds": Rect2(Vector2(3.0, 3.0), Vector2(5.0, 3.0)),
		"always_include_entity_ids": [int(player["id"])],
		"command_option_entity_ids": [int(player["id"])],
	})
	var render_player: Dictionary = compact_render["units"].filter(func(unit): return int(unit.get("id", -1)) == int(player["id"]))[0]
	var render_enemy: Dictionary = compact_render["units"].filter(func(unit): return int(unit.get("id", -1)) == int(visible_enemy["id"]))[0]
	assert_true(not render_player.has("path"), "always-included selection omits authoritative navigation internals")
	assert_true(render_player.get("components", {}).has("combat"), "always-included selection retains its compact command and HUD projection")
	assert_true(not render_enemy.has("path"), "unselected render projection omits authoritative navigation paths")
	assert_true(not render_enemy.get("components", {}).has("combat"), "unselected render projection omits heavyweight combat tables")
	assert_true(render_enemy.has("footprint") and render_enemy.has("anim_state"), "unselected render projection retains picking and animation fields")
	assert_equal(render_enemy.get("pos"), visible_enemy.get("pos"), "compact render projection retains the entity anchor")
	render_enemy["footprint"]["selection_radius"] = Vector2(99.0, 99.0)
	assert_not_equal(visible_enemy.get("footprint", {}).get("selection_radius"), Vector2(99.0, 99.0), "compact render footprint remains detached from simulation state")
	snapshot["player_state"]["food"] = 0
	snapshot["fog"]["cells"][0] = 99
	assert_equal(world.get_food(), 180, "player economy snapshot is detached")
	assert_not_equal(world.get_fog_state_at(1, Vector2(0.5, 0.5)), 99, "fog snapshot is detached")
	world.record_attack_distress(hidden_enemy, player)
	var distress_snapshot := SimulationSnapshot.presentation(world, 8, 1, {"compact_entities": true})
	assert_equal(distress_snapshot.get("ai_distress_signals", []).size(), 1, "observer receives only its own recent distress calls")
	assert_equal(int(distress_snapshot.get("ai_distress_signals", [])[0].get("attacker_id", -1)), int(hidden_enemy["id"]), "distress call preserves the authoritative attacker identity")
	var compact_own: Dictionary = distress_snapshot["units"].filter(func(unit): return int(unit.get("id", -1)) == int(player["id"]))[0]
	var compact_enemy: Dictionary = distress_snapshot["units"].filter(func(unit): return int(unit.get("id", -1)) == int(visible_enemy["id"]))[0]
	assert_equal(compact_own.get("components", {}).get("cargo", {}).get("passenger_ids"), [101, 102], "compact AI snapshot preserves own transport manifest")
	assert_equal(compact_own.get("components", {}).get("trade", {}).get("selected_input_resource_type_id"), 2, "compact AI snapshot preserves own trade policy")
	assert_true(not compact_enemy.get("components", {}).get("cargo", {}).has("passenger_ids"), "compact AI snapshot hides an enemy transport manifest")
	distress_snapshot["ai_distress_signals"][0]["attacker_id"] = -1
	assert_equal(int(world.get_attack_distress_signals(1)[0].get("attacker_id", -1)), int(hidden_enemy["id"]), "distress presentation is detached from authoritative state")
	world.ai_distress_system.advance({"delta": 4.0})
	assert_true(world.get_attack_distress_signals(1).is_empty(), "bounded distress calls expire deterministically")


func test_known_resource_cache_tracks_incremental_exploration() -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var scout: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	scout["components"]["vision"] = {"enabled": true, "range": 3.0}
	var first: Dictionary = world.add_resource("tree", Vector2(5.0, 4.0), 75)
	var second: Dictionary = world.add_resource("tree", Vector2(24.0, 24.0), 75)
	world.update_fog_of_war()
	var initial_ids: Array = world.get_known_resources(1).map(func(resource): return int(resource["id"]))
	assert_true(int(first["id"]) in initial_ids, "initial resource cache includes explored resources")
	assert_true(int(second["id"]) not in initial_ids, "initial resource cache excludes unknown resources")

	scout["pos"] = Vector2(23.0, 24.0)
	world.update_fog_of_war()
	var expanded_ids: Array = world.get_known_resources(1).map(func(resource): return int(resource["id"]))
	assert_true(int(first["id"]) in expanded_ids, "resource cache preserves explored resources outside current vision")
	assert_true(int(second["id"]) in expanded_ids, "resource cache consumes newly explored cells incrementally")
	var repeated_ids: Array = world.get_known_resources(1).map(func(resource): return int(resource["id"]))
	assert_equal(repeated_ids.count(int(second["id"])), 1, "resource cache does not duplicate resources after repeated reads")
	var bounded_ids: Array = world.get_known_resources_in_bounds(1, Rect2(Vector2(22.0, 22.0), Vector2(4.0, 4.0))).map(func(resource): return int(resource["id"]))
	assert_equal(bounded_ids, [int(second["id"])], "bounded resource cache returns only explored resources intersecting the camera")


func assert_not_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual == expected:
		failures.append("%s: values unexpectedly match" % context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
