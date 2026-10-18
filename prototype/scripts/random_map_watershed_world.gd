class_name RoRRandomMapWatershedWorld
extends RefCounted

const VERSION := 6
const PROFILES := ["small_islands", "islands", "coastal", "grasslands", "highlands", "continental", "mediterranean", "hill_country", "narrows"]
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Base := preload("res://scripts/random_map_landscape.gd")
const Wild := preload("res://scripts/random_map_wild_islands.gd")
const Water := preload("res://scripts/random_map_water.gd")
const Hydrology := preload("res://scripts/random_map_hydrology.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const CliffChain := preload("res://scripts/cliff_chain.gd")
const Shapes := preload("res://scripts/random_map_world_shapes.gd")

static func geography(size: Vector2i, profile: String, seed: int) -> Dictionary:
	if profile != "continental":
		var shape := Shapes.build(size, profile, seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed ^ 0xC0171
		return finish(size, shape["terrain"], shape["forms"], profile, seed, rng, shape)
	var span := float(mini(size.x, size.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0xC0171
	var forms: Array = []
	var angle := rng.randf() * TAU
	var center := Vector2(size) * Vector2(rng.randf_range(0.46, 0.54), rng.randf_range(0.46, 0.54))
	forms.append({"center": center, "radii": Vector2(span * 0.37, span * 0.31), "angle": angle})
	for lobe in range(rng.randi_range(5, 8)):
		var direction := angle + rng.randf() * TAU
		var radius := span * rng.randf_range(0.10, 0.17)
		forms.append({"center": center + Vector2.from_angle(direction) * span * rng.randf_range(0.21, 0.32),
			"radii": Vector2(radius * rng.randf_range(0.9, 1.4), radius * rng.randf_range(0.65, 1.0)), "angle": direction})
	for island in range(maxi(5, roundi(span / 26.0))):
		var direction := rng.randf() * TAU
		var radius := span * rng.randf_range(0.012, 0.042)
		forms.append({"center": center + Vector2.from_angle(direction) * span * rng.randf_range(0.37, 0.49),
			"radii": Vector2(radius * 1.4, radius), "angle": direction})
	var coast := Natural.noise_field(size, span * 0.13, seed ^ 0xC0A57)
	var detail := Natural.noise_field(size, 7.5, seed ^ 0xB4A5)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			var point := Vector2(x + 0.5, y + 0.5)
			var silhouette := -2.0
			for form in forms:
				var local := (point - Vector2(form["center"])).rotated(-float(form["angle"])) / Vector2(form["radii"])
				silhouette = maxf(silhouette, 1.0 - local.length())
			terrain[i] = 0 if silhouette + (coast[i] - 0.5) * 0.43 + (detail[i] - 0.5) * 0.11 > 0.0 else 1
			if x < 3 or y < 3 or x >= size.x - 3 or y >= size.y - 3: terrain[i] = 1
	Water.smooth_coast(terrain, size)
	return finish(size, terrain, forms, profile, seed, rng)

static func finish(size: Vector2i, terrain: Array[int], forms: Array, profile: String, seed: int, rng: RandomNumberGenerator, options: Dictionary = {}) -> Dictionary:
	var span := float(mini(size.x, size.y))
	var no_starts: Array[Vector2] = []
	var fields := Natural.fields(size, terrain, no_starts, profile, seed ^ 0x8194)
	var original_levels: Array[int] = fields["vertex_levels"].duplicate()
	var hydro := Hydrology.build(size, terrain, fields, seed, options.get("hydrology", {}))
	if profile == "narrows": Shapes.add_strait_shallows(size, terrain, hydro, options)
	fields = Natural.fields(size, terrain, no_starts, profile, seed ^ 0x8194)
	fields["vertex_levels"] = original_levels
	Hydrology.apply_surface_relief(size, terrain, original_levels, hydro["rivers"], hydro["lakes"])
	fields["recipe"] = fields["recipe"].duplicate(true)
	fields["recipe"]["forest_threshold"] = 0.53
	var climate := Natural.noise_field(size, span * 0.34, seed ^ 0x6819)
	var woodland := Natural.noise_field(size, maxf(10.0, span * 0.10), seed ^ 0x8351)
	var local_wood := Natural.noise_field(size, 11.0, seed ^ 0x6512)
	for i in range(terrain.size()):
		var strength := climate[i] * 0.52 + woodland[i] * 0.36 + local_wood[i] * 0.12
		fields["moisture"][i] = clampf(climate[i] * 0.85 + woodland[i] * 0.15 + 0.08, 0.0, 1.0)
		fields["forest_strength"][i] = strength
		fields["forest_potential"][i] = int(terrain[i] == 0 and fields["coast_distance"][i] > 1 and strength > 0.53 and hydro["rivers"]["mask"][i] == 0)
	var scenery: Array = []
	var cells: Dictionary = {}
	var used: Dictionary = {}
	var ridge_count := int(options.get("ridge_count", 5 if profile == "highlands" else 3))
	for ridge in range(ridge_count):
		var at := Vector2i(Vector2(size) * Vector2(rng.randf_range(0.23, 0.75), rng.randf_range(0.25, 0.76)))
		var sign_axis := 1 if rng.randf() < 0.5 else -1
		for step in range(roundi(span * rng.randf_range(0.18, 0.33) / CliffChain.STRIDE)):
			var valid := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var p := at + Vector2i(dx, dy)
					if not Navigation.inside(p, size) or terrain[p.y * size.x + p.x] != 0 or hydro["rivers"]["mask"][p.y * size.x + p.x] != 0: valid = false
			if valid and not used.has(at) and step % 17 not in [10, 11]:
				Base._append_cliff_strip(scenery, cells, used, at, Vector2i.RIGHT, size, terrain, fields["vertex_levels"], seed)
			at += (Vector2i.RIGHT if rng.randf() > 0.28 else Vector2i.UP) * CliffChain.STRIDE * sign_axis
	CliffChain.apply(scenery)
	var walkable := PackedByteArray()
	walkable.resize(terrain.size())
	for i in range(terrain.size()): walkable[i] = int(terrain[i] in [0, 4])
	for cell in cells: walkable[cell.y * size.x + cell.x] = 0
	return {"size": size, "seed": seed, "terrain": terrain, "fields": fields, "ridge_cells": cells.keys(), "ridge_scenery": scenery,
		"rivers": hydro["rivers"], "lakes": hydro["lakes"], "fords": hydro["fords"], "landforms": forms,
		"walkable": walkable, "woodland_regions": maxi(4, roundi(span / 43.0)), "landmass_seeds": forms.size(), "profile": profile, "wild": true, "shape_kind": options.get("shape_kind", "outer_ocean" if profile == "continental" else "interior")}

static func contract(generator: Dictionary, geography_data: Dictionary, starts: Array[Vector2], seed: int) -> Dictionary:
	var result := Wild.contract(generator, geography_data, starts, seed)
	result["version"] = VERSION
	result["theme"] = "watershed_world_v6"
	result["requires_shared_land"] = false
	result["river_network"] = true
	result["water_ratio"] = [0.0, 0.95]
	result["cliff_profile"] = ""
	result["quality_contract"]["minimum_gate_width_cells"] = 0
	return result
