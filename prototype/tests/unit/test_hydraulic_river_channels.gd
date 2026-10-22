extends SceneTree
const Channels := preload("res://scripts/random_map_river_channels.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Banks := preload("res://scripts/random_map_river_banks.gd")
const Rapids := preload("res://scripts/random_map_river_rapids.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
const Support := preload("res://scripts/random_map_generation_support.gd")
var failures: Array[String] = []

func _initialize() -> void:
	check(Channels.radius(2.0)<1.2,"main-reach threshold no longer forces a warship-sized channel")
	check(Channels.radius(1.0,0.9)<0.5,"headwaters may be narrower than the source fishing boat")
	check(Channels.radius(1)<Channels.radius(4) and Channels.radius(4)<Channels.radius(16),"watershed discharge increases channel width")
	var size := Vector2i(64,64)
	var land: Array[int] = [];land.resize(size.x*size.y)
	var levels: Array[int] = [];levels.resize(65*65)
	var geology := PackedFloat32Array();geology.resize(land.size());geology.fill(0.2)
	var nodes: Array = []
	for y in range(5,58):nodes.append({"cell":Vector2i(32,y),"downstream":Vector2i(32,y+1),"discharge":192.0,"surface_level":0,"is_mouth":y==57,"basin":1})
	var fields := {"vertex_levels":levels,"geology":geology}
	var river := Channels.build(size,land,nodes,48.0,fields,{"width_scale":0.9})
	check(river==Channels.build(size,land,nodes,48.0,fields,{"width_scale":0.9}),"channel shaping is deterministic")
	var wider := Channels.build(size,land,nodes,48.0,fields,{"width_scale":1.4})
	check(wider["mask"].count(1)>river["mask"].count(1),"profile width scale changes the actual curved terrain footprint")
	var capped := Channels.build(size,land,nodes,48.0,fields,{"maximum_radius":0.8})
	check(Array(capped["channels"][0]["radii"]).max()<=0.80001,"profile maximum radius reaches the curved-channel builder")
	var channel: Dictionary=river["channels"][0]
	var mid: int=channel["points"].size()/2
	var broad_radius:float=channel["radii"][mid]
	geology.fill(0.9)
	for y in range(65):
		for x in range(65):levels[y*65+x]=3 if x<30 or x>35 else 0
	var gorge := Channels.build(size,land,nodes,48.0,fields,{"width_scale":0.9})
	check(gorge["channels"][0]["radii"][mid]<broad_radius*0.85,"two high resistant banks form a reach-scale constriction")
	for i in range(1,channel["radii"].size()):check(absf(channel["radii"][i]-channel["radii"][i-1])<0.08,"width varies smoothly along the river")
	var mouths := PackedByteArray();mouths.resize(land.size())
	river.merge({"runoff_threshold":48.0,"mouth_mask":mouths,"waterfalls":[],"rapids":[],"shoals":[]})
	# Flat depositional bars must be able to emerge in a small river as well.
	levels.fill(0)
	var bend := channel["bends"] as PackedFloat32Array;bend.fill(0.25);channel["bends"]=bend
	var rocky := channel["rockiness"] as PackedFloat32Array;rocky.fill(0.05);channel["rockiness"]=rocky
	river["shoals"]=Banks.build(size,land,fields,river,[],41721)
	check(not river["shoals"].is_empty() and river["shoals"][0]["crest_depth"]<0.0,"narrow rivers retain exposed bank bars")
	var shape := Surface.build(size,land,river,[])
	var exposed:=0
	for bar in river["shoals"]:
		for point in bar["points"]:
			if Surface.sample(shape,point).z < -0.045:
				exposed+=1
				check(not Support._shore_fish_fits(point,shape),"shore fish cannot occupy an exposed continuous river bar")
	check(exposed>0,"narrow bars actually survive in the shared visible and physical bed")
	for point in channel["points"]:check(Surface.sample(shape,point).z>0.0,"the river retains flowing water through all bank deposits")
	# Rapid placement uses geological eligibility, not an arbitrary obstacle roll.
	rocky.fill(0.9);channel["rockiness"]=rocky
	var terrain:=land.duplicate();Rivers.apply(terrain,river)
	var rapids:=Rapids.plan(size,terrain,river,[],41721)
	check(not rapids.is_empty(),"a strongly rocky reach receives a boulder rapid")
	check(rapids==Rapids.plan(size,terrain,river,[],41721),"rapid sites and blockers are deterministic")
	river["rapids"]=rapids
	var scenery:Array=[];var cells:Dictionary={}
	Rapids.append_rocks(river,scenery,cells,{},41721)
	check(not scenery.is_empty() and scenery.all(func(item):return item.get("river_rapid",false) and item["occupied_cells"].size()==1),"every rapid obstacle has a visible original rock")
	for rapid in rapids:
		for cell in rapid["barrier_cells"]:check(cells.has(cell),"rapid barriers reach the actual navigation raster")
	for failure in failures:push_error(failure)
	print("Hydraulic river geometry: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)

func check(ok:bool,message:String) -> void:
	if not ok and not failures.has(message):failures.append(message)
