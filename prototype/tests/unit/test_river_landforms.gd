extends SceneTree

const Examples := preload("res://tests/fixtures/river_landscape_examples.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(),"river materials are installed")
	var examples: Dictionary = {}
	for kind in ["bend","ford","waterfall"]:
		var built := Examples.build(kind)
		var data: Dictionary = built["map_data"]
		examples[kind] = data
		check(data == Examples.build(kind)["map_data"],kind+": landforms are deterministic")
		var shape: Dictionary = data["rivers"]["surface"]
		check(shape["model_version"]==2 and shape["stride"]==4,"one field records depth and substrate")
		for y in range(data["size"].y):
			for x in range(data["size"].x):
				var field := Surface.sample(shape,Vector2(x+0.5,y+0.5))
				var weights := Surface.blend({0:0.5,1:0.5},field)
				var total := 0.0
				for value in weights.values():
					check(value>=-0.00001,"all depth-based material weights are nonnegative")
					total += value
				check(absf(total-1.0)<0.00001,"depth-based material coverage is complete")
				if data["terrain_ids"][y*data["size"].x+x] in [1004,1005]: check(field.z<0.0,"exposed navigation cells are above the water level")
	var bend: Dictionary = examples["bend"]
	check(not bend["rivers"]["shoals"].is_empty(),"an alluvial bend has a coherent sediment bar")
	var exposed := 0
	for id in bend["terrain_ids"]:
		if id in [1004,1005]: exposed += 1
	check(exposed>3,"a broad point bar exposes actual ground")
	for bar in bend["rivers"]["shoals"]:
		check(bar["widths"][0]<0.05 and bar["widths"][-1]<0.05,"bars taper instead of forming uniform borders")
	var ford: Dictionary = examples["ford"]
	for crossing in ford["fords"]:
		for i in range(2,19):
			var point: Vector2 = crossing["bank_a"].lerp(crossing["bank_b"],float(i)/20.0)
			var field := Surface.sample(ford["rivers"]["surface"],point)
			check(field.z>0.0 and field.z<0.25,"the crossing retains a continuous shallow water film")
	var waterfall: Dictionary = examples["waterfall"]
	check(waterfall["cliff_obstructions"].size()==1,"one geological ledge replaces repeated waterfall sprites")
	var feature: Dictionary = waterfall["cliff_obstructions"][0]
	var frame := catalog.environment_frame_info(feature,0.0)
	check(frame.has("river_geometry") and frame.get("cascade_texture")!=null and frame.get("rock_texture")!=null,"game and preview resolve the same complete native cascade")
	check(catalog.environment_frame_info(feature,1.0)["frame_index"]==frame["frame_index"],"the authored water and rocks remain static")
	for failure in failures: push_error(failure)
	print("River landforms: asymmetric sections, sediment bars, wet fords and one native rock cascade; %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value and message not in failures: failures.append(message)
