class_name RoRRandomMapWorldShapes
extends RefCounted

const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Water := preload("res://scripts/random_map_water.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Rules := preload("res://scripts/terrain_rules.gd")

# The profile selects geographic structure. Player count and settlements never
# enter silhouette generation; shared ecology and hydrology follow this stage.
static func build(size: Vector2i, profile: String, seed: int) -> Dictionary:
	var span := float(mini(size.x, size.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x51A9E
	var angle := floorf(rng.randf() * 4.0) * PI * 0.5 + rng.randf_range(-0.16, 0.16)
	var coast := Natural.noise_field(size, maxf(8.0, span * 0.13), seed ^ 0xC0A57)
	var detail := Natural.noise_field(size, 5.5, seed ^ 0xB4A5)
	var forms: Array = []
	var insular := profile in ["islands", "small_islands"]
	if insular: forms = _islands(size, profile == "small_islands", rng)
	if profile == "coastal":
		for i in range(maxi(3, roundi(span / 45.0))):
			var radius := maxf(2.5, span * rng.randf_range(0.012, 0.033))
			var local := Vector2(span * rng.randf_range(-0.40, -0.24), span * rng.randf_range(-0.43, 0.43))
			forms.append({"center": Vector2(size) * 0.5 + local.rotated(angle), "radii": Vector2(radius * 1.3, radius), "angle": rng.randf() * TAU, "group": i})
	if profile == "mediterranean":
		for i in range(maxi(2, roundi(span / 90.0))):
			var radius := maxf(2.0, span * rng.randf_range(0.014, 0.035))
			var local := Vector2(span * rng.randf_range(-0.20, 0.20), span * rng.randf_range(-0.12, 0.12))
			forms.append({"center": Vector2(size) * 0.5 + local.rotated(angle), "radii": Vector2(radius * 1.4, radius), "angle": rng.randf() * TAU, "group": i})
	var slots: Array = []
	if profile == "narrows":
		for i in range(rng.randi_range(1, 2)):
			slots.append({"offset": (float(i) - 0.5) * span * 0.31, "phase": rng.randf() * TAU, "width": maxf(1.7, span * rng.randf_range(0.014, 0.022))})
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			var point := Vector2(x + 0.5, y + 0.5)
			var local := (point - Vector2(size) * 0.5).rotated(-angle)
			var perturbation := (coast[i] - 0.5) * 0.43 + (detail[i] - 0.5) * 0.11
			var land := true
			if insular:
				var first := -2.0
				var second := -2.0
				var owner := -1
				for form in forms:
					var value := _silhouette(point, form)
					if int(form["group"]) == owner:
						first = maxf(first, value)
					elif value > first:
						second = first
						first = value
						owner = int(form["group"])
					else: second = maxf(second, value)
				land = first + perturbation > 0.0
				if second > -0.12 and first - second < 0.16: land = false
			elif profile == "coastal":
				land = local.x > -span * 0.16 + perturbation * span * 0.30
			elif profile == "mediterranean":
				var bend := sin(local.x / span * PI * 2.0) * span * 0.025
				land = Vector2(local.x / (span * 0.34), (local.y - bend) / (span * 0.235)).length() > 1.0 + perturbation * 0.55
			elif profile == "narrows":
				land = Vector2(local.x / (span * 0.48), local.y / (span * 0.49)).length() < 1.0 + perturbation * 0.35
				for slot in slots:
					var axis := float(slot["offset"]) + sin(local.y / span * 7.0 + float(slot["phase"])) * span * 0.045
					var width := float(slot["width"]) * (1.0 + sin(local.y / span * 11.0 + float(slot["phase"])) * 0.22)
					if absf(local.x - axis) < width: land = false
			if profile in ["coastal", "mediterranean"]:
				for form in forms:
					if _silhouette(point, form) + perturbation > 0.0: land = true
			if insular and (x < 2 or y < 2 or x >= size.x - 2 or y >= size.y - 2): land = false
			terrain[i] = 0 if land else 1
	Water.smooth_coast(terrain, size)
	var inland := profile in ["grasslands", "highlands", "hill_country"]
	var hydrology := {"edge_outlets": inland}
	if insular: hydrology.merge({"minimum_runoff": 24.0, "runoff_scale": 0.24, "basin_scale": 4.5, "width_scale": 0.72,"width_reference_runoff":maxf(24.0,span*0.24)})
	return {"terrain": terrain, "forms": forms, "hydrology": hydrology, "angle": angle, "slots": slots,
		"shape_kind": "archipelago" if insular else "interior" if inland else "inland_sea" if profile == "mediterranean" else "straits" if profile == "narrows" else "coastal",
		"ridge_count": 5 if profile == "highlands" else 1 if profile in ["hill_country", "grasslands", "small_islands"] else 2}

static func _silhouette(point: Vector2, form: Dictionary) -> float:
	return 1.0 - ((point - Vector2(form["center"])).rotated(-float(form["angle"])) / Vector2(form["radii"])).length()

static func _islands(size: Vector2i, small: bool, rng: RandomNumberGenerator) -> Array:
	var span := float(mini(size.x, size.y))
	var count := (4 if span <= 48 else rng.randi_range(5, 6) if span <= 96 else rng.randi_range(8, 12)) if small else (4 if span <= 48 else rng.randi_range(4, 6) if span <= 96 else rng.randi_range(4, 7))
	if span > 72 and span <= 96: count = 8 if small else 6
	var forms: Array = []
	var centers: Array[Vector2] = []
	for group in range(count):
		var chosen := Vector2.ZERO
		var best := -1.0
		for attempt in range(120):
			var at := Vector2(rng.randf_range(0.16, 0.84) * size.x, rng.randf_range(0.16, 0.84) * size.y)
			var separation := span
			for center in centers: separation = minf(separation, at.distance_to(center))
			if separation > best: best = separation; chosen = at
			if separation > maxf(14.0, span * (0.18 if small else 0.23)): break
		centers.append(chosen)
		var radius := maxf(8.5 if small else 11.0, span * rng.randf_range(0.055 if small else 0.075, 0.085 if small else 0.125))
		var angle := rng.randf() * TAU
		forms.append({"center": chosen, "radii": Vector2(radius * rng.randf_range(1.05, 1.35), radius * rng.randf_range(0.85, 1.02)), "angle": angle, "group": group})
		for lobe in range(rng.randi_range(2, 3) if small else rng.randi_range(2, 5)):
			var direction := angle + rng.randf_range(-2.4, 2.4)
			forms.append({"center": chosen + Vector2.from_angle(direction) * radius * rng.randf_range(0.6, 1.0),
				"radii": Vector2(radius * rng.randf_range(0.40, 0.70), radius * rng.randf_range(0.30, 0.60)), "angle": direction, "group": group})
	for group in range(maxi(3, roundi(span / (22.0 if small else 35.0)))):
		var radius := maxf(2.0, span * rng.randf_range(0.008, 0.025))
		forms.append({"center": Vector2(rng.randf_range(0.07, 0.93) * size.x, rng.randf_range(0.07, 0.93) * size.y),
			"radii": Vector2(radius * 1.5, radius), "angle": rng.randf() * TAU, "group": 100 + group})
	return forms

static func add_strait_shallows(size: Vector2i, terrain: Array[int], hydro: Dictionary, shape: Dictionary) -> void:
	var span := float(mini(size.x, size.y))
	var angle := float(shape["angle"])
	for slot in shape["slots"]:
		var y := sin(float(slot["phase"]) * 2.0) * span * 0.23
		var x := float(slot["offset"]) + sin(y / span * 7.0 + float(slot["phase"])) * span * 0.045
		var center := Vector2i(Vector2(size) * 0.5 + Vector2(x, y).rotated(angle))
		var direction := Vector2.RIGHT.rotated(angle)
		var normal := Vector2i.RIGHT if absf(direction.x) > absf(direction.y) else Vector2i.DOWN
		var banks: Array[Vector2i] = []
		for sign_axis in [-1, 1]:
			for step in range(1, maxi(7, ceili(span * 0.07))):
				var at: Vector2i = center + normal * sign_axis * step
				if not Navigation.inside(at, size): break
				if terrain[at.y * size.x + at.x] not in Rules.WATER_TERRAIN_IDS:
					banks.append(at)
					break
		if banks.size() != 2: continue
		var tangent := Vector2i(-normal.y, normal.x)
		var cells: Array[Vector2i] = []
		var approaches: Array[Vector2i] = []
		var near_mouth := false
		var mouth_mask: PackedByteArray = hydro["rivers"]["mouth_mask"]
		var length := roundi(Vector2(banks[0]).distance_to(banks[1]))
		for step in range(-2, length + 3):
			for side in range(-1, 2):
				var at := banks[0] + normal * step + tangent * side
				if not Navigation.inside(at, size): continue
				var i := at.y * size.x + at.x
				approaches.append(at)
				if mouth_mask[i] != 0: near_mouth = true
				if terrain[i] in Rules.WATER_TERRAIN_IDS:
					cells.append(at)
		if near_mouth: continue
		for at in approaches: hydro["rivers"]["mask"][at.y * size.x + at.x] = 1
		for at in cells:
			terrain[at.y * size.x + at.x] = 4
			hydro["rivers"]["terrain_types"][at.y * size.x + at.x] = 4
		if not cells.is_empty(): hydro["fords"].append({"center": center, "bank_a": Vector2(banks[0]) + Vector2.ONE * 0.5,
			"bank_b": Vector2(banks[1]) + Vector2.ONE * 0.5, "cells": cells, "discharge": 0.0, "origin": "strait_shoal"})
	hydro["rivers"]["ford_count"] = hydro["fords"].size()
