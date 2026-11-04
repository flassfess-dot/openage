extends RefCounted
const Ready := preload("res://tests/support/match_ready.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Commands := preload("res://scripts/commands.gd")

static func failed(game, message: String) -> Array[String]:
	game.free()
	return [message]

static func verify(tree: SceneTree, output: String) -> Array[String]:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var previous_limit := Engine.max_fps
	Engine.max_fps=60
	var game=load("res://main.tscn").instantiate()
	game.autosave.enabled=false
	game.match_path="res://tests/fixtures/e3_save_state_matrix_match.json"
	tree.root.add_child(game)
	if not await Ready.wait_for_ready(tree,game,120000):return failed(game,"autosave process match not ready")
	game.set_process(false)
	game.join_simulation_owner()
	var unit: Dictionary=game.simulation_world.units[0]
	var saved_path: Variant=unit.get("_formation_path_cache")
	var saved_steering: Variant=unit.get("formation_steering_target")
	var had_path := unit.has("_formation_path_cache")
	var had_steering := unit.has("formation_steering_target")
	unit["_formation_path_cache"]={"contract":true}
	unit["formation_steering_target"]=Vector2(12,34)
	var before := var_to_bytes(unit)
	var detached: Dictionary=Checkpoint.capture(game.simulation_world,game.game_controller,game.match_definition,game.map_definition)
	var view: Dictionary=Checkpoint.capture(game.simulation_world,game.game_controller,game.match_definition,game.map_definition,false)
	if var_to_bytes(detached)!=var_to_bytes(view) or var_to_bytes(unit)!=before:return failed(game,"owned view changed bytes or source fields")
	detached={};view={}
	if had_path:unit["_formation_path_cache"]=saved_path
	else:unit.erase("_formation_path_cache")
	if had_steering:unit["formation_steering_target"]=saved_steering
	else:unit.erase("formation_steering_target")
	game.autosave.enabled=true
	game.autosave.save_path=output
	game._seed_autosave()
	if game.autosave._process_channel==null:return failed(game,"supported process mode not prepared")
	game.game_controller.set_paused(false)
	game.game_controller.set_speed_multiplier(1.0)
	game.set_process(true)
	var last_tick := -1
	for index in range(3):
		var initial: int=game.game_controller.tick_index
		if index>0:
			var actor: Dictionary=game.simulation_world.units.filter(func(u):return int(u.get("team",0))==game.local_player_team)[0]
			game.game_controller.enqueue_command(Commands.MoveCommand.new(initial+1,[int(actor["id"])],Vector2(actor["pos"])+Vector2(1 if index==1 else -1,0)))
		if index==2:game.autosave._process_channel.stop()
		while game.game_controller.tick_index<initial+4:await tree.process_frame
		game.autosave.elapsed=game.autosave.next_save
		var deadline := Time.get_ticks_msec()+60000
		while game.autosave.last_tick<=last_tick and Time.get_ticks_msec()<deadline:
			await tree.process_frame
			if not game.autosave.last_error.is_empty():return failed(game,game.autosave.last_error)
		if game.autosave.last_tick<=last_tick or not game.autosave.worker_process_isolated:return failed(game,"isolated save did not complete")
		var loaded := Archive.read(output)
		if not bool(loaded.get("valid",false)) or Checkpoint.unpack(loaded["archive"]["checkpoint"]).is_empty():return failed(game,"process checkpoint unreadable")
		last_tick=game.autosave.last_tick
	var previous_slot := FileAccess.get_file_as_bytes(output)
	game.autosave.elapsed=game.autosave.next_save
	var deadline := Time.get_ticks_msec()+5000
	while not game.autosave.busy and Time.get_ticks_msec()<deadline:await tree.process_frame
	if not game.autosave.busy:return failed(game,"active save cancellation not exercised")
	game.set_process(false)
	var base: String=game.autosave._process_channel.base
	var native=game.autosave._process_channel.kernel
	game.free()
	Engine.max_fps=previous_limit
	if FileAccess.get_file_as_bytes(output)!=previous_slot:return ["cancellation replaced committed slot"]
	if native.background_process_running() or FileAccess.file_exists(base+".seed") or FileAccess.file_exists(base+".job"):return ["process or IPC survived shutdown"]
	print("Autosave process: exact owned view, repeated jobs, recorded commands, restart and cancellation passed")
	return []
