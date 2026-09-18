class_name RoRFogOfWar

const UNKNOWN := 0
const EXPLORED := 1
const VISIBLE := 2

var map_size: Vector2i
var states_by_player: Dictionary = {}
var visible_counts_by_player: Dictionary = {}
var allies_by_player: Dictionary = {}
var vision_sources: Dictionary = {}
var visibility_topology_dirty := true
var revision: int = 0
var performance_probe: Variant = null
var vision_cells_microseconds: int = 0
var regenerated_sources: int = 0
var native_enabled: bool = true
var native_available: bool = false
var native_kernel: Variant = null


func _init(world_size: Vector2i = Vector2i.ONE) -> void:
	map_size = Vector2i(maxi(1, world_size.x), maxi(1, world_size.y))
	native_available = ClassDB.class_exists("RoRVisibilityKernel")
	if native_available:
		native_kernel = ClassDB.instantiate("RoRVisibilityKernel")
		native_kernel.configure(map_size.x, map_size.y)


func reset() -> void:
	states_by_player.clear()
	visible_counts_by_player.clear()
	allies_by_player.clear()
	vision_sources.clear()
	visibility_topology_dirty = true
	revision += 1


func set_performance_probe(probe: Variant) -> void:
	performance_probe = probe


func set_native_enabled(enabled: bool) -> void:
	native_enabled = enabled


func uses_native_kernel() -> bool:
	return native_enabled and native_available and native_kernel != null


func ensure_player(player_id: int) -> void:
	if player_id <= 0:
		return
	if not states_by_player.has(player_id):
		var states := PackedByteArray()
		states.resize(map_size.x * map_size.y)
		states.fill(UNKNOWN)
		states_by_player[player_id] = states
		var visible_counts := PackedInt32Array()
		visible_counts.resize(map_size.x * map_size.y)
		visible_counts.fill(0)
		visible_counts_by_player[player_id] = visible_counts
		visibility_topology_dirty = true
	if not allies_by_player.has(player_id):
		allies_by_player[player_id] = {player_id: true}


func set_alliance(first_player: int, second_player: int, allied: bool = true) -> void:
	set_relation(first_player, second_player, allied)
	set_relation(second_player, first_player, allied)


func set_relation(observer_player: int, source_player: int, allied: bool = true) -> void:
	ensure_player(observer_player)
	ensure_player(source_player)
	if observer_player == source_player:
		allies_by_player[observer_player][source_player] = true
	elif allied:
		allies_by_player[observer_player][source_player] = true
	else:
		allies_by_player[observer_player].erase(source_player)
	visibility_topology_dirty = true
	revision += 1


func are_allied(observer_player: int, owner_player: int) -> bool:
	if observer_player <= 0 or owner_player <= 0:
		return false
	ensure_player(observer_player)
	ensure_player(owner_player)
	return bool(allies_by_player[observer_player].get(owner_player, false))


func update(units: Array, buildings: Array, movement_bucket_count: int = 1, movement_bucket_index: int = 0) -> void:
	var phase_started := Time.get_ticks_usec() if performance_probe != null else 0
	vision_cells_microseconds = 0
	regenerated_sources = 0
	for entity in units:
		var team := int(entity["team"])
		if team > 0 and not states_by_player.has(team):
			ensure_player(team)
	for entity in buildings:
		var team := int(entity["team"])
		if team > 0 and not states_by_player.has(team):
			ensure_player(team)
	if performance_probe != null:
		performance_probe.observe_microseconds("simulation.fog.ensure_players", Time.get_ticks_usec() - phase_started)
		phase_started = Time.get_ticks_usec()

	var current_sources: Dictionary = {}
	_collect_sources(units, 0, current_sources, movement_bucket_count, movement_bucket_index)
	_collect_sources(buildings, 1, current_sources, movement_bucket_count, movement_bucket_index)
	if performance_probe != null:
		performance_probe.observe_microseconds("simulation.fog.collect_sources", Time.get_ticks_usec() - phase_started)
		performance_probe.observe_microseconds("simulation.fog.vision_cells", vision_cells_microseconds)
		performance_probe.increment("fog.regenerated_sources", regenerated_sources)
		phase_started = Time.get_ticks_usec()
	var changed := false
	if visibility_topology_dirty:
		changed = _rebuild_visibility(current_sources)
	else:
		changed = _reconcile_visibility(current_sources)
	vision_sources = current_sources
	visibility_topology_dirty = false
	if changed:
		revision += 1
	if performance_probe != null:
		performance_probe.observe_microseconds("simulation.fog.reconcile", Time.get_ticks_usec() - phase_started)


func state_at_cell(player_id: int, cell: Vector2i) -> int:
	if player_id <= 0:
		return UNKNOWN
	ensure_player(player_id)
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return UNKNOWN
	var states: PackedByteArray = states_by_player[player_id]
	return int(states[_index(cell)])


func state_at_world(player_id: int, position: Vector2) -> int:
	return state_at_cell(player_id, Vector2i(floori(position.x), floori(position.y)))


func state_name(state: int) -> String:
	match state:
		EXPLORED: return "explored"
		VISIBLE: return "visible"
		_: return "unknown"


func snapshot(player_id: int) -> PackedByteArray:
	if player_id <= 0:
		return PackedByteArray()
	ensure_player(player_id)
	return PackedByteArray(states_by_player[player_id]).duplicate()


func _collect_sources(entities: Array, category_id: int, result: Dictionary, movement_bucket_count: int, movement_bucket_index: int) -> void:
	for index in range(entities.size()):
		var entity: Dictionary = entities[index]
		if float(entity["hp"]) <= 0.0:
			continue
		var vision: Dictionary = entity["components"]["vision"]
		var sight_radius := maxf(0.0, float(vision["range"]))
		if sight_radius <= 0.0 or not bool(vision["enabled"]):
			continue
		var source_player := int(entity["team"])
		if source_player <= 0:
			continue
		# Isolated compatibility fixtures may omit an ID; runtime entities always
		# provide one. Preserve the existing deterministic array-index fallback.
		var entity_id := int(entity.get("id", -1))
		# Runtime entity IDs are global across units and buildings, but retain one
		# category bit so isolated tests and compatibility fixtures may reuse IDs.
		# Integer keys avoid formatting and hashing thousands of short Strings on
		# every visibility tick without changing source identity or update order.
		var stable_id := entity_id if entity_id >= 0 else index
		var source_key := (stable_id << 1) | (category_id & 1)
		var center := Vector2(entity["pos"])
		var previous: Variant = vision_sources.get(source_key)
		if previous != null and int(previous["team"]) == source_player and Vector2(previous["center"]).is_equal_approx(center) and is_equal_approx(float(previous["radius"]), sight_radius):
			result[source_key] = previous
			continue
		var stable_bucket_value := entity_id if entity_id >= 0 else index
		var movement_refresh_deferred := (
			previous != null
			and int(previous["team"]) == source_player
			and is_equal_approx(float(previous["radius"]), sight_radius)
			and maxi(1, movement_bucket_count) > 1
			and posmod(stable_bucket_value, maxi(1, movement_bucket_count)) != posmod(movement_bucket_index, maxi(1, movement_bucket_count))
		)
		if movement_refresh_deferred:
			result[source_key] = previous
			continue
		var vision_started := Time.get_ticks_usec() if performance_probe != null else 0
		var cells := _vision_cells(center, sight_radius)
		if performance_probe != null:
			vision_cells_microseconds += Time.get_ticks_usec() - vision_started
			regenerated_sources += 1
		result[source_key] = {
			"team": source_player,
			"center": center,
			"radius": sight_radius,
			"cells": cells,
			"source_revision": int(previous.get("source_revision", 0)) + 1 if previous != null else 1,
		}


func _vision_cells(center: Vector2, radius: float) -> PackedInt32Array:
	if uses_native_kernel():
		return native_kernel.vision_cells(center, radius)
	var result := PackedInt32Array()
	var minimum := Vector2i(maxi(0, floori(center.x - radius)), maxi(0, floori(center.y - radius)))
	var maximum := Vector2i(mini(map_size.x - 1, floori(center.x + radius)), mini(map_size.y - 1, floori(center.y + radius)))
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var nearest := Vector2(clampf(center.x, float(x), float(x + 1)), clampf(center.y, float(y), float(y + 1)))
			if center.distance_squared_to(nearest) <= radius * radius + 0.000001:
				result.append(_index(Vector2i(x, y)))
	return result


func _rebuild_visibility(current_sources: Dictionary) -> bool:
	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		var states: PackedByteArray = states_by_player[observer]
		var counts := PackedInt32Array()
		counts.resize(states.size())
		counts.fill(0)
		for index in range(states.size()):
			if states[index] == VISIBLE:
				states[index] = EXPLORED
				changed = true
		states_by_player[observer] = states
		visible_counts_by_player[observer] = counts
	for source in current_sources.values():
		changed = _add_source(source) or changed
	return changed


func _reconcile_visibility(current_sources: Dictionary) -> bool:
	var removed_sources: Array[Dictionary] = []
	var added_sources: Array[Dictionary] = []
	var previous_replacements: Array[Dictionary] = []
	var current_replacements: Array[Dictionary] = []
	for source_key in vision_sources.keys():
		if not current_sources.has(source_key):
			removed_sources.append(vision_sources[source_key])
	for source_key in current_sources.keys():
		var current: Dictionary = current_sources[source_key]
		var previous: Variant = vision_sources.get(source_key)
		if previous == null:
			added_sources.append(current)
		elif int(previous.get("source_revision", 0)) != int(current.get("source_revision", 0)):
			previous_replacements.append(previous)
			current_replacements.append(current)
	if removed_sources.is_empty() and added_sources.is_empty() and previous_replacements.is_empty():
		return false

	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		var allies: Dictionary = allies_by_player.get(observer, {})
		var states: PackedByteArray = states_by_player[observer]
		var counts: PackedInt32Array = visible_counts_by_player[observer]
		for source in removed_sources:
			if bool(allies.get(int(source["team"]), false)):
				changed = _apply_remove_visible_cells(states, counts, source["cells"]) or changed
		for source in added_sources:
			if bool(allies.get(int(source["team"]), false)):
				changed = _apply_add_visible_cells(states, counts, source["cells"]) or changed
		for replacement_index in range(previous_replacements.size()):
			var previous: Dictionary = previous_replacements[replacement_index]
			var current: Dictionary = current_replacements[replacement_index]
			var previous_team := int(previous["team"])
			var current_team := int(current["team"])
			if previous_team == current_team:
				if bool(allies.get(current_team, false)):
					changed = _apply_replace_visible_cells(states, counts, previous["cells"], current["cells"]) or changed
				continue
			if bool(allies.get(previous_team, false)):
				changed = _apply_remove_visible_cells(states, counts, previous["cells"]) or changed
			if bool(allies.get(current_team, false)):
				changed = _apply_add_visible_cells(states, counts, current["cells"]) or changed
		states_by_player[observer] = states
		visible_counts_by_player[observer] = counts
	return changed


func _add_source(source: Dictionary) -> bool:
	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		if bool(allies_by_player.get(observer, {}).get(int(source["team"]), false)):
			changed = _add_visible_cells(observer, source["cells"]) or changed
	return changed


func _add_visible_cells(observer: int, cells: PackedInt32Array) -> bool:
	var states: PackedByteArray = states_by_player[observer]
	var counts: PackedInt32Array = visible_counts_by_player[observer]
	var changed := _apply_add_visible_cells(states, counts, cells)
	states_by_player[observer] = states
	visible_counts_by_player[observer] = counts
	return changed

func _apply_add_visible_cells(states: PackedByteArray, counts: PackedInt32Array, cells: PackedInt32Array) -> bool:
	var changed := false
	for index in cells:
		if counts[index] == 0 and states[index] != VISIBLE:
			states[index] = VISIBLE
			changed = true
		counts[index] += 1
	return changed


func _apply_remove_visible_cells(states: PackedByteArray, counts: PackedInt32Array, cells: PackedInt32Array) -> bool:
	var changed := false
	for index in cells:
		counts[index] = maxi(0, counts[index] - 1)
		if counts[index] == 0 and states[index] == VISIBLE:
			states[index] = EXPLORED
			changed = true
	return changed


func _apply_replace_visible_cells(states: PackedByteArray, counts: PackedInt32Array, previous_cells: PackedInt32Array, current_cells: PackedInt32Array) -> bool:
	var previous_index := 0
	var current_index := 0
	var changed := false
	while previous_index < previous_cells.size() or current_index < current_cells.size():
		var previous_cell := previous_cells[previous_index] if previous_index < previous_cells.size() else 2147483647
		var current_cell := current_cells[current_index] if current_index < current_cells.size() else 2147483647
		if previous_cell == current_cell:
			previous_index += 1
			current_index += 1
		elif previous_cell < current_cell:
			counts[previous_cell] = maxi(0, counts[previous_cell] - 1)
			if counts[previous_cell] == 0 and states[previous_cell] == VISIBLE:
				states[previous_cell] = EXPLORED
				changed = true
			previous_index += 1
		else:
			if counts[current_cell] == 0 and states[current_cell] != VISIBLE:
				states[current_cell] = VISIBLE
				changed = true
			counts[current_cell] += 1
			current_index += 1
	return changed


func _index(cell: Vector2i) -> int:
	return cell.y * map_size.x + cell.x
