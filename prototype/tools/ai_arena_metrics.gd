# Evaluator only: privileged match data never enters an AI observation.
extends RefCounted
var teams: Dictionary = {}
var actors: Dictionary = {}
var last_tick := 0
var event_cursor := 0

func consume(world,controller) -> void:
	var events: Array=controller.events_after(event_cursor)
	if not events.is_empty(): event_cursor=int(events.back()["sequence_id"])
	sample(world,int(controller.tick_index),events)

func row(team: int) -> Dictionary:
	if not teams.has(team): teams[team] = {"worker_ticks":0,"idle_worker_ticks":0,"tc_ticks":0,"tc_idle_ticks":0,"producer_ticks":0,"population_blocked_ticks":0,"stock_integral":[0,0,0,0],"deposited":[0,0,0,0],"lost_value":0.0,"killed_value":0.0,"converted_value":0.0,"age_ticks":{},"rejected":{},"commands":0}
	return teams[team]

func sample(world, tick: int, events: Array) -> void:
	var elapsed := maxi(0,tick-last_tick)
	if elapsed > 0 or actors.is_empty():
		for actor in world.get_units()+world.get_buildings():
			var team := int(actor.get("team",0))
			if team <= 0: continue
			var data := row(team)
			var id := int(actor["id"])
			if not actors.has(id):
				var cost: Dictionary = world.building_cost(String(actor.get("kind","")),team) if actor.has("production_queue") else world.unit_resource_cost(String(actor.get("kind","")),team)
				var value := 0.0
				for price in cost.values(): value += maxf(0.0,float(price))
				actors[id] = {"team":team,"value":value}
			if float(actor.get("hp",0.0)) <= 0.0: continue
			if bool(actor.get("components",{}).get("worker",{}).get("enabled",false)):
				data["worker_ticks"] += elapsed
				if String(actor.get("task","idle")) == "idle": data["idle_worker_ticks"] += elapsed
			if String(actor.get("kind","")) == "town_center" and String(actor.get("state","complete")) == "complete":
				data["tc_ticks"] += elapsed
				if actor.get("production_queue",[]).is_empty(): data["tc_idle_ticks"] += elapsed
			if actor.has("production_queue") and String(actor.get("kind","")) in ["town_center","barracks","archery_range","stable","academy","siege_workshop","dock","temple"] and String(actor.get("state","complete"))=="complete":
				data["producer_ticks"] += elapsed
				if actor.get("production_queue",[]).any(func(order): return String(order.get("status","")) == "blocked_population"): data["population_blocked_ticks"] += elapsed
		for team in world.player_registry.all_teams():
			var data := row(int(team))
			for type_id in range(4): data["stock_integral"][type_id] += world.get_resource_amount(int(team),type_id)*elapsed
			var age: int = world.get_current_age(int(team))
			if not data["age_ticks"].has(age): data["age_ticks"][age] = tick
	for event in events:
		var payload: Dictionary = event.get("payload",{})
		var team := int(payload.get("team",payload.get("issuer_id",0)))
		match String(event.get("type","")):
			"resources_deposited":
				var type_id := int(payload.get("resource_type_id",-1))
				if team > 0 and type_id >= 0 and type_id < 4: row(team)["deposited"][type_id] += int(payload.get("amount",0))
			"command_accepted":
				if team > 0: row(team)["commands"] += 1
			"command_rejected":
				if team > 0:
					var reason := String(payload.get("reason","unknown"))
					row(team)["rejected"][reason] = int(row(team)["rejected"].get(reason,0))+1
			"death":
				var id := int(payload.get("entity_id",-1))
				if team > 0 and actors.has(id):
					row(team)["lost_value"] += float(actors[id]["value"])
					var killer := int(payload.get("killer_team",0))
					if killer > 0 and killer != team: row(killer)["killed_value"] += float(actors[id]["value"])
			"ownership_changed":
				var id := int(payload.get("entity_id",-1))
				var owner := int(payload.get("new_team",0))
				if actors.has(id) and owner > 0 and String(payload.get("ownership_reason","")) == "conversion": row(owner)["converted_value"] += float(actors[id]["value"])
	last_tick = tick

func report() -> Dictionary:
	var result := teams.duplicate(true)
	for team in result:
		var data: Dictionary = result[team]
		data["idle_worker_ratio"] = float(data["idle_worker_ticks"])/maxf(1.0,float(data["worker_ticks"]))
		data["tc_idle_ratio"] = float(data["tc_idle_ticks"])/maxf(1.0,float(data["tc_ticks"]))
		data["population_blocked_ratio"] = float(data["population_blocked_ticks"])/maxf(1.0,float(data["producer_ticks"]))
	return result
