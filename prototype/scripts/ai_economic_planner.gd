class_name RoRAiEconomicPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")


static func plan(snapshot: Dictionary, tick: int, team: int) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var commands: Array = []
	var own_units: Array = snapshot.get("units", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0)
	var idle_workers: Array = own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("task", "idle")) == "idle")
	var own_buildings: Array = snapshot.get("buildings", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0 and String(entity.get("state", "complete")) == "complete")
	commands.append_array(_plan_idle_trade(snapshot, tick, team, own_units, own_buildings))
	var committed_workers: Dictionary = {}
	var site_kinds: Array = snapshot.get("build_sites", {}).keys()
	site_kinds.sort()
	for kind_value in site_kinds:
		var kind := String(kind_value)
		if own_buildings.any(func(building): return String(building.get("kind", "")) == kind):
			continue
		var sites: Array = snapshot.get("build_sites", {}).get(kind, [])
		var candidates: Array = []
		for worker_value in idle_workers:
			var worker: Dictionary = worker_value
			if String(worker.get("movement_domain", "land")) != "land":
				continue
			var build_options: Array = worker.get("command_options", {}).get("build", [])
			if not build_options.any(func(option): return String(option.get("kind", "")) == kind and bool(option.get("accepted", false))):
				continue
			for site_value in sites:
				var site := Vector2(site_value)
				candidates.append({"worker": worker, "site": site, "distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(site)})
		candidates.sort_custom(func(left, right):
			if not is_equal_approx(float(left["distance"]), float(right["distance"])):
				return float(left["distance"]) < float(right["distance"])
			return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
		)
		if not candidates.is_empty():
			var candidate: Dictionary = candidates[0]
			var worker_id := int(candidate["worker"].get("id", -1))
			commands.append(Commands.BuildCommand.new(tick, [worker_id], kind, candidate["site"]))
			committed_workers[worker_id] = true
			break
	var resources: Array = snapshot.get("resources", []).filter(func(entity): return int(entity.get("amount", 0)) > 0)
	for building_value in snapshot.get("buildings", []):
		var building: Dictionary = building_value
		if bool(building.get("harvestable", false)) and int(building.get("team", 0)) == team and int(building.get("amount", 0)) > 0:
			resources.append(building)
	if not idle_workers.is_empty() and not resources.is_empty():
		var pairs: Array = []
		for worker_value in idle_workers:
			var worker: Dictionary = worker_value
			if committed_workers.has(int(worker.get("id", -1))):
				continue
			for resource_value in resources:
				var resource: Dictionary = resource_value
				if not _resource_allows_worker(resource, worker):
					continue
				pairs.append({"worker": worker, "resource": resource, "distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(resource.get("pos", Vector2.ZERO)))})
		pairs.sort_custom(func(left, right):
			if not is_equal_approx(float(left["distance"]), float(right["distance"])):
				return float(left["distance"]) < float(right["distance"])
			if int(left["worker"].get("id", -1)) != int(right["worker"].get("id", -1)):
				return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
			return int(left["resource"].get("id", -1)) < int(right["resource"].get("id", -1))
		)
		if not pairs.is_empty():
			var assignment: Dictionary = pairs[0]
			commands.append(Commands.GatherCommand.new(tick, [int(assignment["worker"].get("id", -1))], int(assignment["resource"].get("id", -1))))

	for building_value in own_buildings:
		var building: Dictionary = building_value
		if not building.get("production_queue", []).is_empty():
			continue
		var train_options: Array = building.get("command_options", {}).get("train", [])
		var enabled := train_options.filter(func(option): return bool(option.get("accepted", false)))
		if not enabled.is_empty():
			var preferred: Dictionary = _preferred_unit(enabled, own_units, building, snapshot, team)
			commands.append(Commands.TrainCommand.new(tick, [int(building.get("id", -1))], String(preferred.get("kind", "")), team, Vector2(building.get("rally_point", building.get("pos", Vector2.ZERO)))))
			continue
		var research_options: Array = building.get("command_options", {}).get("research", [])
		var available_research := research_options.filter(func(option): return bool(option.get("accepted", false)))
		if not available_research.is_empty():
			commands.append(Commands.ResearchCommand.new(tick, [int(building.get("id", -1))], String.num_int64(int(available_research[0].get("technology_id", -1)))))
	return commands


static func _resource_allows_worker(resource: Dictionary, worker: Dictionary) -> bool:
	var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
	return allowed_domains.is_empty() or String(worker.get("movement_domain", "land")) in allowed_domains


static func _preferred_unit(options: Array, own_units: Array, building: Dictionary, snapshot: Dictionary, team: int) -> Dictionary:
	if String(building.get("kind", "")) == "dock":
		return _preferred_naval_unit(options, own_units, snapshot, team)
	var worker_count := own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("movement_domain", "land")) == "land").size()
	if worker_count < 4:
		for option_value in options:
			var option: Dictionary = option_value
			if String(option.get("kind", "")) == "villager":
				return option
	for option_value in options:
		var option: Dictionary = option_value
		if String(option.get("kind", "")) != "villager":
			return option
	return options[0]


static func _preferred_naval_unit(options: Array, own_units: Array, snapshot: Dictionary, team: int) -> Dictionary:
	var water_workers := own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("movement_domain", "")) == "water").size()
	var water_food_known: bool = snapshot.get("resources", []).any(func(resource):
		return int(resource.get("amount", 0)) > 0 and 0 == int(resource.get("resource_type_id", 0)) and "water" in resource.get("allowed_gatherer_domains", [])
	)
	if water_workers < 2 and water_food_known:
		var fishing := _first_option_with_tag(options, "worker")
		if not fishing.is_empty():
			return fishing
	var traders := own_units.filter(func(entity): return bool(entity.get("components", {}).get("trade", {}).get("enabled", false))).size()
	var foreign_dock_known: bool = snapshot.get("buildings", []).any(func(entity): return int(entity.get("team", 0)) > 0 and int(entity.get("team", 0)) != team and entity.has("trade"))
	if traders < 1 and foreign_dock_known:
		var trader := _first_option_with_tag(options, "trader")
		if not trader.is_empty():
			return trader
	var warships := own_units.filter(func(entity): return String(entity.get("movement_domain", "")) == "water" and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", []))).size()
	if warships < 3:
		var combatant := _first_option_with_tag(options, "combatant")
		if not combatant.is_empty():
			return combatant
	var transports := own_units.filter(func(entity): return bool(entity.get("components", {}).get("cargo", {}).get("enabled", false))).size()
	var enemy_land_known: bool = snapshot.get("units", []).any(func(entity): return int(entity.get("team", 0)) > 0 and int(entity.get("team", 0)) != team and String(entity.get("movement_domain", "land")) == "land")
	if transports < 1 and enemy_land_known:
		var transport := _first_option_with_tag(options, "transport")
		if not transport.is_empty():
			return transport
	for tag in ["combatant", "worker", "trader", "transport"]:
		var fallback := _first_option_with_tag(options, tag)
		if not fallback.is_empty():
			return fallback
	return options[0]


static func _first_option_with_tag(options: Array, tag: String) -> Dictionary:
	for option_value in options:
		var option: Dictionary = option_value
		if tag in option.get("behavior_tags", []):
			return option
	return {}


static func _plan_idle_trade(snapshot: Dictionary, tick: int, team: int, own_units: Array, own_buildings: Array) -> Array:
	if not own_buildings.any(func(building): return building.has("trade")):
		return []
	var foreign_docks: Array = snapshot.get("buildings", []).filter(func(building): return int(building.get("team", 0)) > 0 and int(building.get("team", 0)) != team and building.has("trade") and String(building.get("state", "complete")) == "complete")
	if foreign_docks.is_empty():
		return []
	foreign_docks.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var traders: Array = own_units.filter(func(unit): return bool(unit.get("components", {}).get("trade", {}).get("enabled", false)) and String(unit.get("task", "idle")) == "idle")
	traders.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var player_state: Dictionary = snapshot.get("player_state", {})
	var resource_amounts := {0: int(player_state.get("food", 0)), 1: int(player_state.get("wood", 0)), 2: int(player_state.get("stone", 0))}
	var chosen_resource := 0
	for resource_type_id in [1, 2]:
		if int(resource_amounts[resource_type_id]) > int(resource_amounts[chosen_resource]):
			chosen_resource = resource_type_id
	var result: Array = []
	for trader_value in traders:
		var trader: Dictionary = trader_value
		var current_resource := int(trader.get("components", {}).get("trade", {}).get("selected_input_resource_type_id", 1))
		if current_resource != chosen_resource:
			result.append(Commands.SetTradeResourceCommand.new(tick, [int(trader.get("id", -1))], chosen_resource))
		result.append(Commands.TradeCommand.new(tick, [int(trader.get("id", -1))], int(foreign_docks[0].get("id", -1))))
	return result
