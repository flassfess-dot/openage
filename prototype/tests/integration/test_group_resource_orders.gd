extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	for native in [true, false]:
		if native and "--reference-only" in OS.get_cmdline_user_args(): continue
		for kind in ["berries", "tree", "gold_mine", "stone_mine", "deep_fish", "shore_fish", "whale"]:
			var filters := Array(OS.get_cmdline_user_args()).filter(func(arg): return String(arg).begins_with("--kind="))
			if not filters.is_empty() and filters[0] != "--kind=" + kind: continue
			verify_group_cycle(catalog, kind, native)
			if kind == "shore_fish": verify_group_cycle(catalog, kind, native, true)
	for failure in failures:
		push_error(failure)
	print("Group resource orders: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func verify_group_cycle(catalog, kind: String, native: bool, coastal: bool = false) -> void:
	var water := kind in ["deep_fish", "shore_fish", "whale"]
	var world = configured_world(catalog)
	world.gathering_system.native_recovery_enabled = native
	if water:
		var terrain: Array[int] = []
		for y in range(32):
			for x in range(32): terrain.append(1 if x < 24 else 2 if x == 24 else 0)
		world.configure_map_data({"terrain_ids": terrain})
	world.add_building(1001, "dock" if water else "town_center", Vector2(23.5 if water else 21.5, 14.5), 1)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(29.5, 29.5), false)
	enemy["stance"] = "passive"
	var resource: Dictionary = world.add_resource(kind, Vector2(23.5, 21.5) if coastal else Vector2(15.5 if water else 13.5, 14.5), 1000)
	var stock_before: int = world.get_resource_amount(1, int(resource["resource_type_id"]))
	var workers: Array = []
	var ids: Array[int] = []
	for index in range(4 if water else 8):
		var position := Vector2(18.5, 18.5 + float(index) * 2.0) if coastal else Vector2(10.5 if water else 8.5 + float(index / 4) * 0.7, 11.5 + float(index) * 2.0 if water else 12.5 + float(index % 4))
		var worker: Dictionary = world.add_unit(1, "fishing_boat" if water else "villager", position, false)
		workers.append(worker)
		ids.append(int(worker["id"]))
	world.update_fog_of_war()
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	world.set_simulation_seed(41721)
	var persistence := native and not coastal and kind in ["berries", "deep_fish"] and not "--skip-persistence" in OS.get_cmdline_user_args()
	var initial: Dictionary = Checkpoint.capture(world, controller, {}, {"size": world.map_size}) if persistence else {}
	var saved: Dictionary = {}
	var recorder = controller.start_recording(41721) if persistence else null
	var command := Commands.GatherCommand.new(1, ids, int(resource["id"]))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	check(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "%s native=%s: group command accepted" % [kind, native])
	var assigned := workers.filter(func(worker): return worker.get("task", "") == "gather" and int(worker.get("resource_id", -1)) == int(resource["id"]))
	check(assigned.size() == workers.size(), "%s native=%s: assigned %d/%d; %s" % [kind, native, assigned.size(), workers.size(), diagnostics(workers)])
	var peak_active := 0
	for step in range(4000):
		controller.advance_frame(0.05, 1, 2)
		if step == 80:
			var repeated := Commands.GatherCommand.new(controller.tick_index + 1, ids, int(resource["id"]))
			controller.enqueue_command(repeated, true, 1)
			controller.advance_frame(0.05, 1, 2)
			check(bool(controller.get_command_result(repeated.sequence_id).get("accepted", false)), "%s: repeated group order accepted" % kind)
		if step == 400 and persistence:
			saved = Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world, controller, {}, {"size": world.map_size})))
		peak_active = maxi(peak_active, workers.filter(func(worker): return worker.get("gather_stage", "") == "harvesting").size())
		if workers.all(func(worker): return int(worker.get("deposit_cycles", 0)) >= 2): break
	check(peak_active >= 2, "%s native=%s: peak simultaneous harvesting=%d" % [kind, native, peak_active])
	check(workers.all(func(worker): return int(worker.get("deposit_cycles", 0)) >= 2), "%s native=%s: every worker delivers twice; %s" % [kind, native, diagnostics(workers)])
	var carried: float = workers.reduce(func(total, worker): return total + float(worker.get("carried_amount", 0.0)), 0.0)
	check(is_equal_approx(float(world.get_resource_amount(1, int(resource["resource_type_id"])) - stock_before) + carried, 1000.0 - float(resource["amount"])), "%s: harvested cargo and stockpile conserve resources" % kind)
	if persistence:
		var restored = configured_world(catalog)
		var resumed := Controller.new(restored)
		resumed.set_speed_multiplier(1.0)
		check(not saved.is_empty() and Checkpoint.restore(saved, restored, resumed), "%s: active group checkpoint restores" % kind)
		for unused in range(controller.tick_index - resumed.tick_index): resumed.advance_frame(0.05, 1, 2)
		check(Replay.new().world_state_hash(restored, resumed.tick_index, resumed) == Replay.new().world_state_hash(world, controller.tick_index, controller), "%s: active group save/resume preserves the exact state hash" % kind)
		restored.shutdown_derived_state()
	print("Group %s coastal=%s native=%s peak=%d deliveries=%s" % [kind, coastal, native, peak_active, workers.map(func(worker): return int(worker.get("deposit_cycles", 0)))])
	var cycles: Array = workers.map(func(worker): return int(worker.get("gather_cycles", 0)))
	controller.enqueue_command(Commands.StopCommand.new(controller.tick_index + 1, ids), true, 1)
	controller.advance_frame(0.05, 1, 2)
	for unused in range(20): controller.advance_frame(0.05, 1, 2)
	check(world.resource_approach_slots.is_empty(), "%s native=%s: Stop frees every working position" % [kind, native])
	check(workers.map(func(worker): return int(worker.get("gather_cycles", 0))) == cycles and workers.all(func(worker): return worker.get("task") == "idle"), "%s: Stop cannot resume waiting or working gatherers" % kind)
	if persistence:
		var replayed = configured_world(catalog)
		var playback := Controller.new(replayed)
		playback.set_speed_multiplier(1.0)
		check(Checkpoint.restore(initial, replayed, playback) and playback.load_replay(recorder.to_dictionary()), "%s: group replay loads" % kind)
		check(playback.replay_until_tick(controller.tick_index, 1, 2), "%s: every recorded group tick replays without divergence" % kind)
		check(Replay.new().world_state_hash(replayed, playback.tick_index, playback) == Replay.new().world_state_hash(world, controller.tick_index, controller), "%s: group replay preserves the final state hash" % kind)
		replayed.shutdown_derived_state()
	world.shutdown_derived_state()

func configured_world(catalog):
	var world := World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	return world

func diagnostics(workers: Array) -> String:
	var details: Array[String] = []
	for worker in workers:
		details.append("%d task=%s stage=%s cycles=%d deposits=%d pos=%s slot=%s target=%s dest=%s stuck=%d status=%s reason=%s" % [int(worker["id"]), worker.get("task", ""), worker.get("gather_stage", ""), int(worker.get("gather_cycles", 0)), int(worker.get("deposit_cycles", 0)), worker["pos"], worker.get("resource_approach_slot"), worker.get("target"), worker.get("destination"), int(worker.get("stuck_ticks", 0)), worker.get("path_status", ""), worker.get("diagnostic_reason", "")])
	return "; ".join(details)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
