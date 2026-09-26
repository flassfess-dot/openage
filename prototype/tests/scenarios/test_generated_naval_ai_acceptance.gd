extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const MAX_TICKS := 10000
const AI_TEAM := 2

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "islands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated islands match builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var catalog = ResourceCatalog.new()
	catalog.load()
	var definition: Dictionary = built["definition"]
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var bootstrap := MatchBootstrap.apply(world, definition, built["map_data"])
	assert_true(bool(bootstrap.get("naval_start_guarantees_met", false)), "generated islands bootstrap retains a legal naval start for every player")
	var controller = GameController.new(world)
	controller.set_speed_multiplier(3.0)
	var ai = AiPlayer.new(definition["players"][1])
	var issued_types: Dictionary = {}
	var accepted_types: Dictionary = {}
	var rejected_reasons: Dictionary = {}
	var rejected_types: Dictionary = {}
	var accepted_water_orders := 0
	var fish_discovered := false

	while int(controller.tick_index) < MAX_TICKS and not world.is_battle_over():
		var next_tick := int(controller.tick_index) + 1
		var submitted: Array = []
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, AI_TEAM, ai.presentation_options())
			fish_discovered = fish_discovered or knowledge.get("resources", []).any(func(resource): return String(resource.get("kind", "")) == "deep_fish" and int(resource.get("amount", 0)) > 0)
			for command in ai.collect_commands(knowledge, next_tick):
				var command_type := String(command.command_type())
				issued_types[command_type] = int(issued_types.get(command_type, 0)) + 1
				controller.enqueue_command(command, true, AI_TEAM)
				submitted.append(command)
		controller.advance_frame(0.5, 1, 2)
		for command in submitted:
			var command_type := String(command.command_type())
			var result: Dictionary = controller.get_command_result(int(command.sequence_id))
			if bool(result.get("accepted", false)):
				accepted_types[command_type] = int(accepted_types.get(command_type, 0)) + 1
				if command_type in ["move", "formation_move", "attack", "attack_move", "gather"] and _command_has_live_water_unit(world, command):
					accepted_water_orders += 1
			else:
				var reason := String(result.get("reason", "unknown"))
				rejected_reasons[reason] = int(rejected_reasons.get(reason, 0)) + 1
				rejected_types[command_type] = int(rejected_types.get(command_type, 0)) + 1
		var completed_dock_exists: bool = world.get_buildings().any(func(building): return int(building.get("team", 0)) == AI_TEAM and String(building.get("kind", "")) == "dock" and String(building.get("state", "complete")) == "complete")
		var scout_exists: bool = world.get_units().any(func(unit): return int(unit.get("team", 0)) == AI_TEAM and float(unit.get("hp", 0.0)) > 0.0 and String(unit.get("kind", "")) == "scout_ship")
		if completed_dock_exists and scout_exists and fish_discovered and accepted_water_orders > 0:
			break

	var own_units: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == AI_TEAM and float(unit.get("hp", 0.0)) > 0.0)
	var own_buildings: Array = world.get_buildings().filter(func(building): return int(building.get("team", 0)) == AI_TEAM)
	var completed_docks: Array = own_buildings.filter(func(building): return String(building.get("kind", "")) == "dock" and String(building.get("state", "complete")) == "complete")
	var water_units: Array = own_units.filter(func(unit): return String(unit.get("movement_domain", "land")) == "water")
	var scout_ships: Array = water_units.filter(func(unit): return String(unit.get("kind", "")) == "scout_ship")
	assert_true(not accepted_types.is_empty(), "generated islands AI acts through accepted public commands")
	assert_true(not completed_docks.is_empty(), "generated islands AI completes an autonomous Dock")
	assert_true(not water_units.is_empty(), "generated islands AI autonomously produces a water-domain unit")
	assert_true(not scout_ships.is_empty(), "generated islands AI produces a Scout Ship to reveal its water component")
	assert_true(accepted_water_orders > 0, "generated islands AI issues an accepted order to its produced water-domain unit")
	assert_true(fish_discovered, "generated islands naval exploration reveals generated deep fish through fog-safe knowledge")
	if failures.is_empty():
		print("E5-006C naval exploration reached at tick %d: dock=%d scouts=%d fish_discovered=%s water_orders=%d" % [controller.tick_index, completed_docks.size(), scout_ships.size(), fish_discovered, accepted_water_orders])
	else:
		var final_knowledge := SimulationSnapshot.presentation(world, controller.tick_index, AI_TEAM, ai.presentation_options())
		var visible_enemy_count: int = final_knowledge.get("units", []).filter(func(unit): return int(unit.get("team", 0)) > 0 and int(unit.get("team", 0)) != AI_TEAM).size()
		visible_enemy_count += final_knowledge.get("buildings", []).filter(func(building): return int(building.get("team", 0)) > 0 and int(building.get("team", 0)) != AI_TEAM).size()
		var water_navigation: Dictionary = final_knowledge.get("navigation", {})
		var known_fish_ids: Dictionary = {}
		for resource_value in final_knowledge.get("resources", []):
			if String(resource_value.get("kind", "")) == "deep_fish":
				known_fish_ids[int(resource_value.get("id", -1))] = true
		var fish_diagnostics: Array = []
		for resource_value in world.get_resources():
			if String(resource_value.get("kind", "")) != "deep_fish":
				continue
			var position := Vector2(resource_value.get("pos", Vector2.ZERO))
			fish_diagnostics.append({"id": resource_value.get("id"), "pos": position, "amount": resource_value.get("amount"), "known": known_fish_ids.has(int(resource_value.get("id", -1))), "fog": world.get_fog_of_war().state_at_cell(AI_TEAM, Vector2i(floori(position.x), floori(position.y)))})
		var ship_diagnostics: Array = water_units.map(func(unit): return {"id": unit.get("id"), "kind": unit.get("kind"), "pos": unit.get("pos"), "task": unit.get("task"), "reason": unit.get("diagnostic_reason"), "path_status": unit.get("path_status"), "destination": unit.get("destination")})
		print("E5-006C naval failure diagnostics tick=%d age=%d issued=%s accepted=%s rejected=%s rejected_types=%s visible_enemies=%d result=%s" % [controller.tick_index, world.get_current_age(AI_TEAM), issued_types, accepted_types, rejected_reasons, rejected_types, visible_enemy_count, world.get_victory_result()])
		print("E5-006C naval exploration detail reachable_water=%d frontier_water=%d ships=%s fish=%s" % [water_navigation.get("reachable", {}).get("water", []).size(), water_navigation.get("reachable_frontier", {}).get("water", []).size(), ship_diagnostics, fish_diagnostics])
		print("E5-006C economy state=%s units=%s" % [final_knowledge.get("player_state", {}), own_units.map(func(unit): return {"id": unit.get("id"), "kind": unit.get("kind"), "task": unit.get("task"), "reason": unit.get("diagnostic_reason"), "pos": unit.get("pos"), "target_resource": unit.get("resource_id"), "carried": unit.get("carried_amount"), "deposits": unit.get("deposit_cycles")})])
		print("E5-006C buildings=%s" % [own_buildings.map(func(building): return {"kind": building.get("kind"), "state": building.get("state"), "pos": building.get("pos"), "progress": building.get("build_progress")})])
		print("E5-006C dock production=%s" % [final_knowledge.get("buildings", []).filter(func(building): return int(building.get("team", 0)) == AI_TEAM and String(building.get("kind", "")) == "dock").map(func(building): return {"queue": building.get("production_queue", []), "train": building.get("command_options", {}).get("train", [])})])
	finish()


func _command_has_live_water_unit(world, command) -> bool:
	for unit_id_value in command.unit_ids:
		var unit = world.find_unit(int(unit_id_value))
		if unit != null and int(unit.get("team", 0)) == AI_TEAM and float(unit.get("hp", 0.0)) > 0.0 and String(unit.get("movement_domain", "land")) == "water":
			return true
	return false


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated naval AI acceptance passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
