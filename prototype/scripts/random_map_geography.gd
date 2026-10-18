class_name RoRRandomMapGeography
extends RefCounted

# Opt-in geography-first pilot. No player positions enter this stage.
const VERSION := 4
const PROFILES := ["islands", "coastal", "highlands", "grasslands"]
const Base := preload("res://scripts/random_map_landscape.gd")
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const CliffChain := preload("res://scripts/cliff_chain.gd")
const Water := preload("res://scripts/random_map_water.gd")

static func geography(size: Vector2i, profile: String, seed: int, capacity: int) -> Dictionary:
	var span := float(mini(size.x, size.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x61E097
	var insular := profile == "islands"
	var maritime := insular or profile == "coastal"
	var coast_angle := floorf(Topology.roll(Vector2i(17, 29), seed) * 4.0) * PI * 0.5
	var masses: Array = []
	if insular:
		var columns := ceili(sqrt(float(capacity)))
		var rows := ceili(float(capacity) / columns)
		var radius := sqrt(float(size.x * size.y) * 0.37 / (PI * capacity))
		for i in range(capacity):
			var center := Vector2((i % columns + 0.5) * size.x / columns, (i / columns + 0.5) * size.y / rows)
			center += Vector2(rng.randf_range(-0.012, 0.012) * size.x, rng.randf_range(-0.012, 0.012) * size.y)
			masses.append({"center": center, "radii": Vector2(radius * rng.randf_range(0.96, 1.04), radius * rng.randf_range(0.86, 0.98)), "angle": rng.randf_range(-0.6, 0.6), "phase": rng.randf() * TAU})
	# Independent offshore land: channels and gaps remain navigable water.
	if maritime:
		var neutral_count := 0
		for attempt in range(350):
			if neutral_count >= maxi(6, capacity * 2): break
			var center := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y)
			var radius := span * rng.randf_range(0.045, 0.070)
			if attempt < 5:
				center = Vector2(size) * [Vector2(0.5, 0.5), Vector2(0.5, 0.04), Vector2(0.04, 0.5), Vector2(0.96, 0.5), Vector2(0.5, 0.96)][attempt]
				radius = span * (0.057 if attempt == 0 else 0.045)
			var separate := true
			for mass in masses:
				var local := (center - Vector2(mass["center"])).rotated(-float(mass["angle"])) / Vector2(mass["radii"])
				if local.length() < 1.13 + (radius * 1.25 + 4.0) / minf(mass["radii"].x, mass["radii"].y): separate = false
			if not separate: continue
			masses.append({"center": center, "radii": Vector2(radius * 1.25, radius), "angle": rng.randf() * PI, "phase": rng.randf() * TAU, "neutral": true})
			neutral_count += 1
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var point := Vector2(x + 0.5, y + 0.5)
			var coast := Topology.noise(point, span * 0.18, seed ^ 0xA417) * span * 0.055
			coast += Topology.noise(point, span * 0.055, seed ^ 0x7381) * span * 0.018
			var channel_point := point
			if insular:
				channel_point += Vector2(Topology.noise(point, span * 0.23, seed ^ 0xE521), Topology.noise(point, span * 0.23, seed ^ 0xA381)) * span * 0.025
			var land := not maritime
			if profile == "coastal":
				# Two large embayments and a projecting headland shape the coast.
				var aligned := (point - Vector2(size) * 0.5).rotated(-coast_angle) + Vector2(size) * 0.5
				var boundary := span * 0.35 + sin(aligned.y / span * TAU * 1.25) * span * 0.12 + coast
				land = aligned.x > boundary
			for mass in masses:
				# Islets are admitted only in open sea, at least four cells from
				# other land. Their geometry never depends on chosen settlements.
				if land: break
				var local := (point - Vector2(mass["center"])).rotated(-float(mass["angle"]))
				var shape := Vector2(local.x / mass["radii"].x, local.y / mass["radii"].y)
				var edge := 1.0 + sin(shape.angle() * 3.0 + float(mass["phase"])) * 0.16 + sin(shape.angle() * 5.0) * 0.08
				land = shape.length() < edge + coast / maxf(1.0, mass["radii"].x) * 0.28
				if land and insular and not bool(mass.get("neutral", false)):
					for other in masses:
						if bool(other.get("neutral", false)) or other["center"] == mass["center"]: continue
						if channel_point.distance_to(other["center"]) - channel_point.distance_to(mass["center"]) < 4.5: land = false
			terrain[y * size.x + x] = 0 if land else 1
	Water.smooth_coast(terrain, size)
	var starts: Array[Vector2] = []
	var fields := Natural.fields(size, terrain, starts, profile, seed ^ 0x641A)
	# Regional woodland domains scale with the map; the fine noise only shapes
	# their margins. These domains exist before routes, settlements or resources.
	var regions: Array = []
	var woodland_rng := RandomNumberGenerator.new()
	woodland_rng.seed = seed ^ 0x71391A
	if insular:
		for mass in masses:
			if bool(mass.get("neutral", false)): continue
			regions.append({"center": Vector2(mass["center"]) + Vector2(mass["radii"].x * 0.30, -mass["radii"].y * 0.20), "radii": Vector2(mass["radii"]) * Vector2(1.05, 0.90)})
	else:
		for i in range(4):
			regions.append({"center": Vector2(size) * Vector2(0.24 + (i % 2) * 0.50, 0.22 + (i / 2) * 0.52) + Vector2(woodland_rng.randf_range(-0.06, 0.06), woodland_rng.randf_range(-0.06, 0.06)) * span,
				"radii": Vector2(span * woodland_rng.randf_range(0.19, 0.28), span * woodland_rng.randf_range(0.19, 0.27))})
	for i in range(terrain.size()):
		var point := Vector2(i % size.x + 0.5, i / size.x + 0.5)
		var strength := 0.0
		for region in regions:
			var delta: Vector2 = (point - Vector2(region["center"])) / Vector2(region["radii"])
			strength = maxf(strength, 1.0 - smoothstep(0.55, 1.18, delta.length()))
		strength = clampf(strength * 0.60 + float(fields["woodland"][i]) * 0.30 + float(fields["moisture"][i]) * 0.10, 0.0, 1.0)
		fields["forest_strength"][i] = strength
		fields["forest_potential"][i] = int(terrain[i] == 0 and fields["coast_distance"][i] > 1 and strength > float(fields["recipe"]["forest_threshold"]))
	var scenery: Array = []
	var cells: Dictionary = {}
	var used: Dictionary = {}
	# Mountain spines are geographic barriers with explicit wide passes and open
	# ends. Their footprint is fixed before candidate settlement sites are scored.
	if not insular:
		for ridge in range(2 if profile == "highlands" else 1):
			var y := roundi(size.y * (0.38 + ridge * 0.25))
			var first := roundi(size.x * (0.49 if maritime else 0.14))
			var last := roundi(size.x * 0.85)
			var ridge_centers: Array[Vector2i] = []
			var previous_offset := 0
			for x in range(first, last, CliffChain.STRIDE):
				var fraction := float(x - first) / maxf(1.0, last - first)
				if fraction > 0.40 and fraction < 0.59: continue
				var offset := (-3 if fraction > 0.25 else 0) + (-3 if fraction > 0.72 else 0)
				if offset != previous_offset:
					ridge_centers.append(Vector2i(x - CliffChain.STRIDE, y + offset))
				previous_offset = offset
				ridge_centers.append(Vector2i(x, y + offset))
			for center in ridge_centers:
				if profile == "coastal": center = Vector2i(((Vector2(center) - Vector2(size) * 0.5).rotated(coast_angle) + Vector2(size) * 0.5).round())
				var valid := true
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var at := center + Vector2i(dx, dy)
						if not Navigation.inside(at, size) or terrain[at.y * size.x + at.x] != 0: valid = false
				if valid: Base._append_cliff_strip(scenery, cells, used, center, Vector2i.RIGHT, size, terrain, fields["vertex_levels"], seed)
	CliffChain.apply(scenery)
	var blocked := PackedByteArray()
	blocked.resize(terrain.size())
	for i in range(terrain.size()): blocked[i] = int(terrain[i] == 0)
	for cell in cells: blocked[cell.y * size.x + cell.x] = 0
	return {"size": size, "terrain": terrain, "fields": fields, "ridge_cells": cells.keys(), "ridge_scenery": scenery, "landforms": masses,
		"walkable": blocked, "woodland_regions": regions.size(), "landmass_seeds": masses.size(), "profile": profile}

static func settlement_sites(geography_data: Dictionary, count: int, seed: int) -> Array[Vector2]:
	var size: Vector2i = geography_data["size"]
	var open: PackedByteArray = geography_data["walkable"]
	var clearance := PackedInt32Array()
	clearance.resize(open.size())
	clearance.fill(999)
	var queue := PackedInt32Array()
	for i in range(open.size()):
		var x := i % size.x
		var y := i / size.x
		if open[i] == 0 or x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
			clearance[i] = 0
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(at, size):
			if clearance[next] > clearance[at] + 1:
				clearance[next] = clearance[at] + 1
				queue.append(next)
	var components := PackedInt32Array()
	components.resize(open.size())
	components.fill(-1)
	var areas: Array = []
	for i in range(open.size()):
		if open[i] == 0 or components[i] >= 0: continue
		var pending := PackedInt32Array([i])
		components[i] = areas.size()
		cursor = 0
		while cursor < pending.size():
			var at := pending[cursor]
			cursor += 1
			for next in Navigation.neighbors(at, size):
				if open[next] != 0 and components[next] < 0:
					components[next] = areas.size()
					pending.append(next)
		areas.append(pending.size())
	var result: Array[Vector2] = []
	var occupied_components: Dictionary = {}
	var insular := String(geography_data["profile"]) == "islands"
	var wild := bool(geography_data.get("wild", false))
	var largest := int(areas.max()) if not areas.is_empty() else 0
	var site_clearance := (5 if mini(size.x, size.y) <= 128 else 7) if wild else 6 if mini(size.x, size.y) <= 48 else 7
	for slot in range(count):
		var best := -INF
		var chosen := -1
		for i in range(open.size()):
			if open[i] == 0 or clearance[i] < site_clearance: continue
			var component := components[i]
			if int(areas[component]) < (96 if wild and mini(size.x, size.y) <= 128 else 180): continue
			if not wild and insular and occupied_components.has(component): continue
			if not wild and not insular and int(areas[component]) != largest: continue
			var point := Vector2(i % size.x + 0.5, i / size.x + 0.5)
			var separation := float(mini(size.x, size.y)) * 0.55
			for start in result: separation = minf(separation, point.distance_to(start))
			if separation < ((8.0 if mini(size.x, size.y) <= 128 else maxf(12.0, mini(size.x, size.y) * 0.025)) if wild else maxf(12.0, mini(size.x, size.y) * 0.16)): continue
			var forest := float(geography_data["fields"]["forest_strength"][i])
			var score := separation + minf(12.0, clearance[i]) * 0.9 - forest * 8.0 + Topology.roll(Vector2i(i, slot), seed ^ 0xA123) * 2.0
			if wild: score = Topology.roll(Vector2i(i, slot), seed ^ 0xA123)
			if score > best:
				best = score
				chosen = i
		if chosen < 0: return []
		result.append(Vector2(chosen % size.x + 0.5, chosen / size.x + 0.5))
		occupied_components[components[chosen]] = true
	return result

static func settle(fields: Dictionary, size: Vector2i, starts: Array[Vector2]) -> void:
	var levels: Array[int] = fields["vertex_levels"]
	var flat: Dictionary = {}
	for start in starts:
		var center := Vector2i(start)
		for y in range(center.y - 4, center.y + 5):
			for x in range(center.x - 4, center.x + 5):
				var cell := Vector2i(x, y)
				if Navigation.inside(cell, size):
					flat[cell] = true
					if Vector2(cell).distance_to(Vector2(center)) <= 3.8:
						fields["forest_potential"][y * size.x + x] = 0
	Base.relax_heights(levels, size, flat)

static func composition_errors(metrics: Dictionary) -> Array[String]:
	var errors := Natural.composition_errors(metrics)
	if float(metrics["forest_fraction"]) < 0.10: errors.append("random_map_geography_forest_coverage")
	if float(metrics["largest_grove_cells"]) < float(metrics["land_cells"]) * 0.015:
		errors.append("random_map_geography_regional_forest_missing")
	return errors
