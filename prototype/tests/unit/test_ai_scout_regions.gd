extends SceneTree
const Operations := preload("res://scripts/ai_operations.gd")
const Strategy := preload("res://scripts/ai_strategy_state.gd")
class ScoutFacts extends RefCounted:
	var goal:Dictionary={"type":"explore"}
	var metrics:Dictionary={"decisions":0}
	var scout_visits:Dictionary={}
	var actors:Array=[]
	var risky:=false
	func enemies(_tick:int,_policy:Dictionary) -> Array:return actors
	func danger(point:Vector2,_tick:int,_policy:Dictionary,_domain:String="land") -> float:return 100.0 if risky and point.y>12.0 else 0.0
func _initialize() -> void:
	var operations := Operations.new()
	var state := Strategy.new()
	state.goal = {"type":"explore"}
	var isolated := actor(1, 2.0)
	var explorer := actor(2, 1.0)
	var snapshot := {"navigation":{"unit_regions":{1:"pocket",2:"main"}, "frontier_by_region":{"main":[Vector2(20.5,20.5)]}, "reachable_frontier":{"land":[Vector2(20.5,20.5)]}}}
	var orders: Array = operations._scout(snapshot, 100, 1, [isolated, explorer], {}, state, {})
	if orders.size() != 1 or orders[0].unit_ids != [2]:
		push_error("scouting must select a fighter with a frontier in its own component")
		quit(1)
		return
	operations.scouts["land"] = {"id":1,"target":Vector2.ZERO,"order_tick":-1}
	if not operations._scout(snapshot, 300, 1, [isolated], {}, state, {}).is_empty():
		push_error("an isolated retained scout must not use another component's frontier")
		quit(1)
		return
	if not verify_information():quit(1);return
	print("AI scout component boundaries and decision information passed")
	quit(0)
func actor(id: int, speed: float) -> Dictionary:
	return {"id":id,"team":1,"hp":40.0,"kind":"clubman","pos":Vector2(10.5,10.5),"movement_domain":"land","combat_enabled":true,"task":"idle","components":{"worker":{"enabled":false}},"ai_profile":{"speed":speed}}

func verify_information() -> bool:
	var model:=preload("res://scripts/ai_scout_information.gd")
	var facts:=ScoutFacts.new()
	var old:=Vector2(14.5,10.5)
	var route:=Vector2(10.5,14.5)
	facts.goal={"type":"attack","expansion_position":Vector2(25,25)}
	facts.actors=[{"id":50,"kind":"clubman","observed":false,"confidence":0.0,"pos":old,"movement_domain":"land","route_area":{"points":[route]}}]
	var snapshot:={"tick":100,"observer_team":1,"player_state":{"food":0},"resources":[{"id":60,"resource_type_id":0,"amount":500,"pos":Vector2(20,20)}],"navigation":{"unit_regions":{1:"main"},"frontier_by_region":{"main":[old,route]},"reachable_frontier":{"land":[old,route]}}}
	var before:=var_to_bytes([snapshot,facts.actors])
	var policy:={"competitive":true,"minimum_attack_group_size":0,"desired_stock":{0:150}}
	var operations:=Operations.new()
	var orders:Array=operations._scout(snapshot,100,1,[actor(1,1.0)],policy,facts,{})
	if orders.size()!=1 or Vector2(orders[0].params["target"])!=route or String(operations.scouts["land"]["information"]["decision"])!="army":push_error("scout did not use the possible enemy route for its attack decision");return false
	if var_to_bytes([snapshot,facts.actors])!=before:push_error("scout information ranking changed its legal input");return false
	var questions:Array=model.interests(snapshot,facts,policy,facts.actors)
	if questions.size()>model.MAX_INTERESTS or not questions.any(func(q):return String(q["decision"])=="resource") or not questions.any(func(q):return String(q["decision"])=="expansion"):push_error("resource or expansion information request missing");return false
	facts.risky=true
	orders=Operations.new()._scout(snapshot,300,1,[actor(1,1.0)],policy,facts,{})
	if orders.size()!=1 or Vector2(orders[0].params["target"])!=old:push_error("scout information gain bypassed its danger ceiling");return false
	var distant:Dictionary=model.evaluate(route,Vector2(100,100),1.0,"land",questions,1000)
	var near:Dictionary=model.evaluate(route,Vector2(10,10),1.0,"land",questions,1000)
	if float(near["value"])<=float(distant["value"]) or float(model.evaluate(route,Vector2(10,10),1.0,"land",questions,0)["value"])!=0.0:push_error("scout information omitted travel time or recent-visit cost");return false
	return true
