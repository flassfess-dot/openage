extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
var failures: Array[String] = []
func _initialize() -> void:
	for native in [false, true]:
		var world = World.new(Vector2i(24, 20))
		world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x == 12 else "grass")
		world.pathfinder.set_native_enabled(native)
		var first: Dictionary = world.add_unit(1, "clubman", Vector2(5.5, 8.5), false)
		var second: Dictionary = world.add_unit(1, "clubman", Vector2(18.5, 8.5), false)
		reveal(world)
		var controller = Controller.new(world)
		var ids: Array[int] = [int(first["id"]), int(second["id"])]
		controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(6.5, 15.5), "LINE", Vector2.DOWN), false, 1)
		controller.advance_frame(0.05, 1, 2)
		check(controller.formation_groups.size() == 2, "same-domain disconnected members form separate groups")
		check(int(first["formation_group_id"]) != int(second["formation_group_id"]), "formation never spans disconnected islands")
		world = World.new(Vector2i(24, 20))
		world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x in range(9, 14) and cell.y in range(6, 11) else "grass")
		world.pathfinder.set_native_enabled(native)
		first = world.add_unit(1, "clubman", Vector2(7.5, 8.5), false)
		second = world.add_unit(1, "clubman", Vector2(15.5, 8.5), false)
		reveal(world)
		controller = Controller.new(world)
		ids = [int(first["id"]), int(second["id"])]
		controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(18.5, 15.5), "LINE", Vector2.DOWN), false, 1)
		controller.advance_frame(0.05, 1, 2)
		check(controller.formation_groups.size() == 1, "lake-separated members in one component remain together")
		check(first.get("diagnostic_reason") != "no_group_route" and second.get("diagnostic_reason") != "no_group_route", "a centroid inside a lake does not break a reachable group route")
	for failure in failures: push_error(failure)
	print("Formation region routes: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func reveal(world) -> void:
	for y in range(world.map_size.y):
		for x in range(world.map_size.x): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
