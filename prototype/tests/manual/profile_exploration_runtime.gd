extends SceneTree
# Exercise the real generated world and presentation at equal viewport/population,
# before and after exploration. Timings are diagnostic, not hardware-dependent tests.
const Settings := preload("res://scripts/skirmish_settings.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var output := "res://qa/exploration-performance-20261003/before.json"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var settings := Settings.default_settings()
	settings["map_size_id"] = "supergiant"
	settings["seed"] = 41721
	for index in range(8): settings["players"][index]["enabled"] = index < 4
	print("Generating supergiant benchmark map")
	var built := Settings.build(settings)
	if not built.get("valid", false):
		push_error(str(built.get("errors")))
		quit(1)
		return
	print("Map generated; booting real match")
	for player in built["definition"]["players"]: player["controller"] = "human"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "benchmark://exploration"
	game.match_definition_override = built["definition"]
	game.map_definition_override = built["map_data"]
	viewport.add_child(game)
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	var scout: Dictionary = game.simulation_world.get_units().filter(func(u): return u["team"] == 1)[0]
	var start: Vector2 = scout["pos"]
	var dirty_resource: Dictionary = game.simulation_world.add_resource("tree",start+Vector2(2,0),1000)
	game.view_zoom = 1.0
	var results := {"renderer":DisplayServer.get_name(),"map_size": [400,400],"world_resources": game.simulation_world.get_resources().size(),"cases":{}}
	for phase in ["small_explored", "fully_explored", "fully_explored_harvesting"]:
		if phase == "fully_explored":
			var fog = game.simulation_world.get_fog_of_war()
			var states: PackedByteArray = fog.states_by_player[1]
			for index in range(states.size()):
				if states[index] == 0: states[index] = 1
			fog.states_by_player[1] = states
			fog.revisions_by_player[1] += 1
			fog.exploration_revisions_by_player[1] += 1
			fog.revision += 1
			game.simulation_world.known_resources_by_player.erase(1)
			game.simulation_world.get_known_resources(1)
			game.cached_overview_tick = -1
			game.cached_world_fog_texture_revision = -1
		for step in range(12):
			scout["pos"] = start + Vector2(step*.23,0)
			game.update_units(.05)
			game.queue_redraw()
			await process_frame
		var probe := Probe.new(512)
		game.game_controller.set_performance_probe(probe)
		var samples := []
		var frame_samples := []
		for step in range(120):
			scout["pos"] = start if phase.ends_with("harvesting") else start + Vector2((step%80)*.23,0)
			if phase.ends_with("harvesting"):
				dirty_resource["amount"] -= 1
				game.simulation_world.mark_known_resource_dirty(dirty_resource)
			var tick_started := Time.get_ticks_usec()
			game.update_units(.05)
			var update_us := Time.get_ticks_usec()-tick_started
			game.queue_redraw()
			await process_frame
			if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
			frame_samples.append(Time.get_ticks_usec()-tick_started)
			samples.append({"tick":game.game_controller.tick_index,"update_us":update_us})
		var report := probe.report()
		results["cases"][phase] = {"probe":report,"ticks":samples,"frame_microseconds":Probe.summarize(frame_samples),"known_resources":game.overview_resource_nodes.size()}
		print("PROFILE ",phase," known=",game.overview_resource_nodes.size())
		var names: Array = report["metrics_microseconds"].keys()
		names.sort_custom(func(a,b):return report["metrics_microseconds"][a]["max"] > report["metrics_microseconds"][b]["max"])
		for index in range(mini(18,names.size())):
			print(names[index]," ",report["metrics_microseconds"][names[index]])
		print("COUNTERS ",report["counters"])
		game.game_controller.set_performance_probe(null)
	if DisplayServer.get_name() != "headless":
		viewport.get_texture().get_image().save_png(output.get_base_dir().path_join("explored-map.png"))
	var path := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	game.free()
	viewport.free()
	quit(0)