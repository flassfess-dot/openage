extends SceneTree
const Game := preload("res://main.gd")
const World := preload("res://scripts/simulation_world.gd")
const Renderer := preload("res://scripts/render_world.gd")
class ActorWorld extends World:
	var actors: Dictionary = {}
	func _init() -> void: super(Vector2i.ONE,true)
	func find_unit(id: int) -> Variant: return actors.get(id)
var failures: Array[String] = []
func check(condition: bool,message: String) -> void:
	if not condition: failures.append(message)
func project(point: Vector2) -> Vector2: return point*10.0
func _initialize() -> void:
	var world := ActorWorld.new()
	var game := Game.new()
	game.simulation_world=world
	game.local_player_team=1
	var own := {"id":1,"kind":"worker","team":1,"hp":100.0,"pos":Vector2(2,2),"previous_pos":Vector2(1.9,2),"movement_domain":"land"}
	var enemy := {"id":2,"kind":"worker","team":2,"hp":100.0,"pos":Vector2(3,3),"previous_pos":Vector2(2.9,3),"movement_domain":"land"}
	world.actors={1:{"team":1,"path":[Vector2(2.15,2)],"path_index":0},2:{"team":2,"path":[Vector2(3.15,3)],"path_index":0}}
	own.make_read_only();enemy.make_read_only()
	var source: Array=[own,enemy]
	source.make_read_only()
	var bounded:=game._bounded_prediction_units(source)
	check(not own.has("render_prediction_alpha_limit"),"borrowed publication stays unchanged")
	check(is_same(bounded[1],enemy) and not bounded[1].has("render_prediction_alpha_limit"),"enemy destinations are never queried/projected")
	check(absf(float(bounded[0]["render_prediction_alpha_limit"])-2.5)<0.0001,"friendly final waypoint limits extrapolation distance")
	for native in [true,false]:
		var renderer:=Renderer.new()
		if not native: renderer.native_render_kernel=null
		var snapshot: Dictionary={"tick":1,"units":[bounded[0]],"buildings":[],"resources":[]}
		var items:=renderer.create_world_drawables(snapshot,project,5.0)
		var bodies:=items.filter(func(item): return item["kind"]=="unit")
		check(bodies.size()==1 and Vector2(bodies[0]["world_anchor"]).distance_to(Vector2(2.15,2))<0.00001,"native and fallback creation stop at the intended waypoint")
		renderer.refresh_world_drawables(items,project,4.5)
		check(Vector2(bodies[0]["world_anchor"]).distance_to(Vector2(2.15,2))<0.00001,"retained refresh preserves the waypoint bound")
	world.actors[1]={"team":1,"path":[Vector2(2.1,2),Vector2(5,5)],"path_index":0}
	var unchanged:=game._bounded_prediction_units(source)
	check(is_same(unchanged,source),"intermediate route segments keep the existing interpolation contract")
	world.actors[1]={"team":1,"path":[Vector2(2.15,2)],"path_index":0,"formation_shared_motion":true}
	check(is_same(game._bounded_prediction_units(source),source),"shared formation steering retains its own presentation contract")
	world.actors[1]={"team":2,"path":[Vector2(2.15,2)],"path_index":0}
	check(is_same(game._bounded_prediction_units(source),source),"stale own rows cannot read a converted enemy's route")
	game.simulation_world=null
	world.shutdown_derived_state()
	game.free()
	for failure in failures: push_error(failure)
	print("Render prediction bounds: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
