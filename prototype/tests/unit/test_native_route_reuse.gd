extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
var failures: Array[String] = []
func _initialize() -> void:
	for radius in [0.0, 0.3, 0.5, 0.7, 1.2]: verify(radius)
	for failure in failures: push_error(failure)
	print("Native route reuse: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func verify(radius: float) -> void:
	var grid := Grid.new(Vector2i(48, 48))
	grid.configure_terrain(func(cell): return "water" if cell.x in [12,24,36] and cell.y > 2 and cell.y < 45 and not (cell.y >= 15 and cell.y <= 19) and not (cell.y >= 32 and cell.y <= 36) else "grass")
	var planner := Pathfinder.new(grid)
	var reference := Pathfinder.new(grid)
	reference.set_native_enabled(false)
	var start := Vector2i(3, 3)
	var goal := Vector2i(44, 44)
	var expected := reference.find_cell_path(start, goal, "land", -1, radius)
	var kernel = planner._native_kernel_for("land", -1)
	var packed: PackedInt32Array = kernel.find_cell_path(start, goal, radius)
	var labels: PackedInt32Array = kernel.connectivity_labels(radius)
	for index in range(labels.size()):
		check(labels[index] == reference.component_id(Vector2i(index % 48, index / 48), "land", -1, radius), "native component partitions and root IDs match the eight-neighbor reference")
	check(cells(packed) == expected and not expected.is_empty(), "A* preserves exact reference ordering for radius %.2f" % radius)
	var original := packed.duplicate()
	packed[0] = -17
	check(kernel.find_cell_path(start, goal, radius) == original, "caller mutation cannot alter the retained route")
	check(kernel.get_last_expanded_nodes() == 0, "the immediate repeated raw query avoids another A* search")
	check(planner.find_smoothed_cell_path(start, goal, "land", -1, radius) == reference.find_smoothed_cell_path(start, goal, "land", -1, radius), "cached raw route preserves smoothing")
	var retained = kernel.create_search_context()
	var blocked: Vector2i = expected[expected.size() / 2]
	grid.occupy([blocked], "test", 91)
	var fresh := Pathfinder.new(grid)
	fresh.set_native_enabled(false)
	kernel = planner._native_kernel_for("land", -1)
	check(cells(kernel.find_cell_path(start, goal, radius)) == fresh.find_cell_path(start, goal, "land", -1, radius), "a changed walkability generation invalidates the raw route")
	check(retained.find_cell_path(start, goal, radius) == original, "a retained search context keeps its own route generation")
	grid.release_occupant([blocked], "test", 91)
	kernel = planner._native_kernel_for("land", -1)
	check(kernel.find_cell_path(start, goal, radius) == original, "reopening an obstruction restores the reference route")
func cells(packed: PackedInt32Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in range(0, packed.size(), 2): result.append(Vector2i(packed[index], packed[index + 1]))
	return result
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
