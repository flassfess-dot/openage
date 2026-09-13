extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(2, 13)
	for resource_type in range(4):
		world.set_resource_amount(2, resource_type, 1000)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(16.5, 16.5), false)
	world.update_fog_of_war()

	var contract := {
		"schema_version": 1,
		"status": "normalized",
		"runtime_support": {"economy_enabled": true, "build_order_enabled": true, "military_enabled": false},
		"strategic_numbers": [],
		"build_order": [
			{"type": "building", "source_opcode": "B", "source_id": 12, "source_name": "Barracks1", "target_count": 1, "producer_source_unit_id": -1, "source_parameters": [], "runtime_alias": "barracks"},
		],
		"target_markers": [],
	}
	var ai = AiPlayer.new({
		"team": 2,
		"source_ai": contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 20},
	})
	var options: Dictionary = ai.presentation_options()
	var snapshot: Dictionary = SimulationSnapshot.presentation(world, 0, 2, options)
	assert_true(not snapshot.get("build_sites", {}).get("barracks", []).is_empty(), "compact source-AI snapshot exposes a legal Barracks site")
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.size(), 1, "source AI emits one non-conflicting build-list command")
	if not commands.is_empty():
		assert_equal(commands[0].command_type(), "build", "source B entry crosses the public command boundary")
		assert_equal(commands[0].unit_ids, [int(worker.get("id", -1))], "source builder is selected from the legal observer snapshot")
		var controller = GameController.new(world)
		controller.enqueue_command(commands[0], true, 2)
		controller.advance_frame(0.05, 1, 2)
		var result: Dictionary = controller.get_command_result(commands[0].sequence_id)
		assert_true(bool(result.get("accepted", false)), "authoritative simulation accepts the source-AI BuildCommand (result=%s target=%s)" % [str(result), str(commands[0].target)])
		var barracks: Array = world.get_buildings().filter(func(building): return int(building.get("team", 0)) == 2 and String(building.get("kind", "")) == "barracks")
		assert_equal(barracks.size(), 1, "source-AI BuildCommand creates exactly one Barracks foundation")
		if not barracks.is_empty():
			assert_equal(String(barracks[0].get("state", "")), "foundation", "source AI uses the normal construction lifecycle")
	verify_city_wall_plan_pipeline(catalog)

	if failures.is_empty():
		print("I12-020L source campaign AI build pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_city_wall_plan_pipeline(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(48, 48))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(2, 13)
	for resource_type in range(4):
		world.set_resource_amount(2, resource_type, 1000)
	world.grant_technology(2, 101)
	world.grant_technology(2, 11)
	world.add_building(100, "town_center", Vector2(24.5, 24.5), 2)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(24.5, 24.5), false)
	world.update_fog_of_war()
	var contract := {
		"schema_version": 1,
		"status": "integrated",
		"runtime_support": {"economy_enabled": true, "build_order_enabled": true, "military_enabled": false},
		"strategic_numbers": [
			{"source_id": 73, "value": 3, "runtime_semantics": "implemented"},
			{"source_id": 74, "value": 5, "runtime_semantics": "implemented"},
			{"source_id": 84, "value": 2, "runtime_semantics": "implemented"},
			{"source_id": 85, "value": 2, "runtime_semantics": "implemented"},
		],
		"build_order": [
			{"type": "building", "source_opcode": "B", "source_id": 72, "source_name": "Wall", "target_count": 1, "producer_source_unit_id": -1, "source_parameters": [], "runtime_alias": "wall"},
		],
		"target_markers": [],
	}
	var ai = AiPlayer.new({
		"team": 2,
		"source_ai": contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 20},
	})
	var first_snapshot: Dictionary = SimulationSnapshot.presentation(world, 0, 2, ai.presentation_options())
	assert_true(ai.collect_commands(first_snapshot, 1).is_empty(), "first decision initializes the persistent wall geometry before requesting distant planned sites")
	var options: Dictionary = ai.presentation_options()
	assert_true("wall" in options.get("strict_preferred_build_site_kinds", []), "initialized AI requests strict planned wall cells")
	var planned_snapshot: Dictionary = SimulationSnapshot.presentation(world, 0, 2, options)
	assert_true(not planned_snapshot.get("build_sites", {}).get("wall", []).is_empty(), "authoritative snapshot validates at least one visible planned wall cell")
	ai.last_economic_tick = -1
	var commands: Array = ai.collect_commands(planned_snapshot, 1)
	assert_equal(commands.size(), 1, "second decision emits one planned wall segment")
	if commands.is_empty():
		return
	var target_cell := Vector2i(floori(commands[0].target.x), floori(commands[0].target.y))
	assert_true(target_cell not in ai.source_city_plan.gate_cells, "wall command never occupies a planned passage")
	var controller = GameController.new(world)
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	var result: Dictionary = controller.get_command_result(commands[0].sequence_id)
	assert_true(bool(result.get("accepted", false)), "normal authoritative placement accepts the planned wall command (result=%s target=%s)" % [str(result), str(commands[0].target)])
	var walls: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "wall" and int(building.get("team", 0)) == 2)
	assert_equal(walls.size(), 1, "city plan creates one ordinary wall foundation")
	assert_equal(int(worker.get("id", -1)), int(commands[0].unit_ids[0]), "planned wall keeps the ordinary worker ownership contract")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
