extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Pipeline := preload("res://scripts/order_pipeline.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_pursuit(catalog, native)
		test_stop_and_queue(catalog, native)
	for failure in failures: push_error(failure)
	print("Explicit attack pursuit: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func fixture(catalog, native: bool) -> Dictionary:
	var world = World.new(Vector2i(48, 48))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.pathfinder.set_native_enabled(native)
	world.set_alliance(1, 3, true)
	world.set_alliance(3, 1, true)
	var fighters: Array = []
	var ids: Array[int] = []
	for i in range(3):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(7 + i, 8), false)
		unit["stance"] = "passive"
		fighters.append(unit)
		ids.append(int(unit["id"]))
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10, 8), false)
	target["stance"] = "passive"
	var next: Dictionary = world.add_unit(2, "clubman", Vector2(10, 9), false)
	next["stance"] = "passive"
	var building: Dictionary = world.add_building(1000, "house", Vector2(10, 11), 2)
	var outside: Dictionary = world.add_unit(2, "clubman", Vector2(40, 40), false)
	outside["stance"] = "passive"
	var allied: Dictionary = world.add_unit(3, "clubman", Vector2(10, 10), false)
	allied["stance"] = "passive"
	world.update_fog_of_war()
	return {"world": world, "controller": Controller.new(world), "fighters": fighters, "ids": ids, "target": target, "next": next, "building": building, "outside": outside, "allied": allied}
func submit(f: Dictionary, command) -> void:
	f["controller"].enqueue_command(command, true, 1)
	f["controller"].process_commands()
func test_pursuit(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var controller = f["controller"]
	submit(f, Commands.FormationMoveCommand.new(0, f["ids"], Vector2(8, 8), "LINE", Vector2.RIGHT))
	check(f["fighters"].all(func(unit): return int(unit["formation_group_id"]) >= 0), "fixture starts in a formation")
	submit(f, Commands.AttackCommand.new(0, f["ids"], int(f["target"]["id"])))
	check(f["fighters"].all(func(unit): return int(unit["formation_group_id"]) >= 0 and unit.get("combat_pursuit", false) and unit["formation_slot_mode"] == "released"), "explicit attack releases slots but remembers the formation")
	f["target"]["hp"] = 0
	for tick in range(20): controller.advance_frame(0.05, 1, 2)
	var ids: Array = [int(f["next"]["id"]), int(f["building"]["id"])]
	check(f["fighters"].all(func(unit): return unit["task"] == "attack" and int(unit["target_id"]) in ids), "every actor retargets visible hostiles after its chosen enemy dies (native=%s actors=%s)" % [native, f["fighters"].map(func(unit): return [unit["task"], unit["target_id"], unit["diagnostic_reason"], unit.get("combat_pursuit"), unit["pos"]])])
	check(f["fighters"].all(func(unit): return bool(unit.get("combat_pursuit", false)) and unit["task"] == "attack"), "combat pursuit never returns to its old travel slot")
	f["next"]["hp"] = 0
	for tick in range(20): controller.advance_frame(0.05, 1, 2)
	check(f["fighters"].all(func(unit): return unit["task"] == "attack" and int(unit["target_id"]) == int(f["building"]["id"])), "pursuit continues from units to visible enemy buildings")
	f["building"]["hp"] = 0
	for tick in range(20): controller.advance_frame(0.05, 1, 2)
	check(f["fighters"].all(func(unit): return unit["task"] == "idle"), "allied and unseen enemies are excluded from pursuit")
	check(f["allied"]["hp"] == f["allied"]["max_hp"] and f["outside"]["hp"] == f["outside"]["max_hp"], "pursuit respects diplomacy and field of view")
func test_stop_and_queue(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	submit(f, Commands.AttackCommand.new(0, f["ids"], int(f["target"]["id"])))
	submit(f, Commands.StopCommand.new(0, f["ids"]))
	check(f["fighters"].all(func(unit): return not unit.get("combat_pursuit", false)), "Stop cancels pursuit")
	for tick in range(8): f["controller"].advance_frame(0.05, 1, 2)
	check(f["fighters"].all(func(unit): return unit["task"] == "idle"), "passive actors stay stopped even with a visible enemy")
	submit(f, Commands.AttackCommand.new(f["controller"].tick_index, f["ids"], int(f["target"]["id"])))
	var move = Commands.MoveCommand.new(f["controller"].tick_index, f["ids"], Vector2(4, 20))
	move.params["queue_order"] = true
	submit(f, move)
	f["target"]["hp"] = 0
	for tick in range(8): f["controller"].advance_frame(0.05, 1, 2)
	check(f["fighters"].all(func(unit): return unit["task"] == "move" and not unit.get("combat_pursuit", false)), "a queued manual move takes precedence over automatic retargeting")
	f = fixture(catalog, native)
	submit(f, Commands.AttackCommand.new(0, f["ids"], int(f["target"]["id"])))
	submit(f, Commands.FormationMoveCommand.new(0, f["ids"], Vector2(4, 20), "LINE", Vector2.DOWN))
	check(f["fighters"].all(func(unit): return unit["task"] == "move" and not unit.get("combat_pursuit", false)), "a new formation order also cancels prior combat pursuit")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
