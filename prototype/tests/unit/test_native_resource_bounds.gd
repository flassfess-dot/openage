extends SceneTree
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null or not kernel.has_method("known_resources_in_bounds"): push_error("Current native resource bounds query is required");quit(1);return
	var known := {}
	var chunks := {}
	for index in range(1600):
		var id := 1600-index
		var pos := Vector2((index%40)*0.7-3.2,(index/40)*0.7-2.4)
		var row := Data.capture_frozen({"id":id,"pos":pos,"amount":100,"behavior_tags":["tree"]})
		known[id] = row
		var chunk := Vector2i(floori(pos.x/8.0),floori(pos.y/8.0))
		if not chunks.has(chunk): chunks[chunk] = {}
		chunks[chunk][id] = true
	for bounds in [Rect2i(-8,-8,48,48),Rect2i(0,0,8,8),Rect2i(8,8,16,16),Rect2i(-4,-4,4,4),Rect2i(24,24,1,1),Rect2i(4,4,0,8),Rect2i(100,100,8,8)]:
		var expected: Array = known.values().filter(func(row): return bounds.has_point(Vector2i(Vector2(row["pos"]).floor())))
		expected.sort_custom(func(a,b): return int(a["id"]) < int(b["id"]))
		var actual: Array = kernel.known_resources_in_bounds(known,chunks,bounds,8)
		check(actual == expected and actual.is_read_only(),"native bounds query matches exact cells, edge exclusion and stable ID order")
		for index in range(actual.size()): check(is_same(actual[index],expected[index]),"unchanged legal memory rows retain their immutable identity")
	check(kernel.known_resources_in_bounds(known,chunks,Rect2i(0,0,8,8),0).is_empty(),"invalid bucket size is bounded")
	for failure in failures: push_error(failure)
	print("Native resource bounds: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
