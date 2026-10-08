extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []

class CountingWorld:
	extends "res://scripts/simulation_world.gd"
	var placement_queries := 0
	func get_local_build_sites(team: int, kinds: Array, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
		placement_queries += 1
		return super.get_local_build_sites(team, kinds, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world := CountingWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 22 else "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource_type in range(4): world.set_resource_amount(1, resource_type, 1000)
	world.add_unit(1, "villager", Vector2(10.5, 10.5), false)
	world.add_unit(1, "villager", Vector2(16.5, 12.5), false)
	for y in range(32):
		for x in range(32): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	var expected := world.get_local_build_sites(1, ["house", "dock"], 4, 12)
	world.placement_queries = 0
	var store := Store.new()
	var ai := Ai.new({"team": 1})
	var options := {"compact_entities": true, "include_navigation": false, "include_fog_cells": false, "include_projectiles": false, "include_worker_command_options": false, "requested_build_site_kinds": ["house", "dock"], "defer_build_sites": true, "maximum_build_sites_per_kind": 4, "build_site_cache_ticks": 1200}
	var verifier := Replay.new()
	var before := verifier.world_state_hash(world, 2)
	var snapshot := store.observe_with_queries(world, 2, 1, options)
	check(world.placement_queries == 0 and world.task_coordinator.pending.is_empty(), "owner capture neither searches placements nor submits nested work")
	check(snapshot["build_sites"].is_empty() and snapshot["build_site_queries"].size() == 2, "deferred observation contains explicit searches instead of computed sites")
	var input := Data.seal(Task.capture(ai, snapshot, 10))
	check(is_same(input["snapshot"]["build_site_queries"][0]["input"]["base"], input["snapshot"]["build_site_queries"][1]["input"]["base"]), "multiple kinds share one immutable topology/occupancy capture")
	var output := Task.run(input)
	var actual: Dictionary = {}
	for update in output["build_site_cache_updates"]:
		actual.merge(update["sites"])
	check(actual == expected and world.placement_queries == 0, "worker-only search preserves sequential coast and worker ordering")
	check(verifier.world_state_hash(world, 2) == before, "capture and calculation cannot mutate the live world")
	world.commit_ai_build_site_queries(output["build_site_cache_updates"], 10)
	var cached: Array = world.capture_ai_build_site_queries(1, ["house", "dock"], 11, 1200, 4, 12, {}, [], 0.0)
	check(cached.all(func(query): return query.has("cached_sites") and not query.has("input")), "unchanged results become compact cached queries")
	world.units[0]["pos"] += Vector2(1, 0)
	world.local_build_site_cache.clear()
	world.commit_ai_build_site_queries(output["build_site_cache_updates"], 12)
	check(world.local_build_site_cache.is_empty(), "results captured before worker motion cannot enter the live cache")
	check(Task.run(input) == output, "world motion cannot alter already captured planning input")
	var empty_queries: Array = world.capture_ai_build_site_queries(1, ["dock"], 12, 1200, 4, 12, {}, ["dock"], 0.0)
	var empty_snapshot := snapshot.duplicate()
	empty_snapshot["build_site_queries"] = empty_queries
	var empty_output := Task.run(Data.seal(Task.capture(ai, empty_snapshot, 20)))
	world.commit_ai_build_site_queries(empty_output["build_site_cache_updates"], 20)
	var cached_empty: Array = world.capture_ai_build_site_queries(1, ["dock"], 21, 1200, 4, 12, {}, ["dock"], 0.0)
	check(cached_empty[0].has("cached_sites") and cached_empty[0]["cached_sites"].is_empty(), "failed searches are cached and do not recur every decision")
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
