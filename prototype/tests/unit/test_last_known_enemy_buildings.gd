extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const AiStrategicPlanner := preload("res://scripts/ai_strategic_planner.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var scout: Dictionary = world.add_unit(1, "scout", Vector2(17, 17), false)
	var enemy: Dictionary = world.add_building(901, "town_center", Vector2(19, 17), 2)
	world.update_fog_of_war()
	var initial: Dictionary = by_id(SimulationSnapshot.presentation(world, 0, 1).get("buildings", []), int(enemy["id"]))
	assert_true(not initial.is_empty(), "visible enemy building enters observer snapshot")
	var observed_hp := float(initial.get("hp", -1.0))
	scout["pos"] = Vector2(3, 3)
	world.update_fog_of_war()
	enemy["hp"] = maxf(1.0, observed_hp - 100.0)
	enemy["team"] = 3
	var hidden_snapshot: Dictionary = SimulationSnapshot.presentation(world, 1, 1)
	var hidden: Dictionary = by_id(hidden_snapshot.get("buildings", []), int(enemy["id"]))
	assert_equal(float(hidden.get("hp", -1.0)), observed_hp, "hidden damage does not update remembered HP")
	assert_equal(int(hidden.get("team", -1)), 2, "hidden conversion does not update remembered owner")
	assert_true(bool(hidden.get("last_known", false)), "fogged building is marked last-known")
	assert_true(String(AiStrategicPlanner.choose_goal(hidden_snapshot, 1, 0).get("type", "")) != "attack", "AI cannot directly attack an unobserved building")
	assert_equal(String(ContextResolver.resolve([scout], hidden, Vector2.ZERO, 1).get("type", "")), "move", "context command does not target a hidden static object")
	var codec := ReplaySystem.new()
	var archived_memory: Dictionary = codec.decode_variant(codec.encode_variant(world.last_known_buildings_by_player))
	world.restore_last_known_buildings(archived_memory)
	assert_true(world.last_known_buildings_by_player.has(1), "save restore converts observer key back to integer")
	assert_true(world.last_known_buildings_by_player[1].has(int(enemy["id"])), "save restore converts building key back to integer")
	assert_true(by_id(SimulationSnapshot.presentation(world, 1, 1).get("buildings", []), int(enemy["id"])).get("last_known", false), "remembered building survives save codec")
	world.buildings.erase(enemy)
	world.buildings_by_id.erase(int(enemy["id"]))
	world.update_fog_of_war()
	var destroyed_hidden: Dictionary = by_id(SimulationSnapshot.presentation(world, 2, 1).get("buildings", []), int(enemy["id"]))
	assert_equal(float(destroyed_hidden.get("hp", -1.0)), observed_hp, "hidden destruction does not remove the remembered building")
	scout["pos"] = Vector2(17, 17)
	world.update_fog_of_war()
	assert_true(by_id(SimulationSnapshot.presentation(world, 3, 1).get("buildings", []), int(enemy["id"])).is_empty(), "reconnaissance clears destroyed building memory")
	finish()


func by_id(entities: Array, id: int) -> Dictionary:
	for entity_value in entities:
		var entity: Dictionary = entity_value
		if int(entity.get("id", -1)) == id:
			return entity
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P06 last-known enemy buildings passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
