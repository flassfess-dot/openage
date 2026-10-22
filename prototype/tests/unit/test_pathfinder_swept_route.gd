extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	for native in [false, true]:
		var world := World.new(Vector2i(64, 48))
		world.pathfinder.set_native_enabled(native)
		world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 29 and cell.x <= 31 and cell.y != 24 else "grass")
		for endpoints in [[Vector2(27.5, 24.5), Vector2(39.5, 25.5)], [Vector2(28.55335, 24.43371), Vector2(50.5, 27.5)]]:
			var path: Array[Vector2] = world.pathfinder.find_path(endpoints[0], endpoints[1], "land", -1, 0.3)
			check(not path.is_empty() and path.back().is_equal_approx(endpoints[1]), "a valid passage route reaches the exact endpoint")
			var cursor: Vector2 = endpoints[0]
			for point in path:
				check(world.navigation_grid.is_segment_walkable_for(cursor, point, 0.3, "land", -1), "every smoothed segment clears the complete body (native=%s)" % native)
				cursor = point
			check(world.pathfinder.find_path(endpoints[0], endpoints[1], "land", -1, 0.3) == path, "cache reuse preserves the safe route")
		world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Swept route: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
