extends SceneTree
const Ready := preload("res://tests/support/match_ready.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Loading := preload("res://scripts/navigation_loading.gd")
var result: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.trim_prefix("--save=")
	var game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	if not game.load_game_from_path(path): quit(1); return
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	game.set_process(false)
	var seed := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	var input := {"seed": seed, "catalogs": {"gamespec": game.gamespec_data, "terrain": game.resource_catalog.terrain_catalog_data, "objects": game.resource_catalog.object_catalog_data, "graphics": game.resource_catalog.graphics_catalog_data, "runtime": game.resource_catalog.runtime_catalog_data}.duplicate(true)}
	if not await Ready.advance_to_tick(self, game.game_controller, game.game_controller.tick_index + 37, 1, 2): quit(1); return
	input["tick"] = game.game_controller.tick_index
	input["commands"] = game.game_controller.replay_recorder.issuance_records.duplicate(true)
	var expected := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	var thread := Thread.new()
	thread.start(worker.bind(input))
	while thread.is_alive(): await process_frame
	thread.wait_to_finish()
	var actual: Dictionary = result
	print("REPLAY_PROBE equal=", actual == expected)
	for key in expected:
		if expected[key] != actual.get(key): print("REPLAY_DIFF ", key)
	var codec := Replay.new()
	var hash_before := codec.world_state_hash(game.simulation_world, game.game_controller.tick_index, game.game_controller)
	game.free()
	var world = make_world(input["catalogs"], actual["world"]["map_size"])
	var controller := Controller.new(world)
	Checkpoint.restore(actual, world, controller)
	var hash_after := codec.world_state_hash(world, controller.tick_index, controller)
	print("REPLAY_PROBE canonical_equal=", hash_before == hash_after)
	world.shutdown_derived_state()
	quit(0 if hash_before == hash_after else 1)
func make_world(catalogs: Dictionary, size: Vector2i):
	var world := World.new(size)
	world.set_gamespec(catalogs["gamespec"])
	world.set_terrain_catalog(catalogs["terrain"])
	world.set_object_catalog(catalogs["objects"])
	world.set_graphics_catalog(catalogs["graphics"])
	world.set_runtime_catalog(catalogs["runtime"])
	return world
func worker(input: Dictionary) -> void:
	var seed: Dictionary = input["seed"]
	var world = make_world(input["catalogs"], seed["world"]["map_size"])
	var controller := Controller.new(world)
	Checkpoint.restore(seed, world, controller)
	var preparation := Loading.new()
	preparation.coordinator.enabled = false
	preparation.begin(world, seed["match_definition"].get("players", []))
	while not preparation.poll(world): pass
	preparation.shutdown()
	var threshold: int = controller.next_command_sequence
	var records: Array = input["commands"].filter(func(r): return int(r["sequence_id"]) >= threshold)
	var cursor := 0
	var codec := Replay.new()
	while controller.tick_index <= int(input["tick"]):
		while cursor < records.size() and int(records[cursor].get("issued_tick", 0)) <= controller.tick_index:
			controller.enqueue_command(codec.command_from_record(records[cursor]), false)
			cursor += 1
		if controller.tick_index == int(input["tick"]): break
		controller._run_fixed_tick(1,2)
	result = Checkpoint.capture(world, controller, seed["match_definition"], seed["map_definition"])
	world.shutdown_derived_state()
