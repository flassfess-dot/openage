extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Hud := preload("res://scripts/hud_view_model.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	test_build_and_upgrade(catalog)
	test_passage(catalog)
	test_placement_orientation(catalog)
	test_economy_and_large_units(catalog)
	test_opening_checkpoint(catalog)
	test_presentations(catalog)
	if failures.is_empty():
		print("Gate construction, upgrade, passage, ownership, replay and presentation tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func make_world(catalog):
	var world = World.new(Vector2i(24,24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.navigation_grid.configure_elevation(func(_cell): return 0)
	world.set_resource_amount(1,1,2000)
	world.set_resource_amount(1,2,2000)
	return world

func research(world, team: int, technologies: Array) -> void:
	for id in technologies:
		world.apply_technology_commands(team,world.technology_system.complete_research(team,int(id)))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func test_build_and_upgrade(catalog) -> void:
	var world = make_world(catalog)
	check(not world.get_build_options(1).any(func(option): return option["kind"] == "gate"),"gates unavailable before small-wall research")
	research(world,1,[101,11])
	check(world.get_build_options(1).any(func(option): return option["kind"] == "gate"),"wall research unlocks gate menu")
	var worker: Dictionary = world.add_unit(1,"villager",Vector2(7,8),false)
	var controller = Controller.new(world)
	var build = Commands.BuildCommand.new(0,[1],"gate",Vector2(9,9))
	build.params["gate_axis"] = 1
	controller.enqueue_command(build,true,1)
	controller.process_commands()
	check(bool(controller.get_command_result(build.sequence_id).get("accepted",false)),"public build command accepted: "+world.last_build_failure)
	var gates: Array = world.get_buildings().filter(func(building): return building["kind"] == "gate")
	check(gates.size() == 1,"one gate entity constructed")
	if gates.is_empty():
		return
	var gate: Dictionary = gates[0]
	check(int(gate["gate_axis"]) == 1 and gate["occupied_cells"].size() == 4,"rotated gate reserves four cells")
	check(int(world.get_resource_amount(1,1)) == 1960 and int(world.get_resource_amount(1,2)) == 1980,"one gate cost reserved")
	gate["construction_required"] = 0.2
	if worker.get("building_approach_slot") is Vector2:
		world.set_entity_field(worker,"pos",worker["building_approach_slot"])
	for step in range(20):
		world.update_units(0.05,1,2)
	check(gate["state"] == "complete","worker actually completes gate")
	var command = Commands.GateModeCommand.new(controller.tick_index,[int(gate["id"])],"open")
	controller.enqueue_command(command,true,1)
	controller.process_commands()
	check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)) and gate["gate_mode"] == "open","public mode command accepted")
	var foreign = Commands.GateModeCommand.new(controller.tick_index,[int(gate["id"])],"locked")
	controller.enqueue_command(foreign,true,2)
	controller.process_commands()
	check(not bool(controller.get_command_result(foreign.sequence_id).get("accepted",true)) and gate["gate_mode"] == "open","foreign gate control rejected")
	world.set_entity_field(gate,"hp",float(gate["max_hp"])*0.5)
	research(world,1,[102,13])
	check(int(gate["source_unit_id"]) == 10117 and is_equal_approx(float(gate["hp"])/float(gate["max_hp"]),0.5),"wall upgrade preserves gate health ratio")
	check(gate["gate_mode"] == "open" and int(gate["gate_axis"]) == 1,"upgrade retains orientation and mode")
	var hud = Hud.new()
	hud.configure(catalog.runtime_catalog_data,catalog.localization,catalog.object_catalog_data)
	var snapshot: Dictionary = controller.presentation_snapshot(1) if controller.has_method("presentation_snapshot") else {"buildings":[gate],"units":[],"player_state":{"team":1},"observer_team":1}
	var model: Dictionary = hud.build(snapshot,[int(gate["id"])],"LINE")
	check(model["commands"].filter(func(action): return String(action.get("id","")).begins_with("gate_")).size() == 3,"owned gate exposes all three HUD modes")
	var replay = Replay.new()
	replay.record_command(build)
	replay.record_command(command)
	var decoded = replay.command_from_record(replay.command_records[0])
	check(int(decoded.params.get("gate_axis",-1)) == 1,"replay retains gate rotation")
	decoded = replay.command_from_record(replay.command_records[1])
	check(decoded.command_type() == "gate_mode" and decoded.params["mode"] == "open","replay retains gate command")

func test_passage(catalog) -> void:
	var world = make_world(catalog)
	research(world,1,[101,11,102,13])
	var gate: Dictionary = world.add_building(100,"gate",Vector2(12,12))
	for x in range(24):
		if x >= 10 and x <= 13:
			continue
		world.add_building(200+x,"wall",Vector2(x,12))
	var unit: Dictionary = world.add_unit(1,"clubman",Vector2(12,7),false)
	world.add_unit(2,"clubman",Vector2(3,3),false)
	world.update_fog_of_war()
	check(not world.navigation_grid.is_walkable(Vector2i(12,12)),"closed gate physically blocks passage")
	var planner = world.movement_system.knowledge.planner(world,1)
	check(planner.grid.is_walkable(Vector2i(12,12)),"friendly planning can route through an automatic gate")
	var controller = Controller.new(world)
	var move = Commands.MoveCommand.new(0,[1],Vector2(12,19))
	controller.enqueue_command(move,true,1)
	controller.process_commands()
	for step in range(400):
		controller.advance_frame(0.05,1,2)
		if Vector2(unit["pos"]).y > 17.0:
			break
	check(Vector2(unit["pos"]).y > 17.0,"friendly unit physically crossed gate: "+str(unit["pos"])+" / "+str(unit.get("diagnostic_reason","")))
	check(not world.navigation_grid.is_walkable(Vector2i(10,12)) and not world.navigation_grid.is_walkable(Vector2i(13,12)),"open gate keeps both piers blocked")
	world.gate_system.set_mode([100],1,"open")
	world.gate_system.advance(1.0)
	world.set_entity_field(unit,"pos",Vector2(12,12.5))
	world.rebuild_spatial_index()
	world.gate_system.set_mode([100],1,"locked")
	world.gate_system.advance(1.0)
	check(float(gate["gate_open_fraction"]) >= 0.95,"closure waits for an occupied corridor")
	world.set_entity_field(unit,"pos",Vector2(12,18))
	world.rebuild_spatial_index()
	world.gate_system.advance(1.0)
	check(float(gate["gate_open_fraction"]) == 0 and not world.navigation_grid.is_walkable(Vector2i(12,12)),"locked gate closes after corridor clears")
	planner = world.movement_system.knowledge.planner(world,1)
	check(not planner.grid.is_walkable(Vector2i(12,12)),"locked gate also blocks friendly planning")
	world.navigation_grid.rebuild(world.resource_nodes,world.buildings)
	check(not world.navigation_grid.is_walkable(Vector2i(12,12)),"full navigation rebuild respects closed gate")
	world.gate_system.set_mode([100],1,"open")
	world.gate_system.advance(1.0)
	world.navigation_grid.rebuild(world.resource_nodes,world.buildings)
	check(world.navigation_grid.is_walkable(Vector2i(12,12)) and not world.navigation_grid.is_walkable(Vector2i(10,12)),"full rebuild preserves open passage and solid piers")
	var checkpoint: Dictionary = Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world,controller,{}, {"size": world.map_size})))
	var restored = make_world(catalog)
	var restored_controller = Controller.new(restored)
	check(Checkpoint.restore(checkpoint,restored,restored_controller),"gate checkpoint restores")
	var restored_gate: Variant = restored.find_building(100)
	check(restored_gate != null and restored_gate["gate_mode"] == "open" and float(restored_gate["gate_open_fraction"]) == 1.0,"checkpoint retains gate mode and pose")
	check(restored.gate_system.gate_ids.has(100),"checkpoint restores active gate roster")
	if restored_gate != null:
		restored.gate_system.set_mode([100],1,"locked")
		restored.gate_system.advance(1.0)
		check(float(restored_gate["gate_open_fraction"]) == 0.0,"restored gate continues to operate")
	world.gate_system.set_mode([100],1,"auto")
	world.gate_system.advance(2.0)
	var enemy: Dictionary = world.get_units().filter(func(actor): return int(actor["team"]) == 2)[0]
	world.set_entity_field(enemy,"pos",Vector2(12,10))
	world.set_entity_field(enemy,"path",[Vector2(12,19)])
	world.set_entity_field(enemy,"path_index",0)
	world.set_entity_field(enemy,"task","move")
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	var enemy_planner = world.movement_system.knowledge.planner(world,2)
	check(not enemy_planner.grid.is_walkable(Vector2i(12,12)),"enemy cannot plan through a known closed automatic gate")
	world.gate_system.advance(1.0)
	check(float(gate["gate_open_fraction"]) == 0.0,"enemy approaching does not open gate")
	world.set_alliance(1,2,true)
	var ally_planner = world.movement_system.knowledge.planner(world,2)
	check(ally_planner.grid.is_walkable(Vector2i(12,12)),"new ally can plan through same gate")
	world.gate_system.advance(1.0)
	check(float(gate["gate_open_fraction"]) == 1.0,"allied passage request opens gate")
	var deletion = Commands.DeleteEntityCommand.new(controller.tick_index,[100])
	controller.enqueue_command(deletion,true,1)
	controller.process_commands()
	check(float(gate["hp"]) <= 0.0 and world.navigation_grid.is_walkable(Vector2i(10,12)),"destruction releases pier and passage obstruction")

func test_placement_orientation(catalog) -> void:
	for axis in [0,1]:
		var world = make_world(catalog)
		research(world,1,[101,11])
		world.add_unit(1,"villager",Vector2(12,8),false)
		world.add_resource("tree",Vector2(10.5,12.5) if axis == 0 else Vector2(12.5,10.5),10)
		world.update_fog_of_war()
		check(not world.can_place_foundation(1,"gate",Vector2(12,12),{"gate_axis":axis}),"placement checks obstruction on actual gate axis")
		check(world.can_place_foundation(1,"gate",Vector2(12,12),{"gate_axis":1-axis}),"rotation releases cells outside new footprint")
		check(not world.can_place_foundation(1,"gate",Vector2(12,12),{"gate_axis":3}),"invalid orientation rejected")

func barrier(world, axis: int = 0) -> Dictionary:
	research(world,1,[101,11,102,13])
	var gate: Dictionary = world.add_building(100,"gate",Vector2(12,12),1,true,{"gate_axis":axis})
	for cell in range(24):
		if cell >= 10 and cell <= 13:
			continue
		world.add_building(200+cell,"wall",Vector2(cell,12) if axis == 0 else Vector2(12,cell))
	world.add_unit(2,"clubman",Vector2(2,2),false)
	return gate

func test_economy_and_large_units(catalog) -> void:
	for axis in [0,1]:
		for kind in ["cavalry","catapult"]:
			var world = make_world(catalog)
			barrier(world,axis)
			var unit: Dictionary = world.add_unit(1,kind,Vector2(12,7) if axis == 0 else Vector2(7,12),false)
			var controller = Controller.new(world)
			var destination := Vector2(12,19) if axis == 0 else Vector2(19,12)
			controller.enqueue_command(Commands.MoveCommand.new(0,[int(unit["id"])],destination),true,1)
			controller.process_commands()
			for step in range(800):
				controller.advance_frame(0.05,1,2)
				if Vector2(unit["pos"]).distance_to(destination) < 1:
					break
			check(Vector2(unit["pos"]).distance_to(destination) < 1,"%s crossed axis %d gate: %s" % [kind,axis,unit["pos"]])
	var world = make_world(catalog)
	barrier(world)
	world.add_building(500,"town_center",Vector2(12,5),1)
	var worker: Dictionary = world.add_unit(1,"villager",Vector2(12,8),false)
	var berries: Dictionary = world.add_resource("berries",Vector2(12,17),8)
	var before := int(world.get_resource_amount(1,0))
	var controller = Controller.new(world)
	controller.enqueue_command(Commands.GatherCommand.new(0,[int(worker["id"])],int(berries["id"])),true,1)
	controller.process_commands()
	for step in range(1800):
		controller.advance_frame(0.05,1,2)
		if int(world.get_resource_amount(1,0)) == before+8:
			break
	check(int(world.get_resource_amount(1,0)) == before+8,"worker crosses gate to gather and returns to deposit: "+str(worker.get("diagnostic_reason","")))

func test_opening_checkpoint(catalog) -> void:
	var world = make_world(catalog)
	var gate: Dictionary = barrier(world)
	var unit: Dictionary = world.add_unit(1,"clubman",Vector2(12,7),false)
	var controller = Controller.new(world)
	controller.enqueue_command(Commands.GateModeCommand.new(0,[100],"open"),true,1)
	controller.enqueue_command(Commands.MoveCommand.new(0,[int(unit["id"])],Vector2(12,19)),true,1)
	for step in range(4):
		controller.advance_frame(0.05,1,2)
	check(float(gate["gate_open_fraction"]) > 0 and float(gate["gate_open_fraction"]) < 0.95,"checkpoint captured during opening")
	var checkpoint: Dictionary = Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world,controller,{},{"size":world.map_size})))
	var restored = make_world(catalog)
	var restored_controller = Controller.new(restored)
	check(Checkpoint.restore(checkpoint,restored,restored_controller),"opening checkpoint restores")
	var verifier = Replay.new()
	check(verifier.world_state_hash(world,controller.tick_index,controller) == verifier.world_state_hash(restored,restored_controller.tick_index,restored_controller),"opening checkpoint restores exact state")
	for step in range(60):
		controller.advance_frame(0.05,1,2)
		restored_controller.advance_frame(0.05,1,2)
	check(verifier.world_state_hash(world,controller.tick_index,controller) == verifier.world_state_hash(restored,restored_controller.tick_index,restored_controller),"opening and crossing continue identically after checkpoint")
	check(Vector2(world.find_unit(int(unit["id"]))["pos"]).y > 12,"route issued together with manual opening crosses gate")

func test_presentations(catalog) -> void:
	for civilization in [1,2,3,10,13]:
		var world = make_world(catalog)
		world.set_team_civilization(1,civilization)
		research(world,1,[101,11])
		var gate: Dictionary = world.add_building(100,"gate",Vector2(12,12))
		for level in [72,117,155]:
			if level == 117:
				research(world,1,[102,13])
			elif level == 155:
				research(world,1,[103,14])
			for axis in [0,1]:
				gate["gate_axis"] = axis
				for pose in [0.0,0.5,1.0]:
					gate["gate_open_fraction"] = pose
					var info: Dictionary = catalog.building_frame_info(gate,0)
					check(info.get("composite_parts",[]).size() >= 12,"all cultures, wall tiers and orientations have complete pieces")
