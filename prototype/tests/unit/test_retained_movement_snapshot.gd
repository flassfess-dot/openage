extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var world := World.new(Vector2i(48, 48))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	for i in range(20): world.add_unit(1, "villager", Vector2(8 + i % 5, 8 + i / 5), false)
	var candidate := Pathfinder.new(world.navigation_grid)
	var reference := Pathfinder.new(world.navigation_grid)
	reference.incremental_movement_enabled = false
	candidate.prepare_native_movement_snapshot(world.units)
	check(candidate.native_shared_movement_kernel.has_method("configure_movement_entities"), "retained movement module is installed")
	check(candidate.last_movement_snapshot_stats.get("full_rebuilds") == 1, "new roster builds a full generation")
	candidate.prepare_native_movement_snapshot(world.units)
	check(candidate.last_movement_snapshot_stats.get("updated") == 0 and candidate.last_movement_snapshot_stats.get("generation_copies") == 0, "idle roster neither repacks nor copies a generation")
	var old_context = candidate.native_shared_movement_kernel.create_search_context()
	old_context.share_movement_snapshot(candidate.native_shared_movement_kernel)
	var old_result: Vector4 = old_context.calculate_movement(int(world.units[0]["id"]), Vector2(22, 22), 1.0, 1.0, 0.05)
	for step in range(9):
		var unit: Dictionary = world.units[step]
		match step:
			0: unit["pos"] += Vector2(0.01, 0.01)
			1: unit["pos"] += Vector2(5, 5)
			2: unit["hp"] = 0.0
			3: unit["footprint_radius"] = 1.37
			4: unit["minimum_clearance"] = 1.17
			5: unit["push_priority"] = 99
			6: unit["solid_animal"] = true
			7: unit["behavior_tags"] = ["huntable"]
			8: unit["movement_domain"] = "water"
		candidate.prepare_native_movement_snapshot(world.units)
		reference.prepare_native_movement_snapshot(world.units)
		for other in world.units:
			check(candidate.calculate_native_movement(other, Vector2(22, 22), 0.05) == reference.calculate_native_movement(other, Vector2(22, 22), 0.05), "exact legacy movement after change %d" % step)
		check(old_context.calculate_movement(int(world.units[0]["id"]), Vector2(22, 22), 1.0, 1.0, 0.05) == old_result, "old worker generation stays immutable")
	world.units.reverse()
	candidate.prepare_native_movement_snapshot(world.units)
	reference.prepare_native_movement_snapshot(world.units)
	check(candidate.last_movement_snapshot_stats.get("full_rebuilds") == 1, "roster order change rebuilds original deterministic slot order")
	for unit in world.units: check(candidate.calculate_native_movement(unit, Vector2(22, 22), 0.05) == reference.calculate_native_movement(unit, Vector2(22, 22), 0.05), "reordered neighbors retain exact results")
	world.units.remove_at(0)
	candidate.prepare_native_movement_snapshot(world.units)
	reference.prepare_native_movement_snapshot(world.units)
	for unit in world.units: check(candidate.calculate_native_movement(unit, Vector2(22, 22), 0.05) == reference.calculate_native_movement(unit, Vector2(22, 22), 0.05), "removed obstacle retains exact results")
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print("Retained movement generation checks: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
