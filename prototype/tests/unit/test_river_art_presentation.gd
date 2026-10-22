extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Examples := preload("res://tests/fixtures/river_landscape_examples.gd")
const Presentation := preload("res://scripts/river_feature_presentation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(),"native river art imports completely")
	if not failures.is_empty(): finish();return
	var feature: Dictionary = Examples.build("waterfall")["map_data"]["cliff_obstructions"][0]
	var original := feature.duplicate(true)
	var info := catalog.environment_frame_info(feature,0.0)
	check(info["animation_frames"]==1,"the authored waterfall is deliberately static")
	check(info["cascade_texture"].get_size()==Vector2(59,69),"the complete native reference is used, without cropping its rock or water")
	for example in [[Vector2.RIGHT,[16,17]],[Vector2.DOWN,[18,19]],[Vector2.LEFT,[17,16]],[Vector2.UP,[19,18]]]:
		var fall: Dictionary = feature["river_form"].duplicate()
		fall["direction"]=example[0]
		var ends := Presentation._bank_layout(fall,feature["position"],info["bank_rocks"])
		check(ends.map(func(end):return end["source_frame"])==example[1],"both native cliff endings face the river and continue landward when the flow reverses")
		check(ends[0]["foreground"]!=ends[1]["foreground"],"near and far bank endings straddle the waterfall in drawing order")
	check(Presentation._mesh(info,"cascade")==Presentation._mesh(catalog.environment_frame_info(feature,93.7),"cascade"),"elapsed time does not replace native water or move rocks")
	for angle in range(8):
		for radius in [1.3,3.0]:
			for drop in [1,3,5]:
				var rotated := feature.duplicate(true)
				var fall: Dictionary = rotated["river_form"]
				fall["direction"]=Vector2.from_angle(angle*TAU/8.0)
				fall["radius"]=radius
				fall["upper_level"]=drop;fall["lower_level"]=0
				var frame_info := catalog.environment_frame_info(rotated,0.0)
				var ends := Presentation._bank_layout(fall,rotated["position"],frame_info["bank_rocks"])
				check(ends.size()==2,"every direction and drop retains both complete native cliff endings")
				for end in ends:
					check(end["source_frame"] in [16,17,18,19],"a bank uses an authored directional ending rather than an isolated rock")
					check(Vector2(end["screen"]).is_finite(),"bank attachment remains finite at every supported drop")
				var stones := Presentation._cascade_layout(fall,rotated["position"])
				check(stones.size()>=4 and stones.size()<=10,"the cascade retains a bounded set of large water-bearing rocks")
				for stone in stones:
					check(Presentation._cascade_point(stone,Presentation.SOURCE_LIP).distance_to(stone["lip"])<0.001,"the native stream joins its intended upper-river point")
					check(Presentation._cascade_point(stone,Presentation.SOURCE_FOOT).distance_to(stone["foot"])<0.001,"the complete boulder rests at its intended lower-river point")
					var a := Vector2(10,42);var b := Vector2(27,60)
					var actual := Presentation._cascade_point(stone,a).distance_to(Presentation._cascade_point(stone,b))
					check(absf(actual-a.distance_to(b)*stone["scale"])<0.001,"the large rock face keeps native proportions instead of stretching with the water neck")
				for kind in ["rock","cascade"]:
					var arrays: Array = Presentation._mesh(frame_info,kind).surface_get_arrays(0)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					check(not vertices.is_empty(),"all directions and drop heights retain presentation geometry")
					for point in vertices: check(point.is_finite(),"no direction emits invalid coordinates")
					for index in arrays[Mesh.ARRAY_INDEX]: check(index>=0 and index<vertices.size(),"every triangle references its own vertices")
					for uv in arrays[Mesh.ARRAY_TEX_UV]: check(uv.x>=0.0 and uv.x<=1.0 and uv.y>=0.0 and uv.y<=1.0,"sampling stays inside the whole authored sprite")
	check(feature==original,"drawing leaves terrain and navigation metadata unchanged")
	check(Presentation.geometry_cache.size()<=Presentation.MAX_CACHED_MESHES,"changing directions and drop heights retains a bounded geometry cache")
	finish()

func check(value: bool,message: String) -> void:
	if not value and message not in failures: failures.append(message)

func finish() -> void:
	for failure in failures: push_error(failure)
	print("River art: whole native reference, large boulders, directional cliff endings, bank drawing order, eight directions and bounded static meshes; %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
