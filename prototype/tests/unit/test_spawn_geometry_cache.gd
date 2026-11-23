extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Footprint := preload("res://scripts/footprint.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world := World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data,false)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var dock: Dictionary = world.add_building(700,"dock",Vector2(10.5,10.5),1)
	var production = world.production_system
	for attempt in range(20):
		check(production.free_spawn_position(dock,"scout_ship") == null,"landlocked dock remains blocked")
	check(production.spawn_geometry_cache.size()==1 and production.spawn_geometry_cache[700]["points"].is_empty(),"negative geometry is retained once per producer")
	world.navigation_grid.configure_terrain(func(_cell): return "water")
	var first: Variant = production.free_spawn_position(dock,"scout_ship")
	check(first is Vector2,"opening water invalidates the blocked geometry immediately")
	check(first==production._free_spawn_position_uncached(dock,"scout_ship"),"first valid exit retains original slot order")
	if first is Vector2:
		var blocker: Dictionary = world.add_unit(1,"scout_ship",first,false)
		var occupied: Variant = production.free_spawn_position(dock,"scout_ship")
		check(occupied!=first and occupied==production._free_spawn_position_uncached(dock,"scout_ship"),"new mobile occupancy is read on every attempt")
		world.set_entity_field(blocker,"hp",0.0)
		check(production.free_spawn_position(dock,"scout_ship")==first,"a dead occupant frees its exit in the same tick")
	for index in range(production.MAX_SPAWN_GEOMETRY_ENTRIES+2):
		var other: Dictionary = dock.duplicate()
		other["id"]=1000+index
		production.free_spawn_position(other,"scout_ship")
	check(production.spawn_geometry_cache.size()<=production.MAX_SPAWN_GEOMETRY_ENTRIES,"producer cache has a finite capacity")
	production.unregister_building(1001)
	check(not production.spawn_geometry_cache.has(1001),"building removal drops its cached geometry")
	var base_points: int = world.unit_population_points_cost("clubman",1)
	check(base_points==world._uncached_unit_population_points_cost("clubman",1),"cached population charge agrees with the reference")
	world.grant_technology(1,121)
	check(world.unit_population_points_cost("clubman",1)==world._uncached_unit_population_points_cost("clubman",1) and world.unit_population_points_cost("clubman",1)<base_points,"Logistics invalidates the cached population charge immediately")
	test_dock_exits(world, dock)
	test_dock_between_basins(world, dock)
	production.reset()
	check(production.spawn_geometry_cache.is_empty(),"match reset clears geometry")
	world.shutdown_derived_state()
	check(world.population_cost_cache.is_empty(),"world shutdown clears population metadata")
	for failure in failures: push_error(failure)
	print("Spawn geometry cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func test_dock_exits(world, dock: Dictionary) -> void:
	var grid = world.get_navigation_grid()
	var center: Vector2 = dock["pos"]
	var coast_x := 0
	for cell in dock["occupied_cells"]:
		coast_x = maxi(coast_x, cell.x + 1)
	grid.configure_terrain(func(cell): return "water" if cell.x >= coast_x else "grass")
	var cliff: Array[Vector2i] = []
	for y in range(world.get_map_size().y):
		cliff.append(Vector2i(coast_x, y))
	grid.occupy(cliff, "static_obstruction", 750)
	var footprint := Footprint.mobile("fishing_boat", world.unit_stats("fishing_boat"))
	var radius: float = footprint["movement_radius"]
	check(grid.is_position_walkable_for(Vector2(coast_x + 2.5, center.y), radius, "water", 3), "open sea exists behind the cliff")
	check(world.free_spawn_position(dock, "fishing_boat") == null, "a wider search cannot launch across a cliff separating the entire wharf from the sea")
	grid.release_occupant(cliff, "static_obstruction", 750)
	check(world.free_spawn_position(dock, "fishing_boat") is Vector2, "removing the cliff immediately opens the wharf")

	# A real moored fleet covers all positions from the old 24-sample launch
	# ellipse. Farther berths on the same shore still have a clear route out.
	var old_extent: Vector2 = dock["footprint"]["half_size"] + Vector2.ONE * (radius + 0.35)
	var moored: Array[Dictionary] = []
	var separation: float = 2.0 * radius + footprint["minimum_clearance"]
	for i in range(24):
		var point := center + Vector2.from_angle(TAU * i / 24.0) * old_extent
		if not grid.is_position_walkable_for(point, radius, "water", 3): continue
		if moored.any(func(boat): return point.distance_to(boat["pos"]) < separation): continue
		moored.append(world.add_unit(1, "fishing_boat", point, false))
	check(not moored.is_empty(), "the crowded shore contains real moored boats")
	var outer: Variant = world.free_spawn_position(dock, "fishing_boat")
	check(outer is Vector2, "a crowded inner wharf still launches into the open berthing area")
	if outer is Vector2:
		check(((outer - center) / old_extent).length() > 1.0, "the new berth extends beyond the old ellipse")
		for boat in moored:
			check(outer.distance_to(boat["pos"]) >= separation, "the new hull clears each moored hull")
		check(grid.is_segment_walkable_for(outer, outer + Vector2.RIGHT * 4.0, radius, "water", 3), "the outer berth opens directly to navigable water")
	for boat in moored:
		world.set_entity_field(boat, "hp", 0.0)

	# A large hull moored athwart a three-cell-wide inlet plugs its mouth.
	# A boat can be launched seaward of it or wait until the plug moves.
	var inlet_y := floori(center.y)
	var mouth_x := coast_x + 2
	grid.configure_terrain(func(cell): return "water" if cell.x >= coast_x and (abs(cell.y - inlet_y) <= 1 or cell.x > mouth_x) else "grass")
	var mouth := Vector2(mouth_x + 0.5, center.y)
	var blocking_ship: Dictionary = world.add_unit(1, "scout_ship", mouth, false)
	check(mouth.is_equal_approx(blocking_ship["pos"]), "the blocking hull fits across the mouth")
	var blocked: Variant = world.free_spawn_position(dock, "fishing_boat")
	check(blocked == null or blocked.x >= mouth.x, "a stationary hull cannot trap a newly produced boat on the inside of an inlet")
	world.set_entity_field(blocking_ship, "hp", 0.0)
	check(world.free_spawn_position(dock, "fishing_boat") is Vector2, "a freed inlet is usable again with warm geometry")


func test_dock_between_basins(world, dock: Dictionary) -> void:
	var left: int = world.get_map_size().x
	var right := 0
	for cell in dock["occupied_cells"]:
		left = mini(left, cell.x)
		right = maxi(right, cell.x)
	var y := floori(dock["pos"].y)
	var lake := Vector2i(2, y)
	var sea := Vector2i(29, y)
	var terrain := func(cell):
		if cell.x >= 1 and cell.x < left and absi(cell.y - y) <= 4: return "water"
		if cell.x > right and (absi(cell.y - y) <= 1 or cell.x > right + 8): return "water"
		return "grass"
	var planner = world.pathfinder
	var native_setting: bool = planner.native_enabled
	for use_native in [true, false]:
		planner.native_enabled = use_native
		world.navigation_grid.configure_terrain(terrain)
		var radius := float(Footprint.mobile("fishing_boat", world.unit_stats("fishing_boat"))["movement_radius"])
		check(planner.component_id(lake, "water", 3, radius) >= 0 and planner.component_id(sea, "water", 3, radius) >= 0, "both bodies of water can carry the hull")
		check(not planner.cells_connected(lake, sea, "water", 3, radius), "the isthmus separates the small lake from the sea")
		world.set_rally_point(dock["id"], dock["pos"])
		var standard: Variant = world.free_spawn_position(dock, "fishing_boat")
		check(standard is Vector2 and standard.x > right, "the default berth leads down the narrow channel to the larger sea (native=%s)" % use_native)
		check(world.set_rally_point(dock["id"], Vector2(lake) + Vector2(0.5, 0.5)), "a rally point can be set on the lake")
		var directed: Variant = world.free_spawn_position(dock, "fishing_boat")
		check(directed is Vector2 and directed.x < left, "an explicit reachable lake rally overrides default basin size (native=%s)" % use_native)
	planner.native_enabled = native_setting
