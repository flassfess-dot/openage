extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.normalize({
		"id": "mixed_domain_ai_smoke",
		"map": {"size": [22, 20], "seed": 99173, "generator": {
			"water_border": {"left": 6, "top": 0, "right": 0, "bottom": 0, "shore_width": 1, "land_terrain_id": 0},
			"naval_start": {"dock_footprint_radius_cells": 1, "dock_surface_terrain_ids": [1, 2, 4, 22]},
		}},
		"players": [
			{"team": 1, "controller": "ai", "civilization_id": 13, "start": [7.5, 10.5], "ai": {"economic_interval_ticks": 200, "military_interval_ticks": 5, "formation": "LINE"}},
			{"team": 2, "controller": "ai", "civilization_id": 13, "start": [9.5, 10.5], "ai": {"economic_interval_ticks": 200, "military_interval_ticks": 5, "formation": "WEDGE"}},
		],
		"entities": [
			{"category": "unit", "team": 1, "kind": "scout_ship", "position": [3.5, 7.5]},
			{"category": "unit", "team": 1, "kind": "transport", "position": [5.5, 10.5]},
			{"category": "unit", "team": 2, "kind": "clubman", "position": [9.5, 10.5]},
			{"category": "unit", "team": 2, "kind": "scout_ship", "position": [4.5, 7.5]},
			{"category": "unit", "team": 1, "kind": "clubman", "position": [6.5, 10.5]},
		],
		"victory_rules": [{"type": "conquest"}],
	})
	assert_true(bool(definition.get("valid", false)), "mixed-domain AI definition validates")
	var map_data := RandomMapGenerator.generate(definition)
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var bootstrap := MatchBootstrap.apply(world, definition, map_data)
	assert_true(bool(bootstrap.get("naval_start_guarantees_met", false)), "mixed-domain map retains one usable Dock zone per AI")
	var controller = GameController.new(world)
	var players := [AiPlayer.new(definition["players"][0]), AiPlayer.new(definition["players"][1])]
	var issued_types: Dictionary = {1: {}, 2: {}}
	var accepted_types: Dictionary = {1: {}, 2: {}}
	var domain_violations := 0
	var first_domain_violation: Dictionary = {}
	var first_observations: Dictionary = {}

	for step in range(4000):
		var next_tick: int = int(controller.tick_index) + 1
		var submitted: Array = []
		for ai in players:
			var knowledge := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team))
			var commands: Array = ai.collect_commands(knowledge, next_tick)
			if step == 0:
				first_observations[int(ai.team)] = {"units": knowledge.get("units", []).map(func(unit): return {"id": int(unit.get("id", -1)), "team": int(unit.get("team", 0)), "kind": String(unit.get("kind", "")), "domain": String(unit.get("movement_domain", ""))}), "commands": commands.map(func(command): return String(command.command_type()))}
			for command in commands:
				issued_types[int(ai.team)][String(command.command_type())] = true
				controller.enqueue_command(command, true, int(ai.team))
				submitted.append({"team": int(ai.team), "type": String(command.command_type()), "sequence_id": int(command.sequence_id)})
		controller.advance_frame(0.05, 1, 2)
		for submitted_value in submitted:
			var submitted_command: Dictionary = submitted_value
			var result: Dictionary = controller.get_command_result(int(submitted_command["sequence_id"]))
			if bool(result.get("accepted", false)):
				accepted_types[int(submitted_command["team"])][String(submitted_command["type"])] = true
		var current_violations := find_domain_violations(world)
		domain_violations += current_violations.size()
		if first_domain_violation.is_empty() and not current_violations.is_empty():
			first_domain_violation = current_violations[0]
		if world.is_battle_over():
			break

	assert_true(accepted_types[1].has("board"), "land-assault AI boards a nearby combatant through the accepted public command path (issued=%s, accepted=%s)" % [str(issued_types[1]), str(accepted_types[1])])
	assert_true(accepted_types[1].has("unload"), "land-assault AI completes an accepted public coastal unload phase (issued=%s, accepted=%s)" % [str(issued_types[1]), str(accepted_types[1])])
	assert_true(accepted_types[2].has("attack"), "naval AI explicitly attacks the visible enemy ship (first=%s, issued=%s, accepted=%s)" % [str(first_observations.get(2, {})), str(issued_types[2]), str(accepted_types[2])])
	assert_equal(domain_violations, 0, "long match never places a live unit on an invalid movement surface (first=%s)" % str(first_domain_violation))
	assert_true(world.is_battle_over(), "mixed-domain AI match reaches a deterministic terminal state")
	assert_equal(world.get_victory_result().get("winner_team"), 1, "asymmetric mixed-domain fixture has a stable winner")
	assert_equal(world.get_victory_result().get("reason"), "conquest", "mixed-domain match ends through the configured RoR conquest rule")

	if failures.is_empty():
		print("I12-019E mixed-domain AI smoke match passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func find_domain_violations(world) -> Array:
	var result: Array = []
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var domain := String(unit.get("movement_domain", "land"))
		if domain not in ["land", "water"]:
			continue
		var cell := Vector2i(floori(float(unit.get("pos", Vector2.ZERO).x)), floori(float(unit.get("pos", Vector2.ZERO).y)))
		if not world.navigation_grid.surface_accessible(cell, domain, int(unit.get("terrain_restriction", -1))):
			result.append({"id": int(unit.get("id", -1)), "kind": String(unit.get("kind", "")), "domain": domain, "restriction": int(unit.get("terrain_restriction", -1)), "pos": unit.get("pos"), "cell": cell, "terrain_id": world.navigation_grid.terrain_id(cell)})
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
