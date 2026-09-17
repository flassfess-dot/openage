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


func _init(world_size: Vector2i = Vector2i.ONE) -> void:
	map_size = Vector2i(maxi(1, world_size.x), maxi(1, world_size.y))


func reset() -> void:
	states_by_player.clear()
	visible_counts_by_player.clear()
	allies_by_player.clear()
	vision_sources.clear()
	visibility_topology_dirty = true
	revision += 1


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
	for entity in units:
		ensure_player(int(entity.get("team", 0)))
	for entity in buildings:
		ensure_player(int(entity.get("team", 0)))

	var current_sources: Dictionary = {}
	_collect_sources(units, "unit", current_sources, movement_bucket_count, movement_bucket_index)
	_collect_sources(buildings, "building", current_sources, movement_bucket_count, movement_bucket_index)
	var changed := false
	if visibility_topology_dirty:
		changed = _rebuild_visibility(current_sources)
	else:
		for source_key in vision_sources.keys():
			if current_sources.has(source_key):
				continue
			changed = _remove_source(vision_sources[source_key]) or changed
		for source_key in current_sources.keys():
			var current: Dictionary = current_sources[source_key]
			var previous: Variant = vision_sources.get(source_key)
			if previous == null:
				changed = _add_source(current) or changed
			elif previous != current:
				changed = _replace_source(previous, current) or changed
	vision_sources = current_sources
	visibility_topology_dirty = false
	if changed:
		revision += 1


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


func _collect_sources(entities: Array, category: String, result: Dictionary, movement_bucket_count: int, movement_bucket_index: int) -> void:
	for index in range(entities.size()):
		var entity: Dictionary = entities[index]
		if float(entity.get("hp", 0.0)) <= 0.0:
			continue
		var vision: Dictionary = entity.get("components", {}).get("vision", {})
		var sight_radius := maxf(0.0, float(vision.get("range", 0.0)))
		if sight_radius <= 0.0 or not bool(vision.get("enabled", true)):
			continue
		var source_player := int(entity.get("team", 0))
		if source_player <= 0:
			continue
		var entity_id := int(entity.get("id", -1))
		var source_key := "%s:%d" % [category, entity_id if entity_id >= 0 else index]
		var center := Vector2(entity.get("pos", Vector2.ZERO))
		var previous: Variant = vision_sources.get(source_key)
		if previous != null and int(previous.get("team", 0)) == source_player and Vector2(previous.get("center", Vector2.ZERO)).is_equal_approx(center) and is_equal_approx(float(previous.get("radius", 0.0)), sight_radius):
			result[source_key] = previous
			continue
		var stable_bucket_value := entity_id if entity_id >= 0 else index
		var movement_refresh_deferred := (
			previous != null
			and int(previous.get("team", 0)) == source_player
			and is_equal_approx(float(previous.get("radius", 0.0)), sight_radius)
			and maxi(1, movement_bucket_count) > 1
			and posmod(stable_bucket_value, maxi(1, movement_bucket_count)) != posmod(movement_bucket_index, maxi(1, movement_bucket_count))
		)
		if movement_refresh_deferred:
			result[source_key] = previous
			continue
		result[source_key] = {
			"team": source_player,
			"center": center,
			"radius": sight_radius,
			"cells": _vision_cells(center, sight_radius),
		}


func _vision_cells(center: Vector2, radius: float) -> PackedInt32Array:
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


func _add_source(source: Dictionary) -> bool:
	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		if bool(allies_by_player.get(observer, {}).get(int(source["team"]), false)):
			changed = _add_visible_cells(observer, source["cells"]) or changed
	return changed


func _remove_source(source: Dictionary) -> bool:
	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		if bool(allies_by_player.get(observer, {}).get(int(source["team"]), false)):
			changed = _remove_visible_cells(observer, source["cells"]) or changed
	return changed


func _replace_source(previous: Dictionary, current: Dictionary) -> bool:
	if int(previous["team"]) != int(current["team"]):
		var removed := _remove_source(previous)
		var added := _add_source(current)
		return removed or added
	var changed := false
	for observer_value in states_by_player.keys():
		var observer := int(observer_value)
		if bool(allies_by_player.get(observer, {}).get(int(current["team"]), false)):
			changed = _replace_visible_cells(observer, previous["cells"], current["cells"]) or changed
	return changed


func _add_visible_cells(observer: int, cells: PackedInt32Array) -> bool:
	var states: PackedByteArray = states_by_player[observer]
	var counts: PackedInt32Array = visible_counts_by_player[observer]
	var changed := false
	for index in cells:
		if counts[index] == 0 and states[index] != VISIBLE:
			states[index] = VISIBLE
			changed = true
		counts[index] += 1
	states_by_player[observer] = states
	visible_counts_by_player[observer] = counts
	return changed


func _remove_visible_cells(observer: int, cells: PackedInt32Array) -> bool:
	var states: PackedByteArray = states_by_player[observer]
	var counts: PackedInt32Array = visible_counts_by_player[observer]
	var changed := false
	for index in cells:
		counts[index] = maxi(0, counts[index] - 1)
		if counts[index] == 0 and states[index] == VISIBLE:
			states[index] = EXPLORED
			changed = true
	states_by_player[observer] = states
	visible_counts_by_player[observer] = counts
	return changed


func _replace_visible_cells(observer: int, previous_cells: PackedInt32Array, current_cells: PackedInt32Array) -> bool:
	var states: PackedByteArray = states_by_player[observer]
	var counts: PackedInt32Array = visible_counts_by_player[observer]
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
	states_by_player[observer] = states
	visible_counts_by_player[observer] = counts
	return changed


func _index(cell: Vector2i) -> int:
	return cell.y * map_size.x + cell.x
