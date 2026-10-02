extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const ViewModel := preload("res://scripts/hud_view_model.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(Vector2i(80, 80))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_resource_amount(1, 0, 2000)
	world.set_resource_amount(2, 0, 2000)
	world.add_building(80, "town_center", Vector2(50, 50), 1)
	world.add_building(81, "town_center", Vector2(70, 70), 2)
	for index in range(10): world.add_building(100 + index, "house", Vector2(5 + index * 3, 5), 1)
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	assert_true(world.enqueue_unit_production(80, 1, "villager") != null, "own producer starts outside the camera")
	assert_true(world.enqueue_research(80, 1, 101) != null, "research joins the live mixed queue")
	assert_true(world.enqueue_unit_production(81, 2, "villager") != null, "foreign producer is active")
	var options := {"include_production_overview": true, "include_overview": false, "entity_bounds": Rect2(0, 0, 10, 10), "always_include_entity_ids": [80], "command_option_entity_ids": [80]}
	var snapshot: Dictionary = Snapshot.presentation(world, 0, 1, options)
	assert_equal(snapshot["production_overview"].size(), 1, "global production includes only own active producers")
	assert_equal(snapshot["production_overview"][0]["id"], 80, "own out-of-camera producer remains available")
	assert_equal(snapshot["production_overview"][0]["production_queue"].size(), 1, "global projection copies only the active head")
	snapshot["production_overview"][0]["production_queue"][0]["progress"] = 99
	assert_equal(float(world.find_building(80)["production_queue"][0]["progress"]), 0.0, "UI cannot mutate authoritative production")
	snapshot = Snapshot.presentation(world, 0, 1, options)
	var view = ViewModel.new()
	view.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var update: Dictionary = view.build_update(snapshot, [80], "LINE")
	var model: Dictionary = update["model"]
	assert_equal(model["queue"][0]["icon_kind"], "unit", "live unit carries an icon")
	assert_equal(model["queue"][1]["icon_kind"], "technology", "waiting research carries its own icon")
	assert_equal(model["queue"][1]["icon_id"], 65, "waiting research uses original DAT icon")
	world.update_production(1)
	snapshot = Snapshot.presentation(world, 20, 1, options)
	# First tick changes status from queued to training; establish the structural cache.
	update = view.build_update(snapshot, [80], "LINE", update["signature"])
	model = update.get("model", model)
	world.update_production(1)
	snapshot = Snapshot.presentation(world, 40, 1, options)
	var next: Dictionary = view.build_update(snapshot, [80], "LINE", update["signature"])
	assert_true(not bool(next["changed"]), "progress does not rebuild command controls")
	view.refresh_dynamic_model(model, snapshot, [80])
	assert_true(float(model["queue"][0]["progress"]) > 0, "selected producer progress advances")
	assert_equal(model["queue"][0]["progress"], model["global_queue"][0]["progress"], "selected and global progress agree")
	assert_true(float(model["queue"][0]["remaining_seconds"]) < float(model["queue"][0]["duration"]), "remaining time derives from the real order")
	assert_true(world.cancel_production(80, 0), "cancel current unit promotes pending research")
	snapshot = Snapshot.presentation(world, 40, 1, options)
	model = view.build(snapshot, [80], "LINE")
	assert_equal(model["queue"][0]["type"], "research", "live HUD switches to the promoted technology")
	assert_equal(model["global_queue"][0]["icon_kind"], "technology", "global icon changes with the real head")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Live HUD production projection and cache integration passed")
	quit(0 if failures.is_empty() else 1)

func assert_true(value: bool, context: String) -> void:
	if not value: failures.append(context)

func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected: failures.append("%s: expected %s, got %s" % [context, expected, actual])