class_name RoRSimulationSpatialSyncSystem
extends RefCounted

const COMPATIBILITY_REFRESH_INTERVAL_TICKS := 200

var roster_dirty: bool = false
var compatibility_ticks: int = 0


func reset() -> void:
	roster_dirty = false
	compatibility_ticks = 0


func mark_roster_dirty() -> void:
	roster_dirty = true


func advance(spatial_index, active_units: Array, all_units: Array, buildings: Array) -> bool:
	compatibility_ticks += 1
	if roster_dirty or compatibility_ticks >= COMPATIBILITY_REFRESH_INTERVAL_TICKS:
		if not spatial_index.synchronize_dynamic_entities(all_units, buildings):
			return false
		reset()
		return true
	return spatial_index.synchronize_active_units(active_units)


func note_rebuilt() -> void:
	reset()
