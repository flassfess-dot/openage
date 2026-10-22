extends SceneTree

const Pipeline := preload("res://scripts/random_map_candidate_pipeline.gd")
const Footprint := preload("res://scripts/footprint.gd")

func _initialize() -> void:
	# The whole small island is reserved against starting resources. That
	# protects construction space; it must not forbid planning a clearing.
	var size := Vector2i(24,24)
	var terrain: Array[int] = []
	terrain.resize(size.x*size.y)
	terrain.fill(1)
	for y in range(7,18):
		for x in range(7,18): terrain[y*size.x+x]=0
	var levels: Array[int] = []
	levels.resize((size.x+1)*(size.y+1))
	var forest := PackedFloat32Array()
	forest.resize(terrain.size())
	var mask := PackedByteArray()
	mask.resize(terrain.size())
	var center := Vector2(12.5,12.5)
	var definition := {"players":[{"team":1,"start":center}],"entities":[{"category":"building","kind":"town_center","position":center,"resource_exclusion_radius_cells":8}]}
	var pipeline := Pipeline.new(definition,size,41721,{},Callable(),{},0,{},6,{"natural":true,"macro":true,"wild":true,"watershed":true})
	pipeline.result={"size":size,"terrain_ids":terrain,"vertex_levels":levels,"resources":[],"cliff_cells":[]}
	pipeline.terrain=terrain
	pipeline.fields={"forest_strength":forest}
	pipeline.geography={"rivers":{"waterfalls":[],"mask":mask}}
	pipeline.naval_reserved={}
	pipeline.cliffs=[]
	pipeline.river_network=true
	pipeline.reserve_routes()
	var clearings: Array=pipeline.result["building_clearings"]
	if clearings.size()!=1:
		push_error("A resource-free start must retain a construction clearing on its small island")
		quit(1)
		return
	var building_cells := Footprint.occupied_cells(center,Vector2(1.5,1.5))
	var clearing:Dictionary=clearings[0]
	for y in range(clearing["origin"].y,clearing["origin"].y+clearing["width"]):
		for x in range(clearing["origin"].x,clearing["origin"].x+clearing["width"]):
			if Vector2i(x,y) in building_cells or not pipeline.reserved.has(Vector2i(x,y)):
				push_error("A clearing must avoid existing buildings and remain protected from resources")
				quit(1)
				return
	print("Construction clearings: resource exclusions permit building; town-center footprint remains blocked")
	quit(0)
