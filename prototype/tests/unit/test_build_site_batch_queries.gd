extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")

class ScalarWorld:
	extends "res://scripts/simulation_world.gd"

	func _can_place_foundation(team: int, kind: String, position: Vector2, _mobile_occupied_cells: Variant = null) -> bool:
		return super._can_place_foundation(team, kind, position)

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	var world := World.new(Vector2i(28, 28))
	var scalar := ScalarWorld.new(Vector2i(28, 28))
	_configure(world, catalog)
	_configure(scalar, catalog)
	_compare_placement(world)
	_compare_search(world, scalar)
	# Each query must rebuild the short-lived index after movement or removal.
	for changed in [world, scalar]:
		changed.units[0]["pos"] = Vector2(11.7, 10.3)
		changed.units[2]["pos"] = Vector2(12.0, 12.0)
		changed.units[3]["removed"] = true
		changed.units[4]["hp"] = 0.0
		changed.update_fog_of_war()
	_compare_placement(world)
	_compare_search(world, scalar)
	for changed in [world, scalar]:
		changed.set_resource_amount(1, 1, 0)
	_compare_placement(world)
	_compare_search(world, scalar)
	if failures.is_empty():
		print("Batch build-site placement parity passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _configure(world, catalog) -> void:
	world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 20 else "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource in range(4):
		world.set_resource_amount(1, resource, 1000)
	world.add_unit(1, "villager", Vector2(8.5, 9.5), false)
	world.add_unit(1, "villager", Vector2(18.5, 12.5), false)
	for index in range(24):
		var unit: Dictionary = world.add_unit(1 if index % 2 == 0 else 2, "clubman", Vector2(6.7 + index % 6 * 2.1, 7.0 + index / 6 * 1.3), false)
		unit["footprint_radius"] = [0.0, 0.3, 0.6, 1.0][index % 4]
		if index % 7 == 0:
			unit["hp"] = 0.0
		if index % 11 == 0:
			unit["removed"] = true
	world.add_building(900, "house", Vector2(9.5, 7.5), 1)
	world.add_building(901, "house", Vector2(16.5, 9.5), 2)
	world.update_fog_of_war()

func _compare_placement(world) -> void:
	var occupied: Dictionary = world._mobile_foundation_obstructions()
	for kind in ["house", "barracks", "dock"]:
		for x in [5.0, 6.7, 7.5, 8.7, 10.0, 11.7, 12.0, 12.5, 17.7, 18.5, 19.3, 20.5]:
			for y in [5.5, 7.0, 8.5, 9.7, 11.7, 12.0, 12.5, 14.3]:
				var position := Vector2(x, y)
				var expected: bool = world.can_place_foundation(1, kind, position)
				var expected_reason: String = world.last_build_failure
				var actual: bool = world._can_place_foundation(1, kind, position, occupied)
				_check(actual == expected and world.last_build_failure == expected_reason, "%s at %s preserves validity and failure reason" % [kind, position])

func _compare_search(world, scalar) -> void:
	for settings in [
		{"kinds": ["house", "barracks", "dock"], "gap": 0.0},
		{"kinds": ["house"], "gap": 1.0, "preferred": {"house": [Vector2(8.5, 10.5), Vector2(8.5, 10.5), Vector2(11.5, 11.5)]}},
		{"kinds": ["house", "dock"], "gap": 1.0, "preferred": {"dock": [Vector2(20.5, 12.5), Vector2(21.5, 12.5)]}, "strict": ["dock"]},
	]:
		world.last_build_failure = "keep_previous_failure"
		scalar.last_build_failure = "keep_previous_failure"
		var actual: Dictionary = world.get_local_build_sites(1, settings["kinds"], 6, 5, settings.get("preferred", {}), settings.get("strict", []), settings["gap"])
		var expected: Dictionary = scalar.get_local_build_sites(1, settings["kinds"], 6, 5, settings.get("preferred", {}), settings.get("strict", []), settings["gap"])
		_check(actual == expected, "batch search preserves complete ordered results: %s" % settings)
		_check(world.last_build_failure == "keep_previous_failure", "search preserves previous placement diagnostic")

func _check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
