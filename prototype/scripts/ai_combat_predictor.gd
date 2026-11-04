# Bounded approximation over legal actor profiles. Never reads SimulationWorld.
extends RefCounted
const Combat := preload("res://scripts/ai_combat_model.gd")
const STEP_SECONDS=1.0

static func representatives(force: Array) -> Array:
	var buckets: Dictionary = {}
	for actor in force:
		if float(actor.get("hp",0.0))<=0.0: continue
		var p: Dictionary = actor.get("ai_profile",{})
		var role = "siege" if float(p.get("blast_range",0.0))>0.0 else "support" if "healer" in actor.get("behavior_tags",[]) or "converter" in actor.get("behavior_tags",[]) else "combat"
		var key = str([role,actor.get("kind",""),Vector2i(Vector2(actor.get("pos",Vector2.ZERO))/4.0)])
		if not buckets.has(key):
			buckets[key] = {"actor":actor.duplicate(true),"count":0.0,"hp":0.0,"position_sum":Vector2.ZERO,"role":role}
		var bucket: Dictionary = buckets[key]
		var weight = float(actor.get("confidence",1.0))
		bucket["count"] += weight
		bucket["hp"] += float(actor.get("hp",p.get("max_hp",1.0)))*weight
		bucket["position_sum"] += Vector2(actor.get("pos",Vector2.ZERO))*weight
	var keys: Array = buckets.keys(); keys.sort_custom(func(a,b): return String(buckets[a]["role"])>String(buckets[b]["role"]) if buckets[a]["role"]!=buckets[b]["role"] else String(a)<String(b))
	var result: Array = []
	for key in keys:
		var bucket: Dictionary = buckets[key]
		var actor: Dictionary = bucket["actor"]
		actor["pos"] = bucket["position_sum"]/maxf(0.01,float(bucket["count"]))
		actor["hp"] = bucket["hp"]
		actor["_count"] = bucket["count"]
		actor["_initial_hp"] = bucket["hp"]
		actor["_cooldown"] = float(actor.get("ai_profile",{}).get("cooldown",0.0))
		if result.size()<64: result.append(actor)
		else:
			# Preserve excess units as mass rather than dropping high IDs.
			var index = posmod(int(actor.get("id",0)),result.size())
			result[index]["hp"] += actor["hp"]; result[index]["_initial_hp"] += actor["hp"]; result[index]["_count"] += actor["_count"]
	return result

static func evaluate(ours: Array, enemies: Array, variants: Array = ["attack","hold","retreat","flank_left","flank_right"]) -> Dictionary:
	var a = representatives(ours); var b = representatives(enemies)
	var results: Dictionary = {}
	var best = "attack"; var best_score = -INF
	for variant in variants.slice(0,6):
		var row = simulate(a,b,String(variant))
		results[String(variant)] = row
		var score = float(row["own_remaining"])-float(row["enemy_remaining"])
		if String(variant)=="retreat": score += 0.05*float(row["own_remaining"])
		if score>best_score: best_score=score; best=String(variant)
	var attack: Dictionary = results.get("attack",results.values()[0] if not results.is_empty() else {})
	var confidence=0.7 if ours.size()+enemies.size()>128 else 0.85
	if ours.is_empty() or enemies.is_empty(): confidence=0.2
	if (ours+enemies).any(func(actor): return "converter" in actor.get("behavior_tags",[]) or float(actor.get("ai_profile",{}).get("blast_range",0.0))>0.0): confidence=minf(confidence,0.5)
	return {"best":best,"variants":results,"attack_ratio":(float(attack.get("own_remaining",0.0))+0.05)/(float(attack.get("enemy_remaining",0.0))+0.05),"confidence":confidence,"actors":a.size()+b.size(),"steps":16}

static func simulate(left: Array,right: Array,mode: String) -> Dictionary:
	var a = left.duplicate(true); var b = right.duplicate(true)
	var initial_a = health(a); var initial_b = health(b)
	for step in range(16):
		var damage_a: Dictionary = {}; var damage_b: Dictionary = {}
		advance(a,b,damage_b,mode)
		advance(b,a,damage_a,"attack")
		for index in damage_a: a[int(index)]["hp"] = maxf(0.0,float(a[int(index)]["hp"])-float(damage_a[index]))
		for index in damage_b: b[int(index)]["hp"] = maxf(0.0,float(b[int(index)]["hp"])-float(damage_b[index]))
		if health(a)<=0.0 or health(b)<=0.0: break
	return {"own_remaining":health(a)/maxf(1.0,initial_a),"enemy_remaining":health(b)/maxf(1.0,initial_b),"own_hp":health(a),"enemy_hp":health(b)}

static func health(force: Array) -> float:
	var total = 0.0
	for actor in force: total += maxf(0.0,float(actor.get("hp",0.0)))
	return total

static func advance(force: Array,enemies: Array,damage: Dictionary,mode: String) -> void:
	for actor in force:
		if float(actor["hp"])<=0.0: continue
		var profile: Dictionary = actor.get("ai_profile",{})
		var count = maxf(0.0,float(actor["_count"])*float(actor["hp"])/maxf(1.0,float(actor["_initial_hp"])))
		if "healer" in actor.get("behavior_tags",[]):
			for ally in force:
				if float(ally["hp"])>0.0 and float(ally["hp"])<float(ally["_initial_hp"]) and Vector2(ally["pos"]).distance_to(Vector2(actor["pos"]))<6.0:
					ally["hp"] = minf(float(ally["_initial_hp"]),float(ally["hp"])+count*float(profile.get("heal_rate",1.0))*STEP_SECONDS); break
		var nearest: Array = []
		for index in range(enemies.size()):
			var enemy: Dictionary = enemies[index]
			if float(enemy["hp"])<=0.0: continue
			var domain = String(enemy.get("movement_domain","land"))
			if domain=="static": domain="land"
			if domain not in actor.get("target_domains",["land","water"]): continue
			nearest.append({"index":index,"distance":Vector2(actor["pos"]).distance_to(Vector2(enemy["pos"]))})
		nearest.sort_custom(func(x,y): return float(x["distance"])<float(y["distance"]) if not is_equal_approx(float(x["distance"]),float(y["distance"])) else int(x["index"])<int(y["index"]))
		var target = -1; var best = -INF
		for candidate in nearest.slice(0,8):
			var enemy: Dictionary = enemies[int(candidate["index"])]
			var value = Combat.dps(actor,enemy)/(1.0+float(candidate["distance"])*0.25)
			if "converter" in actor.get("behavior_tags",[]): value += float(enemy["hp"])*0.03
			if value>best: best=value; target=int(candidate["index"])
		if target<0: continue
		var enemy: Dictionary = enemies[target]
		var delta = Vector2(enemy["pos"])-Vector2(actor["pos"])
		var distance = delta.length()
		var reach = float(profile.get("range",0.0))+float(actor.get("footprint_radius",0.3))+float(enemy.get("footprint_radius",0.3))+0.1
		var speed = maxf(0.0,float(profile.get("speed",0.0)))
		if mode=="retreat": actor["pos"] = Vector2(actor["pos"])-delta.normalized()*speed*STEP_SECONDS
		elif distance>reach and mode!="hold":
			var direction = delta.normalized()
			if mode=="flank_left": direction=(direction+direction.orthogonal()*0.4).normalized()
			if mode=="flank_right": direction=(direction-direction.orthogonal()*0.4).normalized()
			actor["pos"] = Vector2(actor["pos"])+direction*minf(speed*STEP_SECONDS,maxf(0.0,distance-reach))
		distance=Vector2(enemy["pos"]).distance_to(Vector2(actor["pos"]))
		actor["_cooldown"] = maxf(0.0,float(actor["_cooldown"])-STEP_SECONDS)
		if distance>reach+0.02 or float(actor["_cooldown"])>0.0: continue
		var period = maxf(0.1,float(profile.get("period",2.0)))
		var frontage = minf(count,maxf(1.0,float(enemy["_count"]))*6.0) if float(profile.get("range",0.0))<1.0 else count
		var hit = Combat.dps(actor,enemy)*period*frontage
		if "converter" in actor.get("behavior_tags",[]):
			actor["_chant"]=float(actor.get("_chant",0.0))+STEP_SECONDS
			var conversion: Dictionary=profile.get("conversion",{})
			var interval=maxf(0.5,float(conversion.get("chant_interval",1.5)))
			if float(actor["_chant"])>=interval*maxi(3,int(conversion.get("min_chants",3))): hit+=float(enemy["hp"])*count*float(conversion.get("base_success_chance",0.3))*STEP_SECONDS/interval
		var elevation = float(actor.get("elevation",0.0))-float(enemy.get("elevation",0.0))
		hit *= 1.25 if elevation>0.0 else 0.75 if elevation<0.0 else 1.0
		damage[target] = float(damage.get(target,0.0))+hit
		var blast = float(profile.get("blast_range",0.0))
		if blast>0.0:
			for candidate in nearest.slice(0,8):
				var index = int(candidate["index"])
				if index!=target and Vector2(enemies[index]["pos"]).distance_to(Vector2(enemy["pos"]))<blast: damage[index] = float(damage.get(index,0.0))+hit*0.5
		actor["_cooldown"] = period
