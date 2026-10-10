extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Probe := preload("res://scripts/performance_probe.gd")
func _initialize() -> void:
	var world := World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var template: Dictionary = world.add_unit(1, "villager", Vector2(4, 4), false)
	var rows: Array = []
	for count in [10, 250, 1000, 4000]:
		for share in [0, 10, 100]:
			var units: Array = []
			for i in range(count):
				var unit := template.duplicate()
				unit["id"] = i + 1
				unit["pos"] = Vector2(i % 128, i / 128)
				units.append(unit)
			var retained := Pathfinder.new(world.navigation_grid)
			var reference := Pathfinder.new(world.navigation_grid)
			reference.incremental_movement_enabled = false
			retained.prepare_native_movement_snapshot(units)
			reference.prepare_native_movement_snapshot(units)
			var a: Array[int] = []
			var b: Array[int] = []
			for step in range(60):
				for i in range(count * share / 100): units[i]["pos"] += Vector2(0.031, 0.017)
				var started := Time.get_ticks_usec()
				retained.prepare_native_movement_snapshot(units)
				a.append(Time.get_ticks_usec() - started)
				started = Time.get_ticks_usec()
				reference.prepare_native_movement_snapshot(units)
				b.append(Time.get_ticks_usec() - started)
			rows.append({"units": count, "changed_percent": share, "retained_us": Probe.summarize(a), "reference_us": Probe.summarize(b)})
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	world.task_coordinator.shutdown()
	print("Movement preparation benchmark: ", JSON.stringify(rows))
	quit(0)
