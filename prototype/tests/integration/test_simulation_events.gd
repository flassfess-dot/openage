extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_combat_events_flow_through_controller()
	test_creation_capture_is_explicit()
	test_completion_events_are_authoritative()
	test_production_completion_flows_through_tick()
	if failures.is_empty():
		print("I1-002 simulation domain event integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_combat_events_flow_through_controller() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec({"units": {"test_melee": {
		"hit_points": 3.0,
		"speed": 1.0,
		"attack_period": 1.0,
		"range": 0.0,
		"projectile_id": -1,
		"attacks": [{"amount": 4.0}],
		"animations": {"attack": {"frame_rate": 0.05, "damage_frame": 0}},
	}}})
	var attacker: Dictionary = world.add_unit(1, "test_melee", Vector2(6.0, 6.0), false)
	var target: Dictionary = world.add_unit(2, "test_melee", Vector2(6.6, 6.0), false)
	var controller = GameController.new(world)
	var command = Commands.AttackCommand.new(1, [attacker["id"]], int(target["id"]))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)

	var events: Array = controller.events_after()
	var types: Array[String] = []
	for event in events:
		types.append(String(event["type"]))
	assert_true(types.has("command_accepted"), "command result shares the event stream")
	assert_true(types.has("attack"), "attack event is emitted at action frame")
	assert_true(types.has("hit"), "hit event is emitted for contact")
	assert_true(types.has("damage"), "damage event is emitted with authoritative result")
	assert_true(types.has("death"), "death event is emitted once on lifecycle transition")
	var damage_event: Dictionary = first_event(events, "damage")
	assert_equal(damage_event.get("payload", {}).get("target_id"), target["id"], "damage event identifies target")
	assert_equal(float(damage_event.get("payload", {}).get("remaining_hp", -1.0)), 0.0, "damage event contains post-hit health")
	assert_true(not types.has("entity_created"), "entities created before a tick do not leak as runtime events")


func test_creation_capture_is_explicit() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.add_unit(1, "clubman", Vector2(2.0, 2.0), false)
	assert_equal(world.drain_domain_events().size(), 0, "setup mutation is silent outside event capture")
	world.begin_event_capture()
	var created: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 2.0), false)
	world.end_event_capture()
	var events: Array = world.drain_domain_events()
	assert_equal(events.size(), 1, "captured creation emits one event")
	assert_equal(events[0]["type"], "entity_created", "creation event has stable type")
	assert_equal(events[0]["payload"]["entity_id"], created["id"], "creation event identifies entity")


func test_completion_events_are_authoritative() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.begin_event_capture()
	var foundation: Dictionary = world.add_building(42, "house", Vector2(6.0, 6.0), 1, false)
	world.complete_foundation(foundation)
	world.grant_technology(1, 999)
	world.end_event_capture()
	var events: Array = world.drain_domain_events()
	var types: Array[String] = []
	for event in events:
		types.append(String(event["type"]))
	assert_equal(types, ["entity_created", "build_complete", "research_complete"], "completion events preserve transition order")
	assert_equal(first_event(events, "build_complete")["payload"]["building_id"], 42, "build completion identifies building")
	assert_equal(first_event(events, "research_complete")["payload"]["technology_id"], 999, "research completion identifies technology")


func test_production_completion_flows_through_tick() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec({"units": {"quick_unit": {
		"hit_points": 5.0,
		"speed": 1.0,
		"creation_time": 0.05,
		"resource_cost": [
			{"type_id": 0, "amount": 10, "enabled": true},
			{"type_id": 4, "amount": 1, "enabled": false},
		],
	}}})
	var building: Dictionary = world.add_building(77, "town_center", Vector2(8.0, 8.0), 1)
	world.set_resource_amount(1, 0, 20)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "quick_unit") != null, "quick production enters queue")
	var controller = GameController.new(world)
	controller.advance_frame(0.05, 1, 2)
	var created: Dictionary = first_event(controller.events_after(), "entity_created")
	assert_equal(created.get("payload", {}).get("entity_category"), "unit", "production completion emits unit creation through controller stream")
	assert_equal(created.get("payload", {}).get("kind"), "quick_unit", "production event preserves trained kind")
	assert_equal(world.get_population(1), 1, "production completion adds living population")


func first_event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if String(event.get("type", "")) == event_type:
			return event
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
