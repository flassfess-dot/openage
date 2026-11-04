extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
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
	production.reset()
	check(production.spawn_geometry_cache.is_empty(),"match reset clears geometry")
	world.shutdown_derived_state()
	check(world.population_cost_cache.is_empty(),"world shutdown clears population metadata")
	for failure in failures: push_error(failure)
	print("Spawn geometry cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
