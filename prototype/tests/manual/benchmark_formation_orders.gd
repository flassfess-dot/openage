extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Geometry := preload("res://scripts/formation_geometry.gd")
const Probe := preload("res://scripts/performance_probe.gd")

func _initialize() -> void:
	var rows: Array = []
	for count in [20, 64, 100, 500]:
		var world = World.new(Vector2i(160, 128))
		var controller = Controller.new(world)
		controller.set_speed_multiplier(1.0)
		var ids: Array[int] = []
		for position in Geometry.world_slots(Geometry.local_slots(count, "LINE"), Vector2(36.5, 60.5), Vector2.RIGHT):
			var unit: Dictionary = world.add_unit(1, "clubman", position, false)
			unit["stance"] = "passive"
			ids.append(int(unit["id"]))
		world.add_unit(2, "clubman", Vector2(150, 120), false)["stance"] = "passive"
		var probe := Probe.new()
		controller.set_performance_probe(probe)
		for iteration in range(12):
			controller.enqueue_command(Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, Vector2(110.5, 60.5), "LINE", Vector2.RIGHT))
			controller.tick_index += 1
			controller.process_commands()
		var ticks: Array = []
		for tick in range(120):
			var started := Time.get_ticks_usec()
			controller.advance_frame(0.05, 1, 2)
			ticks.append(Time.get_ticks_usec() - started)
		var metrics: Dictionary = probe.report()["metrics_microseconds"]
		var selected: Dictionary = {}
		for key in metrics:
			if String(key).begins_with("formation.") or key == "simulation.unit_orders.formation_cohesion": selected[key] = metrics[key]
		var row := {"count": count, "ticks_us": Probe.summarize(ticks), "metrics_us": selected}
		rows.append(row)
		print("FORMATION_BENCH ", JSON.stringify(row))
		world.task_coordinator.shutdown()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(arg.trim_prefix("--output="), FileAccess.WRITE)
			file.store_string(JSON.stringify(rows, "\t"))
	quit(0)
