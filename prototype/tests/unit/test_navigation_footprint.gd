extends SceneTree

const Grid := preload("res://scripts/navigation_grid.gd")
const Finder := preload("res://scripts/pathfinder.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const World := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_circle_clearance()
	test_swept_circle_clearance()
	test_retained_movement_obstacle_removal()
	test_escape_cannot_introduce_new_corner_overlap()
	test_native_clearance_and_movement()
	for failure in failures: push_error(failure)
	print("Navigation footprint: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func test_circle_clearance() -> void:
	for domain in ["land", "water"]:
		var grid := Grid.new(Vector2i(12, 12))
		grid.configure_terrain(func(_cell): return "water" if domain == "water" else "grass")
		grid.occupy([Vector2i(6, 6)], "static", 100)
		check(not grid.is_position_walkable_for(Vector2(5.8, 5.8), 0.3, domain), "diagonal obstacle intersects the circle (%s)" % domain)
		check(grid.is_position_walkable_for(Vector2(5.75, 5.75), 0.3, domain), "a free circle is not replaced by its bounding square (%s)" % domain)
		check(not grid.is_position_walkable_for(Vector2(5.5, 5.5), 1.0, domain), "large circle detects diagonal occupancy (%s)" % domain)
		grid.release_occupant([Vector2i(6, 6)], "static", 100)
		grid.occupy([Vector2i(6, 5)], "static", 101)
		check(not grid.is_position_walkable_for(Vector2(5.5, 5.5), 2.2, domain), "large circle detects obstacles between centre and perimeter (%s)" % domain)
		check(grid.is_position_walkable_for(Vector2(5.5, 5.5), 0.5, domain), "tangency without penetration is legal (%s)" % domain)
		check(not grid.is_position_walkable_for(Vector2(0.2, 3.5), 0.3, domain), "circle cannot overlap the map boundary (%s)" % domain)
		check(grid.is_position_walkable_for(Vector2(0.5, 3.5), 0.5, domain), "circle may touch the map boundary (%s)" % domain)
		grid.set_terrain(Vector2i(4, 4), "grass" if domain == "water" else "water")
		check(not grid.is_position_walkable_for(Vector2(3.8, 3.8), 0.3, domain), "diagonal terrain restrictions obey circle clearance (%s)" % domain)


func test_escape_cannot_introduce_new_corner_overlap() -> void:
	var grid := Grid.new(Vector2i(12, 12))
	grid.configure_terrain(func(_cell): return "grass")
	grid.occupy([Vector2i(6, 6), Vector2i(4, 6)], "static", 100)
	var origin := Vector2(5.9, 5.9)
	check(grid.is_footprint_escape_walkable_for(origin, Vector2(5.85, 5.85), 0.3), "a retreat may temporarily retain the pre-existing overlap")
	check(not grid.is_footprint_escape_walkable_for(origin, Vector2(5.2, 5.8), 0.3), "a retreat cannot introduce an overlap with a new diagonal obstacle")

func test_native_clearance_and_movement() -> void:
	for domain in ["land", "water"]:
		var grid := Grid.new(Vector2i(14, 14))
		grid.configure_terrain(func(_cell): return "water" if domain == "water" else "grass")
		grid.occupy([Vector2i(6, 6)], "static", 100)
		var native := Finder.new(grid)
		check(native.uses_native_kernel(), "native kernel is loaded for footprint regression")
		if not native.uses_native_kernel(): continue
		var reference := Finder.new(grid)
		reference.set_native_enabled(false)
		for radius in [0.3, 0.5, 1.0, 2.2]:
			var cell := Vector2i(5, 5)
			var expected := grid.is_position_walkable_for(Vector2(cell) + Vector2(0.5, 0.5), radius, domain)
			check((native.component_id(cell, domain, -1, radius) >= 0) == expected, "native connectivity uses whole circle (radius=%s domain=%s)" % [radius, domain])
			var start := Vector2(3.5, 5.5)
			var goal := Vector2(9.5, 5.5)
			check(native.find_path(start, goal, domain, -1, radius) == reference.find_path(start, goal, domain, -1, radius), "native paths match reference clearance (radius=%s domain=%s)" % [radius, domain])
		var unit := {
			"id": 1, "kind": "clubman", "team": 1, "pos": Vector2(5.7, 5.7),
			"previous_pos": Vector2(5.7, 5.7), "hp": 20.0, "speed": 1.2,
			"footprint_radius": 0.3, "minimum_clearance": 0.06, "push_priority": 1,
			"cohesion_speed_scale": 1.0, "movement_domain": domain, "terrain_restriction": -1,
		}
		var target := Vector2(9, 9)
		var expected := LocalMovement.calculate(unit.duplicate(true), target, [], grid, 0.2)
		native.prepare_native_movement_snapshot([unit])
		var actual := native.calculate_native_movement(unit, target, 0.2)
		var velocity := Vector2(actual.x, actual.y)
		check(velocity.is_equal_approx(expected["actual_velocity"]), "native corner avoidance matches reference (%s)" % domain)
		var next: Vector2 = unit["pos"] + velocity * 0.2
		check(next.distance_to(Vector2(6, 6)) >= 0.3, "actual movement never penetrates the obstacle corner (%s)" % domain)
		check(grid.is_position_walkable_for(next, 0.3, domain), "actual movement respects whole footprint (%s)" % domain)


func check(value: bool, message: String) -> void:
	if not value: failures.append(message)


func test_swept_circle_clearance() -> void:
	var grid := Grid.new(Vector2i(16, 16))
	grid.configure_terrain(func(_cell): return "grass")
	grid.occupy([Vector2i(6, 6)], "static", 100)
	check(not grid.is_segment_walkable_for(Vector2(5.7, 5.8), Vector2(7.3, 5.8), 0.3), "legal endpoints cannot hide a collision in the middle of a segment")
	check(grid.is_segment_walkable_for(Vector2(5.5, 5.5), Vector2(8.5, 5.5), 0.5), "swept circle tangency remains legal")
	check(not grid.is_segment_walkable_for(Vector2(5.72, 5.85), Vector2(9.5, 5.5), 0.3), "off-centre segment detects an obstacle corner")
	check(grid.is_segment_walkable_for(Vector2(5.72, 5.85), Vector2(5.5, 5.5), 0.3), "return to cell centre safely clears the corner")


func test_retained_movement_obstacle_removal() -> void:
	var world := World.new(Vector2i(16, 16))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(5.7, 5.7), false)
	unit["footprint_radius"] = 0.3
	world.navigation_grid.occupy([Vector2i(6, 6)], "static", 100)
	world.pathfinder.configure_entity_change_source(world)
	world.pathfinder.prepare_native_movement_snapshot([unit])
	check(world.pathfinder.has_native_movement_for(int(unit["id"])), "retained movement regression uses native execution")
	var target := Vector2(9, 9)
	var blocked: Vector4 = world.pathfinder.calculate_native_movement(unit, target, 0.2)
	world.navigation_grid.release_occupant([Vector2i(6, 6)], "static", 100)
	world.pathfinder.prepare_native_movement_snapshot([unit])
	var opened: Vector4 = world.pathfinder.calculate_native_movement(unit, target, 0.2)
	var expected := LocalMovement.calculate(unit.duplicate(true), target, [], world.navigation_grid, 0.2)
	check(Vector2(opened.x, opened.y).is_equal_approx(expected["actual_velocity"]), "retained native kernel observes obstacle removal without a path query")
	check(not Vector2(blocked.x, blocked.y).is_equal_approx(Vector2(opened.x, opened.y)), "removing the obstacle actually changes local movement")
	world.shutdown_derived_state()