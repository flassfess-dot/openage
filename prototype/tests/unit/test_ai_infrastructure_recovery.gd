extends SceneTree
const Recovery=preload("res://scripts/ai_infrastructure_recovery.gd")
class Facts extends RefCounted:
	var metrics: Dictionary={}
	var income: Dictionary={0:0.0}
	var goal: Dictionary={"type":"develop"}
var failures: Array[String]=[]
func _initialize() -> void:
	var state=Facts.new()
	var snapshot:={"tick":0,"player_state":{"age":101,"food":260}}
	var buildings: Array=[{"kind":"town_center","command_options":{"research":[{"technology_id":102,"cost":{0:800}}]}}]
	var worker:={"id":1,"pos":Vector2(20,20),"task":"gather","movement_domain":"land","carried_amount":10.0,"carried_resource_type_id":0,"components":{"worker":{"enabled":true}},"ai_profile":{"drop_site_kinds":["town_center","storage_pit"]}}
	Recovery.plan(snapshot,{},state,[worker],buildings,1.0)
	snapshot["tick"]=1200;worker["pos"]=Vector2(22,20)
	var recovered:=Recovery.plan(snapshot,{},state,[worker],buildings,1.0)
	check(recovered["goals"].has("storage_pit") and not recovered["goals"].has("granary"),"a full moving hunter needs a permitted meat drop-site, not a fruit granary")
	check(recovered["farms"],"sustained zero income requests food production")
	state.income[0]=0.4;snapshot["tick"]=1220
	check(Recovery.plan(snapshot,{},state,[worker],buildings,1.0)["farms"],"one small deposit does not prematurely cancel food recovery")
	snapshot["player_state"]["food"]=800
	check(not Recovery.plan(snapshot,{},state,[worker],buildings,1.0)["farms"],"funded reserve releases the food fallback")
	state.goal["type"]="defend"
	check(Recovery.plan(snapshot,{},state,[worker],buildings,1.0)["goals"].is_empty(),"immediate defence does not spend on new recovery infrastructure")
	state.goal["type"]="develop";worker["carried_amount"]=0
	Recovery.plan(snapshot,{},state,[worker],buildings,1.0)
	check(state.metrics["cargo_progress"].is_empty(),"completed cargo does not leave a retained recovery track")
	for failure in failures: push_error(failure)
	print("AI infrastructure recovery: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
