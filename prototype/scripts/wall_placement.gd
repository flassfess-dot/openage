class_name RoRWallPlacement
extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")


static func cells(start: Vector2i, finish: Vector2i, maximum_segments: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x := start.x
	var y := start.y
	var dx := absi(finish.x - start.x)
	var dy := absi(finish.y - start.y)
	var step_x := 1 if start.x < finish.x else -1
	var step_y := 1 if start.y < finish.y else -1
	var error := dx - dy
	while maximum_segments <= 0 or result.size() < maximum_segments:
		result.append(Vector2i(x, y))
		if x == finish.x and y == finish.y:
			break
		var doubled_error := error * 2
		if doubled_error > -dy:
			error -= dy
			x += step_x
		if doubled_error < dx:
			error += dx
			y += step_y
	return result


# Native SLP direction 0 follows world Y, direction 1 follows world X.
# Only a straight pair keeps a panel; ends, corners and dense rows use a block.
static func presentation_facing(mask: int) -> int:
	match mask & 15:
		5: return 0
		10: return 1
		_: return 2


static func connectivity_key(building: Dictionary) -> String:
	var group := String(building.get("connectivity_group", ""))
	if group == "wall":
		var source_id := int(building.get("source_unit_id", -1))
		if String(building.get("kind", "")) == "gate":
			source_id -= 10000
		group += ":%d" % source_id
	return "%d:%s" % [int(building.get("team", 0)), group]


static func connection_cells(building: Dictionary) -> Array:
	var cells: Array = building.get("occupied_cells", building.get("footprint", {}).get("occupied_cells", []))
	if String(building.get("kind", "")) != "gate" or cells.size() < 2:
		return cells
	var ordered: Array = cells.duplicate()
	var axis := int(building.get("gate_axis", 0))
	ordered.sort_custom(func(a, b): return a[axis] < b[axis])
	# A wall attaches to masonry, never to the gate opening.
	return [ordered[0], ordered[-1]]


static func masonry_center(building: Dictionary) -> Vector2:
	var position := Vector2(building.get("pos",Vector2.ZERO))
	if String(building.get("kind","")) != "gate":
		return position
	var piers := connection_cells(building)
	return (Vector2(piers[0])+Vector2(piers[1]))*0.5 if piers.size() == 2 else position


# Selection and hit testing must use the same tile-aligned center as gate art.
static func selection_polygon(building: Dictionary) -> PackedVector2Array:
	var footprint: Dictionary = building.get("footprint", {})
	if String(building.get("kind", "")) != "gate" and footprint.has("polygon"):
		return PackedVector2Array(footprint["polygon"])
	var center := masonry_center(building)
	var half := Vector2(footprint.get("half_size", Vector2(0.5, 0.5)))
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])


static func mask_at(occupied: Dictionary, cell: Vector2i) -> int:
	var result := 0
	var offsets := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for direction in range(4):
		if occupied.has(cell + offsets[direction]):
			result |= 1 << direction
	return result


static func plan(world, team: int, line: Array[Vector2i]) -> Dictionary:
	var source: Dictionary = world.object_record_for("wall", team)
	var source_id := int(world.technology_system.resolved_unit_id(team, int(source.get("unit_id", 72))))
	source = world.object_record_by_id(source_id, team)
	var existing: Dictionary = {}
	for building in world.get_buildings():
		if String(building.get("kind", "")) != "wall" or int(building.get("team", 0)) != team or int(building.get("source_unit_id", -1)) != source_id or float(building.get("hp", 0.0)) <= 0.0 or String(building.get("state", "")) == "destroyed":
			continue
		for cell in building.get("occupied_cells", []):
			existing[Vector2i(cell)] = building
	var occupied: Dictionary = existing.duplicate()
	for building in world.get_buildings():
		if String(building.get("kind", "")) != "gate" or int(building.get("team", 0)) != team or int(building.get("source_unit_id", -1)) != source_id + 10000 or float(building.get("hp", 0.0)) <= 0.0 or String(building.get("state", "")) == "destroyed":
			continue
		for cell in connection_cells(building):
			occupied[Vector2i(cell)] = true
	var cost: Dictionary = world.building_cost("wall", team)
	var remaining: Dictionary = {}
	for resource_id in cost:
		remaining[resource_id] = world.get_resource_amount(team, int(resource_id))
	var entries: Array = []
	var planned_positions: Array[Vector2] = []
	var half_size: Vector2 = Footprint.building(world.unit_stats("wall"), Vector2.ZERO)["obstruction_half_size"]
	var seen: Dictionary = {}
	for cell in line:
		if seen.has(cell):
			continue
		seen[cell] = true
		var position := Vector2(clampf(cell.x, 0.5, world.map_size.x - 0.5), clampf(cell.y, 0.5, world.map_size.y - 0.5))
		var entry := {
			"cell": cell, "position": position, "valid": false,
			"reason": "", "status": "blocked", "building_id": -1,
		}
		if existing.has(cell):
			var building: Dictionary = existing[cell]
			entry["valid"] = true
			entry["status"] = "reuse" if String(building.get("state", "")) == "foundation" else "existing"
			entry["building_id"] = int(building["id"])
		else:
			entry["valid"] = world.can_place_foundation(team, "wall", position)
			entry["reason"] = world.last_build_failure
			if entry["valid"]:
				# Clamping at the map edge can move adjacent anchors closer than
				# one footprint. Preview the same collision as actual reservation.
				for planned_position in planned_positions:
					var delta := (planned_position - position).abs()
					if delta.x < half_size.x * 2.0 - 0.001 and delta.y < half_size.y * 2.0 - 0.001:
						entry["valid"] = false
						entry["reason"] = "blocked_or_sloped"
						break
			if entry["valid"]:
				for resource_id in cost:
					if int(remaining[resource_id]) < int(cost[resource_id]):
						entry["valid"] = false
						entry["reason"] = "insufficient_resources"
						break
			if entry["valid"]:
				entry["status"] = "new"
				occupied[cell] = true
				planned_positions.append(position)
				for resource_id in cost:
					remaining[resource_id] -= int(cost[resource_id])
		entries.append(entry)
	var previews: Array = []
	var neighbor_cells: Dictionary = {}
	for entry in entries:
		var cell: Vector2i = entry["cell"]
		var mask := mask_at(occupied, cell)
		entry["connection_mask"] = mask
		entry["ghost"] = _ghost(world, team, source_id, source, entry["position"], mask)
		if String(entry["status"]) == "existing":
			entry["ghost"]["hp"] = existing[cell]["hp"]
			entry["ghost"]["max_hp"] = existing[cell]["max_hp"]
		previews.append(entry)
		if not bool(entry["valid"]):
			continue
		for offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if existing.has(cell + offset) and not seen.has(cell + offset):
				neighbor_cells[cell + offset] = true
	for cell in neighbor_cells:
		var building: Dictionary = existing[cell]
		var mask := mask_at(occupied, cell)
		if int(building.get("connection_mask", 0)) == mask:
			continue
		var ghost := _ghost(world, team, source_id, source, building["pos"], mask)
		if String(building.get("state", "")) != "foundation":
			ghost["hp"] = building["hp"]
			ghost["max_hp"] = building["max_hp"]
		previews.append({"cell": cell, "position": building["pos"], "valid": true, "status": "neighbor", "ghost": ghost})
	previews.sort_custom(func(a, b):
		var ap: Vector2 = a["position"]
		var bp: Vector2 = b["position"]
		return ap.x + ap.y < bp.x + bp.y or (is_equal_approx(ap.x + ap.y, bp.x + bp.y) and ap.x < bp.x)
	)
	return {"entries": entries, "previews": previews, "source_unit_id": source_id, "remaining_resources": remaining}


static func _ghost(world, team: int, source_id: int, source: Dictionary, position: Vector2, mask: int) -> Dictionary:
	return {
		"kind": "wall", "team": team, "pos": position, "source_unit_id": source_id,
		"display_graphic_id": int(source.get("graphics", {}).get("idle", -1)),
		"state": "complete", "hp": float(source.get("health", 200.0)),
		"max_hp": float(source.get("health", 200.0)), "connection_mask": mask,
		"components": {"ownership": {"civilization_id": int(world.civilization_by_team.get(team, 13))}},
	}
