extends SceneTree

const Ready := preload("res://tests/support/match_ready.gd")
var game
var failures: Array[String] = []
var output := "res://qa/five-issues/live"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var save := "user://saves/autosave.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): save = arg.trim_prefix("--save=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self,game,120000): quit(1); return
	print("Overlap verifier: initial scene ready, loading saved match")
	if not game.load_game_from_path(save): push_error(game.last_save_error); quit(1); return
	print("Overlap verifier: checkpoint restored, waiting for navigation")
	if not await Ready.wait_for_ready(self,game,120000): quit(1); return
	print("Overlap verifier: saved match ready")
	game.join_simulation_owner()
	game.set_process(false)
	game.autosave.enabled = false
	game.game_controller.set_paused(true)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save))
	var ids: Array[int] = []
	for id in saved["view_state"]["control_groups"]["1"]: ids.append(int(id))
	var world = game.simulation_world
	var units: Array = ids.map(func(id):return world.find_unit(id))
	if units.any(func(unit):return unit==null): push_error("saved control group 1 is unavailable"); quit(1); return
	var before := distances(units)
	var center := Vector2.ZERO
	for unit in units: center += Vector2(unit["pos"])/units.size()
	game.player_control_state.replace_or_add(ids,false)
	game.view_zoom = 2.5
	game.center_view_on_world(center)
	await capture("group-before")
	for tick in range(100):
		world.update_units(0.05,1,2)
		world.rebuild_spatial_index(false)
	var after := distances(units)
	for pair in after:
		if float(pair["distance"]) < float(pair["required"])-0.01: failures.append("control group 1 still overlaps: "+str(pair))
	await capture("group-after")
	# Use existing enemy buildings from this same save for the art/depth probes.
	for kind in ["farm","barracks"]:
		var matches: Array = world.buildings.filter(func(building):return building["kind"]==kind and int(building["team"])!=1 and float(building["hp"])>0)
		if matches.is_empty(): continue
		var building: Dictionary = matches[0]
		world.begin_entity_death(building)
		world.advance_death_only(float(building["death_duration"])+0.1)
		var witness: Dictionary = world.add_unit(1,"villager",Vector2(building["pos"])-Vector2(0.1,0.1),false)
		world.rebuild_spatial_index(false)
		world.update_fog_of_war()
		var selected: Array[int] = [int(witness["id"])]
		game.player_control_state.replace_or_add(selected,false)
		game.center_view_on_world(Vector2(building["pos"]))
		await capture(kind+"-ruin")
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"save":save,"ids":ids,"before":before,"after":after,"failures":failures},"\t"))
	for failure in failures: push_error(failure)
	print("Reported save overlap: ","PASSED" if failures.is_empty() else "FAILED", " ",after)
	game.free()
	quit(0 if failures.is_empty() else 1)

func distances(units: Array) -> Array:
	var result := []
	for i in range(units.size()):
		for j in range(i+1,units.size()):
			result.append({"ids":[units[i]["id"],units[j]["id"]],"distance":Vector2(units[i]["pos"]).distance_to(units[j]["pos"]),"required":float(units[i]["footprint_radius"])+float(units[j]["footprint_radius"])})
	return result

func capture(label: String) -> void:
	game.sync_world_state()
	game.refresh_hud_model()
	game.queue_redraw()
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
