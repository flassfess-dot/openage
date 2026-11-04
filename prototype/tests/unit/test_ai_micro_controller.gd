extends SceneTree
const Micro := preload("res://scripts/ai_micro_controller.gd")
const State := preload("res://scripts/ai_strategy_state.gd")
var failures: Array[String] = []

func actor(id: int,team: int,pos: Vector2,hp: float=30.0,reach: float=0.0) -> Dictionary:
	return {"id":id,"team":team,"pos":pos,"hp":hp,"max_hp":hp,"kind":"test","entity_type":"unit","task":"idle","movement_domain":"land","combat_enabled":true,"target_domains":["land"],"ai_profile":{"enabled":true,"damage":10.0,"period":1.0,"range":reach,"speed":1.0,"max_hp":hp,"cooldown":0.0},"components":{}}

func _initialize() -> void:
	var micro := Micro.new(); var state := State.new()
	var archer := actor(1,1,Vector2(4.5,4.5),30,6); archer["ai_profile"]["cooldown"]=0.8
	var enemy := actor(10,2,Vector2(5.5,4.5),30,0)
	var snapshot := {"tick":0,"observer_team":1,"units":[archer,enemy],"buildings":[],"projectiles":[],"player_state":{"allies":[1]},"navigation":{"reachable":{"land":[Vector2(2.5,4.5),Vector2(3.5,4.5),Vector2(4.5,4.5)]}}}
	var commands := micro.plan(snapshot,4,1,{},state)
	check(not commands.is_empty() and commands[0].command_type()=="move","ranged recovery produces a retreat between shots")
	archer["ai_profile"]["cooldown"]=0.0
	snapshot["units"]=[archer,actor(2,1,Vector2(4.5,4.6),30,6),actor(10,2,Vector2(7,4.5),1,0),actor(11,2,Vector2(7,4.6),30,0)]
	commands = Micro.new().plan(snapshot,4,1,{},state)
	var targets: Dictionary = {}
	for command in commands:
		if command.command_type()=="attack": targets[int(command.params["target_entity_id"])]=true
	check(targets.size()==2,"planned salvo avoids wasting two shots on one-health target")
	var missile := {"id":100,"team":2,"pos":Vector2(2,4.5),"velocity":Vector2(2,0),"radius":0.2}
	snapshot["projectiles"]=[missile]
	var reaction := Micro.new()
	check(reaction.projectile_dodge(archer,snapshot,0,1,4)==Vector2.ZERO,"no instantaneous response to a new projectile")
	check(reaction.projectile_dodge(archer,snapshot,4,1,4)!=Vector2.ZERO,"visible trajectory can trigger a delayed dodge")
	var saved := reaction.canonical_state(); var restored := Micro.new()
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"reaction history survives save")
	var priest:=actor(20,1,Vector2(4.5,4.5),25,0)
	priest["combat_enabled"]=false; priest["behavior_tags"]=["converter"]
	priest["ai_profile"]["conversion"]={"enabled":true,"faith":25.0,"max_faith":100.0}
	var cavalry:=actor(30,2,Vector2(9.5,4.5),150,0)
	snapshot["projectiles"]=[]; snapshot["units"]=[priest,cavalry]
	check(Micro.new().decide(priest,[cavalry],[priest],snapshot,40,1,{},State.new(),{},false).is_empty(),"depleted priest saves the command budget until faith recovers")
	priest["ai_profile"]["conversion"]["faith"]=100.0
	check(String(Micro.new().decide(priest,[cavalry],[priest],snapshot,40,1,{},State.new(),{},false).get("type",""))=="convert","recharged priest can resume conversion")
	verify_role_control()
	for failure in failures: push_error(failure)
	print("Tactical micro: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value: failures.append(message)

func verify_role_control() -> void:
	var points: Array=[]
	for y in range(1,16):
		for x in range(1,16): points.append(Vector2(x+0.5,y+0.5))
	var snapshot := {"tick":40,"observer_team":1,"units":[],"buildings":[],"projectiles":[],"player_state":{"allies":[1]},"navigation":{"reachable":{"land":points,"water":points}}}
	var winding := actor(200,1,Vector2(4.5,4.5),30,6)
	winding["task"]="attack_move";winding["ai_profile"]["action_phase"]="PerformAction"
	snapshot["units"]=[winding,actor(201,2,Vector2(5.5,4.5),50,1)]
	check(Micro.new().plan(snapshot,40,1,{},State.new()).is_empty(),"an autonomous attack-move shot completes its windup before a new tactical order")
	var priest := actor(20,1,Vector2(4.5,4.5),25,0)
	priest["combat_enabled"]=false;priest["behavior_tags"]=["converter"]
	priest["task"]="convert";priest["target_id"]=30
	priest["ai_profile"]["conversion"]={"enabled":true,"faith":100.0,"max_faith":100.0}
	priest["ai_profile"]["action_phase"]="PerformAction"
	var attacker := actor(30,2,Vector2(5.5,4.5),150,1)
	snapshot["units"]=[priest,attacker]
	var orders: Array=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="move" and 20 in c.unit_ids),"a priest can abandon a cast when a melee attacker reaches it")
	priest["ai_profile"]["conversion"].merge({"active":true,"target_id":30,"chants":2,"min_chants":3,"chant_interval":1.5,"chant_elapsed":1.4},true)
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.is_empty(),"a viable nearly completed conversion is preserved using own progress rather than the future random outcome")
	priest["target_id"]=9999;attacker["pos"]=Vector2(8.5,4.5)
	snapshot["units"]=[priest,attacker]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="hold" and 20 in c.unit_ids),"a conversion whose target is no longer observed is explicitly cancelled")
	var archer := actor(40,1,Vector2(4.5,6.5),30,6)
	var guard := actor(41,1,Vector2(4.5,10.5),60,1)
	var runner := actor(50,2,Vector2(11.5,6.5),50,1);runner["ai_profile"]["speed"]=2.1
	snapshot["units"]=[archer,guard,runner]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="move" and 41 in c.unit_ids and Vector2(c.params.get("target",Vector2.ZERO)).x>4.5),"a melee escort occupies the threatened front of its ranged support")
	guard["pos"]=Vector2(6.5,6.5);runner["pos"]=Vector2(10,6.5)
	snapshot["units"]=[archer,guard,runner]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(not orders.any(func(c):return c.command_type()=="attack" and 41 in c.unit_ids and int(c.params.get("target_entity_id",-1))==50),"a faster decoy cannot pull the melee screen away from ranged support")
	var pursuit := actor(43,1,Vector2(6.5,6.5),100,1)
	pursuit["behavior_tags"]=["cavalry"];pursuit["ai_profile"]["speed"]=2.0
	snapshot["units"]=[archer,guard,pursuit,runner]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="attack" and 43 in c.unit_ids and int(c.params.get("target_entity_id",-1))==50) and not orders.any(func(c):return c.command_type()=="attack" and 41 in c.unit_ids),"mobile cavalry can pursue while infantry retains the protective line")
	var shooter := actor(51,2,Vector2(12,6.5),30,6)
	snapshot["units"]=[archer,guard,shooter]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="attack" and 41 in c.unit_ids and int(c.params.get("target_entity_id",-1))==51),"a melee screen closes with an enemy shooter instead of waiting under its fire")
	var ship := actor(60,1,Vector2(4.5,4.5),200,6);ship["movement_domain"]="water";ship["target_domains"]=["water"]
	var warship := actor(61,2,Vector2(7.5,4.5),200,6);warship["movement_domain"]="water"
	var transport := actor(62,2,Vector2(7.5,5.5),200,0);transport["movement_domain"]="water";transport["combat_enabled"]=false;transport["behavior_tags"]=["transport"]
	snapshot["units"]=[ship,warship,transport]
	orders=Micro.new().plan(snapshot,40,1,{},State.new())
	check(orders.any(func(c):return c.command_type()=="attack" and 60 in c.unit_ids and int(c.params.get("target_entity_id",-1))==62),"a visible transport is a meaningful naval interception target")
	var siege := actor(70,1,Vector2(4.5,4.5),100,8);siege["ai_profile"]["blast_range"]=2.0
	var tower := actor(71,2,Vector2(10,4.5),600,6);tower["entity_type"]="building";tower["kind"]="tower"
	var fighter := actor(72,2,Vector2(10,6.5),40,1)
	snapshot["units"]=[siege,fighter];snapshot["buildings"]=[tower]
	var state := State.new();state.goal={"strategic_plan":"siege"}
	orders=Micro.new().plan(snapshot,40,1,{},state)
	check(orders.any(func(c):return c.command_type()=="attack" and 70 in c.unit_ids and int(c.params.get("target_entity_id",-1))==71),"a siege plan prioritizes a defended fortification over a cheap distraction")
