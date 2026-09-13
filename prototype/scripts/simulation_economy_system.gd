class_name RoRSimulationEconomySystem
extends RefCounted

var resource_stockpiles_by_team: Dictionary = {}
var population_by_team: Dictionary = {}
var population_reserved_by_team: Dictionary = {}
var population_cap_by_team: Dictionary = {}
var population_limit_by_team: Dictionary = {}
var population_housing_by_team: Dictionary = {}
var population_housing_enabled_by_team: Dictionary = {}


func reset(default_food: int = 180, default_wood: int = 120) -> void:
	resource_stockpiles_by_team.clear()
	population_by_team.clear()
	population_reserved_by_team.clear()
	population_cap_by_team.clear()
	population_limit_by_team.clear()
	population_housing_by_team.clear()
	population_housing_enabled_by_team.clear()
	set_resource_amount(1, 0, default_food)
	set_resource_amount(1, 1, default_wood)


func get_resource_amount(team: int, resource_id: int) -> int:
	return int(resource_stockpiles_by_team.get(team, {}).get(resource_id, 0))


func set_resource_amount(team: int, resource_id: int, amount: int) -> void:
	if not resource_stockpiles_by_team.has(team):
		resource_stockpiles_by_team[team] = {}
	resource_stockpiles_by_team[team][resource_id] = maxi(0, amount)


func change_resource_amount(team: int, resource_id: int, delta: int) -> int:
	var updated := get_resource_amount(team, resource_id) + delta
	set_resource_amount(team, resource_id, updated)
	return get_resource_amount(team, resource_id)


func can_afford(team: int, cost: Dictionary) -> bool:
	for resource_id in cost:
		if get_resource_amount(team, int(resource_id)) < int(cost[resource_id]):
			return false
	return true


func spend(team: int, cost: Dictionary) -> void:
	for resource_id in cost:
		change_resource_amount(team, int(resource_id), -int(cost[resource_id]))


func refund(team: int, cost: Dictionary) -> void:
	for resource_id in cost:
		change_resource_amount(team, int(resource_id), int(cost[resource_id]))


func get_population(team: int) -> int:
	return int(population_by_team.get(team, 0))


func add_population(team: int, amount: int) -> void:
	population_by_team[team] = maxi(0, get_population(team) + amount)


func get_reserved_population(team: int) -> int:
	return int(population_reserved_by_team.get(team, 0))


func can_reserve_population(team: int, amount: int) -> bool:
	return get_population(team) + get_reserved_population(team) + maxi(0, amount) <= get_population_cap(team)


func reserve_population(team: int, amount: int) -> void:
	population_reserved_by_team[team] = get_reserved_population(team) + maxi(0, amount)


func release_reserved_population(team: int, amount: int) -> void:
	population_reserved_by_team[team] = maxi(0, get_reserved_population(team) - maxi(0, amount))


func get_population_cap(team: int) -> int:
	return int(population_cap_by_team.get(team, _effective_population_cap(team)))


func set_population_cap(team: int, value: int) -> void:
	population_limit_by_team[team] = maxi(0, value)
	_sync_population_cap(team)


func enable_population_housing(team: int) -> void:
	population_housing_enabled_by_team[team] = true
	if not population_housing_by_team.has(team):
		population_housing_by_team[team] = 0
	_sync_population_cap(team)


func set_population_housing(team: int, value: int) -> void:
	population_housing_enabled_by_team[team] = true
	population_housing_by_team[team] = maxi(0, value)
	_sync_population_cap(team)


func add_population_housing(team: int, amount: int) -> void:
	enable_population_housing(team)
	population_housing_by_team[team] = maxi(0, int(population_housing_by_team.get(team, 0)) + amount)
	_sync_population_cap(team)


func get_population_housing(team: int) -> int:
	return int(population_housing_by_team.get(team, 0))


func get_population_limit(team: int) -> int:
	return int(population_limit_by_team.get(team, 50))


func _effective_population_cap(team: int) -> int:
	var limit := get_population_limit(team)
	if bool(population_housing_enabled_by_team.get(team, false)):
		return mini(limit, get_population_housing(team))
	return limit


func _sync_population_cap(team: int) -> void:
	population_cap_by_team[team] = _effective_population_cap(team)


func snapshot() -> Dictionary:
	return {
		"resource_stockpiles": resource_stockpiles_by_team.duplicate(true),
		"population": population_by_team.duplicate(true),
		"population_reserved": population_reserved_by_team.duplicate(true),
		"population_cap": population_cap_by_team.duplicate(true),
		"population_limit": population_limit_by_team.duplicate(true),
		"population_housing": population_housing_by_team.duplicate(true),
		"population_housing_enabled": population_housing_enabled_by_team.duplicate(true),
	}
