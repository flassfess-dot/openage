extends SceneTree

const RandomMapZones := preload("res://scripts/random_map_zones.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_open_map_zone_classification()
	_test_path_distance_and_coast_classification()
	_test_unclaimed_component_becomes_frontier()
	_test_generated_map_publishes_deterministic_zones()
	_finish("Random map strategic zone tests passed")


func _test_open_map_zone_classification() -> void:
	var size := Vector2i(21, 11)
	var players := _players([Vector2(3.5, 5.5), Vector2(17.5, 5.5)])
	var zones := RandomMapZones.build(players, size, _filled_terrain(size, 0), [], {
		"profile": "fixture",
		"sanctuary_radius_cells": 2,
		"sanctuary_radius_min_cells": 1,
		"sanctuary_radius_max_cells": 4,
		"frontier_distance_cells": 7,
		"contested_safety_max": 0.12,
		"territory_safety_min": 0.30,
	})
	assert_equal(RandomMapZones.zone_at(zones, size, Vector2i(3, 5)), RandomMapZones.ZONE_SANCTUARY, "player start belongs to its sanctuary")
	assert_equal(RandomMapZones.zone_at(zones, size, Vector2i(10, 5)), RandomMapZones.ZONE_CONTESTED, "equidistant center belongs to the contested band")
	assert_equal(RandomMapZones.zone_at(zones, size, Vector2i(6, 5)), RandomMapZones.ZONE_TERRITORY, "clearly owned nearby cell belongs to player territory")
	assert_equal(RandomMapZones.zone_at(zones, size, Vector2i(8, 5)), RandomMapZones.ZONE_FRONTIER, "transition between ownership and contest becomes frontier")
	assert_equal(_value_sum(zones["zone_counts"]), size.x * size.y, "zone counts cover every map cell")
	assert_equal(zones["sanctuary_cell_count_by_team"]["1"], zones["sanctuary_cell_count_by_team"]["2"], "symmetric starts receive equal sanctuary areas")


func _test_path_distance_and_coast_classification() -> void:
	var size := Vector2i(12, 12)
	var terrain := _filled_terrain(size, 0)
	for y in range(10):
		terrain[y * size.x + 4] = 1
	var zones := RandomMapZones.build(_players([Vector2(1.5, 1.5), Vector2(10.5, 10.5)]), size, terrain, [], {
		"sanctuary_radius_cells": 1,
		"sanctuary_radius_min_cells": 1,
		"sanctuary_radius_max_cells": 2,
		"frontier_distance_cells": 5,
	})
	var resource_index := 1 * size.x + 6
	assert_equal(int(zones["nearest_start_indices"][resource_index]), 1, "ownership follows the traversable route around the water wall")
	assert_equal(int(zones["nearest_start_distances"][resource_index]), 13, "nearest distance includes the detour through the gap")
	assert_true(RandomMapZones.is_coastal_at(zones, size, Vector2i(5, 1)), "land beside the water wall is marked coastal")
	assert_equal(RandomMapZones.zone_at(zones, size, Vector2i(4, 1)), RandomMapZones.ZONE_BLOCKED, "water never receives a land strategy zone")


func _test_unclaimed_component_becomes_frontier() -> void:
	var size := Vector2i(10, 6)
	var terrain := _filled_terrain(size, 0)
	for y in range(size.y):
		terrain[y * size.x + 4] = 1
	var zones := RandomMapZones.build(_players([Vector2(1.5, 2.5)]), size, terrain, [], {
		"sanctuary_radius_cells": 1,
		"sanctuary_radius_min_cells": 1,
		"sanctuary_radius_max_cells": 2,
		"frontier_distance_cells": 4,
	})
	var unclaimed := Vector2i(7, 2)
	var index := unclaimed.y * size.x + unclaimed.x
	assert_equal(int(zones["nearest_start_indices"][index]), -1, "component without a start remains unclaimed")
	assert_equal(RandomMapZones.zone_at(zones, size, unclaimed), RandomMapZones.ZONE_FRONTIER, "unclaimed walkable component is explicit frontier")


func _test_generated_map_publishes_deterministic_zones() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "grasslands"
	settings["seed"] = 41721
	var first := SkirmishSettings.build(settings)
	var second := SkirmishSettings.build(settings)
	assert_true(bool(first.get("valid", false)), "generated fixture builds: %s" % str(first.get("errors", [])))
	assert_true(bool(second.get("valid", false)), "repeated generated fixture builds")
	if not bool(first.get("valid", false)) or not bool(second.get("valid", false)):
		return
	var map_data: Dictionary = first["map_data"]
	var zones: Dictionary = map_data.get("strategic_zones", {})
	var map_size: Vector2i = map_data["size"]
	var cell_count := map_size.x * map_size.y
	assert_equal(zones.get("zone_ids", []).size(), cell_count, "generated zones cover the full map")
	assert_equal(zones.get("nearest_start_indices", []).size(), cell_count, "generated ownership covers the full map")
	assert_equal(zones, second["map_data"]["strategic_zones"], "same seed produces byte-equivalent strategic zones")
	assert_equal(String(zones.get("profile", "")), "grasslands", "zones retain their profile budget identity")
	assert_equal(int(first["map_quality"]["metrics"]["strategic_zone_cell_count"]), cell_count, "quality report audits the published zone grid")
	assert_true(float(first["map_quality"]["metrics"]["sanctuary_balance_ratio"]) > 0.0, "quality report measures sanctuary balance")


func _players(starts: Array) -> Array:
	var result: Array = []
	for index in range(starts.size()):
		result.append({"team": index + 1, "start": starts[index]})
	return result


func _filled_terrain(size: Vector2i, terrain_id: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(size.x * size.y)
	result.fill(terrain_id)
	return result


func _value_sum(values: Dictionary) -> int:
	var result := 0
	for value in values.values():
		result += int(value)
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
