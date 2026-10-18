extends SceneTree
const Cache := preload("res://scripts/build_site_static_cache.gd")
const Grid := preload("res://scripts/navigation_grid.gd")
const Navigation := preload("res://scripts/navigation_task_data.gd")
var failures: Array[String] = []
func check_rings() -> void:
	var kernel: Variant = ClassDB.instantiate("RoRReadModelKernel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 16041998
	for center in [Vector2i.ZERO,Vector2i(15,16),Vector2i(32,25),Vector2i(-2,5)]:
		var pages: Dictionary = {}
		for y in range(3):
			for x in range(3):
				var flags := PackedByteArray()
				flags.resize(256)
				for i in range(256): flags[i] = rng.randi_range(0,2)
				pages[Vector2i(x,y)] = flags
		var seen := {Vector2i(1,1):true,Vector2i(4,6):true}
		var actual_seen := seen.duplicate()
		var expected: Array = []
		for r in range(1,13):
			for y in range(center.y-r,center.y+r+1):
				var columns: Array = range(center.x-r,center.x+r+1) if absi(y-center.y) == r else [center.x-r,center.x+r]
				for x in columns:
					var cell := Vector2i(x,y)
					if x < 0 or y < 0 or x >= 40 or y >= 40 or seen.has(cell): continue
					seen[cell] = true
					var flags: PackedByteArray = pages[Vector2i(x/16,y/16)]
					if flags[(y%16)*16+x%16] != 2: expected.append(cell)
		check(kernel.build_site_ring_cells(center,12,Vector2i(40,40),actual_seen,pages) == expected,"native rings preserve first-visit order and static rejections")
		check(actual_seen == seen,"native rings preserve complete visited-cell membership")
func _initialize() -> void:
	check_rings()
	var grid := Grid.new(Vector2i(128,128))
	var cache := Cache.new()
	var profile := {"footprint":{"occupied_cells":[Vector2i.ZERO,Vector2i(1,0)]}}
	var first := Navigation.capture_chunked(grid,{},7)
	cache.begin(first)
	cache.prepare_kind("house",profile)
	cache.store("house",Vector2(15.5,15.5),true)
	cache.store("house",Vector2(80.5,80.5),false)
	grid.set_terrain(Vector2i(16,15),"water")
	var second := Navigation.capture_chunked(grid,first,7)
	cache.begin(second)
	check(cache.lookup("house",Vector2(15.5,15.5)) == 0,"neighboring page invalidates a footprint crossing the page edge")
	check(cache.lookup("house",Vector2(80.5,80.5)) == 2,"distant edits retain negative audits")
	cache.store("house",Vector2(15.5,15.5),true)
	cache.prepare_kind("house",{"footprint":{"occupied_cells":[Vector2i.ZERO]}})
	check(cache.lookup("house",Vector2(15.5,15.5)) == 0,"changed placement profile invalidates audits")
	cache.store("house",Vector2(15.5,15.5),true)
	cache.begin(first)
	cache.prepare_kind("house",profile)
	check(cache.lookup("house",Vector2(15.5,15.5)) == 0,"earlier retained publication clears future audits")
	cache.store("house",Vector2(15.5,15.5),true)
	cache.begin(Navigation.capture_chunked(grid,{},8))
	cache.prepare_kind("house",profile)
	check(cache.lookup("house",Vector2(15.5,15.5)) == 0,"new source generation clears audits")
	cache.maximum_pages = 3
	for i in range(30): cache.store("house",Vector2(i*16+0.5,0.5),true)
	check(cache.retained.size() == 3 and cache.pages_by_kind.house.size() == 3,"retained pages have a strict bound")
	check(cache.lookup("house",Vector2(0.5,0.5)) == 0,"evicted page recomputes")
	cache.begin({"size":grid.size,"epoch":grid.cache_epoch,"source_generation":8,"revision":grid.revision})
	check(not cache.active,"old checkpoint without version metadata uses reference fallback")
	for failure in failures: push_error(failure)
	print("Build site static cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
