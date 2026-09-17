extends SceneTree

const SpatialHash := preload("res://scripts/spatial_hash.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_large_footprint_is_inserted_into_every_cell()
	test_queries_are_unique_filtered_and_stable()
	test_external_neighbor_query_excludes_shared_formation()

	if failures.is_empty():
		print("N-002 spatial hash tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_large_footprint_is_inserted_into_every_cell() -> void:
	var index = SpatialHash.new(1.0)
	var building := {"id": 20, "pos": Vector2(2.0, 2.0)}
	index.insert(building, building["pos"], 1.25, "obstacle")
	assert_equal(index.query_circle(Vector2(0.8, 2.0), 0.01, "obstacle"), [building], "large footprint reaches neighbor bucket")
	assert_equal(index.query_circle(Vector2(3.2, 2.0), 0.01, "obstacle"), [building], "large footprint reaches opposite bucket")


func test_queries_are_unique_filtered_and_stable() -> void:
	var index = SpatialHash.new(1.0)
	var first := {"id": 3, "pos": Vector2(2.2, 2.2), "hp": 20.0, "footprint_radius": 0.8, "minimum_clearance": 0.04}
	var second := {"id": 7, "pos": Vector2(2.8, 2.8), "hp": 20.0, "footprint_radius": 0.8, "minimum_clearance": 0.04}
	var resource := {"id": 5, "pos": Vector2(2.4, 2.4)}
	index.insert(second, second["pos"], 0.8, "unit")
	index.insert(first, first["pos"], 0.8, "unit")
	index.insert(resource, resource["pos"], 0.4, "resource")
	assert_equal(index.query_circle(Vector2(2.5, 2.5), 1.0, "unit"), [first, second], "circle query is unique and stable")
	assert_equal(index.query_aabb(Rect2(2.0, 2.0, 1.0, 1.0), "resource"), [resource], "AABB category query")
	assert_equal(index.query_neighbors(first, 1.5, "unit"), [second], "neighbor query excludes source entity")
	var reusable: Array = [resource]
	index.query_neighbors_into(first, 1.5, "unit", reusable)
	assert_equal(reusable, [second], "reusable neighbor query preserves result and clears prior contents")
	var exact_radius := index.movement_neighbor_radius(first)
	assert_equal(index.query_neighbors(first, exact_radius, "unit"), [second], "derived movement radius retains avoidance neighbor")


func test_external_neighbor_query_excludes_shared_formation() -> void:
	var index = SpatialHash.new(1.0)
	var source := {"id": 1, "pos": Vector2(2.0, 2.0), "formation_group_id": 8, "footprint_radius": 0.3, "minimum_clearance": 0.04}
	var group_member := {"id": 2, "pos": Vector2(2.5, 2.0), "formation_group_id": 8, "footprint_radius": 0.3, "minimum_clearance": 0.04}
	var outsider := {"id": 3, "pos": Vector2(2.0, 2.5), "formation_group_id": 9, "footprint_radius": 0.3, "minimum_clearance": 0.04}
	for unit in [source, group_member, outsider]:
		index.insert(unit, unit["pos"], unit["footprint_radius"], "unit")
	var result: Array = []
	index.query_external_neighbors_into(source, 1.0, 8, result)
	assert_equal(result, [outsider], "shared formation is excluded while outsider remains")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
