extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "compact"
	var built := Settings.build(settings)
	check(bool(built.get("valid", false)), "generated map is valid: %s" % [built.get("errors", [])])
	if not built.get("valid", false):
		finish()
		return
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, built["definition"], built["map_data"])
	var size: Vector2i = built["map_data"]["size"]
	var mask := Navigation.mask(built["map_data"], built["definition"])
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			check((mask[y * size.x + x] != 0) == world.navigation_grid.is_walkable(cell), "generation occupancy matches live navigation")
	var trees: Array = world.get_resources().filter(func(r): return r.get("kind", "") == "tree")
	check(not trees.is_empty(), "trees bootstrap")
	var imported: Array = trees.filter(func(r): return r.has("environment_asset"))
	var native: Array = trees.filter(func(r): return not r.has("environment_asset"))
	check(not imported.is_empty() and not native.is_empty(), "both tree sources survive bootstrap on one map")
	for tree in trees:
		check(not catalog.resource_frame_info(tree).is_empty(), "every tree has native fallback art")
	var before := trees.duplicate(true)
	if catalog.enable_environment_pack():
		for tree in trees:
			var compact: Dictionary = Snapshot._compact_render_entity(tree)
			var info: Dictionary = catalog.resource_frame_info(compact)
			var depleted: Dictionary = compact.duplicate(true)
			depleted["amount"] = 0
			if tree.has("environment_asset"):
				check(compact.get("environment_asset") == tree["environment_asset"] and compact.get("environment_variant") == tree["environment_variant"], "render snapshot retains imported species and variant")
				check(String(info.get("asset_name", "")).begins_with("aoe2_temperate:"), "imported tree art resolves through real rendering")
				check(catalog.resource_frame_info(depleted).get("asset_name", "") == "aoe2_temperate:stump", "imported trees use imported stumps")
			else:
				check(info.get("asset_name", "") == tree["source_graphic_asset_name"], "enabled pack preserves native tree art")
				check(catalog.resource_frame_info(depleted).get("asset_name", "") == "tree_stump", "native trees use native stumps")
		check(trees == before, "resolving mixed presentation cannot mutate simulation identity")

	# Exercise the gameplay path, including retained fog memory and optional
	# publication. Testing _compact_render_entity alone missed the forest loss.
	var generated_trees: Array = built["map_data"]["resources"].filter(func(r): return r.get("category", "") == "resource" and r.get("kind", "") == "tree")
	check(trees.size() == generated_trees.size(), "generation and bootstrap retain exactly the same tree density")
	var fog = world.get_fog_of_war()
	fog.ensure_player(1)
	fog.states_by_player[1].fill(2)
	fog.revisions_by_player[1] += 1
	fog.exploration_revisions_by_player[1] += 1
	fog.revision += 1
	var coordinator = preload("res://scripts/isolated_task_coordinator.gd").new()
	var publication = preload("res://scripts/presentation_publication.gd").new()
	var by_id := {}
	for tree in trees: by_id[tree["id"]] = tree
	for threaded in [false, true]:
		coordinator.subsystem_enabled["presentation"] = threaded
		for tick in range(3):
			var captured := Snapshot.with_queries(world, tick, 1, {"compact_render_entities": true, "borrow_visible_render_entities": true, "include_navigation": false, "include_build_sites": false})
			var published: Dictionary = publication.publish(captured, [], coordinator)
			var visible_trees: Array = published["resources"].filter(func(r): return r.get("kind", "") == "tree")
			check(visible_trees.size() == trees.size(), "full explored forest reaches gameplay presentation without thinning")
			for tree in visible_trees:
				var original: Dictionary = by_id[tree["id"]]
				check(tree["pos"] == original["pos"], "gameplay preserves generated forest placement")
				for field in ["environment_asset", "environment_variant", "tree_condition"]:
					check(tree.get(field) == original.get(field), "retained fog memory preserves tree metadata: " + field)
				var expected := catalog.resource_frame_info(original)
				var actual := catalog.resource_frame_info(tree)
				check(actual.get("asset_name") == expected.get("asset_name") and actual.get("frame_index") == expected.get("frame_index"), "every published tree uses the exact generated artwork")
	coordinator.shutdown()
	world.task_coordinator.shutdown()
	finish()

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Generated environment presentation and live occupancy passed")
	quit(0 if failures.is_empty() else 1)
