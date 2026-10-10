class_name RoRSimulationSpatialSyncSystem
extends RefCounted


var roster_dirty: bool = false


func reset() -> void:
	roster_dirty = false


func mark_roster_dirty() -> void:
	roster_dirty = true


func advance(spatial_index, active_units: Array, all_units: Array, buildings: Array) -> bool:
	if roster_dirty:
		if not spatial_index.synchronize_dynamic_entities(all_units, buildings):
			return false
		reset()
		return true
	return spatial_index.synchronize_active_units(active_units)


func note_rebuilt() -> void:
	reset()
