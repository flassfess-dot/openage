extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Knowledge := preload("res://scripts/navigation_knowledge_grid.gd")
const Nav := preload("res://scripts/navigation_task_data.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var grid := Grid.new(Vector2i(48, 48))
	grid.configure_terrain(func(_cell): return "grass")
	grid.occupy([Vector2i(3, 3)], "resource", 10)
	var first := Nav.capture_chunked(grid)
	var worker = Nav.create_grid(first)
	var executor := Task.Executor.new()
	var planner = executor.build_planner(first)
	check(is_same(planner, executor.build_planner(first)), "unchanged input retains private planner")
	grid.set_terrain(Vector2i(4, 4), "water")
	grid.occupy([Vector2i(4, 4)], "building", 20)
	var old_route: Array = planner.find_path(Vector2(1.5, 1.5), Vector2(20.5, 20.5))
	var second := Nav.capture_chunked(grid, first)
	check(is_same(first["cell_pages"]["terrain_cells"][Vector2i(2, 2)], second["cell_pages"]["terrain_cells"][Vector2i(2, 2)]), "local update shares distant immutable page")
	check(first["cell_pages"]["terrain_cells"][Vector2i.ZERO][Vector2i(4, 4)] == "grass", "old input keeps source terrain")
	Nav.update_chunked_grid(worker, second)
	check(is_same(planner, executor.build_planner(second)), "topology patch retains planner and derived route caches")
	compare(grid, worker)
	var fresh := Pathfinder.new(Nav.create_grid(second))
	check(planner.find_path(Vector2(1.5,1.5), Vector2(20.5,20.5)) == fresh.find_path(Vector2(1.5,1.5), Vector2(20.5,20.5)), "cached path and native mask invalidate after dynamic blockage")
	check(not old_route.is_empty(), "route cache was populated before the change")
	check(worker.changed_cells_since(int(first["revision"])) != null, "worker retains exact invalidation journal")
	grid.release_occupant([Vector2i(3, 3)], "resource", 10)
	var third := Nav.capture_chunked(grid, second)
	Nav.update_chunked_grid(worker, third)
	compare(grid, worker)
	check(first["cell_pages"]["occupied_cells"][Vector2i.ZERO].has(Vector2i(3, 3)), "released obstacle cannot change old input")
	# A skipped/expired delta requires a full publication, never a partial update.
	for i in range(120): grid.set_terrain_id(Vector2i(i % 48, i / 48), i + 20)
	var full := Nav.capture_chunked(grid, third)
	check(full["changed_pages"] != null and full["changed_pages"].size() < 9, "expired cell journal retains exact bounded page updates")
	check(is_same(third["cell_pages"]["terrain_cells"][Vector2i(2, 2)], full["cell_pages"]["terrain_cells"][Vector2i(2, 2)]), "journal expiry does not recopy a distant map page")
	check(grid.task_page_revisions.size() <= 9, "page history is bounded by map area")
	Nav.update_chunked_grid(worker, full)
	compare(grid, worker)
	var decoded: Dictionary = bytes_to_var(var_to_bytes(full))
	compare(grid, Nav.create_grid(decoded))
	var replacement := Grid.new(grid.size)
	replacement.configure_terrain(func(_cell): return "water")
	var replaced := Nav.capture_chunked(replacement, {}, 1)
	check(not is_same(planner, executor.build_planner(replaced)), "source replacement discards the private planner")
	compare(replacement, executor.planner.grid)
	# A worker that skipped an intermediate publication still rebuilds correctly.
	var skipped = Nav.create_grid(first)
	Nav.update_chunked_grid(skipped, full)
	compare(grid, skipped)
	grid.configure_terrain(func(_cell): return "water")
	var reset := Nav.capture_chunked(grid, full)
	check(reset["changed_pages"] == null, "bulk reset invalidates all pages")
	compare(grid, Nav.create_grid(reset))
	var ragged := Grid.new(Vector2i(35, 19))
	ragged.set_terrain(Vector2i(34, 18), "water")
	compare(ragged, Nav.create_grid(Nav.capture_chunked(ragged)))
	if ClassDB.class_exists("RoRReadModelKernel"):
		var kernel = ClassDB.instantiate("RoRReadModelKernel")
		if kernel.has_method("capture_navigation_pages"):
			var unsafe := {"terrain_cells": {Vector2i.ZERO: {Vector2i.ZERO: RefCounted.new()}}}
			check(kernel.capture_navigation_pages({}, unsafe, [], Vector2i.ONE).is_empty(), "native page sharing rejects unsafe retained objects")
	var knowledge := Knowledge.new(Vector2i(24, 24))
	knowledge.learned[26] = 1
	var learned := Nav.capture_chunked(knowledge)
	knowledge.learned[26] = 0
	check(Nav.create_grid(learned).learned[26] == 1, "knowledge flags are detached")
	for failure in failures: push_error(failure)
	print("Chunked build topology: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func compare(source, target) -> void:
	for field in Nav.CELL_FIELDS:
		if field == "occupied_cells":
			check(source.get(field).keys().size() == target.get(field).size(), "occupation membership count")
			for cell in source.get(field): check(target.get(field).has(cell), "occupation membership")
		else: check(source.get(field) == target.get(field), "current field matches source: " + field)
	for domain in ["land", "water"]:
		for y in range(source.size.y):
			for x in range(source.size.x): check(source.is_walkable_for(Vector2i(x,y), domain) == target.is_walkable_for(Vector2i(x,y), domain), "worker walkability")
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
