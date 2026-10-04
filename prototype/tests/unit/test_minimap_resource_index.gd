extends SceneTree
const Index := preload("res://scripts/minimap_resource_index.gd")
const World := preload("res://scripts/simulation_world.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
var failures: Array[String] = []
func _initialize() -> void:
	test_incremental_pixels()
	test_legal_memory_changes()
	test_bounded_queue_and_bulk_recovery()
	test_borrowed_ordered_overview()
	if failures.is_empty():
		print("Explored-map incremental minimap contracts passed")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
func test_incremental_pixels() -> void:
	var index := Index.new()
	var probe := Probe.new()
	var resources := []
	for id in range(10000): resources.append({"id":id,"amount":75,"pos":Vector2(id%100,id/100)})
	var rectangle := Rect2(0,0,200,100)
	var center := Vector2(100,0)
	index.synchronize(resources,null,center,1,rectangle,Callable(),probe)
	_check(probe.counters.get("presentation.minimap.resource_index.resources_visited") == 10000,"first build visits known resources once")
	probe.clear()
	var before: Array = index.synchronize(resources,{},center,1,rectangle,Callable(),probe)
	for resource in resources: resource["amount"] -= 1
	_check(index.synchronize(resources,{},center,1,rectangle,Callable(),probe) == before,"quantity decrements preserve markers")
	_check(probe.counters.get("presentation.minimap.resource_index.resources_visited") == 0,"unchanged marker updates do not scan the explored forest")
	_check(probe.counters.get("presentation.minimap.resource_index.full_rebuilds",0) == 0,"warm updates do not rebuild index")
	var pair := Index.new()
	var a := {"id":1,"amount":75,"pos":Vector2(10,10)}
	var b := {"id":2,"amount":75,"pos":Vector2(10.1,10.1)}
	var c := {"id":3,"amount":75,"pos":Vector2(40,40)}
	_check(pair.synchronize([a,b],null,center,1,rectangle).size() == 1,"overlapping resource marks share one pixel")
	_check(pair.synchronize([], {1:null},center,1,rectangle).size() == 1,"removing one overlapping tree retains the other mark")
	_check(pair.synchronize([], {2:null,3:c},center,1,rectangle) == [Vector2(101,41)],"depletion and new exploration update just their pixels")
	pair.synchronize([c],{},center,2,rectangle)
	_check(pair.pixels == [Vector2(101,81)],"geometry changes reproject all retained markers")
	pair.clear()
	_check(pair.pixels_by_resource_id.is_empty() and pair.counts_by_pixel.is_empty(),"new match clears index")
func test_legal_memory_changes() -> void:
	var world := World.new(Vector2i(40,40))
	var observer: Dictionary = world.add_unit(1,"villager",Vector2(4.5,4.5),false)
	observer["components"]["vision"] = {"enabled":true,"range":4.0}
	var resource: Dictionary = world.add_resource("tree",Vector2(5.5,4.5),75)
	world.update_fog_of_war()
	world.get_known_resources(1)
	_check(world.consume_known_resource_marker_changes(1) == null,"initial consumer requests full build")
	resource["amount"] = 74
	world.mark_known_resource_dirty(resource)
	var changes: Variant = world.consume_known_resource_marker_changes(1)
	_check(changes is Dictionary and changes.is_empty(),"harvesting visible tree does not invalidate minimap marker")
	_check(world.get_known_resources(1)[0]["amount"] == 74,"quantity memory still updates for HUD and AI")
	observer["pos"] = Vector2(32.5,32.5)
	world.update_fog_of_war()
	resource["amount"] = 0
	world.mark_known_resource_dirty(resource)
	changes = world.consume_known_resource_marker_changes(1)
	_check(changes is Dictionary and changes.is_empty(),"hidden depletion does not leak through marker queue")
	_check(world.get_known_resources(1)[0]["amount"] == 74,"hidden resource remains frozen")
	observer["pos"] = Vector2(4.5,4.5)
	world.update_fog_of_war()
	changes = world.consume_known_resource_marker_changes(1)
	_check(changes is Dictionary and changes.has(resource["id"]) and (changes[resource["id"]] == null or changes[resource["id"]].get("amount") == 0),"re-observing depleted tree removes remembered marker")
	var another: Dictionary = world.add_resource("tree",Vector2(6.5,4.5),75)
	world.mark_known_resource_dirty(another)
	changes = world.consume_known_resource_marker_changes(1)
	_check(changes is Dictionary and changes.get(another["id"],{}).get("amount") == 75,"newly observed resource adds a marker")
	var saved: Dictionary = world.known_resource_memory_state()
	world.restore_known_resource_memory(saved)
	_check(world.consume_known_resource_marker_changes(1) == null,"loading resource memory rebuilds derived marker index")
func test_bounded_queue_and_bulk_recovery() -> void:
	var world := World.new(Vector2i(4,4))
	world.get_fog_of_war().reveal_explored_cell(1,Vector2i.ZERO)
	world.get_known_resources(1)
	world.consume_known_resource_marker_changes(1)
	var cached: Dictionary = world.known_resources_by_player[1]
	for id in range(World.MAX_MINIMAP_RESOURCE_CHANGES+32):
		world._mark_known_resource_marker_changed(cached,id)
	_check(cached["marker_changes"].size() <= World.MAX_MINIMAP_RESOURCE_CHANGES,"pending marker queue stays bounded during bulk exploration")
	_check(world.consume_known_resource_marker_changes(1) == null,"bulk overflow requests one safe rebuild")
	_check(world.consume_known_resource_marker_changes(1) == {},"bulk rebuild acknowledgement clears pending work")
func test_borrowed_ordered_overview() -> void:
	var world := World.new(Vector2i(20,20))
	var observer: Dictionary = world.add_unit(1,"villager",Vector2(5.5,5.5),false)
	observer["components"]["vision"] = {"enabled":true,"range":4.0}
	world.add_resource("tree",Vector2(5.5,6.5),75)
	world.add_resource("tree",Vector2(6.5,6.5),75)
	world.update_fog_of_war()
	var known: Array = world.get_known_resources(1)
	var snapshot := Snapshot.presentation(world,0,1,{"include_overview":true,"borrow_overview_entities":true,"include_navigation":false,"include_build_sites":false})
	_check(is_same(snapshot["overview"]["resources"],known),"trusted renderer borrows the already sorted legal resource overview")
	var detached := Snapshot.presentation(world,0,1,{"include_overview":true,"include_navigation":false,"include_build_sites":false})
	detached["overview"]["resources"][0]["amount"] = -999
	_check(known[0]["amount"] == 75,"ordinary snapshot callers retain detached overview records")
func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)