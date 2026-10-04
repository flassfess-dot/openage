extends SceneTree

const Ai := preload("res://scripts/ai_player.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const MAX_TICKS := 18000
var failures: Array[String] = []

func _initialize() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "grasslands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "standard"
	var built := Settings.build(settings)
	check(bool(built.get("valid",false)), "normal-resource generated match builds")
	if not built.get("valid",false):
		finish()
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
	check(world.get_resource_amount(2,0) == 200 and world.get_resource_amount(2,1) == 200, "AI receives ordinary 200 food and wood")
	# An early victory must not end this economy regression before age research.
	# Only the passive opponent receives extra HP; AI costs and yields are intact.
	for entity in world.get_units()+world.get_buildings():
		if entity["team"] == 1: entity["hp"] = 100000.0
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ai := Ai.new(built["definition"]["players"][1])
	while controller.tick_index < MAX_TICKS and world.get_current_age(2) < 101:
		var tick: int = controller.tick_index+1
		if ai.needs_decision(tick):
			var knowledge := Snapshot.presentation(world,controller.tick_index,2,ai.presentation_options())
			for command in ai.collect_commands(knowledge,tick): controller.enqueue_command(command,true,2)
		controller.advance_frame(.05,1,2)
	var complete_kinds: Array = world.get_buildings().filter(func(b):return b["team"] == 2 and b["state"] == "complete").map(func(b):return b["kind"])
	check(world.get_current_age(2) >= 101, "AI completes Tool Age without free resources or prebuilt prerequisites")
	check("barracks" in complete_kinds and "granary" in complete_kinds, "AI completes its own Stone Age prerequisites")
	var wood_after_saving := false
	var age_researched := false
	for event in controller.events_after():
		var payload: Dictionary = event.get("payload",{})
		if event["type"] == "resources_deposited" and int(payload.get("team",0)) == 2 and int(payload.get("resource_type_id",-1)) == 1 and int(event["tick"]) > 2000:
			wood_after_saving = true
		if event["type"] == "command_accepted" and int(payload.get("issuer_id",0)) == 2 and payload.get("command_type") == "research": age_researched = true
	check(wood_after_saving, "wood income continues after AI begins reserving food for its age advance")
	check(age_researched, "age research uses the public command pipeline")
	print("Normal-resource AI progression: tick=",controller.tick_index," age=",world.get_current_age(2)," buildings=",complete_kinds)
	finish()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func finish() -> void:
	if failures.is_empty():
		print("Normal-resource AI age progression tests passed")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)