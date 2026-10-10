class_name RoRSimulationVisibilitySystem
extends RefCounted

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MOVEMENT_REFRESH_BUCKETS := 4

var fog: FogOfWar
var units_provider: Callable
var buildings_provider: Callable
var movement_refresh_bucket := 0
var world_ref: WeakRef
var source_cursor := -1
var source_epoch := -1
var pending_motion: Dictionary = {}


func _init(world_size: Vector2i, source_units: Callable = Callable(), source_buildings: Callable = Callable()) -> void:
	fog = FogOfWar.new(world_size)
	units_provider = source_units
	buildings_provider = source_buildings


func configure_source(world) -> void:
	if world_ref == null or world_ref.get_ref() != world:
		world_ref = weakref(world)
		source_cursor = -1
		source_epoch = -1
		pending_motion.clear()

func advance(context: Dictionary = {}) -> void:
	var world: Variant = world_ref.get_ref() if world_ref != null else null
	if world == null:
		fog.update(units_provider.call() if units_provider.is_valid() else [], buildings_provider.call() if buildings_provider.is_valid() else [])
		return
	var journal = world.entity_changes
	var delta: Dictionary = journal.changes_since(source_cursor if source_epoch == journal.epoch else -1)
	if bool(context.get("force", false)) or bool(delta["full"]) or fog.visibility_topology_dirty:
		pending_motion.clear()
		fog.update(world.get_units(), world.get_buildings(), 1, 0)
	else:
		var changed: Dictionary = {}
		for id in delta["ids"]:
			var mask := int(delta["masks"][id])
			if mask & (1 | 8 | 32 | 128): changed[id] = true
			elif mask & 2: pending_motion[id] = true
		for id in pending_motion.keys():
			if posmod(int(id), MOVEMENT_REFRESH_BUCKETS) == movement_refresh_bucket:
				changed[id] = true
				pending_motion.erase(id)
		var units: Array = []
		var buildings: Array = []
		var removed: Array = []
		var ids: Array = changed.keys()
		ids.sort()
		for id in ids:
			var row: Variant = world.find_unit(int(id))
			var category := 0
			if row == null:
				row = world.find_building(int(id))
				category = 1
			if row == null:
				removed.append(int(id) << 1)
				removed.append((int(id) << 1) | 1)
				continue
			var vision: Dictionary = row.get("components", {}).get("vision", {})
			if float(row.get("hp", 0.0)) <= 0.0 or not bool(vision.get("enabled", false)) or float(vision.get("range", 0.0)) <= 0.0 or int(row.get("team", 0)) <= 0:
				removed.append((int(id) << 1) | category)
			elif category == 0: units.append(row)
			else: buildings.append(row)
		fog.apply_entity_changes(units, buildings, removed)
	source_cursor = int(delta["revision"])
	source_epoch = int(journal.epoch)
	movement_refresh_bucket = posmod(movement_refresh_bucket + 1, MOVEMENT_REFRESH_BUCKETS)


func set_performance_probe(probe: Variant) -> void:
	fog.set_performance_probe(probe)


func set_native_enabled(enabled: bool) -> void:
	fog.set_native_enabled(enabled)


func uses_native_kernel() -> bool:
	return fog.uses_native_kernel()


func reset() -> void:
	fog.reset()
	source_cursor = -1
	source_epoch = -1
	pending_motion.clear()
	movement_refresh_bucket = 0


func set_alliance(first_team: int, second_team: int, allied: bool = true) -> void:
	fog.set_alliance(first_team, second_team, allied)


func set_relation(observer_team: int, source_team: int, allied: bool = true) -> void:
	fog.set_relation(observer_team, source_team, allied)


func set_shared_vision(observer_team: int, source_team: int, enabled: bool) -> void:
	fog.set_shared_vision(observer_team, source_team, enabled)


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
	if owner == team:
		return true
	var state := state_at_world(team, Vector2(entity.get("pos", Vector2.ZERO)))
	return state == FogOfWar.VISIBLE or (allow_explored_static and state == FogOfWar.EXPLORED)


func get_fog() -> FogOfWar:
	return fog
