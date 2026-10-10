extends Node

# Deliberately avoid preloading gameplay scripts: this must report a broken
# exported class registry instead of failing before the smoke check can start.
var tree: SceneTree
var output_path := ""
var save_path := ""
var map_size_id := "compact"
var report: Dictionary = {"passed": false, "stages": []}


func _ready() -> void:
	tree = get_tree()
	call_deferred("run")


func run() -> void:
	Engine.max_fps = 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--save="): save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--map-size="): map_size_id = argument.trim_prefix("--map-size=")
	if output_path.is_empty():
		fail("Pass --output=<report.json> in a writable diagnostic directory")
		return
	report["release"] = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args() and not report["release"]:
		fail("Startup verification must run the exported executable")
		return
	var classes: Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		if String(entry["path"]).begins_with("res://qa/"):
			fail("Diagnostic copy registered as a game class: " + String(entry["path"]))
			return
		classes[String(entry["class"])] = String(entry["path"])
	for expected in ["RoRIsolatedTaskData", "RoRPathfinder", "RoRGameController", "RoRNavigationLoading", "RoRNavigationTaskData", "RoRFormationCorridor", "RoRFormationPreview", "RoRPickingService", "RoRRenderWorld", "RoRSimulationMovementSystem"]:
		if not classes.has(expected) or not String(classes[expected]).begins_with("res://scripts/") or not ResourceLoader.exists(classes[expected]):
			fail("Missing or invalid exported class: " + expected)
			return
	print("PACKAGED_STARTUP class registry OK")
	var launcher = tree.current_scene
	if launcher == null or not launcher.has_method("_launch_custom_skirmish"):
		fail("Startup verification requires the real launcher scene")
		return
	await tree.process_frame
	launcher.screen_buttons["single_player"].pressed.emit()
	launcher.screen_buttons["random_map"].pressed.emit()
	launcher._select_metadata(launcher.setting_controls["map_size_id"], map_size_id)
	launcher.setting_controls["seed"].value = 41721
	launcher.start_button.pressed.emit()
	var game = await wait_for_match("random_map")
	if game == null: return
	if not await check_running(game, "random_map"): return
	if save_path.is_empty():
		save_path = output_path.get_base_dir().path_join("startup-roundtrip.json")
		if not game.save_game_to_path(save_path, "Release startup verification"):
			fail("Could not save temporary verification match: " + String(game.last_save_error))
			return
	report["save_path"] = save_path
	tree.current_scene = null
	game.free()
	await tree.process_frame
	launcher = open_launcher()
	if launcher == null: return
	await tree.process_frame
	launcher._show_save_menu()
	# Use the actual menu load callback, without changing the user's saves.
	launcher.saved_games.assign([{ "path": save_path }])
	launcher.save_list.clear()
	launcher.save_list.add_item("Release startup verification")
	launcher.save_list.select(0)
	launcher._load_selected_save()
	game = await wait_for_match("load_save")
	if game == null: return
	game.game_controller.set_paused(false)
	if not await check_running(game, "load_save"): return
	tree.current_scene = null
	game.free()
	report["passed"] = true
	write_report()
	print("PACKAGED_STARTUP PASSED: random map and saved game both reached running simulation")
	tree.quit(0)


func open_launcher():
	var scene = load("res://launcher.tscn")
	if scene == null or not scene.can_instantiate():
		fail("Cannot load exported launcher")
		return null
	var launcher = scene.instantiate()
	if not launcher.has_method("_launch_custom_skirmish"):
		launcher.free()
		fail("Exported launcher script did not compile")
		return null
	tree.root.add_child(launcher)
	tree.current_scene = launcher
	return launcher


func wait_for_match(stage: String):
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if stage == "load_save" and is_instance_valid(tree.current_scene) and tree.current_scene.has_method("_load_selected_save") and tree.current_scene.current_screen == "saves":
			report["menu_status"] = tree.current_scene.status_label.text if tree.current_scene.status_label != null else ""
			fail("The current save menu rejected the load: " + String(report["menu_status"] ))
			return null
		if is_instance_valid(tree.current_scene) and tree.current_scene.has_method("load_game_from_path"):
			if tree.current_scene.game_controller != null and not tree.current_scene.navigation_loading.is_loading():
				return tree.current_scene
	fail("Match never became ready: " + stage)
	return null


func check_running(game, stage: String) -> bool:
	var initial_tick: int = game.game_controller.tick_index
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if game.game_controller.tick_index >= initial_tick + 10:
			game.current_world_drawables()
			report["stages"].append({"stage": stage, "initial_tick": initial_tick, "final_tick": game.game_controller.tick_index, "map_size": [game.map_size.x, game.map_size.y]})
			print("PACKAGED_STARTUP %s running: tick %d -> %d" % [stage, initial_tick, game.game_controller.tick_index])
			return true
	fail("Simulation did not advance after loading: " + stage)
	return false


func fail(message: String) -> void:
	report["error"] = message
	write_report()
	push_error(message)
	tree.quit(1)


func write_report() -> void:
	if output_path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write startup report: " + output_path)
		return
	file.store_string(JSON.stringify(report, "\t"))
