extends SceneTree
const Policy = preload("res://scripts/skirmish_ai_policy.gd")
const Catalog = preload("res://scripts/resource_catalog.gd")
const World = preload("res://scripts/simulation_world.gd")
const Controller = preload("res://scripts/game_controller.gd")
const Commands = preload("res://scripts/commands.gd")
const Snapshot = preload("res://scripts/simulation_snapshot.gd")
const Predictor = preload("res://scripts/ai_combat_predictor.gd")
const Micro = preload("res://scripts/ai_micro_controller.gd")
const State = preload("res://scripts/ai_strategy_state.gd")
const Scheduler = preload("res://scripts/ai_action_scheduler.gd")
const Operations = preload("res://scripts/ai_operations.gd")
var rows: Array=[]

static func retained_fraction(force: Array,team: int) -> float:
	var initial:=0.0; var remaining:=0.0
	for actor in force:
		initial+=float(actor.get("max_hp",1))
		if int(actor.get("team",0))==team: remaining+=maxf(0,float(actor.get("hp",0)))
	return remaining/maxf(1,initial)

static func outcome_margin(ours: Array,enemies: Array) -> float:
	var initial_a:=0.0; var initial_b:=0.0; var a:=0.0; var b:=0.0
	for actor in ours: initial_a+=float(actor.get("max_hp",1))
	for actor in enemies: initial_b+=float(actor.get("max_hp",1))
	for actor in ours+enemies:
		if int(actor.get("team",0))==1: a+=maxf(0,float(actor.get("hp",0)))
		elif int(actor.get("team",0))==2: b+=maxf(0,float(actor.get("hp",0)))
	return a/maxf(1,initial_a)-b/maxf(1,initial_b)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.max_fps=0
	var output_path:=""; var difficulty:="standard"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path=argument.trim_prefix("--output=")
		elif argument.begins_with("--difficulty="): difficulty=argument.trim_prefix("--difficulty=")
	if output_path.is_empty() or difficulty not in ["easy","standard","hard"]: push_error("Combat acceptance needs output and valid difficulty"); quit(1); return
	var policy: Dictionary=Policy.resolve("random_map_balanced",difficulty)
	policy.merge(policy.get("competitive_parameters",{}),true)
	policy["algorithm_version"]="competitive_v2"
	var catalog=Catalog.new(); catalog.load()
	var rosters: Array=[
		["clubman","clubman"],["archer","clubman"],["hoplite","cavalry"],
		["stone_thrower","archer"],["priest","cavalry"],["scout_ship","scout_ship"],
		["catapult_trireme","scout_ship"],["slinger","archer"],
		["hoplite","clubman"],["archer","archer"],["archer","cavalry"],["clubman","slinger"]]
	var role_fixtures: bool="--role-fixtures" in OS.get_cmdline_user_args()
	if role_fixtures: rosters=[["clubman","clubman"],["clubman","clubman"]]
	for split in ["fit","heldout"]:
		if split=="heldout" and (role_fixtures or "--fit-only" in OS.get_cmdline_user_args()): continue
		for index in range(rosters.size()):
			if "--priest-diagnostic" in OS.get_cmdline_user_args() and index!=4: continue
			for micro_enabled in [false,true]:
				var world=World.new(Vector2i(40,32))
				world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
				world.task_coordinator.enabled=false
				var water: bool=index in [5,6]
				var terrain_ids: Array[int]=[]; terrain_ids.resize(40*32); terrain_ids.fill(1 if water else 0)
				var vertex_levels: Array[int]=[]; vertex_levels.resize(41*33); vertex_levels.fill(0)
				if index==9:
					for y in range(33):
						for x in range(15): vertex_levels[y*41+x]=1
				world.configure_map_data({"terrain_ids":terrain_ids,"vertex_levels":vertex_levels})
				for team in [1,2]: world.set_team_civilization(team,13)
				world.simulation_seed=(700001 if split=="fit" else 900031)+index*29
				world.simulation_rng.seed=world.simulation_seed
				for team in [1,2]: world.set_population_cap(team,100); world.set_population_housing(team,100)
				var count: int=4 if split=="fit" else 6+index%3
				var own_count:=count; var enemy_count:=count+(1 if split=="heldout" and index%2==0 else 0)
				var equal_cost: bool="--equal-cost" in OS.get_cmdline_user_args()
				if equal_cost:
					var ac:=0; var bc:=0
					for value in world.unit_resource_cost(String(rosters[index][0]),1).values(): ac+=int(value)
					for value in world.unit_resource_cost(String(rosters[index][1]),2).values(): bc+=int(value)
					var divisor:=ac; var remainder:=bc
					while remainder!=0:
						var next:=divisor%remainder; divisor=remainder; remainder=next
					var budget: int=ac*bc/maxi(1,divisor)
					budget*=mini(3,maxi(1,ceili((600.0 if split=="fit" else 900.0)/maxi(1,budget))))
					own_count=budget/maxi(1,ac); enemy_count=budget/maxi(1,bc)
				var own: Array=[]; var enemy: Array=[]
				if role_fixtures:
					var mixed := ["priest","archer","archer","stone_thrower","hoplite","hoplite","cavalry","archer"]
					for n in range(mixed.size()):
						own.append(world.add_unit(1,mixed[n],Vector2(11.5-0.8*(n%3),10.5+1.2*(n/3)),false))
						enemy.append(world.add_unit(2,mixed[n],Vector2(17.5+0.8*(n%3),10.5+1.2*(n/3)),false))
				else:
					for n in range(own_count): own.append(world.add_unit(1,"clubman" if not equal_cost and index==10 and n%2==0 else String(rosters[index][0]),Vector2(12.5,10.5+n*0.8),false))
					for n in range(enemy_count): enemy.append(world.add_unit(2,"archer" if not equal_cost and index==11 and n%2==0 else String(rosters[index][1]),Vector2(16.0+(0.2*(index%3) if split=="heldout" else 0.0),10.5+n*0.8),false))
				if index==8 or (role_fixtures and index==1):
					for y in range(5,24):
						if y not in [13,14,15,16]: world.add_building(80000+y,"wall",Vector2(14.5,y+0.5),0)
				world.update_fog_of_war()
				var controller=Controller.new(world); controller.set_speed_multiplier(1.0)
				var legal:=Snapshot.with_queries(world,0,1,{"compact_entities":true,"include_ai_profiles":true,"include_projectiles":false,"include_ai_projectiles":true,"include_scenario":false,"include_navigation":true})
				var a: Array=legal.get("units",[]).filter(func(u): return int(u.get("team",0))==1)
				var b: Array=legal.get("units",[]).filter(func(u): return int(u.get("team",0))==2)
				var prediction:=Predictor.evaluate(a,b,["attack","hold","retreat"])
				var ids1: Array[int]=[]; var ids2: Array[int]=[]
				for actor in own: ids1.append(int(actor["id"]))
				for actor in enemy: ids2.append(int(actor["id"]))
				controller.enqueue_command(Commands.AttackMoveCommand.new(0,ids1,Vector2(19,14)),true,1)
				controller.enqueue_command(Commands.AttackMoveCommand.new(0,ids2,Vector2(12,14)),true,2)
				var micro=Micro.new(); var state=State.new(); var scheduler=Scheduler.new(); var operations=Operations.new(); var rejected:=0; var issued:=0
				var rejection_reasons: Dictionary={}
				var accepted_role_orders: Dictionary={}
				var horizon: Dictionary={}
				var started:=Time.get_ticks_msec()
				while controller.tick_index<(0 if "--profiles" in OS.get_cmdline_user_args() else 1200):
					if micro_enabled and controller.tick_index%4==0:
						var snapshot:=Snapshot.with_queries(world,controller.tick_index,1,{"compact_entities":true,"include_ai_profiles":true,"include_projectiles":false,"include_ai_projectiles":true,"include_scenario":false,"include_navigation":true})
						snapshot=scheduler.react(snapshot,controller.tick_index,1,policy)
						var commands: Array=micro.plan(snapshot,controller.tick_index,1,policy,state)
						commands=scheduler.admit(commands,controller.tick_index,policy,state,operations)
						for command in commands: controller.enqueue_command(command,true,1); issued+=1
						controller.process_commands()
						for command in commands:
							var feedback: Dictionary=controller.get_command_result(command.sequence_id)
							if not bool(feedback.get("accepted",false)):
								rejected+=1
								var reason:=String(feedback.get("reason","missing_feedback"))
								rejection_reasons[reason]=int(rejection_reasons.get(reason,0))+1
							else:
								var reason:=String(command.params.get("_ai_feedback",{}).get("reason","unknown"))
								accepted_role_orders[reason]=int(accepted_role_orders.get(reason,0))+1
						micro.record_sent(commands,controller.tick_index)
					controller.advance_frame(0.05,1,2,1)
					if horizon.is_empty() and controller.tick_index>=320:
						horizon={"tick":controller.tick_index,"own_retained":retained_fraction(own,1),"enemy_retained":retained_fraction(enemy,2),"outcome_margin":outcome_margin(own,enemy)}
					if not (own+enemy).any(func(u): return int(u.get("team",0))==1 and float(u.get("hp",0))>0) or not (own+enemy).any(func(u): return int(u.get("team",0))==2 and float(u.get("hp",0))>0): break
				var ahp:=0.0; var bhp:=0.0; var ainitial:=0.0; var binitial:=0.0
				for actor in own: ahp+=maxf(0,float(actor.get("hp",0))); ainitial+=float(actor.get("max_hp",1))
				for actor in enemy: bhp+=maxf(0,float(actor.get("hp",0))); binitial+=float(actor.get("max_hp",1))
				var actual:=outcome_margin(own,enemy)
				if horizon.is_empty(): horizon={"tick":controller.tick_index,"own_retained":retained_fraction(own,1),"enemy_retained":retained_fraction(enemy,2),"outcome_margin":actual}
				var own_value:=0.0; var enemy_value:=0.0; var own_lost:=0.0; var enemy_lost:=0.0
				for actor in own+enemy:
					var original_team:=1 if actor in own else 2
					var cost: Dictionary=world.unit_resource_cost(String(actor.get("kind","")),original_team)
					var value:=0.0
					for amount in cost.values(): value+=float(amount)
					var lost: bool=float(actor.get("hp",0.0))<=0.0 or int(actor.get("team",0))!=original_team
					if original_team==1: own_value+=value; own_lost+=value if lost else 0.0
					else: enemy_value+=value; enemy_lost+=value if lost else 0.0
				var predicted:=float(prediction.get("attack_ratio",1.0))-1.0
				rows.append({"split":split,"scenario":index,"kinds":rosters[index],"seed":world.simulation_seed,"micro":micro_enabled,"prediction":prediction,"observed_own":a,"observed_enemy":b,"actual_margin":actual,"own_value":own_value,"enemy_value":enemy_value,"own_lost":own_lost,"enemy_lost":enemy_lost,"sign_correct":signf(actual)==signf(predicted),"ticks":controller.tick_index,"own_remaining":ahp/maxf(1,ainitial),"enemy_remaining":bhp/maxf(1,binitial),"issued":issued,"rejected":rejected,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"visible_enemies":b.size()})
				world.shutdown_derived_state()
				rows.back()["rejection_reasons"]=rejection_reasons
				rows.back()["accepted_role_orders"]=accepted_role_orders
				if role_fixtures: rows.back()["actual_roster"]=["priest","archer","archer","stone_thrower","hoplite","hoplite","cavalry","archer"]
				if role_fixtures:
					rows.back()["terminal_roster"]={"own_initial":own.map(func(actor): return {"kind":actor.get("kind",""),"team":actor.get("team",0),"hp":actor.get("hp",0.0),"task":actor.get("task","")}),"enemy_initial":enemy.map(func(actor): return {"kind":actor.get("kind",""),"team":actor.get("team",0),"hp":actor.get("hp",0.0),"task":actor.get("task","")})}
				rows.back()["horizon_16_seconds"]=horizon
				var forecast: Dictionary=prediction.get("variants",{}).get("attack",{})
				rows.back()["horizon_mean_abs_retained_hp_error"]=(absf(float(forecast.get("own_remaining",0))-float(horizon["own_retained"]))+absf(float(forecast.get("enemy_remaining",0))-float(horizon["enemy_retained"])))*0.5
				print("COMBAT ",split," ",index," micro=",micro_enabled," margin=",actual)
				await process_frame
	var held:=rows.filter(func(r): return r["split"]=="heldout" and not bool(r["micro"]))
	var correct:=held.filter(func(r): return bool(r["sign_correct"])).size()
	var report:={"schema_version":2,"rows":rows,"heldout_sign_accuracy":float(correct)/maxi(1,held.size()),"provenance":"authoritative_simulation; legal observer profiles; fit and heldout seeds disjoint; no human demonstrations; ownership-aware terminal outcome and matched16s retained-roster HP loss"}
	report["equal_cost_fixture"]="--equal-cost" in OS.get_cmdline_user_args()
	var output:="combat_profiles.json" if "--profiles" in OS.get_cmdline_user_args() else "combat_equal_cost.json" if "--equal-cost" in OS.get_cmdline_user_args() else "combat_benchmark.json"
	if "--priest-diagnostic" in OS.get_cmdline_user_args(): output="combat_priest_diagnostic.json"
	report["active_policy"]=policy
	report["difficulty"]=difficulty
	report["role_fixtures"]=role_fixtures
	if role_fixtures or "--fit-only" in OS.get_cmdline_user_args():
		report["heldout_sign_accuracy"]=null
		report["heldout_used"]=false
	report["runtime"]={"release":not OS.has_feature("editor"),"native":ClassDB.class_exists("RoRPathKernel") and ClassDB.class_exists("RoRReadModelKernel"),"executable":OS.get_executable_path()}
	report["scope"]="Controlled equal-cost module battles using the final runtime difficulty/parameters; not full-match strength or human rating"
	if role_fixtures or "--fit-only" in OS.get_cmdline_user_args(): report["scope"]="Fit-only diagnostic battles; heldout untouched; mixed mirror forces when role_fixtures=true; not final acceptance"
	var file:=FileAccess.open(output_path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	quit(0)
