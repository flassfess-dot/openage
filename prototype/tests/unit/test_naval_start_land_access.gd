extends SceneTree

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Generator := preload("res://scripts/random_map_generator.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var size := Vector2i(16,12)
	var terrain: Array[int] = []
	terrain.resize(size.x*size.y)
	terrain.fill(1)
	# A one-cell approach to the beach, with the future dock beside it.
	for y in range(3,9):
		for x in range(2,7): terrain[y*size.x+x]=0
	for x in range(7,11): terrain[7*size.x+x]=2
	var definition := {"players":[{"team":1,"start":Vector2(4.5,5.5)}],"entities":[{"category":"building","kind":"town_center","position":Vector2(4.5,5.5)}]}
	var map := {"size":size,"terrain_ids":terrain,"naval_start_zones":[{"team":1,"dock_position":Vector2(9.5,5.5),"land_staging":Vector2(10.5,7.5),"water_staging":Vector2(12.5,7.5)}],"resources":[],"scenery":[]}
	var reserved := {}
	Navigation.reserve_naval_access(definition,map,reserved)
	for x in range(7,11): check(reserved.has(Vector2i(x,7)),"the complete narrow land approach is protected before resource placement")
	check(not reserved.has(Vector2i(9,5)),"the access route never crosses the future dock")
	check(not reserved.has(Vector2i(12,7)),"land access does not consume open water resource cells")
	var repeated := {}
	Navigation.reserve_naval_access(definition,map,repeated)
	check(repeated==reserved,"naval route reservation is deterministic")
	var occupied_map: Dictionary = map.duplicate(true)
	occupied_map["resources"]=[{"category":"resource","kind":"tree","position":Vector2(8.5,7.5),"placement_domain":"land"}]
	var audit := Navigation.inspect(definition,occupied_map)
	check("random_map_final_naval_land_unreachable:1" in audit["errors"],"final audit rejects an empty beach isolated by a resource")
	var clusters := [{"kind":"tree","count":8,"center":Vector2(8.5,7.5),"radius":3.0,"amount":75,"placement_domain":"land"}]
	map["resources"]=Generator._generate_resource_clusters(clusters,size,41721,terrain,reserved)
	check(not map["resources"].is_empty(),"resource placement still fills available surrounding land")
	check(map["resources"].all(func(resource):return not reserved.has(Vector2i(resource["position"]))),"resource placement respects the protected route")
	check(Navigation.inspect(definition,map)["errors"].is_empty(),"the beach remains reachable after resources are placed")
	for failure in failures: push_error(failure)
	print("Naval start land access: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
