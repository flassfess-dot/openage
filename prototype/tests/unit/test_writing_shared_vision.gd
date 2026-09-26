extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.add_unit(1, "clubman", Vector2(3, 3), false)
	var ally: Dictionary = world.add_unit(2, "clubman", Vector2(23, 23), false)
	world.update_fog_of_war()
	ally["pos"] = Vector2(13, 23)
	world.update_fog_of_war()
	world.set_alliance(1, 2, true)
	assert_equal(world.get_fog_state_at(1, Vector2(13, 23)), 0, "alliance alone leaves ally live sight unknown")
	assert_equal(world.get_fog_state_at(1, Vector2(23, 23)), 0, "alliance alone does not merge ally exploration")
	world.grant_technology(1, 114)
	world.update_fog_of_war()
	assert_equal(world.get_fog_state_at(1, Vector2(13, 23)), 2, "Writing enables current ally sight")
	assert_equal(world.get_fog_state_at(1, Vector2(23, 23)), 1, "Writing merges historical ally exploration")
	world.set_alliance(1, 2, false)
	assert_equal(world.get_fog_state_at(1, Vector2(13, 23)), 1, "alliance break removes shared live sight but retains exploration")
	var fog = FogOfWar.new(Vector2i(32, 32))
	var third_source := {"id": 300, "team": 3, "pos": Vector2(27, 27), "hp": 10.0, "components": {"vision": {"enabled": true, "range": 2.0}}}
	fog.update([third_source], [])
	fog.set_alliance(2, 3, true)
	fog.set_shared_vision(2, 3, true)
	fog.update([third_source], [])
	fog.set_alliance(1, 2, true)
	fog.set_shared_vision(1, 2, true)
	fog.update([third_source], [])
	assert_equal(fog.state_at_world(1, Vector2(27, 27)), FogOfWar.UNKNOWN, "shared exploration does not leak through a non-allied third player")
	fog.set_relation(0, 1, true)
	fog.set_shared_vision(0, 1, true)
	fog.merge_exploration(0, 1)
	assert_equal(fog.states_by_player.has(0), false, "neutral team never receives a fog map")
	world.add_building(900, "town_center", Vector2(16, 16), 0)
	assert_equal(world.get_fog_of_war().states_by_player.has(0), false, "neutral building completion does not create player vision")
	finish()


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P06 Writing shared vision passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
