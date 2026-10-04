extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
class CountingWorld:
	extends "res://scripts/simulation_world.gd"
	var projections := 0
	func _compact_ai_resource(resource: Dictionary) -> Dictionary:
		projections += 1
		return super._compact_ai_resource(resource)
var failures: Array[String] = []
func _initialize() -> void:
	var world := CountingWorld.new(Vector2i(40, 40))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	for index in range(300):
		var resource: Dictionary = world.add_resource("tree", Vector2(2 + index % 30, 2 + index / 30), 100)
		world.fog_of_war.reveal_explored_cell(2, Vector2i(resource["pos"]))
	var first: Array = world.get_known_ai_resources(2)
	check(first.size() == 300 and world.projections == 300, "initial resource projection builds once")
	var retained: Dictionary = first[10]
	var cached: Dictionary = world.known_resources_by_player[2]
	var changed: Dictionary = world.find_resource(int(retained["id"]))
	changed["amount"] = 40
	world._remember_known_resource(cached, changed)
	var second: Array = world.get_known_ai_resources(2)
	check(is_same(first, second) and is_same(retained, second[10]), "resource deltas retain array and record identity")
	check(int(retained["amount"]) == 40 and world.projections == 301, "one change projects only one resource")
	world._forget_known_resource(cached, int(changed["id"]))
	check(first.size() == 299 and not cached["ai_projection"]["ids"].has(changed["id"]), "forgetting removes only the affected record")
	var secret: Dictionary = world.add_resource("gold_mine", Vector2(38.5, 38.5), 100)
	world.get_known_ai_resources(2)
	check(not cached["ai_projection"]["ids"].has(secret["id"]), "unexplored resources remain private")
	check(world.get_known_ai_resources(3).is_empty(), "another observer has independent memory")
	for failure in failures: push_error(failure)
	print("Incremental AI resources: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
