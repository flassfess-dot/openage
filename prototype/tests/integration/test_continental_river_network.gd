extends SceneTree

const World := preload("res://scripts/random_map_watershed_world.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	for seed in [41721,7919,104729]:
		var geo:=World.geography(Vector2i(400,400),"continental",seed)
		var rivers: Dictionary=geo["rivers"]
		var plan: Dictionary=rivers["network_plan"]
		check(Rivers.inspect(rivers)["valid"],"%d keeps every selected branch connected and draining downhill"%seed)
		check(plan["mainland_rivers"] in [2,3],"%d has two or three major mainland rivers"%seed)
		check(plan["raw_mouths"]>rivers["mouth_count"],"%d hides minor independent coastal streams"%seed)
		check(rivers["width_reference_runoff"]>rivers["runoff_threshold"],"%d can expose narrow headwaters without widening developed rivers"%seed)
		var lookup: Dictionary={};var incoming: Dictionary={}
		for node in rivers["nodes"]:
			lookup[Vector2(node["cell"])+Vector2.ONE*0.5]=node
			incoming[node["downstream"]]=int(incoming.get(node["downstream"],0))+1
		var expected_sources:=0
		for system in plan["systems"]:
			var path: PackedVector2Array=system["main_path"]
			if system["mainland"]:check(system["tributaries"].size() in [2,3],"%d retains two or three substantial tributaries per mainland system"%seed)
			expected_sources+=1+system["tributaries"].size()
			check(lookup[path[0]]["radius"]>lookup[path[-1]]["radius"]*2.0,"%d widens the trunk downstream with accumulated runoff"%seed)
			for branch in system["tributaries"]:
				check(branch["length"]>=plan["minimum_tributary_length"],"%d excludes short tributary twigs"%seed)
				for point in branch["path"]:check(lookup.has(point),"%d retains the complete selected tributary path"%seed)
		var sources: int=rivers["nodes"].filter(func(node):return not incoming.has(node["cell"])).size()
		check(sources==expected_sources,"%d publishes exactly the selected branches without tertiary noise"%seed)
		if seed==41721:
			check(rivers==World.geography(Vector2i(400,400),"continental",seed)["rivers"],"same seed reproduces the full selected terrain and water surface")
		print("Continental river systems seed=%d rivers=%d tributaries=%s"%[seed,plan["mainland_rivers"],str(plan["systems"].map(func(system):return system["tributaries"].size()))])
	var other:=World.geography(Vector2i(96,96),"coastal",41721)
	check(not other["rivers"].has("network_plan"),"other geographic profiles keep their own network composition")
	for failure in failures:push_error(failure)
	print("Continental river composition: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):failures.append(message)
