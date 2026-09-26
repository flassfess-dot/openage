extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const PresentationEffectTimeline := preload("res://scripts/presentation_effect_timeline.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

class EffectRegistryStub extends RefCounted:
	func duration(_graphic_id: int) -> float:
		return 0.5

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_command_and_replay(catalog)
	test_exact_ground_impact_and_blast(catalog)
	test_empty_ground_misses(catalog)
	test_fog_safe_impact_presentation()
	if failures.is_empty():
		print("P02 attack-ground pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_command_and_replay(catalog) -> void:
	var world = original_world(catalog)
	var siege: Dictionary = world.add_unit(1, "stone_thrower", Vector2(5, 8), false)
	var ordinary: Dictionary = world.add_unit(1, "clubman", Vector2(6, 8), false)
	assert_true(world.can_attack_ground(siege), "source stone thrower supports ground attack")
	assert_true(not world.can_attack_ground(ordinary), "ordinary melee unit cannot attack ground")
	var controller = GameController.new(world)
	var ids: Array[int] = [int(siege["id"]), int(ordinary["id"])]
	var command = Commands.AttackGroundCommand.new(1, ids, Vector2(10, 8))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "public AttackGroundCommand is accepted for eligible members")
	assert_equal(String(siege.get("task", "")), "attack_ground", "eligible siege unit receives the ground task")
	assert_equal(String(ordinary.get("task", "")), "idle", "ineligible unit is not diverted")
	var replay = ReplaySystem.new()
	replay.begin(4477)
	replay.record_command(command)
	var loaded = ReplaySystem.new()
	assert_true(loaded.load_json(replay.to_json()), "ground-attack replay JSON loads")
	var restored = loaded.command_from_record(loaded.command_records[0])
	assert_equal(String(restored.command_type()), "attack_ground", "replay reconstructs AttackGroundCommand")
	assert_equal(Vector2(restored.target), Vector2(10, 8), "replay preserves the exact world position")


func test_exact_ground_impact_and_blast(catalog) -> void:
	var world = original_world(catalog)
	var siege: Dictionary = world.add_unit(1, "stone_thrower", Vector2(5, 8), false)
	var direct: Dictionary = world.add_unit(2, "clubman", Vector2(10, 8), false)
	var adjacent: Dictionary = world.add_unit(2, "clubman", Vector2(10.4, 8), false)
	var friendly: Dictionary = world.add_unit(1, "clubman", Vector2(10, 8.4), false)
	siege["components"]["combat"]["friendly_fire"] = false
	var direct_hp := float(direct["hp"])
	var adjacent_hp := float(adjacent["hp"])
	var friendly_hp := float(friendly["hp"])
	var projectile: Dictionary = world.spawn_projectile(siege, {"id": -1, "pos": Vector2(10, 8), "hp": 1.0, "elevation": world.elevation_at(Vector2(10, 8)), "attack_ground": true})
	assert_equal(int(projectile.get("target_id", -2)), -1, "ground attack has no hidden entity target")
	assert_equal(Vector2(projectile.get("target_position", Vector2.ZERO)), Vector2(10, 8), "ground shot aims at the chosen point")
	for _step in range(200):
		world.update_projectiles(GameController.FIXED_STEP_SECONDS, 1)
		if not bool(projectile.get("active", true)):
			break
	assert_true(not bool(projectile.get("active", true)), "ground projectile reaches its impact point")
	assert_true(float(direct["hp"]) < direct_hp, "blast damages an enemy at the point")
	assert_true(float(adjacent["hp"]) < adjacent_hp, "shared spatial blast damages a nearby enemy")
	assert_equal(float(friendly["hp"]), friendly_hp, "existing friendly-fire policy still applies")


func test_empty_ground_misses(catalog) -> void:
	var world = original_world(catalog)
	var siege: Dictionary = world.add_unit(1, "stone_thrower", Vector2(5, 8), false)
	var far_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(15, 15), false)
	var enemy_hp := float(far_enemy["hp"])
	var projectile: Dictionary = world.spawn_projectile(siege, {"id": -1, "pos": Vector2(10, 8), "hp": 1.0, "attack_ground": true})
	for _step in range(200):
		world.update_projectiles(GameController.FIXED_STEP_SECONDS, 1)
		if not bool(projectile.get("active", true)):
			break
	assert_true(not bool(projectile.get("hit", true)), "empty ground records a miss")
	assert_equal(float(far_enemy["hp"]), enemy_hp, "ground shot does not redirect to a distant entity")


func test_fog_safe_impact_presentation() -> void:
	var timeline = PresentationEffectTimeline.new()
	timeline.configure(EffectRegistryStub.new())
	var impact := {"type": "projectile_impact", "sequence_id": 17, "payload": {"projectile_id": 34, "team": 1, "position": Vector2(10, 8), "impact_effect_graphic_id": 270}}
	timeline.consume([impact], func(_position): return false)
	assert_equal(timeline.snapshot().size(), 0, "unseen ground impact cannot leak an effect through fog")
	timeline.consume([impact], func(_position): return true)
	assert_equal(timeline.snapshot().size(), 1, "visible ground impact uses the normal effect pipeline")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
