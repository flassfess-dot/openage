extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
var failures: Array[String] = []

func _initialize() -> void:
	for native in [false, true]: test_deferred_visibility_survives_checkpoint(native)
	test_full_observer_refresh_keeps_entity_records()
	test_direct_unit_tick_initializes_activity()
	for failure in failures: push_error(failure)
	print("Runtime checkpoint visibility: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func test_deferred_visibility_survives_checkpoint(native: bool) -> void:
	var world := World.new(Vector2i(24, 24))
	world.set_gamespec({"units": {"clubman": {"hit_points": 100.0, "line_of_sight": 1.0}}})
	world.visibility_system.set_native_enabled(native)
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.5, 4.5), false)
	unit["components"]["vision"]["range"] = 1.0
	world.add_unit(2, "clubman", Vector2(21.5, 21.5), false)["stance"] = "passive"
	world.update_fog_of_war()
	if world.visibility_system.movement_refresh_bucket == int(unit["id"]) % 4: world._tick_fog({})
	world.set_entity_field(unit, "pos", Vector2(12.5, 12.5))
	world.set_entity_field(unit, "previous_pos", unit["pos"])
	world.set_entity_field(unit, "target", unit["pos"])
	world._tick_fog({})
	check(world.visibility_system.pending_motion.has(int(unit["id"])), "fixture retains deferred source motion")
	check(world.fog_of_war.state_at_world(1, unit["pos"]) == 0, "deferred source has not revealed its new position")
	var controller := Controller.new(world)
	var data := Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world, controller, {}, {"size": world.map_size})))
	var restored := World.new(world.map_size)
	restored.visibility_system.set_native_enabled(native)
	var resumed := Controller.new(restored)
	check(Checkpoint.restore(data, restored, resumed), "deferred source checkpoint restores")
	check(restored.visibility_system.pending_motion.has(int(unit["id"])), "restored source keeps its deferred motion")
	var verifier := Replay.new()
	for tick in range(8):
		world._tick_fog({})
		restored._tick_fog({})
		check(verifier.world_snapshot(world, tick) == verifier.world_snapshot(restored, tick), "restored fog advances on the original bucket without extra revisions (%s tick=%s)" % [native, tick])
	check(restored.fog_of_war.state_at_world(1, unit["pos"]) == 2, "deferred source eventually reveals its new position")
	world.shutdown_derived_state()
	restored.shutdown_derived_state()

func test_full_observer_refresh_keeps_entity_records() -> void:
	var world := World.new(Vector2i(24, 24))
	world.set_gamespec({"units": {"clubman": {"hit_points": 100.0, "line_of_sight": 1.0}}})
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.5, 4.5), false)
	world.update_fog_of_war()
	var index = world.entity_read_index
	index.legal_entities(world, 1, "units")
	# The entity history may overflow while an observer has exact fog changes.
	world.set_entity_field(unit, "pos", Vector2(10.5, 4.5))
	world.update_fog_of_war()
	for step in range(Journal.MAX_BATCHES + 1):
		world.entity_changes.mark(int(unit["id"]), Journal.APPEARANCE)
		world.entity_changes.flush()
	check(index.legal_entities(world, 1, "units") == [unit], "overflow observer refresh retains the legal unit")
	check(is_same(index.entities[int(unit["id"])], unit), "candidate ID sets never overwrite live entity records")
	check(index.in_bounds(Rect2(8, 2, 6, 6), "units") == [unit], "spatial reads still return dictionaries after observer refresh")
	world.shutdown_derived_state()

func test_direct_unit_tick_initializes_activity() -> void:
	var world := World.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.5, 4.5), false)
	for tick in range(20): world.update_units(0.05, 1, 2)
	check(world.unit_activity_registry.source_journal == world.entity_changes, "public unit updates bind the appearance journal before idle animation")
	check(float(unit["anim"]) > 0.0 and unit["pos"] == Vector2(4.5, 4.5), "direct idle updates advance animation without moving the actor")
	world.shutdown_derived_state()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
