extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Ai := preload("res://scripts/ai_player.gd")
var failures: Array[String] = []

class CountingWorld extends World:
	var projection_calls := 0
	func compact_render_projection(entity: Dictionary) -> Dictionary:
		projection_calls += 1
		return super.compact_render_projection(entity)

func _initialize() -> void:
	check(ClassDB.class_exists("RoRReadModelKernel"), "native read-model module is installed")
	test_render_parity()
	test_single_building_projection()
	test_capture_isolation()
	test_shared_movement()
	for failure in failures: push_error(failure)
	print("Read-model optimization checks: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func test_render_parity() -> void:
	var world := World.new(Vector2i(32, 32))
	var entities: Array = [
		world.add_unit(1, "villager", Vector2(4, 4), false),
		world.add_unit(2, "archer", Vector2(8, 8), false),
		world.add_building(800, "town_center", Vector2(16, 16), 1),
		world.add_resource("tree", Vector2(9, 9), 100),
	]
	for entity in entities:
		var previous: Dictionary = {}
		for step in range(12):
			entity["pos"] = Vector2(step, step + 1)
			entity["anim"] = float(step) / 10.0
			entity["hp"] = float(100 - step)
			entity["presentation_state_overrides"] = {"Build": ["builder", step]}
			if step % 2 == 0: entity["environment_variant"] = step
			else: entity.erase("environment_variant")
			var reference := Contract.render_reference(entity)
			var projected := Contract.render(entity, previous)
			check(projected == reference, "native and reference fields match, step %d" % step)
			check(projected.is_read_only() and projected["components"].is_read_only(), "outer and nested projection are readonly")
			check(is_same(projected, Contract.render(entity, projected)), "unchanged projection preserves identity")
			entity["presentation_state_overrides"]["Build"][1] = 999
			check(projected["presentation_state_overrides"]["Build"][1] == step, "published nested values do not alias live data")
			if not previous.is_empty(): check(previous["pos"] != projected["pos"], "old positions remain unchanged")
			previous = projected
	Contract.native_enabled = false
	var fallback := Contract.render(entities[0])
	Contract.native_enabled = true
	check(fallback == Contract.render_reference(entities[0]), "non-native fallback preserves the contract")
	var selected := Snapshot._compact_control_entity(entities[0], 1, Callable(world, "compact_render_projection"))
	selected["components"]["combat"]["cooldown"] = 99
	check(entities[0].get("cooldown", 0) != 99, "selected component views remain detached")
	world.task_coordinator.shutdown()

func test_single_building_projection() -> void:
	var world := CountingWorld.new(Vector2i(32, 32))
	world.add_building(900, "town_center", Vector2(5, 5), 1)
	world.add_building(901, "barracks", Vector2(24, 24), 1)
	world.projection_calls = 0
	var options := {"compact_render_entities": true, "entity_bounds": Rect2(0, 0, 10, 10), "always_include_entity_ids": [900]}
	var view := Snapshot.presentation(world, 1, 1, options)
	check(world.projection_calls == 2, "visible and offscreen building are each projected once, including selected building")
	check(view["buildings"].size() == 1, "offscreen buildings stay out of the detailed view")
	check(world.last_known_buildings_by_player[1].has(901), "offscreen legal building memory is retained")
	world.task_coordinator.shutdown()

func test_capture_isolation() -> void:
	var points: Array[Vector2] = [Vector2.ONE, Vector2.ZERO]
	var topology := {"points": points}
	check(Data.freeze_detached(topology), "prepare a trusted topology")
	var source := {"navigation": topology, "units": [{"id": 1, "pos": Vector2.ONE, "nested": [7]}], "bytes": PackedByteArray([1, 2])}
	var captured := Data.capture_frozen(source)
	check(captured.is_read_only() and captured["units"].is_read_only() and captured["units"][0].is_read_only(), "capture recursively freezes its owned output")
	check(is_same(captured["navigation"], topology), "trusted topology is shared by exact identity")
	source["units"][0]["nested"][0] = 8
	source["bytes"][0] = 9
	check(captured["units"][0]["nested"][0] == 7 and captured["bytes"][0] == 1, "mutable source and packed data stay detached")
	var unsafe := {"units": [{"object": RefCounted.new()}]}
	check(Data.capture_frozen(unsafe).is_empty(), "native capture rejects live objects")
	check(Task.capture(Ai.new({"team": 1}), unsafe, 20).is_empty(), "invalid capture cannot turn into a valid empty AI observation")
	var forged := {Data.SEAL_KEY: 1, "child": {"object": RefCounted.new()}}
	forged.make_read_only()
	check(Data.capture_frozen(forged).is_empty(), "readonly flags and copied markers cannot forge trust")
	var typed: Dictionary[Vector2i, int] = {Vector2i.ONE: 3}
	var native := Data.capture_frozen({"typed": typed, "values": [1, 2]})
	Data.native_capture_enabled = false
	var fallback := Data.capture_frozen({"typed": typed, "values": [1, 2]})
	Data.native_capture_enabled = true
	check(native == fallback and native["typed"].is_same_typed(typed), "fallback and native preserve values and typed dictionaries")
	typed.make_read_only()
	var scalar_map := Data.capture_frozen({"typed": typed})
	check(is_same(scalar_map["typed"], typed), "readonly scalar cell maps stay shared without an identity registry")
	var hot_topology := Data.seal({"cells": {"test": [1, 2, 3]}})
	for index in range(40):
		Data.seal({"other": index})
		var observation := Data.capture_frozen({"navigation": hot_topology, "value": index})
		check(is_same(observation["navigation"], hot_topology), "hot sealed map survives transient publications")

	check(Data.immutable_roots.size() <= Data.MAX_IMMUTABLE_ROOTS, "capture registry remains bounded")

func test_shared_movement() -> void:
	var world := World.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var a: Dictionary = world.add_unit(1, "villager", Vector2(5, 5), false)
	var b: Dictionary = world.add_unit(1, "villager", Vector2(6, 5), false)
	b["terrain_restriction"] = int(a["terrain_restriction"]) + 1
	var planner = world.pathfinder
	planner.prepare_native_movement_snapshot(world.units)
	var legacy_planner = preload("res://scripts/pathfinder.gd").new(world.navigation_grid)
	legacy_planner.incremental_movement_enabled = false
	legacy_planner.prepare_native_movement_snapshot(world.units)
	for unit in world.units:
		var kernel = planner.native_movement_kernels_by_unit_id.get(int(unit["id"]))
		check(kernel != null, "heterogeneous movement mask has a kernel")
		if kernel == null: continue
		var reference = kernel.create_search_context()
		reference.configure_movement_snapshot(legacy_planner.native_movement_ids, legacy_planner.native_movement_positions, legacy_planner.native_movement_radii, legacy_planner.native_movement_clearances, legacy_planner.native_movement_priorities, legacy_planner.native_movement_health, legacy_planner.native_movement_solid_animals)
		var target: Vector2 = unit["pos"] + Vector2(5, 0)
		check(kernel.calculate_movement(unit["id"], target, 1.0, 1.0, 0.05) == reference.calculate_movement(unit["id"], target, 1.0, 1.0, 0.05), "shared collision snapshot matches an independent complete snapshot")
		var retained = kernel.create_search_context()
		retained.share_movement_snapshot(kernel)
		var before = retained.calculate_movement(unit["id"], target, 1.0, 1.0, 0.05)
		kernel.configure_movement_snapshot(PackedInt32Array(), PackedVector2Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(), PackedFloat32Array())
		check(retained.calculate_movement(unit["id"], target, 1.0, 1.0, 0.05) == before, "a new movement publication cannot mutate an earlier shared generation")
	planner.prepare_native_movement_snapshot([])
	check(not planner.has_native_movement_for(a["id"]), "empty world clears native movement lookup")
	world.task_coordinator.shutdown()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
