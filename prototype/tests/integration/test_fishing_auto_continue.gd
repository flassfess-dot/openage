extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Commands := preload("res://scripts/commands.gd")
const Controller := preload("res://scripts/game_controller.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	test_continuous_delivery(catalog, false)
	test_continuous_delivery(catalog, true)
	test_full_cargo_remembers_next_shoal(catalog)
	test_own_vision(catalog)
	test_extended_sight_and_ties(catalog)
	test_unreachable_shoal(catalog)
	test_player_orders(catalog)
	if failures.is_empty():
		print("Fishing boats automatically continue within their own sight: tests passed")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func fixture(catalog) -> Dictionary:
	var world := World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(32): terrain.append(1 if x < 24 else 2 if x == 24 else 0)
	var levels: Array[int] = []
	levels.resize(33*33)
	levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": levels})
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(29.5,29.5), false)
	enemy["stance"] = "passive"
	world.add_building(1001, "dock", Vector2(23.5,10.5), 1)
	var boat: Dictionary = world.add_unit(1, "fishing_boat", Vector2(18.5,10.5), false)
	return {"world":world,"boat":boat}

func test_continuous_delivery(catalog, upgraded: bool) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	if upgraded:
		world.grant_technology(1, 102)
		world.grant_technology(1, 4)
		check(boat["source_unit_id"] == 14, "fixture upgrades the boat to Fishing Ship")
	var first: Dictionary = world.add_resource("deep_fish", Vector2(19.5,10.5), 1)
	var second: Dictionary = world.add_resource("whale", Vector2(18.5,13.5), 2)
	var food_before: int = world.get_resource_amount(1,0)
	world.assign_command_gather([boat], first["id"])
	advance_until(world, func():return int(boat["resource_id"]) == int(second["id"]), 400)
	check(first["amount"] == 0, "first shoal is actually harvested")
	check(boat["resource_id"] == second["id"], "boat switches to a different fish kind without a new command")
	check(boat["carried_amount"] == 1.0 and boat["gather_stage"] != "returning", "partial cargo continues to the next shoal")
	advance_until(world, func():return world.get_resource_amount(1,0) == food_before+3 and boat["task"] == "idle", 2400)
	check(world.get_resource_amount(1,0) == food_before+3, "boat delivers both shoals exactly once")
	check(second["amount"] == 0 and boat["task"] == "idle", "boat rests when no fish remains in sight")

func test_full_cargo_remembers_next_shoal(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	boat["carry_capacity"] = 1.0
	var food_before: int = world.get_resource_amount(1,0)
	var first: Dictionary = world.add_resource("deep_fish", Vector2(19.5,10.5), 1)
	var next: Dictionary = world.add_resource("shore_fish", Vector2(18.5,13.5), 2)
	world.assign_command_gather([boat], first["id"])
	advance_until(world, func():return first["amount"] == 0, 400)
	check(boat["resource_id"] == next["id"] and boat["gather_stage"] == "returning", "full cargo remembers the next shoal before sailing to Dock")
	advance_until(world, func():return next["amount"] == 0 and boat["task"] == "idle", 3000)
	check(world.get_resource_amount(1,0) == food_before+3, "boat resumes its selected shoal after every delivery")

func test_own_vision(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	boat["components"]["vision"]["range"] = 2.0
	var food_before: int = world.get_resource_amount(1,0)
	var first: Dictionary = world.add_resource("deep_fish", Vector2(19.5,10.5), 1)
	var outside: Dictionary = world.add_resource("deep_fish", Vector2(18.5,14.5), 2)
	world.add_unit(1, "scout_ship", outside["pos"]+Vector2(1,0), false)
	world.update_fog_of_war()
	check(world.is_entity_visible_to(1,outside), "another ship reveals the distant shoal")
	world.assign_command_gather([boat], first["id"])
	advance_until(world, func():return boat["task"] == "idle", 2000)
	check(outside["amount"] == 2, "allied sight does not grant automatic fishing outside this boat's vision")
	check(world.get_resource_amount(1,0) == food_before+1, "out-of-sight fallback still delivers remaining cargo")

func test_extended_sight_and_ties(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	boat["components"]["vision"]["range"] = 8.0
	var first: Dictionary = world.add_resource("deep_fish", Vector2(19.5,10.5), 1)
	var next: Dictionary = world.add_resource("whale", Vector2(18.5,17.5), 10)
	world.assign_command_gather([boat],first["id"])
	first["amount"] = 0
	world.gathering_system.update_gather_order(boat,.05)
	check(boat["resource_id"] == next["id"], "search follows actual sight beyond the former six-cell radius")
	f = fixture(catalog)
	world = f["world"]
	boat = f["boat"]
	first = world.add_resource("deep_fish", Vector2(19.5,10.5), 1)
	var lower_id: Dictionary = world.add_resource("whale", Vector2(18.5,13.5), 10)
	world.add_resource("shore_fish", Vector2(18.5,7.5), 10)
	world.assign_command_gather([boat],first["id"])
	first["amount"] = 0
	world.gathering_system.update_gather_order(boat,.05)
	check(boat["resource_id"] == lower_id["id"], "equally close shoals have a deterministic ID tie-break")

func test_unreachable_shoal(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(32): terrain.append(1 if x < 14 or (x >=16 and x <=18 and y >=8 and y <=12) else 0)
	world.configure_map_data({"terrain_ids":terrain})
	boat["pos"] = Vector2(12.5,10.5)
	boat["components"]["vision"]["range"] = 8.0
	var first: Dictionary = world.add_resource("deep_fish", Vector2(13.5,10.5), 1)
	world.add_resource("deep_fish", Vector2(16.5,10.5), 10)
	var reachable: Dictionary = world.add_resource("whale", Vector2(12.5,16.5), 10)
	world.assign_command_gather([boat],first["id"])
	first["amount"] = 0
	world.gathering_system.update_gather_order(boat,.05)
	check(boat["resource_id"] == reachable["id"], "boat skips nearer fish in a disconnected pond")

func test_player_orders(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var boat: Dictionary = f["boat"]
	var first: Dictionary = world.add_resource("deep_fish",Vector2(19.5,10.5),1)
	var next: Dictionary = world.add_resource("whale",Vector2(18.5,13.5),10)
	world.assign_command_gather([boat],first["id"])
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(boat["id"])]
	var move := Commands.MoveCommand.new(0,ids,Vector2(15.5,10.5))
	move.params["queue_order"] = true
	controller.enqueue_command(move,true,1)
	controller.process_commands()
	check(OrderPipeline.queued(boat).size() == 1, "explicit movement is queued")
	for unused in range(2000):
		controller.advance_frame(.05,1,2)
		if OrderPipeline.current(boat)["type"] == "move": break
	check(OrderPipeline.current(boat)["type"] == "move" and next["amount"] == 10, "queued movement takes priority over automatic fishing")
	world.assign_command_gather([boat],next["id"])
	controller.enqueue_command(Commands.StopCommand.new(0,ids),true,1)
	controller.process_commands()
	for unused in range(30): world.advance(.05,1,2)
	check(boat["task"] == "idle" and next["amount"] == 10, "Stop keeps a boat idle even with fish in sight")

func advance_until(world, condition: Callable, ticks: int) -> void:
	for unused in range(ticks):
		world.advance(.05,1,2)
		if condition.call(): return

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)