extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Knowledge := preload("res://scripts/navigation_knowledge_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Corridor := preload("res://scripts/formation_corridor.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var grid := Grid.new(Vector2i(48, 32))
	grid.configure_terrain(func(cell): return "water" if cell.x == 15 and cell.y > 5 else "grass")
	grid.occupy([Vector2i(12, 12), Vector2i(11, 12), Vector2i(38, 24)], "building", 9)
	verify(grid)
	var known := Knowledge.new(grid.size)
	for cell in grid.terrain_cells:
		if cell.x > 25: continue
		known.terrain_cells[cell] = grid.terrain_cells[cell]
		known.terrain_ids[cell] = grid.terrain_ids[cell]
		known.learned[cell.y * grid.size.x + cell.x] = 1
	known.occupied_cells = grid.occupied_cells.duplicate(true)
	verify(known)
	for failure in failures: push_error(failure)
	print("Native navigation geometry: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func verify(grid) -> void:
	var planner := Pathfinder.new(grid)
	var reference := Pathfinder.new(grid)
	reference.set_native_enabled(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41721
	for domain in ["land", "water", "amphibious"]:
		var kernel = planner._native_kernel_for(domain, -1)
		if not kernel.has_method("corridor_widths") or not kernel.has_method("is_segment_walkable"):
			check(false, "native geometry methods are available")
			return
		for radius in [0.0, 0.3, 0.5, 1.1]:
			for i in range(120):
				var start := Vector2(rng.randf_range(-1, 49), rng.randf_range(-1, 33))
				var finish := Vector2(rng.randf_range(-1, 49), rng.randf_range(-1, 33))
				check(kernel.is_position_walkable(start, radius) == grid.is_position_walkable_for(start, radius, domain), "position footprint matches reference")
				check(kernel.is_segment_walkable(start, finish, radius) == grid.is_segment_walkable_for(start, finish, radius, domain), "swept footprint matches reference")
				if i < 12:
					var first := Vector2i(start.floor())
					var last := Vector2i(finish.floor())
					check(planner.direct_cell_path(first, last, domain, -1, radius) == reference.direct_cell_path(first, last, domain, -1, radius), "native direct cells preserve trace and diagonal steps")
			for requested in [Vector2i(15, 10), Vector2i(12, 12), Vector2i(-1, 3), Vector2i(48, 31)]:
				check(planner.nearest_walkable(requested, domain, -1, radius) == reference.nearest_walkable(requested, domain, -1, radius), "nearest endpoint preserves ring, distance and row-major ties")
			var cells: Array[Vector2i] = []
			for x in range(1, 47): cells.append(Vector2i(x, 14))
			for maximum in [4, 12]:
				var widths: PackedInt32Array = kernel.corridor_widths(cells, maximum, radius)
				for i in range(cells.size()):
					check(widths[i] == Corridor._available_lateral_width(grid, cells[i], Corridor._route_direction(cells, i), maximum, domain, -1, radius), "corridor width matches reference")
			for segment in [[Vector2(11.7, 11.7), Vector2(13.2, 13.2)], [Vector2(2.5, 2.5), Vector2(2.5, 2.5)], [Vector2(10, 11.5), Vector2(14, 11.5)]]:
				check(kernel.is_segment_walkable(segment[0], segment[1], radius) == grid.is_segment_walkable_for(segment[0], segment[1], radius, domain), "corner, tangent and zero-length cases match")
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
