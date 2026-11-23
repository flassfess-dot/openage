extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Footprint := preload("res://scripts/footprint.gd")

var failures: Array[String] = []
var catalog := Catalog.new()


func _initialize() -> void:
	catalog.load_generated_data()
	test_allied_clearance()
	test_rejected_clearance()
	test_adjacent_wall_foundations(false)
	test_adjacent_wall_foundations(true)
	test_intruder()
	test_farm()
	for failure in failures:
		push_error(failure)
	print("Foundation clearance and farm hut: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func make_world():
	var world := World.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_resource_amount(1, 1, 1000)
	return world


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func test_allied_clearance() -> void:
	var world = make_world()
	var controller := Controller.new(world)
	var site := Vector2(12.5, 12.5)
	var builder: Dictionary = world.add_unit(1, "villager", site, false)
	var ally: Dictionary = world.add_unit(2, "clubman", site + Vector2(0.7, 0), false)
	world.add_unit(3, "villager", Vector2(22, 22), false)
	world.set_alliance(1, 2)
	world.update_fog_of_war()
	check(world.can_place_foundation(1, "house", site), "preview accepts allied occupants")
	check(builder.task == "idle" and ally.task == "idle", "preview leaves both orders alone")
	var foundation: Variant = world.assign_command_build([builder], "house", site)
	check(foundation != null, "confirm reserves the house")
	if foundation == null:
		return
	check(foundation.get("clearance_slots", {}).size() == 2, "builder and allied soldier both receive exits")
	check(builder.pos == site and ally.pos == site + Vector2(0.7, 0), "evacuation starts without teleportation")
	check(builder.task == "build" and ally.task == "move", "builder retains build order")
	check(world.navigation_grid.is_walkable(Vector2i(site.floor())), "site stays open during evacuation")
	check(not world.can_place_foundation(1, "house", site), "another foundation cannot overlap the reserved site")
	controller.advance_frame(0.05, 1, 2)
	check(is_zero_approx(foundation.construction_progress), "builders wait for clearance")
	var data := Checkpoint.capture(world, controller, {}, {})
	var restored = make_world()
	var resumed := Controller.new(restored)
	check(Checkpoint.restore(data, restored, resumed), "checkpoint during evacuation restores")
	var house: Dictionary = restored.find_building(foundation.id)
	var worker: Dictionary = restored.find_unit(builder.id)
	var soldier: Dictionary = restored.find_unit(ally.id)
	for tick in range(1200):
		resumed.advance_frame(0.05, 1, 2)
		if house.state == "complete":
			break
	check(house.state == "complete", "saved builder clears and finishes the house tick=%s over=%s slots=%s worker=%s/%s/%s/%s soldier=%s/%s/%s/%s" % [resumed.tick_index,restored.battle_over, house.get("clearance_slots"), worker.pos,worker.task,worker.destination,worker.get("diagnostic_reason"),soldier.pos,soldier.task,soldier.destination,soldier.get("diagnostic_reason")])
	check(not restored.building_placement_system.mobile_footprint_overlaps_cells(worker, house.occupied_cells), "worker ends outside the house")
	check(not restored.building_placement_system.mobile_footprint_overlaps_cells(soldier, house.occupied_cells), "allied soldier ends outside the house")
	check(not restored.navigation_grid.is_walkable(Vector2i(site.floor())), "cleared house closes to traffic")
	check(Vector2(soldier.pos).distance_to(worker.pos) >= 0.5, "occupants have separate exits")
	world.shutdown_derived_state()
	restored.shutdown_derived_state()


func test_rejected_clearance() -> void:
	var world = make_world()
	var site := Vector2(12.5, 12.5)
	var worker: Dictionary = world.add_unit(1, "villager", site, false)
	var enemy: Dictionary = world.add_unit(2, "villager", site + Vector2(0.5, 0), false)
	world.update_fog_of_war()
	check(world.place_foundation(1, "house", site) == null, "hostile occupant blocks confirmation")
	check(enemy.task == "idle" and worker.task == "idle", "rejected placement issues no orders")
	enemy["hp"] = 0.0
	var cells: Array = Footprint.building(world.building_placement_stats("house"), site).occupied_cells
	var ring: Array = []
	for cell in cells:
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if next not in cells and next not in ring:
				ring.append(next)
	world.configure_static_obstructions([{"id": 42, "occupied_cells":ring}])
	check(world.place_foundation(1, "house", site) == null, "surrounded unit has no legal exit")
	check(world.get_resource_amount(1, 1) == 1000, "rejected placement is free")
	world.shutdown_derived_state()


func test_adjacent_wall_foundations(two_workers: bool) -> void:
	var world = make_world()
	var site := Vector2(10.5, 10.5)
	var unit: Dictionary = world.add_unit(1, "villager", site, false)
	var second: Dictionary = world.add_unit(1, "villager", site + (Vector2.RIGHT if two_workers else Vector2(5, 0)), false)
	world.update_fog_of_war()
	var walls: Array = []
	for offset in [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var wall: Variant = world.foundation_system.reserve_planned_wall(1, site + offset)
		check(wall != null, "adjacent wall reserves a legal site")
		if wall != null:
			walls.append(wall)
	for tick in range(200):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index(false)
		if world.foundation_system.pending_clearance.is_empty():
			break
	check(world.foundation_system.pending_clearance.is_empty(), "adjacent walls leave escape routes")
	for wall in walls:
		check(not world.building_placement_system.mobile_footprint_overlaps_cells(unit, wall.occupied_cells), "first unit exits every wall segment")
		check(not world.building_placement_system.mobile_footprint_overlaps_cells(second, wall.occupied_cells), "second unit exits every wall segment")
	world.shutdown_derived_state()


func test_intruder() -> void:
	var world = make_world()
	var site := Vector2(12.5, 12.5)
	var builder: Dictionary = world.add_unit(1, "villager", site, false)
	world.update_fog_of_war()
	var house: Variant = world.assign_command_build([builder], "house", site)
	if house == null:
		failures.append("test house for intruder must reserve")
		return
	var intruder: Dictionary = world.add_unit(2, "villager", site + Vector2(0.8, 0), false)
	for tick in range(100):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index(false)
		if not world.building_placement_system.mobile_footprint_overlaps_cells(builder, house.occupied_cells):
			break
	check(intruder.task == "idle", "an enemy entering an accepted site receives no order")
	check(not world.building_placement_system.mobile_footprint_overlaps_cells(builder, house.occupied_cells), "builder still exits when an enemy enters")
	check(house.has("clearance_slots") and house.construction_progress == 0.0, "construction waits for enemy to leave")
	world.shutdown_derived_state()


func test_farm() -> void:
	var world = make_world()
	world.grant_technology(1, 101)
	world.add_building(900, "market", Vector2(4, 4), 1)
	var center := Vector2(12.5, 12.5)
	var hut := Vector2i((center + Footprint.FARM_HUT_OFFSET).floor())
	var worker: Dictionary = world.add_unit(1, "villager", center - Vector2(2, 0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", center + Vector2(0, 1), false)
	world.update_fog_of_war()
	var farm: Variant = world.place_foundation(1, "farm", center, [worker])
	check(farm != null, "field may be placed under an enemy military unit")
	if farm == null:
		return
	check(enemy.task == "idle" and not farm.has("clearance_slots"), "military unit standing on crops keeps its order")
	check(not world.navigation_grid.is_walkable(hut), "hut obstructs its artwork cell during planting")
	world.complete_foundation(farm)
	world.rebuild_navigation_grid()
	for cell in farm.occupied_cells:
		check(world.navigation_grid.is_walkable(cell) == (cell != hut), "only hut obstructs the completed field at %s" % cell)
	var controller := Controller.new(world)
	var record := Checkpoint.capture(world, controller, {}, {})
	# Mimic the old save format's empty farm navigation cells.
	record["grid"]["occupied_cells"].erase(hut)
	var restored = make_world()
	var resumed := Controller.new(restored)
	check(Checkpoint.restore(record, restored, resumed), "older farm save restores")
	check(not restored.navigation_grid.is_walkable(hut), "older farm acquires its missing hut obstruction")
	restored.shutdown_derived_state()
	world.shutdown_derived_state()
