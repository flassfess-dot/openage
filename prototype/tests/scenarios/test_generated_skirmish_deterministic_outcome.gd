extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const StrategicPlanner := preload("res://scripts/ai_strategic_planner.gd")
const TacticalPlanner := preload("res://scripts/ai_tactical_planner.gd")

const PROGRESS_TICK := 13000
const MAX_TICKS := 16000
const SEED := 41721

var failures: Array[String] = []


func _initialize() -> void:
	var built := generated_match()
	assert_true(bool(built.get("valid", false)), "deterministic outcome match builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var live := create_runtime(built)
	var world = live["world"]
	var controller = live["controller"]
	var ai = AiPlayer.new(built["definition"]["players"][1])
	var recorder = controller.start_recording(SEED, false)
	var issued := 0
	var progress_tick := -1
	var progress_town_center_hp := 600.0
	while int(controller.tick_index) < MAX_TICKS and not world.is_battle_over():
		var next_tick := int(controller.tick_index) + 1
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, int(ai.team))
				issued += 1
		controller.advance_frame(0.5, 1, 2)
		if progress_tick < 0 and int(controller.tick_index) >= PROGRESS_TICK:
			progress_tick = int(controller.tick_index)
			progress_town_center_hp = _enemy_town_center_hp(world)

	var final_tick := int(controller.tick_index)
	var result: Dictionary = world.get_victory_result()
	var final_hash: String = recorder.world_state_hash(world, final_tick, controller)
	print("E5-006B live tick=%d issued=%d battle_over=%s result=%s hash=%s" % [final_tick, issued, world.is_battle_over(), result, final_hash])
	if progress_tick >= 0:
		print("E5-006B progress tick=%d enemy_town_center_hp=%.2f" % [progress_tick, progress_town_center_hp])
	if not world.is_battle_over():
		var terminal_knowledge := SimulationSnapshot.presentation(world, final_tick, int(ai.team), ai.presentation_options())
		var terminal_goal := StrategicPlanner.choose_goal(terminal_knowledge, int(ai.team), ai.decision_index)
		var terminal_commands := TacticalPlanner.plan(terminal_knowledge, final_tick + 1, int(ai.team), terminal_goal, ai.formation_name, ai.minimum_attack_group_size, ai.maximum_attack_group_size, ai.use_workers_in_attack_groups)
		var planned_summary: Array[String] = []
		for command in terminal_commands:
			planned_summary.append("%s:%s" % [command.command_type(), command.unit_ids])
		print("E5-006B AI diagnostic last_military=%d last_attack=%d decisions=%d goal=%s planned=%s" % [ai.last_military_tick, ai.last_attack_tick, ai.decision_index, terminal_goal, planned_summary])
		print("E5-006B economy diagnostic player=%s" % terminal_knowledge.get("player_state", {}))
		for building_value in terminal_knowledge.get("buildings", []):
			var own_building: Dictionary = building_value
			if int(own_building.get("team", 0)) == int(ai.team):
				print("E5-006B production diagnostic id=%d kind=%s queue=%s train=%s" % [int(own_building.get("id", -1)), String(own_building.get("kind", "")), own_building.get("production_queue", []), own_building.get("command_options", {}).get("train", [])])
		print("E5-006B terminal diagnostic units=%s buildings=%s" % [_survivor_summary(world.get_units()), _survivor_summary(world.get_buildings())])
		for entity_value in world.get_units() + world.get_buildings():
			var entity: Dictionary = entity_value
			if float(entity.get("hp", 0.0)) <= 0.0 or (int(entity.get("team", 0)) != 1 and String(entity.get("kind", "")) != "clubman"):
				continue
			print("E5-006B entity id=%d team=%d kind=%s pos=%s hp=%.2f task=%s target_id=%d destination=%s combat_destination=%s path=%d path_index=%d status=%s reason=%s radius=%.3f" % [int(entity.get("id", -1)), int(entity.get("team", 0)), String(entity.get("kind", "")), str(entity.get("pos", Vector2.ZERO)), float(entity.get("hp", 0.0)), String(entity.get("task", "static")), int(entity.get("target_id", -1)), str(entity.get("destination", Vector2.ZERO)), str(entity.get("combat_destination", null)), entity.get("path", []).size(), int(entity.get("path_index", 0)), String(entity.get("path_status", "")), String(entity.get("diagnostic_reason", "")), float(entity.get("footprint_radius", 0.0))])
	assert_true(issued > 0, "generated AI records public commands")
	assert_true(progress_tick < 0 or progress_town_center_hp < 600.0, "generated AI damages the enemy Town Center by the original 13000-tick checkpoint")
	assert_true(world.is_battle_over(), "generated two-player inland match reaches a terminal state")
	assert_equal(int(result.get("winner_team", 0)), 2, "active generated AI defeats the idle human opponent")
	assert_equal(String(result.get("reason", "")), "conquest", "generated match ends through configured conquest")

	if world.is_battle_over():
		var replay := create_runtime(generated_match())
		var replay_world = replay["world"]
		var replay_controller = replay["controller"]
		assert_true(replay_controller.load_replay(recorder.to_json()), "generated command recording loads for deterministic playback")
		assert_true(replay_controller.replay_until_tick(final_tick, 1, 2), "generated command recording reaches the live terminal tick")
		var replay_hash: String = recorder.world_state_hash(replay_world, final_tick, replay_controller)
		assert_equal(replay_hash, final_hash, "generated victory has an identical canonical replay hash")
		assert_equal(replay_world.get_victory_result(), result, "generated replay preserves the exact victory result")
	finish()


func generated_match() -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "grasslands"
	settings["seed"] = SEED
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	return SkirmishSettings.build(settings)


func create_runtime(built: Dictionary) -> Dictionary:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var definition: Dictionary = built["definition"]
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, built["map_data"])
	return {"world": world, "controller": GameController.new(world)}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func _survivor_summary(entities: Array) -> Dictionary:
	var result: Dictionary = {}
	for entity_value in entities:
		var entity: Dictionary = entity_value
		if float(entity.get("hp", 0.0)) <= 0.0:
			continue
		var key := "%d:%s:%s:%s" % [int(entity.get("team", 0)), String(entity.get("kind", "")), String(entity.get("task", "static")), String(entity.get("diagnostic_reason", ""))]
		result[key] = int(result.get(key, 0)) + 1
	return result


func _enemy_town_center_hp(world) -> float:
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if int(building.get("team", 0)) == 1 and String(building.get("kind", "")) == "town_center":
			return maxf(0.0, float(building.get("hp", 0.0)))
	return 0.0


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006B generated skirmish deterministic outcome passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
