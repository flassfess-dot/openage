class_name RoRNavigationKnowledge
extends RefCounted

const KnowledgeGrid := preload("res://scripts/navigation_knowledge_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Fog := preload("res://scripts/fog_of_war.gd")
var entries: Dictionary = {}


func clear() -> void:
	entries.clear()


func planner(world, team: int):
	if team <= 0:
		return world.pathfinder
	var fog = world.fog_of_war
	fog.ensure_player(team)
	var entry: Dictionary = entries.get(team, {})
	if entry.is_empty() or entry.get("source") != world.navigation_grid or not fog.path_dirty_by_player.has(team):
		var grid = KnowledgeGrid.new(world.map_size)
		grid.terrain_restrictions = world.navigation_grid.terrain_restrictions
		entry = {"source": world.navigation_grid, "grid": grid, "planner": Pathfinder.new(grid), "source_revision": -1}
		entry["planner"].set_native_enabled(world.pathfinder.native_enabled)
		fog.track_path_knowledge(team)
		var states: PackedByteArray = fog.states_by_player[team]
		var initial: Array = []
		for index in range(states.size()):
			if states[index] != Fog.UNKNOWN:
				initial.append(index)
		_refresh(world, entry, initial, true, team)
		entry["source_revision"] = world.navigation_grid.revision
		entries[team] = entry
	entry["planner"].performance_probe = world.pathfinder.performance_probe
	if int(entry.get("fog_revision", -1)) == fog.revision and int(entry["source_revision"]) == world.navigation_grid.revision:
		return entry["planner"]
	var dirty: Array = fog.consume_path_knowledge(team)
	if int(entry["source_revision"]) != world.navigation_grid.revision:
		var changes: Variant = world.navigation_grid.changed_cells_since(int(entry["source_revision"]))
		if changes == null:
			# Expired bulk journal: visit only the presently visible cells once.
			var states: PackedByteArray = fog.states_by_player[team]
			for index in range(states.size()):
				if states[index] == Fog.VISIBLE:
					dirty.append(index)
		else:
			for cell in changes:
				if fog.state_at_cell(team, cell) == Fog.VISIBLE:
					dirty.append(cell.y * world.map_size.x + cell.x)
	if not dirty.is_empty():
		_refresh(world, entry, dirty, false, team)
	entry["source_revision"] = world.navigation_grid.revision
	entry["fog_revision"] = fog.revision
	entry["planner"].performance_probe = world.pathfinder.performance_probe
	return entry["planner"]


func _refresh(world, entry: Dictionary, indices: Array, initial: bool, team: int) -> void:
	var source = world.navigation_grid
	var grid = entry["grid"]
	var changed := false
	var patch_needed: bool = not entry["planner"].native_kernels.is_empty()
	var changed_cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for index_value in indices:
		var index := int(index_value)
		if seen.has(index):
			continue
		seen[index] = true
		var cell := Vector2i(index % source.size.x, index / source.size.x)
		# Exploration may be shared without current sight; retain old knowledge.
		if not initial and grid.learned[index] != 0 and world.fog_of_war.state_at_cell(team, cell) != Fog.VISIBLE:
			continue
		var occupants: Array = source.occupied_cells.get(cell, [])
		var terrain_id: int = source.terrain_id(cell)
		var terrain: String = source.terrain(cell)
		if grid.learned[index] == 0 or grid.occupied_cells.get(cell, []) != occupants or grid.terrain_id(cell) != terrain_id:
			grid.learned[index] = 1
			grid.terrain_ids[cell] = terrain_id
			grid.terrain_cells[cell] = terrain
			grid.elevation_cells[cell] = source.elevation(cell)
			if occupants.is_empty():
				grid.occupied_cells.erase(cell)
			else:
				grid.occupied_cells[cell] = occupants.duplicate(true)
			grid._record_change(cell)
			if patch_needed:
				changed_cells.append(cell)
			changed = true
	if changed:
		grid.revision += 1
		grid.surface_revision += 1
		grid.surface_component_cache.clear()
		entry["planner"].patch_native_masks(changed_cells)
