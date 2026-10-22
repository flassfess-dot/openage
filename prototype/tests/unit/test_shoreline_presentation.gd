extends SceneTree
const Terrain := preload("res://scripts/environment_terrain.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Features := preload("res://scripts/shoreline_features.gd")
const Presentation := preload("res://scripts/shoreline_presentation.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Examples := preload("res://tests/fixtures/river_landscape_examples.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
var failures:Array[String]=[]
func _initialize() -> void:
 var catalog:=Catalog.new();catalog.load()
 check(catalog.enable_environment_pack(),"native shore artwork loads completely")
 for mask in range(16):
  var size:=Vector2i(4,4)
  var terrain:Array[int]=[];terrain.resize(16)
  for y in range(4):
   for x in range(4):
    var quadrant:=0 if x<2 and y<2 else 1 if y<2 else 2 if x>=2 else 3
    terrain[y*4+x]=6 if mask&(1<<quadrant) else 1
  var levels:Array[int]=[];levels.resize(25)
  var data:Dictionary={"size":size,"terrain_ids":terrain,"vertex_levels":levels,"resources":[],"scenery":[],"rivers":{},"lakes":[]}
  var original:=data.duplicate(true)
  var provider:=func(cell):return -1 if cell.x<0 or cell.y<0 or cell.x>=4 or cell.y>=4 else terrain[cell.y*4+cell.x]
  for y in range(33):
   for x in range(33):_parity(Vector2(x,y)/8.0,provider,{})
  Features.decorate(data)
  for key in ["terrain_ids","vertex_levels","resources","rivers"]:check(data[key]==original[key],"shore presentation preserves "+key)
  if mask!=0 and mask!=15:check(not data["scenery"].is_empty(),"all marching-square orientations retain the shore: "+str(mask))
  _features(data,catalog,provider)
  var once:=data.duplicate(true);Features.decorate(data)
  check(data==once,"decorating a fixture twice is deterministic and idempotent")
 for kind in ["bend","ford","waterfall"]:
  var data:Dictionary=Examples.build(kind)["map_data"]
  var size:Vector2i=data["size"]
  var provider:=func(cell):return -1 if cell.x<0 or cell.y<0 or cell.x>=size.x or cell.y>=size.y else data["terrain_ids"][cell.y*size.x+cell.x]
  var original:=data.duplicate(true)
  Features.decorate(data)
  _features(data,catalog,provider)
  for key in ["terrain_ids","vertex_levels","resources","rivers","fords","cliff_cells"]:check(data[key]==original[key],"native ribbon preserves actual river geography: "+key)
  for item in data["scenery"]:
   var points:PackedVector2Array=item["shore_form"]["points"]
   for i in range(1,points.size()):
    for fall in data["rivers"]["waterfalls"]:check(((points[i]+points[i-1])*0.5).distance_to(fall["position"])>=float(fall["radius"])+2.49,"waterline cannot paint across an accepted waterfall or its rock caps")
  for y in range(20,33):
   for x in range(20,37):_parity(Vector2(x,y)+Vector2(0.123,0.217),provider,data["rivers"]["surface"])
 _cache_reuse()
 for failure in failures:push_error(failure)
 print("Native shore: 16 contour cases, exact blend parity, connected strips, UV seams, depth layers, deterministic rebuild and unchanged geography; %d failures"%failures.size())
 quit(0 if failures.is_empty() else 1)
func _parity(point:Vector2,provider:Callable,river:Dictionary) -> void:
 var weights:=Terrain.weights(point,provider,null,0)
 if not river.is_empty():weights=Surface.blend(weights,Surface.sample(river,point))
 var expected:=0.0
 for id in weights:
  if id not in [1,4,15,22]:expected+=weights[id]
 check(absf(expected-Terrain.surface_land_coverage(point,provider,river))<0.000001,"numeric contour matches the rendered terrain blend")
func _features(data:Dictionary,catalog,provider:Callable) -> void:
 for item in data["scenery"]:
  check(RenderWorld.environment_layer(item)==RenderItem.Layer.TERRAIN and not item.has("occupied_cells"),"shore ribbons sit below islets and units without blocking paths")
  var info:Dictionary=catalog.environment_frame_info(item)
  check(info.has("shore_geometry") and not info.has("texture"),"shore geometry bypasses sprite batching")
  var form:Dictionary=item["shore_form"]
  for weight in form["marine_weights"]:check(weight>=0.0 and weight<=1.0,"sea and river profiles blend within a bounded range")
  for i in range(form["points"].size()):
   var point:Vector2=form["points"][i]
   var normal:Vector2=form["normals"][i]
   # At saddle corners the terrain's snapped weights can jump over 0.5.
   # Require the two sides to straddle the visible contour within half a
   # 16x16 terrain mesh step, rather than require an unattainable scalar.
   var river:Dictionary=data.get("rivers",{}).get("surface",{})
   check(Terrain.surface_land_coverage(point-normal*0.03125,provider,river)<=0.5 and Terrain.surface_land_coverage(point+normal*0.03125,provider,river)>=0.5,"authored waterline straddles the actual rendered coast")
  for normal in form["normals"]:check(normal.is_finite() and normal.length()>0.99,"each ribbon faces from water toward land")
  var mesh:=Presentation._mesh(item)
  check(mesh.get_surface_count()==1,"every published ribbon has a drawable surface")
  if mesh.get_surface_count()==0:continue
  var arrays:=mesh.surface_get_arrays(0)
  for point in arrays[Mesh.ARRAY_VERTEX]:check(point.is_finite(),"shore mesh contains finite positions")
  var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
  for uv in uvs:check(uv.x>=-0.00001 and uv.x<=1.00001 and uv.y>=0 and uv.y<=1,"shore UVs never clamp beyond the native strip")
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  for i in range(0,indices.size(),3):
   var lo:=minf(uvs[indices[i]].x,minf(uvs[indices[i+1]].x,uvs[indices[i+2]].x))
   var hi:=maxf(uvs[indices[i]].x,maxf(uvs[indices[i+1]].x,uvs[indices[i+2]].x))
   check(hi-lo<0.20,"no triangle interpolates across a native texture repeat seam")
  for profile in range(2):check(Presentation._mesh(item,profile).get_surface_count()==1,"both native shore profiles use the same continuous geometry")
func check(value:bool,message:String) -> void:
 if not value and not failures.has(message):failures.append(message)

func _cache_reuse() -> void:
 var data:Dictionary=Examples.build("bend")["map_data"]
 Features.decorate(data)
 var template:Dictionary=data["scenery"][0]
 var canvas:=Node2D.new()
 var features:Array=[]
 var original:Array=[]
 Presentation.begin_frame(canvas)
 for i in range(Presentation.MAX_CACHED_MESHES+1):
  var feature:Dictionary=template.duplicate(true)
  feature["position"]+=Vector2(i*0.1,0)
  features.append(feature)
  original.append(Presentation.retained_mesh(canvas,feature,0))
 Presentation.meshes.clear()
 Presentation.begin_frame(canvas)
 for i in range(features.size()):check(is_same(original[i],Presentation.retained_mesh(canvas,features[i],0)),"an overview reuses visible meshes after shared-cache eviction")
 check(Presentation.meshes.size()<=Presentation.MAX_CACHED_MESHES,"shared shore cache stays bounded")
 canvas.free()
