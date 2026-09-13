class_name RoRFogOfWar

const UNKNOWN := 0
const EXPLORED := 1
const VISIBLE := 2

var map_size: Vector2i
var states_by_player: Dictionary = {}
var allies_by_player: Dictionary = {}
var revision: int = 0


func _init(world_size: Vector2i = Vector2i.ONE) -> void:
	map_size = Vector2i(maxi(1, world_size.x), maxi(1, world_size.y))


func reset() -> void:
	states_by_player.clear()
	allies_by_player.clear()
	revision += 1


func ensure_player(player_id: int) -> void:
	if player_id <= 0:
		return
	if not states_by_player.has(player_id):
		var states := PackedByteArray()
		states.resize(map_size.x * map_size.y)
		states.fill(UNKNOWN)
		states_by_player[player_id] = states
	if not allies_by_player.has(player_id):
		allies_by_player[player_id] = {player_id: true}


func set_alliance(first_player: int, second_player: int, allied: bool = true) -> void:
	ensure_player(first_player)
	ensure_player(second_player)
	if allied:
		allies_by_player[first_player][second_player] = true
		allies_by_player[second_player][first_player] = true
	else:
		if first_player != second_player:
			allies_by_player[first_player].erase(second_player)
			allies_by_player[second_player].erase(first_player)
	revision += 1


func are_allied(observer_player: int, owner_player: int) -> bool:
	if observer_player <= 0 or owner_player <= 0:
		return false
	ensure_player(observer_player)
	ensure_player(owner_player)
	return bool(allies_by_player[observer_player].get(owner_player, false))


func update(units: Array, buildings: Array) -> void:
	for entity in units + buildings:
		ensure_player(int(entity.get("team", 0)))
	for player_value in states_by_player.keys():
		var player_id := int(player_value)
		var states: PackedByteArray = states_by_player[player_id]
		for index in range(states.size()):
			if states[index] == VISIBLE:
				states[index] = EXPLORED
		states_by_player[player_id] = states

	for entity in units + buildings:
		if float(entity.get("hp", 0.0)) <= 0.0:
			continue
		var vision: Dictionary = entity.get("components", {}).get("vision", {})
		var sight_radius := maxf(0.0, float(vision.get("range", 0.0)))
		if sight_radius <= 0.0 or not bool(vision.get("enabled", true)):
			continue
		var source_player := int(entity.get("team", 0))
		if source_player <= 0:
			continue
		for observer_value in states_by_player.keys():
			var observer_player := int(observer_value)
			if are_allied(observer_player, source_player):
				_reveal_circle(observer_player, Vector2(entity["pos"]), sight_radius)
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


func _reveal_circle(player_id: int, center: Vector2, radius: float) -> void:
	var states: PackedByteArray = states_by_player[player_id]
	var minimum := Vector2i(maxi(0, floori(center.x - radius)), maxi(0, floori(center.y - radius)))
	var maximum := Vector2i(mini(map_size.x - 1, floori(center.x + radius)), mini(map_size.y - 1, floori(center.y + radius)))
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var nearest := Vector2(clampf(center.x, float(x), float(x + 1)), clampf(center.y, float(y), float(y + 1)))
			if center.distance_squared_to(nearest) <= radius * radius + 0.000001:
				states[_index(Vector2i(x, y))] = VISIBLE
	states_by_player[player_id] = states


func _index(cell: Vector2i) -> int:
	return cell.y * map_size.x + cell.x
