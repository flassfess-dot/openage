extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
var output := "res://qa/economy-fixes-20261003/before-ai.json"
var max_ticks := 6000
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "compact"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--map-type="): settings["map_type_id"] = arg.trim_prefix("--map-type=")
		if arg.begins_with("--map-size="): settings["map_size_id"] = arg.trim_prefix("--map-size=")
		if arg.begins_with("--seed="): settings["seed"] = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--ticks="): max_ticks = int(arg.trim_prefix("--ticks="))
	var built := Settings.build(settings)
	if not built.get("valid",false):
		push_error(str(built.get("errors")))
		quit(1)
		return
	var catalog := Catalog.new()
	catalog.load()
	var world := World.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world,built["definition"],built["map_data"])
	# Keep the passive diagnostic opponent alive so an early victory does not
	# conceal an economic stall. The AI itself receives normal starting resources.
	for entity in world.get_units()+world.get_buildings():
		if entity["team"] == 1: entity["hp"] = 100000.0
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ai := Ai.new(built["definition"]["players"][1])
	var trace := []
	for tick in range(max_ticks):
		var next_tick := controller.tick_index+1
		if ai.needs_decision(next_tick):
			var snapshot := Snapshot.with_queries(world,controller.tick_index,2,ai.presentation_options())
			for command in ai.collect_commands(snapshot,next_tick): controller.enqueue_command(command,true,2)
		controller.advance_frame(.05,1,2)
		if tick%1000 == 999 or tick == max_ticks-1:
			var snapshot := Snapshot.with_queries(world,controller.tick_index,2,ai.presentation_options())
			var own_workers: Array = world.get_units().filter(func(u):return u["team"] == 2 and world.entity_is_worker(u))
			var record := {"tick":controller.tick_index,"age":world.get_current_age(2),"resources":snapshot["player_state"],"workers":own_workers.map(func(u):return {"id":u["id"],"pos":u["pos"],"task":u["task"],"stage":u.get("gather_stage"),"resource_id":u.get("resource_id"),"reason":u.get("diagnostic_reason"),"carry":u.get("carried_amount")}),"buildings":snapshot["buildings"].filter(func(b):return b["team"]==2).map(func(b):return {"kind":b["kind"],"state":b["state"],"queue":b.get("production_queue"),"research":b.get("command_options",{}).get("research",[])})}
			trace.append(record)
			print("tick=",controller.tick_index," age=",world.get_current_age(2)," stock=",[world.get_resource_amount(2,0),world.get_resource_amount(2,1),world.get_resource_amount(2,2),world.get_resource_amount(2,3)]," workers=",own_workers.size()," buildings=",record["buildings"].map(func(b):return b["kind"]+":"+b["state"]))
	var events: Array = controller.events_after()
	var path := ProjectSettings.globalize_path(output)
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"settings":settings,"trace":trace,"events":events.filter(func(e):return e["type"] in ["command_rejected","research_queued","research_complete","building_completed"])},"\t"))
	quit(0)