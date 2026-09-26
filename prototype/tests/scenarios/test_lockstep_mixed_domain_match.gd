extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const LockstepSession := preload("res://scripts/lockstep_session.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const MATCH_TICKS := 2000

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.normalize({
		"id": "mixed_domain_lockstep", "networked": true,
		"map": {"size": [22, 20], "seed": 99173, "generator": {
			"water_border": {"left": 6, "top": 0, "right": 0, "bottom": 0, "shore_width": 1, "land_terrain_id": 0},
			"naval_start": {"dock_footprint_radius_cells": 1, "dock_surface_terrain_ids": [1, 2, 4, 22]},
		}},
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "start": [7.5, 10.5]},
			{"team": 2, "controller": "remote", "civilization_id": 14, "start": [9.5, 10.5]},
		],
		"entities": [
			{"category": "unit", "team": 1, "kind": "scout_ship", "position": [3.5, 7.5]},
			{"category": "unit", "team": 2, "kind": "scout_ship", "position": [4.5, 7.5]},
			{"category": "unit", "team": 1, "kind": "clubman", "position": [7.5, 10.5]},
			{"category": "unit", "team": 2, "kind": "clubman", "position": [9.5, 10.5]},
		],
		"victory_rules": [{"type": "conquest"}],
	})
	assert_true(bool(definition.get("valid", false)), "networked mixed-domain fixture validates")
	if not bool(definition.get("valid", false)):
		finish()
		return
	var map_data := RandomMapGenerator.generate(definition)
	var catalog = ResourceCatalog.new()
	catalog.load()
	var sessions: Array = []
	for local_team in [1, 2]:
		var world = SimulationWorld.new(map_data["size"])
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		MatchBootstrap.apply(world, definition, map_data)
		var session = LockstepSession.new()
		assert_equal(session.configure(GameController.new(world), definition, 99173, [1, 2], local_team, 40), "", "networked mixed-domain peer configures")
		sessions.append(session)
	for sender in sessions:
		var hello: Dictionary = JSON.parse_string(JSON.stringify(sender.hello_packet()))
		for receiver in sessions:
			assert_equal(receiver.receive_packet(hello), "", "mixed-domain peer handshake agrees")
	var land_id := first_unit_id(sessions[0].controller.simulation_world, 1, "clubman")
	var ship_id := first_unit_id(sessions[0].controller.simulation_world, 2, "scout_ship")
	assert_true(land_id > 0 and ship_id > 0, "mixed-domain fixture has both movement domains")
	for tick in range(1, MATCH_TICKS + 1):
		var frame_packets: Array[Dictionary] = []
		for session in sessions:
			var commands: Array = []
			if tick == 1 and session.local_team == 1:
				commands.append(Commands.MoveCommand.new(tick, [land_id], Vector2(8.5, 10.5)))
			if tick == 1 and session.local_team == 2:
				commands.append(Commands.AttackMoveCommand.new(tick, [ship_id], Vector2(3.5, 7.5)))
			if tick == 100 and session.local_team == 1:
				commands.append(Commands.PopulationLimitCommand.new(tick, 100))
			if tick == 1900 and session.local_team == 2:
				commands.append(Commands.ResignCommand.new(tick))
			frame_packets.append(session.frame_packet(tick, commands))
		if tick % 2 == 0:
			frame_packets.reverse()
		for packet in frame_packets:
			var transmitted: Dictionary = JSON.parse_string(JSON.stringify(packet))
			for session in sessions:
				var error: String = session.receive_packet(transmitted)
				if not error.is_empty():
					failures.append("frame tick %d: %s" % [tick, error])
				if tick % 7 == 0:
					session.receive_packet(transmitted)
		var hash_packets: Array[Dictionary] = []
		for session in sessions:
			var step: Dictionary = session.advance_one()
			if not bool(step.get("advanced", false)):
				failures.append("peer %d stopped at tick %d: %s" % [session.local_team, tick, step.get("reason", "")])
			if not step.get("hash_packet", {}).is_empty():
				hash_packets.append(step["hash_packet"])
		for packet in hash_packets:
			var transmitted: Dictionary = JSON.parse_string(JSON.stringify(packet))
			for session in sessions:
				session.receive_packet(transmitted)
		if not failures.is_empty():
			break
	assert_equal(sessions[0].phase, "running", "long mixed-domain session remains synchronized")
	assert_equal(sessions[1].phase, "running", "remote mixed-domain session remains synchronized")
	assert_equal(sessions[0].local_hashes.get(MATCH_TICKS, ""), sessions[1].local_hashes.get(MATCH_TICKS, ""), "long mixed-domain peers finish on the same canonical hash")
	assert_equal(sessions[0].controller.simulation_world.get_victory_result(), sessions[1].controller.simulation_world.get_victory_result(), "long mixed-domain peers agree on outcome")
	assert_true(bool(sessions[0].controller.simulation_world.get_victory_result().get("over", false)), "long match reaches the same terminal state")
	assert_equal(sessions[0].controller.simulation_world.economy_system.get_population_limit(2), 100, "host population change reaches the remote team")
	finish()


func first_unit_id(world, team: int, kind: String) -> int:
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team and String(unit.get("kind", "")) == kind:
			return int(unit.get("id", -1))
	return -1


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P12 long mixed-domain lockstep command-stream test passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
