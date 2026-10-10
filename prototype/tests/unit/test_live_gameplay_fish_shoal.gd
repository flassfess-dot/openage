extends SceneTree
const RenderWorld := preload("res://scripts/render_world.gd")
const Picking := preload("res://scripts/picking_service.gd")
const Shoal := preload("res://scripts/fish_shoal_selection.gd")
const Context := preload("res://scripts/context_resolver.gd")
var failures: Array[String] = []

func project(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * 32.0, (point.x + point.y) * 16.0)

func _initialize() -> void:
	var resources: Array = []
	for index in range(4):
		resources.append({"id": index + 1, "kind": "deep_fish", "entity_type": "resource", "pos": Vector2(10 + index, 10) if index < 3 else Vector2(24, 10), "amount": 100, "selection_radius": 1.0})
	var snapshot := {"tick": 0, "resources": resources, "units": [], "buildings": []}
	var renderer := RenderWorld.new()
	var highlighted: Array[int] = [1, 2, 3]
	var items: Array = renderer.create_world_drawables(snapshot, project, 1.0, Callable(), highlighted)
	var outlines: Array = items.filter(func(item): return item["kind"] == "selection")
	check(outlines.size() == 1, "three nearby fish receive one common outline")
	if outlines.size() == 1:
		check(outlines[0]["data"]["selection_member_ids"].size() == 3, "outline contains all members of one school")
		var geometry: Dictionary = Shoal.geometry(outlines[0]["data"], project, 1.0)
		check(Vector2(geometry["radius"]).x > 64.0, "school has one large ellipse")
	var picking := Picking.new()
	for index in range(3):
		var hits: Array = picking.hit_stack(project(resources[index]["pos"]), items, project, 1.0)
		check(not hits.is_empty(), "every part of the school is selectable")
		if not hits.is_empty():
			check(int(hits[0]["id"]) == 1, "all parts select the same school")
			var worker := {"id": 90, "team": 1, "kind": "fishing_boat", "components": {"worker": {"enabled": true}}}
			var resolution: Dictionary = Context.resolve([worker], picking.context_entity(hits[0]), resources[index]["pos"], 1)
			check(resolution.get("type") == "gather" and int(resolution.get("target_id", -1)) == 1, "school click still targets a real harvestable resource")
	var distant: Array = picking.hit_stack(project(resources[3]["pos"]), items, project, 1.0)
	check(not distant.is_empty() and int(distant[0]["id"]) == 4, "distant school keeps its own selection")
	# Retained resource-cache path must keep the common outline on later ticks.
	snapshot["tick"] = 1
	items = renderer.create_world_drawables(snapshot, project, 1.0, Callable(), highlighted)
	outlines = items.filter(func(item): return item["kind"] == "selection")
	check(outlines.size() == 1 and outlines[0]["data"].has("selection_members"), "cached school keeps one grouped outline")
	resources[0]["amount"] = 0
	items = renderer.create_world_drawables(snapshot, project, 1.0, Callable(), highlighted)
	var surviving: Array = picking.hit_stack(project(resources[1]["pos"]), items, project, 1.0)
	check(not surviving.is_empty() and int(surviving[0]["id"]) == 2, "depleted leader is replaced by a living school member")
	check(not Picking.resource_is_selectable(resources[0]), "depleted fish are no longer selectable")
	finish("Live gameplay fish school selection")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
