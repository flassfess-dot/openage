extends RefCounted

# Shared deterministic predicates and ranking rules for both economy planners.
const Commands := preload("res://scripts/commands.gd")


static func navigation_failure_rank(entity: Dictionary) -> int:
	var reason := String(entity.get("diagnostic_reason", ""))
	return 1 if reason in ["no_path", "local_blocked"] or reason.begins_with("stuck_") else 0


static func gather_assignment_precedes(left: Dictionary, right: Dictionary) -> bool:
	if int(left["shortage"]) != int(right["shortage"]):
		return int(left["shortage"]) > int(right["shortage"])
	if bool(left["active_gatherer"]) != bool(right["active_gatherer"]):
		return not bool(left["active_gatherer"])
	var left_failure := navigation_failure_rank(left["worker"])
	var right_failure := navigation_failure_rank(right["worker"])
	if left_failure != right_failure:
		return left_failure < right_failure
	if not is_equal_approx(float(left["distance"]), float(right["distance"])):
		return float(left["distance"]) < float(right["distance"])
	if int(left["worker"].get("id", -1)) != int(right["worker"].get("id", -1)):
		return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
	return int(left["resource"].get("id", -1)) < int(right["resource"].get("id", -1))


static func build_site_candidate_precedes(left: Dictionary, right: Dictionary) -> bool:
	if bool(left["preserves_gap"]) != bool(right["preserves_gap"]):
		return bool(left["preserves_gap"])
	var left_idle := 0 if String(left["worker"].get("task", "idle")) == "idle" else 1
	var right_idle := 0 if String(right["worker"].get("task", "idle")) == "idle" else 1
	if left_idle != right_idle:
		return left_idle < right_idle
	var left_failure := navigation_failure_rank(left["worker"])
	var right_failure := navigation_failure_rank(right["worker"])
	if left_failure != right_failure:
		return left_failure < right_failure
	if not is_equal_approx(float(left["distance"]), float(right["distance"])):
		return float(left["distance"]) < float(right["distance"])
	return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))


static func foundation_builder_precedes(left: Dictionary, right: Dictionary, foundation: Dictionary) -> bool:
	var left_stuck := 1 if String(left.get("diagnostic_reason", "")).begins_with("stuck_") else 0
	var right_stuck := 1 if String(right.get("diagnostic_reason", "")).begins_with("stuck_") else 0
	if left_stuck != right_stuck:
		return left_stuck < right_stuck
	var left_idle := 0 if String(left.get("task", "idle")) == "idle" else 1
	var right_idle := 0 if String(right.get("task", "idle")) == "idle" else 1
	if left_idle != right_idle:
		return left_idle < right_idle
	var foundation_position := Vector2(foundation.get("pos", Vector2.ZERO))
	var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(foundation_position)
	var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(foundation_position)
	return left_distance < right_distance if not is_equal_approx(left_distance, right_distance) else int(left.get("id", -1)) < int(right.get("id", -1))


static func id_lookup(entity_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for entity_id_value in entity_ids:
		result[int(entity_id_value)] = true
	return result


static func site_preserves_structure_gap(site: Vector2, kind: String, worker: Dictionary, structures: Array, minimum_gap: float) -> bool:
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


static func sort_build_kinds(kinds: Array, priorities: Array) -> void:
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


static func active_order_population_points(buildings: Array) -> int:
	var points := 0
	for building_value in buildings:
		var queue: Array = building_value.get("production_queue", [])
		if queue.is_empty() or String(queue[0].get("order_type", "unit")) != "unit":
			continue
		points += maxi(0, int(queue[0].get("population_points_cost", int(queue[0].get("population_cost", 0)) * 2)))
	return points


static func needs_housing(player_state: Dictionary, buffer: int, blocked_population: bool = false, active_order_points: int = 0) -> bool:
	if player_state.has("population_limit") and int(player_state.get("population_cap", 0)) >= int(player_state.get("population_limit", 0)):
		return false
	var used_points := int(player_state.get("population_points", int(player_state.get("population", 0)) * 2)) + int(player_state.get("population_reserved", 0)) * 2
	var cap_points := mini(int(player_state.get("population_cap", 0)), int(player_state.get("population_limit", 0))) * 2
	return blocked_population or cap_points - used_points <= maxi(0, buffer) * 2 + maxi(0, active_order_points)


static func resource_allows_worker(resource: Dictionary, worker: Dictionary) -> bool:
	var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
	if allowed_domains.is_empty():
		allowed_domains = ["land"]
	return String(worker.get("movement_domain", "land")) in allowed_domains


static func resource_previously_failed_for_worker(resource: Dictionary, worker: Dictionary, failed_targets: Dictionary = {}) -> bool:
	if failed_targets.get(int(worker.get("id", -1)), {}).has(int(resource.get("id", -2))):
		return true
	var order: Dictionary = worker.get("components", {}).get("order", {})
	return String(order.get("type", "")) == "gather" and int(order.get("target_entity_id", -1)) == int(resource.get("id", -2)) and bool(order.get("completed", false)) and String(order.get("completion_reason", "")) in ["no_approach_slot", "no_path", "local_blocked"]


static func resource_has_reachable_approach(resource: Dictionary, worker: Dictionary, reachable_by_domain: Dictionary) -> bool:
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


static func plan_idle_trade(snapshot: Dictionary, tick: int, team: int, own_units: Array, own_buildings: Array) -> Array:
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


static func reachable_cells_by_domain(navigation: Dictionary, native_enabled: bool = true) -> Dictionary:
	if native_enabled and ClassDB.class_exists("RoRReadModelKernel"):
		var kernel = ClassDB.instantiate("RoRReadModelKernel")
		if kernel.has_method("reachable_cell_lookup"):
			return kernel.reachable_cell_lookup(navigation)
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
