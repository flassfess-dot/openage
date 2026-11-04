extends SceneTree
const Economy := preload("res://scripts/simulation_economy_system.gd")
const Belief := preload("res://scripts/ai_belief_model.gd")
const Projectile := preload("res://scripts/ai_projectile_observation.gd")
const State := preload("res://scripts/ai_strategy_state.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var economy := Economy.new(); economy.reset(200,200)
	economy.change_resource_amount(1,0,10,"income")
	economy.spend(1,{0:50}); economy.refund(1,{0:20}); economy.change_resource_amount(1,0,75)
	check(economy.get_resource_amount(1,0)==255,"ordinary stock arithmetic preserved")
	check(economy.resource_ledger_by_team[1]["income"][0]==10,"refund/tribute cannot be counted as gathered income")
	check(economy.resource_ledger_by_team[1]["spent"][0]==50,"spending exactly once")
	economy.change_resource_amount(1,0,-5,"repair"); economy.change_resource_amount(1,0,15,"trade_in"); economy.change_resource_amount(1,0,20,"tribute_in")
	check(economy.resource_ledger_by_team[1]["income"][0]==10 and economy.resource_ledger_by_team[1]["spent"][0]==55,"repair/trade/tribute cannot inflate gathering income")
	check(economy.resource_ledger_by_team[1]["categories"]["repair"][0]==5 and economy.resource_ledger_by_team[1]["categories"]["tribute_in"][0]==20,"expense and transfer categories preserve their exact applied amount")
	var enemy := {"id":10,"team":2,"hp":600.0,"pos":Vector2(10,10),"entity_type":"building","kind":"town_center","movement_domain":"static"}
	var state := State.new()
	var snapshot := {"tick":0,"observer_team":1,"player_state":{"allies":[1]},"buildings":[enemy],"units":[]}
	check(not Projectile.project({"team":2,"source_id":900,"pos":Vector2.ONE},1).has("source_id"),"foreign projectile does not reveal unseen shooter ID")
	var crowded_projectiles: Array=[{"id":1,"team":2,"pos":Vector2(10,10),"velocity":Vector2.ONE}]
	for id in range(2,1100): crowded_projectiles.append({"id":id,"team":2,"pos":Vector2(80,80),"velocity":Vector2.ONE})
	var selected:=Projectile.select_visible(crowded_projectiles,[{"team":1,"pos":Vector2(10,10)}],1)
	check(selected.size()==1024 and int(selected[0]["id"])==1,"old nearby incoming shell survives bounded projectile attention")
	var policy := {"competitive":true,"memory_ticks":1200}
	state.observe(snapshot,1,policy)
	snapshot["tick"]=2400; snapshot["buildings"]=[]
	state.observe(snapshot,1,policy)
	check(state.memory.has(10),"static base remains remembered beyond mobile lifetime")
	check(state.enemies(2400,policy)[0]["confidence"]>0.5,"static confidence persists without hidden lookup")
	snapshot["ai_visible_memory_locations"]={10:true}; snapshot["tick"]=2420
	state.observe(snapshot,1,policy)
	check(not state.memory.has(10),"negative visible observation disproves static memory")
	var entry := {"observed":false,"seen_tick":0,"entity":{"movement_domain":"land","ai_profile":{"speed":2.0}}}
	check(Belief.uncertainty(entry,200)==20.0,"mobile uncertainty expands with elapsed time and speed")
	verify_route_hypotheses()
	verify_origin_revisit()
	var hidden := Projectile.project({"id":1,"team":2,"pos":Vector2(4,4),"previous_pos":Vector2(3,4),"target_id":999,"accurate":true,"accuracy_roll":7,"target_position":Vector2(20,20),"damage":80},1)
	check(not hidden.has("target_id") and not hidden.has("accurate") and not hidden.has("target_position") and not hidden.has("damage"),"foreign future aim/hit/damage excluded")
	check(hidden["velocity"]==Vector2(20,0),"velocity derived only from observed movement")
	var saved := state.canonical_state(); var restored := State.new()
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"legal knowledge survives exact round trip")
	var crowded:={"tick":0,"units":[],"buildings":[],"observer_team":1,"player_state":{"allies":[1]}}
	for id in range(1200): crowded["units"].append({"id":100+id,"team":2,"hp":40.0,"pos":Vector2(10+id%8,10+id/150),"kind":"clubman","movement_domain":"land","ai_profile":{"speed":1.0}})
	var bounded=State.new(); var bounded_policy:={"competitive":true,"maximum_enemy_memory":1024,"memory_ticks":1200}
	bounded.observe(crowded,1,bounded_policy)
	check(bounded.memory.size()==1024 and not bounded.belief_regions.is_empty() and bounded.belief_regions.size()<=256,"eviction retains bounded regional hypotheses")
	var mass: int=bounded.memory.size()
	for region in bounded.belief_regions.values(): mass+=int(region["count"])
	check(mass==1200,"first crowded observation preserves army mass")
	var bounded_copy=State.new()
	check(bounded_copy.restore_state(bounded.canonical_state()) and bounded_copy.canonical_state()==bounded.canonical_state(),"regional hypotheses survive exact save")
	for failure in failures: push_error(failure)
	print("Competitive legal knowledge: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value: failures.append(message)

func verify_origin_revisit() -> void:
	var policy:={"competitive":true,"memory_ticks":1200}
	var actor:={"id":10,"team":2,"hp":80.0,"kind":"scout","pos":Vector2(2.5,2.5),"movement_domain":"land","ai_profile":{"speed":1.0}}
	var snapshot:={"tick":0,"observer_team":1,"player_state":{"allies":[1]},"units":[actor],"buildings":[],"navigation":route_navigation(8,8)}
	var state:=State.new()
	state.observe(snapshot,1,policy)
	snapshot["tick"]=40;snapshot["units"]=[];snapshot["ai_visible_memory_locations"]={10:true}
	state.observe(snapshot,1,policy)
	check(Vector2(actor["pos"]) not in state.memory[10]["route_area"]["points"],"a currently visible empty origin is excluded")
	var saved:=state.canonical_state()
	var restored:=State.new()
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"negative observation survives exact save before further reasoning")
	snapshot["tick"]=60;snapshot.erase("ai_visible_memory_locations")
	state.observe(snapshot,1,policy);restored.observe(snapshot,1,policy)
	check(Vector2(actor["pos"]) in state.memory[10]["route_area"]["points"],"an old empty observation must not permanently exclude a mobile enemy's return after fog comes back")
	check(int(state.memory[10]["seen_tick"])==0 and float(state.memory[10]["entity"]["hp"])==80.0,"allowing a possible return cannot refresh the unseen enemy")
	check(state.canonical_state()==restored.canonical_state(),"possible return reasoning remains deterministic after restore")
	check(int(state.memory[10]["origin_disproved_tick"])==40,"hidden time passing cannot refresh the negative observation either")
	var older:=saved.duplicate(true)
	older["memory"][0]["value"].erase("origin_disproved_tick")
	var old_restore:=State.new()
	check(old_restore.restore_state(older) and old_restore.canonical_state()==older,"older optional-negative-field states restore without adding new fields")
	old_restore.observe(snapshot,1,policy)
	check(Vector2(actor["pos"]) in old_restore.memory[10]["route_area"]["points"],"an old boolean with unknown evidence age cannot permanently exclude a return")
	for invalid in [-1,41,39.5,INF]:
		var bad:=saved.duplicate(true)
		bad["memory"][0]["value"]["origin_disproved_tick"]=invalid
		check(not State.new().restore_state(bad),"invalid negative-observation timestamp is rejected")
	var contradictory:=saved.duplicate(true)
	contradictory["memory"][0]["value"]["origin_disproved"]=false
	check(not State.new().restore_state(contradictory),"negative timestamp requires matching negative evidence")
	snapshot["tick"]=61;snapshot["ai_visible_memory_locations"]={10:true}
	state.observe(snapshot,1,policy)
	check(Vector2(actor["pos"]) not in state.memory[10]["route_area"]["points"] and int(state.memory[10]["origin_disproved_tick"])==61,"new legal empty observation excludes the origin again")


func route_navigation(width: int, height: int, wall_x: int = -1) -> Dictionary:
	var land: Array[Vector2]=[]
	for y in range(height):
		for x in range(width):
			if x!=wall_x: land.append(Vector2(x+0.5,y+0.5))
	return {"cell_geometry":true,"land":land,"water":[],"frontier":{"land":[],"water":[]}}


func verify_route_hypotheses() -> void:
	var policy:={"competitive":true,"memory_ticks":1200,"maximum_enemy_memory":256}
	var actor:={"id":10,"team":2,"hp":80.0,"kind":"scout","pos":Vector2(1.5,2.5),"movement_domain":"land","ai_profile":{"speed":1.0}}
	var snapshot:={"tick":0,"observer_team":1,"player_state":{"allies":[1]},"units":[actor],"buildings":[],"navigation":route_navigation(8,5,3)}
	var state:=State.new()
	state.observe(snapshot,1,policy)
	snapshot["tick"]=200
	snapshot["units"]=[]
	snapshot["ai_visible_memory_locations"]={10:true}
	state.observe(snapshot,1,policy)
	check(state.memory.has(10),"empty former cell does not prove a mobile enemy is dead")
	if not state.memory.has(10): return
	check(int(state.memory[10]["seen_tick"])==0 and float(state.memory[10]["entity"]["hp"])==80.0,"route inference cannot refresh hidden age or health")
	var area: Dictionary=state.memory[10].get("route_area",{})
	check(not area.is_empty() and area["points"].size()>1,"stale mobile enemy has a known-route hypothesis")
	if area.is_empty(): return
	check(area["points"].all(func(p):return p.x<3.0) and Vector2(2.5,2.5) in area["points"],"known solid wall separates route hypotheses inside the same distance radius")
	check(Vector2(1.5,2.5) not in area["points"] and bool(area["hypothesis_only"]),"disproved origin is excluded without claiming certainty about unseen routes")
	var saved:=state.canonical_state()
	var restored:=State.new()
	check(restored.restore_state(saved) and restored.canonical_state()==saved,"route hypotheses and rotation survive exact save")
	var exposed: Array=state.enemies(200,policy)
	exposed[0]["route_area"]["points"][0]=Vector2(900,900)
	check(state.canonical_state()==saved,"returned route area cannot mutate persistent memory")
	var malformed:=saved.duplicate(true)
	malformed["memory"][0]["value"]["route_area"]["points"].resize(Belief.MAX_ROUTE_CELLS+1)
	check(not State.new().restore_state(malformed),"oversized route hypothesis is rejected")
	malformed=saved.duplicate(true)
	malformed["memory"][0]["value"]["route_area"]["tick"]=50000
	check(not State.new().restore_state(malformed),"future route timestamp is rejected")
	var navigation: Dictionary=snapshot["navigation"]
	navigation["frontier"]["land"]=[Vector2(0.5,0.5)]
	check(bool(Belief.route_area(state.memory[10],200,navigation)["unknown_exit"]),"a reachable unexplored exit remains explicit uncertainty")
	var water_entry:={"entity":actor.duplicate(true),"observed":false,"seen_tick":0}
	water_entry["entity"]["movement_domain"]="water"
	navigation["water"]=[Vector2(0.5,2.5),Vector2(1.5,2.5),Vector2(2.5,2.5)]
	var water:=Belief.route_area(water_entry,200,navigation)
	check(water["points"].all(func(p):return p.y==2.5 and p.x<=2.5),"water hypotheses use known water rather than adjacent land")
	var large:=route_navigation(400,400)
	var large_entry:={"entity":actor.duplicate(true),"observed":false,"seen_tick":0}
	large_entry["entity"]["pos"]=Vector2(200.5,200.5)
	var bounded:=Belief.route_area(large_entry,2000,large)
	check(int(bounded["expanded"])<=Belief.MAX_ROUTE_CELLS and bounded["points"].size()<=Belief.MAX_ROUTE_CELLS and bool(bounded["truncated"]),"large-map route search reports its finite limit")
	check(int(bounded["membership_queries"])<=Belief.MAX_ROUTE_CELLS*12,"route search queries a bounded neighbourhood rather than reindexing the explored map")
	var crowd:={"tick":0,"observer_team":1,"player_state":{"allies":[1]},"units":[],"buildings":[],"navigation":route_navigation(32,32)}
	for id in range(40):
		var enemy: Dictionary=actor.duplicate(true)
		enemy["id"]=100+id
		enemy["pos"]=Vector2(8.5+id%5,8.5+id/5)
		crowd["units"].append(enemy)
	var many:=State.new()
	many.observe(crowd,1,policy)
	crowd["units"]=[]
	for iteration in range(10):
		crowd["tick"]=200+iteration*20
		many.observe(crowd,1,policy)
		var fresh:=0
		var retained:=0
		for memory in many.memory.values():
			if not memory.get("route_area",{}).is_empty():
				retained+=1
				if int(memory["route_area"]["tick"])==int(crowd["tick"]): fresh+=1
		check(fresh<=Belief.ROUTES_PER_OBSERVATION and retained<=Belief.MAX_ROUTE_HYPOTHESES,"army-size growth cannot exceed route work/storage budgets")
	var copy:=State.new()
	check(copy.restore_state(many.canonical_state()),"rotating route scheduler restores")
	crowd["tick"]+=20
	many.observe(crowd,1,policy)
	copy.observe(crowd,1,policy)
	check(copy.canonical_state()==many.canonical_state(),"save resume cannot change the next bounded route attention")
	snapshot["tick"]=1201
	state.observe(snapshot,1,policy)
	check(not state.memory.has(10),"mobile route inference cannot extend memory lifetime")
	var legacy:=State.new()
	snapshot["tick"]=0;snapshot["units"]=[actor];snapshot.erase("ai_visible_memory_locations")
	legacy.observe(snapshot,1,{"memory_ticks":1200})
	snapshot["tick"]=200;snapshot["units"]=[];snapshot["ai_visible_memory_locations"]={10:true}
	legacy.observe(snapshot,1,{"memory_ticks":1200})
	check(not legacy.memory.has(10) and not legacy.metrics.has("belief_route_cursor"),"ordinary legacy memory retains its existing contract")
