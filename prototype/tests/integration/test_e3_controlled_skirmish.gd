extends SceneTree

const ReplaySystem := preload("res://scripts/replay_system.gd")

const MATCH_PATH := "res://tests/fixtures/e3_controlled_skirmish_match.json"
const SAVE_PATH := "res://qa/e3-controlled-skirmish.json"
const PLAYER_TEAM := 1
const ENEMY_TEAM := 2

var failures: Array[String] = []
var final_snapshots: Array = []
var run_traces: Array[Dictionary] = []


func _initialize() -> void:
	cleanup()
	var uninterrupted_hash: String = await run_match(false)
	var restored_hash: String = await run_match(true)
	assert_true(not uninterrupted_hash.is_empty(), "uninterrupted controlled skirmish reaches a canonical result")
	if restored_hash != uninterrupted_hash and final_snapshots.size() == 2:
		print("E3 CONTROLLED SKIRMISH FIRST DIFFERENCE: %s" % first_difference(final_snapshots[0], final_snapshots[1], "root"))
		print("E3 CONTROLLED SKIRMISH TRACES: %s" % [run_traces])
	assert_equal(restored_hash, uninterrupted_hash, "save/load branch reaches the same final canonical state")
	cleanup()
	if failures.is_empty():
		print("E3 controlled skirmish acceptance passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func run_match(use_checkpoint: bool) -> String:
	var trace := {"checkpoint": use_checkpoint}
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_process(false)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	game.sync_world_state()

	var worker: Dictionary = first_entity(game.simulation_world.get_units(), PLAYER_TEAM, "villager")
	var tree: Dictionary = first_entity(game.simulation_world.get_resources(), 0, "tree")
	select_entities(game, [int(worker.get("id", -1))])
	var wood_before: int = int(game.simulation_world.get_wood())
	game.issue_order(game.world_to_screen(Vector2(tree.get("pos", Vector2.ZERO))))
	var gather_record := last_command_record(game)
	assert_equal(String(gather_record.get("type", "")), "gather", "resource click emits GatherCommand through main")
	advance_until(game, func(): return int(tree.get("amount", 0)) == 0 and String(worker.get("task", "")) == "idle", 1800)
	assert_command_accepted(game, gather_record, "gather")
	assert_equal(game.simulation_world.get_wood(), wood_before + 4, "worker physically gathers, carries and deposits the tree")
	trace["gather"] = game.game_controller.tick_index

	select_entities(game, [int(worker.get("id", -1))])
	game.hud_controls.build_requested.emit("house")
	assert_equal(game.pending_build_kind, "house", "HUD build action enters placement mode")
	var build_position := first_build_position(game, "house", Vector2(8.0, 20.0))
	assert_true(build_position != Vector2.ZERO, "controlled map exposes a legal House footprint")
	if build_position == Vector2.ZERO:
		game.free()
		await process_frame
		return ""
	var build_screen: Vector2 = game.world_to_screen(build_position)
	game.handle_input_action({"type": "selection_committed", "from": build_screen, "to": build_screen})
	var build_record := last_command_record(game)
	assert_equal(String(build_record.get("type", "")), "build", "placement click emits BuildCommand through main")
	advance_until(game, func(): return completed_building(game, "house") != null, 2200)
	assert_command_accepted(game, build_record, "build")
	assert_true(completed_building(game, "house") != null, "worker completes the House without direct state mutation")
	trace["build"] = game.game_controller.tick_index

	var barracks: Dictionary = first_entity(game.simulation_world.get_buildings(), PLAYER_TEAM, "barracks")
	var clubmen_before := living_units(game, PLAYER_TEAM, "clubman").size()
	select_entities(game, [int(barracks.get("id", -1))])
	game.hud_controls.train_requested.emit("clubman", int(barracks.get("id", -1)))
	var train_record := last_command_record(game)
	assert_equal(String(train_record.get("type", "")), "train", "HUD production action emits TrainCommand")
	advance_until(game, func(): return living_units(game, PLAYER_TEAM, "clubman").size() > clubmen_before, 1200)
	assert_command_accepted(game, train_record, "train")
	assert_equal(living_units(game, PLAYER_TEAM, "clubman").size(), clubmen_before + 1, "Barracks completes one queued Clubman")
	trace["train"] = game.game_controller.tick_index

	var town_center: Dictionary = first_entity(game.simulation_world.get_buildings(), PLAYER_TEAM, "town_center")
	select_entities(game, [int(town_center.get("id", -1))])
	game.hud_controls.research_requested.emit(101, int(town_center.get("id", -1)))
	var research_record := last_command_record(game)
	assert_equal(String(research_record.get("type", "")), "research", "HUD research action emits ResearchCommand")
	advance_until(game, func(): return game.simulation_world.get_current_age(PLAYER_TEAM) == 101, 3200)
	assert_command_accepted(game, research_record, "research")
	assert_equal(game.simulation_world.get_current_age(PLAYER_TEAM), 101, "Tool Age completes through the production queue")
	trace["research"] = game.game_controller.tick_index

	if use_checkpoint:
		var checkpoint_tick := int(game.game_controller.tick_index)
		var checkpoint_hash := ReplaySystem.new().world_state_hash(game.simulation_world, checkpoint_tick, game.game_controller)
		assert_true(game.save_game_to_path(SAVE_PATH), "controlled skirmish writes an intermediate save")
		advance_ticks(game, 12)
		assert_true(game.load_game_from_path(SAVE_PATH), "controlled skirmish restores the intermediate save")
		assert_equal(game.game_controller.tick_index, checkpoint_tick, "load restores the exact fixed tick")
		assert_equal(ReplaySystem.new().world_state_hash(game.simulation_world, checkpoint_tick, game.game_controller), checkpoint_hash, "load restores the exact checkpoint state")

	var soldiers := living_units(game, PLAYER_TEAM, "clubman")
	var soldier_ids := entity_ids(soldiers)
	select_entities(game, soldier_ids)
	game.hud_controls.formation_requested.emit("LINE")
	var reform_record := last_command_record(game)
	advance_ticks(game, 2)
	assert_equal(String(reform_record.get("type", "")), "formation_move", "formation HUD action emits FormationMoveCommand")
	assert_command_accepted(game, reform_record, "formation reform")

	var march_target := Vector2(25.0, 18.0)
	game.issue_order(game.world_to_screen(march_target), game.world_to_screen(march_target + Vector2.RIGHT))
	var march_record := last_command_record(game)
	assert_equal(String(march_record.get("type", "")), "formation_move", "directed terrain order preserves the selected formation")
	advance_until(game, func(): return living_units(game, ENEMY_TEAM, "clubman").is_empty() or bool(game.simulation_world.get_victory_result().get("over", false)), 2600)
	assert_command_accepted(game, march_record, "formation march")
	assert_true(game.game_controller.events_after().any(func(event): return String(event.get("type", "")) == "formation_state_changed" and String(event.get("payload", {}).get("current_state", "")) == "ENGAGED"), "marching formation enters autonomous ENGAGED lifecycle")
	assert_true(living_units(game, ENEMY_TEAM, "clubman").is_empty(), "formation defeats the hostile force autonomously")
	var result: Dictionary = game.simulation_world.get_victory_result()
	assert_true(bool(result.get("over", false)), "conquest reaches a terminal result")
	assert_equal(int(result.get("winner_team", 0)), PLAYER_TEAM, "controlled skirmish awards victory to the player")
	trace["victory"] = game.game_controller.tick_index
	run_traces.append(trace)

	var verifier := ReplaySystem.new()
	final_snapshots.append(verifier.encode_variant(verifier.world_snapshot(game.simulation_world, game.game_controller.tick_index, game.game_controller)))
	var final_hash := verifier.world_state_hash(game.simulation_world, game.game_controller.tick_index, game.game_controller)
	game.free()
	await process_frame
	return final_hash


func select_entities(game, ids: Array[int]) -> void:
	game.player_control_state.replace_or_add(ids, false)
	game.sync_world_state()


func advance_until(game, predicate: Callable, maximum_ticks: int) -> void:
	for _tick in range(maximum_ticks):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, PLAYER_TEAM, ENEMY_TEAM)
		if bool(predicate.call()):
			game.sync_world_state()
			return
	game.sync_world_state()


func advance_ticks(game, count: int) -> void:
	for _tick in range(count):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, PLAYER_TEAM, ENEMY_TEAM)
	game.sync_world_state()


func last_command_record(game) -> Dictionary:
	var records: Array = game.game_controller.replay_recorder.command_records
	assert_true(not records.is_empty(), "public action records a replay command")
	return records[-1] if not records.is_empty() else {}


func assert_command_accepted(game, record: Dictionary, context: String) -> void:
	var sequence_id := int(record.get("sequence_id", -1))
	assert_true(bool(game.game_controller.get_command_result(sequence_id).get("accepted", false)), "%s command is accepted" % context)


func first_build_position(game, kind: String, center: Vector2) -> Vector2:
	for radius in range(7):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := center + Vector2(x, y)
				if game.simulation_world.can_place_foundation(PLAYER_TEAM, kind, candidate):
					return candidate
	return Vector2.ZERO


func completed_building(game, kind: String) -> Variant:
	var matches: Array = game.simulation_world.get_buildings().filter(func(building): return int(building.get("team", 0)) == PLAYER_TEAM and String(building.get("kind", "")) == kind and String(building.get("state", "")) == "complete")
	return matches[0] if not matches.is_empty() else null


func living_units(game, team: int, kind: String) -> Array:
	return game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == team and String(unit.get("kind", "")) == kind and float(unit.get("hp", 0.0)) > 0.0)


func first_entity(entities: Array, team: int, kind: String) -> Dictionary:
	var matches := entities.filter(func(entity): return int(entity.get("team", 0)) == team and String(entity.get("kind", "")) == kind)
	assert_true(not matches.is_empty(), "fixture contains team %d %s" % [team, kind])
	return matches[0] if not matches.is_empty() else {}


func entity_ids(entities: Array) -> Array[int]:
	var result: Array[int] = []
	for entity in entities:
		result.append(int(entity.get("id", -1)))
	return result


func cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := ProjectSettings.globalize_path(SAVE_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if typeof(expected) != typeof(actual):
		return "%s type %s != %s" % [path, typeof(expected), typeof(actual)]
	if expected is Dictionary:
		for key in expected:
			if not actual.has(key):
				return "%s.%s missing" % [path, key]
			var difference := first_difference(expected[key], actual[key], "%s.%s" % [path, key])
			if not difference.is_empty():
				return difference
		for key in actual:
			if not expected.has(key):
				return "%s.%s unexpected" % [path, key]
		return ""
	if expected is Array:
		if expected.size() != actual.size():
			return "%s size %d != %d" % [path, expected.size(), actual.size()]
		for index in range(expected.size()):
			var difference := first_difference(expected[index], actual[index], "%s[%d]" % [path, index])
			if not difference.is_empty():
				return difference
		return ""
	if expected != actual:
		return "%s %s != %s" % [path, expected, actual]
	return ""


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
