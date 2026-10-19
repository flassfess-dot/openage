extends RefCounted

const Landscape := preload("res://scripts/random_map_landscape.gd")
const Natural := preload("res://scripts/random_map_natural_landscape.gd")
const Geography := preload("res://scripts/random_map_geography.gd")
const WildIslands := preload("res://scripts/random_map_wild_islands.gd")
const Watershed := preload("res://scripts/random_map_watershed_world.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const NaturalTopology := preload("res://scripts/random_map_natural_topology.gd")


static func geography(version: int, size: Vector2i, generator: Dictionary, seed: int, player_count: int) -> Dictionary:
	match version:
		Watershed.VERSION:
			return Watershed.geography(size, String(generator.get("map_type_id", "continental")), seed)
		WildIslands.VERSION:
			return WildIslands.geography(size, seed, bool(generator.get("river_network", false)))
		Geography.VERSION:
			return Geography.geography(size, String(generator.get("map_type_id", "grasslands")), seed, player_count)
	return {}


static func topology(version: int, size: Vector2i, starts: Array[Vector2], generator: Dictionary, seed: int) -> Dictionary:
	match version:
		Watershed.VERSION, WildIslands.VERSION, Geography.VERSION:
			return {}
		Natural.VERSION:
			return NaturalTopology.prepare(size, starts, String(generator.get("topology", "inland")), generator, seed)
	return Topology.prepare(size, starts, String(generator.get("topology", "inland")), generator, seed)


static func fields(version: int, geography_data: Dictionary, size: Vector2i, terrain: Array[int], starts: Array[Vector2], profile: String, seed: int, candidate: int) -> Dictionary:
	match version:
		Watershed.VERSION, WildIslands.VERSION, Geography.VERSION:
			return geography_data["fields"]
		Natural.VERSION:
			return Natural.fields(size, terrain, starts, profile, seed ^ (0x2A63B91 + candidate * 104729))
	return Landscape.select_fields(size, terrain, starts, profile, seed)
