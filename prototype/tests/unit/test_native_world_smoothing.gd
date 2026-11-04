extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Planner := preload("res://scripts/pathfinder.gd")
class Counting extends "res://scripts/pathfinder.gd":
	var segment_queries:=0
	func is_segment_walkable(start: Vector2, finish: Vector2, radius: float, domain: String="land", restriction: int=-1) -> bool:
		segment_queries+=1
		return super.is_segment_walkable(start,finish,radius,domain,restriction)
class Reference extends "res://scripts/pathfinder.gd":
	var segment_queries:=0
	func is_segment_walkable(start: Vector2, finish: Vector2, radius: float, domain: String="land", restriction: int=-1) -> bool:
		segment_queries+=1
		return super.is_segment_walkable(start,finish,radius,domain,restriction)
	func _swept_world_route(origin: Vector2, destination: Vector2, start: Vector2i, goal: Vector2i, radius: float, domain: String, restriction: int) -> Array[Vector2]:
		var cells: Array[Vector2i]=find_cell_path(start,goal,domain,restriction,radius)
		var candidates: Array[Vector2]=[]
		if cells.is_empty():return candidates
		var center:=Vector2(start)+Vector2(0.5,0.5)
		if not origin.is_equal_approx(center):candidates.append(center)
		for index in range(1,cells.size()):candidates.append(Vector2(cells[index])+Vector2(0.5,0.5))
		if candidates.is_empty() or not candidates.back().is_equal_approx(destination):candidates.append(destination)
		var result: Array[Vector2]=[]
		var cursor:=origin
		var first:=0
		if not is_position_walkable(origin,radius,domain,restriction) and candidates[0].is_equal_approx(center):
			result.append(center);cursor=center;first=1
		while first<candidates.size():
			var selected:=-1
			for index in range(candidates.size()-1,first-1,-1):
				if is_segment_walkable(cursor,candidates[index],radius,domain,restriction):selected=index;break
			if selected<0:return []
			cursor=candidates[selected];result.append(cursor);first=selected+1
		return result
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message)
func _initialize() -> void:
	check(ClassDB.class_exists("RoRPathKernel") and ClassDB.instantiate("RoRPathKernel").has_method("smooth_swept_world_path"),"native world smoother must be built")
	Planner.native_world_smoothing_default=false
	check(not Counting.new().native_world_smoothing_enabled,"reference default applies to future planners")
	Planner.native_world_smoothing_default=true
	for native in [false,true]:
		var grid:=Grid.new(Vector2i(96,96))
		grid.configure_terrain(func(_cell):return "grass")
		grid.occupy([Vector2i(4,4)],"building",1)
		var candidate:=Counting.new(grid)
		var reference:=Reference.new(grid)
		candidate.set_native_enabled(native);reference.set_native_enabled(native)
		var goal:=Vector2(90.5,90.5)
		for origin in [Vector2(4.9,4.9),Vector2(4.5,4.5),Vector2(5.01,5.01),Vector2(5.5,5.5)]:
			for radius in [0.0,0.3,0.7]:
				candidate.segment_queries=0;reference.segment_queries=0
				var expected:=reference._swept_world_route(origin,goal,Vector2i(origin),Vector2i(goal),radius,"land",-1)
				var actual:=candidate._swept_world_route(origin,goal,Vector2i(origin),Vector2i(goal),radius,"land",-1)
				check(actual==expected,"origin escape and blocked centre preserve exact route, native=%s origin=%s radius=%s" % [native,origin,radius])
				if native and origin==Vector2(4.9,4.9) and radius==0.3:
					check(reference.segment_queries>50 and candidate.segment_queries==0,"blocked centre rejects once instead of testing a long route")
	var comparisons:=24
	for layout in range(4):
		var grid:=Grid.new(Vector2i(48,48))
		grid.configure_terrain(func(cell):return "water" if layout==3 and cell.y>24 else "grass")
		var blocked: Array=[]
		for y in range(2,46):
			for x in [12,24,36]:
				if (layout==0 and y not in [8,9,10]) or (layout==1 and (y<38 if x!=24 else y>10)) or (layout==2 and (x+y)%7!=0):blocked.append(Vector2i(x,y))
		grid.occupy(blocked,"building",50)
		var candidate:=Counting.new(grid)
		var reference:=Reference.new(grid)
		for radius in [0.0,0.3,0.7,1.1]:
			for origin in [Vector2(4.1,4.9),Vector2(13.01,13.01),Vector2(23.9,32.1)]:
				for goal in [Vector2(42.5,8.2),Vector2(26.1,40.9),Vector2(4.9,4.1)]:
					for domain in ["land","water"] if layout==3 else ["land"]:
						check(candidate.find_path(origin,goal,domain,-1,radius)==reference.find_path(origin,goal,domain,-1,radius),"full world path matches, layout=%d radius=%s domain=%s" % [layout,radius,domain])
						comparisons+=1
	print("Native world smoothing: %d path comparisons" % comparisons)
	var kernel=ClassDB.instantiate("RoRPathKernel")
	var mask:=PackedByteArray();mask.resize(64);mask.fill(1);mask[3*8+3]=0
	kernel.configure(8,8,1,mask)
	check(kernel.smooth_swept_world_path(Vector2(1.5,1.5),PackedVector2Array(),0.3,Vector2(1.5,1.5)).is_empty(),"empty candidate input is empty")
	check(kernel.smooth_swept_world_path(Vector2(3.9,3.9),PackedVector2Array([Vector2(3.5,3.5)]),0.3,Vector2(3.5,3.5))==PackedVector2Array([Vector2(3.5,3.5)]),"legacy single-centre escape remains unchanged")
	var points:=PackedVector2Array([Vector2(6.5,3.5)])
	var context=kernel.create_movement_context()
	check(kernel.smooth_swept_world_path(Vector2(1.5,3.5),points,0.3,Vector2(1.5,3.5)).is_empty(),"closed passage blocks the complete swept route")
	kernel.update_walkable(2,PackedInt32Array([3*8+3]),PackedByteArray([1]))
	check(kernel.smooth_swept_world_path(Vector2(1.5,3.5),points,0.3,Vector2(1.5,3.5))==points,"opening a passage is visible on the next call")
	check(context.smooth_swept_world_path(Vector2(1.5,3.5),points,0.3,Vector2(1.5,3.5)).is_empty(),"private contexts retain their immutable old mask")
	for failure in failures:push_error(failure)
	print("Native world smoothing: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
