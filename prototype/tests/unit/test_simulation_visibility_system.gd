extends SceneTree

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const SimulationVisibilitySystem := preload("res://scripts/simulation_visibility_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_visibility_system_matches_fog_reference()
	if failures.is_empty():
		print("I1-005a simulation visibility parity tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_visibility_system_matches_fog_reference() -> void:
	var map_size := Vector2i(16, 16)
	var units: Array = [
		vision_entity(1, 1, Vector2(4.0, 4.0), 4.0),
		vision_entity(2, 2, Vector2(8.0, 4.0), 3.0),
	]
	var buildings: Array = [vision_entity(3, 1, Vector2(3.0, 9.0), 2.0)]
	var reference = FogOfWar.new(map_size)
	var system = SimulationVisibilitySystem.new(map_size, func(): return units, func(): return buildings)

	reference.update(units, buildings)
	system.advance({"tick": 1})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "first player visibility matches reference")
	assert_equal(system.get_fog().snapshot(2), reference.snapshot(2), "second player visibility matches reference")

	reference.set_alliance(1, 2, true)
	system.set_alliance(1, 2, true)
	reference.update(units, buildings)
	system.advance({"tick": 2})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "allied visibility matches reference")

	var observed := {"team": 2, "pos": Vector2(8.0, 4.0)}
	assert_equal(system.is_entity_visible(1, observed), true, "allied entity is visible through query facade")
	units[0]["hp"] = 0.0
	buildings[0]["hp"] = 0.0
	reference.update(units, buildings)
	system.advance({"tick": 3})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "source death transition matches reference")


func vision_entity(id: int, team: int, position: Vector2, sight: float) -> Dictionary:
	return {
		"id": id,
		"team": team,
		"pos": position,
		"hp": 10.0,
		"components": {"vision": {"range": sight, "enabled": true}},
	}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
