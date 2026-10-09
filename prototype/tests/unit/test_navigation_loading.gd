extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Loading := preload("res://scripts/navigation_loading.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for threaded in [false, true]:
		var world = World.new(Vector2i(64, 64))
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.add_unit(2, "villager", Vector2(20.5, 20.5), false)
		world.add_resource("tree", Vector2(22.5, 21.5), 100)
		world.update_fog_of_war()
		var loading = Loading.new()
		loading.coordinator.enabled = threaded
		loading.begin(world, [{"team": 1, "controller": "human"}, {"team": 2, "controller": "ai"}, {"team": 3, "controller": "ai", "ai": {"enabled": false}}])
		check(loading.is_loading(), "AI cold data remains behind loading screen")
		var attempts := 0
		while loading.is_loading() and attempts < 1000:
			loading.poll(world)
			attempts += 1
			await process_frame
		check(not loading.is_loading(), "navigation and AI preparation complete")
		check(world.ai_navigation_knowledge.entries.has(2) and not world.ai_navigation_knowledge.entries.has(3), "only enabled AI views are prewarmed")
		check(world.ai_navigation_knowledge.prepare_snapshot(world, world.get_fog_of_war(), 2), "first AI decision needs no cold navigation scan")
		check(world.ai_navigation_knowledge.last_prepared_cells == 0, "first AI decision performs no incremental warmup")
		check(world.prepare_known_ai_resource_snapshot(2) and world.known_resources_by_player[2].has("ai_projection"), "first AI decision needs no cold resource projection")
		loading.shutdown()
		check(loading.pending_ai_teams.is_empty() and not loading.is_loading(), "shutdown clears pending warmup")
		world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print("Navigation loading warmup: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
