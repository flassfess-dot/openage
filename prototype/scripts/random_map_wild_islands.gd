class_name RoRRandomMapWildIslands
extends RefCounted

const VERSION := 5
const Base := preload("res://scripts/random_map_landscape.gd")
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Water := preload("res://scripts/random_map_water.gd")
const CliffChain := preload("res://scripts/cliff_chain.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")

# Landforms and regional ecology do not receive player count or positions.
static func geography(size: Vector2i, seed: int, river_network: bool = false) -> Dictionary:
	var span := float(mini(size.x, size.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5711D
	var forms: Array = []
	var cores: Array = []
	for i in range(rng.randi_range(4, 7) if river_network else rng.randi_range(2, 4)):
		var center := Vector2(rng.randf_range(0.18, 0.82) * size.x, rng.randf_range(0.18, 0.82) * size.y)
		if river_network:
			for attempt in range(80):
				if cores.all(func(core): return center.distance_to(core["center"]) > span * 0.22): break
				center = Vector2(rng.randf_range(0.13, 0.87) * size.x, rng.randf_range(0.13, 0.87) * size.y)
		var radius := span * (rng.randf_range(0.055, 0.105) if river_network else rng.randf_range(0.085, 0.17))
		var angle := rng.randf() * TAU
		cores.append({"center": center, "radius": radius, "angle": angle})
		forms.append({"center": center, "radii": Vector2(radius * rng.randf_range(0.9, 1.5), radius * rng.randf_range(0.55, 1.0)), "angle": angle, "group": i})
		# Unequal attached lobes build headlands, bays and branching peninsulas.
		for lobe in range(rng.randi_range(2, 5)):
			var direction := angle + rng.randf_range(-2.4, 2.4)
			var offset := Vector2.from_angle(direction) * radius * rng.randf_range(0.55, 1.25)
			forms.append({"center": center + offset, "radii": Vector2(radius * rng.randf_range(0.40, 0.85), radius * rng.randf_range(0.30, 0.65)), "angle": direction, "group": i})
	var families := maxi(4, roundi(span / 43.0))
	for family in range(families):
		var center := Vector2(rng.randf_range(0.08, 0.92) * size.x, rng.randf_range(0.08, 0.92) * size.y)
		var direction := Vector2.from_angle(rng.randf() * TAU)
		var length := span * rng.randf_range(0.07, 0.23)
		for island in range(rng.randi_range(4, 9)):
			var at := center + direction * rng.randf_range(-length, length)
			at += direction.orthogonal() * span * rng.randf_range(-0.035, 0.035)
			var radius := maxf(3.0, span * lerpf(0.012, 0.070, pow(rng.randf(), 2.2)))
			forms.append({"center": at, "radii": Vector2(radius * rng.randf_range(0.75, 1.8), radius * rng.randf_range(0.55, 1.1)), "angle": rng.randf() * PI, "group": 100 + family})
	var silhouette := PackedFloat32Array()
	silhouette.resize(size.x * size.y)
	silhouette.fill(-2.0)
	var runner_up := silhouette.duplicate()
	var owners := PackedInt32Array()
	owners.resize(silhouette.size())
	owners.fill(-1)
	for form in forms:
		var center: Vector2 = form["center"]
		var radii: Vector2 = form["radii"]
		var extent := radii.length() * 1.25
		for y in range(maxi(0, floori(center.y - extent)), mini(size.y, ceili(center.y + extent))):
			for x in range(maxi(0, floori(center.x - extent)), mini(size.x, ceili(center.x + extent))):
				var local := (Vector2(x + 0.5, y + 0.5) - center).rotated(-float(form["angle"])) / radii
				var i := y * size.x + x
				var value := 1.0 - local.length()
				if river_network and int(form["group"]) != owners[i]:
					if value > silhouette[i]:
						runner_up[i] = silhouette[i]
						owners[i] = int(form["group"])
					else:
						runner_up[i] = maxf(runner_up[i], value)
				silhouette[i] = maxf(silhouette[i], value)
	var coastal := Natural.noise_field(size, maxf(8.0, span * 0.09), seed ^ 0x8147)
	var shore_detail := Natural.noise_field(size, 5.0, seed ^ 0x6382)
	var terrain: Array[int] = []
	terrain.resize(silhouette.size())
	for i in range(terrain.size()):
		var perturbation := (coastal[i] - 0.5) * 0.65 + (shore_detail[i] - 0.5) * 0.15
		terrain[i] = 0 if silhouette[i] + perturbation > 0.0 else 1
		if river_network and runner_up[i] > -0.15 and silhouette[i] - runner_up[i] < 0.19 + (coastal[i] - 0.5) * 0.09:
			terrain[i] = 1
	Water.smooth_coast(terrain, size)
	var empty_starts: Array[Vector2] = []
	var fields := Natural.fields(size, terrain, empty_starts, "highlands", seed ^ 0x8194)
	var rivers: Dictionary = {}
	if river_network:
		rivers = Rivers.carve(size, terrain, fields)
		fields = Natural.fields(size, terrain, empty_starts, "highlands", seed ^ 0x8194)
	fields["recipe"] = fields["recipe"].duplicate(true)
	fields["recipe"]["forest_threshold"] = 0.53
	var climate := Natural.noise_field(size, span * 0.34, seed ^ 0x6819)
	var woodland := Natural.noise_field(size, maxf(10.0, span * 0.10), seed ^ 0x8351)
	var local_wood := Natural.noise_field(size, 11.0, seed ^ 0x6512)
	for i in range(terrain.size()):
		fields["moisture"][i] = clampf(climate[i] * 0.85 + woodland[i] * 0.15 + 0.08, 0.0, 1.0)
		var strength := climate[i] * 0.52 + woodland[i] * 0.36 + local_wood[i] * 0.12
		fields["forest_strength"][i] = strength
		fields["forest_potential"][i] = int(terrain[i] == 0 and fields["coast_distance"][i] > 1 and strength > 0.53)
		if river_network and rivers["mask"][i] != 0: fields["forest_potential"][i] = 0
	var scenery: Array = []
	var cells: Dictionary = {}
	var used: Dictionary = {}
	var mountain_rng := RandomNumberGenerator.new()
	mountain_rng.seed = seed ^ 0x71945
	for core in cores:
		for ridge in range(mountain_rng.randi_range(1, 3)):
			var center := Vector2i(Vector2(core["center"]) + Vector2(mountain_rng.randf_range(-0.5, 0.0), mountain_rng.randf_range(-0.3, 0.5)) * float(core["radius"]))
			var sign_axis := 1 if mountain_rng.randf() < 0.5 else -1
			for step in range(roundi(float(core["radius"]) * mountain_rng.randf_range(0.7, 1.8) / 3.0)):
				var valid := true
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var cell := center + Vector2i(dx, dy)
						if not Navigation.inside(cell, size) or terrain[cell.y * size.x + cell.x] != 0: valid = false
				if valid and not used.has(center) and mountain_rng.randf() > 0.06:
					Base._append_cliff_strip(scenery, cells, used, center, Vector2i.RIGHT, size, terrain, fields["vertex_levels"], seed)
				center += (Vector2i.RIGHT if mountain_rng.randf() > 0.32 else Vector2i.UP) * CliffChain.STRIDE * sign_axis
	CliffChain.apply(scenery)
	var walkable := PackedByteArray()
	walkable.resize(terrain.size())
	for i in range(terrain.size()): walkable[i] = int(terrain[i] == 0)
	for cell in cells: walkable[cell.y * size.x + cell.x] = 0
	return {"size": size, "terrain": terrain, "fields": fields, "ridge_cells": cells.keys(), "ridge_scenery": scenery, "rivers": rivers,
		"landforms": forms, "walkable": walkable, "woodland_regions": families, "landmass_seeds": forms.size(), "profile": "islands", "wild": true}

static func contract(generator: Dictionary, geography_data: Dictionary, starts: Array[Vector2], seed: int) -> Dictionary:
	var result := generator.duplicate(true)
	result["version"] = VERSION
	result["theme"] = "wild_islands_v5"
	result["wild_geography"] = true
	if not geography_data.get("rivers", {}).is_empty(): result["river_network"] = true
	result["requires_naval_starts"] = false
	result["naval_resource_clusters"] = []
	result["water_ratio"] = [0.10, 0.95]
	result["quality_contract"]["resource_counts"] = {"tree": 2, "berries": 1}
	result["quality_contract"]["naval_resource_counts"] = {}
	result["quality_contract"]["minimum_start_distance_fraction"] = 0.025
	# Opening viability is a small, uneven food/wood foothold. Minerals and all
	# expansion wealth belong to geographic regions, with no player allocation.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x13E91
	var clusters: Array = []
	for start in starts:
		for kind in ["tree", "berries"]:
			clusters.append({"kind": kind, "count": rng.randi_range(3, 11) if kind == "tree" else rng.randi_range(2, 7),
				"radius": rng.randf_range(1.0, 3.5), "amount": 75 if kind == "tree" else 150, "owner_start": [start.x, start.y],
				"minimum_distance": rng.randf_range(4.0, 7.0), "maximum_distance": rng.randf_range(10.0, 18.0), "guarantee_radius": 20.0})
	var size: Vector2i = geography_data["size"]
	var deposits := 0
	for attempt in range(1600):
		if deposits >= maxi(12, size.x * size.y / 850): break
		var cell := Vector2i(rng.randi_range(2, size.x - 3), rng.randi_range(2, size.y - 3))
		var i := cell.y * size.x + cell.x
		if geography_data["terrain"][i] != 0 or geography_data["fields"]["coast_distance"][i] < 3: continue
		if float(geography_data["fields"]["geology"][i]) < 0.52: continue
		clusters.append({"kind": "gold_mine" if rng.randf() < 0.5 else "stone_mine", "count": rng.randi_range(3, 15),
			"center": [cell.x + 0.5, cell.y + 0.5], "radius": rng.randf_range(1.2, 3.4), "amount": 400, "placement_radius": 5.0})
		deposits += 1
	result["resource_clusters"] = clusters
	result["source_profile"]["unit_groups"] = result["source_profile"].get("unit_groups", []).filter(func(group): return int(group.get("unit_id", -1)) not in [66, 102])
	return result
