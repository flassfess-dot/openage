extends SceneTree

const Grid := preload("res://scripts/navigation_knowledge_grid.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var grid = Grid.new(Vector2i(400, 400))
	var probe := Probe.new()
	var cells := [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	for cell in cells:
		grid.learned[cell.y * 400 + cell.x] = 1
		grid.terrain_cells[cell] = "water" if cell.x == 4 else "grass"
	grid.occupy([Vector2i(6, 4)], "building", 500)
	for domain in ["land", "water", "air"]:
		probe.clear()
		var mask: PackedByteArray = grid.native_walkability_mask(domain, -1, probe)
		check(mask.size() == 160000 and mask[399 * 400 + 399] == 1, "unknown supergiant terrain remains traversable in %s" % domain)
		for cell in cells:
			check(mask[cell.y * 400 + cell.x] == int(grid.is_walkable_for(cell, domain, -1)), "learned mask preserves domain and obstruction rules")
		check(int(probe.counters.get("navigation.native_mask_evaluated_cells", 0)) == 3, "mask evaluates three learned cells instead of 160000 map cells")
	var planner = Pathfinder.new(grid)
	planner.set_performance_probe(probe)
	if planner.uses_native_kernel():
		probe.clear()
		planner.find_path(Vector2(2.5, 4.5), Vector2(9.5, 4.5), "land", -1, 0.3)
		check(int(probe.counters.get("navigation.native_mask_evaluated_cells", 0)) == 3, "first native command uses the sparse mask")
		grid.release_occupant([Vector2i(6, 4)], "building", 500)
		planner.find_path(Vector2(2.5, 4.5), Vector2(9.5, 4.5), "land", -1, 0.3)
		check(int(probe.counters.get("navigation.native_mask_rebuilds", 0)) == 1 and int(probe.counters.get("navigation.native_mask_updates", 0)) == 1, "known topology changes patch the existing sparse native mask")
	for failure in failures:
		push_error(failure)
	print("Sparse navigation masks: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
