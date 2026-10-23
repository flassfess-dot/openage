extends SceneTree

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const SimulationVisibilitySystem := preload("res://scripts/simulation_visibility_system.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_visibility_system_matches_fog_reference()
	test_movement_refresh_is_bounded()
	for native in [false, true]:
		test_foundation_lifecycle(native)
	if failures.is_empty():
		print("I1-005a simulation visibility parity tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_visibility_system_matches_fog_reference() -> void:
	var map_size := Vector2i(16, 16)
	var units: Array = [
		vision_entity(1, 1, Vector2(4.0, 4.0), 4.0),
		vision_entity(2, 2, Vector2(8.0, 4.0), 3.0),
	]
	var buildings: Array = [vision_entity(3, 1, Vector2(3.0, 9.0), 2.0)]
	var reference = FogOfWar.new(map_size)
	var system = SimulationVisibilitySystem.new(map_size, func(): return units, func(): return buildings)

	reference.update(units, buildings)
	system.advance({"tick": 1})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "first player visibility matches reference")
	assert_equal(system.get_fog().snapshot(2), reference.snapshot(2), "second player visibility matches reference")

	reference.set_alliance(1, 2, true)
	system.set_alliance(1, 2, true)
	reference.set_shared_vision(1, 2, true)
	system.set_shared_vision(1, 2, true)
	reference.update(units, buildings)
	system.advance({"tick": 2})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "allied visibility matches reference")

	var observed := {"team": 2, "pos": Vector2(8.0, 4.0)}
	assert_equal(system.is_entity_visible(1, observed), true, "allied entity is visible through query facade")
	units[0]["hp"] = 0.0
	buildings[0]["hp"] = 0.0
	reference.update(units, buildings)
	system.advance({"tick": 3})
	assert_equal(system.get_fog().snapshot(1), reference.snapshot(1), "source death transition matches reference")


func test_movement_refresh_is_bounded() -> void:
	var units: Array = [vision_entity(3, 1, Vector2(2.5, 2.5), 1.0)]
	var system = SimulationVisibilitySystem.new(Vector2i(16, 16), func(): return units, func(): return [])
	system.advance({"tick": 1})
	units[0]["pos"] = Vector2(10.5, 10.5)
	for tick in range(2, 6):
		system.advance({"tick": tick})
	assert_equal(system.get_fog().state_at_world(1, Vector2(10.5, 10.5)), FogOfWar.VISIBLE, "moving vision refreshes within one four-bucket cycle")
	assert_equal(system.get_fog().state_at_world(1, Vector2(2.5, 2.5)), FogOfWar.EXPLORED, "bounded movement refresh retires the previous footprint")


func test_foundation_lifecycle(native: bool) -> void:
	var world := World.new(Vector2i(24, 24))
	world.visibility_system.set_native_enabled(native)
	world.fog_of_war.ensure_player(1)
	var building: Dictionary = world.add_building(100, "house", Vector2(12.5, 12.5), 1, false)
	building["components"]["vision"] = {"range": 4.0, "enabled": true}
	world.notify_entity_changed(building)
	world._tick_fog({})
	assert_equal(world.fog_of_war.state_at_world(1, building["pos"]), FogOfWar.UNKNOWN, "foundation never reveals unknown ground (native=%s)" % native)
	world.update_fog_of_war()
	assert_equal(world.fog_of_war.vision_sources.has(201), false, "full refresh excludes the foundation")
	var restored := World.new(world.map_size)
	restored.visibility_system.set_native_enabled(native)
	var data := Checkpoint.capture(world, Controller.new(world), {}, {"size": world.map_size})
	assert_equal(Checkpoint.restore(data, restored, Controller.new(restored)), true, "foundation checkpoint restores")
	restored.update_fog_of_war()
	assert_equal(restored.fog_of_war.state_at_world(1, building["pos"]), FogOfWar.UNKNOWN, "restored foundation keeps unknown ground hidden")
	world.complete_foundation(building)
	world._tick_fog({})
	assert_equal(world.fog_of_war.state_at_world(1, building["pos"]), FogOfWar.VISIBLE, "completed building starts providing sight")
	# Reseeding/reverting a completed structure retires its old source immediately.
	world.set_entity_field(building, "state", "foundation")
	world._tick_fog({})
	assert_equal(world.fog_of_war.state_at_world(1, building["pos"]), FogOfWar.EXPLORED, "foundation transition removes sight while preserving exploration")
	# Simulate an older checkpoint containing the previously erroneous source.
	building["state"] = "complete"
	world.update_fog_of_war()
	building["state"] = "foundation"
	data = Checkpoint.capture(world, Controller.new(world), {}, {"size": world.map_size})
	assert_equal(Checkpoint.restore(data, restored, Controller.new(restored)), true, "legacy foundation source restores")
	assert_equal(restored.fog_of_war.state_at_world(1, building["pos"]), FogOfWar.EXPLORED, "legacy source is retired on load without erasing exploration")
	world.cancel_foundation(int(building["id"]))
	assert_equal(world.fog_of_war.vision_sources.has(201), false, "cancelling a foundation cannot leave sight behind")
	world.shutdown_derived_state()
	restored.shutdown_derived_state()


func vision_entity(id: int, team: int, position: Vector2, sight: float) -> Dictionary:
	return {
		"id": id,
		"team": team,
		"pos": position,
		"hp": 10.0,
		"components": {"vision": {"range": sight, "enabled": true}},
	}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
