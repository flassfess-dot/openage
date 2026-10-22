class_name RoRShorelineFeatures
extends RefCounted

const Terrain := preload("res://scripts/environment_terrain.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const RESOLUTION := 4
const CHUNK_LENGTH := 4.0
var data: Dictionary
var size: Vector2i
var river: Dictionary
var samples: Dictionary = {}
var crossings: Dictionary = {}
var points := PackedVector2Array()
var links: Dictionary = {}
var lake_cells: Dictionary = {}
var provider: Callable

static func decorate(map_data: Dictionary, timings: Dictionary = {}) -> void:
 var builder := RoRShorelineFeatures.new()
 builder.data=map_data;builder.size=map_data["size"]
 builder.river=map_data.get("rivers",{}).get("surface",{})
 builder.provider=builder._terrain
 for lake in map_data.get("lakes",[]):
  for cell in lake["cells"]:builder.lake_cells[int(cell)]=true
 # Rebuilding a preview or loading a decorated fixture must not duplicate it.
 map_data["scenery"]=map_data["scenery"].filter(func(item):return not item.get("shoreline_detail",false))
 var started:=Time.get_ticks_usec()
 builder._extract()
 var count:=builder._publish_paths()
 for i in range(map_data["scenery"].size()):map_data["scenery"][i]["id"]=-800000-i
 map_data["shoreline_summary"]={"features":count,"contour_points":builder.points.size()}
 timings["build_ms"]=(Time.get_ticks_usec()-started)/1000.0
 builder.provider=Callable()

func _terrain(cell: Vector2i) -> int:
 if cell.x<0 or cell.y<0 or cell.x>=size.x or cell.y>=size.y:return -1
 return int(data["terrain_ids"][cell.y*size.x+cell.x])

func _coverage(point: Vector2) -> float:
 return Terrain.surface_land_coverage(point,provider,river)

func _sample(at: Vector2i) -> float:
 if not samples.has(at):samples[at]=_coverage(Vector2(at)/RESOLUTION)
 return samples[at]

func _extract() -> void:
 for y in range(size.y):
  for x in range(size.x):
   var land:=false
   var water:=false
   for dy in range(-1,2):
    for dx in range(-1,2):
     var kind:=_terrain(Vector2i(x+dx,y+dy))
     if kind<0:continue
     if kind in [1,4,15,22]:water=true
     else:land=true
   if not land or not water:continue
   for sy in range(RESOLUTION):
    for sx in range(RESOLUTION):_square(Vector2i(x,y)*RESOLUTION+Vector2i(sx,sy))

func _square(origin: Vector2i) -> void:
 var corners: Array[Vector2i]=[origin,origin+Vector2i.RIGHT,origin+Vector2i.ONE,origin+Vector2i.DOWN]
 var mask:=0
 for i in range(4):
  if _sample(corners[i])>=0.5:mask|=1<<i
 if mask==0 or mask==15:return
 var nodes: Dictionary={}
 var edges: Array[int]=[]
 for i in range(4):
  if bool(mask&(1<<i))==bool(mask&(1<<((i+1)%4))):continue
  nodes[i]=_crossing(corners[i],corners[(i+1)%4]);edges.append(i)
 if edges.size()==2:
  _connect(nodes[edges[0]],nodes[edges[1]])
 else:
  var center_land:=_coverage((Vector2(origin)+Vector2.ONE*0.5)/RESOLUTION)>=0.5
  var pairs: Array=[[0,1],[2,3]] if (mask==5)==center_land else [[3,0],[1,2]]
  for pair in pairs:_connect(nodes[pair[0]],nodes[pair[1]])

func _crossing(a: Vector2i,b: Vector2i) -> int:
 var first:=a.min(b)
 var key:=Vector3i(first.x,first.y,1 if a.y==b.y else 0)
 if crossings.has(key):return crossings[key]
 var lo:=Vector2(a)/RESOLUTION
 var hi:=Vector2(b)/RESOLUTION
 var initial:=_sample(a)>=0.5
 # Binary coverage sampled on a coarse grid would make another staircase.
 # Refine against the exact terrain blend, including the river bed field.
 for unused in range(6):
  var middle:Vector2=(lo+hi)*0.5
  if (_coverage(middle)>=0.5)==initial:lo=middle
  else:hi=middle
 var index:=points.size()
 points.append((lo+hi)*0.5);links[index]=[];crossings[key]=index
 return index

func _connect(a: int,b: int) -> void:
 var middle:Vector2=(points[a]+points[b])*0.5
 if middle.x<0.4 or middle.y<0.4 or middle.x>size.x-0.4 or middle.y>size.y-0.4:return
 for fall in data.get("rivers",{}).get("waterfalls",[]):
  if middle.distance_to(fall["position"])<float(fall["radius"])+2.5:return
 # Keep the accepted sandy-islet composition of exposed point bars.
 var field:=Surface.sample(river,middle)
 if field.y>0.9 and field.x>0.25 and field.z<0.10:return
 links[a].append(b);links[b].append(a)

func _publish_paths() -> int:
 var visited: Dictionary={}
 var order: Array=links.keys()
 order.sort_custom(func(a,b):return links[a].size()<links[b].size())
 var count:=0
 for first in order:
  for adjacent in links[first]:
   if visited.has(Vector2i(mini(first,adjacent),maxi(first,adjacent))):continue
   var path:=PackedVector2Array([points[first]])
   var current:int=first
   var next:int=adjacent
   while true:
    visited[Vector2i(mini(current,next),maxi(current,next))]=true
    path.append(points[next]);current=next;next=-1
    for candidate in links[current]:
     if not visited.has(Vector2i(mini(current,candidate),maxi(current,candidate))):next=candidate;break
    if next<0:break
   if path.size()<3:continue
   count+=_chunks(path)
 return count

func _chunks(path: PackedVector2Array) -> int:
 var distances:=PackedFloat32Array([0.0])
 for i in range(1,path.size()):distances.append(distances[-1]+path[i].distance_to(path[i-1]))
 if distances[-1]<0.4:return 0
 var closed:=path[0].distance_to(path[-1])<0.01
 var start:=0
 var count:=0
 for i in range(1,path.size()):
  if distances[i]-distances[start]<CHUNK_LENGTH and i<path.size()-1:continue
  var center:Vector2=path[(start+i)/2]
  var normals:=PackedVector2Array()
  var heights:=PackedFloat32Array()
  var opacity:=PackedFloat32Array()
  var marine_weights:=PackedFloat32Array()
  for j in range(start,i+1):
   var point:=path[j]
   var gradient:=Vector2(_coverage(point+Vector2(0.04,0))-_coverage(point-Vector2(0.04,0)),_coverage(point+Vector2(0,0.04))-_coverage(point-Vector2(0,0.04)))
   var normal:=gradient.normalized()
   normals.append(normal)
   for offset in [-0.18,0.42]:heights.append(_height(point+normal*offset))
   opacity.append(1.0 if closed else smoothstep(0.0,0.35,distances[j])*smoothstep(0.0,0.35,distances[-1]-distances[j]))
   marine_weights.append(_marine_weight(point))
  var form:Dictionary={"points":path.slice(start,i+1),"distances":distances.slice(start,i+1),"normals":normals,"heights":heights,"opacity":opacity,
   "marine":_marine_weight(center)>=0.5,"marine_weights":marine_weights,"anchor_height":_height(center)}
  var bounds:=Rect2(path[start],Vector2.ZERO)
  for j in range(start,i+1):bounds=bounds.expand(path[j])
  bounds=bounds.grow(0.65)
  data["scenery"].append({"id":-950000-count-data["scenery"].size(),"asset_name":"ror_shoreline","position":center,
   "source_frame":0,
   "shoreline_detail":true,"shore_form":form,"presentation_layer":"terrain_detail","decoration_key":"ror_shoreline","source_game":"ror",
   "feature_family":"ror_shoreline","ecology_role":"marine_waterline" if form["marine"] else "fresh_waterline","ambient":true,"route_id":-1,
   "presentation_bounds":[bounds.position.x-center.x,bounds.position.y-center.y,bounds.end.x-center.x,bounds.end.y-center.y]})
  start=i;count+=1
 return count

func _height(point: Vector2) -> float:
 var cell:=Vector2i(point.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
 var fraction:=point-Vector2(cell)
 var at:=cell.y*(size.x+1)+cell.x
 var levels:Array=data["vertex_levels"]
 return lerpf(lerpf(levels[at],levels[at+1],fraction.x),lerpf(levels[at+size.x+1],levels[at+size.x+2],fraction.x),fraction.y)

func _marine_weight(point: Vector2) -> float:
 var cell:=Vector2i(point.floor())
 var sea:=0.0
 var total:=0.0
 var rivers:Dictionary=data.get("rivers",{})
 for dy in range(-2,3):
  for dx in range(-2,3):
   var at:=cell+Vector2i(dx,dy)
   if _terrain(at) not in [1,4,15,22]:continue
   var distance:float=point.distance_squared_to(Vector2(at)+Vector2.ONE*0.5)
   if distance>6.25:continue
   var weight:float=(1.0-smoothstep(2.25,6.25,distance))/(0.3+distance)
   total+=weight
   var index:=at.y*size.x+at.x
   if not lake_cells.has(index) and (not rivers.has("mask") or rivers["mask"][index]==0 or rivers["mouth_mask"][index]!=0):sea+=weight
 return smoothstep(0.25,0.75,sea/total) if total>0.0 else 0.0
