extends SceneTree
const Micro=preload("res://scripts/ai_micro_controller.gd")
var failures: Array[String]=[]
func reference(actor: Dictionary,target: Dictionary,snapshot: Dictionary,reach: float) -> bool:
 var domain=String(actor.get("movement_domain","land"))
 var destination=Vector2(target.get("pos",Vector2.ZERO))
 var cells: Dictionary=snapshot.get("_micro_cells",{}).get(domain,{})
 var start=Vector2i(Vector2(actor.get("pos",Vector2.ZERO)).floor())
 var visited: Dictionary={start:true};var queue: Array=[start];var cursor=0
 while cursor<queue.size() and cursor<256:
  var cell: Vector2i=queue[cursor];cursor+=1
  if (Vector2(cell)+Vector2(0.5,0.5)).distance_to(destination)<=reach+0.5:return true
  for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next=cell+delta
   if cells.has(next) and not visited.has(next):visited[next]=true;queue.append(next)
 return false
func _initialize() -> void:
 var rows: Array=[]
 for fixture in range(3):
  var cells: Dictionary={}
  for y in range(48):
   for x in range(48):
    if fixture==1 and x==16 and y not in [3,4]:continue
    if fixture==2 and (x%7==0 and y%9!=2):continue
    cells[Vector2i(x,y)]=true
  var snapshot: Dictionary={"_micro_cells":{"land":cells},"_micro_floods":{}}
  var queries: Array=[]
  for actor_id in range(16):
   var actor={"id":actor_id,"movement_domain":"land","pos":Vector2(8+actor_id%4,8+actor_id/4)}
   for target_id in range(32):
    var target={"pos":Vector2(2+target_id%8*4.0,4+target_id/8*8.0)}
    for reach in [0.9,3.5,10.0]:queries.append({"actor":actor,"target":target,"reach":reach})
  var before=Time.get_ticks_usec();var truth: Array=[]
  for q in queries:truth.append(reference(q["actor"],q["target"],snapshot,q["reach"]))
  var reference_us=Time.get_ticks_usec()-before;before=Time.get_ticks_usec();var actual: Array=[]
  for q in queries:actual.append(Micro.locally_reachable(q["actor"],q["target"],snapshot,q["reach"]))
  var candidate_us=Time.get_ticks_usec()-before
  check(actual==truth,"Exact original256-cell BFS parity fixture"+str(fixture))
  for search in snapshot["_micro_floods"].values():check(search["processed"].size()<=256,"processed cell bound")
  check(snapshot["_micro_floods"].size()<=64,"origin cache bound")
  var plain={"_micro_cells":{"land":cells}};var bytes=var_to_bytes(plain)
  Micro.locally_reachable(queries[0]["actor"],queries[0]["target"],plain,0.9)
  check(var_to_bytes(plain)==bytes,"Caller snapshot remains immutable without explicit private cache")
  rows.append({"fixture":fixture,"queries":queries.size(),"reference_us":reference_us,"candidate_us":candidate_us,"speedup":float(reference_us)/maxi(1,candidate_us),"equal":actual==truth})
  if fixture==0:
   var near: Dictionary={"_micro_cells":{"land":cells},"_micro_floods":{}}
   var actor={"movement_domain":"land","pos":Vector2(8.5,8.5)}
   check(Micro.locally_reachable(actor,{"pos":Vector2(9.5,8.5)},near,0.0),"near target found")
   check(near["_micro_floods"].values()[0]["processed"].size()<10,"short search expands lazily")
   check(not Micro.locally_reachable(actor,{"pos":Vector2(40.5,40.5)},near,0.0),"far target remains outside original bound")
   var search: Dictionary=near["_micro_floods"].values()[0]
   var queued: Vector2i=search["queue"].back()
   check(not search["processed"].has(queued),"fixture has a queued but unprocessed cell")
   check(not Micro.locally_reachable(actor,{"pos":Vector2(queued)+Vector2(0.5,0.5)},near,-0.4),"unprocessed queue does not bypass256-cell bound")
   for index in range(100):Micro.locally_reachable({"movement_domain":"land","pos":Vector2(index+100,100)},{"pos":Vector2(200,200)},near,0.0)
   check(near["_micro_floods"].size()==64,"too many origins cannot grow the cache")
   near["_micro_cells"]["water"]={}
   check(not Micro.locally_reachable({"movement_domain":"water","pos":Vector2(8.5,8.5)},{"pos":Vector2(9.5,8.5)},near,0.0),"land cache cannot supply water reachability")
   for reach in [INF,-INF,NAN]:
    check(Micro.locally_reachable(actor,{"pos":Vector2(40.5,40.5)},near,reach)==reference(actor,{"pos":Vector2(40.5,40.5)},near,reach),"non-finite reach preserves reference result without unbounded cell loops")
 var output=FileAccess.open("res://qa/ai-competitive/competitive-20261030/micro_reachability_benchmark.json",FileAccess.WRITE)
 output.store_string(JSON.stringify({"rows":rows,"failures":failures,"scope":"exact query kernel, cache creation included,4608 queries; not total game FPS"},"\t"));output.close()
 for failure in failures:push_error(failure)
 print("Micro reachability: ",failures.size()," failures;4608 parity queries")
 quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
 if not value:failures.append(message)
