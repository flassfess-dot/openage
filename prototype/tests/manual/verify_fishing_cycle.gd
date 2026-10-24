extends Node

# An exported entry point for the reported saved-match cycle, without writing
# the source archive or the player's autosave. Use a new --output report path.
const Ready := preload("res://tests/support/match_ready.gd")
var game
var output := ""
var report := {"passed":false,"samples":[],"failures":[]}

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var save := ""
	var boat_id := 28341
	var max_ticks := 3600
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save="): save = argument.trim_prefix("--save=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--boat-id="): boat_id = int(argument.trim_prefix("--boat-id="))
		elif argument.begins_with("--max-ticks="): max_ticks = clampi(int(argument.trim_prefix("--max-ticks=")),20,20000)
	if save.is_empty() or output.is_empty() or FileAccess.file_exists(output):
		push_error("Pass a source --save and a new --output report path")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	report["release"] = not OS.is_debug_build() and not OS.has_feature("editor")
	report["save"] = save
	report["boat_id"] = boat_id
	if "--require-release" in OS.get_cmdline_user_args() and not report["release"]:
		finish("Fishing verification requires the actual Release executable")
		return
	var window_mode = get_tree().root.get_node_or_null("WindowMode")
	if window_mode != null:
		window_mode.persist_changes = false
		window_mode.apply_settings(false,Vector2i(1280,720))
	game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.simulation_owner_enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(),game,120000): finish("Initial match did not become ready"); return
	if not game.load_game_from_path(save): finish(String(game.last_save_error)); return
	game.game_controller.set_paused(true)
	if not await Ready.wait_for_ready(get_tree(),game,120000): finish("Saved match did not become ready"); return
	game.join_simulation_owner()
	game.set_process(false)
	game.ai_decision_queue.cancel(game.task_coordinator)
	game.ai_players.clear()
	var boat: Variant = game.simulation_world.find_unit(boat_id)
	if boat == null or String(boat["kind"]) != "fishing_boat": finish("Saved Fishing Boat is unavailable"); return
	var initial_deposits := int(boat["deposit_cycles"])
	report["initial_tick"] = game.game_controller.tick_index
	report["initial_deposits"] = initial_deposits
	if float(boat["carried_amount"]) < float(boat["carry_capacity"]) - 0.0001:
		finish("Saved Fishing Boat does not have full cargo")
		return
	var selected: Array[int] = [boat_id]
	game.player_control_state.replace_or_add(selected,false)
	game.view_zoom = 2.5
	await capture("full-cargo",boat)
	game.game_controller.set_paused(false)
	var returned := false
	for unused in range(ceili(float(max_ticks)/20.0)):
		if not await Ready.advance_to_tick(get_tree(),game.game_controller,game.game_controller.tick_index+20,1,2): finish("Fixed simulation did not advance"); return
		if not returned and String(boat["gather_stage"]) == "returning":
			returned = true
			await capture("returning",boat)
		if int(boat["deposit_cycles"]) > initial_deposits and String(boat["anim_state"]) == "Gather" and float(boat["carried_amount"]) > 0.0:
			var expected_net := 784 if int(boat["source_unit_id"]) == 14 else 43
			var expected_hull := 44 if int(boat["source_unit_id"]) == 14 else 42
			var info: Dictionary = game.unit_frame_info(boat)
			if not returned or int(info.get("graphic_id",-1)) != expected_net or not info.get("composite_parts",[]).any(func(part):return int(part.get("graphic_id",-1)) == expected_hull):
				finish("Resumed fishing did not resolve its net and hull")
				return
			await capture("fishing-net",boat)
			if not await Ready.advance_to_tick(get_tree(),game.game_controller,game.game_controller.tick_index+20,1,2): finish("Fishing simulation stopped"); return
			await capture("fishing-net-later",boat)
			report["passed"] = true
			finish()
			return
	finish("Saved boat did not deliver its cargo and resume fishing within the tick limit")

func capture(label: String,boat: Dictionary) -> void:
	game.center_view_on_world(boat["pos"])
	game.sync_world_state()
	game.refresh_hud_model()
	game.queue_redraw()
	var screenshot := ""
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		screenshot = output.get_basename()+"-"+label+".png"
		if get_tree().root.get_texture().get_image().save_png(screenshot) != OK: report["failures"].append("Could not save "+screenshot)
	var info: Dictionary = game.unit_frame_info(boat)
	var row := {"label":label,"tick":game.game_controller.tick_index,"pos":boat["pos"],"cargo":boat["carried_amount"],"stage":boat["gather_stage"],"anim_state":boat["anim_state"],"graphic":info.get("graphic_id"),"frame":info.get("frame_index"),"deposits":boat["deposit_cycles"],"screenshot":screenshot}
	report["samples"].append(row)
	print("FISHING_CYCLE ",JSON.stringify(row))

func finish(error: String = "") -> void:
	if not error.is_empty(): report["failures"].append(error)
	report["passed"] = bool(report["passed"]) and report["failures"].is_empty()
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write fishing verification report")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	for failure in report["failures"]: push_error(failure)
	print("FISHING_CYCLE ","PASSED" if report["passed"] else "FAILED")
	if is_instance_valid(game): game.free()
	get_tree().quit(0 if report["passed"] else 1)
