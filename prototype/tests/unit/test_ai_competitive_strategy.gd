extends SceneTree
const Macro=preload("res://scripts/ai_macro_plan.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const Director=preload("res://scripts/ai_strategy_director.gd")
const Regions=preload("res://scripts/ai_region_model.gd")
var failures: Array[String]=[]
class Facts extends RefCounted:
	var threat:=0.0
	var goal: Dictionary={"home":Vector2(4,4),"type":"develop"}
	var metrics: Dictionary={}
	var expeditions: Dictionary={}
	var blocked:=false
	func danger(position: Vector2,_tick: int,_policy: Dictionary,_domain: String="land") -> float: return 100.0 if blocked and position.x>8.0 and position.x<16.0 and position.y<8.0 else threat
	func enemies(_tick: int,_policy: Dictionary,_observed: bool=false) -> Array: return []
func _initialize() -> void:
	var styles: Dictionary={}
	var choices: Array=[]
	for seed in range(20):
		var selected:=Macro.opening({"observer_team":1,"match_seed":seed},{})
		check(selected==Macro.opening({"observer_team":1,"match_seed":seed},{}),"seed repeats its opening")
		styles[selected]=true; choices.append({"seed":seed,"style":selected})
	check(styles.size()==4,"twenty seeds cover all four opening families")
	verify_contextual_opening()
	var easy: Dictionary=Policy.resolve("random_map_balanced","easy")["competitive_parameters"]
	var hard: Dictionary=Policy.resolve("random_map_balanced","hard")["competitive_parameters"]
	check(not easy["combat_rollouts"] and hard["strategy_interval_ticks"]<easy["strategy_interval_ticks"],"difficulty changes attention and search depth")
	var state=Facts.new(); var regions=Regions.new(); var director=Director.new()
	var snapshot: Dictionary={"tick":0,"observer_team":1,"units":[],"buildings":[],"resources":[],"player_state":{"age":100,"allies":[1,2]},"navigation":{},"victory_rules":[{"type":"artifacts"}],"objectives":[]}
	for id in range(18): snapshot["units"].append({"id":id+1,"team":1,"hp":25.0,"components":{"worker":{"enabled":true}}})
	var tc: Dictionary={"id":100,"team":1,"hp":600.0,"kind":"town_center","state":"complete","command_options":{"research":[{"technology_id":101,"accepted":false,"reason":"missing_prerequisites"}]}}
	snapshot["buildings"]=[tc]
	var policy:={"age_advance_technology_ids":[101,102,103],"plan_inertia":8.0}
	director.choose(snapshot,1,policy,state,regions)
	check(director.plan["id"]=="advance" and director.plan["active_task"]=="satisfy_prerequisites","plan waits for actual age prerequisites")
	tc["command_options"]["research"][0]["reason"]="insufficient_resources"; snapshot["tick"]=80
	director.choose(snapshot,1,policy,state,regions)
	check(director.plan["active_task"]=="reserve_resources","plan advances only after prerequisites")
	tc["command_options"]["research"][0]["accepted"]=true; snapshot["tick"]=160
	director.choose(snapshot,1,policy,state,regions)
	check(director.plan["active_task"]=="advance_age","affordable age moves to the execution step")
	snapshot["player_state"]["age"]=101; snapshot["tick"]=240
	director.choose(snapshot,1,policy,state,regions)
	check(director.plan["active_task"]=="apply_upgrades","completed age is observed before applying upgrades")
	var restored=Director.new(); check(restored.restore_state(director.canonical_state()) and restored.canonical_state()==director.canonical_state(),"in-flight plan restores exactly")
	state.threat=20.0; snapshot["tick"]=241
	director.choose(snapshot,1,policy,state,regions)
	check(director.plan["id"]=="survive","serious threat preempts inertia immediately")
	state.threat=0.0; state.blocked=true
	var points: Array=[]
	for y in [4,12]:
		for x in [4,12,20]: points.append(Vector2(x,y))
	regions.update({"tick":400,"navigation":{"reachable":{"land":points}},"resources":[],"map_size":Vector2i(24,24)},state,{})
	var route:=regions.route(Vector2(4,4),Vector2(20,4),"land")
	check(not route.is_empty() and route.any(func(p): return Vector2(p).y>8.0),"strategic route avoids a known dangerous passage")
	state.blocked=false; snapshot["tick"]=480
	snapshot["objectives"]=[{"id":800,"team":2,"category":"artifact","pos":Vector2(5,4)},{"id":801,"team":0,"category":"artifact","pos":Vector2(8,4)}]
	var goal: Dictionary=Director.new().choose(snapshot,1,policy,state,regions)
	check(int(goal.get("target_id",-1))==801,"allied objective does not distract from neutral victory objective")
	var report_path:="res://qa/ai-competitive/competitive-20261030/strategy_contracts.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var output=FileAccess.open(report_path,FileAccess.WRITE)
	check(output!=null,"strategy report opens in a clean project")
	if output!=null:output.store_string(JSON.stringify({"styles":choices,"failures":failures},"\t"))
	verify_real_siege_screen()
	for failure in failures: push_error(failure)
	print("Competitive strategy: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)

func verify_contextual_opening() -> void:
	var state:=preload("res://scripts/ai_strategy_state.gd").new()
	var snapshot:={"observer_team":1,"match_seed":41,"player_state":{"players":[{"team":1,"civilization_id":13},{"team":2,"civilization_id":3}]},"navigation":{"land":range(100),"water":[]},"buildings":[]}
	var before:=var_to_bytes(snapshot)
	var first:=Macro.opening(snapshot,{},state)
	check(first!="naval" and float(state.metrics["opening_selection"]["weights"]["naval"])==0.0,"known dry terrain excludes a naval opening")
	check(var_to_bytes(snapshot)==before,"style selection leaves the captured inputs intact")
	var saved:=state.canonical_state()
	var restored:=preload("res://scripts/ai_strategy_state.gd").new()
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"opening choice and its seeded context restore exactly")
	snapshot["navigation"]={"land":[],"water":range(100)}
	check(Macro.opening(snapshot,{},restored)==first,"exploration cannot silently replace the committed opening")
	check(Macro.opening(snapshot,{"style":"pressure"},restored)=="pressure","explicit style overrides an automatic opening")
	var water_state:=preload("res://scripts/ai_strategy_state.gd").new()
	Macro.opening(snapshot,{},water_state)
	check(float(water_state.metrics["opening_selection"]["weights"]["naval"])>1.0,"known water increases naval opening probability")
	var capable:=snapshot.duplicate(true)
	capable["buildings"]=[{"team":1,"command_options":{"train":[{"behavior_tags":["worker"],"cost":{0:35}},{"behavior_tags":["combatant"],"ai_profile":{"enabled":true,"speed":1.5,"range":0.0}}]}}]
	var own_state:=preload("res://scripts/ai_strategy_state.gd").new()
	Macro.opening(capable,{},own_state)
	check(float(own_state.metrics["opening_selection"]["weights"]["growth"])>float(water_state.metrics["opening_selection"]["weights"]["growth"]) and float(own_state.metrics["opening_selection"]["weights"]["pressure"])>float(water_state.metrics["opening_selection"]["weights"]["pressure"]),"own civilization's real worker price and fast melee capability affect weights")
	capable["buildings"][0]["team"]=2
	var foreign_state:=preload("res://scripts/ai_strategy_state.gd").new()
	Macro.opening(capable,{},foreign_state)
	check(foreign_state.metrics["opening_selection"]["weights"]==water_state.metrics["opening_selection"]["weights"],"foreign capabilities cannot change an opening")
	var old_state:=preload("res://scripts/ai_strategy_state.gd").new()
	old_state.metrics["macro_plan"]={"style":"fast_age"}
	check(Macro.opening(snapshot,{},old_state)=="fast_age","older in-progress opening migrates without a style change")
	var malformed:=saved.duplicate(true);malformed["metrics"]["opening_selection"]["style"]="unknown"
	check(not restored.restore_state(malformed),"malformed saved style is rejected")

func verify_real_siege_screen() -> void:
	var director := Director.new();var state := Facts.new()
	var units: Array=[]
	for id in range(3): units.append({"id":id+1,"team":1,"hp":100.0,"pos":Vector2(8+id,8),"kind":"stone_thrower","movement_domain":"land","combat_enabled":true,"components":{},"behavior_tags":["siege","ranged"],"ai_profile":{"range":10.0,"blast_range":1.5}})
	var snapshot := {"units":units,"buildings":[],"player_state":{"allies":[1]}}
	var policy := {"minimum_attack_group_size":3}
	check(not director.task_complete("assign_screen",snapshot,1,policy,state,units),"three siege engines alone do not constitute a protective screen")
	director.plan={"id":"siege","active_task":"assign_screen","facts":{"siege_count":3,"screen_count":0,"screen_target":5}}
	var demand: Dictionary=director.apply_policy(policy)
	check(bool(demand.get("prefer_screen",false)) and not bool(demand.get("prefer_siege",false)),"a missing screen changes the actual production preference before more siege engines")
	for id in range(5): units.append({"id":20+id,"team":1,"hp":100.0,"pos":Vector2(7.5+id*0.3,8.5),"kind":"hoplite","movement_domain":"land","combat_enabled":true,"components":{},"behavior_tags":["melee"],"ai_profile":{"range":0.0}})
	check(director.task_complete("assign_screen",snapshot,1,policy,state,units),"nearby melee fighters complete the real screen requirement")
	for unit in units.slice(3): unit["pos"]=Vector2(25,25)
	check(not director.task_complete("assign_screen",snapshot,1,policy,state,units),"distant melee fighters cannot complete the firing group's screen")
	units.append({"id":50,"team":1,"hp":40.0,"pos":Vector2(8,8),"kind":"archer","task":"attack","combat_enabled":true,"ai_profile":{"range":6.0,"action_phase":"PerformAction"}})
	check(not director.task_complete("occupy_firing_position",snapshot,1,policy,state,units),"an ordinary archer's attack does not complete the siege firing task")
	units[0]["ai_profile"]["action_phase"]="PerformAction"
	check(director.task_complete("occupy_firing_position",snapshot,1,policy,state,units),"the siege engine's own firing phase completes the firing-position task")
