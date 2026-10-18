extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Queries := preload("res://scripts/simulation_observation_queries.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world := World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for type_id in range(4): world.set_resource_amount(1,type_id,10000)
	var units: Array = [world.add_unit(1,"villager",Vector2(4,4),false)]
	var rows: Array = []
	for kind in ["house","town_center","town_center","barracks","barracks","granary","storage_pit"]:
		rows.append(world.add_building(1000+rows.size(),kind,Vector2(8+rows.size(),8),1))
	for variant in range(6):
		var row: Dictionary = world.add_building(1100+variant,"town_center",Vector2(10+variant,16),1,variant != 4)
		if variant == 5: row["hp"] = 0.0
		if variant in [1,2,3]:
			var queue: Array = []
			for i in range(1 if variant == 1 else 2 if variant == 2 else 15): queue.append({"kind":"villager","order_type":"unit","status":"training" if variant != 2 else "blocked_population"})
			row["production_queue"] = queue
		rows.append(row)
	for profiled in [false,true]:
		var options := {"economic_production_options_only":true,"planning_technology_ids":[100,101,102,103],"include_ai_profiles":profiled}
		var cached := options.duplicate()
		cached["_ai_command_options_cache"] = {}
		var profile_cache: Dictionary = {}
		for row in rows:
			var expected := Queries.building_command_options(world,row,1,options,units,{})
			var actual := Queries.building_command_options(world,row,1,cached,units,profile_cache)
			if actual != expected: failures.append("Cached availability differs for "+str(row.id)+" profiles="+str(profiled))
			if not actual.is_read_only(): failures.append("Cached option graph must be immutable")
		if cached["_ai_command_options_cache"].size() >= rows.size(): failures.append("Equivalent producers did not share a generation template")
	var worker_options := {"requested_build_site_kinds":["house","barracks","granary"],"skip_spatial_queries":true}
	var worker_cached := worker_options.duplicate()
	worker_cached["_ai_build_options_cache"] = {}
	var snapshot := {"observer_team":1,"tick":0,"units":[units[0],units[0]],"buildings":[]}
	var expected_workers := Data.capture_frozen(Queries.enrich(world,snapshot,worker_options))
	var actual_workers := Data.capture_frozen(Queries.enrich(world,snapshot,worker_cached))
	if actual_workers != expected_workers: failures.append("Shared worker menus changed the observation")
	var retained: Dictionary = worker_cached["_ai_build_options_cache"]["worker_commands"]
	var again := Queries.enrich(world,snapshot,worker_cached)
	if not is_same(retained,again["units"][0]["command_options"]): failures.append("Worker menu was copied inside the same pinned generation")
	if not retained.is_read_only() or not retained["build"].is_read_only(): failures.append("Shared worker menu is mutable")
	world.set_resource_amount(1,0,0)
	worker_cached["_ai_build_options_cache"] = {}
	if Data.capture_frozen(Queries.enrich(world,snapshot,worker_cached)) != Data.capture_frozen(Queries.enrich(world,snapshot,worker_options)): failures.append("A fresh generation retained stale affordability")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI command options cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
