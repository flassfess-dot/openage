extends SceneTree

const Rivers := preload("res://scripts/random_map_rivers.gd")
const Hydro := preload("res://scripts/random_map_hydrology.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Shapes := preload("res://scripts/random_map_world_shapes.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Terrain := preload("res://scripts/environment_terrain.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	verify_mouths(catalog)
	verify_crossings(catalog)
	verify_materials(catalog)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--generated-fixture="):
			verify_generated_world(catalog, argument.trim_prefix("--generated-fixture="))
	for failure in failures: push_error(failure)
	print("River mouths and source fords: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func fields(size: Vector2i, terrain: Array[int]) -> Dictionary:
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	levels.fill(0)
	var moisture := PackedFloat32Array()
	moisture.resize(terrain.size())
	moisture.fill(0.8)
	return {"vertex_levels": levels, "moisture": moisture, "geology": moisture.duplicate(), "coast_distance": Landscape.coast_distances(size, terrain)}

func configured(catalog, size: Vector2i, terrain: Array[int], levels: Array[int]):
	var world := World.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": levels})
	world.add_unit(2, "clubman", Vector2(3.5, 3.5), false)["stance"] = "passive"
	return world

func verify_mouths(catalog) -> void:
	var size := Vector2i(56, 56)
	var original: Array[int] = []
	for y in range(size.y):
		for x in range(size.x): original.append(0 if x >= 2 and x < 38 and y >= 2 and y < 54 else 1)
	var relief := fields(size, original)
	var terrain := original.duplicate()
	var options := {"runoff_threshold": 3.0, "minimum_basin_runoff": 24.0, "width_scale": 0.9, "maximum_radius": 3.8}
	var river := Rivers.carve(size, terrain, relief, options)
	var repeated_terrain := original.duplicate()
	var repeated := Rivers.carve(size, repeated_terrain, relief, options)
	check(terrain == repeated_terrain and river == repeated, "mouth protection is deterministic")
	check(int(river["mouth_count"]) > 0, "fixture contains real drainage outlets")
	for i in range(terrain.size()):
		if original[i] == 1: check(terrain[i] in [1, 22], "river painting preserves the receiving sea's navigability")
		if river["mouth_mask"][i] != 0 and river["mask"][i] != 0:
			check(terrain[i] in [1, 22], "every painted estuary cell is open water, without shoals, bars or fords")
	var world = configured(catalog, size, terrain, relief["vertex_levels"])
	var checked := 0
	for node in river["nodes"]:
		if not node["is_mouth"] or node["downstream"].x < 38: continue
		var goal := Vector2(node["cell"]) + Vector2.ONE * 0.5
		var sea := Vector2(46.5, goal.y)
		for restriction in [3, 6]:
			var path: Array = world.pathfinder.find_path(sea, goal, "water", restriction, 0.5)
			check(not path.is_empty() and Vector2(path.back()).distance_to(goal) < 0.2, "ships reach the river from open sea with full hull clearance")
		var boat: Dictionary = world.add_unit(1, "fishing_boat", sea, false)
		move_to(world, boat, goal, "ship enters a real generated mouth")
		world.begin_entity_death(boat, {"reason": "fixture_complete"})
		checked += 1
		if checked == 3: break
	check(checked > 0, "actual ship movement exercises estuaries")
	world.shutdown_derived_state()

func verify_crossings(catalog) -> void:
	var size := Vector2i(48, 48)
	var terrain: Array[int] = []
	for y in range(size.y):
		for x in range(size.x): terrain.append(1 if x >= 22 and x <= 26 else 0)
	var relief := fields(size, terrain)
	var mask := PackedByteArray()
	mask.resize(terrain.size())
	var types := PackedInt32Array()
	types.resize(terrain.size())
	types.fill(-1)
	for i in range(terrain.size()):
		if terrain[i] == 1:
			mask[i] = 1
			types[i] = 1
	var mouths := PackedByteArray()
	mouths.resize(terrain.size())
	var raw := PackedInt32Array()
	raw.resize(terrain.size())
	var rivers := {"nodes": [{"cell": Vector2i(24, 24), "downstream": Vector2i(24, 25), "mouth_distance": 30, "discharge": 40.0, "bend": 0.0, "head": 20, "downstream_head": 19}],
		"runoff_threshold": 10.0, "mask": mask, "terrain_types": types, "mouth_mask": mouths, "drainage": {"spill_head": raw, "raw_head": raw}}
	var forbidden := rivers.duplicate(true)
	# The center is outside the mouth, but one end of the full crossing is not.
	forbidden["mouth_mask"][24 * size.x + 27] = 1
	check(Hydro._fords(size, terrain, relief, forbidden, [], 41721).is_empty(), "the entire ford footprint must avoid estuaries")
	var strait := {"rivers": forbidden.duplicate(true), "fords": []}
	var strait_terrain := terrain.duplicate()
	Shapes.add_strait_shallows(size, strait_terrain, strait, {"angle": 0.0, "slots": [{"phase": 0.0, "offset": 0.0}]})
	check(strait["fords"].is_empty() and strait_terrain == terrain, "Narrows crossings also leave the whole estuary untouched")
	var fords := Hydro._fords(size, terrain, relief, rivers, [], 41721)
	check(fords.size() == 1, "a gentle middle reach still receives a ford")
	if fords.is_empty(): return
	Rivers.apply(terrain, rivers)
	var world = configured(catalog, size, terrain, relief["vertex_levels"])
	var ford: Dictionary = fords[0]
	for restriction in [3, 6, 7]:
		var domain := "land" if restriction == 7 else "water"
		var native_mask: PackedByteArray = world.navigation_grid.native_walkability_mask(domain, restriction)
		for cell in ford["cells"]:
			check(terrain[cell.y * size.x + cell.x] == Rivers.FORD, "crossing uses native Shallows, not WaterImpassable")
			check(native_mask[cell.y * size.x + cell.x] != 0 and world.navigation_grid.is_walkable_for(cell, domain, restriction), "native and script masks admit infantry and ships on a ford")
	var infantry: Dictionary = world.add_unit(1, "clubman", ford["bank_a"], false)
	move_to(world, infantry, ford["bank_b"], "infantry actually crosses between the banks")
	var boat: Dictionary = world.add_unit(1, "fishing_boat", Vector2(24.5, 18.5), false)
	move_to(world, boat, Vector2(24.5, 30.5), "a ship passes along the river through the ford")
	rivers["mouth_mask"][6 * size.x + 24] = 1
	var data := {"size": size, "terrain_ids": terrain, "vertex_levels": relief["vertex_levels"], "rivers": rivers, "fords": fords,
		"scenery": [{"id": -800000, "asset_name": "aoe2_temperate:ror_shallows", "source_frame": 3, "position": Vector2(24.5, 6.5)}]}
	Hydro.decorate_fords(data, 41721)
	check(not data["scenery"].is_empty(), "ford receives original sandy islets")
	check(not data["scenery"].any(func(item): return item["position"] == Vector2(24.5, 6.5)), "ambient Shallows art cannot make an open mouth look like a ford")
	for item in data["scenery"]:
		check(item["asset_name"] == "aoe2_temperate:ror_shallows" and item["presentation_layer"] == "decal" and not item.has("occupied_cells"), "source ford details stay under units and create no obstacles")
		var spec: Dictionary = Landscape.Decorations.palette().filter(func(entry): return entry["key"] == "ror_shallows")[0]
		for cell in Landscape.Decorations.footprint_cells(spec, int(item["source_frame"]), item["position"]):
			check(terrain[cell.y * size.x + cell.x] in [1, 4, 22], "the whole sandy-islet graphic remains on water")
	world.shutdown_derived_state()

func verify_materials(catalog) -> void:
	check(catalog.enable_environment_pack(), "source environment assets load")
	var pack = catalog.environment_pack
	check(Terrain._material_id(4, pack) != Terrain._material_id(15, pack), "ford and impassable shoal remain visually distinct materials")
	check(pack.has_material(4) and pack.legacy_textures[4] != pack.legacy_textures[1] and pack.legacy_textures[15] != pack.legacy_textures[4], "ford uses its native sandy-islet ground while deep water and submerged shoals retain separate beds")
	var detail: Dictionary = pack.frame_info({"asset_name": "aoe2_temperate:ror_shallows", "source_frame": 3})
	check(detail.get("texture") != null and int(detail.get("graphic_layer", -1)) == 0, "original sandy-islet graphic is available below units")

func verify_generated_world(catalog, path: String) -> void:
	var built: Dictionary = FileAccess.open(path, FileAccess.READ).get_var()
	check(bool(built.get("valid", false)), "rendered control map is valid")
	var data: Dictionary = built["map_data"]
	var size: Vector2i = data["size"]
	var world = configured(catalog, size, data["terrain_ids"], data["vertex_levels"])
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	var definition: Dictionary = built["definition"].duplicate(true)
	for player in definition["players"]:
		player["controller"] = "human"
		player["ai"]["enabled"] = false
	Bootstrap.apply(world, definition, data)
	for actor in world.get_units().duplicate():
		world.release_unit_destination(actor)
		world.detach_unit_for_transport(int(actor["id"]))
	var mouths: PackedByteArray = data["rivers"]["mouth_mask"]
	for i in range(mouths.size()):
		if mouths[i] != 0 and data["rivers"]["terrain_types"][i] >= 0:
			check(data["terrain_ids"][i] in [1, 22], "rendered map keeps all estuaries open")
	var spec: Dictionary = Landscape.Decorations.palette().filter(func(entry): return entry["key"] == "ror_shallows")[0]
	for ford in data["fords"]:
		if data["rivers"]["surface"].get("model_version", 0) >= 1:
			check(preload("res://scripts/random_map_river_surface.gd").sample(data["rivers"]["surface"],(ford["bank_a"]+ford["bank_b"])*0.5).z <= 0.25,"every ford has a continuous submerged gravel ridge")
		else:
			check(data["scenery"].any(func(item): return bool(item.get("ford_detail", false)) and Vector2i(Vector2(item["position"]).floor()) in ford["cells"]), "every rendered ford has a visible sandy-islet detail")
		check(world.navigation_grid.is_segment_walkable_for(ford["bank_a"], ford["bank_b"], 0.3, "land", 7), "every rendered ford joins its banks with infantry clearance")
	for item in data["scenery"]:
		if item.get("asset_name", "") != "aoe2_temperate:ror_shallows": continue
		for cell in Landscape.Decorations.footprint_cells(spec, int(item["source_frame"]), item["position"]):
			var i := cell.y * size.x + cell.x
			check(data["terrain_ids"][i] in [1, 4, 22] and mouths[i] == 0, "rendered ford graphics avoid dry banks and river mouths")
	# The original continental 400/41721 map had WaterImpassable at (118,91),
	# three cells downstream of an apparently open outlet at (118,94).
	if size == Vector2i(400, 400) and int(data["seed"]) == 41721 and String(definition["map"]["generator"]["map_type_id"]) == "continental":
		check(data["terrain_ids"][91 * size.x + 118] in [1, 22], "the original blocked outlet cell is now navigable water")
		var start := Vector2(118.5, 87.5)
		var goal := Vector2(118.5, 94.5)
		for restriction in [3, 6]:
			var path_to_mouth: Array = world.pathfinder.find_path(start, goal, "water", restriction, 0.5)
			check(not path_to_mouth.is_empty() and Vector2(path_to_mouth.back()).distance_to(goal) < 0.2, "both ship restrictions enter the previously blocked 400x400 mouth")
		var boat: Dictionary = world.add_unit(1, "fishing_boat", start, false)
		move_to(world, boat, goal, "ship actually enters the previously blocked 400x400 mouth")
		world.release_unit_destination(boat)
		world.detach_unit_for_transport(int(boat["id"]))
	check(not data["fords"].is_empty(), "rendered control map retains a real ford")
	if not data["fords"].is_empty():
		var ford: Dictionary = data["fords"][0]
		for cell in ford["cells"]:
			check(mouths[cell.y * size.x + cell.x] == 0, "rendered crossing stays outside estuaries")
		var infantry: Dictionary = world.add_unit(1, "clubman", ford["bank_a"], false)
		move_to(world, infantry, ford["bank_b"], "infantry crosses the rendered 400x400 ford")
		world.release_unit_destination(infantry)
		world.detach_unit_for_transport(int(infantry["id"]))
		var axis: Vector2 = (ford["bank_b"] - ford["bank_a"]).normalized()
		var tangent := Vector2(-axis.y, axis.x)
		var center := Vector2(ford["center"]) + Vector2.ONE * 0.5
		var boat: Dictionary = world.add_unit(1, "fishing_boat", center - tangent, false)
		var boat_route:Array=world.pathfinder.find_path(center-tangent,center+tangent,"water",boat["terrain_restriction"],boat["footprint_radius"])
		if boat["pos"].distance_to(center-tangent)<0.1 and not boat_route.is_empty() and Vector2(boat_route[-1]).distance_to(center+tangent)<0.2:
			move_to(world, boat, center + tangent, "a fitting ship crosses the rendered 400x400 ford")
	world.shutdown_derived_state()
	print("Rendered map movement verified: %s seed=%d fords=%d" % [size, int(data["seed"]), data["fords"].size()])

func move_to(world, unit: Dictionary, goal: Vector2, label: String) -> void:
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	controller.enqueue_command(Commands.MoveCommand.new(1, [int(unit["id"])] , goal), true, 1)
	for unused in range(1200):
		controller.advance_frame(0.05, 1, 2)
		if Vector2(unit["pos"]).distance_to(goal) < 0.2: break
	check(Vector2(unit["pos"]).distance_to(goal) < 0.2, "%s: pos=%s goal=%s reason=%s" % [label, unit["pos"], goal, unit.get("diagnostic_reason", "")])

func check(value: bool, message: String) -> void:
	if not value and message not in failures: failures.append(message)
