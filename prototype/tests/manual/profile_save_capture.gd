extends SceneTree
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Ready := preload("res://tests/support/match_ready.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.trim_prefix("--save=")
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	if not game.load_game_from_path(path): push_error(game.last_save_error); quit(1); return
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	game.set_process(false)
	for field in Checkpoint.WORLD_FIELDS:
		var stamp := Time.get_ticks_usec()
		var value: Variant = game.simulation_world.get(field)
		var copied: Variant = Data.copy(value)
		print("SAVE_FIELD ", field, " us=", Time.get_ticks_usec() - stamp, " count=", value.size() if value is Array or value is Dictionary else 0)
	for owner in [game.simulation_world.navigation_grid, game.simulation_world.fog_of_war]:
		var fields: Array = Checkpoint.GRID_FIELDS if owner == game.simulation_world.navigation_grid else Checkpoint.FOG_FIELDS
		for field in fields:
			var stamp := Time.get_ticks_usec()
			var copied: Variant = Data.copy(owner.get(field))
			print("SAVE_FIELD ", field, " us=", Time.get_ticks_usec() - stamp)
	for team in game.simulation_world.movement_system.knowledge.entries:
		var stamp := Time.get_ticks_usec()
		var entry: Dictionary = game.simulation_world.movement_system.knowledge.entries[team]
		var copied: Variant = Checkpoint._capture_fields(entry["grid"], Checkpoint.GRID_FIELDS)
		print("SAVE_FIELD knowledge ", team, " us=", Time.get_ticks_usec() - stamp)
	var started := Time.get_ticks_usec()
	var checkpoint := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	print("SAVE_PROFILE checkpoint_us=", Time.get_ticks_usec() - started)
	game.free()
	quit(0)
