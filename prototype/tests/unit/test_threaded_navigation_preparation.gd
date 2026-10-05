extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Knowledge := preload("res://scripts/navigation_knowledge_grid.gd")
const Data := preload("res://scripts/navigation_task_data.gd")
const Task := preload("res://scripts/navigation_preparation_task.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var coordinator := Coordinator.new()
	var grid := Grid.new(Vector2i(16, 16))
	grid.configure_terrain(func(cell): return "water" if cell.x > 8 else "grass")
	var input := Data.capture(grid)
	var outputs := coordinator.run_ordered("navigation_prepare", [{"grid": input, "domain": "land", "restriction": -1}, {"grid": input, "domain": "water", "restriction": -1}], Task.run)
	for output in outputs:
		var domain := String(output["key"]).split(":")[0]
		check(output["mask"] == grid.native_walkability_mask(domain, -1), "walkability matches exact topology")
		check(output["components"] == grid._build_surface_components(domain, -1), "component numbering and traversal match")
	var learned := Knowledge.new(Vector2i(16, 16))
	var learned_output := Task.run({"grid": Data.capture(learned), "domain": "water", "restriction": -1})
	check(learned_output["mask"] == learned.native_walkability_mask("water", -1), "unknown knowledge remains optimistic")
	var request_id := coordinator.submit("navigation_prepare", {"grid": input, "domain": "land", "restriction": -1}, Task.run, 0, 0, {"revision": grid.revision})
	grid.set_terrain(Vector2i(4, 4), "water")
	check(coordinator.collect(request_id, true, {"revision": grid.revision}).is_empty(), "topology change rejects prewarm")
	coordinator.shutdown()
	finish()
