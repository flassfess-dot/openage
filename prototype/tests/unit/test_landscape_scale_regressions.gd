extends SceneTree

const Topology := preload("res://scripts/random_map_topology.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")

var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	_test_geometry()
	_test_height_independent_ecology()
	_test_sparse_stones()
	_test_shoal_order()
	var directory := "res://qa/landscape-20261003"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("regression-metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"geometry": rows, "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	print("Landscape scale, ecology, stone density and shoal regressions: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_geometry() -> void:
	for length in [72, 200, 400]:
		var size := Vector2i(length, length)
		for seed_value in [41689, 7919]:
			var starts: Array[Vector2] = []
			for angle in [-PI * 0.5, 0.0, PI * 0.5, PI]:
				starts.append(Vector2(size) * 0.5 + Vector2.from_angle(angle + 0.12) * length * 0.32)
			var land_counts: Dictionary = {}
			for profile in ["small_islands", "islands", "mediterranean"]:
				var topology := "mediterranean" if profile == "mediterranean" else "islands"
				var layout := Topology.prepare(size, starts, topology, {"map_type_id": profile, "sea_fraction": 0.23}, seed_value)
				var mask: Array[int] = []
				mask.resize(length * length)
				var water_count := 0
				for y in range(length):
					for x in range(length):
						var wet := Topology.water_at(Vector2(x + 0.5, y + 0.5), layout)
						mask[y * length + x] = int(wet)
						water_count += int(wet)
				land_counts[profile] = mask.size() - water_count
				rows.append({"size": length, "seed": seed_value, "profile": profile, "water_ratio": float(water_count) / mask.size()})
				if topology == "mediterranean":
					var center_width := 0
					for y in range(length): center_width += mask[y * length + length / 2]
					check(center_width >= length * 0.27, "Mediterranean is a broad basin at %d/%d" % [length, seed_value])
					check(mask[0] == 0 and mask[length * (length / 2)] == 0 and mask[length * (length / 2) + length - 1] == 0, "Mediterranean has land enclosing its ends")
					check(float(water_count) / mask.size() >= 0.18 and float(water_count) / mask.size() <= 0.31, "sea retains the declared area budget")
				else:
					for start in starts:
						check(not Topology.water_at(start, layout), "island starts retain dry land")
					var minimum_radius := INF
					var maximum_radius := 0.0
					for i in range(32):
						var direction := Vector2.from_angle(TAU * i / 32.0)
						var reach := 0.0
						for step in range(1, length / 2):
							if Topology.water_at(starts[0] + direction * step, layout): break
							reach = step
						minimum_radius = minf(minimum_radius, reach)
						maximum_radius = maxf(maximum_radius, reach)
					check(maximum_radius / maxf(1.0, minimum_radius) > 1.28, "island coastline is visibly noncircular at %s/%d/%d" % [profile, length, seed_value])
			check(float(land_counts["islands"]) > float(land_counts["small_islands"]) * 1.35, "large islands have substantially more land at %d/%d" % [length, seed_value])

func _test_height_independent_ecology() -> void:
	var size := Vector2i(24, 24)
	var moisture := PackedFloat32Array()
	var geology := PackedFloat32Array()
	moisture.resize(size.x * size.y)
	geology.resize(size.x * size.y)
	for i in range(moisture.size()):
		moisture[i] = float(i % 20) / 20.0
		geology[i] = float(i % 17) / 17.0
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	levels.fill(0)
	var fields := {"moisture": moisture, "geology": geology, "vertex_levels": levels, "recipe": {"rock_threshold": 0.6}}
	var terrain: Array[int] = []
	terrain.resize(moisture.size())
	terrain.fill(0)
	var low := {"size": size, "terrain_ids": terrain.duplicate(), "vertex_levels": levels.duplicate()}
	var high: Dictionary = low.duplicate(true)
	high["vertex_levels"].fill(7)
	Landscape.paint_ground(low, fields)
	Landscape.paint_ground(high, fields)
	check(low["terrain_ids"] == high["terrain_ids"], "soil does not turn worn just because land is raised")
	for i in range(moisture.size()):
		var tree := {"kind": "tree", "position": Vector2(i % size.x + 0.5, i / size.x + 0.5)}
		var raised := tree.duplicate()
		fields["vertex_levels"].fill(0)
		Landscape.bind_tree(tree, fields, size, 1234)
		fields["vertex_levels"].fill(7)
		Landscape.bind_tree(raised, fields, size, 1234)
		check(tree == raised, "changing elevation alone leaves tree art unchanged")
		check(tree["source_graphic_id"] != 607, "yellow beech is not an ordinary conifer")

func _test_sparse_stones() -> void:
	for profile in ["grasslands", "highlands", "coastal"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		var built := Settings.build(settings)
		check(built.get("valid", false), "density fixture is playable: %s %s" % [profile, built.get("errors", [])])
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		var land := 0
		for id in data["terrain_ids"]:
			if id not in [1, 4, 22]: land += 1
		var stones: Array = data["scenery"].filter(func(item): return item["decoration_key"] in ["ror_grass_rocks", "ror_dry_rocks", "ror_mud_rocks"])
		check(stones.size() <= maxi(1, land / 260), "small stones share one sparse area budget")
		for i in range(stones.size()):
			for j in range(i + 1, stones.size()):
				check(Vector2(stones[i]["position"]).distance_to(stones[j]["position"]) >= 5.49, "stone groups leave broad clear spaces")

func _test_shoal_order() -> void:
	var shoal := {"asset_name": "aoe2_temperate:ror_shallows", "presentation_layer": "scenery"}
	check(RenderWorld.environment_layer(shoal) == RenderItem.Layer.DECAL, "old saved shoal artwork stays below ships")
	var water_detail := RenderItem.create("environment", RenderWorld.environment_layer(shoal), Vector2(10, 10), Vector2(0, 200), -1)
	var boat := RenderItem.create("unit", RenderItem.Layer.UNIT_BUILDING, Vector2(5, 5), Vector2(0, 100), 1, {"kind": "fishing_boat"})
	var items := [boat, water_detail]
	items.sort_custom(RenderItem.less)
	check(items[0] == water_detail and items[1] == boat, "even a shoal in the foreground cannot cover a fishing boat")
	for spec in Decorations.palette():
		if spec["key"] == "ror_shallows": check(spec["role"] == "decal", "new shoals use the ground layer")

func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
