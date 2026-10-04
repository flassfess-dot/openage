extends SceneTree

const Finder := preload("res://scripts/pathfinder.gd")
class CountingGrid:
	extends "res://scripts/navigation_grid.gd"
	var checks := 0
	func is_walkable_for(cell: Vector2i, domain: String = "land", restriction: int = -1) -> bool:
		checks += 1
		return super.is_walkable_for(cell, domain, restriction)
var failures: Array[String] = []

func _initialize() -> void:
	for native in [false, true]:
		var grid = CountingGrid.new(Vector2i(40, 40))
		grid.configure_terrain(func(_cell): return "grass")
		var finder = Finder.new(grid)
		finder.set_native_enabled(native)
		grid.checks = 0
		check(finder.find_path(Vector2(3.5, 3.5), Vector2(30.5, 30.5), "water").is_empty(), "land-only water request has no endpoint")
		var initial_checks: int = grid.checks
		check(initial_checks <= 1600, "endpoint search visits map cells once without scanning every ring interior")
		check(finder.find_path(Vector2(3.5, 3.5), Vector2(30.5, 30.5), "water").is_empty() and grid.checks == initial_checks and finder.cache_hits == 1, "repeated failed requests skip endpoint normalization completely")
		grid.configure_terrain(func(_cell): return "water")
		check(not finder.find_path(Vector2(3.5, 3.5), Vector2(30.5, 30.5), "water").is_empty(), "changed terrain invalidates the cached endpoint failure")
		grid.occupy([Vector2i(30, 30)], "building", 100)
		var first: Array = finder.find_path(Vector2(3.5, 3.5), Vector2(30.5, 30.5), "water")
		var before: int = grid.checks
		check(not first.is_empty() and first.back() != Vector2(30.5, 30.5), "blocked endpoint still selects a legal nearest cell")
		check(finder.find_path(Vector2(3.5, 3.5), Vector2(30.5, 30.5), "water") == first and grid.checks == before, "cached successful requests also avoid repeating endpoint correction")
	for failure in failures:
		push_error(failure)
	print("Rejected path cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
