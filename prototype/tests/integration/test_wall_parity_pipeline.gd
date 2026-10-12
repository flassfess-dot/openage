extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")
const Orders := preload("res://scripts/order_pipeline.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Coordinates := preload("res://scripts/coordinates.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Adapter := preload("res://tests/fixtures/wall_placement_main_adapter.gd")
var catalog
var failures: Array[String] = []


func _initialize() -> void:
	catalog = Catalog.new()
	catalog.load()
	test_source_shapes_and_damage()
	test_topology_lifecycle()
	test_budget_reuse_and_shift()
	test_obstacles_completed_walls_and_full_queue()
	test_wall_barrier_and_opening()
	test_dense_render_creation_order()
	test_long_wall_checkpoint_and_replay()
	test_checkpoint_normalizes_older_wall_masks()
	for failure in failures: push_error(failure)
	print("Wall parity pipeline: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func check(value: bool,message: String) -> void:
	if not value: failures.append(message)


func make_world():
	var world = World.new(Vector2i(64,64))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for team in [1,2]:
		world.set_team_civilization(team,13)
		world.set_population_cap(team,50)
		world.set_population_housing(team,50)
	world.grant_technology(1,101)
	world.grant_technology(1,11)
	world.set_resource_amount(1,2,10000)
	world.visibility_system.fog.ensure_player(1)
	for y in range(64):
		for x in range(64): world.visibility_system.fog.reveal_explored_cell(1,Vector2i(x,y))
	world.add_building(5000,"town_center",Vector2(59,59),2)
	return world


func make_wall(source_id: int,civ: int,mask: int) -> Dictionary:
	var source: Dictionary = catalog.object_catalog_data["objects"]["%d:%d" % [civ,source_id]]
	return {"id":1,"kind":"wall","team":1,"source_unit_id":source_id,"display_graphic_id":source["graphics"]["idle"],"state":"complete","hp":float(source["health"])*0.2,"max_hp":source["health"],"connection_mask":mask,"connection_revision":3,"components":{"ownership":{"civilization_id":civ}}}


func test_source_shapes_and_damage() -> void:
	for civ in range(1,17):
		for source_id in [72,117,155]:
			for mask in range(16):
				var wall := make_wall(source_id,civ,mask)
				var expected := 1 if mask == 10 else (0 if mask == 5 else 2)
				for projection in [Contract.render(wall),Contract.render_reference(wall)]:
					check(int(projection.get("connection_mask",-1)) == mask,"compact/native render must retain wall mask")
					var info: Dictionary = catalog.building_frame_info(projection,0.0)
					var layers: Array = [info]
					layers.append_array(info.get("composite_parts",[]))
					var shaped := 0
					for part in layers:
						if part.get("texture") == null: continue
						var graphic: Dictionary = catalog.graphics_catalog_data["graphics"][str(part["graphic_id"])]
						if int(graphic.get("angle_count",1)) == 3:
							shaped += 1
							check(int(part.get("source_direction",-1)) == expected,"civ %d wall %d mask %d base/composite/damage shape" % [civ,source_id,mask])
					check(shaped > 0,"wall must resolve an actual shaped source sprite")


func test_topology_lifecycle() -> void:
	var world = make_world()
	var row: Array = []
	for x in range(12,17): row.append(world.add_building(100+x,"wall",Vector2(x,10),1))
	var middle: Dictionary = row[2]
	var before: Dictionary = world.render_entity_projection_cache.project(middle,world.entity_changes)
	check(int(before["connection_mask"]) == 10,"straight X row has two opposite neighbors")
	check(facing(before) == 1,"X row uses the sprite aligned with the isometric lattice")
	world.set_entity_field(middle, "hp", 40.0)
	var existing_plan: Dictionary = world.plan_wall_line(1, [Vector2i(14, 10)])
	check(float(existing_plan["entries"][0]["ghost"]["hp"]) == 40.0, "preview preserves damage of an existing completed section")
	var plan: Dictionary = world.plan_wall_line(1,WallPlacement.cells(Vector2i(12,11),Vector2i(16,11)))
	check(plan["previews"].size() == 10,"parallel preview includes changed shapes of the existing row")
	for entry in plan["previews"]: check(facing(entry["ghost"]) == 2,"parallel preview forms one solid block mass")
	var adapter = Adapter.new()
	adapter.simulation_world = world
	adapter.game_controller = Controller.new(world)
	adapter.resource_catalog = catalog
	adapter.map_size = world.map_size
	adapter.pending_build_kind = "wall"
	adapter.input_adapter.pointer_position = Vector2(16, 11)
	adapter.input_adapter.pointer.begin_primary(Vector2(12, 11))
	adapter.input_adapter.pointer.update_position(Vector2(16, 11))
	adapter.draw_build_placement_preview()
	check(adapter.fixture_preview_outlines.size() == 10, "production preview draws the new row and its existing neighbors")
	var previous: Dictionary = {}
	var shaped_count := 0
	for item in adapter.fixture_preview_items:
		if not previous.is_empty():
			check(not RenderItem.less(item, previous), "production preview uses the normal world depth order")
		previous = item
		var info: Dictionary = item["frame_info"]
		if info.get("texture") == null:
			continue
		var graphic: Dictionary = catalog.graphics_catalog_data["graphics"][str(info["graphic_id"])]
		if int(graphic.get("angle_count", 1)) == 3:
			shaped_count += 1
			check(int(info.get("source_direction", -1)) == 2, "production preview resolves actual dense block sprites")
	check(shaped_count > 0, "production preview resolves composite wall layers")
	adapter.free()
	var foundation = world.place_foundation(1,"wall",Vector2(14,11))
	check(facing(world.render_entity_projection_cache.project(middle,world.entity_changes)) == 2,"retained projection refreshes after a new neighbor")
	check(world.cancel_foundation(int(foundation["id"])),"neighbor foundation cancels")
	check(facing(world.render_entity_projection_cache.project(middle,world.entity_changes)) == 1,"cancel restores a straight panel")
	var adjacent = world.add_building(300,"wall",Vector2(14,11),1)
	check(world.transfer_entity_ownership(adjacent,2),"neighbor can change owner")
	check(facing(middle) == 1,"enemy wall does not connect")
	check(world.transfer_entity_ownership(adjacent,1),"neighbor can return to owner")
	check(facing(middle) == 2,"returned neighbor restores the block")
	world.set_entity_field(adjacent,"hp",0.0)
	world.begin_building_destruction(adjacent)
	check(facing(middle) == 1,"destroyed neighbor leaves topology immediately")
	world.apply_unit_upgrade_to_entity(middle,117)
	world.refresh_building_connectivity()
	check(int(middle["connection_mask"]) == 0,"different wall levels retain independent connections")
	world.grant_technology(1,102)
	world.grant_technology(1,13)
	check(int(middle["connection_mask"]) == 10,"upgrade batch rebuilds connectivity across newly matching levels")
	world.shutdown_derived_state()


func facing(wall: Dictionary) -> int:
	var info: Dictionary = catalog.building_frame_info(wall)
	if info.get("texture") != null: return int(info.get("source_direction",-1))
	for part in info.get("composite_parts",[]):
		var spec: Dictionary = catalog.graphics_catalog_data["graphics"][str(part["graphic_id"])]
		if int(spec.get("angle_count",1)) == 3: return int(part.get("source_direction",-1))
	return -1


func commit(world,controller,worker: Dictionary,finish: Vector2,shift: bool=false,start: Vector2=Vector2(12,10)):
	var adapter = Adapter.new()
	adapter.simulation_world = world
	adapter.game_controller = controller
	adapter.map_size = world.map_size
	adapter.fixture_workers = [worker]
	adapter.pending_build_kind = "wall"
	adapter.commit_build_placement(finish,shift,start)
	check(adapter.pending_build_kind == ("wall" if shift else ""),"Shift keeps placement mode, plain click exits")
	adapter.free()
	check(controller.command_queue.size() == 1,"one gesture emits one authoritative wall plan")
	var command = controller.command_queue[0]
	controller.tick_index += 1
	controller.process_commands()
	return command


func test_budget_reuse_and_shift() -> void:
	var world = make_world()
	var worker: Dictionary = world.add_unit(1,"villager",Vector2(8,8),false)
	var controller = Controller.new(world)
	world.set_resource_amount(1,2,10)
	var cells := WallPlacement.cells(Vector2i(12,10),Vector2i(16,10))
	var plan: Dictionary = world.plan_wall_line(1,cells)
	check(plan["entries"].map(func(e): return e["valid"]) == [true,true,false,false,false],"preview spends a cumulative stone budget from the anchor")
	var command = commit(world,controller,worker,Vector2(16,10))
	check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"partial legal wall is accepted")
	var foundations: Array = world.get_buildings().filter(func(b): return b["kind"] == "wall")
	check(foundations.map(func(b): return b["pos"]) == [Vector2(12,10),Vector2(13,10)],"execution matches the affordable preview prefix")
	check(world.get_resource_amount(1,2) == 0,"cost is reserved only for created sections")
	world.set_resource_amount(1,2,5)
	commit(world,controller,worker,Vector2(14,10))
	check(world.get_resource_amount(1,2) == 0,"reusing unfinished wall foundations is free")
	check(world.get_buildings().filter(func(b): return b["kind"] == "wall").size() == 3,"repeated line creates only its missing cell")
	var move = Commands.MoveCommand.new(controller.tick_index,[1],Vector2(6,8))
	controller.enqueue_command(move,true,1)
	controller.process_commands()
	var deferred = Commands.MoveCommand.new(controller.tick_index,[1],Vector2(7,8))
	deferred.params["queue_order"] = true
	controller.enqueue_command(deferred,true,1)
	controller.process_commands()
	world.set_resource_amount(1,2,100)
	commit(world,controller,worker,Vector2(16,12),true,Vector2(12,12))
	check(String(worker["task"]) == "move" and Vector2(worker["target"]) == Vector2(6,8),"Shift wall preserves the current movement")
	check(Orders.queued(worker).size() == 2 and String(Orders.queued(worker)[0]["type"]) == "move","Shift appends the entire wall after prior deferred orders")
	world.shutdown_derived_state()


func test_obstacles_completed_walls_and_full_queue() -> void:
	var world = make_world()
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(8, 8), false)
	var controller = Controller.new(world)
	world.add_building(200, "wall", Vector2(12, 10), 1)
	world.add_building(201, "wall", Vector2(16, 10), 1)
	world.add_resource("tree", Vector2(14.5, 10.5), 75)
	world.set_resource_amount(1, 2, 10)
	var plan: Dictionary = world.plan_wall_line(1, WallPlacement.cells(Vector2i(12, 10), Vector2i(16, 10)))
	check(plan["entries"].map(func(e): return e["status"]) == ["existing", "new", "blocked", "new", "existing"], "plan reuses completed own walls and marks a resource obstacle")
	commit(world, controller, worker, Vector2(16, 10))
	var foundations: Array = world.get_buildings().filter(func(b): return b["kind"] == "wall" and b["state"] == "foundation")
	check(foundations.map(func(b): return b["pos"]) == [Vector2(13, 10), Vector2(15, 10)], "obstacle plan creates exactly its legal missing sections")
	check(world.get_resource_amount(1, 2) == 0, "completed sections and obstacles consume no stone")
	var move = Commands.MoveCommand.new(controller.tick_index, [1], Vector2(6, 8))
	controller.enqueue_command(move, true, 1)
	controller.process_commands()
	commit(world, controller, worker, Vector2(12, 10), false)
	check(String(worker["task"]) == "move" and Vector2(worker["target"]) == Vector2(6, 8), "a gesture on a completed wall preserves the current order")
	for index in range(Orders.MAX_QUEUED_ORDERS):
		var deferred = Commands.MoveCommand.new(controller.tick_index, [1], Vector2(7, 8))
		deferred.params["queue_order"] = true
		controller.enqueue_command(deferred, true, 1)
		controller.process_commands()
	world.set_resource_amount(1, 2, 100)
	var count_before: int = world.get_buildings().size()
	var full_queue: Array = Orders.queued(worker).duplicate(true)
	var rejected = commit(world, controller, worker, Vector2(24, 20), true, Vector2(20, 20))
	check(controller.get_command_result(rejected.sequence_id).get("reason") == "order_queue_full", "a full Shift queue rejects the entire new gesture")
	check(world.get_resource_amount(1, 2) == 100 and world.get_buildings().size() == count_before, "queue rejection reserves neither stone nor foundations")
	check(Orders.queued(worker) == full_queue and String(worker["task"]) == "move", "queue rejection preserves all prior orders")
	world.shutdown_derived_state()


func test_wall_barrier_and_opening() -> void:
	var world = make_world()
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(8, 8), false)
	var controller = Controller.new(world)
	var edge_plan: Dictionary = world.plan_wall_line(1, WallPlacement.cells(Vector2i(0, 20), Vector2i(4, 20)))
	check(not bool(edge_plan["entries"][1]["valid"]), "preview accounts for footprints moved by map-edge clamping")
	commit(world, controller, worker, Vector2(4, 20), false, Vector2(0, 20))
	check(world.get_resource_amount(1, 2) == 10000 - 5 * edge_plan["entries"].filter(func(e): return e["valid"]).size(), "edge plan spends exactly the previewed budget")
	world.navigation_grid.set_terrain(Vector2i(0, 30), "water")
	commit(world, controller, worker, Vector2(63, 30), false, Vector2(1, 30))
	check(not world.pathfinder.cells_connected(Vector2i(25, 29), Vector2i(25, 31)), "an uninterrupted wall blocks a route across the map")
	var center: Dictionary = {}
	for wall in world.get_buildings():
		if wall["kind"] == "wall" and Vector2(wall["pos"]) == Vector2(25, 30):
			center = wall
	check(not center.is_empty(), "barrier includes its middle section")
	if not center.is_empty():
		world.cancel_foundation(int(center["id"]))
		check(world.pathfinder.cells_connected(Vector2i(25, 29), Vector2i(25, 31)), "cancelling a section opens a route through the wall")
	world.shutdown_derived_state()


func test_dense_render_creation_order() -> void:
	for source_id in [72, 117, 155]:
		for along_x in [true, false]:
			for damaged in [false, true]:
				var forward := render_dense_wall(source_id, along_x, damaged, false)
				var reverse := render_dense_wall(source_id, along_x, damaged, true)
				check(forward.get_data() == reverse.get_data(), "dense wall pixels must be independent of creation order: level %d X=%s damaged=%s" % [source_id, along_x, damaged])


func render_dense_wall(source_id: int, along_x: bool, damaged: bool, reverse_order: bool) -> Image:
	var world = make_world()
	var cells: Array[Vector2i] = []
	for row in range(2):
		for offset in range(5):
			cells.append(Vector2i(12 + offset, 10 + row) if along_x else Vector2i(12 + row, 10 + offset))
	if reverse_order:
		cells.reverse()
	for index in range(cells.size()):
		var wall: Dictionary = world.add_building(100 + index, "wall", Vector2(cells[index]), 1)
		world.apply_unit_upgrade_to_entity(wall, source_id)
		if damaged:
			world.set_entity_field(wall, "hp", float(wall["max_hp"]) * 0.2)
	world.refresh_building_connectivity()
	var projections: Array = []
	for wall in world.get_buildings():
		if wall["kind"] != "wall":
			continue
		check(facing(wall) == 2, "every dense section uses a block")
		projections.append(Contract.render(wall))
	var image := Image.create(480, 320, false, Image.FORMAT_RGBA8)
	image.fill(Color("263c32"))
	var project := func(pos): return Vector2(240, 130) + Coordinates.iso_raw(Vector2(pos) - Vector2(12, 10))
	var provider := func(_kind, data):
		# Freeze the individual flag phase to compare geometry and occlusion.
		var presentation_data: Dictionary = data.duplicate()
		presentation_data["id"] = 1
		return catalog.building_frame_info(presentation_data, 0.0)
	var renderer = RenderWorld.new()
	for item in renderer.create_world_drawables({"buildings": projections}, project, 1.0, provider):
		var part: Dictionary = item["frame_info"]
		if part.get("texture") == null:
			continue
		var sprite: Image = part["texture"].get_image()
		if bool(part.get("mirrored", false)):
			sprite = sprite.duplicate()
			sprite.flip_x()
		var anchor: Vector2 = item["screen_position"] + part.get("screen_offset", Vector2.ZERO) - part.get("hotspot", Vector2.ZERO)
		image.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), Vector2i(anchor))
	world.shutdown_derived_state()
	return image


func test_long_wall_checkpoint_and_replay() -> void:
	var world = make_world()
	var worker: Dictionary = world.add_unit(1,"villager",Vector2(8,8),false)
	var controller = Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var command = commit(world,controller,worker,Vector2(41,10))
	var walls: Array = world.get_buildings().filter(func(b): return b["kind"] == "wall")
	check(walls.size() == 30,"long gesture is not cut off by the 16-order queue")
	check(Orders.queued(worker).size() == 1,"thirty sections use one continuation entry")
	var codec := Replay.new()
	var record := {"tick":command.tick,"issuer_id":1,"sequence_id":command.sequence_id,"type":"build","unit_ids":[1],"params":codec.encode_variant(command.params)}
	var replayed = codec.command_from_record(record)
	check(replayed != null and replayed.params.get("wall_cells") == command.params["wall_cells"],"replay codec preserves all cells of the gesture")
	var replay_world = make_world()
	replay_world.add_unit(1,"villager",Vector2(8,8),false)
	var replay_controller = Controller.new(replay_world)
	replay_controller.set_speed_multiplier(1.0)
	replay_controller.enqueue_command(replayed,true,1)
	replay_controller.tick_index = controller.tick_index
	replay_controller.process_commands()
	check(codec.world_state_hash(world,controller.tick_index,controller) == codec.world_state_hash(replay_world,replay_controller.tick_index,replay_controller),"replaying the wall gesture creates the identical authoritative state")
	replay_world.shutdown_derived_state()
	for wall in walls: world.set_entity_field(wall,"construction_required",0.05)
	world.cancel_foundation(int(walls[4]["id"]))
	# Checkpoints belong to a completed fixed tick, including domain events and runtime indices.
	controller.advance_frame(0.05,1,2)
	var data := Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world,controller,{}, {"size":world.map_size})))
	var resumed_world = make_world()
	var resumed_controller = Controller.new(resumed_world)
	check(Checkpoint.restore(data,resumed_world,resumed_controller),"checkpoint restores pending wall continuation")
	# Speed is restored by the archive/controller layer, independently of Checkpoint.
	resumed_controller.set_speed_multiplier(controller.get_speed_multiplier())
	check(Orders.queued(resumed_world.find_unit(1)) == Orders.queued(worker),"checkpoint preserves every remaining foundation ID")
	for tick in range(1200):
		controller.advance_frame(0.05,1,2)
		resumed_controller.advance_frame(0.05,1,2)
		if tick % 50 == 0:
			var difference := first_difference(codec.world_snapshot(world,controller.tick_index,controller),codec.world_snapshot(resumed_world,resumed_controller.tick_index,resumed_controller),"root")
			check(difference.is_empty(),"saved wall continues deterministically at tick %d: %s" % [tick,difference])
		if world.get_buildings().filter(func(b): return b["kind"] == "wall" and b["state"] == "foundation").is_empty(): break
	check(world.get_buildings().filter(func(b): return b["kind"] == "wall" and b["state"] == "complete").size() == 29,"worker actually completes the long line and skips its cancelled target")
	check(resumed_world.get_buildings().filter(func(b): return b["kind"] == "wall" and b["state"] == "complete").size() == 29,"restored worker completes the same wall")
	world.shutdown_derived_state()
	resumed_world.shutdown_derived_state()


func test_checkpoint_normalizes_older_wall_masks() -> void:
	var world = make_world()
	var controller = Controller.new(world)
	var walls: Array = []
	for x in range(12, 15):
		walls.append(world.add_building(100 + x, "wall", Vector2(x, 10), 1))
	world.apply_unit_upgrade_to_entity(walls[1], 117)
	# Older saves connected all owned wall levels as a single group.
	for index in range(3):
		world.set_entity_field(walls[index], "connection_mask", [2, 10, 8][index])
	var checkpoint := Checkpoint.capture(world, controller, {}, {"size": world.map_size})
	var restored_world = make_world()
	var restored_controller = Controller.new(restored_world)
	check(Checkpoint.restore(checkpoint, restored_world, restored_controller), "checkpoint with older derived wall masks is readable")
	for wall in restored_world.get_buildings():
		if wall["kind"] == "wall":
			check(int(wall["connection_mask"]) == 0 and facing(wall) == 2, "loading recomputes masks for independent wall levels")
	world.shutdown_derived_state()
	restored_world.shutdown_derived_state()


func first_difference(a: Variant,b: Variant,path: String) -> String:
	if typeof(a) != typeof(b): return "%s types %s / %s" % [path,typeof(a),typeof(b)]
	if a is Dictionary:
		for key in a:
			if not b.has(key): return path+" missing "+str(key)
			var diff := first_difference(a[key],b[key],path+"."+str(key))
			if not diff.is_empty(): return diff
		for key in b:
			if not a.has(key): return path+" extra "+str(key)
	elif a is Array:
		if a.size() != b.size(): return path+" lengths "+str(a.size())+" / "+str(b.size())
		for i in range(a.size()):
			var diff := first_difference(a[i],b[i],path+"["+str(i)+"]")
			if not diff.is_empty(): return diff
	elif a != b: return "%s %s / %s" % [path,a,b]
	return ""
