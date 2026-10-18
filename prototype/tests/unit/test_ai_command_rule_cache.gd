extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Queries := preload("res://scripts/simulation_observation_queries.gd")
const Preparation := preload("res://scripts/ai_observation_preparation.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
class CountingWorld extends "res://scripts/simulation_world.gd":
	var production_reads := 0
	func get_unit_production_options(building_id: int, team: int) -> Array:
		production_reads += 1
		return super.get_unit_production_options(building_id,team)
	func get_unit_production_availability(building_id: int, team: int, kind: String) -> Dictionary:
		production_reads += 1
		return super.get_unit_production_availability(building_id,team,kind)
	func get_research_options(building_id: int, team: int) -> Array:
		production_reads += 1
		return super.get_research_options(building_id,team)
	func get_research_availability(building_id: int, team: int, technology_id: int) -> Dictionary:
		production_reads += 1
		return super.get_research_availability(building_id,team,technology_id)
func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world := CountingWorld.new(Vector2i(24,24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var units: Array = [world.add_unit(1,"villager",Vector2(4,4),false)]
	var rows: Array = []
	for kind in ["town_center","barracks","granary","storage_pit"]: rows.append(world.add_building(100+rows.size(),kind,Vector2(8+rows.size(),8),1))
	var preparation := Preparation.new()
	for profiled in [false,true]:
		var options := {"economic_production_options_only":true,"planning_technology_ids":[100,101,102,103],"include_ai_profiles":profiled}
		for stage in range(7):
			for type_id in range(4): world.set_resource_amount(1,type_id,0 if stage == 1 else 10000)
			if stage == 3: rows[0]["production_queue"] = [{"kind":"villager","order_type":"unit","status":"training"}]
			if stage == 4: rows[0]["production_queue"] = [{"kind":"villager","order_type":"unit","status":"blocked_population"}]
			if stage == 5: units.append(world.add_unit(10+units.size(),"villager",Vector2(5,5),false))
			if stage == 6: world.technology_system.mark_researching(1,100)
			var cached := options.duplicate()
			cached["_ai_command_options_cache"] = {}
			cached["_ai_command_rule_cache"] = preparation._command_rule_cache(world,1,units,options)
			var profiles: Dictionary = {}
			for row in rows:
				var expected := Queries.building_command_options(world,row,1,options,units,{})
				world.production_reads = 0
				var actual := Queries.building_command_options(world,row,1,cached,units,profiles)
				if stage in [1,2]: check(world.production_reads == 0,"stock-only changes must reprice retained rules without querying production again")
				check(actual == expected,"rule reuse changed options at stage %d profiles=%s" % [stage,profiled])
				check(Data.is_detached(actual) and actual.is_read_only(),"rule publications remain immutable and detached")
	var cache := {"entries":{},"sizes":{},"bytes":0}
	var value := Data.capture_frozen({"train":[],"research":[]})
	var lineage: Array = [109]
	Queries._remember_command_rules(cache,["town_center",lineage],value)
	lineage.append(87)
	check(cache["entries"].has(["town_center",[109]]),"a live lineage cannot mutate a retained dictionary key")
	for index in range(Queries.MAX_COMMAND_RULE_ENTRIES + 5): Queries._remember_command_rules(cache,["qa_"+str(index)],value)
	check(cache["entries"].size() <= Queries.MAX_COMMAND_RULE_ENTRIES,"rule entry count is bounded")
	cache = {"entries":{},"sizes":{},"bytes":0}
	var large := Data.capture_frozen({"train":[],"research":[],"padding":"x".repeat(300000)})
	for index in range(10): Queries._remember_command_rules(cache,[index],large)
	check(cache["bytes"] <= Queries.MAX_COMMAND_RULE_BYTES and cache["entries"].size() < 10,"rule payload bytes are bounded")
	var oversized := {"production_requests":[{"runtime_alias":"x".repeat(Preparation.MAX_COMMAND_RULE_SCHEMA_BYTES)}]}
	check(preparation._command_rule_cache(world,1,units,oversized).is_empty(),"oversized rule schemas use uncached queries")
	preparation.clear()
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI command rule cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
