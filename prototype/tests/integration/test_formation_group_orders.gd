extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Geometry := preload("res://scripts/formation_geometry.gd")
const Selection := preload("res://scripts/formation_selection.gd")
const Main := preload("res://main.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Cohesion := preload("res://scripts/formation_cohesion.gd")
var failures: Array[String] = []

func _initialize() -> void:
	test_selection_does_not_transfer_formation()
	for native in [false, true]:
		test_queue_and_mixed_speed_march(native)
		test_casualties_keep_routes(native)
	test_cache_does_not_change_canonical_state()
	test_replay_policy_and_legacy_hash()
	for failure in failures: push_error(failure)
	print("Formation group orders: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func test_selection_does_not_transfer_formation() -> void:
	var world = World.new(Vector2i(64, 64))
	var controller = Controller.new(world)
	var first := add_group(world, Vector2(12, 12), 3)
	var second := add_group(world, Vector2(12, 24), 3)
	var fresh := add_group(world, Vector2(12, 36), 3)
	var game = Main.new()
	game.simulation_world = world
	game.game_controller = controller
	game.units = world.get_units()
	game.player_control_state.replace_or_add(second, false)
	game.set_formation("LINE")
	flush(controller)
	var second_id: int = world.find_unit(second[0])["formation_group_id"]
	game.player_control_state.replace_or_add(first, false)
	game.set_formation("COLUMN")
	flush(controller)
	var first_id: int = world.find_unit(first[0])["formation_group_id"]
	game.player_control_state.replace_or_add(second, false)
	game.refresh_hud_model()
	check(game.formation == "LINE", "selecting the second group displays its own line")
	var slots_before: Array = controller.formation_groups[second_id].slots.duplicate(true)
	game.refresh_hud_model()
	check(controller.command_queue.is_empty(), "selection refresh issues no reform command")
	check(controller.formation_groups[second_id].slots == slots_before, "selection does not change destinations")
	# Exercise the actual RMB input boundary while a stale UI value is present.
	game.formation = "COLUMN"
	game.issue_order(game.world_to_screen(Vector2(26, 24)))
	flush(controller)
	check(controller.formation_groups[second_id].formation_type == "LINE", "RMB ignores a stale formation from another selection")
	check(controller.formation_groups[first_id].formation_type == "COLUMN", "the first group retains its column")
	game.player_control_state.replace_or_add(fresh, false)
	game.refresh_hud_model()
	check(game.formation == "RECTANGLE", "an unformed group does not inherit the previous selection")
	var all_ids: Array[int] = first.duplicate()
	all_ids.append_array(second)
	game.player_control_state.replace_or_add(all_ids, false)
	game.refresh_hud_model()
	check(game.formation.is_empty(), "mixed selection does not falsely highlight one formation")
	game.issue_order(game.world_to_screen(Vector2(30, 20)))
	flush(controller)
	check(controller.formation_groups[first_id].formation_type == "COLUMN" and controller.formation_groups[second_id].formation_type == "LINE", "a mixed move preserves both formations")
	game.free()

func test_queue_and_mixed_speed_march(native: bool) -> void:
	var world = World.new(Vector2i(48, 48))
	world.pathfinder.set_native_enabled(native)
	world.add_unit(2, "clubman", Vector2(44, 44), false)["stance"] = "passive"
	var controller = Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = []
	for position in Geometry.world_slots(Geometry.local_slots(3, "LINE"), Vector2(8, 8), Vector2.DOWN):
		var unit: Dictionary = world.add_unit(1, "clubman", position, false)
		unit["stance"] = "passive"
		ids.append(int(unit["id"]))
	world.find_unit(ids[0])["speed"] = 1.2
	world.find_unit(ids[1])["speed"] = 2.4
	world.find_unit(ids[2])["speed"] = 3.6
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(12, 8), "LINE", Vector2.DOWN))
	controller.advance_frame(0.05, 1, 2)
	var group = controller.formation_groups[world.find_unit(ids[0])["formation_group_id"]]
	var origin: Vector2 = group.march_anchor
	for id in ids:
		var unit: Dictionary = world.find_unit(id)
		check(absf(float(unit["actual_velocity"].length()) - 1.2) < 0.001, "mixed group shares the slowest speed (native=%s)" % native)
	var queued = Commands.MoveCommand.new(2, ids, Vector2(20, 8))
	queued.params["queue_order"] = true
	queued.params["preserve_formations"] = true
	controller.enqueue_command(queued)
	for tick in range(350): controller.advance_frame(0.05, 1, 2)
	check(group.march_anchor.distance_to(origin) > 1.0, "formation has a moving reference point")
	check(controller.formation_groups.size() == 1, "queued waypoint retains a single group")
	check(group.anchor.is_equal_approx(Vector2(20, 8)), "queued destination executes for the cohort")
	for id in ids:
		var unit: Dictionary = world.find_unit(id)
		check(int(unit["formation_group_id"]) == group.group_id, "queue preserves group identity")
		check(Vector2(unit["pos"]).distance_to(Vector2(unit["formation_home"])) < 0.25, "queued group reaches its destination (native=%s id=%d pos=%s target=%s task=%s)" % [native, id, unit["pos"], unit["formation_home"], unit["task"]])
	var target := Commands.AttackMoveCommand.new(controller.tick_index + 1, ids, Vector2(25, 8))
	controller.enqueue_command(target)
	controller.advance_frame(0.05, 1, 2)
	check(controller.formation_groups.size() == 1 and group.order_kind == "attack_move", "attack-move preserves group")
	check(ids.all(func(id): return world.find_unit(id)["task"] == "attack_move"), "attack-move keeps combat acquisition enabled")

func test_casualties_keep_routes(native: bool) -> void:
	var world = World.new(Vector2i(80, 80))
	world.pathfinder.set_native_enabled(native)
	var ids := add_group(world, Vector2(20, 20), 100)
	var controller = Controller.new(world)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(50, 45), "LINE"))
	flush(controller)
	var paths: Dictionary = {}
	for id in ids: paths[id] = world.find_unit(id)["path"]
	var request_count: int = world.navigation_service.next_request_id
	world.find_unit(ids[0])["hp"] = 0.0
	controller.reconcile_formation_groups()
	check(world.navigation_service.next_request_id == request_count, "one death creates no replacement navigation requests")
	for index in range(1, ids.size()): check(is_same(paths[ids[index]], world.find_unit(ids[index])["path"]), "survivor route is reused")

func test_cache_does_not_change_canonical_state() -> void:
	var world = World.new(Vector2i(32, 32))
	var ids := add_group(world, Vector2(8, 8), 2)
	var controller = Controller.new(world)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(20, 8), "LINE"))
	flush(controller)
	var replay := Replay.new()
	var before := replay.world_state_hash(world, controller.tick_index, controller)
	Cohesion.remaining_distance(world.find_unit(ids[0]))
	check(replay.world_state_hash(world, controller.tick_index, controller) == before, "warming the path suffix cache does not affect lockstep state")

func add_group(world, center: Vector2, count: int) -> Array[int]:
	var ids: Array[int] = []
	for position in Geometry.world_slots(Geometry.local_slots(count, "LINE"), center, Vector2.DOWN):
		var unit: Dictionary = world.add_unit(1, "clubman", position, false)
		unit["stance"] = "passive"
		ids.append(int(unit["id"]))
	return ids

func flush(controller) -> void:
	controller.tick_index += 1
	controller.process_commands()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)


func test_replay_policy_and_legacy_hash() -> void:
	var codec := Replay.new()
	var command = Commands.FormationMoveCommand.new(1, [1, 2], Vector2(20, 20), "COLUMN")
	command.params["preserve_formations"] = true
	command.assign_envelope(1, 1)
	codec.record_command(command)
	var replayed = codec.command_from_record(codec.command_records[0])
	check(bool(replayed.params.get("preserve_formations", false)), "record/replay preserves per-group formation policy")
	var world = World.new(Vector2i(40, 40))
	var ids := add_group(world, Vector2(8, 8), 2)
	var controller = Controller.new(world)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(20, 20), "LINE"))
	flush(controller)
	var legacy_snapshot := codec.world_snapshot(world, controller.tick_index, controller)
	for group in legacy_snapshot["controller"]["formation_groups"]:
		for field in ["march_anchor", "march_speed", "order_kind", "deployed_columns"]: group.erase(field)
	var expected_hash := JSON.stringify(codec.encode_variant(legacy_snapshot)).sha256_text()
	var saved_groups: Array = legacy_snapshot["controller"]["formation_groups"]
	check(codec.world_state_hash(world, controller.tick_index, controller, saved_groups) == expected_hash, "old formation checkpoint verifies against its original schema")
	world.find_unit(ids[0])["hp"] -= 1
	check(codec.world_state_hash(world, controller.tick_index, controller, saved_groups) != expected_hash, "legacy migration still detects corrupted authoritative state")
