class_name RoRRandomMapContract
extends RefCounted

const SourceProfile := preload("res://scripts/random_map_source_profile.gd")

const SOURCE_RESOURCE_KINDS := {
	59: {"kind": "berries", "amount": 150},
	66: {"kind": "gold_mine", "amount": 400},
	102: {"kind": "stone_mine", "amount": 250},
	48: {"kind": "elephant", "category": "unit"},
	65: {"kind": "gazelle", "category": "unit"},
}


static func build(map_type: Dictionary, size: Vector2i, starts: Array[Vector2]) -> Dictionary:
	var profile := String(map_type.get("generator_profile", "inland_v1"))
	var topology := String(map_type.get("topology", "inland"))
	var source_profile := SourceProfile.get_profile(String(map_type.get("id", "")))
	var clusters: Array = []
	var source_start_radius := 12.0
	if not source_profile.is_empty():
		var zones: Array = source_profile.get("land_zones", [])
		if not zones.is_empty():
			source_start_radius = maxf(8.0, float(zones[0].get("start_area_radius", 12)))
	for index in range(starts.size()):
		var start: Vector2 = starts[index]
		# Native RoR forest patches are terrain groups. A nearby tree group keeps
		# the opening viable while larger forests are generated across the map.
		clusters.append({"kind": "tree", "count": 12, "radius": 2.8, "amount": 75, "tree_palette": [134, 140, 141, 142, 143, 144, 146, 147, 161, 194], "owner_start": [start.x, start.y], "minimum_distance": 7.0, "maximum_distance": minf(12.0, source_start_radius), "guarantee_radius": 20.0, "guarantee": "player_wood"})
		var first_kind: Dictionary = {}
		for group_value in source_profile.get("unit_groups", []):
			var group: Dictionary = group_value
			var source_id := int(group.get("unit_id", -1))
			if not SOURCE_RESOURCE_KINDS.has(source_id) or int(group.get("set_place_for_all_players", 0)) != 1:
				continue
			var resource_rule: Dictionary = SOURCE_RESOURCE_KINDS[source_id]
			var kind := String(resource_rule["kind"])
			var near_group := not first_kind.has(kind)
			first_kind[kind] = true
			var lower := maxf(5.0, float(group.get("min_distance_to_players", 7)))
			var upper := maxf(lower, float(group.get("max_distance_to_players", 18)))
			if near_group:
				upper = minf(upper, 16.0)
			if topology == "islands":
				upper = minf(upper, source_start_radius + 3.0)
				lower = minf(lower, upper)
			clusters.append({
				"category": String(resource_rule.get("category", "resource")),
				"kind": kind,
				"count": maxi(1, int(group.get("objects_per_group", 1))),
				"radius": maxf(1.0, float(group.get("group_radius", 2))),
				"amount": int(resource_rule.get("amount", 0)),
				"owner_start": [start.x, start.y],
				"minimum_distance": lower,
				"maximum_distance": upper,
				"guarantee_radius": 20.0 if near_group else 0.0,
				"placement_radius": maxf(20.0, upper + maxf(1.0, float(group.get("group_radius", 2))) + 1.0),
				"source_unit_id": source_id,
				"source_group": group.duplicate(true),
			})
	# Allocate each player's essential nearby food, wood and minerals before
	# placing distant groups. Otherwise early players' surplus groups can occupy
	# the last player's entire start region on crowded eight-player maps.
	var prioritized_clusters: Array = []
	var critical_kinds := ["tree", "berries", "stone_mine", "gold_mine", "gazelle", "elephant"]
	for critical_kind in critical_kinds:
		for cluster_value in clusters:
			var cluster: Dictionary = cluster_value
			if String(cluster.get("kind", "")) == critical_kind and float(cluster.get("guarantee_radius", 0.0)) > 0.0:
				prioritized_clusters.append(cluster)
	for cluster_value in clusters:
		var cluster: Dictionary = cluster_value
		if String(cluster.get("kind", "")) in critical_kinds and float(cluster.get("guarantee_radius", 0.0)) > 0.0:
			continue
		prioritized_clusters.append(cluster)
	clusters = prioritized_clusters
	var hills: Array = []
	if topology in ["inland", "highlands", "coastal", "continental", "hill_country"]:
		hills.append({"center": [size.x * 0.5, size.y * 0.5], "radius": maxi(3, mini(size.x, size.y) / (7 if topology in ["highlands", "hill_country"] else 12)), "maximum_elevation": 3 if topology in ["highlands", "hill_country"] else 2})
	if topology in ["highlands", "hill_country"]:
		for start in starts:
			hills.append({"center": [start.x, start.y], "radius": 4, "maximum_elevation": 1})
	return {
		"type": "seeded_skirmish_v1",
		"profile": profile,
		"source_profile": source_profile,
		"topology": topology,
		"requires_shared_land": bool(map_type.get("requires_shared_land", false)),
		"requires_naval_starts": bool(map_type.get("requires_naval_starts", false)),
		"water_ratio": map_type.get("water_ratio", [0.0, 1.0]).duplicate(true),
		"coast_fraction": float(map_type.get("coast_fraction", 0.12)),
		"island_radius_fraction": float(map_type.get("island_radius_fraction", 0.12)),
		"sea_fraction": float(map_type.get("sea_fraction", 0.23)),
		"cliff_profile": String(map_type.get("cliff_profile", "")),
		"naval_start": {
			"dock_footprint_radius_cells": 1,
			"water_staging_clearance_cells": 1,
			"dock_surface_terrain_ids": [1, 2, 4, 22],
			"resource_search_radius": 12.0,
			"resource_minimum_clearance_cells": 2,
			"resource_required_cells": 3,
		},
		"naval_resource_clusters": [
			{"kind": "deep_fish", "count": 3, "radius": 2.5, "amount": 250, "placement_domain": "water", "minimum_domain_clearance_cells": 2, "water_offset": 6.0, "guarantee_radius": 12.0},
		] if bool(map_type.get("requires_naval_starts", false)) else [],
		"hills": hills,
		"resource_clusters": clusters,
		"quality_contract": {
			"minimum_start_distance_fraction": 0.08,
			"resource_radius": 20.0,
			"resource_counts": {"berries": 5, "tree": 10, "stone_mine": 4, "gold_mine": 4},
			"naval_resource_radius": 12.0,
			"naval_resource_counts": {"deep_fish": 2} if bool(map_type.get("requires_naval_starts", false)) else {},
			"naval_resource_minimum_water_clearance_cells": 2,
			"minimum_land_component_cells": 64,
			"minimum_gate_width_cells": 5 if topology == "narrows" else 0,
		},
	}
