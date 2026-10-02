extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(Vector2i(400, 400))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.begin_bulk_load()
	for index in range(10000): world.add_scenario_resource("tree", Vector2(index % 100 + 0.5, int(index / 100) + 0.5), 75)
	var trees: Array = world.get_resources()
	for index in [1, 2, 3]:
		var tree: Dictionary = trees[index]
		tree["tree_phase"] = "falling"
		tree["tree_fall_elapsed"] = 0.0
		world.falling_resource_nodes.append(tree)
	# A lifecycle update touches the three scheduled trees, independent of the
	# ten thousand untouched forest entities. No world-size scan or nav rebuild.
	var revision: int = world.navigation_grid.revision
	world.advance_resource_lifecycle(0.2)
	check(world.falling_resource_nodes.size() == 3, "only three animated trees are scheduled")
	check(trees[0]["tree_fall_elapsed"] == 0 and trees[9999]["tree_fall_elapsed"] == 0, "standing forest remains untouched")
	check(world.navigation_grid.revision == revision, "tree fall does not rebuild navigation")
	world.advance_resource_lifecycle(0.5)
	check(world.falling_resource_nodes.is_empty(), "finished animation removes all lifecycle work")
	for tick in range(100): world.advance_resource_lifecycle(0.05)
	check(trees[1]["tree_fall_elapsed"] < 1.0, "landed tree is no longer updated every tick")
	for failure in failures: push_error(failure)
	print("Supergiant forest lifecycle budget: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
