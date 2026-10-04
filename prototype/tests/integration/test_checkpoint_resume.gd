extends SceneTree
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Commands := preload("res://scripts/commands.gd")
const PATH := "res://qa/checkpoint-resume.json"
var failures: Array[String] = []
func _initialize() -> void:
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	var workers: Array = game.simulation_world.get_units().filter(func(unit): return int(unit["team"]) == 1 and unit["kind"] == "villager")
	var planned = Commands.BuildCommand.new(100, [int(workers[0]["id"])], "house", Vector2(8, 20))
	planned.params["plan_only"] = true
	game.game_controller.enqueue_command(planned, true, 1)
	var verifier := Replay.new()
	verifier.record_command(planned)
	var recorded = verifier.command_from_record(verifier.command_records[0])
	check(recorded != null and bool(recorded.params.get("plan_only", false)), "replay preserves planning-only construction")
	for step in range(12): game.game_controller.advance_frame(0.05, 1, 2)
	var tick := int(game.game_controller.tick_index)
	var original_definition: Dictionary = game.match_definition.duplicate(true)
	var original_map: Dictionary = game.map_definition.duplicate(true)
	var saved_hash := verifier.world_state_hash(game.simulation_world, tick, game.game_controller)
	check(game.save_game_to_path(PATH), "complete checkpoint writes")
	var archive: Dictionary = Archive.read(PATH).get("archive", {})
	check(int(archive.get("format_version", 0)) == 4 and "world_checkpoint" in archive.get("schema_features", []), "new saves declare complete checkpoint schema")
	var data: Dictionary = Checkpoint.unpack(archive.get("checkpoint", {}))
	check(not data.is_empty(), "typed compressed state decodes")
	var continued_ticks := []
	for step in range(30):
		game.game_controller.advance_frame(0.05, 1, 2)
		continued_ticks.append(verifier.world_snapshot(game.simulation_world, game.game_controller.tick_index, game.game_controller))
	var continued_snapshot := verifier.world_snapshot(game.simulation_world, tick + 30, game.game_controller)
	var continued_hash := verifier.world_state_hash(game.simulation_world, tick + 30, game.game_controller)
	game.match_definition = {"id": "different-map"}
	game.map_definition = {"size": Vector2i(12, 12)}
	game.map_size = Vector2i(12, 12)
	check(game.load_game_from_path(PATH), "checkpoint loads independently of currently selected map (%s)" % game.last_save_error)
	check(game.match_definition == original_definition and game.map_definition == original_map, "embedded match and exact terrain replace current settings")
	check(verifier.world_state_hash(game.simulation_world, tick, game.game_controller) == saved_hash, "restoration preserves exact authoritative checksum")
	check(game.game_controller.command_queue.size() == 1 and bool(game.game_controller.command_queue[0].params.get("plan_only", false)), "future construction retains planning semantics")
	check(game.game_controller.maximum_command_results == 1024, "loaded live controller bounds acknowledgements")
	check(game.command_feedback_router.event_cursor == game.game_controller.event_stream.latest_sequence(), "feedback starts after restored history")
	for step in range(30):
		game.game_controller.advance_frame(0.05, 1, 2)
		var difference := first_difference(continued_ticks[step], verifier.world_snapshot(game.simulation_world, game.game_controller.tick_index, game.game_controller), "root")
		check(difference.is_empty(), "continued tick %d matches: %s" % [step, difference])
	check(verifier.world_state_hash(game.simulation_world, tick + 30, game.game_controller) == continued_hash, "random state, visibility and gameplay continue identically for 30 ticks")
	var corrupt: Dictionary = archive.duplicate(true)
	corrupt["checkpoint"]["sha256"] = "0".repeat(64)
	check(Archive.write(PATH, corrupt) == OK, "checksum-corrupted fixture reaches loader")
	check(not game.load_game_from_path(PATH) and game.last_save_error == "checkpoint_invalid", "corrupt checkpoint is rejected")
	check(verifier.world_state_hash(game.simulation_world, tick + 30, game.game_controller) == continued_hash, "rejected state leaves running match untouched")
	var invalid: Dictionary = data.duplicate(true)
	invalid["grid"]["size"] = Vector2i(1, 1)
	check(not Checkpoint.validate(invalid), "inconsistent embedded geometry is rejected")
	invalid = data.duplicate(true)
	invalid["world"]["units"].append(invalid["world"]["units"][0].duplicate(true))
	check(not Checkpoint.validate(invalid), "duplicate authoritative entity IDs are rejected")
	game.free()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	for failure in failures: push_error(failure)
	print("Checkpoint resume: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

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

