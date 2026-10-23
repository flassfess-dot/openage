extends SceneTree

const Network := preload("res://scripts/random_map_river_network.gd")
const Channels := preload("res://scripts/random_map_river_channels.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	var size:=Vector2i(128,128)
	var terrain: Array[int]=[];terrain.resize(size.x*size.y)
	var nodes: Array=[]
	for y in range(10,111):
		nodes.append(node(Vector2i(64,y),Vector2i(64,y+1),100.0+y*20.0,y==110,1))
	for y in [35,55,75,95]:
		for x in range(40,64):nodes.append(node(Vector2i(x,y),Vector2i(x+1,y),50.0+(x-40)*3.0,false,1))
	# A smaller separate catchment must not consume the main river budget.
	for y in range(20,40):nodes.append(node(Vector2i(10,y),Vector2i(10,y+1),100.0+y,y==39,2))
	var snapshot:=nodes.duplicate(true)
	var options:={"main_rivers":1,"tributaries_per_river":2,"minimum_tributary_length":10.0}
	var result:=Network.select(size,terrain,nodes,41721,options)
	check(result==Network.select(size,terrain,nodes,41721,options),"selection is deterministic")
	check(nodes==snapshot,"selection does not mutate the complete drainage graph")
	check(result["plan"]["systems"].size()==1,"main river budget excludes the smaller basin")
	check(result["plan"]["systems"][0]["tributaries"].size()==2,"only the requested substantial tributaries remain")
	var lookup: Dictionary={};var incoming: Dictionary={}
	for item in result["nodes"]:
		lookup[item["cell"]]=item
		incoming[item["downstream"]]=int(incoming.get(item["downstream"],0))+1
		check(item["basin"]==1,"selection favours the long high-discharge catchment")
		check(item["discharge"]==snapshot.filter(func(original):return original["cell"]==item["cell"])[0]["discharge"],"hidden tributaries retain their contribution to runoff")
	var sources:=0
	for item in result["nodes"]:
		if not item["is_mouth"]:check(lookup.has(item["downstream"]),"each selected branch reaches the selected outlet")
		if not incoming.has(item["cell"]):sources+=1
	check(sources==3,"a trunk with two tributaries has three headwaters")
	check(result["plan"]["hidden_node_count"]>0,"unselected twigs remain implicit")
	# Width depends on actual runoff and an explicit hydraulic reference, even
	# when a profile changes the threshold used to choose visible streams.
	var first:=Channels.build(size,terrain,result["nodes"],48.0,{}, {"width_reference_runoff":100.0,"width_transition_cells":4.0})
	var second:=Channels.build(size,terrain,result["nodes"],200.0,{}, {"width_reference_runoff":100.0,"width_transition_cells":4.0})
	check(first==second,"visibility threshold cannot change selected channel width, depth or sediment")
	var nested: Array[Vector2i]=[]
	for x in range(21):nested.append(Vector2i(x,0))
	var graph: Dictionary={};var parents: Dictionary={}
	for cell in nested:
		graph[cell]={"discharge":1000.0}
		if cell.x>0:parents[cell-Vector2i.RIGHT]=[cell]
	for y in range(1,31):
		var cell:=Vector2i(10,y);graph[cell]={"discharge":500.0}
		if not parents.has(cell-Vector2i.DOWN):parents[cell-Vector2i.DOWN]=[]
		parents[cell-Vector2i.DOWN].append(cell)
	for x in range(11,31):
		var cell:=Vector2i(x,15);graph[cell]={"discharge":200.0}
		if not parents.has(cell-Vector2i.RIGHT):parents[cell-Vector2i.RIGHT]=[]
		parents[cell-Vector2i.RIGHT].append(cell)
	var branches:=Network._select_branches(nested,parents,graph,8.0,2)
	check(branches.size()==2 and branches[1]["parent"]==0,"a major tributary can retain its own substantial fork within the same budget")
	check(Network.select(size,terrain,[],41721)["nodes"].is_empty(),"an arid catchment does not invent rivers to fill a quota")
	for failure in failures:push_error(failure)
	print("River network selection: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)

func node(cell: Vector2i, downstream: Vector2i, flow: float, mouth: bool, basin: int) -> Dictionary:
	return {"cell":cell,"downstream":downstream,"discharge":flow,"is_mouth":mouth,"basin":basin,"surface_level":0}

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):failures.append(message)
