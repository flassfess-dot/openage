extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world = World.new(Vector2i(128, 128))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	for index in range(80):
		var unit: Dictionary = world.add_unit(1, "villager", Vector2(4 + index % 10, 4 + index / 10), false)
		unit["task"] = "move"
		unit["target"] = unit["pos"] + Vector2(10, 8)
		unit["formation_group_id"] = -1
		unit["formation_shared_motion"] = false
	var planner = world.pathfinder
	planner.prepare_native_movement_snapshot(world.units)
	var coordinator := Coordinator.new()
	var expected: Array = []
	for unit in world.units: expected.append(planner.calculate_native_movement(unit, unit["target"], 0.05))
	planner.prepare_native_movement_batch(world.units, 0.05, coordinator)
	for index in range(world.units.size()):
		var unit: Dictionary = world.units[index]
		check(planner.calculate_native_movement(unit, unit["target"], 0.05) == expected[index], "velocity, state and neighbor count match exactly")
		var changed_target: Vector2 = unit["target"] + Vector2(3, 1)
		var kernel = planner.native_shared_movement_kernel
		if kernel != null:
			check(planner.calculate_native_movement(unit, changed_target, 0.05) == kernel.calculate_movement(int(unit["id"]), changed_target, float(unit["speed"]), float(unit["cohesion_speed_scale"]), 0.05), "changed target bypasses speculative result")
	coordinator.shutdown()
	finish()
