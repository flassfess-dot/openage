extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	test_original_death_assets(catalog)
	test_death_lifecycle(catalog)
	test_building_death_lifecycle(catalog)

	if failures.is_empty():
		print("S-005 death lifecycle tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_death_assets(catalog) -> void:
	assert_equal(catalog.unit_animation_frames("clubman", "death").size(), 50, "all original clubman death direction frames loaded")
	assert_equal(catalog.unit_animation_frames("clubman", "corpse").size(), 30, "all original clubman corpse direction frames loaded")
	assert_equal(catalog.unit_animation_frames("enemy_archer", "death").size(), 50, "enemy death frames preserve player palette")
	var corpse_graphic: Dictionary = catalog.graphics_catalog_data.get("graphics", {}).get("138", {})
	assert_equal(int(corpse_graphic.get("frames_per_angle", 0)), 6, "corpse descriptor comes from original dead-unit graphic")
	assert_float(float(corpse_graphic.get("frame_rate", 0.0)), 15.0, "original corpse frame lifetime retained")


func test_death_lifecycle(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	var survivor: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var victim: Dictionary = world.add_unit(2, "clubman", Vector2(7.0, 7.0), true)
	world.assign_command_move([victim], Vector2(9.0, 9.0))
	victim["formation_group_id"] = 12
	victim["formation_slot_id"] = 3
	victim["formation_home"] = Vector2(8.0, 8.0)
	assert_equal(world.get_population(2), 1, "living original unit consumes one population")
	assert_true(victim["reserved_destination"] is Vector2, "moving unit owns a destination reservation")
	assert_float(float(victim["death_duration"]), 1.0, "death duration uses original ten frames at 0.1 seconds")
	assert_float(float(victim["corpse_duration"]), 90.0, "corpse lifetime uses original six frames at fifteen seconds")

	victim["hp"] = 0.0
	world.advance(0.05, 1, 2)
	assert_equal(victim["death_phase"], "dying", "lethal health starts death phase")
	assert_equal(victim["anim_state"], AnimationController.DIE, "death animation state starts")
	assert_equal(victim["task"], "die", "dead unit leaves its previous order")
	assert_true(not victim["selected"], "dead unit is deselected")
	assert_equal(victim["reserved_destination"], null, "destination reservation released")
	assert_equal(victim["formation_group_id"], -1, "formation membership released")
	assert_equal(victim["formation_slot_id"], -1, "formation slot released")
	assert_equal(world.get_population(2), 0, "population released at death start")
	assert_true(not bool(victim["components"]["health"]["alive"]), "Health component becomes non-living")
	assert_equal(world.query_units_near(victim["pos"], 0.5).filter(func(unit): return unit["id"] == victim["id"]).size(), 0, "dead unit excluded from target spatial index")
	assert_true(world.is_battle_over(), "last enemy death updates victory condition")

	var renderer = RenderWorld.new()
	var dying_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(dying_items.filter(func(item): return item["kind"] == "unit" and item["stable_id"] == victim["id"]).size(), 1, "dying body remains rendered")
	assert_equal(dying_items.filter(func(item): return item["kind"] in ["selection", "health_bar"] and item["stable_id"] == victim["id"]).size(), 0, "dead body has no selection or health UI")

	world.advance(float(victim["death_duration"]), 1, 2)
	assert_equal(victim["death_phase"], "corpse", "death graphic transitions to corpse")
	assert_equal(victim["anim_state"], AnimationController.DECAY, "corpse uses decay state")
	assert_true(bool(victim["animation_events_fired"].get("death_complete_frame", false)), "death completion event is recorded")
	var corpse_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(corpse_items.filter(func(item): return item["kind"] == "unit" and item["stable_id"] == victim["id"]).size(), 1, "corpse remains rendered")
	assert_equal(corpse_items.filter(func(item): return item["kind"] == "shadow" and item["stable_id"] == victim["id"]).size(), 0, "corpse does not receive a duplicate primitive shadow")

	victim["corpse_duration"] = 0.1
	world.advance(0.11, 1, 2)
	assert_equal(world.find_unit(int(victim["id"])), null, "expired corpse removed from world")
	assert_equal(world.get_population(2), 0, "population is not released twice")
	assert_true(world.find_unit(int(survivor["id"])) != null, "living units survive corpse cleanup")


func test_building_death_lifecycle(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var town_center: Dictionary = world.add_building(42, "town_center", Vector2(10.0, 10.0), 1)
	var center_cell := Vector2i(10, 10)
	assert_true(not world.navigation_grid.is_walkable(center_cell), "living building reserves its navigation footprint")
	assert_float(float(town_center["death_duration"]), 0.465000011026859, "building death duration comes from the original ten-frame graphic")

	world.begin_event_capture()
	world.begin_building_destruction(town_center)
	world.begin_building_destruction(town_center)
	world.end_event_capture()
	var death_events: Array = world.drain_domain_events().filter(func(event): return event["type"] == "death")
	assert_equal(death_events.size(), 1, "building death transition emits exactly one event")
	assert_equal(town_center["death_phase"], "dying", "destroyed building enters a visible death phase")
	assert_equal(town_center["state"], "destroyed", "destroyed building leaves the completed state")
	assert_true(not bool(town_center["removed"]), "destroyed building is retained until its animation completes")
	assert_true(world.navigation_grid.is_walkable(center_cell), "destroyed building releases its navigation footprint immediately")

	var death_frame: Dictionary = catalog.building_frame_info(town_center, 0.0)
	assert_equal(int(death_frame.get("graphic_id", -1)), 492, "Town Center uses its original destruction graphic")
	var death_part_ids: Array[int] = []
	for part in death_frame.get("composite_parts", []):
		death_part_ids.append(int(part.get("graphic_id", -1)))
	assert_true(death_part_ids.has(495), "Town Center destruction includes the original rubble layer")
	var renderer = RenderWorld.new()
	var dying_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(dying_items.filter(func(item): return item["kind"] == "building" and item["stable_id"] == town_center["id"]).size(), 1, "dying building remains rendered")

	world.advance(float(town_center["death_duration"]), 1, 2)
	assert_equal(town_center["death_phase"], "ruin", "destruction animation leaves temporary rubble")
	assert_true(world.find_building(int(town_center["id"])) != null, "rubble remains visible after destruction animation")
	var ruin_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(ruin_items.filter(func(item): return item["kind"] == "building" and item["stable_id"] == town_center["id"]).size(), 1, "temporary rubble stays rendered without blocking movement")
	world.advance(8.01, 1, 2)
	assert_equal(world.find_building(int(town_center["id"])), null, "rubble disappears after its visible lifetime")

	var house: Dictionary = world.add_building(43, "house", Vector2(14.0, 14.0), 1)
	world.begin_building_destruction(house)
	var house_death: Dictionary = catalog.building_frame_info(house, 0.0)
	assert_equal(int(house_death.get("graphic_id", -1)), 491, "House uses the small-building destruction graphic")
	assert_true(house_death.get("composite_parts", []).any(func(part): return int(part.get("graphic_id", -1)) == 494), "House destruction includes the small rubble layer")


func fake_frame_info(_kind: String, _data: Variant) -> Dictionary:
	return {"frame_index": 0, "hotspot": Vector2(8, 20), "mirrored": false}


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
