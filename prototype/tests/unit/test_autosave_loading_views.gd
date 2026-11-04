extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Loading := preload("res://scripts/navigation_loading.gd")
var catalog:=Catalog.new()
var failures: Array[String]=[]
func create_world():
	var world:=World.new(Vector2i(24,24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data,false)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world
func _initialize() -> void:
	catalog.load_generated_data()
	var source=create_world()
	source.navigation_grid.configure_terrain(func(_cell):return "grass")
	source.add_building(700,"town_center",Vector2(6,6),1)
	source.add_building(701,"town_center",Vector2(18,18),2)
	var worker: Dictionary=source.add_unit(1,"villager",Vector2(14,17),false)
	source.add_unit(2,"villager",Vector2(16,16),false)
	var resource: Dictionary=source.add_resource("berries",Vector2(15,17),100)
	source.update_fog_of_war()
	source.assign_command_gather([worker],int(resource["id"]))
	var definition: Dictionary={"local_team":1,"players":[{"team":1,"controller":"human"},{"team":2,"controller":"ai","ai":{"enabled":true}}]}
	var controller:=Controller.new(source)
	var seed: Dictionary=Checkpoint.capture(source,controller,definition,{})
	var snapshots: Array=[]
	for full in [true,false]:
		var world=create_world()
		var restored:=Controller.new(world)
		if not Checkpoint.restore(seed.duplicate(true),world,restored): failures.append("checkpoint restore failed")
		var loading:=Loading.new()
		loading.coordinator.enabled=false
		loading.prepare_ai_views=full
		loading.begin(world,definition["players"],false)
		var attempts:=0
		while not loading.poll(world) and attempts<1000: attempts+=1
		if attempts>=1000:failures.append("loading failed to finish")
		loading.shutdown()
		if not full and not world.ai_navigation_knowledge.entries.is_empty():failures.append("recovery should not build discarded AI navigation")
		var before: Dictionary=Checkpoint.capture(world,restored,definition,{})
		for tick in range(24):
			restored._run_fixed_tick(1,2)
		if int(world.find_resource(int(resource["id"]))["amount"])>=100:failures.append("recovery fixture did not exercise resource memory updates")
		var after: Dictionary=Checkpoint.capture(world,restored,definition,{})
		snapshots.append([before,after])
		world.shutdown_derived_state()
	for phase in range(2):
		if snapshots[0][phase]!=snapshots[1][phase]:
			for key in snapshots[0][phase]:
				if snapshots[0][phase][key]!=snapshots[1][phase][key]:failures.append("durable %s differs, phase %d"%[key,phase])
	source.shutdown_derived_state()
	for failure in failures:push_error(failure)
	print("Autosave loading views: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
