extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world = World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(cell): return "water" if cell.x >= 22 else "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource_type in range(4): world.set_resource_amount(1, resource_type, 1000)
	world.add_unit(1, "villager", Vector2(10.5, 10.5), false)
	world.add_unit(1, "villager", Vector2(16.5, 12.5), false)
	for y in range(32):
		for x in range(32): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	var codec := Replay.new()
	for gap in [0.0, 2.0]:
		var before := codec.world_state_hash(world, 0)
		var expected: Dictionary = world.get_local_build_sites(1, ["house", "dock"], 4, 12, {}, [], gap)
		world.local_build_site_cache.clear()
		var actual: Dictionary = world.get_cached_local_build_sites(1, ["house", "dock"], 20, 1200, 4, 12, {}, [], gap)
		check(actual == expected, "coast, multi-worker order and structure-gap fallback")
		check(codec.world_state_hash(world, 0) == before, "queries do not alter authoritative state")
	var probe := Probe.new()
	world.set_performance_probe(probe)
	world.local_build_site_cache.clear()
	var request_id: int = world.task_coordinator.next_request_id
	var topology_revision: int = world.pathfinder.task_topology_revision
	var single: Dictionary = world.get_cached_local_build_sites(1, ["house"], 30, 1200, 4, 12)
	check(single == world.get_local_build_sites(1, ["house"], 4, 12), "single-kind early exit preserves exact multi-worker order")
	check(world.task_coordinator.next_request_id == request_id, "single kind avoids speculative worker submissions")
	check(world.pathfinder.task_topology_revision == topology_revision and not probe.report()["metrics_microseconds"].has("presentation.ai.capture.build_sites"), "single kind avoids full topology capture")
	var preferred := {"house": [Vector2(18.5, 10.5), Vector2(19.5, 15.5)]}
	check(world.get_cached_local_build_sites(1, ["house"], 40, 1200, 2, 12, preferred, ["house"]) == world.get_local_build_sites(1, ["house"], 2, 12, preferred, ["house"]), "strict preferred order")
	world.units[1]["pos"] = Vector2(18.5, 10.5)
	check(world.get_cached_local_build_sites(1, ["house"], 60, 1200, 4) == world.get_local_build_sites(1, ["house"], 4), "moving obstruction invalidates result")
	world.fog_of_war.reset()
	check(world.get_cached_local_build_sites(1, ["house", "dock"], 80, 1200).is_empty(), "unknown terrain never leaks sites")
	world.task_coordinator.shutdown()
	finish()
