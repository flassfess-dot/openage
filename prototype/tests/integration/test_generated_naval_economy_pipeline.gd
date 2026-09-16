extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const AI_TEAM := 2
const MAX_TICKS := 3000

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "islands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated naval economy fixture builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var definition: Dictionary = built["definition"]
	var ai_settings: Dictionary = definition["players"][1]["ai"]
	ai_settings["land_worker_target"] = 3
	ai_settings["water_worker_target"] = 1
	ai_settings["minimum_workers_before_age_up"] = 999
	ai_settings["construction_priorities"] = []
	ai_settings["building_limits"] = {}
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, built["map_data"])

	var zone: Dictionary = built["map_data"].get("naval_start_zones", [])[1]
	var dock: Dictionary = world.add_building(10001, "dock", Vector2(zone["dock_position"]), AI_TEAM)
	var scout: Dictionary = world.add_unit(AI_TEAM, "scout_ship", Vector2(zone["water_staging"]), false)
	scout["components"]["vision"]["range"] = 20.0
	var population_before_fishing_boat := world.get_population(AI_TEAM)
	world.update_fog_of_war()
	var fish_resources: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
	var generated_fish_positions: Array = built["map_data"].get("resources", []).filter(func(resource): return String(resource.get("kind", "")) == "deep_fish").map(func(resource): return Vector2(resource.get("position", Vector2.ZERO)))
	assert_true(fish_resources.all(func(resource): return Vector2(resource.get("pos", Vector2.ZERO)) in generated_fish_positions), "bootstrap preserves generator-validated deep-fish positions")
	fish_resources.sort_custom(func(left, right): return Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(zone["water_staging"])) < Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(zone["water_staging"])))
	assert_true(not fish_resources.is_empty(), "generated islands fixture contains deep fish")
	if fish_resources.is_empty():
		finish()
		return
	var fish: Dictionary = fish_resources[0]
	var staging_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(zone["water_staging"])), "water")
	var fish_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(fish["pos"])), "water")
	assert_equal(fish_component, staging_component, "guaranteed fish shares the Dock water component")

	var ai = AiPlayer.new(definition["players"][1])
	var initial_knowledge := SimulationSnapshot.presentation(world, 0, AI_TEAM, ai.presentation_options())
	assert_true(initial_knowledge.get("resources", []).any(func(resource): return int(resource.get("id", -1)) == int(fish["id"])), "scouted generated fish reaches fog-safe AI knowledge")
	var controller = GameController.new(world)
	controller.set_speed_multiplier(3.0)
	var accepted_fishing_train := 0
	var accepted_fishing_gather := 0
	var gather_failure: Dictionary = {}
	var initial_fish_amount := int(fish.get("amount", 0))
	var food_before := world.get_resource_amount(AI_TEAM, 0)

	while int(controller.tick_index) < MAX_TICKS:
		var next_tick := int(controller.tick_index) + 1
		var submitted: Array = []
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, AI_TEAM, ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, AI_TEAM)
				submitted.append(command)
		controller.advance_frame(0.5, 1, 2)
		for command in submitted:
			var result: Dictionary = controller.get_command_result(int(command.sequence_id))
			if not bool(result.get("accepted", false)):
				continue
			if String(command.command_type()) == "train" and String(command.unit_type) == "fishing_boat":
				accepted_fishing_train += 1
			elif String(command.command_type()) == "gather" and _command_has_fishing_boat(world, command):
				accepted_fishing_gather += 1
		var current_boats: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == AI_TEAM and String(unit.get("kind", "")) == "fishing_boat")
		if accepted_fishing_gather > 0 and current_boats.any(func(unit): return String(unit.get("task", "")) == "idle" and String(unit.get("components", {}).get("order", {}).get("completion_reason", "")) in ["no_approach_slot", "no_path"]):
			var failed_boat: Dictionary = current_boats.filter(func(unit): return String(unit.get("task", "")) == "idle")[0]
			var failed_target = world.find_resource(int(failed_boat.get("components", {}).get("order", {}).get("target_entity_id", -1)))
			gather_failure = {
				"position": failed_boat.get("pos"),
				"component": world.navigation_grid.surface_component_id(Vector2i(Vector2(failed_boat.get("pos", Vector2.ZERO))), "water"),
				"order": failed_boat.get("components", {}).get("order", {}).duplicate(true),
				"resource": {"id": failed_target.get("id"), "kind": failed_target.get("kind"), "position": failed_target.get("pos"), "domain": failed_target.get("allowed_gatherer_domains")} if failed_target != null else null,
			}
			break
		var completed_cycle: bool = world.get_units().any(func(unit): return int(unit.get("team", 0)) == AI_TEAM and String(unit.get("kind", "")) == "fishing_boat" and int(unit.get("deposit_cycles", 0)) > 0)
		if completed_cycle:
			break

	var boats: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == AI_TEAM and String(unit.get("kind", "")) == "fishing_boat")
	var deposit_cycles: int = boats.reduce(func(total, boat): return int(total) + int(boat.get("deposit_cycles", 0)), 0)
	assert_true(accepted_fishing_train > 0, "AI trains a Fishing Boat after generated fish becomes known")
	assert_true(accepted_fishing_gather > 0, "AI assigns generated fish through the public gather command")
	assert_true(not boats.is_empty(), "Dock completes the AI-requested Fishing Boat")
	if not boats.is_empty():
		assert_equal(world.get_population(AI_TEAM), population_before_fishing_boat + int(boats[0].get("population_cost", 0)), "Fishing Boat consumes the same authoritative population and housing pool as land units")
	assert_true(int(fish.get("amount", 0)) < initial_fish_amount, "Fishing Boat harvests the generated deep-fish pool")
	assert_true(deposit_cycles > 0, "Fishing Boat completes a delivery to its generated-map Dock")
	assert_true(world.get_resource_amount(AI_TEAM, 0) > food_before, "Dock delivery credits gathered fish to the authoritative stockpile")
	assert_equal(String(dock.get("state", "")), "complete", "generated-map Dock remains the authoritative drop site")
	if failures.is_empty():
		print("E5-006C generated fishing cycle reached at tick %d: boats=%d deposits=%d food=%d->%d" % [controller.tick_index, boats.size(), deposit_cycles, food_before, world.get_resource_amount(AI_TEAM, 0)])
	else:
		print("E5-006C fishing failure tick=%d train=%d gather=%d fish=%s dock=%s gather_failure=%s boats=%s" % [controller.tick_index, accepted_fishing_train, accepted_fishing_gather, {"pos": fish.get("pos"), "amount": fish.get("amount"), "component": fish_component}, dock.get("pos"), gather_failure, boats.map(func(boat): return {"id": boat.get("id"), "pos": boat.get("pos"), "task": boat.get("task"), "stage": boat.get("gather_stage"), "reason": boat.get("diagnostic_reason"), "resource_id": boat.get("resource_id"), "slot": boat.get("resource_approach_slot"), "carried": boat.get("carried_amount"), "deposits": boat.get("deposit_cycles"), "target": boat.get("target"), "destination": boat.get("destination"), "path": boat.get("path"), "path_index": boat.get("path_index")})])
	finish()


func _command_has_fishing_boat(world, command) -> bool:
	for unit_id_value in command.unit_ids:
		var unit = world.find_unit(int(unit_id_value))
		if unit != null and String(unit.get("kind", "")) == "fishing_boat":
			return true
	return false


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated naval economy pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
