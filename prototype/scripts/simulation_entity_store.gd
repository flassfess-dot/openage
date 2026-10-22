extends RefCounted

# Owns this state; the world is passed per operation to avoid a reference cycle.
const EntityIds := preload("res://scripts/entity_id.gd")
const SimulationActivityRegistry := preload("res://scripts/simulation_activity_registry.gd")

var units: Array = []
var units_by_id: Dictionary = {}
var unit_activity_registry := SimulationActivityRegistry.new()
var capturable_units: Array[Dictionary] = []
var dying_units: Array[Dictionary] = []
var dying_buildings: Array[Dictionary] = []
var unit_removal_pending: bool = false
var building_removal_pending: bool = false
var resource_nodes: Array = []
var resource_nodes_by_id: Dictionary = {}
var resource_nodes_by_cell: Dictionary = {}
var decaying_resource_nodes: Array = []
# Only actively falling trees are visited by the fixed-tick lifecycle pass.
var falling_resource_nodes: Array = []
var static_obstructions: Array = []
var buildings: Array = []
var buildings_by_id: Dictionary = {}
var projectiles: Array = []
var resolved_projectiles: Array = []
var entity_id_sequence := EntityIds.new()
var resource_approach_slots: Dictionary = {}
var building_approach_slots: Dictionary = {}

func clear_units() -> void:
	units.clear()
	units_by_id.clear()
	unit_activity_registry.clear()
	capturable_units.clear()
	dying_units.clear()
	dying_buildings.clear()
	unit_removal_pending = false
	building_removal_pending = false


func clear_resources() -> void:
	resource_nodes.clear()
	resource_nodes_by_id.clear()
	resource_nodes_by_cell.clear()
	decaying_resource_nodes.clear()
	falling_resource_nodes.clear()


func clear_buildings() -> void:
	buildings.clear()
	buildings_by_id.clear()


func clear_approaches() -> void:
	resource_approach_slots.clear()
	building_approach_slots.clear()


func find_unit(world, id: int) -> Variant:
	return units_by_id.get(id)


func find_resource(world, id: int) -> Variant:
	if resource_nodes_by_id.has(id):
		return resource_nodes_by_id[id]
	for building in buildings:
		if int(building.get("id", -1)) == id and bool(building.get("harvestable", false)) and String(building.get("state", "complete")) == "complete" and float(building.get("hp", 0.0)) > 0.0:
			return building
	return null


func find_building(world, id: int) -> Variant:
	return buildings_by_id.get(id)


func get_units(world) -> Array:
	return units


func get_units_in_bounds(world, bounds: Rect2) -> Array:
	var result: Array = world.spatial_index.query_aabb(bounds, "unit")
	# The movement index intentionally contains living mobile entities only;
	# presentation still needs short-lived dying/corpse records.
	for unit_value in dying_units:
		var unit: Dictionary = unit_value
		if bounds.has_point(Vector2(unit.get("pos", Vector2.ZERO))):
			result.append(unit)
	if not dying_units.is_empty():
		result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func get_resources(world) -> Array:
	return resource_nodes


func get_buildings(world) -> Array:
	return buildings


func get_static_obstructions(world) -> Array:
	return static_obstructions


func get_projectiles(world) -> Array:
	return projectiles


func get_resolved_projectiles(world) -> Array:
	return resolved_projectiles
