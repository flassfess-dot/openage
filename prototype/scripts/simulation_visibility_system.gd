class_name RoRSimulationVisibilitySystem
extends RefCounted

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MOVEMENT_REFRESH_BUCKETS := 4

var fog: FogOfWar
var units_provider: Callable
var buildings_provider: Callable
var movement_refresh_bucket := 0


func _init(world_size: Vector2i, source_units: Callable = Callable(), source_buildings: Callable = Callable()) -> void:
	fog = FogOfWar.new(world_size)
	units_provider = source_units
	buildings_provider = source_buildings


func advance(context: Dictionary = {}) -> void:
	var units: Array = units_provider.call() if units_provider.is_valid() else []
	var buildings: Array = buildings_provider.call() if buildings_provider.is_valid() else []
	if bool(context.get("force", false)):
		fog.update(units, buildings)
		return
	fog.update(units, buildings, MOVEMENT_REFRESH_BUCKETS, movement_refresh_bucket)
	movement_refresh_bucket = posmod(movement_refresh_bucket + 1, MOVEMENT_REFRESH_BUCKETS)


func set_performance_probe(probe: Variant) -> void:
	fog.set_performance_probe(probe)


func set_native_enabled(enabled: bool) -> void:
	fog.set_native_enabled(enabled)


func uses_native_kernel() -> bool:
	return fog.uses_native_kernel()


func reset() -> void:
	fog.reset()
	movement_refresh_bucket = 0


func set_alliance(first_team: int, second_team: int, allied: bool = true) -> void:
	fog.set_alliance(first_team, second_team, allied)


func set_relation(observer_team: int, source_team: int, allied: bool = true) -> void:
	fog.set_relation(observer_team, source_team, allied)


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
