extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const MAX_TICKS := 4000

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "grasslands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "standard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated acceptance match builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		_finish()
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
	MatchBootstrap.apply(world, definition, built["map_data"])
	var controller = GameController.new(world)
	var ai = AiPlayer.new(definition["players"][1])
	var issued := 0

	while int(controller.tick_index) < MAX_TICKS:
		var next_tick := int(controller.tick_index) + 1
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, int(ai.team))
				issued += 1
		controller.advance_frame(0.25, 1, 2)
		if world.is_battle_over():
			break

	var team_two_units := world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 2 and float(unit.get("hp", 0.0)) > 0.0)
	var workers := team_two_units.filter(func(unit): return world.entity_is_worker(unit))
	var combatants := team_two_units.filter(func(unit): return bool(unit.get("combat_enabled", false)) and not world.entity_is_worker(unit))
	var team_two_buildings := world.get_buildings().filter(func(building): return int(building.get("team", 0)) == 2 and float(building.get("hp", 0.0)) > 0.0)
	var kinds: Array = team_two_buildings.map(func(building): return String(building.get("kind", "")))
	var accepted := 0
	var rejected := 0
	var rejection_reasons: Dictionary = {}
	var accepted_types: Dictionary = {}
	for event in controller.events_after():
		if String(event.get("type", "")) == "command_accepted" and int(event.get("payload", {}).get("issuer_id", 0)) == 2:
			accepted += 1
			var command_type := String(event.get("payload", {}).get("command_type", "unknown"))
			accepted_types[command_type] = int(accepted_types.get(command_type, 0)) + 1
		elif String(event.get("type", "")) == "command_rejected" and int(event.get("payload", {}).get("issuer_id", 0)) == 2:
			rejected += 1
			var reason := String(event.get("payload", {}).get("reason", "unknown"))
			rejection_reasons[reason] = int(rejection_reasons.get(reason, 0)) + 1
	var resources := [world.get_resource_amount(2, 0), world.get_resource_amount(2, 1), world.get_resource_amount(2, 2), world.get_resource_amount(2, 3)]
	var queues: Array = team_two_buildings.map(func(building): return {"id": int(building.get("id", -1)), "kind": String(building.get("kind", "")), "pos": building.get("pos", Vector2.ZERO), "state": String(building.get("state", "")), "progress": snappedf(float(building.get("construction_progress", 0.0)), 0.01), "builders": building.get("builders", {}).size(), "queue": building.get("production_queue", []).size()})
	print("E5-006 diagnostics tick=%d issued=%d accepted=%d types=%s rejected=%d reasons=%s workers=%d combatants=%d pop=%d/%d age=%d resources=%s buildings=%s battle_over=%s" % [controller.tick_index, issued, accepted, accepted_types, rejected, rejection_reasons, workers.size(), combatants.size(), world.get_population(2), world.get_population_cap(2), world.get_current_age(2), resources, queues, world.is_battle_over()])

	assert_true(issued > 0 and accepted > 0, "generated AI acts only through accepted public commands")
	assert_true(workers.size() >= 6, "generated AI grows a viable workforce")
	assert_true("house" in kinds, "generated AI completes population housing")
	assert_true("barracks" in kinds, "generated AI completes its first military producer")
	assert_true(combatants.size() >= 3 or world.is_battle_over(), "generated AI fields a policy-sized attack group")
	assert_true(int(accepted_types.get("research", 0)) > 0 or world.get_current_age(2) >= 101, "generated AI starts its first age advance")
	assert_true(int(accepted_types.get("formation_move", 0)) > 0 or int(accepted_types.get("attack_move", 0)) > 0 or int(accepted_types.get("attack", 0)) > 0, "generated military leaves the base through the ordinary combat command pipeline")
	assert_true(rejected <= maxi(2, accepted / 10), "generated AI does not rely on rejected command spam (%d/%d)" % [rejected, accepted])
	_finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func _finish() -> void:
	if failures.is_empty():
		print("E5-006 generated inland skirmish AI acceptance passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
