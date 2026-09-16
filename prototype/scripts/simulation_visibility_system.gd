class_name RoRSimulationVisibilitySystem
extends RefCounted

const FogOfWar := preload("res://scripts/fog_of_war.gd")

var fog: FogOfWar
var units_provider: Callable
var buildings_provider: Callable
var last_source_signature: Array = []
var visibility_dirty := true


func _init(world_size: Vector2i, source_units: Callable = Callable(), source_buildings: Callable = Callable()) -> void:
	fog = FogOfWar.new(world_size)
	units_provider = source_units
	buildings_provider = source_buildings


func advance(_context: Dictionary = {}) -> void:
	var units: Array = units_provider.call() if units_provider.is_valid() else []
	var buildings: Array = buildings_provider.call() if buildings_provider.is_valid() else []
	var signature := _source_signature(units, buildings)
	if not visibility_dirty and signature == last_source_signature:
		return
	fog.update(units, buildings)
	last_source_signature = signature
	visibility_dirty = false


func reset() -> void:
	fog.reset()
	last_source_signature.clear()
	visibility_dirty = true


func set_alliance(first_team: int, second_team: int, allied: bool = true) -> void:
	fog.set_alliance(first_team, second_team, allied)
	visibility_dirty = true


func set_relation(observer_team: int, source_team: int, allied: bool = true) -> void:
	fog.set_relation(observer_team, source_team, allied)
	visibility_dirty = true


func _source_signature(units: Array, buildings: Array) -> Array:
	var result: Array = []
	for entity_value in units + buildings:
		var entity: Dictionary = entity_value
		var vision: Dictionary = entity.get("components", {}).get("vision", {})
		if int(entity.get("team", 0)) <= 0 or float(entity.get("hp", 0.0)) <= 0.0 or not bool(vision.get("enabled", true)) or float(vision.get("range", 0.0)) <= 0.0:
			continue
		result.append([
			int(entity.get("id", -1)),
			int(entity.get("team", 0)),
			Vector2(entity.get("pos", Vector2.ZERO)),
			float(vision.get("range", 0.0)),
		])
	return result


func state_at_world(team: int, position: Vector2) -> int:
	return fog.state_at_world(team, position)


func state_name(state: int) -> String:
	return fog.state_name(state)


func is_entity_visible(team: int, entity: Dictionary, allow_explored_static: bool = false) -> bool:
	# Gaia has no player-owned fog buffer. Its autonomous actors acquire targets
	# through their own perception systems, so a target already admitted by that
	# system must not be cancelled by a nonexistent team-0 visibility map.
	if team <= 0:
		return true
	var owner := int(entity.get("team", 0))
	if owner > 0 and fog.are_allied(team, owner):
		return true
	var state := state_at_world(team, Vector2(entity.get("pos", Vector2.ZERO)))
	return state == FogOfWar.VISIBLE or (allow_explored_static and state == FogOfWar.EXPLORED)


func get_fog() -> FogOfWar:
	return fog
