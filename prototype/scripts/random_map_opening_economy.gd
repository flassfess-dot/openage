extends RefCounted

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Rules := preload("res://scripts/terrain_rules.gd")

# Claim each settlement's essentials before any surplus or neutral deposits.
# A reserved tile can carry a gathering path even when it cannot host a tree.
static func place(definition: Dictionary, data: Dictionary, fields: Dictionary, reserved: Dictionary, seed: int) -> void:
	var generator: Dictionary = definition["map"]["generator"]
	var quality: Dictionary = generator["quality_contract"]
	var required: Dictionary = quality["resource_counts"]
	var walking_limit := int(quality["maximum_gather_path_cells"])
	var walkable := Navigation.mask(data, definition)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var groups: Array[Dictionary] = []
	for cluster in generator["resource_clusters"]:
		if not cluster.has("owner_start"): continue
		var owner: Array = cluster["owner_start"]
		var start := Vector2(owner[0], owner[1])
		var aim := start + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 12.0)
		groups.append({"spec": cluster, "start": start, "aim": aim, "placed": 0})
	for essentials in [true, false]:
		for group in groups:
			var spec: Dictionary = group["spec"]
			var target := int(required.get(spec["kind"], 0)) if essentials else int(spec["count"])
			if target > int(group["placed"]):
				_place_group(group, target, walking_limit, data, fields, reserved, walkable)

static func _place_group(group: Dictionary, target: int, walking_limit: int, data: Dictionary, fields: Dictionary, reserved: Dictionary, walkable: PackedByteArray) -> void:
	var size: Vector2i = data["size"]
	var spec: Dictionary = group["spec"]
	var start: Vector2 = group["start"]
	var reach := ceili(float(spec["guarantee_radius"]))
	var field := Navigation.flood(size, walkable, Vector2i(start), walking_limit)
	var candidates: Array[Dictionary] = []
	for y in range(maxi(0, int(start.y) - reach), mini(size.y, int(start.y) + reach + 1)):
		for x in range(maxi(0, int(start.x) - reach), mini(size.x, int(start.x) + reach + 1)):
			var cell := Vector2i(x, y)
			var i := y * size.x + x
			var distance: int = field["distances"][i]
			if distance <= 0 or reserved.has(cell) or data["terrain_ids"][i] in Rules.WATER_TERRAIN_IDS: continue
			var position := Vector2(cell) + Vector2.ONE * 0.5
			if start.distance_squared_to(position) > reach * reach: continue
			var score := position.distance_to(group["aim"]) + distance * 0.35
			var woodland := float(fields["forest_strength"][i])
			score += woodland * (-3.0 if spec["kind"] == "tree" else 3.0)
			candidates.append({"i": i, "score": score})
	candidates.sort_custom(func(a, b): return a["score"] < b["score"] if a["score"] != b["score"] else a["i"] < b["i"])
	for candidate in candidates:
		var i: int = candidate["i"]
		var cell := Vector2i(i % size.x, i / size.x)
		if reserved.has(cell): continue
		var path := Navigation.trace(field, field["parents"][i])
		var clear := true
		for at in path:
			if walkable[at] == 0:
				clear = false
				break
		if not clear: continue
		Navigation.reserve_path(reserved, path, size, walkable, 0)
		reserved[cell] = true
		walkable[i] = 0
		data["resources"].append({"category": "resource", "kind": spec["kind"], "amount": int(spec["amount"]),
			"position": Vector2(cell) + Vector2.ONE * 0.5, "placement_domain": "land", "owner_start": spec["owner_start"], "guarantee_team": 0})
		group["placed"] += 1
		if group["placed"] >= target: break
