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
			# These occupancy updates happen in current sight. Explored terrain
			# alone must retain hidden obstacles until they are observed again.
			fog.states_by_player[1][y * 32 + x] = 2
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
	test_sparse_surface_discovery()
	test_surface_split_preserves_reference()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func ready_to_finish(knowledge, world, fog) -> bool:
	return knowledge.prepare_snapshot(world, fog, 1, 16)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func test_sparse_surface_discovery() -> void:
	var world := World.new(Vector2i(400, 400))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.add_unit(1, "villager", Vector2(4.5, 4.5), false)
	var fog = world.get_fog_of_war()
	for y in range(16):
		for x in range(16): fog.reveal_explored_cell(1, Vector2i(x, y))
	var knowledge := Knowledge.new()
	var before := knowledge.snapshot(world, fog, 1)
	var saved := before.duplicate(true)
	fog.reveal_explored_cell(1, Vector2i(16, 4))
	var ready := false
	var portions := 0
	var visited := 0
	while not ready and portions < 10:
		ready = knowledge.prepare_snapshot(world, fog, 1, 256, 0)
		visited += knowledge.last_prepared_cells
		portions += 1
	check(ready and visited <= 5, "one discovery on a sparse 400x400 map visits only changed cells when existing land reachability is unchanged")
	if ready:
		check(knowledge.snapshot(world, fog, 1) == Knowledge.new().snapshot(world, fog, 1), "sparse incremental navigation exactly matches a fresh projection")
	check(before == saved, "surface discovery never mutates an earlier publication")
	world.shutdown_derived_state()


func test_surface_split_preserves_reference() -> void:
	for native in [false, true]:
		var world := World.new(Vector2i(24, 24))
		world.pathfinder.set_native_enabled(native)
		var previous_native: bool = world.navigation_grid.native_masks_enabled
		world.navigation_grid.native_masks_enabled = native
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.add_unit(1, "villager", Vector2(3.5, 4.5), false)
		var fog = world.get_fog_of_war()
		fog.ensure_player(1)
		for y in range(24):
			for x in range(24):
				fog.reveal_explored_cell(1, Vector2i(x, y))
				fog.states_by_player[1][y * 24 + x] = 2
		var knowledge := Knowledge.new()
		var before := knowledge.snapshot(world, fog, 1)
		for y in range(24): world.navigation_grid.set_terrain(Vector2i(12, y), "water")
		var ready := false
		for portion in range(100):
			if knowledge.prepare_snapshot(world, fog, 1, 32, 0):
				ready = true
				break
		check(ready, "surface split finishes bounded preparation")
		var after := knowledge.snapshot(world, fog, 1)
		check(Vector2(20.5, 4.5) in before["reachable"]["land"] and Vector2(20.5, 4.5) not in after["reachable"]["land"], "surface split refreshes distant reachable cells even when the actor component ID stays equal")
		check(after == Knowledge.new().snapshot(world, fog, 1), "surface split preserves all fresh-reference buckets and regions")
		world.shutdown_derived_state()
		world.navigation_grid.native_masks_enabled = previous_native
