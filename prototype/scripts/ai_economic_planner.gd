class_name RoRAiEconomicPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")


static func plan(snapshot: Dictionary, tick: int, team: int, policy: Dictionary = {}, reserved_unit_ids: Dictionary = {}) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var commands: Array = []
	var own_units: Array = snapshot.get("units", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0)
	var idle_workers: Array = own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("task", "idle")) == "idle" and not reserved_unit_ids.has(int(entity.get("id", -1))))
	var own_structures: Array = snapshot.get("buildings", []).filter(func(entity): return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0)
	var own_buildings: Array = own_structures.filter(func(entity): return String(entity.get("state", "complete")) == "complete")
	var water_frontier: Array = snapshot.get("navigation", {}).get("reachable_frontier", {}).get("water", [])
	var naval_scout_pending := not water_frontier.is_empty() and own_buildings.any(func(building): return String(building.get("kind", "")) == "dock")
	if naval_scout_pending:
		naval_scout_pending = own_units.any(func(unit): return String(unit.get("movement_domain", "")) == "water" and bool(unit.get("components", {}).get("worker", {}).get("enabled", false)))
		naval_scout_pending = naval_scout_pending and not own_units.any(func(unit): return String(unit.get("movement_domain", "")) == "water" and (bool(unit.get("combat_enabled", false)) or "combatant" in unit.get("behavior_tags", [])))
	var blocked_population := int(snapshot.get("player_state", {}).get("blocked_population_queues", 0)) > 0 or own_buildings.any(func(building): return not building.get("production_queue", []).is_empty() and String(building.get("production_queue", [])[0].get("status", "")) == "blocked_population")
	var queued_population_points := _active_order_population_points(own_buildings)
	var land_workers: Array = own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("movement_domain", "land")) == "land")
	var construction_workers: Array = land_workers.filter(func(entity): return String(entity.get("task", "idle")) in ["idle", "gather"] and not reserved_unit_ids.has(int(entity.get("id", -1))))
	var land_worker_count := land_workers.size()
	var military_count := own_units.filter(func(entity): return not bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", []))).size()
	var wartime_combatant_target := int(policy.get("wartime_combatant_target", 0))
	var age_intent := _age_advance_intent(own_buildings, snapshot.get("player_state", {}), policy, land_worker_count, tick)
	if age_intent.has("command"):
		commands.append(age_intent["command"])
	commands.append_array(_plan_idle_trade(snapshot, tick, team, own_units, own_buildings))
	var committed_workers: Dictionary = {}
	var active_foundations: Array = own_structures.filter(func(entity): return String(entity.get("state", "complete")) == "foundation")
	active_foundations.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var foundation_has_assigned_worker := false
	if not active_foundations.is_empty():
		var active_foundation_id := int(active_foundations[0].get("id", -1))
		foundation_has_assigned_worker = own_units.any(func(unit): return String(unit.get("task", "")) == "build" and int(unit.get("target_building_id", -1)) == active_foundation_id)
	if not active_foundations.is_empty() and not land_workers.is_empty() and int(active_foundations[0].get("builder_count", 0)) == 0 and not foundation_has_assigned_worker:
		var foundation: Dictionary = active_foundations[0]
		var reachable_builder_ids: Array = foundation.get("reachable_builder_ids", [])
		var builder_candidates: Array = land_workers.filter(func(worker): return not reserved_unit_ids.has(int(worker.get("id", -1))) and (not foundation.has("reachable_builder_ids") or int(worker.get("id", -1)) in reachable_builder_ids))
		builder_candidates.sort_custom(func(left, right):
			var left_stuck := 1 if String(left.get("diagnostic_reason", "")).begins_with("stuck_") else 0
			var right_stuck := 1 if String(right.get("diagnostic_reason", "")).begins_with("stuck_") else 0
			if left_stuck != right_stuck:
				return left_stuck < right_stuck
			var left_idle := 0 if String(left.get("task", "idle")) == "idle" else 1
			var right_idle := 0 if String(right.get("task", "idle")) == "idle" else 1
			if left_idle != right_idle:
				return left_idle < right_idle
			var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(foundation.get("pos", Vector2.ZERO)))
			var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(foundation.get("pos", Vector2.ZERO)))
			return left_distance < right_distance if not is_equal_approx(left_distance, right_distance) else int(left.get("id", -1)) < int(right.get("id", -1))
		)
		if not builder_candidates.is_empty():
			var builder: Dictionary = builder_candidates[0]
			var builder_id := int(builder.get("id", -1))
			commands.append(Commands.BuildCommand.new(tick, [builder_id], String(foundation.get("kind", "")), Vector2(foundation.get("pos", Vector2.ZERO))))
			committed_workers[builder_id] = true
	var site_kinds: Array = snapshot.get("build_sites", {}).keys()
	_sort_build_kinds(site_kinds, policy.get("construction_priorities", []))
	for kind_value in site_kinds:
		if not active_foundations.is_empty():
			break
		var kind := String(kind_value)
		if naval_scout_pending and kind not in ["house", "dock"]:
			continue
		if age_intent.has("command"):
			continue
		if bool(age_intent.get("block_construction", false)) and not _age_saving_build_allowed(kind, construction_workers, age_intent.get("cost", {}), policy.get("age_saving_construction_exceptions", [])):
			continue
		var limit := int(policy.get("building_limits", {}).get(kind, 1))
		var same_kind := own_structures.filter(func(building): return String(building.get("kind", "")) == kind)
		var existing_count := same_kind.size()
		if limit <= 0 or existing_count >= limit:
			continue
		if same_kind.any(func(building): return String(building.get("state", "complete")) != "complete"):
			continue
		if kind == "house" and not _needs_housing(snapshot.get("player_state", {}), int(policy.get("housing_buffer", 0)), blocked_population, queued_population_points):
			continue
		var sites: Array = snapshot.get("build_sites", {}).get(kind, [])
		var candidates: Array = []
		var allow_gap_fallback: bool = kind in policy.get("structure_gap_fallback_kinds", [])
		for worker_value in construction_workers:
			var worker: Dictionary = worker_value
			if String(worker.get("movement_domain", "land")) != "land":
				continue
			var build_options: Array = worker.get("command_options", {}).get("build", [])
			if not build_options.any(func(option): return String(option.get("kind", "")) == kind and bool(option.get("accepted", false))):
				continue
			for site_value in sites:
				var site := Vector2(site_value)
				var preserves_gap := _site_preserves_structure_gap(site, kind, worker, own_structures, float(policy.get("minimum_structure_gap", 0.0)))
				if not preserves_gap and not allow_gap_fallback:
					continue
				candidates.append({"worker": worker, "site": site, "distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(site), "preserves_gap": preserves_gap})
		candidates.sort_custom(func(left, right):
			if bool(left["preserves_gap"]) != bool(right["preserves_gap"]):
				return bool(left["preserves_gap"])
			var left_idle := 0 if String(left["worker"].get("task", "idle")) == "idle" else 1
			var right_idle := 0 if String(right["worker"].get("task", "idle")) == "idle" else 1
			if left_idle != right_idle:
				return left_idle < right_idle
			var left_failure := _navigation_failure_rank(left["worker"])
			var right_failure := _navigation_failure_rank(right["worker"])
			if left_failure != right_failure:
				return left_failure < right_failure
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
	var reachable_resource_cells := _reachable_cells_by_domain(snapshot.get("navigation", {}))
	for building_value in snapshot.get("buildings", []):
		var building: Dictionary = building_value
		if bool(building.get("harvestable", false)) and int(building.get("team", 0)) == team and int(building.get("amount", 0)) > 0:
			resources.append(building)
	var age_resource_types: Array = []
	if bool(age_intent.get("saving", false)):
		for resource_type_value in age_intent.get("cost", {}).keys():
			age_resource_types.append(int(resource_type_value))
		var age_resources := resources.filter(func(resource): return int(resource.get("resource_type_id", -1)) in age_resource_types)
		if not age_resources.is_empty():
			resources = age_resources
	if not resources.is_empty():
		var pairs: Array = []
		var stockpile: Dictionary = snapshot.get("player_state", {})
		var desired_stock := {0: 600 if int(stockpile.get("age", 100)) <= 100 else 450, 1: 350, 2: 150, 3: 150}
		for resource_type_value in age_intent.get("cost", {}).keys():
			var type_id := int(resource_type_value)
			if desired_stock.has(type_id):
				desired_stock[type_id] = maxi(int(desired_stock[type_id]), int(age_intent["cost"][resource_type_value]) + 100)
		var resource_names := ["food", "wood", "stone", "gold"]
		var shortages: Dictionary = {}
		var critical_type := -1
		for resource_type in range(resource_names.size()):
			shortages[resource_type] = maxi(0, int(desired_stock[resource_type]) - int(stockpile.get(resource_names[resource_type], 0)))
			if int(shortages[resource_type]) > 0 and (critical_type < 0 or int(shortages[resource_type]) > int(shortages[critical_type])):
				critical_type = resource_type
		var resources_by_id: Dictionary = {}
		for resource_value in snapshot.get("resources", []):
			resources_by_id[int(resource_value.get("id", -1))] = resource_value
		var candidate_workers: Array = idle_workers.duplicate()
		if critical_type >= 0:
			for worker_value in own_units:
				var active_worker: Dictionary = worker_value
				if not bool(active_worker.get("components", {}).get("worker", {}).get("enabled", false)) or String(active_worker.get("task", "")) != "gather" or reserved_unit_ids.has(int(active_worker.get("id", -1))) or committed_workers.has(int(active_worker.get("id", -1))):
					continue
				var current_resource_id := int(active_worker.get("resource_id", -1))
				if current_resource_id < 0:
					current_resource_id = int(active_worker.get("components", {}).get("order", {}).get("target_entity_id", -1))
				var current_resource: Dictionary = resources_by_id.get(current_resource_id, {})
				if current_resource.is_empty() or int(current_resource.get("resource_type_id", -1)) == critical_type:
					continue
				candidate_workers.append(active_worker)
		for worker_value in candidate_workers:
			var worker: Dictionary = worker_value
			if committed_workers.has(int(worker.get("id", -1))):
				continue
			for resource_value in resources:
				var resource: Dictionary = resource_value
				if not _resource_allows_worker(resource, worker):
					continue
				if _resource_previously_failed_for_worker(resource, worker, policy.get("failed_gather_targets", {})):
					continue
				if not _resource_has_reachable_approach(resource, worker, reachable_resource_cells):
					continue
				var resource_type := int(resource.get("resource_type_id", -1))
				var active_gatherer := String(worker.get("task", "idle")) == "gather"
				if active_gatherer and resource_type != critical_type:
					continue
				var shortage := int(shortages.get(resource_type, 0))
				pairs.append({"worker": worker, "resource": resource, "shortage": shortage, "active_gatherer": active_gatherer, "distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(resource.get("pos", Vector2.ZERO)))})
		pairs.sort_custom(func(left, right):
			if int(left["shortage"]) != int(right["shortage"]):
				return int(left["shortage"]) > int(right["shortage"])
			if bool(left["active_gatherer"]) != bool(right["active_gatherer"]):
				return not bool(left["active_gatherer"])
			var left_failure := _navigation_failure_rank(left["worker"])
			var right_failure := _navigation_failure_rank(right["worker"])
			if left_failure != right_failure:
				return left_failure < right_failure
			if not is_equal_approx(float(left["distance"]), float(right["distance"])):
				return float(left["distance"]) < float(right["distance"])
			if int(left["worker"].get("id", -1)) != int(right["worker"].get("id", -1)):
				return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
			return int(left["resource"].get("id", -1)) < int(right["resource"].get("id", -1))
		)
		if not pairs.is_empty():
			var assigned_domains: Dictionary = {}
			for assignment_value in pairs:
				var assignment: Dictionary = assignment_value
				var worker_domain := String(assignment["worker"].get("movement_domain", "land"))
				if assigned_domains.has(worker_domain):
					continue
				commands.append(Commands.GatherCommand.new(tick, [int(assignment["worker"].get("id", -1))], int(assignment["resource"].get("id", -1))))
				assigned_domains[worker_domain] = true

	for building_value in own_buildings:
		var building: Dictionary = building_value
		var queue: Array = building.get("production_queue", [])
		if queue.size() >= 2 or (not queue.is_empty() and (String(queue[0].get("order_type", "unit")) != "unit" or String(queue[0].get("status", "")) == "blocked_population")):
			continue
		if age_intent.has("command"):
			continue
		var train_options: Array = building.get("command_options", {}).get("train", [])
		var enabled := train_options.filter(func(option): return bool(option.get("accepted", false)))
		if naval_scout_pending and String(building.get("kind", "")) != "dock":
			enabled = enabled.filter(func(option): return "combatant" not in option.get("behavior_tags", []))
		if not queue.is_empty():
			enabled = enabled.filter(func(option): return String(option.get("kind", "")) == String(queue[0].get("kind", "")))
		if bool(age_intent.get("saving", false)):
			var age_cost: Dictionary = age_intent.get("cost", {})
			var production_exceptions: Array = policy.get("age_saving_production_exceptions", [])
			enabled = enabled.filter(func(option): return _age_saving_economic_option(option, age_cost, production_exceptions) or (military_count < wartime_combatant_target and "combatant" in option.get("behavior_tags", []) and "worker" not in option.get("behavior_tags", [])))
		var land_worker_target := int(policy.get("land_worker_target", policy.get("worker_target", 0)))
		if land_worker_target > 0 and land_worker_count >= land_worker_target:
			enabled = enabled.filter(func(option): return String(option.get("kind", "")) != "villager")
		var research_options: Array = building.get("command_options", {}).get("research", [])
		var available_research := [] if bool(age_intent.get("saving", false)) or not queue.is_empty() else research_options.filter(func(option): return bool(option.get("accepted", false)))
		if not enabled.is_empty():
			var preferred: Dictionary = _preferred_unit(enabled, own_units, building, snapshot, team, policy)
			if not preferred.is_empty():
				commands.append(Commands.TrainCommand.new(tick, [int(building.get("id", -1))], String(preferred.get("kind", "")), team, Vector2(building.get("rally_point", building.get("pos", Vector2.ZERO)))))
				continue
		if not available_research.is_empty():
			commands.append(Commands.ResearchCommand.new(tick, [int(building.get("id", -1))], String.num_int64(int(available_research[0].get("technology_id", -1)))))
	return commands


static func _age_saving_economic_option(option: Dictionary, age_cost: Dictionary, exceptions: Array = []) -> bool:
	if "worker" not in option.get("behavior_tags", []) and String(option.get("kind", "")) not in exceptions:
		return false
	var option_cost: Dictionary = option.get("cost", {})
	if option_cost.is_empty():
		return false
	return _cost_avoids_reserved_resources(option_cost, age_cost)


static func _age_saving_build_allowed(kind: String, workers: Array, age_cost: Dictionary, exceptions: Array) -> bool:
	if kind not in exceptions:
		return false
	for worker_value in workers:
		var worker: Dictionary = worker_value
		for option_value in worker.get("command_options", {}).get("build", []):
			var option: Dictionary = option_value
			if String(option.get("kind", "")) == kind and bool(option.get("accepted", false)) and _cost_avoids_reserved_resources(option.get("cost", {}), age_cost):
				return true
	return false


static func _cost_avoids_reserved_resources(option_cost: Dictionary, age_cost: Dictionary) -> bool:
	if option_cost.is_empty():
		return false
	var reserved_types: Dictionary = {}
	for resource_type_value in age_cost.keys():
		if int(age_cost.get(resource_type_value, 0)) > 0:
			reserved_types[int(resource_type_value)] = true
	for resource_type_value in option_cost.keys():
		if int(option_cost.get(resource_type_value, 0)) > 0 and reserved_types.has(int(resource_type_value)):
			return false
	return true


static func _navigation_failure_rank(entity: Dictionary) -> int:
	var reason := String(entity.get("diagnostic_reason", ""))
	return 1 if reason in ["no_path", "local_blocked"] or reason.begins_with("stuck_") else 0


static func _age_advance_intent(buildings: Array, player_state: Dictionary, policy: Dictionary, worker_count: int, tick: int) -> Dictionary:
	var minimum_workers := int(policy.get("minimum_workers_before_age_up", 0))
	if minimum_workers <= 0 or worker_count < minimum_workers:
		return {}
	var current_age := int(player_state.get("age", 100))
	var age_ids: Array = policy.get("age_advance_technology_ids", []).duplicate()
	age_ids.sort()
	var target_technology_id := -1
	for value in age_ids:
		var technology_id := int(value)
		if technology_id > current_age:
			target_technology_id = technology_id
			break
	if target_technology_id < 0:
		return {}
	for building_value in buildings:
		var building: Dictionary = building_value
		if not building.get("production_queue", []).is_empty():
			continue
		for option_value in building.get("command_options", {}).get("research", []):
			var option: Dictionary = option_value
			if int(option.get("technology_id", -1)) != target_technology_id:
				continue
			if bool(option.get("accepted", false)):
				return {"command": Commands.ResearchCommand.new(tick, [int(building.get("id", -1))], String.num_int64(target_technology_id)), "saving": false}
			var reason := String(option.get("reason", ""))
			if reason in ["insufficient_resources", "missing_prerequisites"]:
				return {"saving": true, "block_construction": reason == "insufficient_resources", "technology_id": target_technology_id, "cost": option.get("cost", {}).duplicate(true)}
	return {}


static func _site_preserves_structure_gap(site: Vector2, kind: String, worker: Dictionary, structures: Array, minimum_gap: float) -> bool:
	if minimum_gap <= 0.0:
		return true
	var new_radius := 1.0
	for option_value in worker.get("command_options", {}).get("build", []):
		var option: Dictionary = option_value
		if String(option.get("kind", "")) == kind:
			new_radius = maxf(0.5, float(option.get("footprint_radius", 1.0)))
			break
	for building_value in structures:
		var building: Dictionary = building_value
		var existing_radius := maxf(0.5, float(building.get("footprint_radius", 1.0)))
		var clearance := new_radius + existing_radius + minimum_gap
		if site.distance_squared_to(Vector2(building.get("pos", Vector2.ZERO))) < clearance * clearance:
			return false
	return true


static func _sort_build_kinds(kinds: Array, priorities: Array) -> void:
	var order: Dictionary = {}
	for index in range(priorities.size()):
		order[String(priorities[index])] = index
	kinds.sort_custom(func(left, right):
		var left_id := String(left)
		var right_id := String(right)
		var left_order := int(order.get(left_id, 1000000))
		var right_order := int(order.get(right_id, 1000000))
		return left_order < right_order if left_order != right_order else left_id < right_id
	)


static func _active_order_population_points(buildings: Array) -> int:
	var points := 0
	for building_value in buildings:
		var queue: Array = building_value.get("production_queue", [])
		if queue.is_empty() or String(queue[0].get("order_type", "unit")) != "unit":
			continue
		points += maxi(0, int(queue[0].get("population_points_cost", int(queue[0].get("population_cost", 0)) * 2)))
	return points


static func _needs_housing(player_state: Dictionary, buffer: int, blocked_population: bool = false, active_order_points: int = 0) -> bool:
	if player_state.has("population_limit") and int(player_state.get("population_cap", 0)) >= int(player_state.get("population_limit", 0)):
		return false
	var used_points := int(player_state.get("population_points", int(player_state.get("population", 0)) * 2)) + int(player_state.get("population_reserved", 0)) * 2
	var cap_points := mini(int(player_state.get("population_cap", 0)), int(player_state.get("population_limit", 0))) * 2
	return blocked_population or cap_points - used_points <= maxi(0, buffer) * 2 + maxi(0, active_order_points)


static func _resource_allows_worker(resource: Dictionary, worker: Dictionary) -> bool:
	var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
	if allowed_domains.is_empty():
		allowed_domains = ["land"]
	return String(worker.get("movement_domain", "land")) in allowed_domains


static func _resource_previously_failed_for_worker(resource: Dictionary, worker: Dictionary, failed_targets: Dictionary = {}) -> bool:
	if failed_targets.get(int(worker.get("id", -1)), {}).has(int(resource.get("id", -2))):
		return true
	var order: Dictionary = worker.get("components", {}).get("order", {})
	return String(order.get("type", "")) == "gather" and int(order.get("target_entity_id", -1)) == int(resource.get("id", -2)) and bool(order.get("completed", false)) and String(order.get("completion_reason", "")) in ["no_approach_slot", "no_path", "local_blocked"]


static func _reachable_cells_by_domain(navigation: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var reachable: Dictionary = navigation.get("reachable", {})
	for domain in ["land", "water"]:
		var values: Array = reachable.get(domain, [])
		if values.is_empty():
			continue
		var cells: Dictionary = {}
		for value in values:
			cells[Vector2i(Vector2(value))] = true
		result[domain] = cells
	return result


static func _resource_has_reachable_approach(resource: Dictionary, worker: Dictionary, reachable_by_domain: Dictionary) -> bool:
	var domain := String(worker.get("movement_domain", "land"))
	if not reachable_by_domain.has(domain):
		return true
	var cells: Dictionary = reachable_by_domain[domain]
	var target := Vector2i(Vector2(resource.get("pos", Vector2.ZERO)))
	for offset_y in range(-2, 3):
		for offset_x in range(-2, 3):
			if cells.has(target + Vector2i(offset_x, offset_y)):
				return true
	return false


static func _preferred_unit(options: Array, own_units: Array, building: Dictionary, snapshot: Dictionary, team: int, policy: Dictionary = {}) -> Dictionary:
	if String(building.get("kind", "")) == "dock":
		return _preferred_naval_unit(options, own_units, snapshot, team, int(policy.get("water_worker_target", 2)))
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


static func _preferred_naval_unit(options: Array, own_units: Array, snapshot: Dictionary, team: int, water_worker_target: int = 2) -> Dictionary:
	var water_workers := own_units.filter(func(entity): return bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) and String(entity.get("movement_domain", "")) == "water").size()
	var warships := own_units.filter(func(entity): return String(entity.get("movement_domain", "")) == "water" and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", []))).size()
	var reachable_water_frontier: Array = snapshot.get("navigation", {}).get("reachable_frontier", {}).get("water", [])
	# A single fishing boat can establish the naval economy. When there is still
	# unexplored reachable water, save the next wood for an armed scout instead
	# of indefinitely filling the dock queue with more fishing boats.
	if water_workers > 0 and warships == 0 and not reachable_water_frontier.is_empty():
		return _first_option_with_tag(options, "combatant")
	var water_food_known: bool = snapshot.get("resources", []).any(func(resource):
		return int(resource.get("amount", 0)) > 0 and 0 == int(resource.get("resource_type_id", 0)) and "water" in resource.get("allowed_gatherer_domains", [])
	)
	if water_worker_target > 0 and water_workers < water_worker_target and water_food_known:
		var fishing := _first_option_with_tag(options, "worker")
		if not fishing.is_empty():
			return fishing
	var traders := own_units.filter(func(entity): return bool(entity.get("components", {}).get("trade", {}).get("enabled", false))).size()
	var foreign_dock_known: bool = snapshot.get("buildings", []).any(func(entity): return int(entity.get("team", 0)) > 0 and int(entity.get("team", 0)) != team and entity.has("trade"))
	if traders < 1 and foreign_dock_known:
		var trader := _first_option_with_tag(options, "trader")
		if not trader.is_empty():
			return trader
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
	return {}


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
