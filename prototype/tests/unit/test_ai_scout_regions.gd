extends SceneTree
const Operations := preload("res://scripts/ai_operations.gd")
const Strategy := preload("res://scripts/ai_strategy_state.gd")
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
	print("AI scout component boundaries passed")
	quit(0)
func actor(id: int, speed: float) -> Dictionary:
	return {"id":id,"team":1,"hp":40.0,"kind":"clubman","pos":Vector2(10.5,10.5),"movement_domain":"land","combat_enabled":true,"task":"idle","components":{"worker":{"enabled":false}},"ai_profile":{"speed":speed}}
