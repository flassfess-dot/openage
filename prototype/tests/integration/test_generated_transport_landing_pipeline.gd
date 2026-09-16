extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const Footprint := preload("res://scripts/footprint.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const AI_TEAM := 2
const ENEMY_TEAM := 1
const MAX_TICKS := 1000

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "islands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated transport fixture builds: %s" % [built.get("errors", [])])
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
	MatchBootstrap.apply(world, definition, built["map_data"])

	var zones: Array = built["map_data"].get("naval_start_zones", [])
	assert_equal(zones.size(), 2, "two-player islands fixture exposes two naval start zones")
	if zones.size() < 2:
		finish()
		return
	var enemy_zone: Dictionary = zones[0]
	var ai_zone: Dictionary = zones[1]
	var transport_radius := float(Footprint.mobile("transport", world.unit_stats("transport")).get("movement_radius", 0.75))
	var transport_position: Variant = nearest_clear_position(world, Vector2(ai_zone["water_staging"]), transport_radius, "water")
	assert_true(transport_position is Vector2, "generated naval start has clearance for a Transport footprint")
	if not transport_position is Vector2:
		finish()
		return
	var transport: Dictionary = world.add_unit(AI_TEAM, "transport", transport_position, false)
	var first: Dictionary = world.add_unit(AI_TEAM, "clubman", Vector2(ai_zone["land_staging"]), false)
	var second: Dictionary = world.add_unit(AI_TEAM, "clubman", Vector2(ai_zone["land_staging"]) + Vector2(0.0, 0.35), false)
	transport["components"]["vision"]["range"] = 100.0
	world.update_fog_of_war()
	var passenger_ids := [int(first["id"]), int(second["id"])]
	passenger_ids.sort()
	var enemy_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(enemy_zone["land_staging"])), "land")
	var home_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(ai_zone["land_staging"])), "land")
	assert_true(enemy_component >= 0 and home_component >= 0 and enemy_component != home_component, "transport fixture requires disconnected land components")

	var ai = AiPlayer.new(definition["players"][1])
	ai.economic_interval = 100000
	ai.last_economic_tick = 0
	ai.military_interval = 1
	ai.initial_attack_delay = 0
	ai.attack_separation = 1
	ai.minimum_attack_group_size = 2
	ai.maximum_attack_group_size = 2
	var controller = GameController.new(world)
	controller.set_speed_multiplier(3.0)
	var accepted_types: Dictionary = {}
	var rejected_reasons: Dictionary = {}
	var command_trace: Array = []
	var unloaded := false

	while int(controller.tick_index) < MAX_TICKS:
		var next_tick := int(controller.tick_index) + 1
		var submitted: Array = []
		if ai.needs_decision(next_tick):
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, AI_TEAM, ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, AI_TEAM)
				submitted.append(command)
		controller.advance_frame(0.25, 1, 2)
		for command in submitted:
			var result: Dictionary = controller.get_command_result(int(command.sequence_id))
			if command_trace.size() < 24 and String(command.command_type()) in ["board", "move", "unload"]:
				command_trace.append({"tick": next_tick, "type": command.command_type(), "units": command.unit_ids.duplicate(), "params": command.params.duplicate(true), "result": result.duplicate(true)})
			if bool(result.get("accepted", false)):
				accepted_types[String(command.command_type())] = int(accepted_types.get(String(command.command_type()), 0)) + 1
			else:
				var reason := String(result.get("reason", "unknown"))
				rejected_reasons[reason] = int(rejected_reasons.get(reason, 0)) + 1
		var cargo_ids: Array = transport.get("components", {}).get("cargo", {}).get("passenger_ids", [])
		unloaded = cargo_ids.is_empty() and passenger_ids.all(func(unit_id):
			var passenger = world.find_unit(unit_id)
			return passenger != null and world.navigation_grid.surface_component_id(Vector2i(Vector2(passenger.get("pos", Vector2.ZERO))), "land") == enemy_component
		)
		if unloaded:
			break

	assert_true(int(accepted_types.get("board", 0)) > 0, "generated-islands AI boards its land assault group through BoardCommand")
	assert_true(int(accepted_types.get("move", 0)) > 0, "loaded Transport receives a public water movement order")
	assert_true(int(accepted_types.get("unload", 0)) > 0, "generated-islands AI unloads through the public command path")
	assert_true(unloaded, "both passengers land on the enemy island component")
	assert_equal(transport.get("components", {}).get("cargo", {}).get("passenger_ids", []), [], "successful landing clears the authoritative cargo manifest")
	if failures.is_empty():
		print("E5-006C generated transport landing reached at tick %d: accepted=%s" % [controller.tick_index, accepted_types])
	else:
		print("E5-006C transport failure tick=%d accepted=%s rejected=%s zones=%s trace=%s transport=%s passengers=%s" % [controller.tick_index, accepted_types, rejected_reasons, {"enemy": enemy_zone, "home": ai_zone}, command_trace, {"pos": transport.get("pos"), "task": transport.get("task"), "destination": transport.get("destination"), "path_status": transport.get("path_status"), "reason": transport.get("diagnostic_reason"), "path": transport.get("path"), "path_index": transport.get("path_index"), "cargo": transport.get("components", {}).get("cargo", {}).get("passenger_ids", [])}, passenger_ids.map(func(unit_id):
			var passenger = world.find_unit(int(unit_id))
			return {"id": unit_id, "pos": passenger.get("pos") if passenger != null else null, "task": passenger.get("task") if passenger != null else "missing"}
		)])
	finish()


func nearest_clear_position(world, origin: Vector2, radius: float, domain: String) -> Variant:
	var origin_component: int = world.navigation_grid.surface_component_id(Vector2i(origin), domain)
	var candidates: Array[Vector2] = []
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			var cell := Vector2i(x, y)
			if world.navigation_grid.surface_component_id(cell, domain) != origin_component:
				continue
			var candidate := Vector2(cell) + Vector2(0.5, 0.5)
			if world.navigation_grid.is_position_walkable_for(candidate, radius, domain):
				candidates.append(candidate)
	candidates.sort_custom(func(left: Vector2, right: Vector2):
		var left_distance := origin.distance_squared_to(left)
		var right_distance := origin.distance_squared_to(right)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.x < right.x or (is_equal_approx(left.x, right.x) and left.y < right.y)))
	)
	return candidates[0] if not candidates.is_empty() else null


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated transport landing pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
