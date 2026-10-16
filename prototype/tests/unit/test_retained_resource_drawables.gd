extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
const Item := preload("res://scripts/render_item.gd")
var failures: Array[String] = []
var resolved := 0
var camera := Vector2.ZERO
func project(point: Vector2) -> Vector2: return Vector2((point.x-point.y)*32, (point.x+point.y)*16)+camera
func frame_info(_kind: String, row: Dictionary) -> Dictionary:
	resolved += 1
	return {"frame_index": int(row.get("depletion_stage", row.get("decay_elapsed", 0))), "hotspot": Vector2(20,30), "shadow": {"frame_index": 0}}
func _initialize() -> void:
	var renderer := Renderer.new()
	var resources: Array = []
	for i in range(400): resources.append({"id": i+1, "kind": "tree", "pos": Vector2(i%20,i/20), "amount": 100, "tree_phase": "standing"})
	var snapshot := {"resources": resources}
	var items := renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 400, "first viewport resolves each resource once")
	for tick in range(8):
		camera += Vector2(3,2)
		resources[1] = resources[1].duplicate()
		resources[1]["amount"] -= 1
		items = renderer.create_world_drawables(snapshot, project, 1, frame_info)
		verify(items)
	check(resolved == 400, "pan and amount updates reuse static frame descriptors")
	resources.remove_at(0)
	resources.append({"id": 401, "kind": "tree", "pos": Vector2(21,20), "amount": 100})
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 401 and renderer.cached_resource_records.size() == 400 and not renderer.cached_resource_records.has(1), "entering resource resolves alone; departing one is evicted")
	resources[0]["depletion_stage"] = 1
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 402, "depletion changes only one record")
	var highlighted: Array[int] = [int(resources[0]["id"])]
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, highlighted)
	check(resolved == 403 and items.filter(func(item): return item["kind"] == "selection").size() == 1, "highlight changes only one record")
	resources[0]["tree_phase"] = "felled"
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, highlighted)
	check(not items.any(func(item): return item["kind"] == "resource_shadow" and item["stable_id"] == resources[0]["id"]), "felled trunk loses standing-tree shadow")
	verify(items)
	var corpse := {"id": 500, "kind": "gazelle_carcass", "behavior_tags": ["carcass"], "pos": Vector2.ONE, "amount": 100, "decay_elapsed": 0.0}
	snapshot["resources"] = [corpse]
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	corpse["decay_elapsed"] = 2.0
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(items[0]["frame"] == 2, "retained carcass frames still advance")
	snapshot["resources"] = []
	check(renderer.create_world_drawables(snapshot, project).is_empty() and renderer.cached_resource_records.is_empty(), "empty viewport releases retained records")
	renderer.clear_caches()
	check(renderer.cached_resource_raw_drawables.is_empty(), "match reset releases resource drawables")
	# Immutable viewport reuse must keep schools animated and pickable while
	# unrelated trees change. Panning must move the grouped selection too.
	var fish := {"id": 700, "kind": "shore_fish", "pos": Vector2(3, 4), "amount": 100}
	fish.make_read_only()
	var immutable_tree := {"id": 701, "kind": "tree", "pos": Vector2(4, 4), "amount": 100}
	immutable_tree.make_read_only()
	var view: Array = [fish, immutable_tree]
	view.make_read_only()
	snapshot["resources"] = view
	var fish_highlight: Array[int] = [700]
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, fish_highlight)
	var group: Dictionary = items.filter(func(item): return item["kind"] == "resource" and item["stable_id"] == 700)[0]["selection_group"]
	var before := resolved
	camera += Vector2(30, 20)
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, fish_highlight)
	verify(items)
	check(resolved == before + 1, "unchanged immutable view resolves only animated fish, not trees")
	check(is_same(group, items.filter(func(item): return item["kind"] == "resource" and item["stable_id"] == 700)[0]["selection_group"]), "unchanged schools retain grouping and picking membership")
	var changed_tree := immutable_tree.duplicate()
	changed_tree["amount"] = 90
	changed_tree.make_read_only()
	view = [fish, changed_tree]
	view.make_read_only()
	snapshot["resources"] = view
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, fish_highlight)
	check(is_same(group, items.filter(func(item): return item["kind"] == "resource" and item["stable_id"] == 700)[0]["selection_group"]), "tree harvesting does not rebuild fish schools")
	view = [changed_tree]
	view.make_read_only()
	snapshot["resources"] = view
	items = renderer.create_world_drawables(snapshot, project, 1, frame_info, fish_highlight)
	check(not items.any(func(item): return item["data"].has("selection_members")), "departing fish evicts their grouped selection")
	renderer.clear_caches()
	check(renderer.cached_resource_input.is_empty() and renderer.cached_resource_animated.is_empty(), "reset releases retained publication and animation sources")
	for failure in failures: push_error(failure)
	print("Retained resource drawables: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func verify(items: Array) -> void:
	for i in range(items.size()):
		check(items[i]["screen_position"] == project(items[i]["world_anchor"]), "retained resource stays attached during pan")
		if i > 0: check(not Item.less(items[i], items[i-1]), "retained and changed records keep depth order")
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
