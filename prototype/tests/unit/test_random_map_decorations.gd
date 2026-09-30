extends SceneTree
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Field := preload("res://scripts/environment_presentation_field.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Preview := preload("res://scripts/environment_preview.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "mixed pack imports completely")
	var variants := 0
	for spec in Decorations.palette():
		for variant in range(spec["frames"].size()):
			variants += 1
			var ctx := fixture(spec)
			var position := Vector2(16.5, 16.5)
			if spec.has("route_axes"):
				ctx["route_directions"][Vector2i(16, 16)] = Vector2(spec["route_axes"][variant][0], spec["route_axes"][variant][1])
			check(Decorations.fits(spec, variant, position, ctx), "reachable habitat: %s/%d" % [spec["key"], variant])
			var item := {"asset_name": "aoe2_temperate:" + String(spec["key"]), "source_frame": variant, "presentation_layer": spec["role"], "position": position}
			var info: Dictionary = catalog.environment_frame_info(item)
			check(info.get("texture") != null and info.get("frame_index", -1) == variant, "real artwork: %s/%d" % [spec["key"], variant])
			check((RenderWorld.environment_layer(item) == RenderItem.Layer.DECAL) == (spec["role"] == "decal"), "game uses the correct layer")
			var covered := Decorations.footprint_cells(spec, variant, position)
			ctx["foundations"][covered.back()] = true
			check(not Decorations.fits(spec, variant, position, ctx), "full footprint rejects a foundation")
			ctx["foundations"].clear()
			var last: Vector2i = covered.back()
			ctx["terrain"][last.y * 32 + last.x] = 22
			check(not Decorations.fits(spec, variant, position, ctx), "full footprint cannot spill into deep water")
			ctx["terrain"][last.y * 32 + last.x] = int(spec["placement"]["materials"][0])
			ctx["levels"][(last.y + 1) * 33 + last.x + 1] = 1
			check(not Decorations.fits(spec, variant, position, ctx), "stamp cannot cross a terrace edge")
			check(not Decorations.fits(spec, variant, Vector2(-0.5, 4), ctx), "map boundary is enforced")
	check(variants == 105, "105 allowed decoration variants have placement rules and source art")
	for key in ["ror_stone_dirt_trail", "ror_stone_grass_trail", "overgrown_trail"]:
		check(Decorations.palette().filter(func(spec): return spec["key"] == key).is_empty(), "excluded road family has no generation rule: " + key)
	_test_dry_biome_population()
	var cracks: Dictionary = Decorations.palette().filter(func(s): return s["key"] == "ror_cracks")[0]
	var dry := fixture(cracks)
	dry["fields"]["moisture"].fill(0.9)
	check(not Decorations.fits(cracks, 0, Vector2(16.5, 16.5), dry), "wet soil never receives cracks")
	var decal := {"position": Vector2(20, 20), "presentation_layer": "decal"}
	var unit := {"position": Vector2.ONE, "reference": true}
	check(Preview.object_less(decal, unit) and not Preview.object_less(unit, decal), "preview places even foreground decals below actors")
	var route := [{"position": Vector2(1, 1)}, {"position": Vector2(2, 1)}, {"position": Vector2(3, 1)}, {"position": Vector2(10, 10)}, {"position": Vector2(11, 10)}]
	check(Decorations.connected_routes(route).size() == 3, "isolated trail fragments are removed while a connected route survives")
	var field := Field.new()
	field.configure([{"id": -1, "position": Vector2(10.5, 10.5), "presentation_bounds": [-4, -2, 4, 2]}])
	check(field.query(Rect2i(7, 9, 1, 1)).size() == 1, "wide decal remains visible when anchor leaves the view")
	check(field.query(Rect2i(0, 0, 20, 20)).size() == 1, "wide decal is not returned repeatedly")
	check(field.query(Rect2i(20, 20, 2, 2)).is_empty(), "offscreen decal is culled")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Decoration palette passed: 105 allowed variants, source art, habitats, complete footprints, layers and camera culling")
	quit(0 if failures.is_empty() else 1)

func fixture(spec: Dictionary) -> Dictionary:
	var rule: Dictionary = spec["placement"]
	var terrain: Array[int] = []
	terrain.resize(1024)
	terrain.fill(int(rule["materials"][0]))
	var levels: Array[int] = []
	levels.resize(1089)
	levels.fill(0)
	var moisture := PackedFloat32Array()
	moisture.resize(1024)
	moisture.fill((float(rule["moisture"][0]) + float(rule["moisture"][1])) * 0.5)
	var geology := moisture.duplicate()
	geology.fill(0.9)
	var coast := PackedInt32Array()
	coast.resize(1024)
	coast.fill(0)
	var forest := coast.duplicate()
	forest.fill(int(rule.get("forest_distance", [1, 999])[0]))
	var water := coast.duplicate()
	water.fill(int(rule.get("water_distance", [1, 3])[0]))
	var routes: Dictionary = {}
	for y in range(32):
		for x in range(32): routes[Vector2i(x, y)] = true
	return {"size": Vector2i(32, 32), "terrain": terrain, "levels": levels, "fields": {"moisture": moisture, "geology": geology, "coast_distance": coast},
		"forest_distance": forest, "water_distance": water, "foundations": {}, "occupied": {}, "routes": routes, "route_band": routes,
		"paved": routes if rule.get("paved", false) else {}, "route_directions": {}}

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)


func _test_dry_biome_population() -> void:
	# A genuinely dry, exposed plateau with crossing settlement routes exercises
	# rare categories which need not occur in a small temperate-map sample.
	var size := Vector2i(96, 96)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(1000)
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	levels.fill(0)
	var moisture := PackedFloat32Array()
	moisture.resize(terrain.size())
	moisture.fill(0.18)
	var geology := moisture.duplicate()
	geology.fill(0.9)
	var woodland := moisture.duplicate()
	woodland.fill(0.8)
	var coast := PackedInt32Array()
	coast.resize(terrain.size())
	coast.fill(99)
	var fields := {"moisture": moisture, "geology": geology, "woodland": woodland, "coast_distance": coast}
	var edges: Array = []
	for offset in range(8, 90, 8):
		for vertical in [false, true]:
			var path := PackedInt32Array()
			for i in range(4, 92): path.append(i * size.x + offset if vertical else offset * size.x + i)
			edges.append({"path": path, "to_team": 2})
	var data := {"size": size, "terrain_ids": terrain, "vertex_levels": levels, "resources": [], "region_graph": {"edges": edges}}
	var seen: Dictionary = {}
	for seed_value in [71, 4096, 7919, 41689]:
		# Bones also need open countryside, away from the dense road network.
		data["region_graph"]["edges"] = edges if seed_value in [71, 4096] else []
		var items := Decorations.generate(data, fields, {}, seed_value, 2.0)
		for item in items: seen[item["decoration_key"]] = true
	for key in ["ror_cracks", "ror_dirt_trail", "rubble", "ror_bones", "bones"]:
		check(seen.has(key), "rare family is selected by the real generator in its biome: " + key)
