extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Journal := preload("res://scripts/cell_change_journal.gd")
const Dependency := preload("res://scripts/cache_dependency.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
var failures: Array[String] = []

func _initialize() -> void:
	test_journal()
	test_domains()
	test_fog_consumers()
	test_checkpoint_cursors()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func test_journal() -> void:
	var history: Array = []
	Journal.record_cell(history, 0, Vector2i(2, 3))
	Journal.record_cell(history, 1, Vector2i(9, 8))
	var change := Journal.delta(history, 0, 2)
	check(not change["full"] and change["exact"] and change["cells"].size() == 2, "contiguous changes retain exact cells")
	check(change["region"].has_point(Vector2(2, 3)) and change["region"].has_point(Vector2(9, 8)), "region covers distant edits")
	check(change == Journal.delta(history, 0, 2), "reading a journal never consumes another consumer's changes")
	Journal.record_cell(history, 4, Vector2i.ONE)
	check(Journal.delta(history, 2, 5)["full"], "a missing revision requires a full refresh")
	check(Journal.delta(history, 6, 5)["full"], "revision regression requires a full refresh")
	history.clear()
	for revision in range(6):
		Journal.record_cell(history, revision, Vector2i(revision, 0), 3)
	check(history.size() == 3 and Journal.delta(history, 0, 6)["full"], "bounded history cannot authorize stale cache reuse")
	check(not Journal.delta(history, 3, 6)["full"], "retained contiguous suffix still supports incremental refresh")
	history.clear()
	for index in range(Journal.MAX_CELLS_PER_ENTRY + 1):
		Journal.record_cell(history, 0, Vector2i(index, 0))
	change = Journal.delta(history, 0, 1)
	check(not change["full"] and not change["exact"] and change["region"].size.x > 512, "large batch preserves bounded region but rejects incomplete cell list")
	Journal.record_full(history, 1, 2)
	check(Journal.delta(history, 1, 2)["full"], "explicit bulk invalidation requires a full refresh")

func test_domains() -> void:
	var world := World.new(Vector2i(16, 16))
	var geometry := Dependency.stamp(world, Dependency.TERRAIN_GEOMETRY)
	var surface := Dependency.stamp(world, Dependency.TERRAIN_SURFACE)
	var tree := {"kind": "tree", "pos": Vector2(5.5, 6.5)}
	world.register_forest_resource(tree)
	var change := world.cache_changes(Dependency.TERRAIN_SURFACE, surface)
	check(not change["full"] and change["cells"] == [Vector2i(5, 6)], "forest surface mutation emits its real cell")
	check(Dependency.stamp(world, Dependency.TERRAIN_GEOMETRY) == geometry, "surface mutation does not invalidate height geometry")
	world.terrain_elevation.set_vertex(Vector2i(5, 6), 1)
	change = world.cache_changes(Dependency.TERRAIN_GEOMETRY, geometry)
	check(not change["full"] and change["exact"] and change["cells"].size() == 4, "height vertex invalidates four adjacent tiles")
	check(change["cells"].has(Vector2i(5, 6)) and change["cells"].has(Vector2i(4, 5)), "height delta includes both sides of its vertex")
	geometry = Dependency.stamp(world, Dependency.TERRAIN_GEOMETRY)
	world.terrain_elevation.set_vertex(Vector2i(5, 6), 1)
	check(not world.cache_changes(Dependency.TERRAIN_GEOMETRY, geometry)["full"] and world.cache_changes(Dependency.TERRAIN_GEOMETRY, geometry)["cells"].is_empty(), "unchanged height produces no invalidation")
	var other := World.new(Vector2i(16, 16))
	check(other.cache_changes(Dependency.TERRAIN_SURFACE, Dependency.stamp(world, Dependency.TERRAIN_SURFACE))["full"], "new source with coincident revisions cannot reuse old cache")
	var topology := Dependency.stamp(world, Dependency.NAVIGATION_TOPOLOGY)
	world.navigation_grid.occupy([Vector2i(3, 3)], "building", 100)
	check(world.cache_changes(Dependency.NAVIGATION_TOPOLOGY, topology)["cells"] == [Vector2i(3, 3)], "navigation shares the exact-cell contract")
	world.navigation_grid.configure_terrain()
	check(world.cache_changes(Dependency.NAVIGATION_TOPOLOGY, topology)["full"], "full terrain reconfiguration invalidates navigation explicitly")

func test_fog_consumers() -> void:
	var world := World.new(Vector2i(16, 16))
	var fog = world.get_fog_of_war()
	fog.ensure_player(1)
	var visibility := Dependency.stamp(world, Dependency.FOG_VISIBILITY, 1)
	var exploration := Dependency.stamp(world, Dependency.FOG_EXPLORATION, 1)
	fog.consume_presentation_dirty_cells(1)
	fog.reveal_explored_cell(1, Vector2i(7, 7))
	var first := world.cache_changes(Dependency.FOG_VISIBILITY, visibility, 1)
	fog.consume_presentation_dirty_cells(1)
	var second := world.cache_changes(Dependency.FOG_VISIBILITY, visibility, 1)
	check(first == second and first["cells"] == [Vector2i(7, 7)], "legacy queue consumption cannot steal another visibility cache's delta")
	check(world.cache_changes(Dependency.FOG_EXPLORATION, exploration, 1)["cells"] == [Vector2i(7, 7)], "navigation has an independent exploration history")
	fog.reset()
	fog.ensure_player(1)
	check(world.cache_changes(Dependency.FOG_VISIBILITY, visibility, 1)["full"], "fog reset invalidates same-source cursor even with coincident revision")
	check(world.cache_changes(Dependency.FOG_VISIBILITY, visibility, 2)["full"], "observer identity is part of cache dependency")

func test_checkpoint_cursors() -> void:
	var world := World.new(Vector2i(16, 16))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(4.5, 4.5), false)
	var controller := Controller.new(world)
	var data := Checkpoint.capture(world, controller, {}, {"size": world.map_size})
	var surface := Dependency.stamp(world, Dependency.TERRAIN_SURFACE)
	var topology := Dependency.stamp(world, Dependency.NAVIGATION_TOPOLOGY)
	var visibility := Dependency.stamp(world, Dependency.FOG_VISIBILITY, 1)
	var saved_health := float(worker["hp"])
	# Simulate the redundant component fields present in an older checkpoint.
	data["world"]["units"][0]["components"]["health"]["current"] = -99.0
	data["world"]["units"][0]["components"]["transform"]["position"] = Vector2(99, 99)
	check(Checkpoint.restore(data, world, controller), "compatible checkpoint restores into an existing world")
	var restored: Dictionary = world.find_unit(int(worker["id"]))
	check(float(restored["hp"]) == saved_health and not restored["components"]["health"].has("current") and not restored["components"]["transform"].has("position"), "checkpoint import removes old dynamic mirrors without changing authoritative values")
	check(world.cache_changes(Dependency.TERRAIN_SURFACE, surface)["full"] and world.cache_changes(Dependency.NAVIGATION_TOPOLOGY, topology)["full"], "same-object checkpoint restore invalidates coincident terrain/navigation cursors")
	check(world.cache_changes(Dependency.FOG_VISIBILITY, visibility, 1)["full"], "same-object checkpoint restore invalidates visibility cursors")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
