extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"
const SAVE_PATH := "res://qa/e3-save-state-matrix.json"

var failures: Array[String] = []
var round_trip_count := 0
var baseline_hash := ""
var baseline_tick := -1


func _initialize() -> void:
	cleanup()
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)

	test_economy_state(game)
	test_construction_state(game)
	test_formation_and_combat_state(game)
	test_production_and_research_state(game)
	test_naval_combat_state(game)
	test_victory_state(game)

	cleanup()
	game.free()
	if failures.is_empty():
		print("P00 BASELINE save_state_matrix tick=%d round_trips=%d hash=%s" % [baseline_tick, round_trip_count, baseline_hash])
		print("E3 save/load gameplay state matrix passed (%d round trips)" % round_trip_count)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_economy_state(game) -> void:
	var worker: Dictionary = first_entity(game.simulation_world.get_units(), 1, "villager")
	var tree: Dictionary = first_entity(game.simulation_world.get_resources(), 0, "tree")
	var command = Commands.GatherCommand.new(game.game_controller.tick_index + 1, [int(worker.get("id", -1))], int(tree.get("id", -1)))
	game.game_controller.enqueue_command(command, true, 1)
	advance_ticks(game, 3)
	assert_command_accepted(game, command, "gather command")
	worker = game.simulation_world.find_unit(int(worker.get("id", -1)))
	assert_true(String(worker.get("task", "")) in ["gather", "return_resources"], "economy fixture reaches an active gather cycle")
	round_trip(game, "economy/gather")


func test_construction_state(game) -> void:
	var workers: Array = matching_entities(game.simulation_world.get_units(), 1, "villager")
	var worker: Dictionary = workers[1]
	var build_position := first_build_position(game, "house", Vector2(8.0, 20.0))
	assert_true(build_position != Vector2.ZERO, "fixture exposes a legal House position")
	if build_position == Vector2.ZERO:
		return
	var command = Commands.BuildCommand.new(game.game_controller.tick_index + 1, [int(worker.get("id", -1))], "house", build_position)
	game.game_controller.enqueue_command(command, true, 1)
	advance_ticks(game, 3)
	assert_command_accepted(game, command, "build command")
	var foundations: Array = game.simulation_world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "house" and String(building.get("state", "")) == "foundation")
	assert_true(not foundations.is_empty(), "construction fixture reaches an incomplete foundation")
	round_trip(game, "construction/foundation")


func test_formation_and_combat_state(game) -> void:
	var soldiers: Array = matching_entities(game.simulation_world.get_units(), 1, "clubman")
	var soldier_ids: Array[int] = entity_ids(soldiers)
	var formation = Commands.FormationMoveCommand.new(game.game_controller.tick_index + 1, soldier_ids, Vector2(19.0, 18.0), FormationGeometry.LINE, Vector2(1, 0))
	game.game_controller.enqueue_command(formation, true, 1)
	advance_ticks(game, 3)
	assert_command_accepted(game, formation, "formation move command")
	assert_true(not game.game_controller.formation_groups.is_empty(), "formation fixture owns an authoritative group")
	round_trip(game, "formation/travel")

	soldiers = matching_entities(game.simulation_world.get_units(), 1, "clubman")
	soldier_ids = entity_ids(soldiers)
	var target: Dictionary = first_entity(game.simulation_world.get_units(), 2, "clubman")
	var attack = Commands.AttackCommand.new(game.game_controller.tick_index + 1, soldier_ids, int(target.get("id", -1)))
	game.game_controller.enqueue_command(attack, true, 1)
	advance_ticks(game, 2)
	assert_command_accepted(game, attack, "formation attack command")
	var group = game.game_controller.formation_groups.values()[0]
	assert_true(String(group.state) == "ENGAGED", "combat releases the formation into ENGAGED")
	round_trip(game, "formation/engaged-combat")


func test_production_and_research_state(game) -> void:
	var barracks: Dictionary = first_entity(game.simulation_world.get_buildings(), 1, "barracks")
	var train = Commands.TrainCommand.new(game.game_controller.tick_index + 1, [int(barracks.get("id", -1))], "clubman", 1, Vector2(15.0, 16.0))
	game.game_controller.enqueue_command(train, true, 1)
	advance_ticks(game, 2)
	assert_command_accepted(game, train, "production command")
	barracks = game.simulation_world.find_building(int(barracks.get("id", -1)))
	assert_true(not barracks.get("production_queue", []).is_empty(), "production fixture reaches an active queue")
	round_trip(game, "production/queue")

	var town_center: Dictionary = first_entity(game.simulation_world.get_buildings(), 1, "town_center")
	var research = Commands.ResearchCommand.new(game.game_controller.tick_index + 1, [int(town_center.get("id", -1))], "101")
	game.game_controller.enqueue_command(research, true, 1)
	advance_ticks(game, 2)
	assert_command_accepted(game, research, "research command")
	town_center = game.simulation_world.find_building(int(town_center.get("id", -1)))
	assert_true(not town_center.get("production_queue", []).is_empty(), "research fixture reaches an active technology queue")
	round_trip(game, "research/queue")


func test_naval_combat_state(game) -> void:
	var attacker: Dictionary = first_entity(game.simulation_world.get_units(), 1, "scout_ship")
	var target: Dictionary = first_entity(game.simulation_world.get_units(), 2, "scout_ship")
	var command = Commands.AttackCommand.new(game.game_controller.tick_index + 1, [int(attacker.get("id", -1))], int(target.get("id", -1)))
	game.game_controller.enqueue_command(command, true, 1)
	advance_ticks(game, 4)
	assert_command_accepted(game, command, "naval attack command")
	attacker = game.simulation_world.find_unit(int(attacker.get("id", -1)))
	assert_true(String(attacker.get("movement_domain", "")) == "water" and String(attacker.get("task", "")) == "attack", "naval fixture reaches active water combat")
	round_trip(game, "naval/combat")


func test_victory_state(game) -> void:
	var resign = Commands.ResignCommand.new(game.game_controller.tick_index + 1)
	game.game_controller.enqueue_command(resign, true, 2)
	advance_ticks(game, 2)
	assert_command_accepted(game, resign, "opponent resign command")
	assert_true(bool(game.simulation_world.get_victory_result().get("over", false)), "victory fixture reaches a terminal match result")
	round_trip(game, "victory/result")


func round_trip(game, context: String) -> void:
	var verifier := ReplaySystem.new()
	var saved_tick := int(game.game_controller.tick_index)
	var expected_snapshot = verifier.encode_variant(verifier.world_snapshot(game.simulation_world, saved_tick, game.game_controller))
	var expected_hash := verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller)
	baseline_hash = expected_hash
	baseline_tick = saved_tick
	assert_true(game.save_game_to_path(SAVE_PATH), "%s writes save" % context)
	advance_ticks(game, 2)
	var continued_hash := verifier.world_state_hash(game.simulation_world, saved_tick + 2, game.game_controller)
	var loaded: bool = bool(game.load_game_from_path(SAVE_PATH))
	if not loaded:
		print("E3 SAVE MATRIX FIRST DIFFERENCE [%s]: %s" % [context, replay_difference(game, expected_snapshot)])
	assert_true(loaded, "%s loads save (%s)" % [context, game.last_save_error])
	assert_equal(game.game_controller.tick_index, saved_tick, "%s restores fixed tick" % context)
	assert_equal(verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller), expected_hash, "%s restores canonical state" % context)
	if loaded:
		advance_ticks(game, 2)
		assert_equal(verifier.world_state_hash(game.simulation_world, saved_tick + 2, game.game_controller), continued_hash, "%s continues to the identical canonical hash after loading" % context)
		assert_true(game.load_game_from_path(SAVE_PATH), "%s can restore the original checkpoint after continuation" % context)
	round_trip_count += 1


func replay_difference(game, expected_snapshot: Variant) -> String:
	var loaded: Dictionary = GameSaveArchive.read(SAVE_PATH)
	if not bool(loaded.get("valid", false)):
		return "archive:%s" % String(loaded.get("error", "invalid"))
	var archive: Dictionary = loaded.get("archive", {})
	var restored_world = game._new_simulation_world()
	MatchBootstrap.apply(restored_world, game.match_definition, game.map_definition)
	var restored_controller = GameController.new(restored_world)
	restored_controller.reset_timing()
	if not restored_controller.load_replay(archive.get("replay", {})):
		return "replay_invalid"
	restored_controller.replay_until_tick(int(archive.get("tick", 0)), game.PLAYER_TEAM, game.ENEMY_TEAM)
	var verifier := ReplaySystem.new()
	var actual_snapshot = verifier.encode_variant(verifier.world_snapshot(restored_world, restored_controller.tick_index, restored_controller))
	return first_difference(expected_snapshot, actual_snapshot, "root")


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


func advance_ticks(game, count: int) -> void:
	for _step in range(count):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)


func first_build_position(game, kind: String, center: Vector2) -> Vector2:
	for radius in range(7):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := center + Vector2(x, y)
				if game.simulation_world.can_place_foundation(1, kind, candidate):
					return candidate
	return Vector2.ZERO


func matching_entities(entities: Array, team: int, kind: String) -> Array:
	return entities.filter(func(entity): return int(entity.get("team", 0)) == team and String(entity.get("kind", "")) == kind)


func first_entity(entities: Array, team: int, kind: String) -> Dictionary:
	var matches := matching_entities(entities, team, kind)
	assert_true(not matches.is_empty(), "fixture contains team %d %s" % [team, kind])
	return matches[0] if not matches.is_empty() else {}


func entity_ids(entities: Array) -> Array[int]:
	var result: Array[int] = []
	for entity in entities:
		result.append(int(entity.get("id", -1)))
	return result


func assert_command_accepted(game, command, context: String) -> void:
	assert_true(bool(game.game_controller.get_command_result(command.sequence_id).get("accepted", false)), "%s is accepted" % context)


func cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := ProjectSettings.globalize_path(SAVE_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
