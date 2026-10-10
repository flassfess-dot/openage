class_name RoRFishShoalSelection
extends RefCounted

const RenderItem := preload("res://scripts/render_item.gd")
const KINDS := ["deep_fish", "shore_fish"]
const GROUP_DISTANCE := 3.0

static func is_fish(resource: Dictionary) -> bool:
	return String(resource.get("kind", "")) in KINDS and int(resource.get("amount", 0)) > 0

static func group_drawables(drawables: Array, highlighted_ids: Array[int], project: Callable) -> Array:
	var fish: Array = []
	var buckets: Dictionary = {}
	var bodies: Dictionary = {}
	for item in drawables:
		if String(item.get("kind", "")) != "resource" or not is_fish(item.get("data", {})): continue
		var resource: Dictionary = item["data"]
		fish.append(resource)
		bodies[int(resource["id"])] = item
		var cell := Vector2i((Vector2(resource["pos"]) / GROUP_DISTANCE).floor())
		if not buckets.has(cell): buckets[cell] = []
		buckets[cell].append(resource)
	if fish.is_empty(): return drawables
	fish.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	var used: Dictionary = {}
	var selections: Array = []
	for leader in fish:
		var leader_id := int(leader["id"])
		if used.has(leader_id): continue
		var members: Array = []
		var cell := Vector2i((Vector2(leader["pos"]) / GROUP_DISTANCE).floor())
		for y in range(-1, 2):
			for x in range(-1, 2):
				for resource in buckets.get(cell + Vector2i(x, y), []):
					var id := int(resource["id"])
					if used.has(id) or resource["kind"] != leader["kind"]: continue
					# Bound each school around its leader; chains must not join an ocean.
					if Vector2(resource["pos"]).distance_squared_to(leader["pos"]) > GROUP_DISTANCE * GROUP_DISTANCE: continue
					members.append(resource)
					used[id] = true
		var group: Dictionary = leader.duplicate()
		group["selection_members"] = members
		group["selection_member_ids"] = members.map(func(resource): return int(resource["id"]))
		var highlighted := false
		for member in members:
			bodies[int(member["id"])]["selection_group"] = group
			if highlighted_ids.has(int(member["id"])): highlighted = true
		if highlighted:
			selections.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, leader["pos"], project.call(leader["pos"]), leader_id, group, {}, 0.0, Color("d6bc63")))
	var result: Array = []
	for item in drawables:
		if String(item.get("kind", "")) == "selection" and is_fish(item.get("data", {})): continue
		result.append(item)
	result.append_array(selections)
	return result

static func geometry(group: Dictionary, project: Callable, zoom: float) -> Dictionary:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for member in group.get("selection_members", [group]):
		var position: Vector2 = project.call(Vector2(member.get("pos", Vector2.ZERO)))
		var selection: Variant = member.get("selection_radius", member.get("footprint", {}).get("selection_radius", 1.0))
		var extent: float = maxf(selection.x, selection.y) if selection is Vector2 else float(selection)
		var radius := Vector2(maxf(24.0, extent * 32.0), maxf(12.0, extent * 16.0)) * zoom
		minimum = minimum.min(position - radius)
		maximum = maximum.max(position + radius)
	return {"center": (minimum + maximum) * 0.5, "radius": (maximum - minimum) * 0.5 * sqrt(2.0)}
