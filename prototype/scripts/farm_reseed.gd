class_name RoRFarmReseed
extends RefCounted

const MAX_RESERVES := 40


static func count(world, team: int) -> int:
	return world.economy_system.farm_reseed_queues_by_team.get(team, []).size()


static func change(world, granary: Dictionary, amount: int) -> String:
	if String(granary.get("kind", "")) != "granary" or String(granary.get("state", "")) != "complete" or float(granary.get("hp", 0)) <= 0:
		return "invalid_production_building"
	var team := int(granary["team"])
	var reserves: Array = world.economy_system.farm_reseed_queues_by_team.get(team, []).duplicate(true)
	if amount == 1:
		if not world.is_object_available(team, 50):
			return "building_unavailable"
		if reserves.size() >= MAX_RESERVES:
			return "farm_reserve_full"
		var cost: Dictionary = world.building_cost("farm", team)
		if not world.can_afford_resource_cost(team, cost):
			return "insufficient_resources"
		world.spend_resource_cost(team, cost,"reseed")
		reserves.append(cost.duplicate(true))
	elif amount == -1:
		if reserves.is_empty():
			return "farm_reserve_empty"
		world.refund_resource_cost(team, reserves.pop_back())
	else:
		return "invalid_farm_reserve_count"
	world.economy_system.farm_reseed_queues_by_team[team] = reserves
	world.emit_domain_event("farm_reserve_changed", {"team": team, "count": reserves.size()})
	return ""


static func try_reseed(world, worker: Dictionary) -> bool:
	if float(worker.get("carried_amount", 0)) > 0 or not preload("res://scripts/order_pipeline.gd").queued(worker).is_empty():
		return false
	var team := int(worker.get("team", 0))
	var reserves: Array = world.economy_system.farm_reseed_queues_by_team.get(team, [])
	if reserves.is_empty():
		return false
	var farm = world.find_building(int(worker.get("resource_id", -1)))
	if farm == null or String(farm.get("kind", "")) != "farm" or String(farm.get("resource_state", "")) != "depleted" or String(farm.get("state", "")) != "complete" or int(farm.get("team", 0)) != team or float(farm.get("hp", 0)) <= 0:
		return false
	var paid_cost: Dictionary = reserves[0]
	if world.foundation_system.reseed_harvestable_building(farm, [worker], paid_cost) == null:
		return false
	reserves.pop_front()
	world.emit_domain_event("farm_reserve_consumed", {"team": team, "farm_id": int(farm["id"]), "count": reserves.size()})
	return true
