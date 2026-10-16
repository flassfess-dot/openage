extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Geometry := preload("res://scripts/formation_geometry.gd")

var failures: Array[String] = []

func _initialize() -> void:
	for native in [false, true]:
		run_march("open", native, false)
		run_march("passage", native, false)
		run_march("mixed", native, true)
		run_march("turn", native, false, 100)
		run_march("passage", native, false, 100)
		run_march("bend", native, false)
		for shape in [Geometry.BLOCK, Geometry.COLUMN, Geometry.WEDGE, Geometry.STAGGER, Geometry.FLANK]:
			run_march("open", native, false, 20, shape)
	for failure in failures: push_error(failure)
	print("Formation march acceptance: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func run_march(scenario: String, native: bool, mixed: bool, count: int = 20, shape: String = Geometry.LINE) -> void:
	var world = World.new(Vector2i(64, 48))
	world.pathfinder.set_native_enabled(native)
	if scenario == "passage":
		world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 29 and cell.x <= 31 and cell.y != 24 else "grass")
	elif scenario == "bend":
		world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 29 and cell.x <= 31 and cell.y >= 10 and cell.y <= 35 else "grass")
	var ids: Array[int] = []
	for position in Geometry.world_slots(Geometry.local_slots(count, shape), Vector2(12.5, 24.5), Vector2.RIGHT):
		var unit: Dictionary = world.add_unit(1, "clubman", position, false)
		unit["stance"] = "passive"
		if mixed: unit["speed"] = 1.2 if ids.size() % 2 == 0 else 2.4
		ids.append(int(unit["id"]))
	world.add_unit(2, "clubman", Vector2(60, 44), false)["stance"] = "passive"
	for y in range(world.map_size.y):
		for x in range(world.map_size.x): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	var controller = Controller.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.FormationMoveCommand.new(1, ids, Vector2(49.5, 24.5), shape, Vector2.RIGHT))
	var last_tick := 0
	var invalid_positions: Dictionary = {}
	var excessive_steps: Dictionary = {}
	for tick in range(1600):
		if scenario == "turn" and tick == 60:
			controller.enqueue_command(Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, Vector2(30.5, 12.5), "LINE", Vector2.UP))
		if scenario == "turn" and tick == 120:
			controller.enqueue_command(Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, Vector2(12.5, 24.5), "LINE", Vector2.LEFT))
		controller.advance_frame(0.05, 1, 2)
		for id in ids:
			var unit: Dictionary = world.find_unit(id)
			var position: Vector2 = unit["pos"]
			if position.distance_to(unit["previous_pos"]) > float(unit["speed"]) * 0.05 + 0.036: excessive_steps[id] = true
			if scenario in ["passage", "bend"] and position.x >= 27 and position.x <= 34:
				if not world.navigation_grid.is_position_walkable_for(position, unit["footprint_radius"], "land", unit["terrain_restriction"]): invalid_positions[id] = true
		last_tick = tick + 1
		if ids.all(func(id): return world.find_unit(id)["task"] == "idle"): break
	var arrived := 0
	var detached := 0
	var reasons: Dictionary = {}
	for id in ids:
		var unit: Dictionary = world.find_unit(id)
		if unit.get("formation_home") != null and Vector2(unit["pos"]).distance_to(unit["formation_home"]) < 0.04: arrived += 1
		if int(unit["formation_group_id"]) < 0: detached += 1
		var reason := String(unit["diagnostic_reason"])
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	var context := "%s/%s/%d native=%s" % [scenario, shape, count, native]
	print("MARCH %s ticks=%d arrived=%d detached=%d reasons=%s" % [context, last_tick, arrived, detached, reasons])
	if arrived != ids.size(): failures.append("%s: only %d/%d reached formation homes" % [context, arrived, ids.size()])
	if detached > 0: failures.append("%s: %d members abandoned the order" % [context, detached])
	if not invalid_positions.is_empty(): failures.append("%s: footprints crossed blocked terrain: %s" % [context, invalid_positions.keys()])
	if not excessive_steps.is_empty(): failures.append("%s: excessive speed or teleport: %s" % [context, excessive_steps.keys()])
	var group = controller.formation_groups.get(int(world.find_unit(ids[0])["formation_group_id"]))
	if group == null or group.deployed_columns != 0: failures.append("%s: preferred formation did not deploy in the open destination" % context)
	world.task_coordinator.shutdown()
