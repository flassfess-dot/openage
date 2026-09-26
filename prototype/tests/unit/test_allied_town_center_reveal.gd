extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
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
	world.add_unit(1, "clubman", Vector2(3, 3), false)
	var ally_center: Dictionary = world.add_building(801, "town_center", Vector2(23, 23), 2)
	var ally_unit: Dictionary = world.add_unit(2, "clubman", Vector2(21, 23), false)
	world.set_alliance(1, 2, true)
	assert_equal(world.get_fog_state_at(1, Vector2(23, 23)), 1, "allied Town Center location is explored, not live visible")
	assert_true(not world.is_entity_visible_to(1, ally_center), "alliance does not confer live sight")
	var view: Dictionary = SimulationSnapshot.presentation(world, 0, 1)
	var remembered: Dictionary = by_id(view.get("buildings", []), int(ally_center["id"]))
	assert_true(not remembered.is_empty(), "allied Town Center position enters legal knowledge")
	assert_true(bool(remembered.get("last_known", false)), "revealed center is a frozen record")
	assert_true(by_id(view.get("units", []), int(ally_unit["id"])).is_empty(), "other allied units remain hidden before Writing")
	var early_alliance = SimulationWorld.new(Vector2i(32, 32))
	early_alliance.set_gamespec(catalog.gamespec_data)
	early_alliance.set_object_catalog(catalog.object_catalog_data)
	early_alliance.set_runtime_catalog(catalog.runtime_catalog_data)
	early_alliance.set_alliance(1, 2, true)
	var later_center: Dictionary = early_alliance.add_building(802, "town_center", Vector2(24, 23), 2)
	var later_view: Dictionary = SimulationSnapshot.presentation(early_alliance, 0, 1)
	assert_true(not by_id(later_view.get("buildings", []), int(later_center["id"])).is_empty(), "initial alliance reveals Town Center spawned afterwards")
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
		print("P06 allied Town Center reveal passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
