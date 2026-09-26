extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const FIXTURE_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"
const SAVE_PATH := "res://qa/p14-replay-save-hash-matrix.json"

var failures: Array[String] = []
var checkpoints: Array[String] = []


func _initialize() -> void:
	cleanup()
	await verify_rule_checkpoints()
	await verify_generated_maps()
	cleanup()
	if failures.is_empty():
		print("P14 replay/save hash matrix passed: %s" % [", ".join(checkpoints)])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_rule_checkpoints() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	raw["players"][0]["starting_age_technology_id"] = 102
	raw["entities"].append({"category": "building", "team": 1, "kind": "government_center", "position": [20.0, 8.0]})
	var definition := MatchDefinition.normalize(raw)
	assert_true(bool(definition.get("valid", false)), "advanced fixture is valid: %s" % [definition.get("errors", [])])
	if not bool(definition.get("valid", false)):
		return
	var game = await create_game(definition, FIXTURE_PATH)
	if game == null:
		return
	var workers: Array = game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "villager")
	var worker_id := int(workers[0].get("id", -1)) if not workers.is_empty() else -1
	assert_true(worker_id > 0, "fixture contains a worker for deferred orders")
	if worker_id > 0:
		var move = Commands.MoveCommand.new(game.game_controller.tick_index + 1, [worker_id], Vector2(20.0, 18.0))
		var deferred = Commands.MoveCommand.new(game.game_controller.tick_index + 1, [worker_id], Vector2(15.0, 18.0))
		deferred.params["queue_order"] = true
		game.game_controller.enqueue_command(move, true, 1)
		game.game_controller.enqueue_command(deferred, true, 1)
		advance_ticks(game, 1)
		assert_true(bool(game.game_controller.get_command_result(move.sequence_id).get("accepted", false)), "first move accepted")
		assert_true(bool(game.game_controller.get_command_result(deferred.sequence_id).get("accepted", false)), "deferred move accepted")
		var worker: Dictionary = game.simulation_world.find_unit(worker_id)
		assert_true(worker.get("components", {}).get("order", {}).get("queued", []).size() == 1, "deferred stage remains in authoritative queue")
		checkpoint(game, "queued_orders")

	var enemy: Dictionary = first_entity(game.simulation_world.get_units(), 2, "scout_ship")
	var attacker: Dictionary = first_entity(game.simulation_world.get_units(), 1, "scout_ship")
	if not enemy.is_empty() and not attacker.is_empty():
		var attack = Commands.AttackCommand.new(game.game_controller.tick_index + 1, [int(attacker["id"])], int(enemy["id"]))
		game.game_controller.enqueue_command(attack, true, 1)
		advance_ticks(game, 4)
		assert_true(bool(game.game_controller.get_command_result(attack.sequence_id).get("accepted", false)), "naval combat accepted")
		checkpoint(game, "combat")

	var government: Dictionary = first_entity(game.simulation_world.get_buildings(), 1, "government_center")
	if not government.is_empty():
		var government_id := int(government.get("id", -1))
		var logistics = Commands.ResearchCommand.new(game.game_controller.tick_index + 1, [government_id], "121")
		game.game_controller.enqueue_command(logistics, true, 1)
		advance_ticks(game, 1)
		assert_true(bool(game.game_controller.get_command_result(logistics.sequence_id).get("accepted", false)), "Logistics research accepted: %s" % [game.game_controller.get_command_result(logistics.sequence_id)])
		if bool(game.game_controller.get_command_result(logistics.sequence_id).get("accepted", false)):
			for _step in range(2400):
				if game.simulation_world.get_researched_technologies(1).has(121):
					break
				advance_ticks(game, 1)
			assert_true(game.simulation_world.get_researched_technologies(1).has(121), "Logistics research completes")
			var soldiers: Array = game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "clubman")
			assert_true(soldiers.all(func(unit): return int(unit.get("population_points_cost", -1)) == 1), "Logistics reprices existing Clubmen")
			checkpoint(game, "logistics")

	if worker_id > 0:
		var fog_before: PackedByteArray = game.simulation_world.get_fog_of_war().snapshot(1)
		var explore = Commands.MoveCommand.new(game.game_controller.tick_index + 1, [worker_id], Vector2(24.0, 5.0))
		game.game_controller.enqueue_command(explore, true, 1)
		advance_ticks(game, 60)
		assert_true(bool(game.game_controller.get_command_result(explore.sequence_id).get("accepted", false)), "exploration order accepted")
		var fog_after: PackedByteArray = game.simulation_world.get_fog_of_war().snapshot(1)
		assert_true(fog_after != fog_before, "exploration changes canonical fog memory")
		checkpoint(game, "fog")

	var resign = Commands.ResignCommand.new(game.game_controller.tick_index + 1)
	game.game_controller.enqueue_command(resign, true, 2)
	advance_ticks(game, 2)
	assert_true(bool(game.simulation_world.get_victory_result().get("over", false)), "match reaches terminal victory")
	checkpoint(game, "victory")
	game.free()


func verify_generated_maps() -> void:
	for profile in ["continental", "mediterranean", "hill_country", "narrows"]:
		var settings := SkirmishSettings.default_settings()
		settings["map_type_id"] = profile
		settings["seed"] = 41721
		var built := SkirmishSettings.build(settings)
		assert_true(bool(built.get("valid", false)), "%s map builds: %s" % [profile, built.get("errors", [])])
		if not bool(built.get("valid", false)):
			continue
		var game = await create_game(built["definition"], String(built["identity"]), built["map_data"])
		if game == null:
			continue
		advance_ticks(game, 3)
		checkpoint(game, "map/%s" % profile)
		game.free()


func create_game(definition: Dictionary, path: String, map_data: Dictionary = {}):
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.set_process(false)
	game.match_path = path
	game.match_definition_override = definition
	game.map_definition_override = map_data
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	if game.game_controller == null:
		assert_true(false, "%s scene initializes" % path)
		game.free()
		return null
	game.game_controller.set_speed_multiplier(1.0)
	return game


func checkpoint(game, label: String) -> void:
	var verifier := ReplaySystem.new()
	var tick := int(game.game_controller.tick_index)
	var expected := verifier.world_state_hash(game.simulation_world, tick, game.game_controller)
	assert_true(game.save_game_to_path(SAVE_PATH), "%s writes replay-backed save: %s" % [label, game.last_save_error])
	advance_ticks(game, 2)
	var continued := verifier.world_state_hash(game.simulation_world, tick + 2, game.game_controller)
	var loaded := bool(game.load_game_from_path(SAVE_PATH))
	assert_true(loaded, "%s restores replay-backed save: %s" % [label, game.last_save_error])
	if not loaded:
		return
	assert_equal(game.game_controller.tick_index, tick, "%s restores fixed tick" % label)
	assert_equal(verifier.world_state_hash(game.simulation_world, tick, game.game_controller), expected, "%s restores canonical hash" % label)
	advance_ticks(game, 2)
	assert_equal(verifier.world_state_hash(game.simulation_world, tick + 2, game.game_controller), continued, "%s continuation hash is identical" % label)
	assert_true(game.load_game_from_path(SAVE_PATH), "%s restores checkpoint for next stage" % label)
	checkpoints.append("%s@%d=%s" % [label, tick, expected.left(12)])


func advance_ticks(game, count: int) -> void:
	for _step in range(count):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)


func first_entity(entities: Array, team: int, kind: String) -> Dictionary:
	for value in entities:
		var entity: Dictionary = value
		if int(entity.get("team", 0)) == team and String(entity.get("kind", "")) == kind:
			return entity
	assert_true(false, "fixture contains team %d %s" % [team, kind])
	return {}


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
