extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const Footprint := preload("res://scripts/footprint.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

const MAX_TICKS := 800

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["map_type_id"] = "islands"
	settings["seed"] = 41721
	settings["resource_preset_id"] = "very_high"
	settings["ai_difficulty_id"] = "hard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated naval combat fixture builds: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return

	var catalog = ResourceCatalog.new()
	catalog.load()
	var definition: Dictionary = built["definition"].duplicate(true)
	definition["entities"] = []
	var world = SimulationWorld.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, built["map_data"])

	var ship_radius := float(Footprint.mobile("scout_ship", world.unit_stats("scout_ship")).get("movement_radius", 0.75))
	var positions := open_water_cluster(world, ship_radius)
	assert_equal(positions.size(), 3, "generated islands contain one open-water combat cluster")
	if positions.size() < 3:
		finish()
		return
	var first: Dictionary = world.add_unit(1, "scout_ship", positions[0], false)
	var second: Dictionary = world.add_unit(1, "scout_ship", positions[1], false)
	var defender: Dictionary = world.add_unit(2, "scout_ship", positions[2], false)
	world.update_fog_of_war()

	var players := [AiPlayer.new(definition["players"][0]), AiPlayer.new(definition["players"][1])]
	for ai in players:
		ai.enabled = true
		ai.economic_interval = 100000
		ai.last_economic_tick = 0
		ai.military_interval = 1
		ai.initial_attack_delay = 0
		ai.attack_separation = 1
		ai.minimum_attack_group_size = 1
		ai.maximum_attack_group_size = 8
	var controller = GameController.new(world)
	controller.set_speed_multiplier(3.0)
	var accepted_attacks := {1: 0, 2: 0}
	var rejected_reasons: Dictionary = {}

	while int(controller.tick_index) < MAX_TICKS and not world.is_battle_over():
		var next_tick := int(controller.tick_index) + 1
		var submitted: Array = []
		for ai in players:
			if not ai.needs_decision(next_tick):
				continue
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
			for command in ai.collect_commands(knowledge, next_tick):
				controller.enqueue_command(command, true, int(ai.team))
				submitted.append({"team": int(ai.team), "command": command})
		controller.advance_frame(0.25, 1, 2)
		for entry_value in submitted:
			var entry: Dictionary = entry_value
			var command = entry["command"]
			var result: Dictionary = controller.get_command_result(int(command.sequence_id))
			if bool(result.get("accepted", false)) and String(command.command_type()) == "attack":
				accepted_attacks[int(entry["team"])] = int(accepted_attacks.get(int(entry["team"]), 0)) + 1
			elif not bool(result.get("accepted", false)):
				var reason := String(result.get("reason", "unknown"))
				rejected_reasons[reason] = int(rejected_reasons.get(reason, 0)) + 1

	var result: Dictionary = world.get_victory_result()
	var team_two_alive := world.get_units().any(func(unit): return int(unit.get("team", 0)) == 2 and float(unit.get("hp", 0.0)) > 0.0)
	var naval_hits: Array = world.get_resolved_projectiles().filter(func(projectile): return int(projectile.get("projectile_unit_id", -1)) == 9 and not projectile.get("hit_target_ids", []).is_empty())
	assert_true(int(accepted_attacks.get(1, 0)) > 0, "first AI attacks through the public command queue")
	assert_true(int(accepted_attacks.get(2, 0)) > 0, "second AI retaliates through the public command queue")
	assert_true(not naval_hits.is_empty(), "generated naval battle resolves source projectile 9 impacts")
	assert_true(not team_two_alive, "outnumbered naval side is eliminated by simulation combat")
	assert_true(world.is_battle_over(), "ship-only generated match reaches an authoritative terminal state")
	assert_equal(result.get("winner_team"), 1, "deterministic two-versus-one naval fixture has a stable winner")
	assert_equal(result.get("reason"), "conquest", "naval elimination closes through the configured conquest rule")
	assert_true(float(first.get("hp", 0.0)) > 0.0 or float(second.get("hp", 0.0)) > 0.0, "winning side retains at least one live combat ship")
	if failures.is_empty():
		print("E5-006C generated naval combat victory reached at tick %d: attacks=%s hits=%d" % [controller.tick_index, accepted_attacks, naval_hits.size()])
	else:
		print("E5-006C naval combat failure tick=%d attacks=%s rejected=%s result=%s ships=%s" % [controller.tick_index, accepted_attacks, rejected_reasons, result, world.get_units().map(func(unit): return {"id": unit.get("id"), "team": unit.get("team"), "hp": unit.get("hp"), "task": unit.get("task"), "pos": unit.get("pos"), "reason": unit.get("diagnostic_reason")})])
	finish()


func open_water_cluster(world, radius: float) -> Array[Vector2]:
	var offsets := [Vector2(-2.0, 0.0), Vector2(2.0, 0.0), Vector2(0.0, 2.0)]
	var center := Vector2(world.map_size) * 0.5
	var candidates: Array[Vector2] = []
	for y in range(3, world.map_size.y - 3):
		for x in range(3, world.map_size.x - 3):
			var origin := Vector2(x + 0.5, y + 0.5)
			if offsets.all(func(offset): return world.navigation_grid.is_position_walkable_for(origin + offset, radius, "water")):
				candidates.append(origin)
	candidates.sort_custom(func(left: Vector2, right: Vector2):
		var left_distance := center.distance_squared_to(left)
		var right_distance := center.distance_squared_to(right)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.y < right.y or (is_equal_approx(left.y, right.y) and left.x < right.x)))
	)
	if candidates.is_empty():
		return []
	var result: Array[Vector2] = []
	for offset in offsets:
		result.append(candidates[0] + Vector2(offset))
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("E5-006C generated naval combat/victory pipeline passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
