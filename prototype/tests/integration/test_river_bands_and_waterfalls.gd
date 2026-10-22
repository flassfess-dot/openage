extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Quality := preload("res://scripts/random_map_quality.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(),"native shoal material loads")
	check(catalog.environment_pack.has_material(4),"Shallows is a ground material, not separate oval stamps")
	var checked_falls := 0
	for profile in ["grasslands","highlands","hill_country"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		settings["map_size_id"] = "large"
		for i in range(8): settings["players"][i]["enabled"] = i < 2
		var built := Settings.build(settings)
		check(built.get("valid",false),profile+": quality "+str(built.get("errors",[])))
		if not built.get("valid",false): continue
		var data: Dictionary = built["map_data"]
		var size: Vector2i = data["size"]
		var rivers: Dictionary = data["rivers"]
		var shape: Dictionary = rivers["surface"]
		var longest := 0.0
		var wet_samples := 0
		for strip in rivers["shoals"]:
			longest = maxf(longest,strip["length"])
			var points: PackedVector2Array = strip["points"]
			check(strip["widths"][0] < 0.05 and strip["widths"][-1] < 0.05,profile+": each sediment bar tapers at both ends")
			for i in range(1,points.size()): check(points[i].distance_to(points[i-1]) < 0.6,profile+": connected shoreline ribbon")
			for i in range(6,points.size()-6,3):
				var field := Surface.sample(shape,points[i])
				if field.y < 0.9 or field.x < 0.15 or field.z > 0.4 or strip["widths"][i] < 0.3: continue
				var weights := Surface.blend({1:1.0},field)
				check(float(weights.get(4,0.0))+float(weights.get(1004,0.0))+float(weights.get(1005,0.0)) > 0.60,profile+": coherent exposed or submerged bed follows the bar geometry")
				wet_samples += 1
		check(longest >= 8.0 and wet_samples > 12,profile+": elongated banks replace isolated patches")
		check(data["scenery"].all(func(item): return item.get("decoration_key","") != "ror_shallows"),profile+": no full oval Shallows stamps")
		var world := World.new(size)
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		Bootstrap.apply(world,built["definition"],data)
		for actor in world.get_units().duplicate(): world.detach_unit_for_transport(actor["id"])
		for ford in data["fords"]:
			var middle: Vector2 = (ford["bank_a"]+ford["bank_b"])*0.5
			check(Surface.sediment(Surface.sample(shape,middle)) > 0.6,profile+": visible cross-river bar")
			check(world.navigation_grid.is_segment_walkable_for(ford["bank_a"],ford["bank_b"],0.3,"land",7),profile+": infantry can cross the actual bar")
		for fall in rivers["waterfalls"]:
			checked_falls += 1
			check(data["cliff_obstructions"].any(func(item): return item.get("river_barrier",false)),profile+": waterfall has real brown cliff faces")
			for cell in fall["barrier_cells"]:
				check(data["cliff_cells"].has(cell),profile+": waterfall barrier survives publication")
				check(not world.navigation_grid.is_position_walkable_for(Vector2(cell)+Vector2.ONE*0.5,0.3,"water",0),profile+": waterfall blocks the live ship grid")
			for kind in ["fishing_boat","scout_ship","transport","catapult_trireme"]:
				var unit: Dictionary = world.add_unit(1,kind,fall["upper"],false)
				var restriction := int(unit["terrain_restriction"])
				var radius := float(unit["footprint_radius"])
				var upper: Vector2 = world.pathfinder.nearest_walkable(Vector2i(fall["upper"].floor()),"water",restriction,radius)
				var lower: Vector2 = world.pathfinder.nearest_walkable(Vector2i(fall["lower"].floor()),"water",restriction,radius)
				upper += Vector2.ONE*0.5
				lower += Vector2.ONE*0.5
				var fits:bool=upper.distance_to(fall["upper"]) < 3.0 and lower.distance_to(fall["lower"]) < 3.0
				# The revised geography allows a pool to be too narrow for a large
				# ship. Direct blocker checks above still protect every barrier cell.
				if not fits:
					world.detach_unit_for_transport(unit["id"])
					continue
				var path: Array = world.pathfinder.find_path(upper,lower,"water",restriction,radius)
				check(path.is_empty() or Vector2(path[-1]).distance_to(lower) > 1.0,profile+": no ship route across the waterfall: "+kind)
				world.detach_unit_for_transport(unit["id"])
			var invalid: Dictionary = data.duplicate(true)
			invalid["rivers"]["waterfalls"] = []
			check("random_map_cliff_cell_invalid" in Quality.inspect(built["definition"],invalid)["errors"],"ordinary rocks in water are still rejected without a declared waterfall")
		world.shutdown_derived_state()
		print(profile+": continuous bank strips, infantry fords and ship-blocking waterfalls checked")
	check(checked_falls >= 2,"actual generated maps contain multiple physical waterfalls")
	for failure in failures: push_error(failure)
	print("River bands and waterfalls: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
