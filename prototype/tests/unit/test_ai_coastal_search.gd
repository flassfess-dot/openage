extends SceneTree

const Planner := preload("res://scripts/ai_transport_planner.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var failures: Array[String] = []

func _initialize() -> void:
	check(Planner._nearest_coastal_land(Vector2.ZERO, {"land": [Vector2.ONE], "water": []}) == null, "no water yields no coastal land")
	check(Planner._nearest_coastal_land(Vector2.ZERO, {"land": [], "water": [Vector2.ONE]}) == null, "no land yields no coastal land")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	for trial in range(24):
		var land: Array = []
		var water: Array = []
		for index in range(60):
			land.append(Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0)))
			water.append(Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0)))
		var origin := Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		check(Planner._nearest_coastal_land(origin, {"land": land, "water": water}) == reference(origin, land, water), "indexed coast search matches exhaustive search on arbitrary and negative points")
	var tied := [Vector2(1.5, 0.5), Vector2(-0.5, 0.5)]
	check(Planner._nearest_coastal_land(Vector2(0.5, 0.5), {"land": tied, "water": [Vector2(0.5, 1.5)]}) == Vector2(-0.5, 0.5), "equal distances preserve the deterministic coordinate tie-break")
	var land: Array = []
	var water: Array = []
	for index in range(2000):
		land.append(Vector2(index, 0.5))
		water.append(Vector2(index, 1.5))
	var probe := Probe.new()
	check(Planner._nearest_coastal_land(Vector2(1000.0, 0.5), {"land": land, "water": water}, probe) == Vector2(1000.0, 0.5), "large coastal projection finds the nearest shore")
	check(int(probe.counters.get("ai.coast_water_indexed", 0)) == 2000 and int(probe.counters.get("ai.coast_neighbor_comparisons", 0)) <= 10000, "2000 by 2000 search avoids four million pair comparisons")
	test_transport_footprint_approach()
	for failure in failures:
		push_error(failure)
	print("AI coastal search: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func reference(origin: Vector2, land: Array, water: Array) -> Variant:
	var candidates: Array = []
	for point in land:
		if water.any(func(neighbor): return Vector2(point).distance_squared_to(Vector2(neighbor)) <= 2.26):
			candidates.append(point)
	return Planner._nearest(origin, candidates)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_transport_footprint_approach() -> void:
	var water: Array = []
	for y in range(3):
		for x in range(2, 7):
			water.append(Vector2(x, y) + Vector2(0.5, 0.5))
	var landing := Vector2(4.5, 3.5)
	var approach: Variant = Planner._water_approach(landing, {"footprint_radius": 0.75}, {"water": water, "cell_geometry": true})
	check(approach == Vector2(4.5, 1.5), "wide transports approach from open water rather than an endpoint overlapping the beach")
	check(Planner._water_approach(landing, {"footprint_radius": 0.3}, {"water": water, "cell_geometry": true}) == Vector2(4.5, 2.5), "small vessels retain the nearest coastal endpoint")
	check(Planner._water_approach(landing, {"footprint_radius": 0.75}, {"water": [Vector2(4.5, 2.5)], "cell_geometry": true}) == null, "narrow known water cannot trigger repeated impossible transport movement")
