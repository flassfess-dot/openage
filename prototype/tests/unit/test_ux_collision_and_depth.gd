extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Collision := preload("res://scripts/mobile_collision.gd")
const Scenery := preload("res://scripts/scenery_obstructions.gd")
const Grid := preload("res://scripts/navigation_grid.gd")
const Render := preload("res://scripts/render_world.gd")
var failures: Array[String] = []


func _initialize() -> void:
	test_rock_obstructions()
	test_swept_animal_contact()
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_worker_cannot_cross_animal(catalog, native)
	test_building_depth_in_every_direction()
	for failure in failures:
		push_error(failure)
	print("UX collision and depth: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func test_rock_obstructions() -> void:
	var rocks := Scenery.collect([
		{"id": -4, "asset_name": "aoe2_temperate:boulders", "position": Vector2(8.5, 8.5)},
		{"id": -5, "asset_name": "aoe2_temperate:ror_grass", "position": Vector2(3.5, 3.5)},
	])
	var grid = Grid.new(Vector2i(16, 16))
	grid.configure_terrain(func(_cell): return "grass")
	grid.rebuild([], [], rocks)
	check(not grid.is_walkable(Vector2i(8, 8)) and not grid.can_build([Vector2i(8, 8)]), "boulder body blocks movement and foundations")
	check(grid.is_walkable(Vector2i(3, 3)), "flat grass decoration remains passable")


func test_swept_animal_contact() -> void:
	var worker := {"id": 1, "kind": "villager", "pos": Vector2(3, 5), "footprint_radius": 0.3}
	var animal := {"id": 2, "kind": "gazelle", "team": 0, "pos": Vector2(5, 5), "previous_pos": Vector2(5, 5), "footprint_radius": 0.5, "hp": 20.0}
	check(Collision.constrain(worker, Vector2(10, 0), [animal], 0.5).x < 3.0, "swept check prevents tunnelling through an animal at a large time step")
	animal["hp"] = 0.0
	check(Collision.constrain(worker, Vector2(10, 0), [animal], 0.5) == Vector2(10, 0), "dead animals release their body collision")


func test_worker_cannot_cross_animal(catalog, native: bool) -> void:
	var world = World.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.pathfinder.set_native_enabled(native)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(3.5, 10.5), false)
	var animal: Dictionary = world.add_unit(0, "elephant", Vector2(8.5, 10.5), false)
	world.assign_command_move([worker], Vector2(13.5, 10.5))
	var overlap := false
	for unused in range(450):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index(false)
		var minimum := float(worker["footprint_radius"]) + float(animal["footprint_radius"])
		overlap = overlap or Vector2(worker["pos"]).distance_to(animal["pos"]) < minimum - 0.005
	check(not overlap, "moving worker never penetrates the elephant footprint (native=%s)" % native)


func test_building_depth_in_every_direction() -> void:
	var center := Vector2(10, 10)
	var offsets := [Vector2(-2, -2), Vector2(0, -2), Vector2(2, -2), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2(-2, 2), Vector2(-2, 0)]
	for kind in ["granary", "farm"]:
		for offset in offsets:
			for task in ["move", "gather"]:
				var building := {"id": 100, "kind": kind, "team": 1, "hp": 100.0, "pos": center, "harvestable": kind == "farm", "footprint": {"half_size": Vector2(1.5, 1.5)}}
				var worker := {"id": 1, "kind": "villager", "team": 1, "hp": 25.0, "pos": center + offset, "previous_pos": center + offset * 1.05, "task": task}
				var render = Render.new()
				var project := func(point): return Vector2((point.x - point.y) * 32.0, (point.x + point.y) * 16.0)
				var items: Array = render.create_world_drawables({"buildings": [building], "units": [worker]}, project, 0.5)
				render.refresh_world_drawables(items, project, 0.75)
				var body: Dictionary = items.filter(func(item): return item["kind"] == "unit")[0]
				var structure: Dictionary = items.filter(func(item): return item["kind"] == "building")[0]
				var worker_in_front := items.find(body) > items.find(structure)
				var expected_front: bool = kind == "farm" or offset.x > 0 or offset.y > 0
				check(worker_in_front == expected_front, "%s depth at direction %s while %s remains correct after interpolation" % [kind, offset, task])


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
