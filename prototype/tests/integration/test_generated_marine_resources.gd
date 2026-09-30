extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Water := preload("res://scripts/random_map_water.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const KINDS := ["shore_fish", "deep_fish", "whale"]
var failures: Array[String] = []
var catalog = Catalog.new()
var sample: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	catalog.load()
	for profile in ["small_islands", "islands", "coastal", "continental", "mediterranean"]:
		for seed_value in [41689, 7919]:
			var settings := Settings.default_settings()
			settings["map_type_id"] = profile
			settings["seed"] = seed_value
			for i in range(8): settings["players"][i]["enabled"] = i < 4
			var built := Settings.build(settings)
			check(bool(built.get("valid", false)), "%s/%d builds: %s" % [profile, seed_value, built.get("errors", [])])
			if not built.get("valid", false): continue
			inspect_map(built["map_data"], "%s/%d" % [profile, seed_value])
			if profile == "mediterranean" and seed_value == 41689: sample = built
	if not sample.is_empty():
		var repeat := Generator.generate(sample["definition"])
		check(repeat == sample["map_data"], "marine ecology is deterministic, including the map fingerprint")
		var without_docks: Dictionary = sample["definition"].duplicate(true)
		without_docks["map"]["generator"]["requires_naval_starts"] = false
		without_docks["map"].erase("content_hash")
		inspect_map(Generator.generate(without_docks), "sea without compulsory naval starts")
		inspect_live_match()
		inspect_animation()
		await inspect_preview()
	var dry: Array[int] = []
	dry.resize(32 * 32)
	dry.fill(0)
	check(Generator._neutral_fish_clusters(Vector2i(32, 32), dry, 41689).is_empty(), "dry maps have no marine resources")
	var pond := dry.duplicate()
	for y in range(12, 19):
		for x in range(12, 19): pond[y * 32 + x] = 1
	Water.apply(pond, Vector2i(32, 32), 41689)
	var pond_clusters := Generator._neutral_fish_clusters(Vector2i(32, 32), pond, 41689)
	check(not pond_clusters.any(func(item): return item["kind"] == "whale"), "small ponds cannot host whales")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Marine resources passed: 10 sea maps, water without docks, dry land, ponds, live bootstrap, visible animated sprites, render cache and preview")
	quit(0 if failures.is_empty() else 1)

func inspect_map(data: Dictionary, context: String) -> void:
	var counts := {"shore_fish": 0, "deep_fish": 0, "whale": 0}
	var size: Vector2i = data["size"]
	var terrain: Array[int] = data["terrain_ids"]
	var distances := Water.water_distance_from_land(terrain, size)
	var occupied: Dictionary = {}
	var reserved: Array = data.get("reserved_foundation_cells", [])
	var whales: Array[Vector2] = []
	for resource in data["resources"]:
		var kind := String(resource.get("kind", ""))
		if kind not in KINDS: continue
		counts[kind] += 1
		var cell := Vector2i(resource["position"])
		check(not occupied.has(cell) and not reserved.has(cell), context + ": schools do not overlap each other or dock foundations")
		occupied[cell] = true
		check(int(resource["amount"]) == 250, context + ": marine food matches RoR resource capacity")
		check(resource.get("source_graphic_asset_name", "") == kind, context + ": generated assets resolve to the actual imported names")
		var info: Dictionary = catalog.resource_frame_info(resource, 1.0)
		check(info.get("texture") != null and info.get("asset_name", "") == kind, context + ": every marine resource has real art")
		if kind == "shore_fish":
			check(resource["placement_domain"] == "shore_water", context + ": shore habitat is retained")
			check(terrain[cell.y * size.x + cell.x] == 1 and Generator._cell_matches_domain(cell, size, terrain, "shore_water"), context + ": shore fish remain beside dry land")
		else:
			check(Generator._cell_matches_domain_with_clearance(cell, size, terrain, "water", 2), context + ": boats have water around offshore resources")
		if kind == "whale":
			check(terrain[cell.y * size.x + cell.x] == 22 and distances[cell.y * size.x + cell.x] >= 5, context + ": whales remain offshore in deep water")
			check(cell.x >= 5 and cell.y >= 5 and cell.x < size.x - 5 and cell.y < size.y - 5, context + ": whale sprites stay inside the map boundary")
			for other in whales: check(other.distance_to(resource["position"]) >= 10.0, context + ": whales are spaced apart")
			whales.append(resource["position"])
	for kind in KINDS: check(counts[kind] > 0, context + ": " + kind + " must be present")
	check(counts == data.get("marine_resources", {}), context + ": displayed counts match actual resources")
	print("Marine map %s: %s" % [context, counts])

func inspect_live_match() -> void:
	var data: Dictionary = sample["map_data"]
	var world = World.new(data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, sample["definition"], data)
	var counts := {"shore_fish": 0, "deep_fish": 0, "whale": 0}
	for resource in world.get_resources():
		var kind := String(resource["kind"])
		if kind not in KINDS: continue
		counts[kind] += 1
		check("water" in resource.get("allowed_gatherer_domains", []), "boats can harvest " + kind)
		var projected := Snapshot._compact_render_entity(resource)
		check(catalog.resource_frame_info(projected, 1.0).get("texture") != null, "live render snapshot retains marine art")
		if kind == "shore_fish":
			check("land" in resource.get("allowed_gatherer_domains", []), "villagers can harvest shore fish")
			var approach := false
			for offset in Water.ORTHOGONAL_DIRECTIONS:
				var cell: Vector2i = Vector2i(resource["pos"]) + offset
				if world.navigation_grid.is_walkable(cell): approach = true
			check(approach, "shore fish keep an unobstructed land approach after forests and bootstrap")
	check(counts == data["marine_resources"], "bootstrap preserves every generated marine resource")

func inspect_animation() -> void:
	for kind in KINDS:
		var resource: Dictionary = sample["map_data"]["resources"].filter(func(item): return item.get("kind") == kind)[0].duplicate(true)
		resource["id"] = 0
		resource["pos"] = resource["position"]
		var frames: Dictionary = {}
		var visible_area := 0
		var renderer = RenderWorld.new()
		var clock_value := [0.0]
		var provider := func(_category: String, entity: Dictionary): return catalog.resource_frame_info(entity, clock_value[0])
		var projection := func(position: Vector2): return position * 32.0
		for step in range(201):
			clock_value[0] = float(step) * 0.1
			var items: Array = renderer._snapshot_resource_drawables([resource], projection, provider, [])
			check(items.size() == 1, "one selectable drawable per marine resource")
			if items.is_empty(): continue
			var info: Dictionary = items[0]["frame_info"]
			check(info.get("texture") != null, "cached " + kind + " frame is never missing")
			if info.get("texture") == null: continue
			frames[int(info["frame_index"])] = true
			var image: Image = info["texture"].get_image()
			visible_area = maxi(visible_area, image.get_used_rect().get_area())
		check(frames.size() > 5, kind + " animates even when the resource render cache is reused")
		check(visible_area >= 100, kind + " has a visible sprite during its source animation cycle")
		var stale: Dictionary = resource.duplicate(true)
		stale["source_graphic_asset_name"] = "graphic_%d" % int(stale["source_graphic_id"])
		check(catalog.resource_frame_info(stale, 1.0).get("asset_name") == kind, "stale generated aliases fall back to existing " + kind + " art")
		resource["amount"] = 0
		check(catalog.resource_frame_info(resource, 1.0).is_empty(), "depleted marine resources disappear")

func inspect_preview() -> void:
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.seed_input.value = 41689
	for index in range(scene.profiles.size()):
		if scene.profiles[index]["id"] == "mediterranean": scene.profile_choice.select(index)
	scene.generate_map()
	await process_frame
	var items: Array = scene.objects.filter(func(item): return item.has("animated_resource"))
	var expected: Dictionary = scene.generated["map_data"]["marine_resources"]
	check(items.size() == expected["shore_fish"] + expected["deep_fish"] + expected["whale"], "preview includes all generated marine resources")
	var ids: Dictionary = {}
	for item in items: ids[item["animated_resource"]["id"]] = true
	check(ids.size() == items.size(), "preview uses stable distinct phases, not id zero for every fish")
	var mesh = scene.terrain.terrain_mesh
	var before: float = scene.animation_time
	scene._process(0.2)
	check(scene.animation_time > before and scene.has_animated_objects, "preview advances its marine animation clock")
	check(scene.terrain.terrain_mesh == mesh, "animating fish does not rebuild terrain")
	check(scene.status.text.contains("Киты:"), "preview reports marine population")
	scene.free()

func check(value: bool, context: String) -> void:
	if not value and not failures.has(context): failures.append(context)
