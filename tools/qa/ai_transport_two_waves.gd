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
const MAX_TICKS := 4000
const TransportPlanner := preload("res://scripts/ai_transport_planner.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")

var failures: Array[String] = []
var wave_ticks: Array = []
var probe_result: Dictionary = {}


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	# Use the legacy recipe that guarantees a Dock and staging zone per team.
	settings["landscape_version"] = 3
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
	assert_true(ClassDB.class_exists("RoRPathKernel") and world.navigation_grid.mask_kernel != null and world.navigation_grid.mask_kernel.has_method("surface_components"), "two-wave fixture uses the current native backend")
	if not failures.is_empty(): finish(); return
	# Keep boarding/transit/landing independent of neutral wildlife combat.
	for actor in world.get_units().duplicate():
		if int(actor["team"]) == 0: world.detach_unit_for_transport(int(actor["id"]))

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
	var passenger_radius := float(Footprint.mobile("clubman", world.unit_stats("clubman"))["movement_radius"])
	var first_position: Variant = nearest_clear_position(world, Vector2(ai_zone["land_staging"]), passenger_radius, "land")
	var second_position: Variant = nearest_clear_position(world, Vector2(ai_zone["land_staging"]), passenger_radius, "land", first_position)
	assert_true(first_position is Vector2 and second_position is Vector2, "the assault pair starts on distinct clear land footprints")
	if not first_position is Vector2 or not second_position is Vector2:
		finish()
		return
	var first: Dictionary = world.add_unit(AI_TEAM, "clubman", first_position, false)
	var second: Dictionary = world.add_unit(AI_TEAM, "clubman", second_position, false)
	transport["components"]["vision"]["range"] = 100.0
	world.update_fog_of_war()
	var passenger_ids := [int(first["id"]), int(second["id"])]
	passenger_ids.sort()
	var enemy_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(enemy_zone["land_staging"])), "land")
	var home_component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(ai_zone["land_staging"])), "land")
	assert_true(enemy_component >= 0 and home_component >= 0 and enemy_component != home_component, "transport fixture requires disconnected land components")

	# Isolate the competitive transport component, not strategic target choice.
	# This authored fixture grants a scouted map through its vision source;
	# normal catalog movement, capacity, boarding and unloading still apply.
	var ai = AiPlayer.new(definition["players"][1])
	var expeditions: Dictionary = {}
	ai.strategy.expeditions = expeditions
	var goal := {"type":"attack", "position":Vector2(enemy_zone["land_staging"]), "target_domain":"land",
		"competitive":"--legacy" not in OS.get_cmdline_user_args(), "adaptive_strategy":true, "expeditions":expeditions,
		"minimum_landing_group":2, "minimum_naval_escort":2, "landing_threats":[]}
	var waves: Array = [passenger_ids.duplicate()]
	var returning_observed := false
	var submitted_types: Array = []
	var last_planning_tick := -1
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var accepted_types: Dictionary = {}
	var rejected_reasons: Dictionary = {}
	var command_trace: Array = []
	var submitted_total := 0
	var unloaded := false
	var checkpoint_mode := "boarding" if "--checkpoint-boarding" in OS.get_cmdline_user_args() else "transit" if "--checkpoint-transit" in OS.get_cmdline_user_args() else ""
	var checkpoint_proof: Dictionary = {}

	while int(controller.tick_index) < MAX_TICKS:
		var next_tick := int(controller.tick_index) + 1
		var submitted: Array = []
		if next_tick % 10 == 1 and next_tick != last_planning_tick:
			last_planning_tick = next_tick
			var knowledge := SimulationSnapshot.with_queries(world, controller.tick_index, AI_TEAM, ai.presentation_options())
			for command in TransportPlanner.plan(knowledge, next_tick, AI_TEAM, goal):
				controller.enqueue_command(command, true, AI_TEAM)
				submitted.append(command)
			returning_observed = returning_observed or expeditions.values().any(func(entry): return String(entry.get("phase","")) == "returning_for_troops")
		controller.advance_frame(0.05, 1, 2, 1)
		submitted_total += submitted.size()
		for command in submitted:
			var result: Dictionary = controller.get_command_result(int(command.sequence_id))
			if command_trace.size() < 80:
				command_trace.append({"tick": next_tick, "type": command.command_type(), "units": command.unit_ids.duplicate(), "params": command.params.duplicate(true), "result": result.duplicate(true)})
			if bool(result.get("accepted", false)):
				accepted_types[String(command.command_type())] = int(accepted_types.get(String(command.command_type()), 0)) + 1
			else:
				var reason := String(result.get("reason", "unknown"))
				rejected_reasons[reason] = int(rejected_reasons.get(reason, 0)) + 1
		var cargo_ids: Array = transport.get("components", {}).get("cargo", {}).get("passenger_ids", [])
		if not checkpoint_mode.is_empty() and checkpoint_proof.is_empty():
			var approaching := passenger_ids.any(func(id):
				var unit = world.find_unit(int(id))
				return unit != null and String(unit.get("task", "")) == "board"
			)
			var ready := approaching if checkpoint_mode == "boarding" else cargo_ids.size() == 2 and String(transport.get("task", "")) == "move"
			if ready and int(accepted_types.get("board", 0)) > 0:
				var restored := save_transport_checkpoint(world, controller, ai, catalog, definition, built["map_data"], checkpoint_mode, approaching, cargo_ids.size())
				if not failures.is_empty(): finish(); return
				world = restored["world"]
				controller = restored["controller"]
				ai = restored["ai"]
				transport = world.find_unit(int(transport["id"]))
				expeditions = ai.strategy.expeditions
				goal["expeditions"] = expeditions
				checkpoint_proof = restored["proof"]
				cargo_ids = transport.get("components", {}).get("cargo", {}).get("passenger_ids", [])
		unloaded = cargo_ids.is_empty() and passenger_ids.all(func(unit_id):
			var passenger = world.find_unit(unit_id)
			return passenger != null and world.navigation_grid.surface_component_id(Vector2i(Vector2(passenger.get("pos", Vector2.ZERO))), "land") == enemy_component
		)
		if unloaded:
			wave_ticks.append(int(controller.tick_index))
			if waves.size() == 2: break
			var third: Dictionary = world.add_unit(AI_TEAM, "clubman", first_position, false)
			var fourth: Dictionary = world.add_unit(AI_TEAM, "clubman", second_position, false)
			passenger_ids = [int(third["id"]), int(fourth["id"])]
			passenger_ids.sort()
			waves.append(passenger_ids.duplicate())
			unloaded = false


	assert_true(wave_ticks.size() == 2 and wave_ticks[1] > wave_ticks[0], "the same boat completes two sequential landing waves")
	assert_true(int(accepted_types.get("board", 0)) >= 2 and int(accepted_types.get("unload", 0)) >= 2, "each wave uses accepted public Board and Unload commands")
	assert_true(returning_observed, "empty transport returns for the new home-island reinforcements")
	var all_passengers: Array = []
	for wave in waves: all_passengers.append_array(wave)
	assert_true(all_passengers.size() == 4 and all_passengers.all(func(id):
		var unit = world.find_unit(int(id))
		return unit != null and world.navigation_grid.surface_component_id(Vector2i(Vector2(unit["pos"])), "land") == enemy_component
	), "all four surviving passengers occupy the enemy island after the second wave")
	probe_result = {"tick":controller.tick_index,"wave_landing_ticks":wave_ticks,"returning_for_troops_observed":returning_observed,"accepted_types":accepted_types,"rejected_reasons":rejected_reasons,"trace":command_trace,"waves":waves,"cargo":transport.get("components",{}).get("cargo",{}).get("passenger_ids",[]),"scope":"Competitive transport component, fully scouted authored generated-islands fixture, ordinary catalog physics/capacity/public commands. Not full strategic target choice, strength, APM or modern-map generalization."}
	probe_result["competitive"] = goal["competitive"]
	probe_result["runtime"] = {"release":not OS.has_feature("editor"),"native":true}
	probe_result["world_hash"] = Replay.new().world_state_hash(world, controller.tick_index, controller)
	probe_result["reboarded_arrived_troops"] = command_trace.filter(func(row): return String(row["type"]) == "board" and int(row["tick"]) > int(wave_ticks[0]) and row["units"].any(func(id): return id in waves[0])).size() if not wave_ticks.is_empty() else 0
	assert_true(int(accepted_types.get("board", 0)) > 0, "generated-islands AI boards its land assault group through BoardCommand")
	assert_true(int(accepted_types.get("move", 0)) > 0, "loaded Transport receives a public water movement order")
	assert_true(int(accepted_types.get("unload", 0)) > 0, "generated-islands AI unloads through the public command path")
	assert_true(unloaded, "both passengers land on the enemy island component")
	assert_equal(transport.get("components", {}).get("cargo", {}).get("passenger_ids", []), [], "successful landing clears the authoritative cargo manifest")
	if not checkpoint_mode.is_empty():
		assert_true(not checkpoint_proof.is_empty(), "requested transport checkpoint point actually occurs")
	probe_result["transport_checkpoint"] = checkpoint_proof
	probe_result["canonical_ai_state"] = Replay.new().encode_exact_variant(ai.canonical_state())
	probe_result["public_command_count"] = submitted_total
	probe_result["command_trace_complete"] = submitted_total > 0 and command_trace.size() == submitted_total
	if failures.is_empty():
		print("E5-006C generated transport landing reached at tick %d: accepted=%s" % [controller.tick_index, accepted_types])
	else:
		print("E5-006C transport failure tick=%d accepted=%s rejected=%s zones=%s trace=%s transport=%s passengers=%s" % [controller.tick_index, accepted_types, rejected_reasons, {"enemy": enemy_zone, "home": ai_zone}, command_trace, {"pos": transport.get("pos"), "task": transport.get("task"), "destination": transport.get("destination"), "path_status": transport.get("path_status"), "reason": transport.get("diagnostic_reason"), "path": transport.get("path"), "path_index": transport.get("path_index"), "cargo": transport.get("components", {}).get("cargo", {}).get("passenger_ids", [])}, passenger_ids.map(func(unit_id):
			var passenger = world.find_unit(int(unit_id))
			return {"id": unit_id, "pos": passenger.get("pos") if passenger != null else null, "task": passenger.get("task") if passenger != null else "missing"}
		)])
	finish()


func save_transport_checkpoint(world, controller, ai, catalog, definition: Dictionary, map_data: Dictionary, mode: String, approaching: bool, cargo_count: int) -> Dictionary:
	var codec := Replay.new()
	var original_world_hash: String = codec.world_state_hash(world, controller.tick_index, controller)
	var original_ai: Dictionary = ai.canonical_state()
	var save_path := String(OS.get_cmdline_user_args()[0]) + ".checkpoint.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	assert_true(file != null, "transport checkpoint file opens for writing")
	if file == null: return {}
	file.store_string(JSON.stringify({"checkpoint":Checkpoint.pack(Checkpoint.capture(world, controller, definition, map_data)), "ai":codec.encode_exact_variant(original_ai)}))
	file.close()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_true(saved is Dictionary, "transport checkpoint round-trips through a real file")
	if not saved is Dictionary: return {}
	var restored_world = SimulationWorld.new(world.map_size)
	restored_world.set_gamespec(catalog.gamespec_data)
	restored_world.set_terrain_catalog(catalog.terrain_catalog_data)
	restored_world.set_object_catalog(catalog.object_catalog_data)
	restored_world.set_graphics_catalog(catalog.graphics_catalog_data)
	restored_world.set_runtime_catalog(catalog.runtime_catalog_data)
	restored_world.configure_map_data(map_data)
	var restored_controller = GameController.new(restored_world)
	assert_true(Checkpoint.restore(Checkpoint.unpack(saved["checkpoint"]), restored_world, restored_controller), "transport world restores from the versioned packed checkpoint")
	var restored_ai = AiPlayer.new(definition["players"][1])
	assert_true(restored_ai.restore_state(codec.decode_variant(saved["ai"])), "transport owner restores its canonical expedition state")
	var world_exact := codec.world_state_hash(restored_world, restored_controller.tick_index, restored_controller) == original_world_hash
	var ai_exact: bool = restored_ai.canonical_state() == original_ai
	assert_true(world_exact, "transport checkpoint immediately restores exact world state")
	assert_true(ai_exact, "transport checkpoint immediately restores exact typed AI state")
	return {"world":restored_world, "controller":restored_controller, "ai":restored_ai,
		"proof":{"mode":mode, "tick":controller.tick_index, "approaching_passenger":approaching, "cargo_count":cargo_count,
		"world_exact":world_exact, "canonical_ai_exact":ai_exact, "file_sha256":FileAccess.get_sha256(save_path),
		"scope":"Transport component expedition state plus real world checkpoint; not an independently running full strategic AI."}}


func nearest_clear_position(world, origin: Vector2, radius: float, domain: String, avoid: Variant = null) -> Variant:
	var origin_component: int = world.navigation_grid.surface_component_id(Vector2i(origin), domain)
	var candidates: Array[Vector2] = []
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			var cell := Vector2i(x, y)
			if world.navigation_grid.surface_component_id(cell, domain) != origin_component:
				continue
			var candidate := Vector2(cell) + Vector2(0.5, 0.5)
			if avoid is Vector2 and candidate.distance_squared_to(avoid) < pow(radius * 2.0 + 0.06, 2): continue
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
	if not OS.get_cmdline_user_args().is_empty():
		probe_result["passed"] = failures.is_empty()
		probe_result["failures"] = failures
		var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
		if file == null: push_error("Two-wave output is not writable"); quit(1); return
		file.store_string(JSON.stringify(probe_result,"\t")); file.close()
	if failures.is_empty():
		print("E5-006C generated transport landing pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
