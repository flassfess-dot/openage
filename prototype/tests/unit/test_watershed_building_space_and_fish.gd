extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Space := preload("res://scripts/random_map_building_space.gd")
const Support := preload("res://scripts/random_map_generation_support.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
const Watershed := preload("res://scripts/random_map_watershed_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var upland: Array[int] = []
	upland.resize(400 * 400)
	var coast := PackedInt32Array()
	coast.resize(upland.size())
	coast.fill(800)
	var highland_levels := Watershed.broad_relief(Vector2i(400,400), upland, {"recipe":{"relief":7},"coast_distance":coast}, 41721 ^ 0x8194, "highlands")
	check(highland_levels.min() >= 1 and highland_levels.max() >= 4 and highland_levels.max() <= 9, "supergiant highlands preserve raised basin floors and broad mountains with river ledges")
	for profile in ["grasslands", "highlands"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		var built := Settings.build(settings)
		check(built.get("valid", false), profile + " builds")
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		var size: Vector2i = data["size"]
		var river_fish := 0
		var lake_fish := 0
		var lakes: Dictionary = {}
		for lake in data["lakes"]:
			for i in lake["cells"]: lakes[Vector2i(i % size.x, i / size.x)] = true
		for item in data["resources"]:
			if item["kind"] not in ["shore_fish", "deep_fish", "whale"]: continue
			var cell := Vector2i(item["position"])
			if data["rivers"]["mask"][cell.y * size.x + cell.x] != 0:
				check(item["kind"] != "whale", "freshwater does not receive whales")
				if lakes.has(cell): lake_fish += 1
				else: river_fish += 1
		check(river_fish > 0 and lake_fish > 0, profile + " contains real river and lake fish resources")
		var metrics := Space.measure(data)
		check(metrics["flat_land_fraction"] > (0.65 if profile == "grasslands" else 0.50), profile + " retains broad level land")
		check(metrics["flat_land_fraction"] < 0.95 and data["vertex_levels"].max() >= 4, profile + " still has raised hills")
		check(metrics["level_5x5_positions"] >= 400 and metrics["unoccupied_5x5_positions"] >= 30, profile + " retains broad building areas after forests and economy")
		check(data["building_clearings"].size() == built["definition"]["players"].size(), profile + " protects an expansion clearing per settlement")
		var occupied := Space._occupied(data)
		for clearing in data["building_clearings"]:
			check(Space._fits(data, clearing["origin"], clearing["width"], occupied), profile + " clearing stays level, dry and empty after generation")
		var repeat := Generator.generate(built["definition"])
		check(repeat["content_hash"] == data["content_hash"] and repeat["building_clearings"] == data["building_clearings"], profile + " reconstructs relief, fish and clearings deterministically")
		print("%s: river fish %d, lake fish %d, construction %s" % [profile, river_fish, lake_fish, metrics])
	# Freshwater ecology must retain explicit port/obstruction reservations.
	var size := Vector2i(40, 40)
	var terrain: Array[int] = []
	var freshwater := PackedByteArray()
	terrain.resize(1600)
	freshwater.resize(1600)
	for y in range(40):
		for x in range(40):
			terrain[y * 40 + x] = 22 if x > 5 and y > 5 and x < 34 and y < 34 else 0
			freshwater[y * 40 + x] = int(terrain[y * 40 + x] == 22)
	var blocked: Dictionary = {}
	for y in range(12, 21):
		for x in range(12, 21): blocked[Vector2i(x,y)] = true
	var fish := Support._neutral_fish_clusters(size, terrain, 41721, blocked, [], freshwater)
	check(not fish.is_empty(), "a broad inland lake receives fishing schools")
	for item in fish:
		check(item["kind"] != "whale", "an inland deep lake never receives whales")
		check(not blocked.has(Vector2i(item["center"][0],item["center"][1])), "fish preserve explicit dock reservations")
	check(not Support._fish_water_clearance(Vector2i(11,16),size,terrain,blocked,1),"a fishing habitat next to rapid rocks cannot claim blocked boat clearance")
	var zones:=Support._generate_naval_start_zones([{"team":1,"start":[20,3]}],size,terrain,{"water_staging_clearance_cells":1},blocked)
	check(not zones.is_empty(),"the unobstructed shore still offers a real port site")
	for zone in zones:
		check(not blocked.has(Vector2i(zone["dock_position"])) and not blocked.has(Vector2i(zone["water_staging"])),"port placement respects real geological obstacles")
	terrain.fill(0);freshwater.fill(0)
	for y in range(4,36):terrain[y*40+20]=4;freshwater[y*40+20]=1
	var bank_fish:=Support._neutral_fish_clusters(size,terrain,41721,{},[],freshwater)
	check(not bank_fish.is_empty() and bank_fish.all(func(item):return item["kind"]=="shore_fish"),"a one-cell shallow stream supports bank fishing without a boat-sized habitat")
	for item in bank_fish:
		var cell:=Vector2i(item["center"][0],item["center"][1])
		check(Support._shore_fish_approach(cell,size,terrain,{}) is Vector2i,"every narrow-stream school has a dry villager approach")
		check(not Support._fish_water_clearance(cell,size,terrain,{},1),"shore fish do not require open water around a fishing boat")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
