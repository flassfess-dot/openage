extends RefCounted
var cells: Dictionary = {}
var last_tick = -1000
var cell_size = 8
var topology_signature := -1

func update(snapshot: Dictionary, state, policy: Dictionary) -> void:
	var tick = int(snapshot.get("tick",0))
	if tick-last_tick < 80: return
	last_tick = tick
	cell_size = maxi(8,ceili(float(maxi(Vector2i(snapshot.get("map_size",Vector2i(48,48))).x,Vector2i(snapshot.get("map_size",Vector2i(48,48))).y))/48.0))
	var navigation: Dictionary = snapshot.get("navigation",{})
	var signature: int=hash([cell_size,navigation.get("reachable",{}).get("land",navigation.get("land",[])),navigation.get("reachable",{}).get("water",navigation.get("water",[]))])
	var rebuild: bool=signature!=topology_signature
	if rebuild:
		topology_signature=signature
		cells.clear()
		for domain in ["land","water"]:
			var points: Array = navigation.get("reachable",{}).get(domain,navigation.get(domain,[]))
			var stride = maxi(1,ceili(float(points.size())/4096.0))
			for index in range(0,points.size(),stride):
				var point = Vector2(points[index])
				var cell = Vector2i(floori(point.x/cell_size),floori(point.y/cell_size))
				var key = domain+":"+str(cell)
				if not cells.has(key): cells[key] = {"cell":cell,"domain":domain,"position":point,"known_samples":0,"resource_value":0.0}
				cells[key]["known_samples"] += 1
	for entry in cells.values(): entry["resource_value"]=0.0
	for resource in snapshot.get("resources",[]):
		var point = Vector2(resource.get("pos",Vector2.ZERO))
		var cell = Vector2i(floori(point.x/cell_size),floori(point.y/cell_size))
		var key = "land:"+str(cell)
		if cells.has(key): cells[key]["resource_value"] += float(resource.get("amount",0))
	# Tactical movement still uses the exact navigation contract. Coarse cells
	# are strategic summaries, never permission to cross a wall/unknown tile.
	var keys: Array = cells.keys(); keys.sort()
	for key in keys:
		var entry: Dictionary = cells[key]
		entry["risk"] = state.danger(Vector2(entry["position"]),tick,policy,String(entry["domain"]))
		if not rebuild: continue
		var neighbors: Array = []
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor = String(entry["domain"])+":"+str(Vector2i(entry["cell"])+delta)
			if cells.has(neighbor): neighbors.append(neighbor)
		entry["neighbors"] = neighbors

func best_expansion(home: Vector2, maximum_risk: float = 8.0) -> Dictionary:
	var best: Dictionary = {}; var score = -INF
	var keys: Array = cells.keys(); keys.sort()
	for key in keys:
		var entry: Dictionary = cells[key]
		if String(entry["domain"]) != "land" or float(entry.get("risk",0.0)) > maximum_risk: continue
		var distance = home.distance_to(Vector2(entry["position"]))
		if distance < 8.0: continue
		var value = sqrt(float(entry["resource_value"]))*2.0-distance-float(entry.get("risk",0.0))*8.0
		if value > score: score = value; best = entry
	return best.duplicate(true)

func canonical_state() -> Dictionary:
	return {"cells":cells.duplicate(true),"last_tick":last_tick,"cell_size":cell_size,"topology_signature":topology_signature}

func route(origin: Vector2,target: Vector2,domain: String) -> Array:
	var start := ""; var finish := ""; var sd := INF; var fd := INF
	var keys: Array = cells.keys(); keys.sort()
	for key in keys:
		var entry: Dictionary = cells[key]
		if String(entry["domain"])!=domain: continue
		var a := origin.distance_squared_to(Vector2(entry["position"])); var b := target.distance_squared_to(Vector2(entry["position"]))
		if a<sd: sd=a; start=key
		if b<fd: fd=b; finish=key
	if start.is_empty() or finish.is_empty() or start==finish: return []
	var open: Array = [start]; var costs: Dictionary = {start:0.0}; var previous: Dictionary = {}; var expanded := 0
	while not open.is_empty() and expanded<256:
		open.sort_custom(func(a,b): return float(costs[a])<float(costs[b]) if not is_equal_approx(float(costs[a]),float(costs[b])) else String(a)<String(b))
		var current: String = open.pop_front(); expanded+=1
		if current==finish:
			var result: Array = []
			while current!=start and result.size()<32:
				result.push_front(cells[current]["position"]); current=previous[current]
			return result
		for neighbor in cells[current].get("neighbors",[]):
			var value := float(costs[current])+1.0+float(cells[neighbor].get("risk",0.0))*4.0
			if not costs.has(neighbor) or value<float(costs[neighbor]):
				costs[neighbor]=value; previous[neighbor]=current
				if neighbor not in open: open.append(neighbor)
	return []

func restore_state(data: Dictionary) -> bool:
	if not data.get("cells",{}) is Dictionary or data.get("cells",{}).size() > 2400: return false
	cells = data.get("cells",{}).duplicate(true); last_tick = int(data.get("last_tick",-1000)); cell_size = int(data.get("cell_size",8))
	topology_signature=int(data.get("topology_signature",-1))
	return cell_size >= 8
