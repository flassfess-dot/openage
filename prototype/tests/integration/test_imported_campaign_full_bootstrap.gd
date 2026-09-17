extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const Footprint := preload("res://scripts/footprint.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var definition_loaded := Time.get_ticks_msec()
	var catalog := ResourceCatalog.new()
	catalog.load()
	var catalog_loaded := Time.get_ticks_msec()
	var map_data := MapGenerator.generate(definition)
	var map_generated := Time.get_ticks_msec()
	var world := SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var world_configured := Time.get_ticks_msec()
	MatchBootstrap.apply(world, definition, map_data)
	var elapsed := Time.get_ticks_msec() - started
	assert_equal(world.get_units().size(), 262, "full campaign creates every mapped unit including source predators")
	assert_equal(world.get_buildings().size(), 33, "full campaign creates every currently mapped building")
	assert_equal(world.get_resources().size(), 9251, "full campaign creates every mapped resource and static forest node")
	assert_true(not world.is_bulk_loading(), "full campaign closes the bulk-load transaction")
	assert_equal(world.get_units().size() + world.get_buildings().size() + world.get_resources().size(), 9546, "full campaign ordinary bootstrap consumes the complete mapped vertical including wildlife and static forest nodes")
	assert_equal(world.get_units().filter(func(unit): return String(unit.get("kind", "")) in ["lion", "alligator"]).size(), 40, "all source predators are mobile wildlife units")
	assert_equal(world.get_resources().filter(func(resource): return bool(resource.get("static_field_node", false))).size(), 8883, "forest nodes remain static resource state, not autonomous units")
	assert_equal(world.get_static_obstructions().size(), 30, "all source cliffs reach the navigation-owned static obstruction batch")
	assert_equal(world.get_current_age(1), 102, "Roman player starts in the source Bronze Age")
	assert_equal(world.get_current_age(2), 101, "first source opponent starts in the Tool Age")
	assert_equal(world.get_current_age(5), 103, "source Iron Age start reaches the shared technology system")
	var first_cliff: Dictionary = world.get_static_obstructions()[0]
	var first_cliff_cell: Vector2i = first_cliff.get("occupied_cells", [])[0]
	assert_true(not world.navigation_grid.is_walkable(first_cliff_cell), "source cliff footprint blocks land navigation")
	assert_true(world.navigation_grid.occupants(first_cliff_cell).any(func(item): return String(item.get("category", "")) == "static_obstruction"), "navigation grid retains the cliff owner category")
	print("I12-020D full campaign phases: definition=%d ms, catalog=%d ms, map=%d ms, world=%d ms, bootstrap=%d ms, total=%d ms" % [definition_loaded - started, catalog_loaded - definition_loaded, map_generated - catalog_loaded, world_configured - map_generated, Time.get_ticks_msec() - world_configured, elapsed])
	var player_snapshot_started := Time.get_ticks_msec()
	SimulationSnapshot.presentation(world, 0, 1, {"include_navigation": false, "include_build_sites": false})
	print("I12-020D player presentation snapshot: %d ms" % (Time.get_ticks_msec() - player_snapshot_started))
	verify_imported_source_victory(world, definition)
	MatchBootstrap.apply(world, definition, map_data)
	verify_imported_source_defeat(world)
	_finish("I12-020E full campaign bootstrap and outcome vertical tests passed")


func verify_imported_source_victory(world, definition: Dictionary) -> void:
	world.grant_technology(1, 16)
	world.grant_technology(1, 12)
	world.set_resource_amount(1, 2, 5000)
	var workers: Array = world.get_units().filter(func(unit):
		return int(unit.get("team", 0)) == 1 and float(unit.get("hp", 0.0)) > 0.0 and world.entity_is_worker(unit)
	)
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	assert_true(not workers.is_empty(), "imported Roman player has a worker for the source objective vertical")
	if workers.is_empty():
		return
	var worker: Dictionary = workers[0]
	var controller := GameController.new(world)
	var scenario: Dictionary = definition.get("scenario_definition", {})
	var conditions: Array = scenario.get("participants", [])[0].get("groups", [])[0].get("conditions", [])
	var accepted_commands := 0
	world.begin_event_capture()
	world.check_battle_state(1, 2, 0.05)
	for index in range(conditions.size()):
		var condition: Dictionary = conditions[index]
		var site: Variant = find_source_objective_site(world, worker, condition)
		assert_true(site is Vector2, "source tower area %d contains an authoritative build site" % (index + 1))
		if not site is Vector2:
			continue
		var previous_ids: Dictionary = {}
		for building in world.get_buildings():
			previous_ids[int(building.get("id", -1))] = true
		var command = Commands.BuildCommand.new(controller.tick_index, [int(worker.get("id", -1))], "tower", site)
		controller.enqueue_command(command, true, 1)
		controller.process_commands()
		var result: Dictionary = controller.get_command_result(command.sequence_id)
		assert_true(bool(result.get("accepted", false)), "source tower area %d accepts the ordinary BuildCommand (%s)" % [index + 1, String(result.get("reason", ""))])
		if not bool(result.get("accepted", false)):
			continue
		accepted_commands += 1
		var candidates: Array = world.get_buildings().filter(func(building): return not previous_ids.has(int(building.get("id", -1))))
		assert_equal(candidates.size(), 1, "one accepted source objective command creates one foundation")
		if candidates.is_empty():
			continue
		var tower: Dictionary = candidates[0]
		assert_equal(tower.get("source_unit_id"), 199, "researched source replacement creates a Sentry Tower in objective area %d" % (index + 1))
		world.complete_foundation(tower)
		world.check_battle_state(1, 2, 0.05)
		if index + 1 < conditions.size():
			assert_true(not world.is_battle_over(), "imported mission remains active before the twelfth source area")
	world.end_event_capture()
	var events: Array = world.drain_domain_events()
	assert_equal(accepted_commands, 12, "all twelve source areas are completed through public build commands")
	assert_true(world.is_battle_over(), "twelfth completed source tower ends the imported mission")
	assert_equal(world.get_victory_result().get("winner_team"), 1, "imported objective vertical awards victory to Rome")
	assert_equal(world.get_victory_result().get("reason"), "scenario", "imported objective victory retains its source scenario reason")
	assert_equal(events.filter(func(event): return String(event.get("type", "")) == "scenario_condition_changed" and bool(event.get("payload", {}).get("achieved", false))).size(), 12, "full imported vertical emits all twelve source condition events")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1, {"include_navigation": false, "include_build_sites": false})
	assert_equal(presentation.get("scenario", {}).get("result", {}).get("winner_team"), 1, "victory reaches the read-only scenario presentation snapshot")


func verify_imported_source_defeat(world) -> void:
	var controller := GameController.new(world)
	var resign = Commands.ResignCommand.new(1)
	controller.enqueue_command(resign, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(resign.sequence_id).get("accepted", false)), "ordinary resign command crosses the imported mission command boundary")
	assert_true(world.is_battle_over(), "Roman resignation completes the imported source defeat vertical")
	assert_equal(world.get_victory_result().get("winner_team"), 2, "first deterministic source opponent wins after Roman resignation")
	assert_equal(world.get_victory_result().get("reason"), "scenario", "imported defeat is resolved by source DestroyPlayer semantics")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1, {"include_navigation": false, "include_build_sites": false})
	assert_true(bool(presentation.get("match_result", {}).get("over", false)), "defeat reaches the read-only match presentation snapshot")
	assert_true(int(presentation.get("match_result", {}).get("winner_team", 1)) != 1, "local Roman observer receives a losing result")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "player_resigned" and int(event.get("payload", {}).get("team", 0)) == 1), "imported defeat retains the typed resignation event")


func find_source_objective_site(world, worker: Dictionary, condition: Dictionary) -> Variant:
	var area: Array = condition.get("area", [])
	if area.size() != 4:
		return null
	var minimum_x := ceili(float(area[0]) * 2.0)
	var minimum_y := ceili(float(area[1]) * 2.0)
	var maximum_x := floori(float(area[2]) * 2.0)
	var maximum_y := floori(float(area[3]) * 2.0)
	for half_y in range(minimum_y, maximum_y + 1):
		for half_x in range(minimum_x, maximum_x + 1):
			var position := Vector2(half_x * 0.5, half_y * 0.5)
			if not world.map_supports_foundation("tower", position):
				continue
			var footprint := Footprint.building(world.unit_stats("tower"), position)
			var preview := {"pos": position, "footprint": footprint}
			for approach_value in world.building_perimeter_candidates(worker, preview):
				var approach := Vector2(approach_value)
				if not world.navigation_grid.is_position_walkable_for(approach, float(worker.get("footprint_radius", 0.3)), String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1))):
					continue
				worker["pos"] = approach
				worker["previous_pos"] = approach
				world.update_fog_of_war()
				if world.can_place_foundation(1, "tower", position):
					return position
	return null


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
