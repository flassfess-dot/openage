extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Footprint := preload("res://scripts/footprint.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	for frame in [1, 16, 38, 255]:
		_check(catalog.get_terrain_border_texture(8, frame) != null, "source-derived coast frame %d resolves in source and exported games" % frame)
	_test_state_loading(catalog)
	_test_projection_retirement()
	_test_production_refresh(catalog)
	_test_placement_boundaries(catalog)
	if failures.is_empty():
		print("Long-session performance contracts passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_state_loading(catalog) -> void:
	var unit := {"kind": "clubman", "team": 1, "source_unit_id": 73, "facing": 0, "anim": 0.0}
	var registry = catalog.unit_presentations
	var idle: Dictionary = registry.frame_info(unit, "idle")
	_check(idle.get("texture") != null, "first idle frame exists")
	_check(registry.textures["clubman"].keys() == ["idle"], "first frame does not decode unrelated attack/move/death clips")
	var move: Dictionary = registry.frame_info(unit, "move")
	_check(move.get("texture") != null, "new state loads on demand")
	_check(not registry.textures["clubman"].has("death"), "unused death animation stays unloaded")
	_check(registry.frame_info(unit, "idle")["texture"] == idle["texture"], "loading another state retains existing texture identity")
	_check(registry.frame_info(unit, "missing_state")["texture"] == idle["texture"], "missing states still fall back to idle")
	registry.ensure_loaded("clubman")
	_check(registry.animation_frames("clubman", "death").size() == 50, "explicit complete loading preserves all death frames")
	_check(registry.frame_info(unit, "idle")["texture"] == idle["texture"], "complete loading preserves already loaded states")

func _test_projection_retirement() -> void:
	var world := World.new(Vector2i(24, 24))
	var retained: Dictionary = {}
	for index in range(160):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(3.5, 3.5), false)
		retained = world.compact_render_projection(unit)
		unit["removed"] = true
		world.unit_removal_pending = true
		world.purge_removed_units()
	_check(world.render_entity_projection_cache.projections_by_id.is_empty(), "repeated unit retirement does not accumulate projections")
	_check(world.render_entity_projection_cache.categories_by_id.is_empty(), "projection categories are retired too")
	_check(retained.has("id"), "published snapshot remains readable after cache eviction")
	var building: Dictionary = world.add_building(9000, "house", Vector2(12.5, 12.5), 1)
	world.compact_render_projection(building)
	building["removed"] = true
	world.building_removal_pending = true
	world.purge_removed_units()
	_check(world.render_entity_projection_cache.projections_by_id.is_empty(), "removed buildings release projections")

	var passenger: Dictionary = world.add_unit(1, "clubman", Vector2(3.5, 3.5), false)
	world.compact_render_projection(passenger)
	world.detach_unit_for_transport(int(passenger["id"]))
	_check(world.render_entity_projection_cache.projections_by_id.is_empty(), "embarked units release render projections")
	passenger["pos"] = Vector2(8.5, 8.5)
	world.restore_unit_from_transport(passenger)
	_check(world.compact_render_projection(passenger)["pos"] == passenger["pos"], "unloading recreates a current projection")

func _test_production_refresh(catalog) -> void:
	var world := _world(catalog)
	var building: Dictionary = world.add_building(900, "town_center", Vector2(12.5, 12.5), 1)
	var options: Array = world.get_unit_production_options(900, 1)
	_check(not options.is_empty(), "producer index finds town center units")
	_check(options == world.get_unit_production_options(900, 1), "warm and cold producer queries agree")
	for resource in range(4):
		world.set_resource_amount(1, resource, 0)
	var poor: Array = world.get_unit_production_options(900, 1)
	_check(not poor.is_empty() and not poor.any(func(option): return bool(option.get("accepted", false))), "resource spending is reflected without rebuilding producer index")
	world.set_resource_amount(1, 0, 1000)
	_check(world.get_unit_production_options(900, 1).any(func(option): return bool(option.get("accepted", false))), "resource income refreshes availability")
	var research: Array = world.get_research_options(900, 1)
	_check(research == world.get_research_options(900, 1), "warm and cold research queries agree")
	building["state"] = "foundation"
	_check(not world.get_unit_production_options(900, 1).any(func(option): return bool(option.get("accepted", false))), "foundation state is evaluated live")
	building["state"] = "complete"
	# Catalog replacement must invalidate both static indices, including empty results.
	var replacement: Dictionary = catalog.runtime_catalog_data.duplicate(true)
	replacement["archetypes"]["villager"]["runtime"]["train_location_unit_id"] = 123456
	world.set_runtime_catalog(replacement)
	_check(not world.get_unit_production_options(900, 1).any(func(option): return option.get("kind") == "villager"), "runtime catalog replacement invalidates unit location index")
	var replaced_objects: Dictionary = catalog.object_catalog_data.duplicate(true)
	for record in replaced_objects.get("technologies", {}).values():
		record["research_location_id"] = 123456
	world.set_object_catalog(replaced_objects)
	_check(world.get_research_options(900, 1).is_empty(), "object catalog replacement invalidates research index")

func _test_placement_boundaries(catalog) -> void:
	var world := _world(catalog)
	var center := Vector2(12.5, 12.5)
	var unit: Dictionary = world.add_unit(1, "villager", center, false)
	world.update_fog_of_war()
	var occupied: Array = Footprint.building(world.unit_stats("house"), center)["occupied_cells"]
	# Compare the conservative rejection with the original five-point overlap
	# rule, including exact cell edges, near-edge radii, and diagonal misses.
	for radius in [0.0, 0.3, 0.6, 1.0]:
		unit["footprint_radius"] = radius
		for x in [9.0, 10.7, 11.0, 11.7, 12.0, 12.5, 13.0, 13.7, 14.0, 14.3, 15.0]:
			for y in [10.7, 11.0, 12.5, 14.0, 14.3]:
				unit["pos"] = Vector2(x, y)
				var overlaps: bool = world.mobile_footprint_overlaps_cells(unit, occupied)
				var accepted: bool = world.can_place_foundation(1, "house", center)
				_check(accepted == not overlaps, "placement overlap parity at %s radius=%s" % [unit["pos"], radius])
	unit["pos"] = center
	unit["hp"] = 0.0
	_check(world.can_place_foundation(1, "house", center), "dead units do not obstruct construction")

func _world(catalog) -> World:
	var world := World.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for resource in range(4):
		world.set_resource_amount(1, resource, 1000)
	return world

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
