extends RefCounted
const Combat := preload("res://scripts/ai_combat_model.gd")

static func assignments(snapshot: Dictionary,groups: Dictionary,goal: Dictionary,policy: Dictionary,state,by_id: Dictionary,tick: int) -> Dictionary:
	var ids: Array = groups.keys(); ids.sort()
	var result: Dictionary = {}
	var defenders: Dictionary = {}
	if String(goal.get("type",""))=="defend":
		var target = Vector2(goal.get("position",Vector2.ZERO))
		var threats: Array = state.enemies(int(snapshot.get("tick",0)),policy,true).filter(func(e): return Vector2(e.get("pos",Vector2.ZERO)).distance_to(target)<12.0)
		var needed = Combat.strength(threats)*1.3
		var candidates: Array = []
		for id in ids:
			var group = groups[id]["group"]
			if String(group.movement_domain)!=String(goal.get("target_domain","land")): continue
			var members: Array = []
			for member in group.living_ids():
				if by_id.has(int(member)): members.append(by_id[int(member)])
			if members.is_empty(): continue
			var center = Vector2.ZERO
			for member in members: center+=Vector2(member.get("pos",Vector2.ZERO))
			center/=members.size()
			candidates.append({"id":id,"distance":center.distance_to(target),"strength":Combat.strength(members,threats)})
		candidates.sort_custom(func(a,b): return float(a["distance"])<float(b["distance"]) if not is_equal_approx(float(a["distance"]),float(b["distance"])) else int(a["id"])<int(b["id"]))
		var assigned = 0.0
		for candidate in candidates:
			if assigned>=needed and not defenders.is_empty(): break
			defenders[int(candidate["id"])]=true; assigned+=float(candidate["strength"])
	for index in range(ids.size()):
		var id = ids[index]; var operation: Dictionary = groups[id]
		var group = operation["group"]
		var domain = String(group.movement_domain)
		var selected: Dictionary = goal.get("goals_by_domain",{}).get(domain,goal).duplicate(true)
		if defenders.has(int(id)): selected=goal.duplicate(true); operation["role"]="defend"
		else:
			var role = "main" if index==0 else "raid" if index%3==1 else "guard" if index%3==2 and ids.size()>=3 else "reinforce"
			operation["role"]=role
			if role=="guard": selected={"type":"guard","position":goal.get("home",Vector2.ZERO),"target_domain":domain,"target_id":-1}
			if role=="guard" and goal.has("ally_cover_position"): selected["position"]=goal["ally_cover_position"]
			elif role=="raid" or String(selected.get("type",""))=="defend":
				var best = -INF; var found: Dictionary = {}
				for enemy in state.enemies(int(snapshot.get("tick",0)),policy):
					var enemy_domain = String(enemy.get("movement_domain","land"))
					if enemy_domain=="static": enemy_domain="land"
					if enemy_domain!=domain: continue
					var position = Vector2(enemy.get("pos",Vector2.ZERO))
					var value = (60.0 if bool(enemy.get("components",{}).get("worker",{}).get("enabled",false)) else 30.0)*float(enemy.get("confidence",1.0))-Vector2(group.rally_position).distance_to(position)*0.3-state.danger(position,int(snapshot.get("tick",0)),policy,domain)*0.2
					if value>best: best=value; found=enemy
				if not found.is_empty():
					selected={"type":"attack","position":found["pos"],"target_position":found["pos"],"target_id":int(found["id"]),"target_domain":domain,"observed":bool(found.get("observed",false)),"home":goal.get("home",Vector2.ZERO)}
		if goal.has("allied_rally") and String(operation.get("role","")) in ["main","reinforce"]:
			var members: Array=group.living_ids().filter(func(member): return by_id.has(int(member)))
			if not members.is_empty() and members.all(func(member): return Vector2(by_id[int(member)].get("pos",Vector2.ZERO)).distance_to(Vector2(goal["allied_rally"]))>8.0): selected={"type":"guard","position":goal["allied_rally"],"target_domain":domain,"target_id":-1}
		operation["allocated_goal"]=selected.duplicate(true)
		result[id]=selected
	return result
