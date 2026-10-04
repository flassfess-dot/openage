extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Commands := preload("res://scripts/commands.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Context := preload("res://scripts/context_resolver.gd")
const Main := preload("res://main.gd")
const Pipeline := preload("res://scripts/order_pipeline.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	test_rally_input_and_replay(catalog)
	test_object_feedback()
	test_builder_continuation(catalog)
	test_farm_preview_validation(catalog)
	test_nearest_deposit_side(catalog)
	test_repeated_shore_fishing(catalog)
	for failure in failures:
		push_error(failure)
	print("UX orders and economy: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func configured(catalog, size := Vector2i(32, 32)):
	var world = World.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_population_housing(1, 100)
	world.set_population_cap(1, 100)
	for type in range(4):
		world.set_resource_amount(1, type, 10000)
	return world


func test_rally_input_and_replay(catalog) -> void:
	var world = configured(catalog)
	var building: Dictionary = world.add_building(900, "town_center", Vector2(9, 9), 1)
	var controller = Controller.new(world)
	var game = Main.new()
	game.simulation_world = world
	game.game_controller = controller
	game.map_size = world.map_size
	game.local_player_team = 1
	game.render_world = null
	var presented := building.duplicate(true)
	presented["command_options"] = {"train": world.get_unit_production_options(900, 1)}
	game.presentation_snapshot = {"buildings": [presented]}
	var selected_ids: Array[int] = [900]
	game.player_control_state.replace_or_add(selected_ids, false)
	var target := Vector2(17.5, 9.5)
	game.issue_order(game.world_to_screen(target))
	controller.tick_index += 1
	controller.process_commands()
	check(Vector2(building["rally_point"]).distance_to(target) < 0.05, "RMB with a selected producer sets its rally point")
	var restored = Replay.new().command_from_record({"type": "set_rally_point", "tick": 2, "unit_ids": [900], "params": Replay.new().encode_variant({"target": target})})
	check(restored != null and restored.command_type() == "set_rally_point" and restored.target == target, "rally command survives replay serialization")
	world.enqueue_unit_production(900, 1, "villager")
	world.update_production(100.0)
	var produced: Array = world.get_units()
	check(not produced.is_empty() and Vector2(produced[0]["destination"]).distance_to(target) < 0.1, "newly trained units receive the building's rally destination")
	var enemy: Dictionary = world.add_building(901, "town_center", Vector2(25, 25), 2)
	var rejected = Commands.SetRallyPointCommand.new(controller.tick_index, [901], Vector2(3, 3))
	controller.enqueue_command(rejected, true, 1)
	controller.process_commands()
	check(not bool(controller.get_command_result(rejected.sequence_id).get("accepted", false)) and enemy["rally_point"] == enemy["pos"], "rally command cannot control another player's building")
	game.free()


func test_object_feedback() -> void:
	var ground := Vector2(8, 8)
	var target := {"id": 77, "entity_type": "building"}
	for kind in ["build", "repair", "return_resources", "attack", "gather", "heal", "board", "move"]:
		check(Context.feedback_marker({"type": kind}, target, ground) is Dictionary, "object %s never generates ground arrows" % kind)
	check(Context.feedback_marker({"type": "move"}, null, ground) == ground, "empty-ground movement keeps its arrow marker")
	check(Context.feedback_marker({"type": "attack"}, null, ground) == null, "targeted orders without an object have no ground movement marker")


func test_builder_continuation(catalog) -> void:
	var world = configured(catalog)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7, 10), false)
	worker["components"]["vision"]["range"] = 7.0
	world.update_fog_of_war()
	var first: Dictionary = world.add_building(910, "house", Vector2(10, 10), 1, false)
	var second: Dictionary = world.add_building(911, "house", Vector2(10, 13), 1, false)
	var third: Dictionary = world.add_building(912, "house", Vector2(13, 13), 1, false)
	world.assign_workers_to_building([worker], first, "build")
	check(first["builders"].is_empty(), "fixture builder is assigned but has not contributed work yet")
	world.complete_foundation(first)
	check(worker["task"] == "build" and int(worker["target_building_id"]) == 911, "every assigned builder continues to a visible nearby foundation")
	world.complete_foundation(second)
	check(worker["task"] == "build" and int(worker["target_building_id"]) == 912, "builder continues through multiple foundations")
	world.complete_foundation(third)
	check(worker["task"] == "idle", "builder completes when no visible foundations remain")


func test_farm_preview_validation(catalog) -> void:
	var world = configured(catalog)
	world.add_unit(1, "villager", Vector2(8, 8), false)
	var farm: Dictionary = world.add_building(920, "farm", Vector2(10, 10), 1)
	check(world.navigation_grid.is_walkable(Vector2i(10, 10)), "completed farm remains passable to workers")
	check(not world.can_place_foundation(1, "farm", Vector2(10, 10)), "preview placement policy rejects overlap with a passable farm")
	check(not world.can_place_foundation(1, "house", Vector2(10, 10)), "preview rejects buildings on farms too")
	check(farm["hp"] > 0.0, "preview validation never mutates the existing farm")


func test_nearest_deposit_side(catalog) -> void:
	var world = configured(catalog)
	var store: Dictionary = world.add_building(930, "town_center", Vector2(15, 15), 1)
	for offset in [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5)]:
		var worker: Dictionary = world.add_unit(1, "villager", Vector2(15, 15) + offset, false)
		var position: Variant = world.dropoff_approach_position(worker, store)
		check(position is Vector2 and (Vector2(position) - Vector2(store["pos"])).dot(offset) > 0.0, "carrier approaches the closest free side from %s" % offset)
		world.release_building_approach_slot(worker)
		worker["target_building_id"] = -1


func test_repeated_shore_fishing(catalog) -> void:
	for native in [false, true]:
		var world = configured(catalog, Vector2i(28, 28))
		world.pathfinder.set_native_enabled(native)
		var ids: Array[int] = []
		for y in range(28):
			for x in range(28):
				ids.append(1 if x <= 6 else 2 if x == 7 else 0)
		var heights: Array[int] = []
		heights.resize(29 * 29)
		heights.fill(0)
		world.configure_map_data({"terrain_ids": ids, "vertex_levels": heights})
		world.add_building(940, "dock", Vector2(5.5, 12.5), 1)
		var boat: Dictionary = world.add_unit(1, "fishing_boat", Vector2(4.5, 17.5), false)
		var fish: Dictionary = world.add_resource("shore_fish", Vector2(6.5, 18.5), 45)
		boat["carry_capacity"] = 10.0
		var food_before: int = world.get_resource_amount(1, 0)
		world.assign_command_gather([boat], int(fish["id"]))
		for unused in range(4500):
			world.update_units(0.05, 1, 2)
			world.rebuild_spatial_index(false)
			if int(boat["deposit_cycles"]) >= 3:
				break
		check(int(boat["deposit_cycles"]) >= 3 and world.get_resource_amount(1, 0) >= food_before + 30, "shore fishing repeats at least three full deliveries (native=%s task=%s stage=%s pos=%s slot=%s)" % [native, boat["task"], boat["gather_stage"], boat["pos"], boat["resource_approach_slot"]])


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
