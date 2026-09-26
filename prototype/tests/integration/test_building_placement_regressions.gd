extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const Footprint := preload("res://scripts/footprint.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	check_fish_animation(catalog)
	check_town_center_age_art(catalog)
	check_farm_footprint_and_queued_build(catalog)
	check_storage_pit_on_forest_floor(catalog)
	check_repeated_houses(catalog)
	check_wall_line_pipeline(catalog)
	if failures.is_empty():
		print("Fish, age-art, forest placement and repeated placement regression tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check_fish_animation(catalog) -> void:
	for kind in ["deep_fish", "shore_fish"]:
		var sample := {"id": 12, "kind": kind, "amount": 100}
		var first: Dictionary = catalog.resource_frame_info(sample, 0.0)
		var later: Dictionary = catalog.resource_frame_info(sample, 0.4)
		check(first.get("texture") != null, "%s has an imported sprite" % kind)
		check(first.get("frame_index", -1) != later.get("frame_index", -1), "%s advances frames" % kind)


func check_town_center_age_art(catalog) -> void:
	var world = configured_world(catalog)
	var center: Dictionary = world.add_building(700, "town_center", Vector2(7, 7), 1)
	var stone: Dictionary = catalog.building_frame_info(center)
	world.grant_technology(1, 101)
	var tool: Dictionary = catalog.building_frame_info(center)
	check(int(stone.get("frame_index", -1)) != int(tool.get("frame_index", -1)), "Roman Town Center changes sprite at Tool Age")
	world.grant_technology(1, 102)
	var bronze: Dictionary = catalog.building_frame_info(center)
	check(int(bronze.get("graphic_id", -1)) != int(tool.get("graphic_id", -1)), "Roman Town Center receives Bronze Age source art")


func check_farm_footprint_and_queued_build(catalog) -> void:
	var world = configured_world(catalog)
	for resource_id in range(4):
		world.set_resource_amount(1, resource_id, 10000)
	var footprint: Dictionary = Footprint.building(world.unit_stats("farm"), Vector2(18, 18))
	check(footprint.get("occupied_cells", []).size() == 9, "Farm blocks source 3x3 footprint, not its oversized selection outline")
	world.add_resource("tree", Vector2(22.5, 18.5), 100)
	check(world.map_supports_foundation("farm", Vector2(20, 18)), "Farm fits in the three clear columns immediately beside a tree")
	world.add_building(701, "granary", Vector2(5, 5), 1)
	world.grant_technology(1, 101)
	world.add_building(702, "market", Vector2(5, 12), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(18, 22), false)
	world.add_unit(1, "clubman", Vector2(25, 27), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(36, 36), false)
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	var first = Commands.BuildCommand.new(0, [int(worker["id"])], "farm", Vector2(17, 19))
	var second = Commands.BuildCommand.new(0, [int(worker["id"])], "farm", Vector2(23, 24))
	second.params["queue_order"] = true
	controller.enqueue_command(first, true, 1)
	controller.enqueue_command(second, true, 1)
	controller.process_commands()
	for unused in range(1600):
		controller.advance_frame(0.05, 1, 2)
		if world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "farm").size() >= 2:
			break
	check(world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "farm").size() == 2, "Queued Farm starts after first Farm completes: worker=%s pos=%s dest=%s slot=%s path=%s path_index=%s status=%s reason=%s farms=%s first=%s second=%s" % [str(worker.get("task", "")), str(worker.get("pos", "")), str(worker.get("destination", "")), str(worker.get("building_approach_slot", "")), str(worker.get("path", [])), str(worker.get("path_index", -1)), str(worker.get("path_status", "")), str(worker.get("diagnostic_reason", "")), str(world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "farm").map(func(building): return [building.get("state", ""), building.get("construction_progress", 0.0)])), str(controller.get_command_result(first.sequence_id)), str(controller.get_command_result(second.sequence_id))])
	check(int(worker.get("target_building_id", -1)) != 700, "Worker does not remain on completed Farm")


func check_storage_pit_on_forest_floor(catalog) -> void:
	var world = configured_world(catalog)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain_ids: Array[int] = []
	terrain_ids.resize(world.map_size.x * world.map_size.y)
	terrain_ids.fill(0)
	for y in range(17, 24):
		for x in range(14, 22):
			terrain_ids[y * world.map_size.x + x] = 10
	world.configure_map_data({"terrain_ids": terrain_ids})
	world.set_resource_amount(1, 1, 10000)
	world.get_fog_of_war().reveal_explored_cell(1, Vector2i(17, 20))
	world.add_scenario_resource("tree", Vector2(20.5, 20.5), 75)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(17, 24), false)
	check(world.map_supports_foundation("storage_pit", Vector2(17, 20)), "Storage Pit fits on clear green forest floor beside trees")
	check(world.can_place_foundation(1, "storage_pit", Vector2(17, 20)), "Storage Pit command accepts clear green forest floor")
	check(world.worker_can_reach_foundation(worker, "storage_pit", Vector2(17, 20)), "Villager can reach a Storage Pit on clear forest floor")
	check(not world.map_supports_foundation("storage_pit", Vector2(20, 20)), "A tree still blocks Storage Pit placement on its occupied cell")


func check_repeated_houses(catalog) -> void:
	var world = configured_world(catalog)
	for resource_id in range(4):
		world.set_resource_amount(1, resource_id, 10000)
	world.add_building(801, "town_center", Vector2(6, 6), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(11, 11), false)
	world.add_unit(1, "clubman", Vector2(19, 15), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(36, 36), false)
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	for index in range(3):
		var command = Commands.BuildCommand.new(0, [int(worker["id"])], "house", Vector2(11 + index * 3, 13))
		if index > 0:
			command.params["queue_order"] = true
		controller.enqueue_command(command, true, 1)
	controller.process_commands()
	for unused in range(2400):
		controller.advance_frame(0.05, 1, 2)
		if world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "house" and String(building.get("state", "")) == "complete").size() == 3:
			break
	check(world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "house" and String(building.get("state", "")) == "complete").size() == 3, "Repeated house queue completes its last foundation: worker=%s houses=%s" % [str(worker.get("task", "")), str(world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "house").map(func(building): return [building.get("state", ""), building.get("construction_progress", 0.0)]))])


func check_wall_line_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	for resource_id in range(4):
		world.set_resource_amount(1, resource_id, 10000)
	world.grant_technology(1, 11)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(12, 12), false)
	world.add_unit(1, "clubman", Vector2(18, 18), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(36, 36), false)
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	var cells := WallPlacement.cells(Vector2i(12, 15), Vector2i(16, 15))
	var placement_commands: Array = []
	for index in range(cells.size() - 1, -1, -1):
		var placement = Commands.BuildCommand.new(0, [int(worker["id"])], "wall", Vector2(cells[index]))
		placement_commands.append(placement)
		controller.enqueue_command(placement, true, 1)
	for index in range(1, cells.size()):
		var command = Commands.BuildCommand.new(0, [int(worker["id"])], "wall", Vector2(cells[index]))
		command.params["queue_order"] = true
		controller.enqueue_command(command, true, 1)
	controller.process_commands()
	var walls: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "wall")
	check(walls.size() == cells.size(), "Dragging a wall places all segment foundations immediately: %s" % str(placement_commands.map(func(command): return controller.get_command_result(command.sequence_id))))
	for unused in range(1800):
		controller.advance_frame(0.05, 1, 2)
		if walls.all(func(building): return String(building.get("state", "")) == "complete"):
			break
	check(walls.all(func(building): return String(building.get("state", "")) == "complete"), "Wall drag queue constructs every segment: states=%s worker=%s" % [str(walls.map(func(building): return [building.get("state", ""), building.get("construction_progress", 0.0)])), str(worker.get("task", ""))])


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(40, 40))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	return world


func check(value: bool, context: String) -> void:
	if not value:
		failures.append(context)
