extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Movement := preload("res://scripts/simulation_movement_system.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var world := World.new(Vector2i(16,16))
	var reference := Movement.new(world)
	var random := RandomNumberGenerator.new()
	random.seed=20261104
	var comparisons:=0
	var reference_us:=0
	var native_us:=0
	for layout in range(4):
		var grid := Grid.new(Vector2i(40,40))
		grid.configure_terrain(func(_cell): return "grass")
		var obstacles: Array=[]
		for y in range(5,35):
			if layout==1 and y not in [16,17,18]: obstacles.append(Vector2i(20,y))
			if layout==2:
				for x in range(5,35):
					if (x*17+y*11)%23==0: obstacles.append(Vector2i(x,y))
			if layout==3: obstacles.append(Vector2i(20,y))
		grid.occupy(obstacles,"building",10)
		var planner := Pathfinder.new(grid)
		for radius in [0.0,0.3,0.7,1.1]:
			var kernel=planner._native_kernel_for("land",-1)
			if not kernel.has_method("find_local_traffic_path"):
				push_error("Build the native local traffic kernel first");quit(1);return
			for sample in range(10):
				var origin:=Vector2(random.randf_range(12,18),random.randf_range(12,22))
				var goal:=origin+Vector2(random.randf_range(-5,7),random.randf_range(-5,5))
				var unit: Dictionary={"pos":origin,"footprint_radius":radius,"minimum_clearance":0.06,"movement_domain":"land","terrain_restriction":-1}
				var neighbors: Array=[]
				for other in range(sample%5):
					neighbors.append({"pos":origin+Vector2(random.randf_range(-3,4),random.randf_range(-3,3)),"footprint_radius":[0.3,0.6,1.0][other%3],"minimum_clearance":0.06})
				var started:=Time.get_ticks_usec()
				var expected: Array[Vector2]=reference._local_work_path_reference(unit,planner,neighbors,goal)
				reference_us+=Time.get_ticks_usec()-started
				started=Time.get_ticks_usec()
				var actual: PackedVector2Array=kernel.find_local_traffic_path(origin,goal,radius,0.06,neighbors)
				native_us+=Time.get_ticks_usec()-started
				if actual!=PackedVector2Array(expected): failures.append("route differs layout=%d radius=%s sample=%d"%[layout,radius,sample])
				comparisons+=1
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Native local traffic: %d comparisons, %d failures; reference=%dus native=%dus"%[comparisons,failures.size(),reference_us,native_us])
	quit(0 if failures.is_empty() else 1)
