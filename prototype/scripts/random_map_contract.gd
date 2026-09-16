class_name RoRRandomMapContract
extends RefCounted


static func build(map_type: Dictionary, size: Vector2i, starts: Array[Vector2]) -> Dictionary:
	var profile := String(map_type.get("generator_profile", "inland_v1"))
	var topology := String(map_type.get("topology", "inland"))
	var clusters: Array = []
	for start in starts:
		clusters.append({"kind": "berries", "center": [start.x + 4.0, start.y], "count": 5, "radius": 1.2, "amount": 150, "guarantee": "player_food"})
		clusters.append({"kind": "tree", "center": [start.x - 4.0, start.y + 1.0], "count": 10, "radius": 2.2, "amount": 75, "guarantee": "player_wood"})
		clusters.append({"kind": "stone_mine", "center": [start.x, start.y - 5.0], "count": 4, "radius": 1.0, "amount": 250, "guarantee": "player_stone"})
		clusters.append({"kind": "gold_mine", "center": [start.x + 2.0, start.y + 5.0], "count": 4, "radius": 1.0, "amount": 400, "guarantee": "player_gold"})
	var hills: Array = []
	if topology in ["inland", "highlands", "coastal"]:
		hills.append({"center": [size.x * 0.5, size.y * 0.5], "radius": maxi(3, mini(size.x, size.y) / (7 if topology == "highlands" else 12)), "maximum_elevation": 3 if topology == "highlands" else 2})
	if topology == "highlands":
		for start in starts:
			hills.append({"center": [start.x, start.y], "radius": 4, "maximum_elevation": 1})
	return {
		"type": "seeded_skirmish_v1",
		"profile": profile,
		"topology": topology,
		"requires_shared_land": bool(map_type.get("requires_shared_land", false)),
		"requires_naval_starts": bool(map_type.get("requires_naval_starts", false)),
		"water_ratio": map_type.get("water_ratio", [0.0, 1.0]).duplicate(true),
		"coast_fraction": float(map_type.get("coast_fraction", 0.12)),
		"island_radius_fraction": float(map_type.get("island_radius_fraction", 0.12)),
		"naval_start": {
			"dock_footprint_radius_cells": 1,
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
			"resource_radius": 8.0,
			"resource_counts": {"berries": 5, "tree": 10, "stone_mine": 4, "gold_mine": 4},
			"naval_resource_radius": 12.0,
			"naval_resource_counts": {"deep_fish": 2} if bool(map_type.get("requires_naval_starts", false)) else {},
			"naval_resource_minimum_water_clearance_cells": 2,
			"minimum_land_component_cells": 64,
		},
	}
