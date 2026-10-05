extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Knowledge := preload("res://scripts/ai_navigation_knowledge.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var world := World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "land")
	world.add_unit(1, "villager", Vector2(4.5, 4.5), false)
	var fog = world.get_fog_of_war()
	fog.ensure_player(1)
	for y in range(32):
		for x in range(32):
			fog.reveal_explored_cell(1, Vector2i(x, y))
	var knowledge := Knowledge.new()
	var ready := false
	var frames := 0
	while not ready and frames < 33:
		ready = knowledge.prepare_snapshot(world, fog, 1, 32)
		frames += 1
		check(knowledge.last_prepared_cells <= 32, "one preparation slice never exceeds its cell budget")
		if not ready:
			check(not knowledge.entries.has(1), "partial navigation cannot escape into an observation")
	check(ready and frames == 32, "cold full-map preparation is spread over the expected number of frames")
	var first := knowledge.snapshot(world, fog, 1)
	var saved := first.duplicate(true)
	var reference := Knowledge.new()
	check(first == reference.snapshot(world, fog, 1), "budgeted and synchronous reference navigation preserve the same ordering and regions")
	check(first.is_read_only() and first["land"].is_read_only(), "published navigation and all shared buckets are immutable")
	world.navigation_grid.occupy([Vector2i(8, 8)], "building", 80)
	var second := knowledge.snapshot(world, fog, 1)
	check(not second["land"].has(Vector2(8.5, 8.5)) and first["land"].has(Vector2(8.5, 8.5)), "incremental occupancy updates use copy on write")
	check(first == saved, "later navigation updates cannot alter an earlier observation")
	var restarted := Knowledge.new()
	check(not restarted.prepare_snapshot(world, fog, 1, 16), "small budget leaves an explicit pending preparation")
	world.navigation_grid.occupy([Vector2i(12, 12)], "building", 81)
	check(not restarted.prepare_snapshot(world, fog, 1, 16) and int(restarted.pending_preparations[1]["cursor"]) == 16, "source revision change restarts the partial preparation")
	frames = 0
	while not ready_to_finish(restarted, world, fog) and frames < 65:
		frames += 1
	var finished := restarted.snapshot(world, fog, 1)
	check(not finished["land"].has(Vector2(12.5, 12.5)), "restarted preparation includes the latest occupancy")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func ready_to_finish(knowledge, world, fog) -> bool:
	return knowledge.prepare_snapshot(world, fog, 1, 16)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
