extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
const Common := preload("res://scripts/ai_economy_common.gd")

static func producer_rank(kind: String, policy: Dictionary, workers: int) -> int:
	if kind == "town_center": return 0 if (not bool(policy.get("defending", false)) and not bool(policy.get("army_priority", false))) or workers < 6 else 2
	return 1 if kind == String(policy.get("primary_producer", "barracks")) else 3


static func preferred_train(
	options: Array, units: Array, snapshot: Dictionary, policy: Dictionary, state, producer_kind: String
) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	var enemies: Array = state.enemies(int(snapshot.get("tick", 0)), policy, true).slice(
		0, int(policy.get("combat_sample_budget", 32))
	)
	for option in options:
		var kind := String(option.get("kind", ""))
		var tags: Array = option.get("behavior_tags", [])
		var count := units.filter(func(u): return String(u.get("kind", "")) == kind).size()
		var score := -INF
		if "worker" in tags:
			var water := kind == "fishing_boat"
			var target := int(policy.get("water_worker_target" if water else "land_worker_target", 8))
			if not water and bool(policy.get("saving_age", false)):
				target = mini(target, int(policy.get("minimum_workers_before_age_up", 6)))
			if bool(policy.get("defending", false)) and Common.army_count(units) < int(policy.get("minimum_attack_group_size", 3)) and not water:
				target = mini(target, int(policy.get("minimum_workers_before_age_up", 6)))
			if count < target:
				score = 100.0 + float(target - count) * 2.0
		elif "transport" in tags or bool(option.get("ai_profile", {}).get("transport", false)):
			if (
				count < 1
				and String(state.goal.get("type", "")) == "attack"
				and bool(state.goal.get("needs_transport", false))
			):
				score = 90.0
		elif "trader" in tags:
			if (
				count < 1
				and snapshot.get("buildings", []).any(
					func(b): return ( String(b.get("kind", "")) == "dock" and int(b.get("team", 0)) != int(snapshot.get("observer_team", 0)) and not bool(b.get("last_known", false)) )
				)
			):
				score = 20.0
		elif "healer" in tags or "converter" in tags or kind == "priest":
			var army_size := (
				units
				. filter(
					func(u): return "combatant" in u.get("behavior_tags", []) or bool(u.get("combat_enabled", false))
				)
				. size()
			)
			if count < mini(5, maxi(1, army_size / 10)):
				score = 45.0 + float(army_size) * 0.5
		elif "combatant" in tags or bool(option.get("ai_profile", {}).get("enabled", false)):
			var army_target := int(policy.get("army_target", 9999))
			if bool(policy.get("saving_age", false)): army_target = mini(army_target, int(policy.get("minimum_attack_group_size", 3)))
			if Common.army_count(units) >= army_target: continue
			var candidate := {
				"kind": kind,
				"hp": option.get("ai_profile", {}).get("max_hp", 1.0),
				"ai_profile": option.get("ai_profile", {}),
				"combat_enabled": true
			}
			var total_cost := 0.0
			for value in option.get("cost", {}).values():
				total_cost += maxf(0.0, float(value))
			score = Combat.counter_score(candidate, enemies, units) * 200.0 / maxf(30.0, total_cost)
			if String(state.goal.get("type", "")) == "defend":
				score *= 2.0
			if producer_kind == "dock" and count < int(policy.get("minimum_naval_escort", 2)):
				score += 40.0
			if enemies.is_empty() and count == 0:
				score += (
					float(option.get("ai_profile", {}).get("speed", 0.0)) * float(policy.get("scout_priority", 4.0))
				)
		if score > best_score:
			best = option.duplicate()
			best["ai_score"] = score
			best_score = score
	return best


static func preferred_research(options: Array, units: Array, policy: Dictionary, state) -> Dictionary:
	var best: Dictionary = {}
	var score := 0.0
	for option in options:
		if (
			not bool(option.get("accepted", false))
			or int(option.get("technology_id", -1)) in policy.get("age_advance_technology_ids", [])
		):
			continue
		var relevance := float(option.get("ai_relevance", 0.0))
		if bool(option.get("ai_economic", false)):
			relevance *= float(policy.get("economic_research_priority", 1.4))
		if String(state.goal.get("type", "")) == "defend" and not bool(option.get("ai_economic", false)):
			relevance *= 1.5
		var total_cost := 0.0
		for value in option.get("cost", {}).values():
			total_cost += maxf(0.0, float(value))
		var candidate_score := relevance * 100.0 / maxf(50.0, total_cost)
		if candidate_score > score:
			best = option.duplicate()
			best["ai_score"] = candidate_score
			score = candidate_score
	return best


static func age_intent(
	buildings: Array, player: Dictionary, policy: Dictionary, workers: int, tick: int
) -> Dictionary:
	if workers < int(policy.get("minimum_workers_before_age_up", 6)):
		return {}
	var ids: Array = policy.get("age_advance_technology_ids", []).duplicate()
	ids.sort()
	var target := -1
	for id in ids:
		if int(id) > int(player.get("age", 100)):
			target = int(id)
			break
	if target < 0:
		return {}
	for building in buildings:
		if building.get("production_queue", []).any(func(o): return String(o.get("order_type", "")) == "research"):
			continue
		for option in building.get("command_options", {}).get("research", []):
			if int(option.get("technology_id", -1)) != target:
				continue
			if bool(option.get("accepted", false)):
				return {
					"command": Commands.ResearchCommand.new(tick, [int(building["id"])], String.num_int64(target)),
					"cost": option.get("cost", {}),
					"saving": false
				}
			if String(option.get("reason", "")) in ["insufficient_resources", "missing_prerequisites"]:
				return {
					"saving": true,
					"block_construction": String(option["reason"]) == "insufficient_resources",
					"cost": option.get("cost", {}).duplicate(true)
				}
	return {}


static func plan_production(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, budget, reserved: Dictionary, result: Array, units: Array, buildings: Array, workers: Array, memoized_production_enabled: bool) -> void:
	var effective_units: Array = units.duplicate()
	var production_choices: Dictionary = {}
	var effective_version := 0
	for building in buildings:
		for order in building.get("production_queue", []):
			if String(order.get("order_type", "unit")) == "unit":
				var option: Dictionary = {}
				for candidate in building.get("command_options", {}).get("train", []):
					if candidate.get("kind") == order.get("kind"): option = candidate
				effective_units.append({"kind": order.get("kind", ""), "behavior_tags": option.get("behavior_tags", ["worker"] if String(order.get("kind", "")) in ["villager", "fishing_boat"] else ["combatant"]), "ai_profile": option.get("ai_profile", {})})
	buildings.sort_custom(func(a, b):
		var a_rank := producer_rank(String(a.get("kind", "")), policy, workers.size())
		var b_rank := producer_rank(String(b.get("kind", "")), policy, workers.size())
		return a_rank < b_rank if a_rank != b_rank else int(a["id"]) < int(b["id"]))
	for building in buildings:
		var id := int(building.get("id", -1))
		var queue: Array = building.get("production_queue", [])
		if budget.producer_orders.has(id) or queue.size() >= int(policy.get("maximum_production_queue", 2)) or queue.any(func(o): return String(o.get("order_type", "unit")) != "unit" or String(o.get("status", "")) == "blocked_population"):
			continue
		var options: Dictionary = building.get("command_options", {})
		var essential_worker := workers.size() < int(policy["minimum_workers_before_age_up"])
		var train_options: Array = options.get("train", []).filter(func(o): return bool(o.get("accepted", false)) and budget.can_reserve(o.get("cost", {}), int(o.get("population_points_cost", int(o.get("population_cost", 1)) * 2)), id, essential_worker and "worker" in o.get("behavior_tags", [])))
		var producer_kind := String(building.get("kind", ""))
		# A plan sees one fixed enemy sample and policy. Unit counts change only
		# when an accepted offer extends effective_units below.
		var choice_key := [producer_kind, effective_version, train_options]
		var selected: Dictionary
		if memoized_production_enabled and production_choices.has(choice_key):
			selected = production_choices[choice_key]
		else:
			selected = preferred_train(train_options, effective_units, snapshot, policy, state, producer_kind)
			if memoized_production_enabled: production_choices[choice_key] = selected
		var technology := preferred_research(options.get("research", []).filter(func(o): return budget.can_reserve(o.get("cost", {}), 0, id)), units, policy, state)
		var worker_option: bool = "worker" in selected.get("behavior_tags", [])
		if (
			not technology.is_empty()
			and not worker_option
			and building.get("production_queue", []).is_empty()
			and (
				selected.is_empty()
				or (
					float(technology.get("ai_score", 0.0))
					> float(selected.get("ai_score", 0.0)) * float(policy.get("research_priority", 1.1))
				)
			)
		):
			Common.offer(
				result,
				Commands.ResearchCommand.new(tick, [id], String.num_int64(int(technology["technology_id"]))),
				technology.get("cost", {}),
				0,
				id,
				false,
				state,
				budget,
				reserved
			)
		elif not selected.is_empty():
			var essential: bool = (
				worker_option
				and (
					essential_worker
					or workers.size() < int(policy["land_worker_target"]) / 2
				)
			)
			if Common.offer(
				result,
				Commands.TrainCommand.new(
					tick,
					[id],
					String(selected["kind"]),
					team,
					Vector2(building.get("rally_point", building.get("pos", Vector2.ZERO)))
				),
				selected.get("cost", {}),
				int(selected.get("population_points_cost", int(selected.get("population_cost", 1)) * 2)),
				id,
				essential,
				state,
				budget,
				reserved
			):
				effective_units.append({"kind": selected["kind"], "behavior_tags": selected.get("behavior_tags", [])})
				effective_version += 1
