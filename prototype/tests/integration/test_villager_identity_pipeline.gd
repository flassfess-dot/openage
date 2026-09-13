extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_logical_identity_and_production(catalog)
	verify_task_forms_and_palettes(catalog)
	verify_iron_age_upgrade_preserves_task(catalog)
	if failures.is_empty():
		print("I12-013 Villager identity and task-form pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_logical_identity_and_production(catalog) -> void:
	var world = configured_world(catalog)
	world.set_resource_amount(1, 0, 500)
	world.set_population_cap(1, 20)
	world.set_population_housing(1, 20)
	var town_center: Dictionary = world.add_building(950, "town_center", Vector2(12.0, 12.0), 1)
	var before_food: int = world.get_resource_amount(1, 0)
	var order: Variant = world.enqueue_unit_production(int(town_center["id"]), 1, "villager")
	assert_true(order != null, "Villager enters the normal Town Center production queue")
	assert_equal(world.get_resource_amount(1, 0), before_food - 50, "production reserves original 50 food")
	world.update_production(19.95)
	assert_equal(world.get_units().size(), 0, "Villager is not produced before original 20 seconds")
	world.update_production(0.05)
	assert_equal(world.get_units().size(), 1, "Villager is produced at original creation time")
	var villager: Dictionary = world.get_units()[0]
	assert_equal(villager.get("source_unit_id"), 83, "logical Villager starts from source unit 83")
	assert_equal(villager.get("components", {}).get("identity", {}).get("source_key"), "13:83", "authoritative identity points at source 83")
	assert_equal(villager.get("corpse_source_id"), 43, "idle Villager uses source corpse 43")
	assert_float(float(villager.get("carry_capacity", -1.0)), 0.0, "idle source 83 has no task-form inventory")
	assert_equal(catalog.unit_frame_info(villager, "idle").get("asset_name"), "villager_idle", "source 83 idle presentation")
	assert_equal(catalog.unit_frame_info(villager, "attack").get("asset_name"), "villager_attack", "source 83 attack presentation")


func verify_task_forms_and_palettes(catalog) -> void:
	var world = configured_world(catalog)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.0, 7.0), false)
	var enemy: Dictionary = world.add_unit(2, "villager", Vector2(9.0, 7.0), false)
	var roles := [
		{"name": "build", "source": 118, "work_rate": 1.0, "state": AnimationController.BUILD, "asset": "builder_work"},
		{"name": "repair", "source": 156, "work_rate": 0.4000000059604645, "state": AnimationController.REPAIR, "asset": "builder_work"},
		{"name": "fish", "source": 119, "work_rate": 0.6000000238418579, "state": AnimationController.GATHER, "asset": "fisherman_work"},
		{"name": "farm", "source": 259, "work_rate": 0.44999998807907104, "state": AnimationController.GATHER, "asset": "farmer_work"},
		{"name": "hunt", "source": 122, "work_rate": 0.44999998807907104, "state": AnimationController.GATHER, "asset": "hunter_work"},
	]
	for role in roles:
		assert_true(world.worker_role_system.apply(worker, world.worker_role_system.profile_for_task(worker, String(role["name"])), String(role["name"]) == "hunt"), "%s task profile applies" % role["name"])
		assert_role(catalog, worker, role, false)
		assert_true(world.worker_role_system.apply(enemy, world.worker_role_system.profile_for_task(enemy, String(role["name"])), String(role["name"]) == "hunt"), "enemy %s task profile applies" % role["name"])
		assert_role(catalog, enemy, role, true)

	var resource_roles := [
		{"type": 0, "source": 120, "work_rate": 0.44999998807907104, "state": AnimationController.GATHER, "asset": "villager_work_food"},
		{"type": 1, "source": 123, "work_rate": 0.550000011920929, "state": AnimationController.GATHER, "asset": "villager_work_wood"},
		{"type": 2, "source": 124, "work_rate": 0.44999998807907104, "state": AnimationController.GATHER, "asset": "villager_work_mine"},
		{"type": 3, "source": 251, "work_rate": 0.44999998807907104, "state": AnimationController.GATHER, "asset": "villager_work_mine"},
	]
	for role in resource_roles:
		var profile: Dictionary = world.worker_role_system.profile_for_resource_type(worker, int(role["type"]))
		world.worker_role_system.apply(worker, profile, false)
		assert_role(catalog, worker, role, false)
		assert_float(float(worker.get("carry_capacity", 0.0)), 10.0, "resource task form supplies 10 capacity")

	world.worker_role_system.clear(worker)
	assert_equal(worker.get("source_unit_id"), 83, "clearing task form never changes logical identity")
	assert_equal(worker.get("worker_role_source_unit_id"), -1, "clearing removes transient source identity")
	assert_float(float(worker.get("carry_capacity", -1.0)), 0.0, "clearing restores base source capacity")
	assert_equal(worker.get("components", {}).get("identity", {}).has("task_source_unit_id"), false, "clearing removes task identity component")


func verify_iron_age_upgrade_preserves_task(catalog) -> void:
	var world = configured_world(catalog)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(8.0, 8.0), false)
	var lumber_profile: Dictionary = world.worker_role_system.profile_for_resource_type(worker, 1)
	world.worker_role_system.apply(worker, lumber_profile, false)
	world.grant_technology(1, 103)
	assert_equal(worker.get("source_unit_id"), 293, "Iron Age applies original Villager 83 to 293 upgrade")
	assert_equal(worker.get("worker_role_source_unit_id"), 123, "active Lumberjack task source survives age upgrade")
	assert_equal(worker.get("components", {}).get("identity", {}).get("task_source_key"), "13:123", "task source key survives age upgrade")
	assert_equal(presentation_asset(catalog, worker, AnimationController.GATHER), "villager_work_wood", "active task presentation survives sparse source variant")
	world.worker_role_system.clear(worker)
	assert_equal(catalog.unit_frame_info(worker, "attack").get("asset_name"), "iron_villager_attack", "source 293 selects Iron Age attack graphic")
	var future: Dictionary = world.add_unit(1, "villager", Vector2(9.0, 8.0), false)
	assert_equal(future.get("source_unit_id"), 293, "future Villagers inherit Iron Age source upgrade")


func assert_role(catalog, worker: Dictionary, expected: Dictionary, enemy: bool) -> void:
	var context := "%s role%s" % [str(expected.get("name", expected.get("type", ""))), " enemy" if enemy else ""]
	assert_equal(worker.get("source_unit_id"), 83, "%s keeps logical identity before age upgrade" % context)
	assert_equal(worker.get("worker_role_source_unit_id"), int(expected["source"]), "%s task source identity" % context)
	assert_equal(worker.get("components", {}).get("identity", {}).get("task_source_unit_id"), int(expected["source"]), "%s component task identity" % context)
	assert_float(float(worker.get("components", {}).get("worker", {}).get("work_rate", 0.0)), float(expected["work_rate"]), "%s source work rate" % context)
	var expected_asset := ("enemy_%s" % String(expected["asset"])) if enemy else String(expected["asset"])
	assert_equal(presentation_asset(catalog, worker, String(expected["state"])), expected_asset, "%s source presentation" % context)


func presentation_asset(catalog, worker: Dictionary, animation_state: String) -> String:
	worker["anim_state"] = animation_state
	var default_state := AnimationController.clip_for_state(animation_state)
	var state: String = catalog.unit_presentation_state(worker, default_state)
	return String(catalog.unit_frame_info(worker, state).get("asset_name", ""))


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
