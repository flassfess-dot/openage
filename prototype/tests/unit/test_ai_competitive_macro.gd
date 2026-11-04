extends SceneTree
const Ai := preload("res://scripts/ai_player.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
const State := preload("res://scripts/ai_strategy_state.gd")
const Fixture := preload("res://tests/unit/test_ai_baseline_independence.gd")
const Macro := preload("res://scripts/ai_macro_plan.gd")
const Budget := preload("res://scripts/ai_plan_budget.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var fixtures := Fixture.new()
	var policy := Policy.resolve(); policy["algorithm_version"]="competitive_v2"; policy["competitive"]=true
	for cap in [50,200,500]:
		var snapshot: Dictionary = fixtures.fixture(12)
		snapshot["player_state"]["population_limit"]=cap
		snapshot["player_state"]["age"]=103
		var state := State.new(); state.observe(snapshot,1,policy)
		var selected := Economy.policy_for(snapshot,1,policy,state)
		check(int(selected["army_target"])>30 if cap>50 else int(selected["army_target"])>=10,"army demand scales with usable population")
		check(int(selected["land_worker_target"])>90 if cap==500 else int(selected["land_worker_target"])>=10,"worker ceiling scales rather than universal 90")
	var wonder_input: Dictionary=fixtures.fixture(0)
	wonder_input["player_state"]["age"]=103
	for id in range(23): wonder_input["units"].append({"id":500+id,"team":1,"hp":25.0,"kind":"villager","movement_domain":"land","components":{"worker":{"enabled":true}}})
	var wonder_state=State.new(); wonder_state.goal={"pursue_wonder":true}
	var wonder_policy=policy.duplicate(true); wonder_policy["style"]="pressure"
	var wonder_plan=Macro.adapt(wonder_policy,wonder_input,wonder_state)
	check(int(wonder_plan["land_worker_target"])<24 and int(wonder_plan["building_limits"]["wonder"])==1,"population 50 can pursue a wonder with its planned workforce")
	wonder_input["units"]=wonder_input["units"].slice(0,8)
	check(int(Macro.adapt(wonder_policy,wonder_input,wonder_state)["building_limits"]["wonder"])==0,"an undeveloped economy still postpones the wonder")
	var ai := Ai.new({"team":1,"ai":policy})
	var snapshot: Dictionary = fixtures.fixture(8)
	ai.collect_commands(snapshot,1)
	var saved := ai.canonical_state()
	var restored := Ai.new({"team":1,"ai":policy})
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"competitive plan and regions survive exact save")
	var bad := saved.duplicate(true); bad.erase("competitive_controller")
	check(not restored.restore_state(bad),"missing competitive state rejected")
	var economy_input: Dictionary=fixtures.fixture(8)
	for id in range(18): economy_input["units"].append({"id":20+id,"team":1,"kind":"villager","pos":Vector2(4.5,3.5),"hp":25.0,"task":"idle","movement_domain":"land","components":{"worker":{"enabled":true}},"command_options":{"build":[]}})
	economy_input["player_state"]["food"]=300
	economy_input["buildings"][0]["command_options"]["research"]=[{"technology_id":101,"accepted":false,"reason":"insufficient_resources","cost":{0:500}}]
	var economy_state=State.new(); economy_state.goal={"type":"develop"}
	policy["style"]="fast_age"
	var fund=Budget.new(economy_input["player_state"],economy_input["buildings"])
	Economy.plan(economy_input,0,1,policy,economy_state,fund,{})
	check(int(fund.protected.get(0,0))>0 and int(fund.protected.get(0,0))<=300,"age commitment protects accumulated food while keeping an operating floor")
	economy_input["buildings"][0]["command_options"]["research"][0]["reason"]="missing_prerequisites"
	economy_input["player_state"]["wood"]=200
	fund=Budget.new(economy_input["player_state"],economy_input["buildings"])
	Economy.plan(economy_input,20,1,policy,economy_state,fund,{})
	check(int(fund.protected.get(0,0))>0,"missing prerequisite construction does not release the age food to routine troops")
	check(int(fund.protected.get(1,0))==0 and int(fund.remaining[1])==200,"prerequisite construction retains its wood budget")
	var deadline: int=economy_state.metrics["age_reservation"]["deadline"]
	fund=Budget.new(economy_input["player_state"],economy_input["buildings"])
	Economy.plan(economy_input,deadline+1,1,policy,economy_state,fund,{})
	check(fund.protected.is_empty() and economy_state.metrics["age_reservation"].is_empty(),"failed long-term saving releases its reservation on deadline")
	economy_input["player_state"]["age"]=101
	economy_input["buildings"][0]["command_options"]["research"]=[{"technology_id":102,"accepted":false,"reason":"insufficient_resources","cost":{0:800}}]
	var slow_state=State.new(); slow_state.goal={"type":"develop"}; slow_state.income[0]=0.9
	fund=Budget.new(economy_input["player_state"],economy_input["buildings"])
	Economy.plan(economy_input,0,1,policy,slow_state,fund,{})
	check(int(slow_state.metrics["age_reservation"]["deadline"])>=ceili((800.0-300.0)/0.9*20.0),"a productive slow economy has enough simulated time to save the remaining age cost")
	verify_screen_production()
	verify_builder_marginal_value()
	verify_production_forecast()
	fixtures.free()
	for failure in failures: push_error(failure)
	print("Competitive macro: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value: failures.append(message)

func verify_production_forecast() -> void:
	var model:=preload("res://scripts/ai_production_forecast.gd")
	var combat:=preload("res://scripts/ai_combat_model.gd")
	var production:=preload("res://scripts/ai_economy_production.gd")
	var enemy:={"id":50,"kind":"archer","hp":40.0,"movement_domain":"land","confidence":0.5,"observed":false,"ai_profile":{"enabled":true,"max_hp":40.0,"damage":4.0,"attacks":[{"type_id":3,"amount":4.0}],"armors":[{"type_id":3,"amount":0.0}],"period":2.0,"range":5.0}}
	var candidate:={"kind":"counter","hp":60.0,"ai_profile":{"enabled":true,"max_hp":60.0,"damage":5.0,"attacks":[{"type_id":3,"amount":5.0}],"armors":[{"type_id":3,"amount":0.0}],"period":2.0,"range":4.0}}
	var snapshot:={"tick":6000,"observer_team":1,"player_state":{"food":500,"wood":500,"gold":80},"buildings":[]}
	var before:=var_to_bytes([enemy,candidate,snapshot])
	var context:Dictionary=model.context([enemy],snapshot,{})
	check(context["hypothesis_only"] and float(context["records"][0]["probability"])>0.0 and float(context["records"][0]["probability"])<1.0,"unobserved future upgrades remain a probability, never a revealed technology")
	var score:float=model.counter_score(candidate,context,[])
	var actual_dps:float=combat.dps(enemy,candidate)
	check(is_finite(score) and score>0.0,"mixed observed and possible upgraded army has a finite production value")
	check(var_to_bytes([enemy,candidate,snapshot])==before and combat.dps(enemy,candidate)==actual_dps,"forecast does not change observed or tactical combat profiles")
	var foreign:=snapshot.duplicate(true);foreign["foreign_technologies"]={2:[999]}
	check(model.context([enemy],foreign,{})==context,"hidden research supplied outside the legal contract cannot affect the forecast")
	var state:=State.new();state.income[3]=0.5
	var option:={"kind":"counter","cost":{3:80},"duration":30.0}
	var base_army:=[{"kind":"old_line","combat_enabled":true}]
	var logistics:Dictionary=model.logistics(option,base_army,snapshot,state,"barracks",45.0)
	check(float(logistics["switch_seconds"])>0.0,"a new gold-heavy line exposes the resource replenishment cost")
	check(float(model.logistics(option,[{"kind":"villager","behavior_tags":["worker"]}],snapshot,state,"barracks",45.0)["switch_seconds"])==0.0,"first military production is not treated as switching an existing army")
	check(float(model.logistics(option,[candidate],snapshot,state,"barracks",45.0)["switch_seconds"])==0.0,"an established unit line is not charged an invented switching fee")
	var ready:=snapshot.duplicate(true)
	ready["buildings"]=[{"id":1,"team":1,"kind":"barracks","state":"complete","production_queue":[]},{"id":2,"team":1,"kind":"barracks","state":"complete","production_queue":[]}]
	var parallel:Dictionary=model.logistics(option,base_army,ready,state,"barracks",45.0)
	check(int(parallel["capacity"])==2 and float(parallel["reinforcement_seconds"])<float(logistics["reinforcement_seconds"]),"existing own producer capacity improves estimated reinforcement time")
	ready["buildings"][0]["team"]=2;ready["buildings"][1]["team"]=2
	check(int(model.logistics(option,base_army,ready,state,"barracks",45.0)["capacity"])==0,"foreign producers cannot improve own production capacity")
	var many:Array=[]
	for id in range(100):
		var actor:=enemy.duplicate(true);actor["id"]=id;actor["kind"]="clubman" if id<90 else "siege";actor["ai_profile"]["range"]=0.0 if id<90 else 9.0
		many.append(actor)
	var bounded:Dictionary=model.context(many,snapshot,{})
	check(bounded["records"].size()==model.MAX_ENEMIES and bounded["records"].any(func(r):return String(r["current"]["kind"])=="siege"),"production attention stays bounded while retaining later-ID roles")
	check(model.context(many,snapshot,{"combat_sample_budget":16})["records"].size()==16,"easy difficulty retains its smaller production attention budget")
	var options:=[{"kind":"counter","accepted":true,"behavior_tags":["combatant"],"cost":{0:50},"ai_profile":candidate["ai_profile"]},{"kind":"alternative","accepted":true,"behavior_tags":["combatant"],"cost":{0:50},"ai_profile":enemy["ai_profile"]}]
	var choice:Dictionary=production.preferred_train(options,[],snapshot,{"competitive":true},state,"barracks")
	check(not choice.is_empty() and state.metrics.get("production_forecast",{}).get("hypothesis_only",false),"the real competitive production selector consumes the forecast")
	check(String(state.metrics.get("production_forecast",{}).get("kind",""))==String(choice.get("kind","")),"forecast diagnostics describe the selected unit rather than the last candidate")

func verify_screen_production() -> void:
	var production=preload("res://scripts/ai_economy_production.gd")
	var policy := {"competitive":true,"army_target":100,"scout_priority":0.0,"prefer_screen":true,"primary_producer":"archery_range"}
	var ranged := {"kind":"archer","cost":{0:60},"behavior_tags":["combatant","ranged"],"ai_profile":{"enabled":true,"max_hp":40.0,"damage":6.0,"period":1.0,"range":5.0,"speed":1.0}}
	var guard := {"kind":"clubman","cost":{0:60},"behavior_tags":["combatant","melee"],"ai_profile":{"enabled":true,"max_hp":40.0,"damage":6.0,"period":1.0,"range":0.0,"speed":1.0}}
	var chosen: Dictionary=production.preferred_train([ranged,guard],[],{"tick":0},policy,State.new(),"barracks")
	check(chosen.get("kind")=="clubman","an unmet protective screen selects an available melee unit")
	chosen=production.preferred_train([ranged],[],{"tick":0},policy,State.new(),"archery_range")
	check(chosen.get("kind")=="archer","a producer with no melee line retains a legal useful fallback")
	check(production.producer_rank("barracks",policy,20)<production.producer_rank("archery_range",policy,20),"the missing screen receives production funds before additional ranged troops")


func verify_builder_marginal_value() -> void:
	var model=preload("res://scripts/ai_builder_model.gd")
	var first:={"id":1,"arrival":0.0,"rate":1.0,"opportunity":1.0}
	var second:={"id":2,"arrival":0.0,"rate":1.0,"opportunity":1.0}
	check(is_equal_approx(model.completion_time(60.0,[first]),60.0),"one builder follows the game's additive work rule")
	check(is_equal_approx(model.completion_time(60.0,[first,second]),30.0),"parallel builders halve equal-rate construction time")
	check(is_equal_approx(model.completion_time(60.0,[first])*1.0,model.completion_time(60.0,[first,second])*2.0),"extra builder time is offset by existing builders being freed earlier")
	var late:=second.duplicate(true);late["arrival"]=100.0
	check(model.choose(60.0,[first],[late],100.0)["ids"]==[1],"a worker arriving after completion is not stolen from its task")
	var idle:=second.duplicate(true);idle["opportunity"]=0.0
	var chosen: Dictionary=model.choose(60.0,[first],[idle],0.0)
	check(chosen["ids"]==[1,2] and float(chosen["marginal_choices"][0]["income_delay_delta"])<0.0,"an idle helper releases a productive existing builder earlier")
	var idle_primary:=first.duplicate(true);idle_primary["opportunity"]=0.0
	var costly:={"id":3,"arrival":0.0,"rate":1.0,"opportunity":5.0}
	chosen=model.choose(60.0,[idle_primary],[costly,idle],0.05)
	check(chosen["ids"]==[1,2],"nonurgent construction keeps a valuable gatherer on income while accepting idle help")
	chosen=model.choose(60.0,[idle_primary],[costly],20.0)
	check(chosen["ids"]==[1,3],"enough urgency can justify the explicit lost income")
	var distant_primary:=first.duplicate(true);distant_primary["arrival"]=10.0
	chosen=model.choose(60.0,[distant_primary],[idle],2.0)
	check(chosen["ids"]==[1,2],"arrival sorting cannot change the primary command issuer order")
	check(is_equal_approx(float(chosen["completion_seconds"]),35.0),"an early helper works while the primary is still travelling")
	var delayed:=second.duplicate(true);delayed["arrival"]=10.0;delayed["travel"]=0.0;delayed["commitment_delay"]=10.0
	chosen=model.choose(60.0,[first],[delayed],0.1)
	check(chosen["ids"]==[1,2] and is_equal_approx(float(chosen["marginal_choices"][0]["income_delay_delta"]),1.0),"an existing build continues while a future helper still earns before command application")
	var pool: Array=[]
	for id in range(40):pool.append({"id":100+id,"arrival":0.0,"rate":1.0,"opportunity":0.0})
	chosen=model.choose(1000.0,[idle_primary],pool,10.0,100)
	check(chosen["ids"].size()<=model.MAX_CREW and int(chosen["candidates"])==model.MAX_CANDIDATES,"large worker counts cannot exceed crew or candidate budgets")
	var before:=var_to_bytes([first,second,pool])
	model.choose(200.0,[first],[second],2.0)
	check(var_to_bytes([first,second,pool])==before,"crew evaluation is read only")
