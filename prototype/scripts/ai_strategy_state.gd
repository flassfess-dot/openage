class_name RoRAiStrategyState
extends RefCounted
const Combat := preload("res://scripts/ai_combat_model.gd")
const Strategic := preload("res://scripts/ai_strategic_planner.gd")
const Belief := preload("res://scripts/ai_belief_model.gd")
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
var _threat_buckets: Dictionary = {}
var _threat_radius := 8.0
var belief_regions: Dictionary = {}


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


static func wildlife_threat(entity: Dictionary) -> bool:
	return int(entity.get("team", 0)) == 0 and "predator" in entity.get("behavior_tags", [])


func observe(snapshot: Dictionary, team: int, policy: Dictionary) -> void:
	var tick := int(snapshot.get("tick", 0))
	var lifetime := maxi(20, int(policy.get("memory_ticks", 1200)))
	var seen: Dictionary = {}
	var owned: Array = []
	if bool(policy.get("competitive",false)): owned.append_array(snapshot.get("player_state",{}).get("embarked_owned_ids",[]))
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
			if not enemy(entity, snapshot, team) and not wildlife_threat(entity):
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
		var negative: bool=visible_locations.has(int(id)) and not seen.has(id)
		if negative and bool(policy.get("competitive",false)) and not Belief.permanent(entry["entity"]):
			# An empty former position disproves a building, but a mobile unit
			# may have left. Neither its age nor its health is refreshed here.
			entry["origin_disproved"]=true
			entry["origin_disproved_tick"]=tick
			negative=false
		if (
			(tick - int(entry["seen_tick"]) > lifetime and not (bool(policy.get("competitive",false)) and Belief.permanent(entry["entity"])))
			or (not enemy(entry["entity"], snapshot, team) and not wildlife_threat(entry["entity"]))
			or negative
		):
			memory.erase(id)
	var ordered: Array = memory.keys()
	ordered.sort_custom(
		func(a, b):
			if bool(policy.get("competitive",false)):
				var av := Belief.importance(memory[a],tick)
				var bv := Belief.importance(memory[b],tick)
				if not is_equal_approx(av,bv): return av > bv
			var at := int(memory[a]["seen_tick"])
			var bt := int(memory[b]["seen_tick"])
			return at > bt if at != bt else int(a) < int(b)
	)
	var evicted: Array=[]
	for id in ordered.slice(maxi(1, int(policy.get("maximum_enemy_memory", 256)))):
		if bool(policy.get("competitive",false)): evicted.append(memory[id])
		memory.erase(id)
	if bool(policy.get("competitive",false)):
		var grouped: Dictionary={}
		for entry in evicted:
			var actor: Dictionary=entry["entity"]
			var key:=str([int(actor.get("team",0)),String(actor.get("kind","")),Vector2i(Vector2(actor.get("pos",Vector2.ZERO))/16.0)])
			if not grouped.has(key): grouped[key]={"count":0,"entry":entry.duplicate(true)}
			grouped[key]["count"]+=1
		for key in grouped:
			var record: Dictionary=grouped[key]
			record["entry"]["observed"]=false
			record["entry"].erase("route_area")
			if int(record["entry"].get("seen_tick",0))>=int(belief_regions.get(key,{}).get("entry",{}).get("seen_tick",-1)): belief_regions[key]=record
		for key in belief_regions.keys():
			var entry: Dictionary=belief_regions[key]["entry"]
			var id:=int(entry.get("entity",{}).get("id",-1))
			if (tick-int(entry.get("seen_tick",0))>lifetime and not Belief.permanent(entry.get("entity",{}))) or (visible_locations.has(id) and not seen.has(id) and Belief.permanent(entry.get("entity",{}))): belief_regions.erase(key)
		var region_keys: Array=belief_regions.keys()
		region_keys.sort_custom(func(a,b): return int(belief_regions[a]["entry"].get("seen_tick",0))>int(belief_regions[b]["entry"].get("seen_tick",0)) if int(belief_regions[a]["entry"].get("seen_tick",0))!=int(belief_regions[b]["entry"].get("seen_tick",0)) else String(a)<String(b))
		for key in region_keys.slice(256): belief_regions.erase(key)
		_refresh_route_hypotheses(snapshot,ordered,tick)
	if bool(policy.get("competitive",false)):
		var unique: Dictionary={}
		for id in owned: unique[int(id)]=true
		owned=unique.keys()
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
		if bool(policy.get("competitive",false)) and not player.get("resource_ledger",{}).is_empty():
			gross[type_id] = float(player["resource_ledger"].get("income",[0,0,0,0])[type_id])
	if samples.is_empty() or tick-int(samples.back()["tick"]) >= (20 if bool(policy.get("competitive",false)) else 1):
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


func _refresh_route_hypotheses(snapshot: Dictionary, ordered: Array, tick: int) -> void:
	var navigation: Dictionary=snapshot.get("navigation",{})
	if not bool(navigation.get("cell_geometry",false)): return
	var eligible: Array=[]
	var retained: Dictionary={}
	for id in ordered:
		if not memory.has(id): continue
		var entry: Dictionary=memory[id]
		if bool(entry.get("observed",false)) or Belief.permanent(entry["entity"]) or String(entry["entity"].get("movement_domain","land")) not in ["land","water"]: continue
		eligible.append(id)
		retained[id]=true
		if eligible.size()>=Belief.MAX_ROUTE_HYPOTHESES: break
	for id in ordered:
		if memory.has(id) and memory[id].has("route_area") and not retained.has(id): memory[id].erase("route_area")
	if eligible.is_empty(): return
	var cursor:=posmod(int(metrics.get("belief_route_cursor",0)),eligible.size())
	for index in range(mini(Belief.ROUTES_PER_OBSERVATION,eligible.size())):
		var id: int=int(eligible[(cursor+index)%eligible.size()])
		memory[id]["route_area"]=Belief.route_area(memory[id],tick,navigation)
	metrics["belief_route_cursor"]=(cursor+mini(Belief.ROUTES_PER_OBSERVATION,eligible.size()))%eligible.size()


func enemies(tick: int, policy: Dictionary, observed_only: bool = false, include_wildlife: bool = false) -> Array:
	var result: Array = []
	var ids: Array = memory.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = memory[id]
		if not include_wildlife and wildlife_threat(entry["entity"]): continue
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
		if bool(policy.get("competitive",false)):
			actor["confidence"] = Belief.confidence(entry,tick,int(policy.get("memory_ticks",1200)))
			actor["uncertainty_radius"] = Belief.uncertainty(entry,tick)
			var area: Dictionary=entry.get("route_area",{})
			if not area.is_empty() and tick>=int(area["tick"]) and tick-int(area["tick"])<=160:
				actor["route_area"]=area.duplicate(true)
				actor["route_area"]["age_ticks"]=tick-int(area["tick"])
		result.append(actor)
	if bool(policy.get("competitive",false)) and not observed_only:
		var keys: Array=belief_regions.keys(); keys.sort()
		for index in range(keys.size()):
			var record: Dictionary=belief_regions[keys[index]]; var entry: Dictionary=record["entry"]
			var actor: Dictionary=entry["entity"].duplicate(true)
			if not include_wildlife and wildlife_threat(actor): continue
			actor["id"]=-10000-index; actor["aggregate"]=true; actor["observed"]=false
			actor["confidence"]=Belief.confidence(entry,tick,int(policy.get("memory_ticks",1200)))*0.5
			actor["belief_count"]=int(record["count"])
			result.append(actor)
	return result


func danger(position: Vector2, tick: int, policy: Dictionary, domain: String = "land") -> float:
	var total := 0.0
	if _threat_tick != tick:
		_threats = enemies(tick, policy, false, true)
		_threat_tick = tick
		_threat_buckets.clear()
		_threat_radius = 8.0
		if bool(policy.get("competitive",false)):
			for index in range(_threats.size()):
				var actor: Dictionary = _threats[index]
				var cell := Vector2i((Vector2(actor.get("pos",Vector2.ZERO))/8.0).floor())
				if not _threat_buckets.has(cell): _threat_buckets[cell]=[]
				_threat_buckets[cell].append(index)
				_threat_radius=maxf(_threat_radius,6.0+float(Combat.profile(actor).get("range",0.0)))
				if wildlife_threat(actor): _threat_radius=maxf(_threat_radius,float(actor.get("acquisition_range",3.0))+2.0)
	var indices: Array = []
	if bool(policy.get("competitive",false)):
		var first := Vector2i(((position-Vector2.ONE*_threat_radius)/8.0).floor())
		var last := Vector2i(((position+Vector2.ONE*_threat_radius)/8.0).floor())
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1): indices.append_array(_threat_buckets.get(Vector2i(x,y),[]))
		indices.sort()
	else: indices.assign(range(_threats.size()))
	for index in indices:
		var actor: Dictionary = _threats[index]
		var data := Combat.profile(actor)
		if not bool(data.get("enabled", actor.get("combat_enabled", false))):
			continue
		var targets: Array = actor.get("target_domains", ["land", "water"])
		if domain not in targets:
			continue
		var distance := position.distance_to(Vector2(actor.get("pos", Vector2.ZERO)))
		if wildlife_threat(actor):
			# An observed predator is an economic hazard even though neutral
			# animals are absent from military objectives. Avoid its acquisition
			# range with two world units of warning for a working villager.
			var acquisition := maxf(0.0, float(actor.get("acquisition_range", 3.0)))
			var warning := maxf(0.0, (acquisition + 2.0 - distance) / 2.0)
			total += (float(policy.get("maximum_economic_danger", 8.0)) + 1.0) * warning * float(actor.get("confidence", 1.0))
			continue
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
	var known_enemies := enemies(tick, policy)
	if bool(policy.get("competitive",false)) and known_enemies.size()>96:
		known_enemies.sort_custom(func(a,b):
			var av := (100.0 if String(a.get("entity_type",""))=="building" else 40.0)*float(a.get("confidence",1.0))-home.distance_to(Vector2(a.get("pos",Vector2.ZERO)))
			var bv := (100.0 if String(b.get("entity_type",""))=="building" else 40.0)*float(b.get("confidence",1.0))-home.distance_to(Vector2(b.get("pos",Vector2.ZERO)))
			return av>bv if not is_equal_approx(av,bv) else int(a["id"])<int(b["id"]))
		known_enemies=known_enemies.slice(0,96)
	var forces: Dictionary = {"land": [], "water": []}
	for unit in snapshot.get("units", []):
		var domain := String(unit.get("movement_domain", "land"))
		if int(unit.get("team", 0)) == team and domain in forces and bool(unit.get("combat_enabled", false)) and not bool(unit.get("components", {}).get("worker", {}).get("enabled", false)):
			forces[domain].append(unit)
	var strengths := {"land": Combat.strength(forces["land"]), "water": Combat.strength(forces["water"])}
	var approaches: Dictionary = {}
	if bool(policy.get("competitive",false)):
		for domain in ["land","water"]:
			var cells: Dictionary = {}
			for point in snapshot.get("navigation",{}).get("reachable",{}).get(domain,[]): cells[Vector2i(Vector2(point).floor())]=Vector2(point)
			approaches[domain]=cells
	for actor in known_enemies:
		var position := Vector2(actor.get("pos", Vector2.ZERO))
		var distance := home.distance_to(position)
		for base in homes:
			distance = minf(distance, Vector2(base.get("pos", home)).distance_to(position))
		var defence := (
			bool(actor.get("observed", false))
			and bool(Combat.profile(actor).get("enabled", actor.get("combat_enabled", false)))
			and distance <= minf(float(policy.get("enemy_response_distance", 22.0)), maxf(6.0, float(Combat.profile(actor).get("range", 0.0)) + (4.0 if bool(actor.get("components", {}).get("worker", {}).get("enabled", false)) else 8.0)))
		)
		var value := 20.0
		if String(actor.get("kind", "")) == "town_center":
			value = 70.0
		elif String(actor.get("entity_type", "")) == "building":
			value = 40.0
		elif bool(actor.get("components", {}).get("worker", {}).get("enabled", false)):
			value = 35.0
		var movement := String(actor.get("movement_domain", "land"))
		var domains: Array = actor.get("target_domains", ["land" if movement == "static" else movement])
		for domain_value in domains:
			var domain := String(domain_value)
			if domain not in forces: continue
			var radius := float(actor.get("footprint_radius", 1.0))
			var firing_range := 0.0
			for unit in forces[domain]: firing_range = maxf(firing_range, float(Combat.profile(unit).get("range", 0.0)))
			var approach: Variant = _approach(snapshot, domain, position, radius + maxf(2.0, firing_range),approaches.get(domain,{}))
			if domain == "water" and movement == "static" and approach == null: continue
			var guard_strength := 0.0
			for guard in known_enemies.slice(0, int(policy.get("combat_sample_budget", 32))):
				if Vector2(guard.get("pos", Vector2.ZERO)).distance_to(position) <= 10.0:
					guard_strength += Combat.strength([guard]) * float(guard.get("confidence", 1.0))
			var score := (value + (120.0 if defence else 0.0)) * float(actor["confidence"]) - home.distance_to(position) * 0.45 - danger(position, tick, policy, domain) * 0.3
			if not forces[domain].is_empty():
				score += 8.0
				if not defence: score -= maxf(0.0, guard_strength * float(policy.get("attack_ratio", 1.15)) - float(strengths[domain])) * 1.5
			if int(actor.get("id", -1)) == int(goal.get("target_id", -2)): score += float(policy.get("goal_inertia", 18.0))
			var candidate := {"type": "defend" if defence else "attack", "target_id": int(actor["id"]), "position": Vector2(approach) if domain == "water" and movement == "static" else position, "target_position": position, "target_domain": domain, "target_domains": domains.duplicate(), "target_radius": radius, "observed": bool(actor["observed"]), "home": home, "adaptive_strategy": true, "needs_transport": domain == "land" and approach == null}
			if bool(actor.get("aggregate",false)): candidate["type"]="secure"; candidate["objective_category"]="belief"
			if score > float(domain_scores.get(domain, -INF)):
				domain_scores[domain] = score
				domain_goals[domain] = candidate
			if score > best_score:
				# Keep the primary goal detached from its domain map.
				best = candidate.duplicate()
				best_score = score
	if best.is_empty():
		best = Strategic.choose_goal(snapshot, team, decision)
		best["home"] = home
		best["adaptive_strategy"] = true
	best["goals_by_domain"] = domain_goals
	goal = best
	return goal.duplicate(true)


static func _approach(snapshot: Dictionary, domain: String, target: Vector2, maximum_distance: float, indexed: Dictionary = {}) -> Variant:
	var points: Array = snapshot.get("navigation", {}).get("reachable", {}).get(domain, snapshot.get("navigation", {}).get(domain, []))
	if not indexed.is_empty():
		points=[]
		var low:=Vector2i((target-Vector2.ONE*maximum_distance).floor()); var high:=Vector2i((target+Vector2.ONE*maximum_distance).floor())
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				if indexed.has(Vector2i(x,y)): points.append(indexed[Vector2i(x,y)])
	var best: Variant = null
	var distance := maximum_distance * maximum_distance
	for value in points:
		var point := Vector2(value)
		var candidate := point.distance_squared_to(target)
		if candidate <= distance:
			if best == null or candidate < distance or (candidate == distance and (point.y < Vector2(best).y or (point.y == Vector2(best).y and point.x < Vector2(best).x))):
				best = point
				distance = candidate
	return best


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
			if bool(policy.get("competitive",false)):
				var details: Dictionary=metrics.get("rejected_by_type",{})
				var detail_key:=String(entry.get("type",""))+":"+reason
				details[detail_key]=int(details.get(detail_key,0))+1
				metrics["rejected_by_type"]=details
			metrics["rejection_reasons"][reason] = int(metrics["rejection_reasons"].get(reason, 0)) + 1
			var retry := maxi(1, int(policy.get("command_retry_ticks", 60)))
			# A blocked or unreachable depot needs a traffic/navigation retry,
			# not another identical return proposal every economic decision.
			if reason == "invalid_dropoff" or (String(entry.get("type", "")) == "gather" and reason in ["unreachable_target", "no_path", "no_approach_slot"]): retry = maxi(retry, int(policy.get("gather_retry_ticks", 400)))
			cooldowns[String(entry["metadata"].get("key", ""))] = tick + retry
			if entry["metadata"].has("site_key") and reason in ["blocked_or_sloped", "occupied_by_unit", "missing_domain_access", "no_approach_slot", "no_path"]:
				cooldowns[String(entry["metadata"]["site_key"])] = tick + maxi(20, int(policy.get("build_site_retry_ticks", 600)))
	while cooldowns.size() > 1024:
		var keys: Array = cooldowns.keys()
		keys.sort_custom(func(a, b): return int(cooldowns[a]) < int(cooldowns[b]) if int(cooldowns[a]) != int(cooldowns[b]) else String(a) < String(b))
		cooldowns.erase(keys[0])
	pending = retained


func canonical_state() -> Dictionary:
	var records: Array = []
	var ids: Array = memory.keys()
	ids.sort()
	for id in ids:
		records.append({"id": int(id), "value": memory[id].duplicate(true)})
	var result := {
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
	if not belief_regions.is_empty(): result["belief_regions"]=belief_regions.duplicate(true)
	return result


func restore_state(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION:
		return false
	if not data.get("belief_regions",{}) is Dictionary or data.get("belief_regions",{}).size()>256: return false
	belief_regions=data.get("belief_regions",{}).duplicate(true)
	for field in ["memory", "samples", "pending", "previous_owned"]:
		if not data.get(field, []) is Array:
			return false
	for field in ["goal", "income", "spent", "cooldowns", "metrics", "scout_visits", "expeditions"]:
		if not data.get(field, {}) is Dictionary:
			return false
	var defense_pending=data.get("metrics",{}).get("pending_defense_refresh",false)
	var defense_rally=data.get("goal",{}).get("defense_rally",false)
	if not defense_pending is bool or not defense_rally is bool or defense_pending!=defense_rally: return false
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
	if saved_metrics.has("belief_route_cursor") and (int(saved_metrics["belief_route_cursor"])<0 or int(saved_metrics["belief_route_cursor"])>=Belief.MAX_ROUTE_HYPOTHESES): return false
	if saved_metrics.has("opening_selection"):
		var selected=saved_metrics["opening_selection"]
		if not selected is Dictionary or String(selected.get("style","")) not in ["pressure","fast_age","growth","naval"]:return false
		if not selected.get("weights",{}) is Dictionary or selected.get("weights",{}).size()>4:return false
		for weight in selected.get("weights",{}).values():
			if not (weight is float or weight is int) or not is_finite(float(weight)) or float(weight)<0.0:return false
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
		var value: Dictionary=entry["value"]
		if value.has("origin_disproved") and not value["origin_disproved"] is bool: return false
		if value.has("origin_disproved_tick"):
			var negative_tick=value["origin_disproved_tick"]
			if not (negative_tick is int or negative_tick is float) or not is_finite(float(negative_tick)):return false
			if float(int(negative_tick))!=float(negative_tick) or not bool(value.get("origin_disproved",false)) or int(negative_tick)<int(value.get("seen_tick",0)) or int(negative_tick)>int(data.get("last_observation_tick",-1)):return false
		if value.has("route_area"):
			if not Belief.valid_route_area(value["route_area"]): return false
			var area: Dictionary=value["route_area"]
			if not area.is_empty() and (int(area["seen_tick"])!=int(value.get("seen_tick",-1)) or int(area["tick"])>int(data.get("last_observation_tick",-1))): return false
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
