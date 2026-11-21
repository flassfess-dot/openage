extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Fog := preload("res://scripts/fog_of_war.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
const GAMESPEC := {"units": {"clubman": {"hit_points": 100.0, "line_of_sight": 1.0}}}
var failures: Array[String] = []

func _initialize() -> void:
	for native in [false, true]:
		test_deferred_visibility_survives_checkpoint(native)
		test_full_observer_refresh_keeps_entity_records(native)
	test_direct_unit_tick_initializes_activity()
	for failure in failures: push_error(failure)
	print("Runtime checkpoint visibility: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func make_world() -> World:
	var world := World.new(Vector2i(24, 24))
	# The game creates a world with the current rules before applying a checkpoint.
	world.set_gamespec(GAMESPEC)
	return world

func test_deferred_visibility_survives_checkpoint(native: bool) -> void:
	var world := make_world()
	world.visibility_system.set_native_enabled(native)
	var origin := Vector2(4.5, 4.5)
	var destination := Vector2(12.5, 12.5)
	var unit: Dictionary = world.add_unit(1, "clubman", origin, false)
	unit["components"]["vision"]["range"] = 1.0
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(13.25, 12.5), false)
	world.update_fog_of_war()
	if world.visibility_system.movement_refresh_bucket == int(unit["id"]) % 4: world._tick_fog({})
	world.set_entity_field(unit, "pos", destination)
	world.set_entity_field(unit, "previous_pos", unit["pos"])
	world.set_entity_field(unit, "target", unit["pos"])
	world._tick_fog({})
	check(world.visibility_system.pending_motion.has(int(unit["id"])), "fixture retains deferred source motion")
	check(world.fog_of_war.state_at_world(1, destination) == Fog.UNKNOWN, "deferred source has not revealed its new position")
	var controller := Controller.new(world)
	var data := Checkpoint.unpack(Checkpoint.pack(Checkpoint.capture(world, controller, {}, {"size": world.map_size})))
	var restored := make_world()
	restored.visibility_system.set_native_enabled(native)
	var resumed := Controller.new(restored)
	var loaded := Checkpoint.restore(data, restored, resumed)
	check(loaded, "deferred source checkpoint restores")
	if not loaded:
		world.shutdown_derived_state()
		restored.shutdown_derived_state()
		return
	check(restored.visibility_system.pending_motion == world.visibility_system.pending_motion, "restored source keeps its deferred motion")
	check(restored.visibility_system.movement_refresh_bucket == world.visibility_system.movement_refresh_bucket, "restored visibility resumes on the saved bucket")
	var before := Snapshot.presentation(restored, resumed.tick_index, 1)
	var origin_index := int(origin.y) * world.map_size.x + int(origin.x)
	var destination_index := int(destination.y) * world.map_size.x + int(destination.x)
	check(before["fog"]["cells"][origin_index] == Fog.VISIBLE and before["fog"]["cells"][destination_index] == Fog.UNKNOWN, "first view after loading retains sight at the old position")
	check(not before["units"].any(func(row): return row["id"] == enemy["id"]), "first view after loading keeps the enemy hidden")
	var verifier := Replay.new()
	for tick in range(8):
		world._tick_fog({})
		restored._tick_fog({})
		check(verifier.world_snapshot(world, tick) == verifier.world_snapshot(restored, tick), "restored fog advances on the original bucket without extra revisions (%s tick=%s)" % [native, tick])
	var after := Snapshot.presentation(restored, resumed.tick_index, 1)
	check(after["fog"]["cells"][origin_index] == Fog.EXPLORED and after["fog"]["cells"][destination_index] == Fog.VISIBLE, "updated view moves sight and remembers the old position")
	check(after["units"].any(func(row): return row["id"] == enemy["id"]), "updated view reveals the enemy when sight arrives")
	world.shutdown_derived_state()
	restored.shutdown_derived_state()

func test_full_observer_refresh_keeps_entity_records(native: bool) -> void:
	var world := make_world()
	var index = world.entity_read_index
	index.native_enabled = native
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.5, 4.5), false)
	var first_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.25, 4.5), false)
	var next_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(11.25, 4.5), false)
	world.update_fog_of_war()
	check(index.legal_entities(world, 1, "units") == [unit, first_enemy], "initial observer sees the first enemy (native=%s)" % native)
	var entity_cursor := world.entity_changes.revision
	var fog_cursor := world.fog_of_war.revision_for_player(1)
	world.set_entity_field(unit, "pos", Vector2(10.5, 4.5))
	world.update_fog_of_war()
	# Keep the backing index current while the observer's entity cursor expires.
	for step in range(Journal.MAX_BATCHES + 1):
		world.entity_changes.mark(int(unit["id"]), Journal.APPEARANCE)
		index.synchronize(world)
	var fog_delta := world.fog_of_war.visibility_changes_since(1, fog_cursor)
	check(world.entity_changes.read_changes_since(entity_cursor)["full"] and fog_delta["exact"] and not fog_delta["full"], "observer needs an entity refresh with exact fog changes (native=%s)" % native)
	var visible: Array = index.legal_entities(world, 1, "units")
	check(visible == [unit, next_enemy], "observer refresh replaces the hidden enemy with the visible one (native=%s)" % native)
	check(visible.size() == 2 and is_same(visible[0], unit) and is_same(visible[1], next_enemy), "observer refresh returns the live entity records (native=%s)" % native)
	check(index.in_bounds(Rect2(8, 2, 6, 6), "units") == [unit, next_enemy], "spatial reads still return unit dictionaries (native=%s)" % native)
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
