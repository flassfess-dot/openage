class_name RoRAiPlanBudget
extends RefCounted

const RESOURCE_NAMES := ["food", "wood", "stone", "gold"]
var remaining: Dictionary = {}
var protected: Dictionary = {}
var population_points := 0
var producer_orders: Dictionary = {}
var rejected := 0


func _init(player: Dictionary = {}, buildings: Array = []) -> void:
	for type_id in range(RESOURCE_NAMES.size()):
		remaining[type_id] = maxi(0, int(player.get(RESOURCE_NAMES[type_id], 0)))
	var cap := mini(int(player.get("population_cap", 0)), int(player.get("population_limit", 50))) * 2
	var queued_points := 0
	for building in buildings:
		for order in building.get("production_queue", []):
			if String(order.get("order_type", "unit")) == "unit":
				queued_points += maxi(
					0, int(order.get("population_points_cost", int(order.get("population_cost", 1)) * 2))
				)
	population_points = maxi(
		0,
		(
			cap
			- int(player.get("population_points", int(player.get("population", 0)) * 2))
			- maxi(queued_points, int(player.get("population_reserved", 0)) * 2)
		)
	)


func protect(cost: Dictionary) -> void:
	protected.clear()
	for key in cost:
		protected[int(key)] = mini(int(remaining.get(int(key), 0)), maxi(0, int(cost[key])))


func can_reserve(cost: Dictionary, points: int = 0, producer_id: int = -1, essential: bool = false) -> bool:
	if points > population_points or (producer_id >= 0 and producer_orders.has(producer_id)):
		return false
	for key in cost:
		var type_id := int(key)
		var available := int(remaining.get(type_id, 0)) - (0 if essential else int(protected.get(type_id, 0)))
		if maxi(0, int(cost[key])) > available:
			return false
	return true


func reserve(cost: Dictionary, points: int = 0, producer_id: int = -1, essential: bool = false) -> bool:
	if not can_reserve(cost, points, producer_id, essential):
		rejected += 1
		return false
	for key in cost:
		var type_id := int(key)
		remaining[type_id] = int(remaining.get(type_id, 0)) - maxi(0, int(cost[key]))
		protected[type_id] = mini(int(protected.get(type_id, 0)), int(remaining[type_id]))
	population_points -= maxi(0, points)
	if producer_id >= 0:
		producer_orders[producer_id] = true
	return true
