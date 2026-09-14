extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.configure_players([
		{"team": 1, "civilization_id": 14, "starting_resources": {}},
		{"team": 2, "civilization_id": 13, "starting_resources": {}},
	])
	var artifact: Dictionary = world.add_unit(0, "artifact", Vector2(10.0, 10.0), false)
	var captor: Dictionary = world.add_unit(1, "villager", Vector2(10.8, 10.0), false)
	assert_equal(int(artifact.get("team", -1)), 0, "artifact starts neutral")
	assert_true(world.find_combat_target(int(artifact["id"])) == null, "artifact is not a combat target")
	world.update_capturable_objectives()
	assert_equal(int(artifact.get("team", -1)), 1, "nearby player unit captures artifact")
	var linked: Array = world.victory_objectives.filter(func(value): return int(value.get("source_entity_id", -1)) == int(artifact["id"]))
	assert_equal(linked.size(), 1, "artifact owns one logical victory objective")
	if not linked.is_empty():
		assert_equal(int(linked[0].get("team", -1)), 1, "logical artifact objective follows ownership")
		assert_true(bool(linked[0].get("logical_only", false)), "unit presentation remains the sole visual")
	assert_true(world.assign_command_move([artifact], Vector2(15.0, 10.0)), "captured artifact accepts the ordinary movement command")
	assert_equal(String(artifact.get("task", "")), "move", "artifact follows the shared navigation pipeline")
	captor["pos"] = Vector2(2.0, 2.0)
	var recaptor: Dictionary = world.add_unit(2, "clubman", Vector2(10.2, 10.0), false)
	world.update_capturable_objectives()
	assert_equal(int(artifact.get("team", -1)), 2, "enemy proximity recaptures an artifact deterministically")
	assert_true(int(recaptor.get("id", -1)) > 0, "recapturing unit remains a normal simulation entity")

	if failures.is_empty():
		print("I12-020N artifact capture pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
