extends RefCounted

const MAX_INTERESTS:=12
const MAX_ENEMIES:=6
const MAX_RESOURCE_SAMPLES:=64

# Questions whose answers can change a current decision. Points are hypotheses
# or already known locations; they only rank the scout's legal regional frontier.
static func interests(snapshot:Dictionary, state, policy:Dictionary, enemies:Array) -> Array:
	var result:Array=[]
	var attacking:=String(state.goal.get("type","")) in ["attack","secure"]
	var attention:Array=[]
	for enemy in enemies:
		if bool(enemy.get("observed",false)):continue
		var priority:=1.0-float(enemy.get("confidence",1.0))+(0.5 if not enemy.get("route_area",{}).is_empty() else 0.0)
		var slot:=0
		while slot<attention.size() and (float(attention[slot]["priority"])>priority or (float(attention[slot]["priority"])==priority and int(attention[slot]["enemy"].get("id",0))<int(enemy.get("id",0)))):slot+=1
		if slot<MAX_ENEMIES:
			attention.insert(slot,{"enemy":enemy,"priority":priority})
			if attention.size()>MAX_ENEMIES:attention.pop_back()
	for entry in attention:
		var enemy:Dictionary=entry["enemy"]
		var domain:=String(enemy.get("movement_domain","land"))
		var category:="army"
		if domain=="static":
			domain="land"
			category="technology" if String(enemy.get("kind","")) in ["temple","academy","siege_workshop","archery_range","stable"] else "base"
		var area:Dictionary=enemy.get("route_area",{})
		var points:Array=area.get("points",[])
		var samples:Array=[]
		if points.is_empty():samples.append(Vector2(enemy.get("pos",Vector2.ZERO)))
		else:
			var stride:=maxi(1,ceili(float(points.size())/8.0))
			for index in range(0,points.size(),stride):samples.append(Vector2(points[index]))
		var uncertainty:=clampf(1.0-float(enemy.get("confidence",1.0)),0.10,1.0)
		result.append({"decision":category,"domain":domain,"points":samples,"value":(24.0 if attacking else 14.0)*uncertainty,"hypothesis_only":true})
	var player:Dictionary=snapshot.get("player_state",{})
	var resources:Array=snapshot.get("resources",[])
	var names:={0:"food",1:"wood",2:"stone",3:"gold"}
	var needs:Dictionary={}
	for resource in names:
		var stock:=float(player.get(names[resource],0.0))
		var desired:=float(policy.get("desired_stock",{}).get(resource,150.0 if int(resource)<2 else 50.0))
		if stock<desired:needs[resource]=clampf((desired-stock)/maxf(1.0,desired),0.0,1.0)
	var found:Dictionary={}
	var stride:=maxi(1,ceili(float(resources.size())/float(MAX_RESOURCE_SAMPLES)))
	for index in range(0,resources.size(),stride):
		var resource:Dictionary=resources[index]
		var type:=int(resource.get("resource_type_id",-1))
		if not needs.has(type) or found.has(type) or float(resource.get("amount",0.0))<=0.0:continue
		var domains:Array=resource.get("allowed_gatherer_domains",["land"])
		result.append({"decision":"resource","resource":type,"domain":"water" if "water" in domains and "land" not in domains else "land","points":[Vector2(resource.get("pos",Vector2.ZERO))],"value":10.0*float(needs[type])})
		found[type]=true
		if result.size()>=MAX_INTERESTS:break
	if result.size()<MAX_INTERESTS and state.goal.has("expansion_position"):
		result.append({"decision":"expansion","domain":"land","points":[Vector2(state.goal["expansion_position"])],"value":14.0 if String(state.goal.get("strategic_plan",""))=="expand" else 4.0})
	if result.size()<MAX_INTERESTS and bool(state.goal.get("needs_transport",false)):
		result.append({"decision":"exit","domain":"water","points":[Vector2(state.goal.get("target_position",state.goal.get("position",Vector2.ZERO)))],"value":18.0})
	return result.slice(0,MAX_INTERESTS)


static func evaluate(point:Vector2, origin:Vector2, speed:float, domain:String, questions:Array, visit_age:int) -> Dictionary:
	var travel:=origin.distance_to(point)/maxf(0.2,speed)
	var best:=0.0
	var decision:="explore"
	for question in questions:
		if String(question["domain"])!=domain:continue
		var distance:=INF
		for target in question["points"]:distance=minf(distance,point.distance_to(Vector2(target)))
		var value:=float(question["value"])/(1.0+distance/8.0)/(1.0+travel/30.0)*clampf(float(visit_age)/160.0,0.0,1.0)
		if value>best:best=value;decision=String(question["decision"])
	return {"decision":decision,"value":best,"travel_seconds":travel}
