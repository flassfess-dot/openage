class_name RoRRandomMapRiverNetwork
extends RefCounted

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")

# Visibility is a presentation/terrain selection over the complete drainage
# graph. Discharge and the lake spill field are never recomputed after pruning.
# Neither settlement locations nor ship footprints participate in selection.
static func select(size: Vector2i, original: Array[int], nodes: Array, seed: int, options: Dictionary = {}) -> Dictionary:
	var lookup: Dictionary = {}
	var incoming: Dictionary = {}
	for node in nodes:
		lookup[node["cell"]]=node
		if not incoming.has(node["downstream"]):incoming[node["downstream"]]=[]
		incoming[node["downstream"]].append(node["cell"])
	var land := _landmasses(size,original)
	var labels: PackedInt32Array=land["labels"]
	var areas: Array=land["areas"]
	var mainland: int=land["largest"]
	var mainland_area: int=areas[mainland] if mainland>=0 else 0
	var target := 1 if mainland_area<9000 else 2
	if mainland_area>=35000:target=2+int(Topology.roll(Vector2i.ZERO,seed^0x71E3)>0.5)
	target=int(options.get("main_rivers",target))
	var minimum_length := float(options.get("minimum_tributary_length",clampf(sqrt(float(mainland_area))*0.06,5.0,22.0)))
	var candidates: Array=[]
	for node in nodes:
		if not node["is_mouth"]:continue
		var stem:=_trace(node["cell"],incoming,lookup)
		var length:=_length(stem)
		if length<maxf(8.0,minimum_length):continue
		var cell: Vector2i=node["cell"]
		var component: int=labels[cell.y*size.x+cell.x]
		if component!=mainland and (component<0 or areas[component]<maxf(900.0,mainland_area*0.12)):continue
		var branch_target:=2+int(Topology.roll(cell,seed^0xB7A3)>0.5)
		branch_target=int(options.get("tributaries_per_river",branch_target))
		if component!=mainland:branch_target=mini(2,branch_target)
		var tributaries:=_select_branches(stem,incoming,lookup,minimum_length,branch_target)
		candidates.append({"basin":node["basin"],"mouth":cell,"component":component,"stem":stem,"length":length,
			"discharge":node["discharge"],"branches":tributaries,"branch_target":branch_target,
			"score":sqrt(float(node["discharge"])*length)*(1.0+minf(3,tributaries.size())*0.12)})
	candidates.sort_custom(func(a,b):return a["score"]>b["score"] if not is_equal_approx(a["score"],b["score"]) else a["basin"]<b["basin"])
	# Prefer complete systems when the drainage offers them. A third bare trunk
	# is less useful than two substantial branched rivers on the same continent.
	var branched:=candidates.filter(func(candidate):return candidate["component"]==mainland and candidate["branches"].size()>=2)
	if branched.size()>=2:
		target=mini(target,branched.size())
		candidates=candidates.filter(func(candidate):return candidate["component"]!=mainland or candidate["branches"].size()>=2)
	var chosen: Array=[]
	var main_count:=0
	var spacing:=maxf(12.0,sqrt(float(mainland_area))*0.26)
	# First favour separated outlets. Relax the separation once when the real
	# coast cannot offer enough distinct basins; never invent or join streams.
	for separation in [spacing,spacing*0.65]:
		for candidate in candidates:
			if candidate["component"]!=mainland or main_count>=target:continue
			if chosen.any(func(other):return other["basin"]==candidate["basin"] or Vector2(other["mouth"]).distance_to(Vector2(candidate["mouth"]))<separation):continue
			chosen.append(candidate);main_count+=1
	var island_components: Dictionary={}
	for candidate in candidates:
		if candidate["component"]==mainland or island_components.has(candidate["component"]):continue
		chosen.append(candidate);island_components[candidate["component"]]=true
	var kept: Dictionary={}
	var systems: Array=[]
	for candidate in chosen:
		var stem: Array=candidate["stem"]
		for cell in stem:kept[cell]={"river_role":"main","river_system":candidate["basin"]}
		var branches: Array=[]
		for branch in candidate["branches"]:
			for cell in branch["path"]:
				if not kept.has(cell):kept[cell]={"river_role":"tributary","river_system":candidate["basin"]}
			branches.append({"join_distance":branch["join_distance"],"parent":branch["parent"],"length":branch["length"],"discharge":branch["discharge"],"path":_points(branch["path"])})
		systems.append({"basin":candidate["basin"],"mainland":candidate["component"]==mainland,
			"mouth":Vector2(candidate["mouth"])+Vector2.ONE*0.5,"main_path":_points(stem),"main_length":candidate["length"],
			"discharge":candidate["discharge"],"tributary_target":candidate["branch_target"],"tributaries":branches})
	var visible: Array=[]
	for node in nodes:
		if not kept.has(node["cell"]):continue
		var copy: Dictionary=node.duplicate()
		copy.merge(kept[node["cell"]]);visible.append(copy)
	return {"nodes":visible,"plan":{"model":"selected_watershed_systems_v1","mainland_area":mainland_area,
		"mainland_target":target,"mainland_rivers":main_count,"minimum_tributary_length":minimum_length,
		"raw_mouths":nodes.filter(func(node):return node["is_mouth"]).size(),"hidden_node_count":nodes.size()-visible.size(),"systems":systems}}

static func _trace(start: Vector2i, incoming: Dictionary, lookup: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	var at:=start
	while lookup.has(at):
		result.append(at)
		var best:=Vector2i(-1,-1)
		var flow:=-1.0
		for cell in incoming.get(at,[]):
			var value:=float(lookup[cell]["discharge"])
			if value>flow:best=cell;flow=value
		if best.x<0:break
		at=best
	return result

static func _select_branches(stem: Array[Vector2i], incoming: Dictionary, lookup: Dictionary, minimum: float, target: int) -> Array:
	var selected: Array=[]
	var pending:=_tributaries(stem,incoming,lookup,minimum)
	for branch in pending:branch["parent"]=-1
	var gap:=maxf(5.0,minf(minimum,_length(stem)*0.10))
	while selected.size()<target and not pending.is_empty():
		pending.sort_custom(func(a,b):return a["score"]>b["score"] if not is_equal_approx(a["score"],b["score"]) else a["join_distance"]<b["join_distance"])
		var branch: Dictionary=pending.pop_front()
		if selected.any(func(other):return other["parent"]==branch["parent"] and absf(other["join_distance"]-branch["join_distance"])<gap):continue
		var parent:=selected.size()
		selected.append(branch)
		# A major tributary may itself fork. Keep its substantial child as one
		# of the same limited branch budget, rather than retaining every twig.
		for child in _tributaries(branch["path"],incoming,lookup,minimum):
			child["parent"]=parent;pending.append(child)
	return selected

static func _tributaries(stem: Array[Vector2i], incoming: Dictionary, lookup: Dictionary, minimum: float) -> Array:
	var candidates: Array=[]
	var distance:=0.0
	var total:=_length(stem)
	for i in range(stem.size()):
		if i>0:distance+=Vector2(stem[i]).distance_to(Vector2(stem[i-1]))
		if distance<maxf(8.0,minimum*0.5) or total-distance<minimum*0.4:continue
		for cell in incoming.get(stem[i],[]):
			if i+1<stem.size() and cell==stem[i+1]:continue
			var branch:=_trace(cell,incoming,lookup)
			branch.push_front(stem[i])
			var length:=_length(branch)
			if length<minimum:continue
			var flow:=float(lookup[cell]["discharge"])
			candidates.append({"path":branch,"length":length,"discharge":flow,"join_distance":distance,"score":sqrt(length*flow)})
	candidates.sort_custom(func(a,b):return a["score"]>b["score"] if not is_equal_approx(a["score"],b["score"]) else a["join_distance"]<b["join_distance"])
	return candidates

static func _length(cells: Array) -> float:
	var result:=0.0
	for i in range(1,cells.size()):result+=Vector2(cells[i]).distance_to(Vector2(cells[i-1]))
	return result

static func _points(cells: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for cell in cells:result.append(Vector2(cell)+Vector2.ONE*0.5)
	return result

static func _landmasses(size: Vector2i, original: Array[int]) -> Dictionary:
	var labels:=PackedInt32Array();labels.resize(original.size());labels.fill(-1)
	var areas: Array[int]=[]
	var largest:=-1
	for i in range(original.size()):
		if original[i]!=0 or labels[i]>=0:continue
		var id:=areas.size()
		var queue:=PackedInt32Array([i]);labels[i]=id
		var cursor:=0
		while cursor<queue.size():
			var at:=queue[cursor];cursor+=1
			for next in Navigation.neighbors(at,size):
				if original[next]!=0 or labels[next]>=0:continue
				labels[next]=id;queue.append(next)
		areas.append(queue.size())
		if largest<0 or queue.size()>areas[largest]:largest=id
	return {"labels":labels,"areas":areas,"largest":largest}
