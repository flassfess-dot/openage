extends SceneTree

const World := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var world = World.new(Vector2i(24, 20))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.navigation_grid.occupy([Vector2i(10, 9)], "static", 900)
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(9.5, 8.6), false)
	unit["formation_group_id"] = 1
	unit["task"] = "move"
	unit["path"] = [Vector2(9.5, 8.5), Vector2(12.5, 10.5)]
	unit["path_index"] = 0
	unit["target"] = unit["path"][0]
	unit["stuck_ticks"] = 24
	world.movement_system._advance_formation_corner(unit, world.pathfinder)
	check(unit["path_index"] == 0, "close corners are retained when the swept footprint would cross an obstacle")
	unit["path"] = [Vector2(9.5, 8.5), Vector2(12.5, 8.5)]
	var published_path: Array = unit["path"]
	world.movement_system._advance_formation_corner(unit, world.pathfinder)
	check(unit["path_index"] == 1 and unit["target"] == Vector2(12.5, 8.5), "a clear next leg continues without crowding the exact corner")
	check(unit["stuck_ticks"] == 24, "advancing a cursor alone never resets the deadlock budget")
	check(is_same(published_path, unit["path"]), "published route stays immutable for suffix distance caches")
	unit["pos"] = Vector2(12.0, 8.5)
	world.movement_system._advance_formation_corner(unit, world.pathfinder)
	check(unit["target"] == Vector2(12.5, 8.5) and unit["path_index"] == 1, "the final reserved position is never accepted early")
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print("Formation corner following: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
