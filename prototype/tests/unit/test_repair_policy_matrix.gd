extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5, 5), false)
	var own: Dictionary = world.add_building(601, "town_center", Vector2(8, 8), 1)
	var ally: Dictionary = world.add_building(602, "town_center", Vector2(16, 8), 2)
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(8, 18), false)
	var soldier: Dictionary = world.add_unit(1, "clubman", Vector2(10, 18), false)
	for target in [own, ally, ship, soldier]:
		target["hp"] = float(target["max_hp"]) - 10.0
	assert_true(world.can_worker_repair(worker, own), "own damaged building is repairable")
	assert_true(not world.can_worker_repair(worker, ally), "foreign building is not repairable before alliance")
	world.set_alliance(1, 2, true)
	assert_true(world.can_worker_repair(worker, ally), "mutual ally building becomes repairable")
	assert_true(world.can_worker_repair(worker, ship), "damaged ship uses repair policy")
	assert_true(not world.can_worker_repair(worker, soldier), "ordinary land soldier is not worker-repairable")
	assert_true(world.assign_command_repair([worker], int(own["id"])), "valid repair order is accepted")
	own["hp"] = own["max_hp"]
	assert_true(not world.can_worker_repair(worker, own), "full-health target offers no repair")
	world.set_alliance(1, 2, false)
	assert_true(not world.can_worker_repair(worker, ally), "diplomacy revokes ally repair")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func finish() -> void:
	if failures.is_empty():
		print("P04 repair policy matrix passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
