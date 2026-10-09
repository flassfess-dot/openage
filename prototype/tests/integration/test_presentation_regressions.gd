extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Hud := preload("res://scripts/hud_view_model.gd")
const Pack := preload("res://scripts/environment_pack.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Picking := preload("res://scripts/picking_service.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Controller := preload("res://scripts/game_controller.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	test_age_icons(catalog)
	test_fish_selection(catalog)
	test_tree_shadow_layers()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Age icons, fish selection and separate tree shadows passed")
	quit(0 if failures.is_empty() else 1)

func configured_world(catalog, civilization: int = 13):
	var world = World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	return world

func test_age_icons(catalog) -> void:
	for civilization in [1, 2, 4, 9, 13, 16]:
		var world = configured_world(catalog, civilization)
		var hud = Hud.new()
		hud.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
		var worker: Dictionary = world.add_unit(1, "villager", Vector2(20, 20), false)
		var house: Dictionary = world.add_building(900, "house", Vector2(5, 5), 1)
		var barracks: Dictionary = world.add_building(901, "barracks", Vector2(12, 5), 1)
		var signature: Variant = null
		for age in range(4):
			if age > 0: world.grant_technology(1, 100 + age)
			var snapshot := Snapshot.with_queries(world, 10, 1)
			var update: Dictionary = hud.build_update(snapshot, [900], "LINE", signature)
			check(update["changed"], "selected House HUD refreshes on age transition")
			signature = update["signature"]
			var house_model: Dictionary = hud.build(snapshot, [900], "LINE")
			var worker_model: Dictionary = hud.build(snapshot, [int(worker["id"])], "LINE")
			var barracks_model: Dictionary = hud.build(snapshot, [901], "LINE")
			var expected_house: int = [15, 16, 17, 18][age]
			var expected_barracks: int = [3, 3, 4, 5][age]
			check(house_model["selection"]["leader"]["icon_id"] == expected_house, "House portrait follows all four ages for civilization %d, age %d" % [civilization, age])
			check(barracks_model["selection"]["leader"]["icon_id"] == expected_barracks, "Barracks portrait follows source replacement and Iron facet")
			for command in worker_model["commands"]:
				if command.get("type") != "build": continue
				if command.get("id") == "house":
					check(command["icon_id"] == expected_house, "construction House icon matches selected building")
					check(command["icon_kind"] == house_model["selection"]["leader"]["icon_kind"], "construction and portrait use the owner's civilization sheet")
				if command.get("id") == "barracks": check(command["icon_id"] == expected_barracks, "construction Barracks icon updates on age research")
			# The observer's age is not the selected building's age; entity changes
			# must invalidate the HUD even when player_state stays unchanged.
			var altered := snapshot.duplicate(true)
			for building in altered["buildings"]:
				if int(building["id"]) == 900: building["presentation_facing"] = int(building.get("presentation_facing", 0)) + 1
			check(hud.build_update(altered, [900], "LINE", signature)["changed"], "entity facet invalidates HUD without a local-player age change")
			var future: Dictionary = world.add_building(910 + age, "house", Vector2(5 + age * 4, 14), 1)
			check(hud._icon_id_for_kind("house", future) == expected_house, "new buildings inherit the same age icon")
		var controller = Controller.new(world)
		var saved: Dictionary = Checkpoint.capture(world, controller, {}, {})
		var restored = configured_world(catalog, civilization)
		var restored_controller = Controller.new(restored)
		check(Checkpoint.restore(saved, restored, restored_controller), "age icon fixture restores successfully")
		var restored_model: Dictionary = hud.build(Snapshot.with_queries(restored, 10, 1), [900], "LINE")
		check(restored_model["selection"]["leader"]["icon_id"] == 18, "saved Iron Age House retains its icon")

func test_fish_selection(catalog) -> void:
	var world = configured_world(catalog)
	var game = load("res://main.gd").new()
	var shore: Dictionary = world.add_scenario_resource("shore_fish", Vector2(8.5, 8.5), 200)
	var deep: Dictionary = world.add_scenario_resource("deep_fish", Vector2(12.5, 8.5), 500)
	var shore_view := Snapshot.compact_render_entity(shore).duplicate(true)
	var deep_view := Snapshot.compact_render_entity(deep).duplicate(true)
	shore_view["entity_type"] = "resource"
	deep_view["entity_type"] = "resource"
	var small: Vector2 = game.unit_selection_radius(shore_view)
	var large: Vector2 = game.unit_selection_radius(deep_view)
	check(large.x >= small.x * 2.0 and large.y >= small.y * 2.0, "sea shoal selection uses its larger DAT radius")
	var original := large
	deep_view["amount"] = 1
	check(game.unit_selection_radius(deep_view) == original, "selection size follows the shoal footprint, not remaining food")
	check(game.unit_selection_center({"screen_position": Vector2(80, 90)}) == Vector2(80, 90), "fish ring stays at the water anchor")
	game.free()

func test_tree_shadow_layers() -> void:
	# Runtime wiring can be tested before the requested deferred asset repack.
	var pack = Pack.new()
	pack.enabled = true
	pack.objects_by_key = {"oak": {"role": "tree", "depleted_key": "stump"}, "stump": {"role": "scenery"}}
	var texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	pack.textures = {"tree.png": texture, "shadow.png": texture, "stump.png": texture}
	pack.manifest = {"objects": {"oak": {"frames": [{"file": "tree.png", "hotspot": [2, 4], "shadow": {"file": "shadow.png", "hotspot": [3, 1]}}]}, "stump": {"frames": [{"file": "stump.png", "hotspot": [1, 1]}]}}}
	var tree := {"id": 42, "kind": "tree", "pos": Vector2(5, 5), "amount": 75, "source_graphic_asset_name": Pack.PREFIX + "oak", "source_frame": 0, "tree_phase": "standing", "visible_when_depleted": true}
	var frame := pack.frame_info(tree, true)
	check(frame["shadow"]["hotspot"] == Vector2(3, 1), "tree shadow keeps its own DAT hotspot")
	var renderer = RenderWorld.new()
	var projection := func(point): return Vector2(point) * 32.0
	var provider := func(_kind, item): return pack.frame_info(item, true)
	var snapshot := {"resources": [tree]}
	var drawables: Array = renderer.create_world_drawables(snapshot, projection, 1.0, provider)
	var shadows: Array = drawables.filter(func(item): return item["kind"] == "resource_shadow")
	check(shadows.size() == 1, "standing tree draws exactly one shadow")
	if not shadows.is_empty():
		check(shadows[0]["layer"] == RenderItem.Layer.SHADOW, "shadow draws below every unit and building")
		check(shadows[0]["world_anchor"] == tree["pos"], "shadow shares the tree's world anchor")
	check(not Picking.SELECTABLE_DRAWABLES.has("resource_shadow"), "shadow never enlarges pointer picking")
	drawables = renderer.create_world_drawables(snapshot, projection, 1.0, provider)
	check(drawables.filter(func(item): return item["kind"] == "resource_shadow").size() == 1, "resource cache reuses the shadow without duplicating it")
	tree["tree_phase"] = "falling"
	drawables = renderer.create_world_drawables(snapshot, projection, 1.0, provider)
	check(drawables.all(func(item): return item["kind"] != "resource_shadow"), "standing canopy shadow disappears when the tree falls")
	tree["tree_phase"] = "stump"
	tree["amount"] = 0
	check(not pack.frame_info(tree, true).has("shadow"), "depleted tree does not retain the canopy shadow")

func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
