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
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.reset_game(false)
	var victim: Dictionary = world.add_unit(2, "clubman", Vector2(10, 10), false)
	var responders: Array = []
	for index in range(4):
		responders.append(world.add_unit(2, "clubman", Vector2(9 + index, 11), false))
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(10.5, 9.5), false)
	world.update_fog_of_war()
	world.record_attack_distress(attacker, victim)

	var ai = AiPlayer.new({
		"team": 2,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 20},
		"source_ai": {
			"schema_version": 1,
			"status": "partial",
			"build_order": [],
			"target_markers": [],
			"runtime_support": {"military_enabled": true, "attack_enabled": false, "defence_response_enabled": true},
			"strategic_numbers": [
				{"source_id": 19, "value": 50, "runtime_semantics": "implemented"},
				{"source_id": 20, "value": 12, "runtime_semantics": "implemented"},
				{"source_id": 48, "value": 30, "runtime_semantics": "implemented"},
			],
		},
	})
	var snapshot := SimulationSnapshot.presentation(world, 0, 2, ai.presentation_options())
	var commands: Array = ai.collect_commands(snapshot, 1)
	assert_equal(commands.size(), 1, "source response emits one non-conflicting group command")
	assert_equal(commands[0].command_type(), "attack", "source response enters the common attack pipeline")
	assert_equal(commands[0].unit_ids, [int(responders[1]["id"]), int(responders[0]["id"])], "source percentage selects the two nearest idle responders in deterministic distance order")
	assert_equal(ai.last_response_tick, 1, "AI state records the response cooldown origin")
	assert_equal(ai.last_attack_tick, -1, "response-only source contract never invents a scheduled attack")

	var controller = GameController.new(world)
	controller.enqueue_command(commands[0], true, 2)
	controller.advance_frame(0.05, 1, 2)
	for responder in responders.slice(0, 2):
		assert_equal(String(responder.get("task", "")), "attack", "responder executes through authoritative simulation command handling")
		assert_equal(int(responder.get("target_id", -1)), int(attacker["id"]), "responder keeps the exact attacker as its target")
	var accepted: Array = controller.events_after().filter(func(event):
		return String(event.get("type", "")) == "command_accepted" \
			and int(event.get("payload", {}).get("issuer_id", 0)) == 2 \
			and int(event.get("payload", {}).get("sequence_id", -1)) == int(commands[0].sequence_id)
	)
	assert_equal(accepted.size(), 1, "source response command is accepted once by the authoritative controller")

	if failures.is_empty():
		print("I12-020L source campaign AI distress-response pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
