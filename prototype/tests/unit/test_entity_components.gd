extends SceneTree

const EntityComponents := preload("res://scripts/entity_components.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)

	test_complete_unit_schema(world)
	test_original_values(world)
	test_other_entity_types(world)
	test_dynamic_sync(world)
	test_stable_idle_sync_matches_full_sync(world)
	test_runtime_unit_sync_matches_full_sync(world)

	if failures.is_empty():
		print("S-001 entity component tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_complete_unit_schema(world) -> void:
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(3.0, 4.0), false)
	assert_true(EntityComponents.has_complete_schema(villager), "unit exposes all S-001 components")
	assert_equal(villager["components"]["identity"]["source_key"], "13:83", "component links exact logical Villager object")
	assert_equal(villager["components"]["transform"]["position"], Vector2(3.0, 4.0), "Transform position")
	assert_equal(villager["components"]["ownership"]["civilization_id"], 13, "Ownership civilization")


func test_original_values(world) -> void:
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(5.0, 4.0), false)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(6.0, 4.0), false)
	var villager_components: Dictionary = villager["components"]
	var archer_components: Dictionary = archer["components"]
	assert_float(villager_components["health"]["maximum"], 25.0, "Health from Empires.dat")
	assert_float(villager_components["movement"]["speed"], 1.100000023841858, "Movement speed from Empires.dat")
	assert_float(villager_components["vision"]["range"], 4.0, "Vision range from Empires.dat")
	assert_float(villager_components["resource_carrier"]["capacity"], 0.0, "idle Villager capacity comes from source 83 before a task form is applied")
	assert_true(villager_components["worker"]["enabled"], "Worker classification comes from object class")
	assert_float(villager_components["worker"]["work_rate"], 1.0, "Worker rate from Empires.dat")
	assert_equal(int(archer_components["combat"]["attacks"][0]["type_id"]), 3, "Combat attack class")
	assert_float(float(archer_components["combat"]["attacks"][0]["amount"]), 3.0, "Combat attack amount")
	assert_equal(int(archer_components["combat"]["armors"][0]["type_id"]), 1, "Combat armor class")
	assert_float(float(archer_components["combat"]["armors"][0]["amount"]), -2.0, "Combat armor amount")
	assert_float(archer_components["combat"]["range_max"], 5.0, "Combat range from Empires.dat")
	assert_equal(archer_components["production"]["creation_time"], 30, "Production time from Empires.dat")
	assert_equal(archer_components["technology"]["active_research_id"], -1, "Technology initial state")
	assert_equal(archer_components["animation_state"]["state"], "Idle", "AnimationState initial state")
	var transport: Dictionary = world.add_unit(1, "transport", Vector2(7.0, 7.0), false)
	assert_true(transport["components"]["cargo"]["enabled"], "Transport source command enables Cargo component")
	assert_equal(transport["components"]["cargo"]["capacity"], 4, "Transport uses original four-unit capacity")
	assert_equal(transport["components"]["cargo"]["allowed_domains"], ["land"], "Transport accepts land passengers only")


func test_other_entity_types(world) -> void:
	var building: Dictionary = world.add_building(90, "town_center", Vector2(10.0, 10.0), 1)
	var resource: Dictionary = world.add_resource("tree", Vector2(7.0, 7.0), 75)
	assert_true(EntityComponents.has_complete_schema(building), "building exposes component schema")
	assert_true(EntityComponents.has_complete_schema(resource), "resource exposes component schema")
	assert_float(building["components"]["health"]["maximum"], 600.0, "building Health from Empires.dat")
	assert_float(building["components"]["vision"]["range"], 7.0, "building Vision from Empires.dat")
	assert_equal(building["components"]["footprint"]["occupied_cells"].size(), 9, "building Footprint component")
	assert_float(resource["components"]["resource_carrier"]["amount"], 75.0, "resource amount component")


func test_dynamic_sync(world) -> void:
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.0, 2.0), false)
	unit["pos"] = Vector2(2.5, 3.0)
	unit["previous_pos"] = Vector2(2.0, 2.0)
	unit["hp"] = 17.0
	unit["target_id"] = 404
	unit["cooldown"] = 0.75
	unit["anim_state"] = "AttackRecover"
	world.sync_all_components()
	var components: Dictionary = unit["components"]
	assert_equal(components["transform"]["position"], Vector2(2.5, 3.0), "Transform follows simulation state")
	assert_float(components["health"]["current"], 17.0, "Health follows simulation state")
	assert_equal(components["combat"]["target_id"], 404, "Combat target follows simulation state")
	assert_float(components["combat"]["cooldown"], 0.75, "Combat cooldown follows simulation state")
	assert_equal(components["animation_state"]["state"], "AttackRecover", "AnimationState follows controller")


func test_stable_idle_sync_matches_full_sync(world) -> void:
	var source_unit: Dictionary = world.add_unit(1, "clubman", Vector2(8.0, 8.0), false).duplicate(true)
	source_unit["previous_pos"] = Vector2(7.5, 8.0)
	source_unit["actual_velocity"] = Vector2(1.0, 0.0)
	EntityComponents.sync_dynamic(source_unit)
	var full_sync_unit: Dictionary = source_unit.duplicate(true)
	var idle_sync_unit: Dictionary = full_sync_unit.duplicate(true)
	for unit in [full_sync_unit, idle_sync_unit]:
		unit["previous_pos"] = unit["pos"]
		unit["actual_velocity"] = Vector2.ZERO
		unit["hp"] = 23.0
		unit["cooldown"] = 0.45
		unit["work"] = 0.25
		unit["retaliation_target_id"] = -1
		unit["anim_state"] = "Idle"
		unit["anim"] = 1.75
		unit["animation_events_fired"] = {"sample": true}
	EntityComponents.sync_dynamic(full_sync_unit)
	EntityComponents.sync_stable_idle_tick(idle_sync_unit)
	assert_equal(idle_sync_unit["components"], full_sync_unit["components"], "stable idle fast path matches complete component sync")


func test_runtime_unit_sync_matches_full_sync(world) -> void:
	var source_unit: Dictionary = world.add_unit(1, "clubman", Vector2(9.0, 8.0), false).duplicate(true)
	for key in ["pos", "previous_pos", "target", "destination"]:
		source_unit[key] = Vector2(source_unit[key]) + Vector2(0.25, 0.5)
	source_unit["path"] = [Vector2(10.0, 9.0), Vector2(11.0, 10.0)]
	source_unit["path_index"] = 1
	source_unit["desired_velocity"] = Vector2(0.5, 0.25)
	source_unit["actual_velocity"] = Vector2(0.4, 0.2)
	source_unit["hp"] = 19.0
	source_unit["cooldown"] = 0.6
	source_unit["work"] = 0.3
	source_unit["carried_amount"] = 4.0
	source_unit["carried_resource_type_id"] = 1
	source_unit["anim_state"] = "Move"
	source_unit["anim"] = 2.25
	var full_sync_unit: Dictionary = source_unit.duplicate(true)
	var runtime_sync_unit: Dictionary = source_unit.duplicate(true)
	EntityComponents.sync_dynamic(full_sync_unit)
	EntityComponents.sync_runtime_unit(runtime_sync_unit)
	assert_equal(runtime_sync_unit["components"], full_sync_unit["components"], "runtime unit fast path matches complete component sync")


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
