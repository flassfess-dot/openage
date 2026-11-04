extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
const Factory=preload("res://scripts/ai_player_factory.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const Brain=preload("res://scripts/ai_competitive_controller.gd")
var failures: Array[String]=[]
class GuardFacts extends RefCounted:
 var goal: Dictionary={"type":"explore","home":Vector2(8.5,8.5)}
 var calls:=0
 func danger(_position: Vector2,_tick: int,_policy: Dictionary,_domain: String="land") -> float:
  calls+=1;return 100.0
func _initialize() -> void:
 var facts=GuardFacts.new()
 var hostile={"id":900,"team":2,"hp":100000.0,"pos":Vector2(9.5,8.5),"combat_enabled":true,"ai_profile":{"enabled":true,"range":0.0},"target_domains":["land"]}
 for variant in ["quiet","remembered","passive","ally","distant"]:
  var row=hostile.duplicate(true)
  if variant=="remembered":row["last_known"]=true
  if variant=="passive":row["combat_enabled"]=false
  if variant=="distant":row["pos"]=Vector2(28.5,28.5)
  var snapshot={"tick":12,"units":[] if variant=="quiet" else [row],"buildings":[],"player_state":{"allies":[1,2] if variant=="ally" else [1]}}
  check(not Brain.urgent_defense(snapshot,1,{},facts),"no urgent strategy for "+variant)
 check(facts.calls==0,"quiet, passive and remembered rows do not rebuild threat facts")
 check(Brain.urgent_defense({"tick":12,"units":[hostile],"buildings":[],"player_state":{"allies":[1]}},1,{},facts),"eligible visible danger wakes strategy")
 facts.calls=0
 var remote=hostile.duplicate(true);remote["pos"]=Vector2(24.5,25.5)
 check(Brain.urgent_defense({"tick":12,"units":[remote],"buildings":[{"team":1,"kind":"town_center","hp":600.0,"pos":Vector2(24.5,24.5)}],"player_state":{"allies":[1]}},1,{},facts),"an owned secondary town center receives urgent defense")
 var catalog=Catalog.new();catalog.load()
 var world=World.new(Vector2i(32,32))
 world.set_gamespec(catalog.gamespec_data);world.set_object_catalog(catalog.object_catalog_data);world.set_graphics_catalog(catalog.graphics_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
 for team in [1,2]:
  world.set_team_civilization(team,13);world.set_population_cap(team,50);world.set_population_housing(team,50)
 world.add_building(500,"town_center",Vector2(8.5,8.5),1)
 for index in range(12):world.add_unit(1,"villager",Vector2(4.5+index%4,4.5+floori(index/4.0)),false)
 world.set_resource_amount(1,0,300);world.set_resource_amount(1,1,800)
 world.update_fog_of_war()
 world.task_coordinator.enabled=false
 var controller=Controller.new(world);var store=Store.new()
 var policy: Dictionary=Policy.resolve("random_map_balanced","standard")
 policy.merge(policy["competitive_parameters"],true);policy["algorithm_version"]="competitive_v2";policy["style"]="fast_age"
 var ai=Factory.create({"team":1,"ai":policy})
 ai.collect_commands(observe(store,world,0),0)
 check(String(ai.strategy.goal.get("type",""))!="defend","initial peaceful plan")
 check(not ai.strategy.metrics.get("age_reservation",{}).is_empty(),"fixture has an active paid-age saving commitment")
 for index in range(8):world.add_unit(2,"clubman",Vector2(10.5+(index%4)*0.8,8.5+floori(index/4.0)*0.8),false)
 world.update_fog_of_war()
 var rows: Array=[]
 var resumed=null
 for tick in range(1,101):
  controller.advance_frame(0.05,1,2,1)
  check(controller.tick_index==tick,"fixture advances actual fixed tick")
  if tick%4!=0:continue
  var snapshot: Dictionary=observe(store,world,tick)
  var commands: Array=ai.collect_commands(snapshot,tick)
  rows.append({"tick":tick,"actual_tick":controller.tick_index,"goal":ai.strategy.goal.get("type",""),"strategy_tick":ai.competitive_controller.last_strategy_tick,"pending_refresh":ai.strategy.metrics.get("pending_defense_refresh",false),"rally":ai.strategy.goal.get("defense_rally",false),"needs_transport":ai.strategy.goal.get("needs_transport",false),"danger":ai.strategy.danger(Vector2(8.5,8.5),tick,ai.economic_policy),"reservation":ai.strategy.metrics.get("age_reservation",{}).duplicate(true)})
  if tick<12:check(String(ai.strategy.goal.get("type",""))!="defend","new threat obeys8-tick human reaction delay")
  if tick==12:
   check(String(ai.strategy.goal.get("type",""))=="defend","observed raid preempts80-tick strategic cadence on next legal decision")
   check(bool(ai.strategy.goal.get("defense_rally",false)) and not bool(ai.strategy.goal.get("needs_transport",true)),"compact reaction rallies home without inventing a sea crossing")
   check(bool(ai.strategy.metrics.get("pending_defense_refresh",false)),"urgent tactical plan requests one full refresh")
   check(not ai.planning_metrics.has("policy"),"rare economic timings are not repeated on tactical calls")
  if tick==16:
   var saved: Dictionary=ai.canonical_state();resumed=Factory.create({"team":1,"ai":policy})
   check(resumed.restore_state(saved),"save restores an urgent plan waiting for full context")
   var partial: Dictionary=saved.duplicate(true);partial["adaptive_strategy"]["metrics"].erase("pending_defense_refresh")
   check(not Factory.create({"team":1,"ai":policy}).restore_state(partial),"partial urgent control state is rejected")
   partial=saved.duplicate(true);partial.erase("adaptive_strategy")
   check(not Factory.create({"team":1,"ai":policy}).restore_state(partial),"missing competitive strategy cannot bypass pending-plan validation")
  if tick==20:
   check(not ai.strategy.goal.has("defense_rally") and not ai.strategy.metrics.has("pending_defense_refresh"),"next full snapshot refines and clears the urgent rally")
   check(not bool(ai.strategy.goal.get("needs_transport",true)),"full land context confirms no transport is needed")
   if resumed!=null:
    var restored_commands: Array=resumed.collect_commands(snapshot.duplicate(true),tick)
    check(resumed.canonical_state()==ai.canonical_state() and records(restored_commands)==records(commands),"urgent save continuation preserves state and commands at full refresh")
  if tick==100:check(ai.competitive_controller.last_strategy_tick==100,"periodic strategy remains aligned with economic captures")
 check(String(ai.strategy.goal.get("type",""))=="defend","defensive commitment remains active")
 check(ai.strategy.metrics.get("age_reservation",{}).is_empty(),"next economic boundary releases age fund for defense")
 DirAccess.make_dir_recursive_absolute("res://qa/ai-competitive/competitive-20261030")
 var file=FileAccess.open("res://qa/ai-competitive/competitive-20261030/urgent_defense.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"rows":rows,"failures":failures,"scope":"actual world/normal controller ticks/visibility/reacted observations; no hidden enemy order data"},"\t"));file.close()
 for failure in failures:push_error(failure)
 controller.set_before_fixed_tick(Callable());world.shutdown_derived_state()
 print("Urgent AI defense: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
func observe(store,world,tick: int) -> Dictionary:
 return store.observe_with_queries(world,tick,1,{"compact_entities":true,"include_ai_profiles":true,"include_projectiles":false,"include_scenario":false,"include_navigation":tick%20==0,"tactical_only":tick%20!=0,"include_worker_command_options":tick%20==0,"economic_production_options_only":true,"planning_technology_ids":[101,102,103]})
func check(value: bool,message: String) -> void:
 if not value:failures.append(message)

func records(commands: Array) -> Array:
 var rows: Array=[]
 for command in commands:rows.append({"type":command.command_type(),"units":command.unit_ids,"params":command.params.duplicate(true)})
 return rows
