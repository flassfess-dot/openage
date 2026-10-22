extends RefCounted
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Banks := preload("res://scripts/random_map_river_banks.gd")
const Falls := preload("res://scripts/random_map_river_falls.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")

static func build(kind: String) -> Dictionary:
	var size := Vector2i(56,56)
	var original: Array[int] = []
	original.resize(size.x*size.y)
	var terrain := original.duplicate()
	var levels: Array[int] = []
	levels.resize((size.x+1)*(size.y+1))
	if kind == "waterfall":
		for y in range(size.y+1):
			for x in range(size.x+1): levels[y*(size.x+1)+x] = roundi(3.0*(1.0-smoothstep(24.0,29.0,y)))
	var points := PackedVector2Array()
	var radii := PackedFloat32Array()
	var heights := PackedInt32Array()
	var bends := PackedFloat32Array()
	var runoff := PackedFloat32Array()
	var rocky := PackedFloat32Array()
	for i in range(241):
		var t := float(i)/240.0
		points.append(Vector2(28.0+(0.0 if kind=="waterfall" else sin(t*TAU)*6.0),4.0+t*48.0))
		radii.append(3.0+(0.0 if kind=="waterfall" else sin(t*PI)*0.3))
		heights.append(3 if kind=="waterfall" and t<0.48 else 0)
		bends.append(0.0)
		runoff.append(288.0)
		rocky.append(0.8 if kind=="waterfall" else 0.05)
	for i in range(12,points.size()-12): bends[i]=(points[i]-points[i-12]).normalized().cross((points[i+12]-points[i]).normalized())
	var channel := {"points":points,"radii":radii,"levels":heights,"bends":bends,"runoff":runoff,"rockiness":rocky,"basin":17}
	var mask := PackedByteArray()
	var types := PackedInt32Array()
	var surfaces := PackedInt32Array()
	mask.resize(terrain.size());types.resize(terrain.size());surfaces.resize(terrain.size())
	types.fill(-1);surfaces.fill(-1)
	for i in range(points.size()):
		var cell := Vector2i(points[i].floor())
		for y in range(maxi(0,cell.y-4),mini(size.y,cell.y+5)):
			for x in range(maxi(0,cell.x-4),mini(size.x,cell.x+5)):
				if Vector2(x+0.5,y+0.5).distance_to(points[i])>radii[i]: continue
				var at := y*size.x+x
				mask[at]=1;types[at]=1;surfaces[at]=heights[i]
	var mouths := PackedByteArray();mouths.resize(terrain.size())
	var rivers := {"channels":[channel],"mask":mask,"terrain_types":types,"surface_levels":surfaces,"mouth_mask":mouths,"runoff_threshold":48.0,"waterfalls":[]}
	Rivers.apply(terrain,rivers)
	var focus := points[60]
	var fords: Array = []
	if kind=="ford":
		focus=points[120]
		var tangent := (points[126]-points[114]).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var a := focus-normal*4.2-tangent*0.45
		var b := focus+normal*4.2+tangent*0.45
		var cells: Array[Vector2i] = []
		for y in range(size.y):
			for x in range(size.x):
				var point := Vector2(x+0.5,y+0.5)
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))<1.35 and terrain[y*size.x+x]==1:
					cells.append(Vector2i(x,y));types[y*size.x+x]=4
		fords.append({"center":Vector2i(focus),"bank_a":a,"bank_b":b,"cells":cells,"origin":"control_riffle"})
	if kind=="waterfall":
		focus=Vector2(28,27)
		var blocked: Array[Vector2i] = []
		for y in range(26,28):
			for x in range(24,32):
				if terrain[y*size.x+x]==1: blocked.append(Vector2i(x,y))
		rivers["waterfalls"]=[{"position":focus,"direction":Vector2.DOWN,"radius":3.0,"upper_level":3,"lower_level":0,"upper":Vector2(28,23),"lower":Vector2(28,32),"barrier_cells":blocked}]
	rivers["shoals"]=Banks.build(size,terrain,{"vertex_levels":levels},rivers,[],41721)
	rivers["surface"]=Surface.build(size,original,rivers,[],fords)
	Surface.classify(size,rivers,[],fords)
	Rivers.apply(terrain,rivers)
	var scenery: Array = []
	var cliffs: Array = []
	var cliff_cells: Dictionary = {}
	Falls.append_cliffs(size,terrain,levels,rivers,cliffs,cliff_cells,{},41721)
	Falls.restore_pools(size,terrain,levels,rivers)
	Falls.update_presentation(size,levels,cliffs)
	var resources: Array = []
	for i in range(32):
		var position := Vector2(15.0+sin(i*2.39)*2.5,10.0+fposmod(i*5.71,35.0)) if i%2==0 else Vector2(41.0+sin(i*2.39)*2.5,10.0+fposmod(i*5.71,35.0))
		resources.append({"kind":"tree","position":position,"amount":75,"source_graphic_asset_name":"aoe2_temperate:oak","source_frame":i%3})
	var data := {"size":size,"seed":41721,"terrain_ids":terrain,"vertex_levels":levels,"rivers":rivers,"fords":fords,"lakes":[],"scenery":scenery,"resources":resources,"cliff_obstructions":cliffs,"cliff_cells":cliff_cells.keys(),"ecology":{"tree_sources":{"ror":0,"aoe2":resources.size()}}}
	return {"valid":true,"definition":{"players":[]},"map_data":data,"focus":focus}
