extends SceneTree
const Ready := preload("res://tests/support/match_ready.gd")
const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"
var failures: Array[String] = []

func create_game() -> Node:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game):
		failures.append("fixture navigation loading did not finish")
	game.set_process(false)
	game.sync_world_state()
	return game

func advance_tick(game) -> void:
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, 1, 2)
	game.sync_world_state()
	game.process_presentation_events()

const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")

func _initialize() -> void:
	var game = await create_game()
	if not failures.is_empty():
		game.free()
		finish("Live gameplay fixture")
		return
	var building: Dictionary = game.simulation_world.get_buildings().filter(func(row): return int(row.get("team", 0)) == 1 and row.get("kind") == "barracks")[0]
	var ids: Array[int] = [int(building["id"])]
	game.player_control_state.replace_or_add(ids, false)
	game.sync_world_state()
	check(flags(game).is_empty(), "producer has no flag before a rally point is assigned")
	var rally := Vector2(12.5, 21.5)
	game.issue_ground_order(rally)
	advance_tick(game)
	check(bool(building["rally_point_set"]) and Vector2(building["rally_point"]).is_equal_approx(rally), "accepted command publishes its explicit rally point")
	var displayed: Array = flags(game)
	check(displayed.size() == 1, "selected producer displays one rally flag")
	if displayed.size() == 1:
		check(Vector2(displayed[0]["world_anchor"]).is_equal_approx(rally), "flag stands at the rally target")
		check(int(displayed[0]["frame_info"].get("graphic_id", -1)) == 322, "rally uses the original flag on a pole")
		check(displayed[0]["frame_info"].get("texture") != null, "original flag sprite is available")
	game.player_control_state.clear()
	game.sync_world_state()
	check(flags(game).is_empty(), "deselecting producer hides its flag")
	game.player_control_state.replace_or_add(ids, false)
	game.sync_world_state()
	check(flags(game).size() == 1, "reselecting producer restores the same flag")
	var previous_units: Dictionary = {}
	for unit in game.simulation_world.get_units(): previous_units[int(unit["id"])] = true
	game.train_unit_from_hud("clubman", int(building["id"]))
	advance_tick(game)
	for _tick in range(1200): advance_tick(game)
	var trained: Array = game.simulation_world.get_units().filter(func(unit): return not previous_units.has(int(unit["id"])) and unit.get("kind") == "clubman" and int(unit.get("team", 0)) == 1 and Vector2(unit["pos"]).distance_to(rally) < 2.0)
	check(not trained.is_empty(), "trained unit travels to the flag's rally point")
	var checkpoint: Dictionary = Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	var restored = World.new(game.map_size)
	restored.set_gamespec(game.resource_catalog.gamespec_data)
	restored.set_object_catalog(game.resource_catalog.object_catalog_data)
	restored.set_graphics_catalog(game.resource_catalog.graphics_catalog_data)
	restored.set_runtime_catalog(game.resource_catalog.runtime_catalog_data)
	var restored_controller = Controller.new(restored)
	check(Checkpoint.restore(checkpoint, restored, restored_controller), "current checkpoint restores the match")
	var restored_building: Variant = restored.find_building(int(building["id"]))
	check(restored_building != null and bool(restored_building.get("rally_point_set", false)) and Vector2(restored_building["rally_point"]).is_equal_approx(rally), "rally flag state survives a current-format checkpoint")
	# Foreign selection never displays another player's private rally point.
	var foreign: Dictionary = game.simulation_world.get_buildings().filter(func(row): return int(row.get("team", 0)) == 2)[0]
	game.simulation_world.set_rally_point(int(foreign["id"]), Vector2(2.5, 10.5))
	var foreign_ids: Array[int] = [int(foreign["id"])]
	game.player_control_state.replace_or_add(foreign_ids, false)
	game.sync_world_state()
	check(flags(game).is_empty(), "enemy producer rally points stay private")
	game.free()
	finish("Live gameplay producer rally flag")

func flags(game) -> Array:
	return game.current_world_drawables().filter(func(item): return item.get("kind") == "rally_flag")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
