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
	var cached_rows: Array = world.get_known_ai_resources(2)
	var first := cached_rows.duplicate()
	check(first.size() == 300 and world.projections == 300, "initial resource projection builds once")
	var retained: Dictionary = first[10]
	var cached: Dictionary = world.known_resources_by_player[2]
	var changed: Dictionary = world.find_resource(int(retained["id"]))
	changed["amount"] = 40
	world._remember_known_resource(cached, changed)
	var updated_rows: Array = world.get_known_ai_resources(2)
	var second := updated_rows.duplicate()
	check(is_same(cached_rows, updated_rows) and is_same(first[9], second[9]) and not is_same(retained, second[10]), "resource deltas reuse the internal list and unchanged rows, replacing only the changed record")
	check(int(retained["amount"]) == 100 and int(second[10]["amount"]) == 40 and world.projections == 301, "one change projects only one resource and preserves its previous published record")
	world._forget_known_resource(cached, int(changed["id"]))
	check(world.get_known_ai_resources(2).size() == 299 and first.size() == 300 and second.size() == 300 and not cached["ai_projection"]["ids"].has(changed["id"]), "forgetting removes only the affected cached record and preserves published lists")
	var secret: Dictionary = world.add_resource("gold_mine", Vector2(38.5, 38.5), 100)
	world.get_known_ai_resources(2)
	check(not cached["ai_projection"]["ids"].has(secret["id"]), "unexplored resources remain private")
	check(world.get_known_ai_resources(3).is_empty(), "another observer has independent memory")
	for failure in failures: push_error(failure)
	print("Incremental AI resources: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
