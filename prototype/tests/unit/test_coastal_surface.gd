extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Terrain := preload("res://scripts/environment_terrain.gd")
const Renderer := preload("res://scripts/terrain_renderer.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
var failures: Array[String] = []

func _initialize() -> void:
	if not FileAccess.file_exists("res://assets/generated/environment/aoe2_temperate/manifest.json"):
		_test_reported_map()
		check("--require-pack" not in OS.get_cmdline_user_args(), "required coastal art pack is missing")
		print("Coastal rendering checks skipped: optional AoE2 pack not installed")
		_finish()
		return
	var catalog := Catalog.new()
	catalog.load()
	if not catalog.enable_environment_pack():
		push_error("Coastal surface regression requires the imported environment pack")
		quit(1)
		return
	_test_native_materials(catalog)
	_test_shared_edges(catalog)
	_test_coast_shapes(catalog)
	_test_reported_map()
	_finish()

func _finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Continuous coasts, wet shallows, material seams and reported seed passed")
	quit(0 if failures.is_empty() else 1)

func _test_native_materials(catalog) -> void:
	var elevation := Elevation.new(Vector2i(4, 4))
	for id in [0, 1, 2, 4, 22, 1000, 1001, 1002, 1003]:
		var provider := func(_cell): return id
		var tile: Dictionary = Renderer.tile_drawable(Vector2i.ONE, id, provider, catalog, elevation, 1.0, Vector2.ZERO, 41689)
		check(tile.has("mesh_layers"), "every coastal material uses the same geometric surface")
		check(tile["mesh_layers"].size() == 1, "uniform surfaces retain the inexpensive single-material mesh")
		check(tile["borders"].is_empty(), "opaque old corner tiles cannot overwrite continuous coastlines")
		for layer in tile["mesh_layers"]:
			for point in layer["points"]: check(point.is_finite(), "coastal mesh is finite")
	var pack = catalog.environment_pack
	for id in [0, 1, 4, 6, 22]: check(not pack.legacy_textures[id].get_image().detect_alpha(), "native bridge atlases are opaque")
	var water: Image = pack.legacy_textures[1].get_image()
	var shallow: Image = pack.legacy_textures[4].get_image()
	var sand: Image = pack.legacy_textures[6].get_image()
	check(shallow.get_data() != sand.get_data() and shallow.get_data() != water.get_data(), "shallows show submerged soil, distinguishable from both dry beach and open water")
	for y in range(0, 96, 12):
		for x in range(0, 96, 12):
			var a := shallow.get_pixel(x, y)
			var b := water.get_pixel(x, y)
			var c := sand.get_pixel(x, y)
			check(Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < Vector3(a.r, a.g, a.b).distance_to(Vector3(c.r, c.g, c.b)), "submerged bed remains predominantly water")
	check(Rules.is_land_walkable(Rules.logical_for_terrain_id(4)) and Rules.is_water_navigable(Rules.logical_for_terrain_id(4)), "presentation changes preserve amphibious traversal")

func _test_shared_edges(catalog) -> void:
	for land in [0, 2, 1000, 1001, 1003]:
		for water in [1, 4, 22]:
			for axis in [0, 1]:
				var provider := func(cell): return land if cell[axis] >= 2 else water
				for i in range(33):
					var point := Vector2(2.0, 1.0 + float(i) / 32.0) if axis == 0 else Vector2(1.0 + float(i) / 32.0, 2.0)
					var offset := Vector2(0.00001, 0.0) if axis == 0 else Vector2(0.0, 0.00001)
					var a := Terrain.weights(point - offset, provider, catalog.environment_pack, water)
					var b := Terrain.weights(point + offset, provider, catalog.environment_pack, 6 if land == 2 else land)
					_check_partition(a)
					_check_partition(b)
					for id in a: check(absf(float(a[id]) - float(b.get(id, 0.0))) < 0.002, "adjacent water and ground cells agree on their shared coast")
	var edge := func(cell): return -1 if cell.x < 0 else (2 if cell.y > 1 else 1)
	for i in range(33): _check_partition(Terrain.weights(Vector2(0, i / 8.0), edge, catalog.environment_pack, 6))

func _test_coast_shapes(catalog) -> void:
	# All rotations of a cape, a cove, diagonal shoreline and one-cell shoal.
	var offsets := [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i.ONE, Vector2i(-1, 1)]
	for mask in range(256):
		var cells := {Vector2i.ZERO: 2}
		for i in range(8): cells[offsets[i]] = 1 if mask & (1 << i) else 2
		var provider := func(cell): return int(cells.get(cell, 2))
		for y in range(5):
			for x in range(5): _check_partition(Terrain.weights(Vector2(x / 4.0, y / 4.0), provider, catalog.environment_pack, 6))
	var cove := func(cell): return 2 if cell.x >= 2 and cell.y >= 2 else 1
	var sand_weight: float = Terrain.weights(Vector2(2.10, 2.10), cove, catalog.environment_pack, 6).get(6, 0.0)
	check(sand_weight < 0.2, "cape corner is rounded back inside its cell rather than drawing a square sand tip")
	var shoal := func(cell): return 4 if cell == Vector2i.ONE else 1
	for y in range(9):
		for x in range(9):
			var weights := Terrain.weights(Vector2(x / 4.0, y / 4.0), shoal, catalog.environment_pack, 1)
			check(not weights.has(6), "an isolated shallow cell can never turn into a dry sand diamond")

func _test_reported_map() -> void:
	for profile in ["mediterranean", "coastal", "islands"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		settings["seed"] = 41689
		for i in range(8): settings["players"][i]["enabled"] = i < 4
		var built := Settings.build(settings)
		check(built.get("valid", false), "reported seed retains reachable starts and naval economy: %s %s" % [profile, built.get("errors", [])])

func _check_partition(weights: Dictionary) -> void:
	var total := 0.0
	for weight in weights.values():
		check(is_finite(weight) and weight >= 0.0 and weight <= 1.00001, "coastal blend is bounded and finite")
		total += weight
	check(absf(total - 1.0) < 0.00001, "coast surface cannot expose holes or overpaint its neighbours")

func check(value: bool, message: String) -> void:
	if not value and message not in failures: failures.append(message)
