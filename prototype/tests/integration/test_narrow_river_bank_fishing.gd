extends SceneTree
const Support := preload("res://scripts/random_map_generation_support.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")

func _initialize() -> void:
	var size:=Vector2i(40,40)
	var terrain:Array[int]=[];terrain.resize(1600)
	var levels:Array[int]=[];levels.resize(41*41)
	var freshwater:=PackedByteArray();freshwater.resize(1600)
	for y in range(4,36):terrain[y*40+20]=4;freshwater[y*40+20]=1
	var clusters:=Support._neutral_fish_clusters(size,terrain,41721,{},[],freshwater)
	if clusters.is_empty():push_error("narrow Shallows stream must offer bank fish");quit(1);return
	var catalog:=Catalog.new();catalog.load()
	var world:=World.new(size)
	world.set_gamespec(catalog.gamespec_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data);world.set_graphics_catalog(catalog.graphics_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world,{"players":[{"team":1,"civilization_id":13}],"entities":[]},{"size":size,"seed":41721,"terrain_ids":terrain,"vertex_levels":levels,"resources":[],"scenery":[]})
	var point:=Vector2(clusters[0]["center"][0],clusters[0]["center"][1])
	world.add_building(1300,"town_center",Vector2(14.5,point.y),1)
	var worker:Dictionary=world.add_unit(1,"villager",point+Vector2(-2,0),false)
	var fish:Dictionary=world.add_resource("shore_fish",point,2)
	var before:=world.get_resource_amount(1,0)
	var controller:=Controller.new(world)
	controller.enqueue_command(Commands.GatherCommand.new(1,[int(worker["id"])],int(fish["id"])),true,1)
	for tick in range(1600):
		controller.advance_frame(0.05,1,2)
		if world.get_resource_amount(1,0)==before+2:break
	var ok:=world.get_resource_amount(1,0)==before+2
	if not ok:push_error("villager failed to collect and return narrow-stream fish: "+str(worker["task"]))
	world.shutdown_derived_state()
	print("Narrow river bank fishing: villager gathered and returned food = ",ok)
	quit(0 if ok else 1)
