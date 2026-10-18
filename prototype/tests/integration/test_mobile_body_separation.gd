extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Collision := preload("res://scripts/mobile_collision.gd")
var failures: Array[String] = []
var catalog

func _initialize() -> void:
	catalog = Catalog.new()
	catalog.load()
	var worker := {"id":1,"kind":"villager","pos":Vector2(3,5),"footprint_radius":0.3}
	var soldier := {"id":2,"kind":"clubman","pos":Vector2(5,5),"previous_pos":Vector2(5,5),"footprint_radius":0.3,"hp":40.0}
	check(Collision.constrain(worker,Vector2(10,0),[soldier],0.5).x < 3, "ordinary soldiers have swept body collision")
	for native in [false, true]:
		test_idle_saved_group(native)
		test_idle_saved_group(native,true)
		test_opposing_units(native)
		test_berry_workers(native)
	for failure in failures: push_error(failure)
	print("Mobile body separation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func configured_world(native: bool):
	var world = World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell):return "grass")
	world.pathfinder.set_native_enabled(native)
	return world

func step(world, count: int) -> void:
	for unused in range(count):
		world.update_units(0.05,1,2)
		world.rebuild_spatial_index(false)

func clear_bodies(units: Array) -> bool:
	for i in range(units.size()):
		for j in range(i+1,units.size()):
			if Vector2(units[i]["pos"]).distance_to(units[j]["pos"]) < float(units[i]["footprint_radius"])+float(units[j]["footprint_radius"])-0.01: return false
	return true

func test_idle_saved_group(native: bool, corner: bool = false) -> void:
	var world = configured_world(native)
	if corner:
		world.navigation_grid.configure_terrain(func(cell):return "grass" if cell.x==10 and cell.y>=8 and cell.y<=12 or cell.y==12 and cell.x>=10 and cell.x<=17 else "water")
	# Actual positions and kinds from control group 1 in the reported autosave,
	# translated onto a small open map. All three were already idle.
	var units := []
	for entry in [["war_elephant",Vector2(10.9372,12.5132)],["elephant_archer",Vector2(10.48,11.4825)],["war_elephant",Vector2(10.4884,11.9488)]]:
		units.append(world.add_unit(1,entry[0],entry[1],false))
	world.rebuild_spatial_index(false)
	check(not clear_bodies(units),"saved group reproduces overlap")
	step(world,80)
	check(clear_bodies(units),"idle saved elephants separate without receiving an order (native=%s corner=%s)" % [native,corner])
	check(units.all(func(unit):return unit["task"]=="idle"),"separation preserves idle orders")
	check(units.all(func(unit):return world.navigation_grid.is_position_walkable_for(unit["pos"],unit["footprint_radius"],unit["movement_domain"],unit["terrain_restriction"])),"separation keeps every footprint clear of terrain")

func test_opposing_units(native: bool) -> void:
	var world = configured_world(native)
	var left: Dictionary = world.add_unit(1,"clubman",Vector2(5,10),false)
	var right: Dictionary = world.add_unit(1,"clubman",Vector2(16,10),false)
	world.assign_command_move([left],Vector2(16,10))
	world.assign_command_move([right],Vector2(5,10))
	var penetrated := false
	for unused in range(400):
		step(world,1)
		penetrated = penetrated or not clear_bodies([left,right])
	check(not penetrated,"opposing soldiers keep body clearance every tick (native=%s)" % native)
	check(left["pos"].x > 14 and right["pos"].x < 7,"opposing soldiers still reach their destinations (native=%s)" % native)

func test_berry_workers(native: bool) -> void:
	var world = configured_world(native)
	world.add_building(900,"granary",Vector2(6,10),1)
	world.set_resource_amount(1,0,0)
	var berries: Dictionary = world.add_resource("berries",Vector2(15.5,15.5),500)
	var workers := []
	for i in range(6): workers.append(world.add_unit(1,"villager",Vector2(11.5,12.0+i),false))
	world.assign_command_gather(workers,int(berries["id"]))
	var penetrated := false
	for unused in range(900):
		step(world,1)
		penetrated = penetrated or not clear_bodies(workers)
	check(not penetrated,"workers gathering one berry bush retain body clearance (native=%s)" % native)
	check(int(berries["amount"]) < 500,"separation still allows harvesting")
	check(world.get_resource_amount(1,0) > 0,"workers complete a harvest/deposit cycle")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
