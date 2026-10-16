extends SceneTree
const Main := preload("res://main.gd")
const World := preload("res://scripts/simulation_world.gd")
const Item := preload("res://scripts/render_item.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	var game = Main.new()
	game.simulation_world = World.new(Vector2i(8, 8))
	var terrain = game.simulation_world.terrain_elevation
	terrain.set_vertex(Vector2i(2, 2), 2)
	for step in range(120):
		game.view_zoom = float(1 + step % 4)
		game.view_offset = Vector2(step * 1.317, -step * 2.713)
		var point := Vector2(1.25 + float(step % 8) * 0.13, 1.75)
		check(game.world_to_screen(point) == terrain.world_to_screen(point, game.view_zoom, game.view_offset), "retained terrain heights preserve exact projection arithmetic")
	terrain.set_vertex(Vector2i(2, 2), 3)
	var point := Vector2(1.5, 1.5)
	check(game.world_to_screen(point) == terrain.world_to_screen(point, game.view_zoom, game.view_offset), "terrain edits invalidate projected heights")
	terrain.vertex_levels[Vector2i(2, 2)] = 4
	terrain.cache_epoch += 1
	check(game.world_to_screen(point) == terrain.world_to_screen(point, game.view_zoom, game.view_offset), "checkpoint replacement invalidates heights even when the terrain revision repeats")
	for step in range(5000): game.world_to_screen(Vector2(float(step) / 1000.0, 2.5))
	check(game.projected_heights.size() <= game.MAX_PROJECTED_HEIGHTS, "projection history stays bounded while units move")
	game.simulation_world = World.new(Vector2i(4, 4))
	check(game.world_to_screen(point) == game.simulation_world.terrain_elevation.world_to_screen(point, game.view_zoom, game.view_offset), "replacing a world clears its projected heights")
	game.free()
	for failure in failures: push_error(failure)
	print("Projection height cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
