class_name RoRAiStrategyState
extends RefCounted
const Combat := preload("res://scripts/ai_combat_model.gd")
const Strategic := preload("res://scripts/ai_strategic_planner.gd")
const RESOURCE_NAMES := ["food", "wood", "stone", "gold"]
const VERSION := 1
var memory: Dictionary = {}
var goal: Dictionary = {}
var samples: Array = []
var income: Dictionary = {}
var spent: Dictionary = {}
var pending: Array = []
var cooldowns: Dictionary = {}
var metrics: Dictionary = {
	"decisions": 0,
	"commands_accepted": 0,
	"commands_rejected": 0,
	"budget_rejections": 0,
	"idle_worker_ticks": 0,
	"worker_ticks": 0,
	"losses": 0,
	"age_ticks": {},
	"rejection_reasons": {}
}
var gather_cursor := 0
var scout_visits: Dictionary = {}
var expeditions: Dictionary = {}
var previous_owned: Array = []
var last_observation_tick := -1
var _threat_tick := -1
var _threats: Array = []


static func enemy(entity: Dictionary, snapshot: Dictionary, team: int) -> bool:
	var owner := int(entity.get("team", 0))
	var player: Dictionary = snapshot.get("player_state", {})
	return (
		owner > 0
		and owner != team
		and (
			String(player.get("relations", {}).get(owner, "ally" if owner in player.get("allies", [team]) else "enemy"))
			== "enemy"
		)
	)


func observe(snapshot: Dictionary, team: int, policy: Dictionary) -> void:
	var tick := int(snapshot.get("tick", 0))
	var lifetime := maxi(20, int(policy.get("memory_ticks", 1200)))
	var seen: Dictionary = {}
	var owned: Array = []
	var visible_locations: Dictionary = snapshot.get("ai_visible_memory_locations", {})
	var workers := 0
	var idle := 0
	for category in ["units", "buildings"]:
		for entity in snapshot.get(category, []):
			var id := int(entity.get("id", -1))
			if int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0:
				if category == "units":
					owned.append(id)
					for passenger in entity.get("components", {}).get("cargo", {}).get("passenger_ids", []):
						owned.append(int(passenger))
					if bool(entity.get("components", {}).get("worker", {}).get("enabled", false)):
						workers += 1
						if String(entity.get("task", "idle")) == "idle":
							idle += 1
				continue
			if not enemy(entity, snapshot, team):
				continue
			seen[id] = true
			if float(entity.get("hp", 0.0)) <= 0.0 and not bool(entity.get("health_unknown", false)):
				memory.erase(id)
				continue
			# A fog memory row never refreshes its timestamp or hidden health.
			if bool(entity.get("last_known", false)):
				if not memory.has(id):
					memory[id] = {
						"entity": entity.duplicate(true), "seen_tick": maxi(0, tick - lifetime / 2), "observed": false
					}
			else:
				memory[id] = {"entity": entity.duplicate(true), "seen_tick": tick, "observed": true}
	for id in memory.keys():
		var entry: Dictionary = memory[id]
		entry["observed"] = seen.has(id) and int(entry["seen_tick"]) == tick
		if (
			tick - int(entry["seen_tick"]) > lifetime
			or not enemy(entry["entity"], snapshot, team)
			or (visible_locations.has(int(id)) and not seen.has(id))
		):
			memory.erase(id)
	var ordered: Array = memory.keys()
	ordered.sort_custom(
		func(a, b):
			var at := int(memory[a]["seen_tick"])
			var bt := int(memory[b]["seen_tick"])
			return at > bt if at != bt else int(a) < int(b)
	)
	for id in ordered.slice(maxi(1, int(policy.get("maximum_enemy_memory", 256)))):
		memory.erase(id)
	owned.sort()
	if last_observation_tick >= 0 and tick > last_observation_tick:
		metrics["worker_ticks"] += workers * (tick - last_observation_tick)
		metrics["idle_worker_ticks"] += idle * (tick - last_observation_tick)
		for id in previous_owned:
			if id not in owned:
				metrics["losses"] += 1
	previous_owned = owned
	last_observation_tick = tick
	var player: Dictionary = snapshot.get("player_state", {})
	var age := int(player.get("age", 100))
	if not metrics["age_ticks"].has(age):
		metrics["age_ticks"][age] = tick
	var gross: Dictionary = {}
	for type_id in range(RESOURCE_NAMES.size()):
		gross[type_id] = float(player.get(RESOURCE_NAMES[type_id], 0)) + float(spent.get(type_id, 0))
	if samples.is_empty() or tick > int(samples.back()["tick"]):
		samples.append({"tick": tick, "gross": gross})
	while samples.size() > 2 and tick - int(samples[1]["tick"]) > 600:
		samples.pop_front()
	while samples.size() > 64:
		samples.pop_front()
	if samples.size() >= 2:
		var first: Dictionary = samples.front()
		var elapsed := maxf(0.05, float(tick - int(first["tick"])) / 20.0)
		for type_id in range(RESOURCE_NAMES.size()):
			income[type_id] = maxf(0.0, (float(gross[type_id]) - float(first["gross"].get(type_id, 0))) / elapsed)
	for key in cooldowns.keys():
		if int(cooldowns[key]) <= tick:
			cooldowns.erase(key)
	metrics["decisions"] += 1
	_threat_tick = -1


func enemies(tick: int, policy: Dictionary, observed_only: bool = false) -> Array:
	var result: Array = []
	var ids: Array = memory.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = memory[id]
		if observed_only and not bool(entry["observed"]):
			continue
		var actor: Dictionary = entry["entity"].duplicate()
		actor["confidence"] = (
			1.0
			if bool(entry["observed"])
			else maxf(
				0.0, 1.0 - float(tick - int(entry["seen_tick"])) / float(maxi(1, int(policy.get("memory_ticks", 1200))))
			)
		)
		actor["observed"] = bool(entry["observed"])
		result.append(actor)
	return result


func danger(position: Vector2, tick: int, policy: Dictionary, domain: String = "land") -> float:
	var total := 0.0
	if _threat_tick != tick:
		_threats = enemies(tick, policy)
		_threat_tick = tick
	for actor in _threats:
		var data := Combat.profile(actor)
		if not bool(data.get("enabled", actor.get("combat_enabled", false))):
			continue
		var targets: Array = actor.get("target_domains", ["land", "water"])
		if domain not in targets:
			continue
		var distance := position.distance_to(Vector2(actor.get("pos", Vector2.ZERO)))
		var radius := 6.0 + float(data.get("range", 0.0))
		if distance < radius:
			total += Combat.strength([actor]) * float(actor.get("confidence", 1.0)) * (1.0 - distance / radius)
	return total


func choose_goal(snapshot: Dictionary, team: int, policy: Dictionary, decision: int) -> Dictionary:
	var tick := int(snapshot.get("tick", 0))
	var homes: Array = snapshot.get("buildings", []).filter(
		func(e): return int(e.get("team", 0)) == team and float(e.get("hp", 0.0)) > 0.0
	)
	if homes.is_empty():
		homes = snapshot.get("units", []).filter(func(e): return int(e.get("team", 0)) == team)
	var home := Vector2(snapshot.get("map_size", Vector2i(24, 24))) * 0.5
	if not homes.is_empty():
		home = Vector2(homes[0].get("pos", home))
	var best: Dictionary = {}
	var best_score := -INF
	var domain_goals: Dictionary = {}
	var domain_scores: Dictionary = {}
	for actor in enemies(tick, policy):
		var position := Vector2(actor.get("pos", Vector2.ZERO))
		var distance := home.distance_to(position)
		for base in homes:
			distance = minf(distance, Vector2(base.get("pos", home)).distance_to(position))
		var defence := (
			bool(actor.get("observed", false))
			and bool(Combat.profile(actor).get("enabled", actor.get("combat_enabled", false)))
			and distance <= float(policy.get("enemy_response_distance", 22.0))
		)
		var value := 20.0
		if String(actor.get("kind", "")) == "town_center":
			value = 70.0
		elif String(actor.get("entity_type", "")) == "building":
			value = 40.0
		elif bool(actor.get("components", {}).get("worker", {}).get("enabled", false)):
			value = 35.0
		var score := (
			(value + (120.0 if defence else 0.0)) * float(actor["confidence"])
			- home.distance_to(position) * 0.45
			- danger(position, tick, policy) * 0.3
		)
		if int(actor.get("id", -1)) == int(goal.get("target_id", -2)):
			score += float(policy.get("goal_inertia", 18.0))
		var domain := String(actor.get("movement_domain", "land"))
		if domain == "static":
			domain = "land"
		var candidate := {
			"type": "defend" if defence else "attack",
			"target_id": int(actor["id"]),
			"position": position,
			"target_domain": domain,
			"target_radius": float(actor.get("footprint_radius", 1.0)),
			"observed": bool(actor["observed"]),
			"home": home,
			"adaptive_strategy": true
		}
		if score > float(domain_scores.get(domain, -INF)):
			domain_scores[domain] = score
			domain_goals[domain] = candidate
		if score > best_score:
			# The primary goal must not alias a value stored in its domain map.
			best = candidate.duplicate()
			best_score = score
	if best.is_empty():
		best = Strategic.choose_goal(snapshot, team, decision)
		best["home"] = home
		best["adaptive_strategy"] = true
	best["goals_by_domain"] = domain_goals
	if String(best.get("target_domain", "land")) == "land" and String(best.get("type", "")) == "attack":
		var position := Vector2(best.get("position", home))
		var reachable: Array = snapshot.get("navigation", {}).get("reachable", {}).get("land", [])
		best["needs_transport"] = not reachable.any(
			func(p): return Vector2(p).distance_to(position) <= 2.0 + float(best.get("target_radius", 1.0))
		)
	goal = best
	return goal.duplicate(true)


func register(command, metadata: Dictionary) -> void:
	if int(command.sequence_id) <= 0:
		return
	pending.append(
		{
			"sequence": int(command.sequence_id),
			"issuer": int(command.issuer_id),
			"tick": int(command.tick),
			"type": String(command.command_type()),
			"ids": command.unit_ids.duplicate(),
			"metadata": metadata.duplicate(true)
		}
	)


func feedback(controller, team: int, tick: int, policy: Dictionary) -> void:
	var retained: Array = []
	for entry in pending:
		var result: Dictionary = controller.get_command_result(int(entry["sequence"]))
		if result.is_empty():
			if tick <= int(entry["tick"]) + 200:
				retained.append(entry)
			else:
				metrics["feedback_expired"] = int(metrics.get("feedback_expired", 0)) + 1
			continue
		if int(result.get("issuer_id", -1)) != team or int(result.get("sequence_id", -1)) != int(entry["sequence"]):
			continue
		var accepted := bool(result.get("accepted", false))
		var key := "commands_accepted" if accepted else "commands_rejected"
		metrics[key] += 1
		if accepted:
			for resource in entry["metadata"].get("cost", {}):
				spent[int(resource)] = int(spent.get(int(resource), 0)) + int(entry["metadata"]["cost"][resource])
		else:
			var reason := String(result.get("reason", "unknown"))
			metrics["rejection_reasons"][reason] = int(metrics["rejection_reasons"].get(reason, 0)) + 1
			cooldowns[String(entry["metadata"].get("key", ""))] = (
				tick + maxi(1, int(policy.get("command_retry_ticks", 60)))
			)
	pending = retained


func canonical_state() -> Dictionary:
	var records: Array = []
	var ids: Array = memory.keys()
	ids.sort()
	for id in ids:
		records.append({"id": int(id), "value": memory[id].duplicate(true)})
	return {
		"version": VERSION,
		"memory": records,
		"goal": goal.duplicate(true),
		"samples": samples.duplicate(true),
		"income": income.duplicate(true),
		"spent": spent.duplicate(true),
		"pending": pending.duplicate(true),
		"cooldowns": cooldowns.duplicate(true),
		"metrics": metrics.duplicate(true),
		"gather_cursor": gather_cursor,
		"scout_visits": scout_visits.duplicate(true),
		"expeditions": expeditions.duplicate(true),
		"previous_owned": previous_owned.duplicate(),
		"last_observation_tick": last_observation_tick
	}


func restore_state(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION:
		return false
	for field in ["memory", "samples", "pending", "previous_owned"]:
		if not data.get(field, []) is Array:
			return false
	for field in ["goal", "income", "spent", "cooldowns", "metrics", "scout_visits", "expeditions"]:
		if not data.get(field, {}) is Dictionary:
			return false
	_threat_tick = -1
	_threats.clear()
	if (
		data.get("memory", []).size() > 1024
		or data.get("samples", []).size() > 64
		or data.get("pending", []).size() > 1024
	):
		return false
	for sample in data.get("samples", []):
		if not sample is Dictionary or not sample.get("gross") is Dictionary or int(sample.get("tick", -1)) < 0:
			return false
	for entry in data.get("pending", []):
		if (
			not entry is Dictionary
			or not entry.get("metadata") is Dictionary
			or not entry.get("ids") is Array
			or int(entry.get("sequence", -1)) <= 0
			or int(entry.get("issuer", -1)) <= 0
		):
			return false
	var saved_metrics: Dictionary = data.get("metrics", {})
	for field in [
		"decisions",
		"commands_accepted",
		"commands_rejected",
		"budget_rejections",
		"idle_worker_ticks",
		"worker_ticks",
		"losses"
	]:
		if not saved_metrics.has(field) or int(saved_metrics[field]) < 0:
			return false
	if not saved_metrics.get("age_ticks") is Dictionary or not saved_metrics.get("rejection_reasons") is Dictionary:
		return false
	memory.clear()
	for entry in data.get("memory", []):
		if (
			not entry is Dictionary
			or not entry.get("value") is Dictionary
			or not entry["value"].get("entity") is Dictionary
			or int(entry.get("id", -1)) < 0
			or memory.has(int(entry["id"]))
		):
			return false
		memory[int(entry["id"])] = entry["value"].duplicate(true)
	goal = data.get("goal", {}).duplicate(true)
	samples = data.get("samples", []).duplicate(true)
	income = data.get("income", {}).duplicate(true)
	spent = data.get("spent", {}).duplicate(true)
	pending = data.get("pending", []).duplicate(true)
	cooldowns = data.get("cooldowns", {}).duplicate(true)
	metrics = data.get("metrics", metrics).duplicate(true)
	gather_cursor = maxi(0, int(data.get("gather_cursor", 0)))
	scout_visits = data.get("scout_visits", {}).duplicate(true)
	expeditions = data.get("expeditions", {}).duplicate(true)
	previous_owned = data.get("previous_owned", []).duplicate()
	last_observation_tick = int(data.get("last_observation_tick", -1))
	return true
