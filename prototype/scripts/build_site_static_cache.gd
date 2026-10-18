extends RefCounted
# Private to one planner executor. Only immutable observed topology metadata is
# retained; cells from unseen live terrain never enter this cache.
const PAGE_SIZE := 16
var maximum_pages := 4096
var pages_by_kind: Dictionary = {}
var profiles: Dictionary = {}
var halos: Dictionary = {}
var retained: Dictionary = {}
var next_token := 1
var identity: Array = []
var revision := -1
var full_revision := -1
var page_revisions: Dictionary = {}
var active := false
var native_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
func clear() -> void:
	pages_by_kind.clear()
	profiles.clear()
	halos.clear()
	retained.clear()
	identity = []
	revision = -1
	page_revisions = {}
	active = false
func begin(topology: Dictionary) -> void:
	var next_identity := [topology.get("size"),topology.get("epoch"),topology.get("source_generation")]
	if identity != next_identity or int(topology.get("revision",-1)) < revision: clear()
	identity = next_identity
	active = topology.has("task_page_revisions") and topology.has("task_full_revision")
	revision = int(topology.get("revision",-1))
	full_revision = int(topology.get("task_full_revision",-1))
	page_revisions = topology.get("task_page_revisions",{})
func prepare_kind(kind: String, profile: Dictionary) -> void:
	if profiles.has(kind) and profiles[kind] == profile: return
	for entry in pages_by_kind.get(kind,{}).values(): retained.erase(entry["token"])
	pages_by_kind[kind] = {}
	profiles[kind] = profile.duplicate(true)
	var extent := 1
	for offset in profile.get("footprint",{}).get("occupied_cells",[]): extent = maxi(extent,maxi(absi(offset.x),absi(offset.y))+1)
	halos[kind] = maxi(1,ceili(float(extent)/PAGE_SIZE))
func _entry(kind: String, cell: Vector2i) -> Dictionary:
	var key := Vector2i(floori(float(cell.x)/PAGE_SIZE),floori(float(cell.y)/PAGE_SIZE))
	var pages: Dictionary = pages_by_kind[kind]
	var entry: Dictionary = pages.get(key,{})
	if entry.is_empty():
		while retained.size() >= maxi(1,maximum_pages):
			var token: Variant = retained.keys()[0]
			var old: Dictionary = retained[token]
			pages_by_kind[old["kind"]].erase(old["page"])
			retained.erase(token)
		var cells := PackedByteArray()
		cells.resize(PAGE_SIZE*PAGE_SIZE)
		cells.fill(0)
		entry = {"cells":cells,"revision":-1,"stamp":-1,"token":next_token}
		retained[next_token] = {"kind":kind,"page":key}
		next_token += 1
		pages[key] = entry
	if int(entry["revision"]) != revision:
		var stamp := full_revision
		var halo: int = halos[kind]
		for y in range(-halo,halo+1):
			for x in range(-halo,halo+1): stamp = maxi(stamp,int(page_revisions.get(key+Vector2i(x,y),0)))
		if int(entry["stamp"]) != stamp:
			var cells: PackedByteArray = entry["cells"]
			cells.fill(0)
			entry["cells"] = cells
			entry["stamp"] = stamp
		entry["revision"] = revision
	return entry
func lookup(kind: String, position: Vector2) -> int:
	var cell := Vector2i(position.floor())
	return int(_entry(kind,cell)["cells"][posmod(cell.y,PAGE_SIZE)*PAGE_SIZE+posmod(cell.x,PAGE_SIZE)])
func store(kind: String, position: Vector2, supported: bool) -> void:
	var cell := Vector2i(position.floor())
	var entry := _entry(kind,cell)
	var cells: PackedByteArray = entry["cells"]
	cells[posmod(cell.y,PAGE_SIZE)*PAGE_SIZE+posmod(cell.x,PAGE_SIZE)] = 1 if supported else 2
	entry["cells"] = cells

# Prepare page stamps once per worker search, then skip cached rejections in
# native code. Unknown cells still take the original placement checks.
func ring_cells(kind: String, center: Vector2i, radius: int, size: Vector2i, seen: Dictionary) -> Array:
	var pages: Dictionary = {}
	var minimum := Vector2i(maxi(0,center.x-radius)/PAGE_SIZE,maxi(0,center.y-radius)/PAGE_SIZE)
	var maximum := Vector2i(mini(size.x-1,center.x+radius)/PAGE_SIZE,mini(size.y-1,center.y+radius)/PAGE_SIZE)
	for y in range(minimum.y,maximum.y+1):
		for x in range(minimum.x,maximum.x+1):
			pages[Vector2i(x,y)] = _entry(kind,Vector2i(x,y)*PAGE_SIZE)["cells"]
	return native_kernel.build_site_ring_cells(center,radius,size,seen,pages)
