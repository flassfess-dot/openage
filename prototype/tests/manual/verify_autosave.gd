extends Node
const Ready := preload("res://tests/support/match_ready.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Commands := preload("res://scripts/commands.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var output := "res://qa/autosave-20261017/verification.json"
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--save="): source = arg.trim_prefix("--save=")
	var path := output.get_base_dir().path_join("autosave-test.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	if "--enable-ai" in OS.get_cmdline_user_args():
		var definition: Dictionary = preload("res://scripts/match_definition.gd").load_json(game.match_path)
		definition["players"][1]["ai"] = {"enabled": true}
		game.match_definition_override = definition
	game.autosave.save_path = path
	get_tree().root.add_child(game)
	print("AUTOSAVE_VERIFY created fixture")
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	if not source.is_empty():
		print("AUTOSAVE_VERIFY loading source")
		check(game.load_game_from_path(source), "source save loads")
		if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	game.set_process(false)
	print("AUTOSAVE_VERIFY ready")
	game.game_controller.set_paused(false)
	var before: int = game.game_controller.tick_index
	if not await Ready.advance_to_tick(get_tree(), game.game_controller, before + 30, 1, 2): get_tree().quit(1); return
	var due_deadline := Time.get_ticks_msec() + 120000
	game.autosave.elapsed = game.autosave.next_save
	while not game.autosave.busy and Time.get_ticks_msec() < due_deadline:
		game._poll_autosave(0.0)
		if not game.autosave.busy:
			if not await Ready.advance_to_tick(get_tree(), game.game_controller, game.game_controller.tick_index + 1, 1, 2): break
			await get_tree().process_frame
	var target: int = game.game_controller.tick_index
	print("AUTOSAVE_VERIFY requested tick=", target, " capture_us=", game.autosave.last_capture_us)
	var expected := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	var capture_us: int = game.autosave.last_capture_us
	check(game.autosave.busy, "periodic autosave starts")
	if not await Ready.advance_to_tick(get_tree(), game.game_controller, target + 8, 1, 2): get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 240000
	while game.autosave.busy and Time.get_ticks_msec() < deadline:
		game._poll_autosave(0.0)
		await get_tree().process_frame
	check(not game.autosave.busy and game.autosave.last_error.is_empty(), "background save completes: " + game.autosave.last_error)
	var worker_us: int = game.autosave.last_worker_us
	var worker_pool_shared: bool = game.autosave.worker_pool_shared
	check(not worker_pool_shared, "recovery work does not occupy the shared gameplay worker pool")
	var saved: Dictionary = Archive.read(path)
	print("AUTOSAVE_VERIFY completed error=", game.autosave.last_error)
	check(bool(saved.get("valid", false)), "autosave archive validates")
	var actual: Dictionary = Checkpoint.unpack(saved.get("archive", {}).get("checkpoint", {}))
	check(actual == expected, "all durable checkpoint data matches the source snapshot")
	if actual != expected:
		for key in expected:
			if actual.get(key) != expected[key]: print("AUTOSAVE_DIFFERENCE ", difference(expected[key], actual.get(key), str(key)))
	var checkpoint_equal := actual == expected
	expected = {}
	actual = {}
	check(game.load_game_from_path(path, saved), "autosave restores through the real loader: " + game.last_save_error)
	game.game_controller.set_paused(true)
	game.set_process(true)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	game.set_process(false)
	check(game.game_controller.tick_index == target, "autosave contains its source tick")
	if source.is_empty():
		await verify_lifecycle(game, path)
	var result := {"passed": failures.is_empty(), "release": not OS.is_debug_build(), "source": source, "tick": target, "capture_us": capture_us, "worker_us": worker_us, "checkpoint_equal": checkpoint_equal, "worker_pool_shared": worker_pool_shared, "failures": failures}
	game.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	for failure in failures: push_error(failure)
	print("AUTOSAVE_VERIFY ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_lifecycle(game, path: String) -> void:
	var elapsed_before: float = game.autosave.elapsed
	game._poll_autosave(120.0)
	check(game.autosave.elapsed == elapsed_before and not game.autosave.busy, "pause does not schedule or age an autosave")
	game.game_controller.set_paused(false)
	game.hud_modal_overlay.show_menu()
	game._poll_autosave(120.0)
	check(game.autosave.elapsed == elapsed_before and not game.autosave.busy, "an open game menu does not age an autosave")
	game.hud_modal_overlay.close()
	game.launcher_suspended = true
	game._poll_autosave(120.0)
	check(game.autosave.elapsed == elapsed_before, "launcher suspension does not age an autosave")
	game.launcher_suspended = false
	var selected: Array[int] = game.player_control_state.selected_ids()
	if not selected.is_empty():
		game.assign_control_group(1)
		var unit: Dictionary = game.simulation_world.find_unit(selected[0])
		game.game_controller.enqueue_command(Commands.MoveCommand.new(game.game_controller.tick_index + 1, selected, Vector2(unit["pos"]) + Vector2(1,0)), true, game.local_player_team)
	if not await Ready.advance_to_tick(get_tree(), game.game_controller, game.game_controller.tick_index + 20, 1, 2): return
	var second_tick := await request_due(game)
	var expected := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	check(not game.autosave.submit({}, game.simulation_world, game.game_controller), "only one autosave may be in flight")
	if not await Ready.advance_to_tick(get_tree(), game.game_controller, second_tick + 10, 1, 2): return
	await wait_save(game)
	var saved := Archive.read(path)
	check(bool(saved.get("valid", false)) and int(saved.get("archive", {}).get("tick", -1)) == second_tick, "second save replaces the same slot")
	check(Checkpoint.unpack(saved.get("archive", {}).get("checkpoint", {})) == expected, "second snapshot includes the new player command and exact progress")
	var entries := Archive.list_saves(path.get_base_dir(), path + ".missing", path)
	check(entries.size() == 1 and entries[0]["slot_name"] == Archive.AUTOSAVE_NAME, "one autosave is discoverable by the shared load-menu catalog")
	game.hud_modal_overlay.set_named_saves(entries)
	check(game.hud_modal_overlay.named_load_options.item_count == 1 and game.hud_modal_overlay.named_load_options.get_item_text(0).contains(Archive.AUTOSAVE_NAME), "in-match load menu displays the autosave")
	if DisplayServer.get_name() != "headless":
		game.hud_modal_overlay.show_menu()
		game.hud_modal_overlay.show_section("load")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path.get_base_dir().path_join("autosave-load-menu.png"))
		game.hud_modal_overlay.close()
	var original := FileAccess.get_file_as_bytes(path)
	var target := await request_due(game)
	check(target >= second_tick and game.autosave.busy, "next autosave starts before cancellation")
	check(game.load_game_from_path(path), "loading cancels an unpublished autosave safely")
	game.game_controller.set_paused(true)
	game.set_process(true)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): return
	game.set_process(false)
	check(FileAccess.get_file_as_bytes(path) == original, "an obsolete worker cannot replace the loaded slot")
	check(game.game_controller.tick_index == second_tick, "cancelled publication leaves the last complete autosave loadable")
	check(game.control_groups.groups.has(1), "control groups survive autosave load")
	check(not FileAccess.file_exists(path + ".bak"), "only one durable autosave is retained")

func request_due(game) -> int:
	game.autosave.elapsed = game.autosave.next_save
	var deadline := Time.get_ticks_msec() + 30000
	while not game.autosave.busy and Time.get_ticks_msec() < deadline:
		game._poll_autosave(0.0)
		if not game.autosave.busy:
			if not await Ready.advance_to_tick(get_tree(), game.game_controller, game.game_controller.tick_index + 1, 1, 2): break
			await get_tree().process_frame
	return game.game_controller.tick_index

func wait_save(game) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while game.autosave.busy and Time.get_ticks_msec() < deadline:
		game._poll_autosave(0.0)
		await get_tree().process_frame
	check(not game.autosave.busy and game.autosave.last_error.is_empty(), "background overwrite completes")

func difference(expected: Variant, actual: Variant, path: String) -> String:
	if typeof(expected) != typeof(actual): return "%s type %s != %s" % [path, typeof(expected), typeof(actual)]
	if expected is Dictionary:
		for key in expected:
			if not actual.has(key): return "%s missing %s" % [path, key]
			if actual[key] != expected[key]: return difference(expected[key], actual[key], path + "." + str(key))
		return "%s size %s != %s" % [path, expected.size(), actual.size()]
	if expected is Array:
		if expected.size() != actual.size(): return "%s size %s != %s" % [path, expected.size(), actual.size()]
		for index in expected.size():
			if expected[index] != actual[index]: return difference(expected[index], actual[index], path + "." + str(index))
	if expected is PackedByteArray or expected is PackedInt32Array:
		if expected.size() != actual.size(): return "%s size %s != %s" % [path, expected.size(), actual.size()]
		for index in expected.size():
			if expected[index] != actual[index]: return "%s.%d %s != %s" % [path, index, expected[index], actual[index]]
	return "%s %s != %s" % [path, expected, actual]
