extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Rapids := preload("res://scripts/random_map_river_rapids.gd")
var failures: Array[String] = []
var catalog
var controller

func _initialize() -> void:
	catalog=Catalog.new();catalog.load()
	# The same channel must admit hulls that fit and reject larger hulls.
	for narrow in [false,true]:
		var size:=Vector2i(48,48)
		var terrain:Array[int]=[];terrain.resize(48*48)
		var levels:Array[int]=[];levels.resize(49*49)
		for y in range(4,44):
			for x in range(18,30):
				if narrow and y>=18 and y<28 and x!=24:continue
				terrain[y*48+x]=1
		var data:={"size":size,"terrain_ids":terrain,"vertex_levels":levels,"seed":41721,"resources":[],"scenery":[],"cliff_cells":[],"cliff_obstructions":[]}
		var world=_world(data,{"players":[{"team":1,"civilization_id":13}],"entities":[]})
		for kind in ["fishing_boat","scout_ship","transport","catapult_trireme"]:
			var unit:Dictionary=world.add_unit(1,kind,Vector2(24.5,10.5),false)
			var radius:float=unit["footprint_radius"]
			var target:=Vector2(24.5,38.5)
			var path:Array=world.pathfinder.find_path(unit["pos"],target,"water",unit["terrain_restriction"],radius)
			var reaches:=not path.is_empty() and Vector2(path[-1]).distance_to(target)<0.6
			var expected:bool=not narrow or radius<=0.5
			check(reaches==expected,"hull clearance determines tight-reach access: "+kind)
			if expected:check(_move(world,unit,target),"ship completes the fitting control reach: "+kind)
			print("Control narrow=%s %s radius=%.2f route=%s"%[narrow,kind,radius,reaches])
			world.release_unit_destination(unit);world.detach_unit_for_transport(unit["id"])
		world.shutdown_derived_state()
		if not narrow:
			var barrier:Array[Vector2i]=[]
			for x in range(18,30):barrier.append(Vector2i(x,24))
			var rivers:={"rapids":[{"position":Vector2(24.5,24.5),"direction":Vector2.DOWN,"radius":6.0,"barrier_cells":barrier}]}
			var rocks:Array=[];var occupied:Dictionary={}
			Rapids.append_rocks(rivers,rocks,occupied,{},41721)
			data["cliff_obstructions"]=rocks;data["cliff_cells"]=occupied.keys()
			world=_world(data,{"players":[{"team":1,"civilization_id":13}],"entities":[]})
			for kind in ["fishing_boat","scout_ship","transport","catapult_trireme"]:
				var unit:Dictionary=world.add_unit(1,kind,Vector2(24.5,10.5),false)
				var target:=Vector2(24.5,38.5)
				var path:Array=world.pathfinder.find_path(unit["pos"],target,"water",unit["terrain_restriction"],unit["footprint_radius"])
				check(path.is_empty() or Vector2(path[-1]).distance_to(target)>1.0,"visible boulders divide two otherwise navigable pools: "+kind)
				world.detach_unit_for_transport(unit["id"])
			check(data["terrain_ids"]==terrain,"boulder obstruction preserves the visible water underneath")
			world.shutdown_derived_state()
	var tested_routes:=0
	for profile in ["grasslands","highlands"]:
		var settings:=Settings.default_settings();settings["map_type_id"]=profile;settings["map_size_id"]="large"
		var built:=Settings.build(settings)
		check(built.get("valid",false),profile+" builds")
		if not built.get("valid",false):continue
		var data:Dictionary=built["map_data"]
		var world=_world(data,built["definition"])
		for actor in world.get_units().duplicate():world.detach_unit_for_transport(actor["id"])
		var channels:Array=data["rivers"]["channels"].duplicate()
		channels.sort_custom(func(a,b):return a["points"].size()>b["points"].size())
		var profile_routes:=0
		for kind in ["fishing_boat","scout_ship","transport","catapult_trireme"]:
			var probe:Dictionary=world.add_unit(1,kind,Vector2(1,1),false)
			world.detach_unit_for_transport(probe["id"])
			var endpoints:Array[Vector2]=[]
			for channel in channels:
				var points:PackedVector2Array=channel["points"]
				var reach:Array[Vector2]=[]
				for i in range(8,points.size()-8):
					# Use legal raster anchors, matching the actual route solver.
					var point:=Vector2(Vector2i(points[i].floor()))+Vector2.ONE*0.5
					var fits:bool=world.navigation_grid.is_position_walkable_for(point,probe["footprint_radius"],"water",probe["terrain_restriction"])
					if not reach.is_empty() and fits:fits=world.navigation_grid.is_segment_walkable_for(reach[-1],point,probe["footprint_radius"],"water",probe["terrain_restriction"])
					if not fits:reach.clear();continue
					reach.append(point)
					if reach[0].distance_to(reach[-1])>=7.0:
						var path:Array=world.pathfinder.find_path(reach[0],reach[-1],"water",probe["terrain_restriction"],probe["footprint_radius"])
						check(not path.is_empty() and Vector2(path[-1]).distance_to(reach[-1])<0.1,profile+": fitting raster reach has an actual complete route: "+kind)
						endpoints.assign([reach[0],reach[-1]]);break
				if not endpoints.is_empty():break
			# No long route for a large hull is a legitimate geography result.
			# The independent control cases above still require correct routing.
			if endpoints.is_empty():print(profile+" has no long fitting reach for "+kind);continue
			var unit:Dictionary=world.add_unit(1,kind,endpoints[0],false)
			check(unit["pos"].distance_to(endpoints[0])<0.1,"ship spawns on selected real reach: "+kind)
			check(_move(world,unit,endpoints[1]),profile+" ship completes a fitting curved reach: "+kind)
			profile_routes+=1;tested_routes+=1
			world.release_unit_destination(unit);world.detach_unit_for_transport(unit["id"])
		for rapid in data["rivers"]["rapids"]:
			for cell in rapid["barrier_cells"]:
				check(not world.navigation_grid.is_position_walkable_for(Vector2(cell)+Vector2.ONE*0.5,0.3,"water",0),profile+": rapid rocks block live navigation")
		print(profile+": fitted generated reaches tested = "+str(profile_routes))
		world.shutdown_derived_state()
	for failure in failures:push_error(failure)
	print("Natural river navigation: %d actual generated routes, %d failures"%[tested_routes,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _world(data:Dictionary,definition:Dictionary):
	var world=World.new(data["size"])
	world.set_gamespec(catalog.gamespec_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data);world.set_graphics_catalog(catalog.graphics_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world,definition,data)
	var visible:=PackedInt32Array()
	for i in range(data["size"].x*data["size"].y):visible.append(i)
	world.fog_of_war.ensure_player(1)
	world.fog_of_war._add_visible_cells(1,visible)
	world.fog_of_war.revision+=1;world.fog_of_war.revisions_by_player[1]+=1
	controller=Controller.new(world)
	return world

func _move(world,unit:Dictionary,target:Vector2) -> bool:
	controller.enqueue_command(Commands.MoveCommand.new(controller.tick_index+1,[int(unit["id"])],target),true,1)
	for tick in range(1200):
		controller.advance_frame(0.05,1,2)
		if unit["pos"].distance_to(target)<0.45:return true
	print("Failed arrival: ",unit["kind"]," ",unit["pos"]," -> ",target," task=",unit["task"]," path=",unit.get("path",[])," results=",controller.command_results)
	return false

func check(ok:bool,message:String) -> void:
	if not ok and not failures.has(message):failures.append(message)
